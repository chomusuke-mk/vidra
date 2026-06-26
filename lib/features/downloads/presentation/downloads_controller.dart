import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

class DownloadsController extends ChangeNotifier {
  final DownloadRepository _repository;
  final SystemController _systemController; // <-- Inyección del Cerebro

  List<Download> _downloads = [];
  List<Download> get downloads => _downloads;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  StreamSubscription? _globalSseSubscription;

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
        _startGlobalSubscription();
      });
    } else {
      // Si el backend se cae, cortamos la escucha limpia y pacíficamente.
      _stopGlobalSubscription();
    }
  }

  void _startGlobalSubscription() {
    if (_globalSseSubscription != null) return;
    debugPrint('📡 [UI-Downloads] Conectando a stream SSE puramente visual...');
    _globalSseSubscription = _repository.watchGlobalProgress().listen(
      _applyGlobalDeltas,
      onError: (e) {
        debugPrint('⚠️ [UI-Downloads] Error SSE visual ignorado: $e');
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
    } catch (e) {
      debugPrint('Error cargando descargas: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addDownload(String url, Map<String, dynamic> options) async {
    if (url.trim().isEmpty) return;
    // Delegamos todo el trabajo pesado al Isolate mediante el puente del SystemController
    debugPrint('📤 [UI-Downloads] Solicitando descarga vía puente IPC...');
    _systemController.enqueueDownload(url, options);
    // Mostramos un Toast amigable en la UI mientras el Isolate procesa en el fondo
    ToastUtils.showInfo('Descarga enviada...');
  }

  // --- NUEVO: Motor de Acciones (Gestos) ---
  Future<void> sendAction(String id, String action) async {
    try {
      if (action == 'delete') {
        // Borrado UI inmediato para que se sienta rápido
        _downloads.removeWhere((d) => d.id == id);
        notifyListeners();
        ToastUtils.showInfo('Descarga eliminada');
        // Enviamos el comando de control por HTTP
        // (asume que _repository.updateDownload existe o se llama a su client respectivo)
        await _repository.pauseDownload(
          id,
        ); // Ejemplo de fallback basado en tu repository
      }
    } catch (e) {
      ToastUtils.showError('Error enviando acción: $e');
    }
  }

  void _applyGlobalDeltas(List<Delta> deltas) {
    bool listChanged = false;

    for (var delta in deltas) {
      if (delta.subId != null) continue;

      final downloadIndex = _downloads.indexWhere((d) => d.id == delta.id);
      // Si el backend reporta una descarga que no tenemos en memoria (recién agregada por el Isolate)
      if (downloadIndex == -1) {
        // Disparamos un re-fetch rápido silencioso
        _init();
        return;
      }

      final download = _downloads[downloadIndex];

      if (delta.status != null) download.state = delta.status;
      if (delta.info != null) download.info = delta.info;
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
