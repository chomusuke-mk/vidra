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

class AdversarialSelectionRepository implements DownloadRepository {
  final Map<String, List<SubDownload>> entriesMap = {};
  Completer<List<SubDownload>>? pendingGetEntriesCompleter;
  Completer<void>? pendingSubmitCompleter;
  bool submitShouldFail = false;
  bool getEntriesShouldFail = false;
  int getEntriesCalls = 0;
  int submitCalls = 0;

  @override
  Future<List<SubDownload>> getEntries(String id) async {
    getEntriesCalls++;
    if (pendingGetEntriesCompleter != null) {
      return pendingGetEntriesCompleter!.future;
    }
    if (getEntriesShouldFail) {
      throw Exception('Simulated backend failure on getEntries');
    }
    return entriesMap[id] ?? [];
  }

  @override
  Future<void> submitSelectedEntries(String id, List<String> entries) async {
    submitCalls++;
    if (pendingSubmitCompleter != null) {
      await pendingSubmitCompleter!.future;
    }
    if (submitShouldFail) {
      throw Exception('Simulated backend failure on submitSelectedEntries');
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

class TrackingNavigatorObserver extends NavigatorObserver {
  int pushedCount = 0;
  int poppedCount = 0;
  final List<Route<dynamic>> routeStack = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedCount++;
    routeStack.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    poppedCount++;
    routeStack.remove(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routeStack.remove(route);
    super.didRemove(route, previousRoute);
  }
}

Widget createAdversarialApp({
  required AdversarialDownloadsController downloadsCtrl,
  required AdversarialLocaleController localeCtrl,
  required AdversarialSelectionRepository repo,
  required TrackingNavigatorObserver observer,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
      ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
      Provider<DownloadRepository>.value(value: repo),
    ],
    child: MaterialApp(
      navigatorObservers: [observer],
      home: SelectionFabWrapper(
        child: const Scaffold(
          body: Center(child: Text('Parent Root Screen: Main Video List')),
        ),
      ),
    ),
  );
}

void main() {
  group('Empirical Adversarial Stress Suite: Milestone 2 Selection Lifecycle', () {
    late AdversarialDownloadsController downloadsController;
    late AdversarialLocaleController localeController;
    late AdversarialSelectionRepository repository;
    late TrackingNavigatorObserver navigatorObserver;

    setUp(() {
      downloadsController = AdversarialDownloadsController();
      localeController = AdversarialLocaleController();
      repository = AdversarialSelectionRepository();
      navigatorObserver = TrackingNavigatorObserver();
    });

    // =========================================================================
    // CHALLENGE 1: 100+ RAPID DELTA CANCELLATION BURSTS & ROUTE POP INTEGRITY
    // =========================================================================
    testWidgets('ADV-1: 100+ rapid cancellation bursts while modal is open never pop parent route', (
      WidgetTester tester,
    ) async {
      repository.entriesMap['dl_burst'] = [
        SubDownload(subId: 'burst_1', info: Info(title: 'Burst Track 1')),
        SubDownload(subId: 'burst_2', info: Info(title: 'Burst Track 2')),
      ];

      await tester.pumpWidget(
        createAdversarialApp(
          downloadsCtrl: downloadsController,
          localeCtrl: localeController,
          repo: repository,
          observer: navigatorObserver,
        ),
      );
      await tester.pumpAndSettle();

      // Initial route: 1 pushed (Root screen)
      expect(navigatorObserver.pushedCount, equals(1));
      expect(navigatorObserver.poppedCount, equals(0));
      expect(navigatorObserver.routeStack.length, equals(1));

      // Open selection modal
      downloadsController.updateDownloads([
        Download(
          id: 'dl_burst',
          info: Info(title: 'Burst Playlist'),
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
        ),
      ]);
      await tester.pumpAndSettle();

      // Modal pushed: 2 pushed, 0 popped, stack size 2
      expect(navigatorObserver.pushedCount, equals(2));
      expect(navigatorObserver.poppedCount, equals(0));
      expect(navigatorObserver.routeStack.length, equals(2));
      expect(find.byType(Dialog), findsOneWidget);

      // STRESS ATTACK: Fire 100 rapid delta updates in tight sync loop switching state
      for (int i = 0; i < 100; i++) {
        downloadsController.updateDownloads([
          Download(
            id: 'dl_burst',
            info: Info(title: 'Burst Playlist'),
            state: DownloadState(
              value: i % 2 == 0
                  ? DownloadStateEnum.cancelled
                  : DownloadStateEnum.deleted,
            ),
          ),
        ]);
      }

      await tester.pumpAndSettle();

      // Dialog closed: exactly 1 pop must have occurred (the dialog), NOT 2 or more
      expect(navigatorObserver.poppedCount, equals(1));
      expect(navigatorObserver.pushedCount, equals(2));
      expect(navigatorObserver.routeStack.length, equals(1));

      // Parent screen must remain mounted and perfectly intact
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Parent Root Screen: Main Video List'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // =========================================================================
    // CHALLENGE 2: ZERO FlutterError ON ASYNC DISPOSAL UNDER HEAVY CONCURRENCY
    // =========================================================================
    testWidgets('ADV-2: Simultaneous pending getEntries + late submit + rapid disposal produces zero FlutterError', (
      WidgetTester tester,
    ) async {
      repository.entriesMap['dl_concur'] = [
        SubDownload(subId: 'c1', info: Info(title: 'Concur Track 1')),
      ];
      repository.pendingGetEntriesCompleter = Completer<List<SubDownload>>();

      await tester.pumpWidget(
        createAdversarialApp(
          downloadsCtrl: downloadsController,
          localeCtrl: localeController,
          repo: repository,
          observer: navigatorObserver,
        ),
      );
      await tester.pumpAndSettle();

      // Trigger modal open with pending network request
      downloadsController.updateDownloads([
        Download(
          id: 'dl_concur',
          info: Info(title: 'Concur Download'),
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
        ),
      ]);
      await tester.pump(); // Render dialog in loading state

      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Force immediate cancellation & removal while getEntries is unresolved
      downloadsController.updateDownloads([
        Download(
          id: 'dl_concur',
          info: Info(title: 'Concur Download'),
          state: DownloadState(value: DownloadStateEnum.cancelled),
        ),
      ]);
      await tester.pumpAndSettle();

      // Modal is unmounted and controller disposed
      expect(find.byType(Dialog), findsNothing);

      // Resolve getEntries late with data
      repository.pendingGetEntriesCompleter!.complete([
        SubDownload(subId: 'late_1', info: Info(title: 'Late Delivered')),
      ]);
      await tester.pumpAndSettle();

      // No exception should have been thrown
      expect(tester.takeException(), isNull);
      expect(find.text('Parent Root Screen: Main Video List'), findsOneWidget);
    });

    // =========================================================================
    // CHALLENGE 3: DIRECT SelectionModalController DISPOSAL STRESS & REENTRANCY
    // =========================================================================
    test('ADV-3: SelectionModalController direct method invocation storm after disposal is 100% crash-free', () async {
      final fakeRepo = AdversarialSelectionRepository();
      fakeRepo.entriesMap['item_1'] = [
        SubDownload(subId: 's1', info: Info(title: 'Track 1')),
        SubDownload(subId: 's2', info: Info(title: 'Track 2')),
      ];

      final download = Download(
        id: 'item_1',
        info: Info(title: 'Playlist 1'),
        state: DownloadState(value: DownloadStateEnum.awaitingSelection),
      );

      final controller = SelectionModalController(fakeRepo, [download]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.allEntries.length, equals(2));
      expect(controller.isDisposed, isFalse);

      // Dispose controller
      controller.dispose();
      expect(controller.isDisposed, isTrue);

      // Stress invoke all public methods on disposed controller: none must throw
      expect(() => controller.notifyListeners(), returnsNormally);
      expect(() => controller.updateSearch('query'), returnsNormally);
      expect(() => controller.toggleShowOnlySelected(), returnsNormally);
      expect(() => controller.toggleSelection('s1'), returnsNormally);
      expect(() => controller.selectAll(), returnsNormally);
      expect(() => controller.selectNone(), returnsNormally);
      expect(() => controller.invertSelection(), returnsNormally);
      expect(() => controller.switchDownload(download), returnsNormally);

      final submitResult = await controller.submit();
      expect(submitResult, isFalse);
    });

    // =========================================================================
    // CHALLENGE 4: QUEUE THRASHING & INTERLEAVED MODAL AUTO-DISMISSALS
    // =========================================================================
    testWidgets('ADV-4: Queue thrashing: 20 playlists alternating awaiting/cancelled/deleted states in rapid sequence', (
      WidgetTester tester,
    ) async {
      for (int i = 0; i < 20; i++) {
        repository.entriesMap['thrash_$i'] = [
          SubDownload(subId: 't_${i}_sub', info: Info(title: 'Thrash Item $i')),
        ];
      }

      await tester.pumpWidget(
        createAdversarialApp(
          downloadsCtrl: downloadsController,
          localeCtrl: localeController,
          repo: repository,
          observer: navigatorObserver,
        ),
      );
      await tester.pumpAndSettle();

      // Enqueue 20 items in awaitingSelection
      downloadsController.updateDownloads(
        List.generate(
          20,
          (i) => Download(
            id: 'thrash_$i',
            info: Info(title: 'Thrash Playlist $i'),
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First modal is visible
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Thrash Item 0'), findsOneWidget);

      // In a flurry of delta updates, cancel all odd-indexed items and complete even-indexed items except #18
      for (int step = 0; step < 10; step++) {
        downloadsController.updateDownloads(
          List.generate(
            20,
            (i) => Download(
              id: 'thrash_$i',
              info: Info(title: 'Thrash Playlist $i'),
              state: DownloadState(
                value: i == 18
                    ? DownloadStateEnum.awaitingSelection
                    : (i % 2 == 1
                        ? DownloadStateEnum.cancelled
                        : DownloadStateEnum.completed),
              ),
            ),
          ),
        );
      }

      await tester.pumpAndSettle();

      // After settling, only item #18 should be presented
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Thrash Item 18'), findsOneWidget);
      expect(find.text('Parent Root Screen: Main Video List'), findsOneWidget);

      // Cancel item #18
      downloadsController.updateDownloads([
        Download(
          id: 'thrash_18',
          state: DownloadState(value: DownloadStateEnum.cancelled),
        ),
      ]);
      await tester.pumpAndSettle();

      // All modals closed, parent route untouched
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Parent Root Screen: Main Video List'), findsOneWidget);
      expect(navigatorObserver.routeStack.length, equals(1));
      expect(tester.takeException(), isNull);
    });

    // =========================================================================
    // CHALLENGE 5: RACE BETWEEN USER SUBMISSION AND EXTERNAL CANCELLATION DELTA
    // =========================================================================
    testWidgets('ADV-5: User taps submit at exact microsecond download is cancelled by backend delta', (
      WidgetTester tester,
    ) async {
      repository.entriesMap['dl_race'] = [
        SubDownload(subId: 'r1', info: Info(title: 'Race Item 1')),
      ];
      repository.pendingSubmitCompleter = Completer<void>();

      await tester.pumpWidget(
        createAdversarialApp(
          downloadsCtrl: downloadsController,
          localeCtrl: localeController,
          repo: repository,
          observer: navigatorObserver,
        ),
      );
      await tester.pumpAndSettle();

      downloadsController.updateDownloads([
        Download(
          id: 'dl_race',
          info: Info(title: 'Race Modal'),
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
        ),
      ]);
      await tester.pumpAndSettle();

      // User initiates submit
      await tester.tap(find.byType(FilledButton));
      await tester.pump(); // Submit is now in-flight

      // Simultaneous backend cancellation delta
      downloadsController.updateDownloads([
        Download(
          id: 'dl_race',
          info: Info(title: 'Race Modal'),
          state: DownloadState(value: DownloadStateEnum.cancelled),
        ),
      ]);
      await tester.pumpAndSettle();

      // Complete backend submit
      repository.pendingSubmitCompleter!.complete();
      await tester.pumpAndSettle();

      // Zero exceptions, root screen stable, stack size 1
      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Parent Root Screen: Main Video List'), findsOneWidget);
      expect(navigatorObserver.routeStack.length, equals(1));
    });

    // =========================================================================
    // CHALLENGE 6: RAPID MULTIPLE TAPS ON CLOSE BUTTON DURING CANCELLATION BURST
    // =========================================================================
    testWidgets('ADV-6: Rapid multi-taps on Close IconButton combined with 50 cancellation deltas', (
      WidgetTester tester,
    ) async {
      repository.entriesMap['dl_tap_storm'] = [
        SubDownload(subId: 'ts1', info: Info(title: 'Tap Storm Item')),
      ];

      await tester.pumpWidget(
        createAdversarialApp(
          downloadsCtrl: downloadsController,
          localeCtrl: localeController,
          repo: repository,
          observer: navigatorObserver,
        ),
      );
      await tester.pumpAndSettle();

      downloadsController.updateDownloads([
        Download(
          id: 'dl_tap_storm',
          info: Info(title: 'Tap Storm'),
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      // Tap close button and synchronously emit 50 cancellation deltas
      await tester.tap(find.byIcon(Icons.close));
      for (int i = 0; i < 50; i++) {
        downloadsController.updateDownloads([
          Download(
            id: 'dl_tap_storm',
            state: DownloadState(value: DownloadStateEnum.cancelled),
          ),
        ]);
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Parent Root Screen: Main Video List'), findsOneWidget);
      expect(navigatorObserver.routeStack.length, equals(1));
    });
  });
}
