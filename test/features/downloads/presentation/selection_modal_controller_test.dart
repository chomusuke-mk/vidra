import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/selection_modal_controller.dart';

class MockDownloadRepository implements DownloadRepository {
  final Map<String, Completer<List<SubDownload>>> _completers = {};
  final Map<String, List<SubDownload>> _entries = {};
  Completer<void>? pendingSubmitCompleter;
  bool shouldThrowOnGetEntries = false;
  bool shouldThrowOnSubmit = false;
  final List<String> submittedIds = [];
  final List<List<String>> submittedSelections = [];

  void setCompleter(String id, Completer<List<SubDownload>> completer) {
    _completers[id] = completer;
  }

  void setEntries(String id, List<SubDownload> entries) {
    _entries[id] = entries;
  }

  @override
  Future<List<SubDownload>> getEntries(String id) async {
    if (shouldThrowOnGetEntries) {
      throw Exception('Backend network failure on getEntries');
    }
    if (_completers.containsKey(id)) {
      return _completers[id]!.future;
    }
    return _entries[id] ?? [];
  }

  @override
  Future<void> submitSelectedEntries(String id, List<String> entries) async {
    submittedIds.add(id);
    submittedSelections.add(entries);
    if (pendingSubmitCompleter != null) {
      await pendingSubmitCompleter!.future;
    }
    if (shouldThrowOnSubmit) {
      throw Exception('Backend network failure on submit');
    }
  }

  @override
  Stream<List<Delta>> watchGlobalProgress() => const Stream.empty();
  @override
  Future<List<Download>> getAllDownloads() async => [];
  @override
  Future<Download?> getDownloadById(String id) async => null;
  @override
  Future<String> addDownload(String url, {Map<String, dynamic> options = const {}}) async => 'id';
  @override
  Future<void> pauseDownload(String id) async {}
  @override
  Future<void> resumeDownload(String id) async {}
  @override
  Future<void> cancelDownload(String id) async {}
  @override
  Future<void> retryDownload(String id) async {}
  @override
  Future<void> deleteDownload(String id) async {}
  @override
  Future<String> fetchLogs(String? id) async => '';
  @override
  Future<bool> checkHealth() async => true;
  @override
  Stream<List<Delta>> watchDetailedProgress(String id) => const Stream.empty();
}

