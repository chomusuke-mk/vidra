import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/presentation/selection_modal_controller.dart';
import 'package:vidra/features/downloads/presentation/selection_wrapper.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';

class AdversarialMockRepository implements DownloadRepository {
  final List<Completer<List<SubDownload>>> getEntriesCompleters = [];
  final List<String> requestedDownloadIds = [];
  final List<String> submittedDownloadIds = [];
  final List<List<String>> submittedSelections = [];
  Completer<void>? pendingSubmitCompleter;
  bool shouldThrowOnSubmit = false;

  Completer<List<SubDownload>> registerNextGetEntriesCompleter() {
    final completer = Completer<List<SubDownload>>();
    getEntriesCompleters.add(completer);
    return completer;
  }

  @override
  Future<List<SubDownload>> getEntries(String id) {
    requestedDownloadIds.add(id);
    if (getEntriesCompleters.isNotEmpty) {
      return getEntriesCompleters.removeAt(0).future;
    }
    return Future.value([
      SubDownload(subId: '${id}_item_default', info: Info(title: 'Default for $id')),
    ]);
  }

  @override
  Future<void> submitSelectedEntries(String id, List<String> entries) async {
    submittedDownloadIds.add(id);
    submittedSelections.add(entries);
    if (pendingSubmitCompleter != null) {
      await pendingSubmitCompleter!.future;
    }
    if (shouldThrowOnSubmit) {
      throw Exception('Simulated submit failure');
    }
  }

  @override
  Stream<List<Delta>> watchGlobalProgress() => const Stream.empty();
  @override
  Future<List<Download>> getAllDownloads() async => [];
  @override
  Future<Download?> getDownloadById(String id) async => null;
  @override
  Future<String> addDownload(String url, {Map<String, dynamic> options = const {}}) async => 'adv_id';
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

class AdversarialDownloadsController extends ChangeNotifier implements DownloadsController {
  List<Download> _downloads = [];
  String? _manualModalRequestId;

  @override
  List<Download> get downloads => _downloads;
  @override
  bool get isLoading => false;
  @override
  String? get manualModalRequestId => _manualModalRequestId;

  @override
  void requestSelectionModal(String id) {
    _manualModalRequestId = id;
    notifyListeners();
  }

  @override
  void consumeManualModalRequest() {
    _manualModalRequestId = null;
  }

  void updateDownloads(List<Download> newDownloads) {
    _downloads = newDownloads;
    notifyListeners();
  }

