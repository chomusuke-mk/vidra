import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';

enum SubDownloadSortOption { byDefault, alphabetical }

class DownloadDetailController extends ChangeNotifier {
  final DownloadRepository _repository;
  final SystemController _systemController;
  final Download download;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // --- ESTADO PARA LOS LOGS ---
  String _logs = '';
  String get logs => _logs;

  bool _isLoadingLogs = false;
  bool get isLoadingLogs => _isLoadingLogs;

  StreamSubscription? _detailSseSubscription;

  // --- NUEVO: Lógica de Filtros y Búsqueda ---
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  final Set<DownloadStateEnum> _activeFilters = {};
  Set<DownloadStateEnum> get activeFilters => _activeFilters;

  SubDownloadSortOption _sortOption = SubDownloadSortOption.byDefault;
  SubDownloadSortOption get sortOption => _sortOption;

  bool _sortReversed = false;
  bool get sortReversed => _sortReversed;
  bool _isSearchVisible = false;
  bool get isSearchVisible => _isSearchVisible;

  void toggleSearchVisibility() {
    _isSearchVisible = !_isSearchVisible;
    notifyListeners();
  }

  DownloadDetailController(
    this._repository,
    this._systemController,
    this.download,
  ) {
    _systemController.addListener(_onSystemStateChanged);
    _initSequence();
  }

  // --- MÉTODOS DE FILTRADO ---
  void updateSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void toggleFilter(DownloadStateEnum state) {
    if (_activeFilters.contains(state)) {
      _activeFilters.remove(state);
    } else {
      _activeFilters.add(state);
    }
    notifyListeners();
  }

  void setSortOption(SubDownloadSortOption option) {
    if (_sortOption == option) {
      // Si el usuario toca la misma opción que ya está seleccionada, invertimos el orden
      _sortReversed = !_sortReversed;
    } else {
      _sortOption = option;
      _sortReversed = false; // Al cambiar de criterio, empezamos sin reversa
    }
    notifyListeners();
  }

  void toggleSortReverse() {
    _sortReversed = !_sortReversed;
    notifyListeners();
  }

  List<SubDownload> get filteredSubDownloads {
    final subs = download.subDownloads ?? [];
    final filtered = subs.where((sub) {
      if (_searchQuery.isNotEmpty) {
        final title = sub.info?.title?.toLowerCase() ?? '';
        if (!title.contains(_searchQuery.toLowerCase())) return false;
      }
      if (_activeFilters.isNotEmpty) {
        if (sub.state == null || !_activeFilters.contains(sub.state!.value)) {
          return false;
        }
      }
      return true;
    }).toList();
    if (_sortOption == SubDownloadSortOption.alphabetical) {
      filtered.sort((a, b) {
        final titleA = a.info?.title ?? '';
        final titleB = b.info?.title ?? '';
        return titleA.compareTo(titleB);
      });
    }
    if (_sortReversed) {
      return filtered.reversed.toList();
    }
    return filtered;
  }

  // ==========================================================================
  // REACTIVIDAD AL ESTADO DEL SISTEMA
  // ==========================================================================
  void _onSystemStateChanged() {
    if (_systemController.state == SystemState.ready) {
      // Si el backend revive mientras estamos en esta pantalla,
      // recargamos los datos frescos y nos reconectamos.
      _initSequence();
    } else {
      // Backend caído, nos desconectamos en silencio.
      _stopDetailSubscription();
    }
  }

  Future<void> _initSequence() async {
    // PROTECCIÓN: Si el backend no está listo, no intentamos hacer peticiones.
    // Solo mostramos los datos estáticos que ya tenemos en memoria (download).
    if (_systemController.state != SystemState.ready) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final freshDownload = await _repository.getDownloadById(download.id!);

      if (freshDownload != null) {
        download.info = freshDownload.info ?? download.info;
        download.state = freshDownload.state ?? download.state;
        download.subDownloads = freshDownload.subDownloads ?? [];
        download.options = freshDownload.options ?? download.options;
      }
      await fetchLogs();
    } catch (e) {
      debugPrint('Error sincronizando detalle: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      _startDetailSubscription(); // Nos conectamos porque sabemos que el backend está listo
    }
  }

  Future<void> fetchLogs() async {
    if (_systemController.state != SystemState.ready) return;

    _isLoadingLogs = true;
    notifyListeners();
    try {
      _logs = await _repository.fetchLogs(download.id!);
    } catch (e) {
      _logs = 'Error obtaining logs:\n$e';
    } finally {
      _isLoadingLogs = false;
      notifyListeners();
    }
  }

  void _startDetailSubscription() {
    if (_detailSseSubscription != null) return;

    _detailSseSubscription = _repository
        .watchDetailedProgress(download.id!)
        .listen(
          _applySubDeltas,
          onError: (e) {
            debugPrint('⚠️ Error SSE Detalle (Ignorado): $e');
            // Dejamos que el _onSystemStateChanged se encargue de cerrar esto limpiamente.
          },
          cancelOnError: false, // Magia antidecuelgues
        );
  }

  void _stopDetailSubscription() {
    _detailSseSubscription?.cancel();
    _detailSseSubscription = null;
  }

  void _applySubDeltas(List<Delta> deltas) {
    bool changed = false;

    for (var delta in deltas) {
      if (delta.subId == null) {
        continue; // Solo nos interesan los sub-deltas aquí
      }

      download.subDownloads ??= [];

      // Borrado dinámico de sub-descargas si el SSE así lo demanda
      if (delta.status?.value == DownloadStateEnum.deleted) {
        download.subDownloads!.removeWhere((s) => s.subId == delta.subId);
        changed = true;
        continue;
      }

      final subIndex = download.subDownloads!.indexWhere(
        (s) => s.subId == delta.subId,
      );

      if (subIndex != -1) {
        final sub = download.subDownloads![subIndex];
        if (delta.status != null) sub.state = delta.status;
        if (delta.info != null) sub.info = delta.info;
      } else {
        // CREAR: Llega un sub_id desconocido (ej. el backend descubrió un nuevo elemento en la playlist)
        download.subDownloads!.add(
          SubDownload(
            subId: delta.subId,
            parentId: delta.id,
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
    _systemController.removeListener(_onSystemStateChanged);
    _detailSseSubscription?.cancel();
    super.dispose();
  }
}