void main() {
  group('SelectionModalController Unit Tests', () {
    late MockDownloadRepository repository;

    setUp(() {
      repository = MockDownloadRepository();
    });

    test('Disposal Safety: late getEntries completion after dispose does not throw or notify', () async {
      final completer = Completer<List<SubDownload>>();
      repository.setCompleter('dl_1', completer);

      final ctrl = SelectionModalController(repository, [
        Download(id: 'dl_1', info: Info(title: 'Item 1')),
      ]);

      expect(ctrl.isLoading, isTrue);
      expect(ctrl.isDisposed, isFalse);

      // Dispose controller while getEntries is still pending
      ctrl.dispose();
      expect(ctrl.isDisposed, isTrue);

      // Complete the pending future late
      completer.complete([
        SubDownload(subId: 's1', info: Info(title: 'Sub 1')),
      ]);
      await Future<void>.delayed(Duration.zero);

      // Must not throw FlutterError and state must remain clean
      expect(ctrl.isDisposed, isTrue);
    });

    test('Disposal Safety: late submit completion after dispose does not throw or notify', () async {
      repository.setEntries('dl_1', [
        SubDownload(subId: 's1', info: Info(title: 'Sub 1')),
      ]);

      final ctrl = SelectionModalController(repository, [
        Download(id: 'dl_1', info: Info(title: 'Item 1')),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.selectedIds, contains('s1'));

      final submitCompleter = Completer<void>();
      repository.pendingSubmitCompleter = submitCompleter;

      final submitFuture = ctrl.submit();
      expect(ctrl.isSubmitting, isTrue);

      // Dispose controller while submit is in flight
      ctrl.dispose();
      expect(ctrl.isDisposed, isTrue);

      // Complete submission
      submitCompleter.complete();
      final result = await submitFuture;

      expect(result, isTrue);
      expect(ctrl.isDisposed, isTrue);
    });

    test('Request Tokening: out-of-order responses ignore older request data', () async {
      final completer1 = Completer<List<SubDownload>>();
      final completer2 = Completer<List<SubDownload>>();

      repository.setCompleter('dl_1', completer1);
      repository.setCompleter('dl_2', completer2);

      final ctrl = SelectionModalController(repository, [
        Download(id: 'dl_1', info: Info(title: 'Download 1')),
        Download(id: 'dl_2', info: Info(title: 'Download 2')),
      ]);

      // Switch to dl_2 immediately
      ctrl.switchDownload(Download(id: 'dl_2', info: Info(title: 'Download 2')));

      // Complete dl_2 first
      completer2.complete([
        SubDownload(subId: 'dl2_item1', info: Info(title: 'Item from DL 2')),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.allEntries.map((e) => e.subId), contains('dl2_item1'));
      expect(ctrl.isLoading, isFalse);

      // Complete dl_1 late (out-of-order)
      completer1.complete([
        SubDownload(subId: 'dl1_item1', info: Info(title: 'Item from DL 1')),
      ]);
      await Future<void>.delayed(Duration.zero);

      // Must NOT overwrite dl_2 data with stale dl_1 data
      expect(ctrl.allEntries.map((e) => e.subId), contains('dl2_item1'));
      expect(ctrl.allEntries.map((e) => e.subId), isNot(contains('dl1_item1')));
    });

    test('Error Handling: backend exception in getEntries resets entries gracefully without throwing', () async {
      repository.shouldThrowOnGetEntries = true;

      final ctrl = SelectionModalController(repository, [
        Download(id: 'dl_err', info: Info(title: 'Error DL')),
      ]);

      await Future<void>.delayed(Duration.zero);

      expect(ctrl.isLoading, isFalse);
      expect(ctrl.allEntries, isEmpty);
      expect(ctrl.selectedIds, isEmpty);
    });

    test('Error Handling: backend exception in submit returns false gracefully without throwing', () async {
      repository.setEntries('dl_1', [
        SubDownload(subId: 's1', info: Info(title: 'Sub 1')),
      ]);
      repository.shouldThrowOnSubmit = true;

      final ctrl = SelectionModalController(repository, [
        Download(id: 'dl_1', info: Info(title: 'Item 1')),
      ]);
      await Future<void>.delayed(Duration.zero);

      final result = await ctrl.submit();
      expect(result, isFalse);
      expect(ctrl.isSubmitting, isFalse);
    });

    test('Selection Operations: toggle, selectAll, selectNone, invertSelection', () async {
      repository.setEntries('dl_1', [
        SubDownload(subId: 's1', info: Info(title: 'Song A')),
        SubDownload(subId: 's2', info: Info(title: 'Song B')),
        SubDownload(subId: 's3', info: Info(title: 'Song C')),
      ]);

      final ctrl = SelectionModalController(repository, [
        Download(id: 'dl_1', info: Info(title: 'Item 1')),
      ]);
      await Future<void>.delayed(Duration.zero);

      // By default all selected
      expect(ctrl.selectedIds, equals({'s1', 's2', 's3'}));

      // Toggle s2
      ctrl.toggleSelection('s2');
      expect(ctrl.selectedIds, equals({'s1', 's3'}));

      // Toggle s2 back
      ctrl.toggleSelection('s2');
      expect(ctrl.selectedIds, equals({'s1', 's2', 's3'}));

      // Select none
      ctrl.selectNone();
      expect(ctrl.selectedIds, isEmpty);

      // Invert selection
      ctrl.invertSelection();
      expect(ctrl.selectedIds, equals({'s1', 's2', 's3'}));

      // Toggle s1 and invert
      ctrl.toggleSelection('s1');
      ctrl.invertSelection();
      expect(ctrl.selectedIds, equals({'s1'}));

      // Select all
      ctrl.selectAll();
      expect(ctrl.selectedIds, equals({'s1', 's2', 's3'}));
    });

    test('Filtering: search and showOnlySelected', () async {
      repository.setEntries('dl_1', [
        SubDownload(subId: 's1', info: Info(title: 'Rock Music Video')),
        SubDownload(subId: 's2', info: Info(title: 'Jazz Audio Track')),
        SubDownload(subId: 's3', info: Info(title: 'Pop Song')),
      ]);

      final ctrl = SelectionModalController(repository, [
        Download(id: 'dl_1', info: Info(title: 'Item 1')),
      ]);
      await Future<void>.delayed(Duration.zero);

      // Search filter
      ctrl.updateSearch('Jazz');
      expect(ctrl.filteredEntries.length, equals(1));
      expect(ctrl.filteredEntries.first.subId, equals('s2'));

      ctrl.updateSearch('');
      expect(ctrl.filteredEntries.length, equals(3));

      // Deselect s3 and enable showOnlySelected
      ctrl.toggleSelection('s3');
      ctrl.toggleShowOnlySelected();
      expect(ctrl.showOnlySelected, isTrue);
      expect(ctrl.filteredEntries.map((e) => e.subId), equals(['s1', 's2']));
    });

    test('Edge Cases: empty download ID or null ID handles gracefully', () async {
      final ctrl = SelectionModalController(repository, [
        Download(id: null, info: Info(title: 'Null ID')),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.allEntries, isEmpty);
      expect(ctrl.selectedIds, isEmpty);

      final submitResult = await ctrl.submit();
      expect(submitResult, isFalse);
    });
  });
}