  @override
  Future<bool> addDownload(String url, Map<String, dynamic> options) async => true;
  @override
  Future<bool> sendAction(String id, String action) async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdversarialLocaleController extends ChangeNotifier implements LocaleController {
  final AppStringKey _strings = AppStringKey();

  AdversarialLocaleController() {
    _strings.updateFromJson({
      'sw_selection_enqueued': 'Selection enqueued',
      'sw_list_forwarded': 'List forwarded to queue',
      'sw_unknown_title': 'Unknown Title',
      'sw_search': 'Search',
      'sw_filter_selected': 'Selected only',
      'sw_button_select_all': 'Select all',
      'sw_button_deselect_all': 'Deselect all',
      'sw_button_invert_selection': 'Invert',
      'sw_no_elements_match': 'No elements match',
      'sw_sending_selection': 'Sending selection...',
      'sw_button_download_selected': 'Download selected',
      'sw_no_elements_selected': 'No elements selected',
      'sw_send_selection_success': 'Selection sent successfully',
      'sw_send_selection_error': 'Error sending selection',
    });
  }

  @override
  AppStringKey get localeStrings => _strings;
  @override
  String get currentLocaleCode => 'en';
  @override
  Future<void> get whenReady => Future.value();
  @override
  void setLocale(String localeCode) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Adversarial Challenge: Milestone 2 Selection Lifecycle & Request Tokening', () {
    late AdversarialMockRepository repository;

    setUp(() {
      repository = AdversarialMockRepository();
    });

    // =========================================================================
    // CHALLENGE 1: Rapid switchDownload() Storm with Shuffled Out-Of-Order HTTP Responses
    // =========================================================================
    test('Stress Test 1: Rapid 20x switchDownload across out-of-order responses isolates active download state', () async {
      // Setup 20 completers for 20 sequential switch requests
      final completers = <Completer<List<SubDownload>>>[];
      for (var i = 0; i < 20; i++) {
        completers.add(repository.registerNextGetEntriesCompleter());
      }

      final downloads = List.generate(
        5,
        (i) => Download(id: 'dl_$i', info: Info(title: 'Download $i')),
      );

      // Initial construction triggers request #0 (dl_0)
      final ctrl = SelectionModalController(repository, downloads);
      expect(ctrl.isLoading, isTrue);

      // Rapidly switch 19 times across downloads [1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4]
      // Request #19 will be for dl_4
      for (var i = 1; i < 20; i++) {
        final targetDownload = downloads[i % 5];
        ctrl.switchDownload(targetDownload);
        expect(ctrl.currentDownload.id, equals(targetDownload.id));
      }

      // At this point, 20 requests have been issued. Request #19 (dl_4) is active.
      expect(repository.requestedDownloadIds.length, equals(20));
      expect(ctrl.isLoading, isTrue);

      // Now complete requests in reverse/shuffled order:
      // Resolve requests 0 to 18 first with distinct items
      for (var i = 0; i < 19; i++) {
        completers[i].complete([
          SubDownload(subId: 'stale_item_$i', info: Info(title: 'Stale item $i')),
        ]);
      }
      await Future<void>.delayed(Duration.zero);

      // Verify that NONE of the stale responses 0..18 polluted allEntries or reset isLoading
      expect(ctrl.allEntries, isEmpty, reason: 'Stale responses must not populate allEntries while active request #19 is pending');
      expect(ctrl.selectedIds, isEmpty, reason: 'Stale responses must not populate selectedIds');
      expect(ctrl.isLoading, isTrue, reason: 'isLoading must remain true until active request completes');

      // Now complete the final active request #19 (dl_4)
      completers[19].complete([
        SubDownload(subId: 'active_dl4_item1', info: Info(title: 'Active DL4 Item 1')),
        SubDownload(subId: 'active_dl4_item2', info: Info(title: 'Active DL4 Item 2')),
      ]);
      await Future<void>.delayed(Duration.zero);

      // Active request must now be properly reflected
      expect(ctrl.isLoading, isFalse);
      expect(ctrl.allEntries.map((e) => e.subId), equals(['active_dl4_item1', 'active_dl4_item2']));
      expect(ctrl.selectedIds, equals({'active_dl4_item1', 'active_dl4_item2'}));
    });

    // =========================================================================
    // CHALLENGE 2: Interleaved Exceptions from Stale Requests
    // =========================================================================
    test('Stress Test 2: Network exceptions on stale requests do not clear or corrupt active request data', () async {
      final c0 = repository.registerNextGetEntriesCompleter();
      final c1 = repository.registerNextGetEntriesCompleter();
      final c2 = repository.registerNextGetEntriesCompleter();

      final d0 = Download(id: 'dl_0', info: Info(title: 'D0'));
      final d1 = Download(id: 'dl_1', info: Info(title: 'D1'));
      final d2 = Download(id: 'dl_2', info: Info(title: 'D2'));

      final ctrl = SelectionModalController(repository, [d0, d1, d2]); // Triggers c0
      ctrl.switchDownload(d1); // Triggers c1
      ctrl.switchDownload(d2); // Triggers c2

      // Resolve c2 (active) first with valid data
      c2.complete([
        SubDownload(subId: 'd2_correct_item', info: Info(title: 'D2 Correct')),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.allEntries.map((e) => e.subId), equals(['d2_correct_item']));
      expect(ctrl.isLoading, isFalse);

      // Now throw exceptions on c0 and c1 late
      c0.completeError(Exception('Fatal socket drop on c0'));
      c1.completeError(Exception('Server 500 on c1'));
      await Future<void>.delayed(Duration.zero);

      // Active state must NOT be wiped by error handler of c0 or c1
      expect(ctrl.allEntries.map((e) => e.subId), equals(['d2_correct_item']));
      expect(ctrl.selectedIds, equals({'d2_correct_item'}));
      expect(ctrl.isLoading, isFalse);
    });

    // =========================================================================
    // CHALLENGE 3: Repeated Switching Between Same 2 Downloads with Out-Of-Order Resolution
    // =========================================================================
    test('Stress Test 3: Ping-pong switching between A and B with interleaved delivery', () async {
      final cA1 = repository.registerNextGetEntriesCompleter();
      final cB1 = repository.registerNextGetEntriesCompleter();
      final cA2 = repository.registerNextGetEntriesCompleter();

      final dA = Download(id: 'dl_A', info: Info(title: 'Download A'));
      final dB = Download(id: 'dl_B', info: Info(title: 'Download B'));

      final ctrl = SelectionModalController(repository, [dA, dB]); // cA1
      ctrl.switchDownload(dB); // cB1
      ctrl.switchDownload(dA); // cA2 (active: dA with token #3)

      // cB1 resolves first
      cB1.complete([
        SubDownload(subId: 'item_B_stale', info: Info(title: 'B item')),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.allEntries, isEmpty);

      // cA1 resolves next (older fetch for A)
      cA1.complete([
        SubDownload(subId: 'item_A_old_version', info: Info(title: 'A old item')),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.allEntries, isEmpty);

      // cA2 resolves last (fresh fetch for A)
      cA2.complete([
        SubDownload(subId: 'item_A_fresh_version', info: Info(title: 'A fresh item')),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.allEntries.map((e) => e.subId), equals(['item_A_fresh_version']));
      expect(ctrl.selectedIds, equals({'item_A_fresh_version'}));
    });

    // =========================================================================
    // CHALLENGE 4: Sequential Queue Processing & Dismissed Set Integrity in SelectionFabWrapper
    // =========================================================================
    testWidgets('Stress Test 4: Queue processing with rapid delta cancellation, dismissal, and manual priority override', (
      WidgetTester tester,
    ) async {
      final downloadsController = AdversarialDownloadsController();
      final localeController = AdversarialLocaleController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsController),
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            Provider<DownloadRepository>.value(value: repository),
          ],
          child: MaterialApp(
            home: SelectionFabWrapper(
              child: const Scaffold(
                body: Center(child: Text('Main Screen Content')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Burst of 6 downloads entering awaitingSelection
      final initialDownloads = List.generate(
        6,
        (i) => Download(
          id: 'burst_$i',
          info: Info(title: 'Burst Playlist $i'),
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
        ),
      );
      downloadsController.updateDownloads(initialDownloads);
      await tester.pumpAndSettle();

      // burst_0 modal is now active
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Default for burst_0'), findsOneWidget);

      // 2. While burst_0 is active:
      // - Cancel burst_1 and burst_2 from backend
      // - Cancel active burst_0
      downloadsController.updateDownloads([
        Download(id: 'burst_0', state: DownloadState(value: DownloadStateEnum.cancelled)),
        Download(id: 'burst_1', state: DownloadState(value: DownloadStateEnum.cancelled)),
        Download(id: 'burst_2', state: DownloadState(value: DownloadStateEnum.cancelled)),
        initialDownloads[3], // burst_3 awaiting
        initialDownloads[4], // burst_4 awaiting
        initialDownloads[5], // burst_5 awaiting
      ]);
      await tester.pumpAndSettle();

      // burst_0 closed, burst_1 and burst_2 skipped from queue, burst_3 automatically opened
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Default for burst_3'), findsOneWidget);

      // 3. User dismisses burst_3 by pressing close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // burst_4 should now open automatically, and burst_3 is in dismissed set
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Default for burst_4'), findsOneWidget);

      // 4. Send progress updates for burst_3 — it should NOT interrupt or reopen
      downloadsController.updateDownloads([
        Download(id: 'burst_3', state: DownloadState(value: DownloadStateEnum.awaitingSelection, progressValue: 50.0)),
        initialDownloads[4],
        initialDownloads[5],
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Default for burst_4'), findsOneWidget);

      // 5. User requests manual selection for dismissed burst_3 from Card
      downloadsController.requestSelectionModal('burst_3');
      await tester.pumpAndSettle();

      // burst_4 is still open, but burst_3 was enqueued to front
      expect(find.text('Default for burst_4'), findsOneWidget);

      // 6. User submits burst_4
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // Next modal must be burst_3 (front of queue override) rather than burst_5
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Default for burst_3'), findsOneWidget);

      // 7. Submit burst_3
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // Next modal is burst_5
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Default for burst_5'), findsOneWidget);

      // 8. Submit burst_5
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // All queues empty, dialog closed
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Main Screen Content'), findsOneWidget);
    });

    // =========================================================================
    // CHALLENGE 5: Multiple rapid FAB triggers during queue drain
    // =========================================================================
    testWidgets('Stress Test 5: Rapid FAB taps during active modal do not duplicate queue or trigger duplicate dialogs', (
      WidgetTester tester,
    ) async {
      final downloadsController = AdversarialDownloadsController();
      final localeController = AdversarialLocaleController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsController),
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            Provider<DownloadRepository>.value(value: repository),
          ],
          child: MaterialApp(
            home: SelectionFabWrapper(
              child: const Scaffold(
                body: Center(child: Text('Main Screen Content')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      downloadsController.updateDownloads([
        Download(id: 'item_fab_1', info: Info(title: 'FAB 1'), state: DownloadState(value: DownloadStateEnum.awaitingSelection)),
        Download(id: 'item_fab_2', info: Info(title: 'FAB 2'), state: DownloadState(value: DownloadStateEnum.awaitingSelection)),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Default for item_fab_1'), findsOneWidget);

      // Rapidly tap the FAB 10 times while modal 1 is active
      final fab = find.byType(FloatingActionButton);
      if (fab.evaluate().isNotEmpty) {
        for (var i = 0; i < 10; i++) {
          await tester.tap(fab, warnIfMissed: false);
        }
        await tester.pumpAndSettle();
      }

      // Close modal 1
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // Modal 2 should open once
      expect(find.text('Default for item_fab_2'), findsOneWidget);

      // Close modal 2
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // No lingering dialogs
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
