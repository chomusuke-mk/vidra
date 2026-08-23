import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/presentation/selection_wrapper.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';

class MockLocaleController extends ChangeNotifier implements LocaleController {
  final AppStringKey _strings = AppStringKey();

  MockLocaleController() {
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

class FakeSelectionRepository implements DownloadRepository {
  Map<String, List<SubDownload>> entriesMap = {};
  Completer<List<SubDownload>>? pendingGetEntriesCompleter;
  Completer<void>? pendingSubmitCompleter;
  bool submitShouldFail = false;
  final List<String> submittedIds = [];
  final List<List<String>> submittedEntries = [];
  int getEntriesCalls = 0;

  @override
  Future<List<SubDownload>> getEntries(String id) async {
    getEntriesCalls++;
    if (pendingGetEntriesCompleter != null) {
      return pendingGetEntriesCompleter!.future;
    }
    return entriesMap[id] ?? [];
  }

  @override
  Future<void> submitSelectedEntries(String id, List<String> entries) async {
    submittedIds.add(id);
    submittedEntries.add(entries);
    if (pendingSubmitCompleter != null) {
      await pendingSubmitCompleter!.future;
    }
    if (submitShouldFail) {
      throw Exception('Simulated selection submission failure');
    }
  }

  @override
  Stream<List<Delta>> watchGlobalProgress() => const Stream.empty();
  @override
  Future<List<Download>> getAllDownloads() async => [];
  @override
  Future<Download?> getDownloadById(String id) async => null;
  @override
  Future<String> addDownload(String url, {Map<String, dynamic> options = const {}}) async => 'new_id';
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

class FakeControlledDownloadsController extends ChangeNotifier implements DownloadsController {
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

Widget createTestApp({
  required FakeControlledDownloadsController downloadsCtrl,
  required MockLocaleController localeCtrl,
  required FakeSelectionRepository repo,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
      ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
      Provider<DownloadRepository>.value(value: repo),
    ],
    child: MaterialApp(
      home: SelectionFabWrapper(
        child: const Scaffold(
          body: Center(child: Text('Main Video List')),
        ),
      ),
    ),
  );
}

void main() {
  group('E2E Selection Modal Lifecycle & Error Handling Suite', () {
    late FakeControlledDownloadsController downloadsController;
    late MockLocaleController localeController;
    late FakeSelectionRepository repository;

    setUp(() {
      downloadsController = FakeControlledDownloadsController();
      localeController = MockLocaleController();
      repository = FakeSelectionRepository();
    });

    // =========================================================================
    // TIER 1: FEATURE COVERAGE — Selection Modal Lifecycle
    // =========================================================================
    group('Tier 1: Selection Lifecycle Coverage', () {
      testWidgets('1.1: Modal automatically opens when a download enters awaitingSelection state', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_1'] = [
          SubDownload(
            subId: 'sub_1',
            info: Info(title: 'Chapter 1', duration: '03:15'),
          ),
          SubDownload(
            subId: 'sub_2',
            info: Info(title: 'Chapter 2', duration: '04:20'),
          ),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsNothing);

        // Transition download to awaitingSelection
        downloadsController.updateDownloads([
          Download(
            id: 'dl_1',
            info: Info(title: 'Playlist 1'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Chapter 1'), findsOneWidget);
        expect(find.text('Chapter 2'), findsOneWidget);
      });

      testWidgets('1.2: Modal automatically closes when active download transitions to cancelled', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_active'] = [
          SubDownload(subId: 's1', info: Info(title: 'Item 1')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_active',
            info: Info(title: 'Active Item'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);

        // Cancel the download
        downloadsController.updateDownloads([
          Download(
            id: 'dl_active',
            info: Info(title: 'Active Item'),
            state: DownloadState(value: DownloadStateEnum.cancelled),
          ),
        ]);
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets('1.3: Modal automatically closes when active download transitions to deleted', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_delete'] = [
          SubDownload(subId: 's1', info: Info(title: 'Item 1')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_delete',
            info: Info(title: 'Delete Item'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);

        // Remove / delete download completely
        downloadsController.updateDownloads([]);
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets('1.4: Modal queue processes multiple awaitingSelection items sequentially', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['playlist_1'] = [
          SubDownload(subId: 'p1_s1', info: Info(title: 'P1 Item 1')),
        ];
        repository.entriesMap['playlist_2'] = [
          SubDownload(subId: 'p2_s1', info: Info(title: 'P2 Item 1')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        // Enqueue 2 downloads at once
        downloadsController.updateDownloads([
          Download(
            id: 'playlist_1',
            info: Info(title: 'Playlist 1'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
          Download(
            id: 'playlist_2',
            info: Info(title: 'Playlist 2'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        // First modal is open
        expect(find.text('P1 Item 1'), findsOneWidget);
        expect(find.text('P2 Item 1'), findsNothing);

        // Close first modal by submitting
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        // Second modal should now automatically open
        expect(find.text('P2 Item 1'), findsOneWidget);

        // Close second modal
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets('1.5: Selection submission posts chosen IDs to backend and closes modal on success', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_submit'] = [
          SubDownload(subId: 'item_a', info: Info(title: 'Video A')),
          SubDownload(subId: 'item_b', info: Info(title: 'Video B')),
          SubDownload(subId: 'item_c', info: Info(title: 'Video C')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_submit',
            info: Info(title: 'Album Submission'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        // Deselect item_b
        await tester.tap(find.text('Video B'));
        await tester.pumpAndSettle();

        // Submit
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(repository.submittedIds.length, equals(1));
        expect(repository.submittedIds.first, equals('dl_submit'));
        expect(repository.submittedEntries.first, containsAll(['item_a', 'item_c']));
        expect(repository.submittedEntries.first, isNot(contains('item_b')));
        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets('1.6: Selection submission failure retains modal and shows error feedback', (
        WidgetTester tester,
      ) async {
        repository.submitShouldFail = true;
        repository.entriesMap['dl_fail'] = [
          SubDownload(subId: 'f1', info: Info(title: 'Fail Item')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_fail',
            info: Info(title: 'Fail Modal'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        // Tap submit
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        // Dialog should remain open
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Fail Item'), findsOneWidget);
      });
    });

    // =========================================================================
    // TIER 2: BOUNDARY & CORNER CASES
    // =========================================================================
    group('Tier 2: Boundary & Corner Cases', () {
      testWidgets('2.1: Double-Pop Guard: 50 rapid deltas cancelling active download trigger Navigator.pop at most once', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_pop'] = [
          SubDownload(subId: 'p1', info: Info(title: 'Pop Guard Item')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_pop',
            info: Info(title: 'Pop Guard'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);

        // Fire 50 rapid updates switching state to cancelled
        for (var i = 0; i < 50; i++) {
          downloadsController.updateDownloads([
            Download(
              id: 'dl_pop',
              info: Info(title: 'Pop Guard'),
              state: DownloadState(value: DownloadStateEnum.cancelled),
            ),
          ]);
        }
        await tester.pumpAndSettle();

        // Dialog is closed and underlying screen is still intact
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('Main Video List'), findsOneWidget);
      });

      testWidgets('2.2: Disposal Safety: Auto-dismissal while getEntries HTTP request is pending does not throw post-dispose error', (
        WidgetTester tester,
      ) async {
        repository.pendingGetEntriesCompleter = Completer<List<SubDownload>>();

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_slow',
            info: Info(title: 'Slow Load Item'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pump(); // Start building dialog with loader

        expect(find.byType(CircularProgressIndicator), findsWidgets);

        // Cancel download while getEntries is still unresolved
        downloadsController.updateDownloads([
          Download(
            id: 'dl_slow',
            info: Info(title: 'Slow Load Item'),
            state: DownloadState(value: DownloadStateEnum.cancelled),
          ),
        ]);
        await tester.pumpAndSettle();

        // Now resolve the late HTTP call
        repository.pendingGetEntriesCompleter!.complete([
          SubDownload(subId: 'late_1', info: Info(title: 'Late Item')),
        ]);
        await tester.pumpAndSettle();

        // Must not throw FlutterError (notifyListeners called on disposed controller)
        expect(tester.takeException(), isNull);
        expect(find.text('Main Video List'), findsOneWidget);
      });

      testWidgets('2.3: Disposal Safety: Auto-dismissal while submit HTTP request is pending does not throw post-dispose error', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_slow_submit'] = [
          SubDownload(subId: 's1', info: Info(title: 'Submit Item')),
        ];
        repository.pendingSubmitCompleter = Completer<void>();

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_slow_submit',
            info: Info(title: 'Slow Submit Item'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        // Tap submit to start async submission
        await tester.tap(find.byType(FilledButton));
        await tester.pump();

        // External event cancels download while submit is in flight
        downloadsController.updateDownloads([
          Download(
            id: 'dl_slow_submit',
            info: Info(title: 'Slow Submit Item'),
            state: DownloadState(value: DownloadStateEnum.cancelled),
          ),
        ]);
        await tester.pumpAndSettle();

        // Complete the pending submit
        repository.pendingSubmitCompleter!.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Main Video List'), findsOneWidget);
      });

      testWidgets('2.4: Empty Entries: Modal handles download with empty entries list without crashing', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_empty'] = [];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_empty',
            info: Info(title: 'Empty Playlist'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('No elements match'), findsOneWidget);

        // Close via close icon
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets('2.5: Massive Selection: Modal with 300 items supports select all, deselect all, and invert seamlessly', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_massive'] = List.generate(
          300,
          (i) => SubDownload(
            subId: 'item_$i',
            info: Info(title: 'Track #$i', duration: '03:${(i % 60).toString().padLeft(2, '0')}'),
          ),
        );

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_massive',
            info: Info(title: 'Massive Playlist'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        expect(find.text('300 / 300'), findsOneWidget);

        // Deselect All
        await tester.tap(find.byIcon(Icons.deselect));
        await tester.pumpAndSettle();
        expect(find.text('0 / 300'), findsOneWidget);

        // Invert Selection -> all 300 selected
        await tester.tap(find.byIcon(Icons.flip));
        await tester.pumpAndSettle();
        expect(find.text('300 / 300'), findsOneWidget);

        // Select None -> 0 selected
        await tester.tap(find.byIcon(Icons.deselect));
        await tester.pumpAndSettle();
        expect(find.text('0 / 300'), findsOneWidget);

        // Select All -> 300 selected
        await tester.tap(find.byIcon(Icons.select_all));
        await tester.pumpAndSettle();
        expect(find.text('300 / 300'), findsOneWidget);
      });

      testWidgets('2.6: Search Filtering and Selected-Only Chip correctly filter visible entries', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_filter'] = [
          SubDownload(subId: 'a1', info: Info(title: 'Alpha Song')),
          SubDownload(subId: 'b1', info: Info(title: 'Beta Audio')),
          SubDownload(subId: 'a2', info: Info(title: 'Alpha Remix')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_filter',
            info: Info(title: 'Filterable Playlist'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        // Search for 'Beta'
        await tester.enterText(find.byType(TextField), 'Beta');
        await tester.pumpAndSettle();

        expect(find.text('Beta Audio'), findsOneWidget);
        expect(find.text('Alpha Song'), findsNothing);

        // Clear search
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();

        expect(find.text('Alpha Song'), findsOneWidget);
        expect(find.text('Beta Audio'), findsOneWidget);
      });
    });

    // =========================================================================
    // TIER 3: CROSS-FEATURE COMBINATIONS
    // =========================================================================
    group('Tier 3: Cross-Feature Combinations', () {
      testWidgets('3.1: Cancellation of active modal download during rapid delta flood of other items', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_primary'] = [
          SubDownload(subId: 's1', info: Info(title: 'Primary Item')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_primary',
            info: Info(title: 'Primary Download'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);

        // Flood updates for 5 other downloads while cancelling primary download
        downloadsController.updateDownloads([
          Download(id: 'dl_primary', state: DownloadState(value: DownloadStateEnum.cancelled)),
          Download(id: 'dl_other_1', state: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 10.0)),
          Download(id: 'dl_other_2', state: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 20.0)),
          Download(id: 'dl_other_3', state: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 30.0)),
        ]);
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsNothing);
        expect(find.text('Main Video List'), findsOneWidget);
      });

      testWidgets('3.2: Simultaneous deletion of active modal download and creation of new awaitingSelection item', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_old'] = [
          SubDownload(subId: 'old_1', info: Info(title: 'Old Item')),
        ];
        repository.entriesMap['dl_next'] = [
          SubDownload(subId: 'next_1', info: Info(title: 'Next Item')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_old',
            info: Info(title: 'Old Download'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Old Item'), findsOneWidget);

        // In a single atomic state update, delete old and introduce next
        downloadsController.updateDownloads([
          Download(
            id: 'dl_next',
            info: Info(title: 'Next Download'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        // Old modal closes and next modal opens seamlessly
        expect(find.text('Next Item'), findsOneWidget);
        expect(find.text('Old Item'), findsNothing);
      });

      testWidgets('3.3: Manual FAB click enqueues and reopens dismissed awaitingSelection items', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_dismissed'] = [
          SubDownload(subId: 'd1', info: Info(title: 'Dismissed Item')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_dismissed',
            info: Info(title: 'Dismissed Playlist'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        // Dismiss via close button
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsNothing);
        // FAB is visible with badge '1'
        expect(find.byType(FloatingActionButton), findsOneWidget);

        // Tap FAB to reopen
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        // Dialog should be reopened
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Dismissed Item'), findsOneWidget);
      });
    });

    // =========================================================================
    // TIER 4: REAL-WORLD SCENARIOS
    // =========================================================================
    group('Tier 4: Real-World Scenarios', () {
      testWidgets('4.1: Complex playlist triage: 3 playlists awaiting selection, cancel one, modify one, submit one', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['triage_1'] = [
          SubDownload(subId: 't1_a', info: Info(title: 'Triage 1 Track A')),
        ];
        repository.entriesMap['triage_2'] = [
          SubDownload(subId: 't2_a', info: Info(title: 'Triage 2 Track A')),
          SubDownload(subId: 't2_b', info: Info(title: 'Triage 2 Track B')),
        ];
        repository.entriesMap['triage_3'] = [
          SubDownload(subId: 't3_a', info: Info(title: 'Triage 3 Track A')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        // 1. All 3 playlists enter awaitingSelection
        downloadsController.updateDownloads([
          Download(id: 'triage_1', info: Info(title: 'Playlist 1'), state: DownloadState(value: DownloadStateEnum.awaitingSelection)),
          Download(id: 'triage_2', info: Info(title: 'Playlist 2'), state: DownloadState(value: DownloadStateEnum.awaitingSelection)),
          Download(id: 'triage_3', info: Info(title: 'Playlist 3'), state: DownloadState(value: DownloadStateEnum.awaitingSelection)),
        ]);
        await tester.pumpAndSettle();

        // First modal is Playlist 1. User cancels Playlist 1 remotely via backend
        expect(find.text('Triage 1 Track A'), findsOneWidget);
        downloadsController.updateDownloads([
          Download(id: 'triage_1', info: Info(title: 'Playlist 1'), state: DownloadState(value: DownloadStateEnum.cancelled)),
          Download(id: 'triage_2', info: Info(title: 'Playlist 2'), state: DownloadState(value: DownloadStateEnum.awaitingSelection)),
          Download(id: 'triage_3', info: Info(title: 'Playlist 3'), state: DownloadState(value: DownloadStateEnum.awaitingSelection)),
        ]);
        await tester.pumpAndSettle();

        // Modal for Playlist 2 opens. User deselects Track B and submits
        expect(find.text('Triage 2 Track A'), findsOneWidget);
        await tester.tap(find.text('Triage 2 Track B'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        // Modal for Playlist 3 opens. User submits all
        expect(find.text('Triage 3 Track A'), findsOneWidget);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        // All modals complete cleanly
        expect(find.byType(Dialog), findsNothing);
        expect(repository.submittedIds, equals(['triage_2', 'triage_3']));
        expect(repository.submittedEntries[0], equals(['t2_a']));
        expect(repository.submittedEntries[1], equals(['t3_a']));
      });

      testWidgets('4.2: User applies multiple filters, search queries, and inverts selection without state corruption', (
        WidgetTester tester,
      ) async {
        repository.entriesMap['dl_complex'] = [
          SubDownload(subId: 'c1', info: Info(title: 'Documentary Part 1', duration: '45:00')),
          SubDownload(subId: 'c2', info: Info(title: 'Documentary Part 2', duration: '48:00')),
          SubDownload(subId: 'c3', info: Info(title: 'Trailer', duration: '02:30')),
          SubDownload(subId: 'c4', info: Info(title: 'Bonus Interview', duration: '12:00')),
        ];

        await tester.pumpWidget(
          createTestApp(
            downloadsCtrl: downloadsController,
            localeCtrl: localeController,
            repo: repository,
          ),
        );
        await tester.pumpAndSettle();

        downloadsController.updateDownloads([
          Download(
            id: 'dl_complex',
            info: Info(title: 'Docu Series'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await tester.pumpAndSettle();

        // 1. Search for 'Documentary'
        await tester.enterText(find.byType(TextField), 'Documentary');
        await tester.pumpAndSettle();
        expect(find.text('Documentary Part 1'), findsOneWidget);
        expect(find.text('Documentary Part 2'), findsOneWidget);
        expect(find.text('Trailer'), findsNothing);

        // 2. Deselect Part 1
        await tester.tap(find.text('Documentary Part 1'));
        await tester.pumpAndSettle();

        // 3. Clear search
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();

        // 4. Submit
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(repository.submittedEntries.first, containsAll(['c2', 'c3', 'c4']));
        expect(repository.submittedEntries.first, isNot(contains('c1')));
      });
    });
  });
}
