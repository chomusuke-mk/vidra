import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';

class DownloadDetailController extends ChangeNotifier {
  final DownloadRepository _repository;
  final Download download;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // --- ESTADO PARA LOS LOGS ---
  String _logs = '';
  String get logs => _logs;

  bool _isLoadingLogs = false;
  bool get isLoadingLogs => _isLoadingLogs;

  StreamSubscription? _detailSseSubscription;

  DownloadDetailController(this._repository, this.download) {
    _initSequence();
  }

  Future<void> _initSequence() async {
    // 1. Mostrar estado de carga
    _isLoading = true;
    notifyListeners();

    try {
      // 2. Traer la última verdad absoluta desde el servidor
      final freshDownload = await _repository.getDownloadById(download.id!);

      if (freshDownload != null) {
        // Actualizamos la referencia en memoria con los últimos datos,
        // especialmente las sub-descargas que la pantalla principal ignoraba.
        download.info = freshDownload.info ?? download.info;
        download.state = freshDownload.state ?? download.state;
        download.subDownloads = freshDownload.subDownloads ?? [];
        download.options = freshDownload.options ?? download.options;
      }
      await fetchLogs();
    } catch (e) {
      debugPrint('Error sincronizando detalle: $e');
    } finally {
      // 3. Quitar el loading para renderizar la pantalla
      _isLoading = false;
      notifyListeners();

      // 4. Iniciar la escucha de deltas sobre los datos ya actualizados
      _startDetailSubscription();
    }
  }

  Future<void> fetchLogs() async {
    _isLoadingLogs = true;
    notifyListeners();
    try {
      // ponytail: Asegúrate de que el repositorio tenga este método implementado.
      _logs = await _repository.fetchLogs(download.id!);
    } catch (e) {
      _logs = 'Error obteniendo logs:\n$e';
    } finally {
      _isLoadingLogs = false;
      notifyListeners();
    }
  }

  void _startDetailSubscription() {
    _detailSseSubscription = _repository
        .watchDetailedProgress(download.id!)
        .listen(
          _applySubDeltas,
          onError: (e) => debugPrint('Error SSE Detalle: $e'),
        );
  }

  void _applySubDeltas(List<Delta> deltas) {
    bool changed = false;

    for (var delta in deltas) {
      if (delta.subId == null) {
        continue; // Solo nos interesan los sub-deltas aquí
      }

      download.subDownloads ??= [];

      final subIndex = download.subDownloads!.indexWhere(
        (s) => s.subId == delta.subId,
      );

      if (subIndex != -1) {
        // ACTUALIZAR: El subId ya existe
        final sub = download.subDownloads![subIndex];
        if (delta.status != null) sub.state = delta.status;
        if (delta.info != null) sub.info = delta.info;
      } else {
        // CREAR: Llega un sub_id desconocido (ej. el backend descubrió un nuevo elemento en la playlist)
        download.subDownloads!.add(
          SubDownload(
            subId: delta.subId,
            parentId: delta.id, // o download.id
            state: delta.status,
            info: delta.info,
          ),
        );
      }
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _detailSseSubscription?.cancel();
    super.dispose();
  }
}
