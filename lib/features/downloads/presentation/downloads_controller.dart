import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/shared/utils/notification_service.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

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
    if (_systemController.state == SystemState.ready) {
      _onSystemStateChanged();
    }
  }

  // ==========================================================================
  // REACTIVIDAD AL ESTADO DEL SISTEMA
  // ==========================================================================
  void _onSystemStateChanged() {
    if (_systemController.state == SystemState.ready) {
      // 1. El backend ya levantó (Puerto real disponible). Traemos los datos de BD.
      _init().then((_) {
        // 2. AHORA SÍ nos suscribimos (porque _downloads ya no está vacío)
        _startGlobalSubscription();
        // 3. Enviamos a procesar todo lo que el usuario encoló
        flushPendingQueue();
      });
    } else {
      // Si el backend se cae, cortamos la escucha limpia y pacíficamente.
      _stopGlobalSubscription();
    }
  }

  void _startGlobalSubscription() {
    if (_globalSseSubscription != null) return;

    _globalSseSubscription = _repository.watchGlobalProgress().listen(
      _applyGlobalDeltas,
      onError: (e) {
        debugPrint('⚠️ Error SSE Global (Ignorado, esperando al Watchdog): $e');
      },
      cancelOnError: false,
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
    // Bloqueo de seguridad: Evita peticiones si Python no está listo
    if (_systemController.state != SystemState.ready) return;
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
    }
  }

  Future<void> addDownload(String url, Map<String, dynamic> options) async {
    if (url.trim().isEmpty) return;

    if (_systemController.state != SystemState.ready) {
      debugPrint('Backend no está listo. Encolando descarga...');
      _pendingQueue.add({"url": url, "options": options});
      return;
    }

    try {
      await _repository.addDownload(url, options: options);
      await _init();
    } catch (e) {
      debugPrint('Error al agregar descarga: $e');
    }
  }

  // --- NUEVO: Motor de Acciones (Gestos) ---
  Future<void> sendAction(String id, String action) async {
    try {
      // Nota: Asegúrate de tener implementado updateDownload en tu DownloadRepository
      // que apunte a client.updateDownload(id: id, action: action);
      // TODO: implementar la acción
      // await _repository.updateDownload(id, action);

      if (action == 'delete') {
        // Borrado UI inmediato para que se sienta rápido
        _downloads.removeWhere((d) => d.id == id);
        notifyListeners();
        ToastUtils.showInfo('Descarga eliminada');
      }
    } catch (e) {
      ToastUtils.showError('Error enviando acción: $e');
    }
  }

  Future<void> flushPendingQueue() async {
    if (_pendingQueue.isEmpty) return;
    final queueCopy = List<Map<String, dynamic>>.from(_pendingQueue);
    _pendingQueue.clear();
    for (var item in queueCopy) {
      try {
        await _repository.addDownload(item["url"], options: item["options"]);
      } catch (e) {
        debugPrint('Error procesando elemento encolado: $e');
      }
    }
    await _init();
  }

  void _triggerImageCache(String? id, String? url) async {
    if (id == null ||
        url == null ||
        url.isEmpty ||
        _imageCache.containsKey(id)) {
      return;
    }

    _imageCache[id] = '';

    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      _imageCache[id] = file.path;
    } catch (e) {
      _imageCache.remove(id);
      debugPrint('Error precargando miniatura para notificaciones: $e');
    }
  }

  void _applyGlobalDeltas(List<Delta> deltas) {
    bool listChanged = false;

    for (var delta in deltas) {
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

      String body = '$title\n$durationStr$platform';
      if (download.state?.subState != null) {
        body += '\n${download.state!.subState}';
      }

      final currentImagePath =
          _imageCache[download.id] != null &&
              _imageCache[download.id]!.isNotEmpty
          ? _imageCache[download.id]
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
          _imageCache.remove(download.id);
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
