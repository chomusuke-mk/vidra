import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/shared/utils/notification_service.dart';

class DownloadsController extends ChangeNotifier {
  final DownloadRepository _repository;
  final SystemController _systemController; // <-- Inyección del Cerebro
  
  final List<Map<String, dynamic>> _pendingQueue = [];

  List<Download> _downloads = [];
  List<Download> get downloads => _downloads;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  StreamSubscription? _globalSseSubscription;

  final Map<String, String> _imageCache = {};

  DownloadsController(this._repository, this._systemController) {
    _systemController.addListener(_onSystemStateChanged);
    _init();
  }

  // ==========================================================================
  // REACTIVIDAD AL ESTADO DEL SISTEMA
  // ==========================================================================
  void _onSystemStateChanged() {
    if (_systemController.state == SystemState.ready) {
      flushPendingQueue();
      _startGlobalSubscription();
    } else {
      // Si el backend se cae (retrying, fatalError, etc), cortamos la escucha limpia y pacíficamente.
      _stopGlobalSubscription();
    }
  }

  void _startGlobalSubscription() {
    if (_globalSseSubscription != null) return; // Ya estamos conectados

    _globalSseSubscription = _repository.watchGlobalProgress().listen(
      _applyGlobalDeltas,
      onError: (e) {
        debugPrint('⚠️ Error SSE Global (Ignorado, esperando al Watchdog): $e');
        // No cancelamos manualmente aquí. El SystemController (Watchdog)
        // se dará cuenta de que el backend cayó, cambiará el estado a 'retrying',
        // y eso disparará _stopGlobalSubscription() automáticamente.
      },
      cancelOnError:
          false, // ¡MAGIA! Evita que el Stream muera y crashee la app si se corta el socket.
    );
  }

  void _stopGlobalSubscription() {
    _globalSseSubscription?.cancel();
    _globalSseSubscription = null;
  }

  // ==========================================================================
  // CORE LOGIC
  // ==========================================================================
  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    try {
      _downloads = await _repository.getAllDownloads();
      for (var d in _downloads) {
        _triggerImageCache(d.id, d.info?.image);
      }
    } catch (e) {
      debugPrint('Error cargando descargas: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      // Si justo arrancamos y el sistema ya estaba listo, nos conectamos.
      if (_systemController.state == SystemState.ready) {
        _startGlobalSubscription();
      }
    }
  }

  Future<void> addDownload(
    String url,
    Map<String, dynamic> options, {
    bool isBackendReady = false,
  }) async {
    if (url.trim().isEmpty) return;

    // Si el backend aún no está en estado "SystemState.ready"
    if (!isBackendReady) {
      debugPrint('Backend no está listo. Encolando descarga...');
      _pendingQueue.add({"url": url, "options": options});
      // Aquí puedes lanzar un ToastUtils.showInfo('Preparando motor de descarga...');
      return;
    }

    try {
      await _repository.addDownload(url, options: options);
      await _init(); // Refresca la lista de descargas
    } catch (e) {
      debugPrint('Error al agregar descarga: $e');
    }
  }

  /// Nuevo método: Se llamará automáticamente cuando SystemController avise que está Ready
  Future<void> flushPendingQueue() async {
    if (_pendingQueue.isEmpty) return;

    debugPrint(
      'Vaciando cola de descargas pendientes (${_pendingQueue.length})...',
    );

    // Extraemos y limpiamos la cola inmediatamente para evitar duplicados
    final queueCopy = List<Map<String, dynamic>>.from(_pendingQueue);
    _pendingQueue.clear();

    for (var item in queueCopy) {
      try {
        await _repository.addDownload(item["url"], options: item["options"]);
      } catch (e) {
        debugPrint('Error procesando elemento encolado: $e');
      }
    }
    await _init(); // Sincronizamos la UI al final
  }

  /// Descarga y guarda en disco la imagen SIN bloquear el flujo de notificaciones
  void _triggerImageCache(String? id, String? url) async {
    if (id == null ||
        url == null ||
        url.isEmpty ||
        _imageCache.containsKey(id)) {
      return;
    }

    // Ponemos una bandera temporal para no lanzar 20 peticiones a la misma URL en lo que demora la descarga
    _imageCache[id] = '';

    try {
      // Utiliza la MISMA caché que CachedNetworkImage de tus tarjetas de UI
      final file = await DefaultCacheManager().getSingleFile(url);
      _imageCache[id] = file.path; // Actualizamos con la ruta real en disco
    } catch (e) {
      _imageCache.remove(
        id,
      ); // Si falla, quitamos la bandera para reintentar después
      debugPrint('Error precargando miniatura para notificaciones: $e');
    }
  }

  // Ahora solo procesamos reemplazos totales para el objeto Padre
  void _applyGlobalDeltas(List<Delta> deltas) {
    bool listChanged = false;

    for (var delta in deltas) {
      // Como regla, aquí no llegan deltas con subId, pero lo ignoramos por seguridad si llegara
      if (delta.subId != null) continue;

      final downloadIndex = _downloads.indexWhere((d) => d.id == delta.id);
      if (downloadIndex == -1) continue;

      final download = _downloads[downloadIndex];

      final oldState = download.state?.value;

      if (delta.status != null) download.state = delta.status;
      if (delta.info != null) {
        download.info = delta.info;
        _triggerImageCache(download.id, download.info?.image);
      }

      final newState = download.state?.value;
      final notificationId = download.id.hashCode;
      final autor = download.info?.autor ?? 'Desconocido';
      final title = download.info?.title ?? 'Procesando...';
      final durationStr = download.info?.duration != null
          ? '${download.info?.duration} • '
          : '';
      final platform = download.info?.platform ?? '';
      // Construimos el cuerpo multilinea
      String body = '$title\n$durationStr$platform';
      if (download.state?.subState != null) {
        body += '\n${download.state!.subState}';
      }

      // Si la imagen ya terminó de descargar, se pasará la ruta. Si no, irá null y en el próximo tick de 2 seg se adjuntará.
      final currentImagePath =
          _imageCache[download.id] != null &&
              _imageCache[download.id]!.isNotEmpty
          ? _imageCache[download.id]
          : null;

      // Disparador A: En progreso (Cada 2 segundos)
      if (newState == DownloadState.inProgress) {
        final progress = (download.state?.progressValue ?? 0).toInt();
        NotificationService.showProgress(
          id: notificationId,
          title: autor,
          body:
              '${download.state?.progressLabel ?? ''}\n$body', // Añadimos velocidad/label arriba
          progress: progress,
          maxProgress: 100, // Asumiendo que progressValue es un % de 0 a 100
          imagePath: currentImagePath,
        );
      }
      // Disparador B: Transiciones estáticas importantes
      else if (oldState != newState) {
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
            body: 'Error: ${download.state?.subState ?? "Desconocido"}\n$title',
            isError: true,
            imagePath: currentImagePath,
          );
        } else if (newState == DownloadState.canceled ||
            newState == DownloadState.deleted) {
          NotificationService.cancel(notificationId);
          _imageCache.remove(download.id); // Limpieza de memoria
        }
      }

      listChanged = true;
    }

    if (listChanged) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _systemController.removeListener(_onSystemStateChanged);
    _globalSseSubscription?.cancel();
    super.dispose();
  }
}
