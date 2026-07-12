import 'package:flutter/material.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

class SelectionModalController extends ChangeNotifier {
  final DownloadRepository repository;

  // Lista de descargas pendientes (para el dropdown)
  List<Download> pendingDownloads;
  late Download currentDownload;

  bool isLoading = false;
  bool isSubmitting = false;

  List<SubDownload> allEntries = [];
  Set<String> selectedIds = {};

  // Filtros
  String searchQuery = '';
  bool showOnlySelected = false;

  SelectionModalController(this.repository, this.pendingDownloads) {
    currentDownload = pendingDownloads.first;
    _fetchEntries();
  }

  void switchDownload(Download newDownload) {
    if (currentDownload.id == newDownload.id) return;
    currentDownload = newDownload;
    _fetchEntries();
  }

  Future<void> _fetchEntries() async {
    isLoading = true;
    notifyListeners();

    try {
      allEntries = await repository.getEntries(currentDownload.id!);
      // Por defecto, todo seleccionado
      selectedIds = allEntries.map((e) => e.subId!).toSet();
    } catch (e) {
      debugPrint('Error cargando elementos: $e');
      ToastUtils.showError('Error loading elements: $e');
      allEntries = [];
      selectedIds.clear();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // --- RENDIMIENTO: Getter filtrado al vuelo ---
  List<SubDownload> get filteredEntries {
    return allEntries.where((e) {
      final matchesSearch =
          e.info?.title?.toLowerCase().contains(searchQuery.toLowerCase()) ??
          false;
      final matchesFilter = !showOnlySelected || selectedIds.contains(e.subId);
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
    selectedIds = allEntries.map((e) => e.subId!).toSet();
    notifyListeners();
  }

  void selectNone() {
    selectedIds.clear();
    notifyListeners();
  }

  void invertSelection() {
    final allIds = allEntries.map((e) => e.subId!).toSet();
    selectedIds = allIds.difference(selectedIds);
    notifyListeners();
  }

  Future<bool> submit() async {
    if (selectedIds.isEmpty) {
      return false;
    }

    isSubmitting = true;
    notifyListeners();

    try {
      await repository.submitSelectedEntries(
        currentDownload.id!,
        selectedIds.toList(),
      );
      return true;
    } catch (e) {
      debugPrint('Error enviando selección: $e');
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}
