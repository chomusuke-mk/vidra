import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/shared/utils/notification_service.dart';

class DownloadsController extends ChangeNotifier {
  final DownloadRepository _repository;

  List<Download> _downloads = [];
  List<Download> get downloads => _downloads;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  StreamSubscription? _globalSseSubscription;

  final Map<String, String> _imageCache = {};

  DownloadsController(this._repository) {
    _init();
  }

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
      _manageGlobalSubscription();
    }
  }

  Future<void> addDownload(String url, Map<String, dynamic> options) async {
    if (url.trim().isEmpty) return;
    try {
      await _repository.addDownload(url, options: options);
      await _init();
    } catch (e) {
      debugPrint('Error al agregar descarga: $e');
    }
  }

  bool _hasActiveDownloads() {
    return _downloads.any((d) {
      final state = d.state?.value;
      return state == DownloadState.requested ||
          state == DownloadState.pending ||
          state == DownloadState.identifying ||
          state == DownloadState.waitForSelection ||
          state == DownloadState.inProgress;
    });
  }

  void _manageGlobalSubscription() {
    final hasActive = _hasActiveDownloads();

    if (hasActive && _globalSseSubscription == null) {
      _globalSseSubscription = _repository.watchGlobalProgress().listen(
        _applyGlobalDeltas,
        onError: (e) => debugPrint('Error SSE Global: $e'),
      );
    } else if (!hasActive && _globalSseSubscription != null) {
      _globalSseSubscription?.cancel();
      _globalSseSubscription = null;
    }
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
      _manageGlobalSubscription();
    }
  }

  @override
  void dispose() {
    _globalSseSubscription?.cancel();
    super.dispose();
  }
}
