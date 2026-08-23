import 'package:flutter/material.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';

class SelectionModalController extends ChangeNotifier {
  final DownloadRepository repository;

  // Lista de descargas pendientes (para el dropdown)
  List<Download> pendingDownloads;
  late Download currentDownload;

  bool isLoading = false;
  bool isSubmitting = false;
  bool _isDisposed = false;
  int _fetchRequestId = 0;

  bool get isDisposed => _isDisposed;

  List<SubDownload> allEntries = [];
  Set<String> selectedIds = {};

  // Filtros
  String searchQuery = '';
  bool showOnlySelected = false;

  SelectionModalController(this.repository, this.pendingDownloads) {
    currentDownload = pendingDownloads.first;
    _fetchEntries();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  void switchDownload(Download newDownload) {
    if (currentDownload.id == newDownload.id) return;
    currentDownload = newDownload;
    _fetchEntries();
  }

  Future<void> _fetchEntries() async {
    final int requestId = ++_fetchRequestId;
    if (_isDisposed) return;

    isLoading = true;
    notifyListeners();

    try {
      final downloadId = currentDownload.id;
      if (downloadId == null || downloadId.isEmpty) {
        if (_isDisposed || requestId != _fetchRequestId) return;
        allEntries = [];
        selectedIds.clear();
        return;
      }

      final entries = await repository.getEntries(downloadId);
      if (_isDisposed || requestId != _fetchRequestId) return;

      allEntries = entries;
      // Por defecto, todo seleccionado (defensivo contra subId nulo)
      selectedIds = allEntries
          .where((e) => e.subId != null && e.subId!.isNotEmpty)
          .map((e) => e.subId!)
          .toSet();
    } catch (e) {
      debugPrint('Error cargando elementos: $e');
      if (_isDisposed || requestId != _fetchRequestId) return;
      allEntries = [];
      selectedIds.clear();
    } finally {
      if (!_isDisposed && requestId == _fetchRequestId) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  // --- RENDIMIENTO: Getter filtrado al vuelo ---
  List<SubDownload> get filteredEntries {
    return allEntries.where((e) {
      final matchesSearch =
          e.info?.title?.toLowerCase().contains(searchQuery.toLowerCase()) ??
          false;
      final matchesFilter =
          !showOnlySelected || (e.subId != null && selectedIds.contains(e.subId));
      return matchesSearch && matchesFilter;
    }).toList();
  }

  // --- ACCIONES ---
  void updateSearch(String query) {
    searchQuery = query;
    notifyListeners();
  }

  void toggleShowOnlySelected() {
    showOnlySelected = !showOnlySelected;
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    notifyListeners();
  }

  void selectAll() {
    selectedIds = allEntries
        .where((e) => e.subId != null && e.subId!.isNotEmpty)
        .map((e) => e.subId!)
        .toSet();
    notifyListeners();
  }

  void selectNone() {
    selectedIds.clear();
    notifyListeners();
  }

  void invertSelection() {
    final allIds = allEntries
        .where((e) => e.subId != null && e.subId!.isNotEmpty)
        .map((e) => e.subId!)
        .toSet();
    selectedIds = allIds.difference(selectedIds);
    notifyListeners();
  }

  Future<bool> submit() async {
    if (selectedIds.isEmpty || _isDisposed) {
      return false;
    }

    final downloadId = currentDownload.id;
    if (downloadId == null || downloadId.isEmpty) {
      return false;
    }

    isSubmitting = true;
    notifyListeners();

    try {
      await repository.submitSelectedEntries(
        downloadId,
        selectedIds.toList(),
      );
      return true;
    } catch (e) {
      debugPrint('Error enviando selección: $e');
      return false;
    } finally {
      if (!_isDisposed) {
        isSubmitting = false;
        notifyListeners();
      }
    }
  }
}
