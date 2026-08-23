import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';

class DownloadsController extends ChangeNotifier {
  final DownloadRepository _repository;
  final SystemController _systemController;

  List<Download> _downloads = [];
  List<Download> get downloads => _downloads;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  StreamSubscription? _globalSseSubscription;

  String? _manualModalRequestId;
  String? get manualModalRequestId => _manualModalRequestId;

  // --- Single-Flight Concurrency Controls ---
  Future<void>? _syncFuture;
  bool _syncQueued = false;
  bool _isDisposed = false;

  // --- Bounded FIFO Tombstone & Missing ID Sets (Max 500) ---
  static const int _maxTombstones = 500;
  static const int _maxIgnoredMissing = 500;

  final LinkedHashSet<String> _tombstonedIds = LinkedHashSet<String>();
  final LinkedHashSet<String> _ignoredMissingIds = LinkedHashSet<String>();
  final Set<String> _pendingMissingIds = <String>{};

  Set<String> get tombstonedIds => Set.unmodifiable(_tombstonedIds);
  Set<String> get ignoredMissingIds => Set.unmodifiable(_ignoredMissingIds);

  bool isTombstoned(String id) => _tombstonedIds.contains(id);
  bool isIgnoredMissing(String id) => _ignoredMissingIds.contains(id);

  DownloadsController(this._repository, this._systemController) {
    _systemController.addListener(_onSystemStateChanged);
    if (_systemController.state == SystemState.ready) {
      _onSystemStateChanged();
    }
  }

