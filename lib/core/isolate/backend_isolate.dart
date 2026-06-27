import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
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
  final bool isAndroid = config['isAndroid'];

  // 2. Inicializamos el entorno para que los canales nativos funcionen en background
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.init();

  debugPrint('🧠 [Isolate] Iniciado correctamente en segundo plano.');

  // 3. Variables de estado locales
  String state = 'initializing';
  bool isUpdating = false;
  Timer? healthCheckTimer;
  int failedPings = 0;
  String? pythonAppPath;

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
      bool overlayGranted = await FlutterOverlayWindow.isPermissionGranted();
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

  void startGlobalSubscription() {
    sseSubscription?.cancel();
    sseSubscription = httpClient.subscribeToDeltas().listen(
      (jsonList) async {
        final deltas = jsonList
            .map((json) => Delta.fromJson(json as Map<String, dynamic>))
            .toList();
        bool needsRefresh = false;

        for (var delta in deltas) {
          if (delta.subId != null || delta.id == null) {
            continue; // Ignoramos sub-descargas para notificaciones globales
          }

          final downloadIndex = cachedDownloads.indexWhere(
            (d) => d.id == delta.id,
          );

          // Si no tenemos este ID en caché, marcamos para refrescar la lista completa en un momento
          if (downloadIndex == -1) {
            needsRefresh = true;
            continue;
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
          final autor = download.info?.autor ?? 'Desconocido';
          final title = download.info?.title ?? 'Procesando...';
          final durationStr = download.info?.duration != null
              ? '${download.info?.duration} • '
              : '';
          final platform = download.info?.platform ?? '';

          String body = '$title\n$durationStr$platform';
          if (delta.status?.subState != null) {
            body += '\n${delta.status!.subState}';
          }

          if (delta.info?.image != null) {
            triggerImageCache(delta.id!, delta.info!.image!);
          }
          final currentImagePath =
              imageCache[download.id] != null &&
                  imageCache[download.id]!.isNotEmpty
              ? imageCache[download.id]
              : null;

          if (newState == DownloadState.inProgress) {
            final progress = (download.state?.progressValue ?? 0).toInt();
            NotificationService.showProgress(
              id: notificationId,
              title: autor,
              body: '${download.state?.progressLabel ?? ''}\n$body',
              progress: progress,
              maxProgress: 100,
              imagePath: currentImagePath,
            );
          } else if (oldState != newState) {
            // Transiciones de Estado
            if (newState == DownloadState.identifying) {
              NotificationService.showState(
                id: notificationId,
                title: autor,
                body: 'Identificando: $title',
                imagePath: currentImagePath,
              );
            } else if (newState == DownloadState.waitForSelection) {
              NotificationService.showState(
                id: notificationId,
                title: autor,
                body: 'Esperando selección: $title',
                imagePath: currentImagePath,
              );
            } else if (newState == DownloadState.completed &&
                oldState == DownloadState.inProgress) {
              NotificationService.showState(
                id: notificationId,
                title: autor,
                body: '¡Descarga completada!\n$title',
                imagePath: currentImagePath,
              );
            } else if (newState == DownloadState.failed) {
              NotificationService.showState(
                id: notificationId,
                title: autor,
                body:
                    'Error: ${download.state?.subState ?? "Desconocido"}\n$title',
                isError: true,
                imagePath: currentImagePath,
              );
            } else if (newState == DownloadState.canceled ||
                newState == DownloadState.deleted) {
              NotificationService.cancel(notificationId);
              imageCache.remove(download.id);
            }
          }
        }
        // Si llegó un ID desconocido, refrescamos la caché.
        if (needsRefresh) {
          await refreshDownloadsCache();
        }

        // Verificar si hay trabajo activo para mantener la app despierta
        final isWorking =
            pendingQueue.isNotEmpty ||
            cachedDownloads.any(
              (d) =>
                  d.state?.value == DownloadState.inProgress ||
                  d.state?.value == DownloadState.identifying ||
                  d.state?.value == DownloadState.pending,
            );

        if (isWorking) {
          NotificationService.keepAppAlive();
        } else {
          NotificationService.letAppSleep();
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

      // 1. Replicamos la magia de SeriousPython.run():
      // Asignar el directorio actual a la carpeta "data" de la app
      final dataDir = Directory(p.join(supportDirPath, "data"));
      if (!dataDir.existsSync()) {
        dataDir.createSync(recursive: true);
      }
      Directory.current = dataDir.path;

      // 2. Unimos la ruta que nos mandó la UI con el archivo de entrada
      // (Si tu compilación genera un main.pyc en el futuro, puedes agregar la lógica de File().exists() aquí)
      final fullAppPath = p.join(pythonAppPath!, "main.py");

      debugPrint('🧠 [Isolate] Lanzando SeriousPython en Puerto: $backendPort');
      debugPrint('🧠 [Isolate] FFMPEG_PATH: $ffmpegPath');
      debugPrint('🧠 [Isolate] QUICKJS_PATH: $quickjsPath');

      // 3. Lanzamos directo con runProgram
      SeriousPython.runProgram(
        fullAppPath,
        environmentVariables: {
          'APP_ENV': 'production',
          'API_TOKEN': backendToken,
          'LOGS_PATH': p.join(supportDirPath, 'logs'),
          'DATA_PATH': p.join(supportDirPath, 'data'),
          'TEMP_PATH': p.join(supportDirPath, 'temp'),
          'HOST': '127.0.0.1',
          'PORT': backendPort.toString(),
          'SERVER_LOGS_FILE_PATH': p.join(supportDirPath, 'logs', 'server.log'),
          'FFMPEG_PATH': ffmpegPath,
          'QUICKJS_PATH': quickjsPath,
        },
        sync: false,
        modulePaths: [p.join(supportDirPath, 'core_modules')],
      );
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
          // LA MAGIA OCURRE AQUÍ: Apenas el backend vive, pedimos toda la info.
          await refreshDownloadsCache();
          startGlobalSubscription();
          processDownloadQueue();
        }
      } else {
        failedPings++;
        debugPrint(
          '🧠 [Isolate] Python no responde. Intento ($failedPings/10)',
        );
        notifyUiState('retrying');

        if (failedPings >= 10) {
          debugPrint('🧠 [Isolate] Resurrección de Python activada...');
          failedPings = 0;
          notifyUiState('startingBackend');
          if (!await startPythonBackend()) notifyUiState('fatalError');
        }
      }
    });
  }

  // --- Secuencia Maestra de Arranque ---
  Future<void> initSequence() async {
    if (isUpdating) return;
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

    notifyUiState('startingBackend');
    if (!await startPythonBackend()) {
      notifyUiState('fatalError');
      return;
    }

    startHealthCheck();
  }

  // ==========================================================================
  // ESCUCHA DE COMANDOS DESDE LA UI
  // ==========================================================================
  final ReceivePort receivePort = ReceivePort();
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
          await initSequence();
          break;

        case 'pause_for_update':
          isUpdating = true;
          healthCheckTimer?.cancel();
          sseSubscription?.cancel();
          await httpClient.shutdown();
          notifyUiState('initializing');
          SeriousPython.terminate();
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
