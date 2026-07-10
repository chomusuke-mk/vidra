import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_screen_overlay/flutter_screen_overlay.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:serious_python/serious_python.dart';

import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/shared/utils/notification_service.dart';

// ============================================================================
// PUNTO DE ENTRADA DEL ISOLATE DEL BACKEND (EL "CEREBRO" EN SEGUNDO PLANO)
// ============================================================================
@pragma('vm:entry-point')
void backendIsolateMain(Map<String, dynamic> config) async {
  // 1. Extraemos la configuración enviada por la UI
  final RootIsolateToken rootToken = config['rootToken'];
  final SendPort sendPort = config['sendPort'];
  final int backendPort = config['backendPort'];
  final String backendToken = config['backendToken'];
  final String supportDirPath = config['supportDirPath'];
  final String tempDirPath = config['tempDirPath'];
  final String serverLogsFilePath = config['serverLogsFilePath'];
  final bool isAndroid = config['isAndroid'];

  // 2. Inicializamos el entorno para que los canales nativos funcionen en background
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  DartPluginRegistrant.ensureInitialized();
  if (!Platform.isAndroid) {
    try {
      await NotificationService.init();
    } catch (e) {
      debugPrint(
        '🧠 [Isolate] Posible error inicializando NotificationService: $e',
      );
    }
  }
  try {
    await NotificationService.keepAppAlive();
    debugPrint('🧠 [Isolate] Keep notification iniciada correctamente.');
  } catch (e) {
    debugPrint('🧠 [Isolate] Posible error iniciando keep notification: $e');
  }

  debugPrint('🧠 [Isolate] Iniciado correctamente en segundo plano.');

  // 3. Variables de estado locales
  String state = 'initializing';
  bool isUpdating = false;
  bool isInitializing = false;
  bool isBackendRunning = false;
  Timer? healthCheckTimer;
  int failedPings = 0;
  String? pythonAppPath;
  Future<void>? cacheRefreshFuture;

  // Cola de descargas
  final List<Map<String, dynamic>> pendingQueue = [];
  StreamSubscription? sseSubscription;
  final Map<String, String> imageCache = {};

  // --- CACHÉ DE DESCARGAS (Memoria del Isolate) ---
  List<Download> cachedDownloads = [];

  // Cliente HTTP local para hablar con Python
  final httpClient = VidraHttpClient(
    baseUrl: 'http://127.0.0.1:$backendPort',
    defaultHeaders: {},
    token: backendToken,
    timeout: const Duration(seconds: 30),
  );

  // --- Funciones de comunicación hacia la UI ---
  void notifyUiState(String newState) {
    if (state != newState) {
      state = newState;
      sendPort.send({'event': 'state', 'value': state});
      debugPrint('🧠 [Isolate] Cambio de estado notificado a UI: $state');
    }
  }

  // --- Validación de Recursos (Copia adaptada del SystemController) ---
  bool checkResources() {
    try {
      final ytDlpDir = Directory(
        p.join(supportDirPath, 'core_modules', 'yt_dlp'),
      );
      final ejsDir = Directory(
        p.join(supportDirPath, 'core_modules', 'yt_dlp_ejs'),
      );
      if (!ytDlpDir.existsSync() || ytDlpDir.listSync().isEmpty) return false;
      if (!ejsDir.existsSync() || ejsDir.listSync().isEmpty) return false;
      return true;
    } catch (e) {
      debugPrint('🧠 [Isolate] Error comprobando recursos: $e');
      return false;
    }
  }

  // --- Validación de Permisos (Copia adaptada del SystemController) ---
  Future<bool> checkPermissions() async {
    if (!isAndroid) return true;
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      bool storageGranted = androidInfo.version.sdkInt >= 30
          ? await Permission.manageExternalStorage.isGranted
          : await Permission.storage.isGranted;
      bool overlayGranted = await FlutterScreenOverlay.isPermissionGranted();
      bool notifGranted = androidInfo.version.sdkInt >= 33
          ? await Permission.notification.isGranted
          : true;
      bool batteryGranted =
          await Permission.ignoreBatteryOptimizations.isGranted;
      return storageGranted && overlayGranted && notifGranted && batteryGranted;
    } catch (e) {
      debugPrint('🧠 [Isolate] Error comprobando permisos: $e');
      return false;
    }
  }

  // --- Resolutor de Rutas de FFmpeg y QuickJS (Sin bloquear la UI) ---
  Future<String> resolveExecutable(String baseName) async {
    if (isAndroid) {
      try {
        const platform = MethodChannel('vidra_channel');
        final nativeLibDir = await platform.invokeMethod<String>(
          'getNativeLibDir',
        );
        return p.join(nativeLibDir ?? '', 'lib$baseName.so');
      } catch (e) {
        debugPrint(
          '🧠 [Isolate] Fallo al obtener NativeLibDir para $baseName: $e',
        );
        return 'lib$baseName.so';
      }
    } else {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final ext = Platform.isWindows ? '.exe' : '';
      return p.join(exeDir, '$baseName$ext');
    }
  }

  // --- Reactividad SSE, Caché de Imágenes y Merging de Deltas ---
  void triggerImageCache(String id, String url) async {
    if (url.isEmpty || imageCache.containsKey(id)) return;
    imageCache[id] = '';
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      imageCache[id] = file.path;
    } catch (e) {
      imageCache.remove(id);
    }
  }

  /// Refresca la lista completa de descargas (Se llama al iniciar o si llega un delta de un ID nuevo)
  Future<void> refreshDownloadsCache() async {
    try {
      final data = await httpClient.getDownloads();
      if (data is List) {
        cachedDownloads = data.map((e) => Download.fromJson(e)).toList();
        for (var d in cachedDownloads) {
          if (d.info?.image != null) triggerImageCache(d.id!, d.info!.image!);
        }
      }
    } catch (e) {
      debugPrint('🧠 [Isolate] Error refrescando caché: $e');
    }
  }

  // Nueva función segura para refrescar
  Future<void> refreshCacheSafe() {
    // Si ya hay un refresco en curso, devuelve ese mismo Future (no hace llamadas HTTP extra)
    cacheRefreshFuture ??= refreshDownloadsCache().whenComplete(() {
      cacheRefreshFuture = null;
    });
    return cacheRefreshFuture!;
  }

  void startGlobalSubscription() {
    sseSubscription?.cancel();
    sseSubscription = httpClient.subscribeToDeltas().listen(
      (jsonList) async {
        final deltas = jsonList
            .map((json) => Delta.fromJson(json as Map<String, dynamic>))
            .toList();

        for (var delta in deltas) {
          if (delta.subId != null || delta.id == null) continue;

          var downloadIndex = cachedDownloads.indexWhere(
            (d) => d.id == delta.id,
          );

          // Si no tenemos este ID en caché, marcamos para refrescar la lista completa en un momento
          if (downloadIndex == -1) {
            await refreshCacheSafe();
            downloadIndex = cachedDownloads.indexWhere((d) => d.id == delta.id);

            // Si después del refetch AÚN no existe, entonces lo ignoramos.
            if (downloadIndex == -1) continue;
          }

          final download = cachedDownloads[downloadIndex];
          final oldState = download.state?.value;

          // FUSIONAMOS LOS CAMBIOS PARCIALES DEL DELTA AL OBJETO COMPLETO EN CACHÉ
          if (delta.status != null) download.state = delta.status;
          if (delta.info != null) {
            download.info = delta.info;
            if (download.info?.image != null) {
              triggerImageCache(download.id!, download.info!.image!);
            }
          }

          // CALCULAMOS NOTIFICACIONES BASADO EN LA FUSIÓN
          final newState = download.state?.value;
          final notificationId = download.id.hashCode;
          final autor = download.info?.autor ?? 'Unknown';
          final title = download.info?.title ?? 'Processing...';

          String body = title;
          if (download.state?.subState != null) {
            body += '\n${download.state!.subState}';
          }
          final Color? color = download.state?.subStateColor?.color;

          final currentImagePath =
              imageCache[download.id] != null &&
                  imageCache[download.id]!.isNotEmpty
              ? imageCache[download.id]
              : null;

          if (newState == DownloadStateEnum.inProgress) {
            final progress = download.state?.progressValue != null
                ? (download.state!.progressValue! * 100).toInt()
                : null;
            final progressLabel = download.state?.progressLabel;
            NotificationService.showProgress(
              id: notificationId,
              title: autor,
              body: body,
              progress: progress,
              maxProgress: 100,
              imagePath: currentImagePath,
              progressLabel: progressLabel,
              color: color,
            );
          } else if (oldState != newState) {
            if (newState == DownloadStateEnum.extractingInformation) {
              NotificationService.showState(
                id: notificationId,
                title: autor,
                body: '${newState?.humanReadable}\n$title',
                imagePath: currentImagePath,
                color: color,
              );
            } else if (newState == DownloadStateEnum.awaitingSelection) {
              NotificationService.showState(
                id: notificationId,
                title: autor,
                body: '${newState?.humanReadable}\n$title',
                imagePath: currentImagePath,
                color: color,
              );
            } else if (newState == DownloadStateEnum.completed &&
                oldState == DownloadStateEnum.inProgress) {
              NotificationService.showState(
                id: notificationId,
                title: autor,
                body: '${newState?.humanReadable}\n$title',
                imagePath: currentImagePath,
                color: color,
              );
            } else if (newState == DownloadStateEnum.failed) {
              NotificationService.showState(
                id: notificationId,
                title: autor,
                body:
                    'Error: ${download.state?.subState ?? "Desconocido"}\n$title',
                isError: true,
                imagePath: currentImagePath,
                color: color,
              );
            } else if (newState == DownloadStateEnum.cancelled ||
                newState == DownloadStateEnum.deleted) {
              NotificationService.cancel(notificationId);
              imageCache.remove(download.id);
            }
          }
        }
      },
      onError: (e) {
        debugPrint('🧠 [Isolate] Error en SSE: $e');
      },
    );
  }

  // --- Gestión de la Cola de Descargas ---
  void processDownloadQueue() async {
    if (pendingQueue.isEmpty || state != 'ready') return;

    final queueCopy = List<Map<String, dynamic>>.from(pendingQueue);
    pendingQueue.clear();

    for (var item in queueCopy) {
      try {
        debugPrint('🧠 [Isolate] Enviando descarga de la cola: ${item["url"]}');
        await httpClient.addDownload(
          url: item["url"],
          options: item["options"],
        );
        await refreshDownloadsCache(); // Actualizamos la memoria
      } catch (e) {
        debugPrint('🧠 [Isolate] Error procesando cola: $e');
      }
    }
  }

  // --- Arranque del Backend ---
  Future<bool> startPythonBackend() async {
    try {
      final ffmpegPath = await resolveExecutable('ffmpeg');
      final quickjsPath = await resolveExecutable('quickjs');
      final coreModulesPath = p.join(supportDirPath, 'core_modules');

      // ========================================================
      // Lógica para que funcione serious_python
      final dataDir = Directory(p.join(supportDirPath, "data"));
      if (!dataDir.existsSync()) {
        dataDir.createSync(recursive: true);
      }
      Directory.current = dataDir.path;
      final fullAppPath = p.join(pythonAppPath!, "main.py");
      // ========================================================

      debugPrint('🧠 [Isolate] Lanzando SeriousPython en Puerto: $backendPort');
      debugPrint('🧠 [Isolate] FFMPEG_PATH: $ffmpegPath');
      debugPrint('🧠 [Isolate] QUICKJS_PATH: $quickjsPath');
      debugPrint('🧠 [Isolate] CORE_MODULES: $coreModulesPath');

      // 3. Lanzamos directo con runProgram
      SeriousPython.runProgram(
        fullAppPath,
        environmentVariables: {
          'APP_ENV': 'production',
          'API_TOKEN': backendToken,
          'LOGS_PATH': p.join(tempDirPath, 'vidra_backend', 'logs'),
          'DATA_PATH': p.join(supportDirPath, 'vidra_backend', 'data'),
          'TEMP_PATH': p.join(tempDirPath, 'vidra_backend', 'temp'),
          'HOST': '127.0.0.1',
          'PORT': backendPort.toString(),
          'SERVER_LOGS_FILE_PATH': serverLogsFilePath,
          'FFMPEG_PATH': ffmpegPath,
          'QUICKJS_PATH': quickjsPath,
        },
        sync: false,
        modulePaths: [coreModulesPath],
      ).catchError((e) {
        debugPrint('🧠 [Isolate] Error lanzando SeriousPython: $e');
        return "error";
      });
      return true;
    } catch (e) {
      debugPrint('🧠 [Isolate] Error fatal ejecutando Python: $e');
      return false;
    }
  }

  // --- Watchdog Inmortal ---
  void startHealthCheck() {
    healthCheckTimer?.cancel();
    failedPings = 0;

    healthCheckTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (isUpdating) return;
      final isAlive = await httpClient.healthCheck();

      if (isAlive) {
        if (state != 'ready') {
          failedPings = 0;
          notifyUiState('ready');
          await refreshDownloadsCache();
          startGlobalSubscription();
          processDownloadQueue();
        }
      } else {
        failedPings++;
        debugPrint(
          '🧠 [Isolate] Python no responde. Intento ($failedPings/30)',
        );
        notifyUiState('retrying');

        if (failedPings >= 30) {
          debugPrint('🧠 [Isolate] Resurrección de Python activada...');
          SeriousPython.terminate();
          isBackendRunning = false;
          failedPings = 0;
          notifyUiState('startingBackend');
          if (!await startPythonBackend()) {
            notifyUiState('fatalError');
          } else {
            isBackendRunning = true;
          }
        }
      }
    });
  }

  // --- Secuencia Maestra de Arranque ---
  Future<void> initSequence() async {
    // AÑADIDO: Evitamos que dos flujos inicialicen al mismo tiempo
    if (isUpdating || isInitializing) return;
    isInitializing = true;
    try {
      notifyUiState('initializing');

      debugPrint('🧠 [Isolate] Comprobando permisos...');
      if (!await checkPermissions()) {
        notifyUiState('missingPermissions');
        NotificationService.showState(
          id: 9991,
          title: 'Acción Requerida',
          body: 'Faltan permisos críticos para ejecutar Vidra.',
          isError: true,
        );
        return;
      }

      debugPrint('🧠 [Isolate] Comprobando recursos...');
      if (!checkResources()) {
        notifyUiState('missingResources');
        NotificationService.showState(
          id: 9992,
          title: 'Acción Requerida',
          body: 'Faltan componentes. Abre la app para descargar.',
          isError: true,
        );
        return;
      }

      // NUEVO: El guardián de la extracción
      if (pythonAppPath == null) {
        debugPrint(
          '🧠 [Isolate] Permisos OK. Esperando a que la UI termine de extraer Python...',
        );
        notifyUiState('unpacking');
        return; // Cortamos el flujo aquí. Se retomará cuando llegue el mensaje por IPC.
      }

      // AÑADIDO: Cortafuegos final. Si ya está corriendo, no lo vuelvas a lanzar.
      if (isBackendRunning) {
        debugPrint(
          '🧠 [Isolate] El backend ya está corriendo, ignorando petición.',
        );
        return;
      }

      notifyUiState('startingBackend');
      if (!await startPythonBackend()) {
        notifyUiState('fatalError');
        return;
      }
      isBackendRunning = true;
      startHealthCheck();
    } finally {
      isInitializing = false;
    }
  }

  // ==========================================================================
  // ESCUCHA DE COMANDOS DESDE LA UI
  // ==========================================================================
  final ReceivePort receivePort = ReceivePort();
  IsolateNameServer.removePortNameMapping('vidra_backend_port');
  IsolateNameServer.registerPortWithName(
    receivePort.sendPort,
    'vidra_backend_port',
  );
  sendPort.send({'event': 'port', 'value': receivePort.sendPort});

  receivePort.listen((message) async {
    if (message is Map<String, dynamic>) {
      final cmd = message['cmd'];
      debugPrint('🧠 [Isolate] Comando recibido desde UI: $cmd');

      switch (cmd) {
        // NUEVO COMANDO
        case 'python_prepared':
          pythonAppPath = message['path'];
          debugPrint('🧠 [Isolate] Ruta de Python recibida desde la UI.');
          await initSequence(); // Retomamos la secuencia de arranque
          break;

        case 'revalidate':
          isUpdating = false;
          await initSequence();
          break;

        case 'pause_for_update':
          isUpdating = true;
          healthCheckTimer?.cancel();
          sseSubscription?.cancel();
          await httpClient.shutdown();
          notifyUiState('initializing');
          SeriousPython.terminate();
          isBackendRunning = false;
          sendPort.send({'event': 'paused_ack'});
          break;

        case 'download':
          final String url = message['url'];
          final Map<String, dynamic> options = message['options'];
          if (state == 'ready') {
            try {
              await httpClient.addDownload(url: url, options: options);
              await refreshDownloadsCache(); // Refrescar caché tras encolar localmente
            } catch (e) {
              debugPrint('🧠 [Isolate] Error mandando descarga directa: $e');
            }
          } else {
            debugPrint('🧠 [Isolate] Backend no listo, encolando descarga.');
            pendingQueue.add({"url": url, "options": options});
          }
          break;
      }
    }
  });

  await initSequence();
}