  // ==========================================================================
  // MODAL MANUAL DE DESCARGA
  // ==========================================================================
  void requestSelectionModal(String id) {
    _manualModalRequestId = id;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void consumeManualModalRequest() {
    _manualModalRequestId = null;
  }

  // ==========================================================================
  // TOMBSTONE & GHOST ID HELPERS
  // ==========================================================================
  void tombstoneId(String id) {
    _tombstoneInternal(id);
    _downloads.removeWhere((d) => d.id == id);
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void _tombstoneInternal(String id) {
    _ignoredMissingIds.remove(id);
    _pendingMissingIds.remove(id);
    if (_tombstonedIds.contains(id)) {
      _tombstonedIds.remove(id);
    } else if (_tombstonedIds.length >= _maxTombstones) {
      _tombstonedIds.remove(_tombstonedIds.first);
    }
    _tombstonedIds.add(id);
  }

  void _addToIgnoredMissing(String id) {
    if (_tombstonedIds.contains(id)) return;
    if (_ignoredMissingIds.contains(id)) {
      _ignoredMissingIds.remove(id);
    } else if (_ignoredMissingIds.length >= _maxIgnoredMissing) {
      _ignoredMissingIds.remove(_ignoredMissingIds.first);
    }
    _ignoredMissingIds.add(id);
  }

  void clearTombstones() {
    _tombstonedIds.clear();
    _ignoredMissingIds.clear();
    _pendingMissingIds.clear();
  }

  void resurrectId(String id) {
    _tombstonedIds.remove(id);
    _ignoredMissingIds.remove(id);
    _pendingMissingIds.remove(id);
  }

  // ==========================================================================
  // REACTIVIDAD AL ESTADO DEL SISTEMA
  // ==========================================================================
  void _onSystemStateChanged() {
    if (_systemController.state == SystemState.ready) {
      // 1. El backend ya levantó (Puerto real disponible). Traemos los datos de BD.
      syncDownloads(isInitialLoad: true).then((_) {
        if (!_isDisposed && _systemController.state == SystemState.ready) {
          _startGlobalSubscription();
        }
      });
    } else {
      // Si el backend se cae o cambia de estado, cortamos la escucha limpia y pacíficamente.
      _stopGlobalSubscription();
    }
  }

  void _startGlobalSubscription() {
    if (_globalSseSubscription != null || _isDisposed) return;
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
  // CORE SINGLE-FLIGHT SYNCHRONIZATION
  // ==========================================================================

  /// Public helper for non-loading refreshes.
  Future<void> refreshDownloads() => syncDownloads(isInitialLoad: false);

  /// Thread-safe, single-flight downloads synchronization.
  ///
  /// - If [isInitialLoad] is true and [_downloads] is empty, sets [_isLoading = true].
  /// - Background syncs ([isInitialLoad] == false) run silently without modifying [_isLoading].
  /// - Coalesces concurrent calls into a single in-flight future.
  /// - Queues at most one follow-up execution if called while in-flight.
  Future<void> syncDownloads({bool isInitialLoad = false}) {
    if (_systemController.state != SystemState.ready || _isDisposed) {
      return Future.value();
    }

    if (isInitialLoad && _downloads.isEmpty) {
      if (!_isLoading) {
        _isLoading = true;
        if (!_isDisposed) {
          notifyListeners();
        }
      }
    }

    if (_syncFuture != null) {
      _syncQueued = true;
      return _syncFuture!;
    }

    _syncFuture = _executeSync(isInitialLoad: isInitialLoad).whenComplete(() {
      _syncFuture = null;
      if (_syncQueued &&
          !_isDisposed &&
          _systemController.state == SystemState.ready) {
        _syncQueued = false;
        syncDownloads(isInitialLoad: false);
      }
    });

    return _syncFuture!;
  }

  Future<void> _executeSync({required bool isInitialLoad}) async {
    try {
      final freshDownloads = await _repository.getAllDownloads();
      if (_isDisposed) return;

      // Filter out tombstoned items
      final filteredDownloads = <Download>[];
      final returnedIds = <String>{};

      for (final download in freshDownloads) {
        final id = download.id;
        if (id != null) {
          if (_tombstonedIds.contains(id)) {
            // Tombstoned items are filtered out
            continue;
          }
          returnedIds.add(id);
          // If server explicitly returns an item, reconcile it from missing/pending sets
          _ignoredMissingIds.remove(id);
          _pendingMissingIds.remove(id);
        }
        filteredDownloads.add(download);
      }

      _downloads = filteredDownloads;

      // Reconcile pending missing IDs:
      // Any ID in _pendingMissingIds not present in fresh response is a confirmed ghost
      if (_pendingMissingIds.isNotEmpty) {
        final missingIds = _pendingMissingIds.difference(returnedIds);
        for (final id in missingIds) {
          _addToIgnoredMissing(id);
        }
        _pendingMissingIds.clear();
      }
    } catch (e) {
      debugPrint('Error cargando descargas: $e');
    } finally {
      if (isInitialLoad && _isLoading) {
        _isLoading = false;
      }
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  // ==========================================================================
  // ACTIONS & GESTURES
  // ==========================================================================
  Future<bool> addDownload(String url, Map<String, dynamic> options) async {
    if (url.trim().isEmpty) return false;
    debugPrint('📤 [UI-Downloads] Solicitando descarga vía puente IPC...');
    _systemController.enqueueDownload(url, options);
    return true;
  }

  Future<bool> deleteDownload(String id) async {
    tombstoneId(id);
    try {
      await _repository.deleteDownload(id);
      return true;
    } catch (e) {
      debugPrint('Error al eliminar descarga $id: $e');
      return false;
    }
  }

  Future<bool> cancelDownload(String id) async {
    try {
      await _repository.cancelDownload(id);
      return true;
    } catch (e) {
      debugPrint('Error al cancelar descarga $id: $e');
      return false;
    }
  }

  Future<bool> pauseDownload(String id) async {
    try {
      await _repository.pauseDownload(id);
      return true;
    } catch (e) {
      debugPrint('Error al pausar descarga $id: $e');
      return false;
    }
  }

  Future<bool> resumeDownload(String id) async {
    try {
      await _repository.resumeDownload(id);
      return true;
    } catch (e) {
      debugPrint('Error al reanudar descarga $id: $e');
      return false;
    }
  }

  Future<bool> retryDownload(String id) async {
    _ignoredMissingIds.remove(id);
    _tombstonedIds.remove(id);
    try {
      await _repository.retryDownload(id);
      return true;
    } catch (e) {
      debugPrint('Error al reintentar descarga $id: $e');
      return false;
    }
  }

  Future<bool> sendAction(String id, String action) async {
    switch (action) {
      case 'delete':
        return deleteDownload(id);
      case 'cancel':
        return cancelDownload(id);
      case 'pause':
        return pauseDownload(id);
      case 'resume':
        return resumeDownload(id);
      case 'retry':
        return retryDownload(id);
      default:
        debugPrint('Acción no reconocida: $action');
        return false;
    }
  }

  // ==========================================================================
  // SAFE BATCH DELTA PROCESSING
  // ==========================================================================
  void _applyGlobalDeltas(List<Delta> deltas) {
    bool listChanged = false;
    bool needsSync = false;

    for (final delta in deltas) {
      if (delta.subId != null || delta.id == null) continue;
      final id = delta.id!;

      // 1. Fast-Path: Skip tombstoned or confirmed-missing ghost items immediately
      if (_tombstonedIds.contains(id) || _ignoredMissingIds.contains(id)) {
        continue;
      }

      // 2. Handle deleted state delta from backend
      if (delta.status?.value == DownloadStateEnum.deleted) {
        _tombstoneInternal(id);
        _downloads.removeWhere((d) => d.id == id);
        listChanged = true;
        continue;
      }

      // 3. Match against in-memory downloads
      final downloadIndex = _downloads.indexWhere((d) => d.id == id);
      if (downloadIndex == -1) {
        // Unknown download: schedule single-flight sync and mark for missing check
        if (!_pendingMissingIds.contains(id)) {
          _pendingMissingIds.add(id);
          needsSync = true;
        }
        // DO NOT return! Continue processing remaining deltas in the batch
        continue;
      }

      // 4. In-place state mutation for existing download
      final download = _downloads[downloadIndex];
      if (delta.status != null) {
        download.state = delta.status;
        listChanged = true;
      }
      if (delta.info != null) {
        download.info = delta.info;
        listChanged = true;
      }
    }

    if (listChanged && !_isDisposed) {
      notifyListeners();
    }

    if (needsSync && !_isDisposed) {
      syncDownloads(isInitialLoad: false);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _systemController.removeListener(_onSystemStateChanged);
    _stopGlobalSubscription();
    super.dispose();
  }
}
