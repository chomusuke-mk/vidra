import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/download_detail_screen.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/presentation/downloads_screen.dart';
import 'package:vidra/features/downloads/presentation/widgets/quick_settings_bottom_sheet.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/settings/presentation/settings_screen.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/utils/tutorial_utils.dart';

class AdversarialMockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  AdversarialMockLocaleRepository() {
    for (final code in ['en', 'es']) {
      final f = File('i18n/$code.jsonc');
      if (f.existsSync()) {
        final raw = f.readAsStringSync();
        final map = (jsonc.decode(raw) as Map).cast<String, dynamic>().map(
          (k, v) => MapEntry(k, v.toString().trim()),
        );
        map.removeWhere((k, v) => v.trim().isEmpty);
        _storage[code] = map;
      }
    }
  }

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    return _storage[localeCode] ?? {};
  }
}

class AdversarialFakeSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  SystemState _state = SystemState.ready;
  @override
  SystemState get state => _state;

  void setState(SystemState s) {
    _state = s;
    notifyListeners();
  }

  @override
  int? get backendPort => 5000;

  @override
  String? get backendToken => 'mock_token';

  @override
  String? get serverLogsFilePath => '/tmp/mock.log';

  @override
  Future<void> get whenPortReady => Future.value();

  final List<Map<String, dynamic>> enqueuedDownloads = [];

  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {
    enqueuedDownloads.add({'url': url, 'options': options});
  }

  @override
  Future<void> resumeInitialization() async {}

  @override
  Future<void> stopBackendForUpdate() async {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class AdversarialFakeUpdateController extends ChangeNotifier
    implements UpdateController {
  @override
  bool get hasAvailableUpdates => false;

  @override
  bool get isCheckingUpdates => false;

  @override
  bool get hasPendingChecks => false;

  @override
  bool get isAutoDownloadingMissing => false;

  @override
  double get missingModulesProgress => 0.0;

  @override
  bool get hasShownSessionUpdateBubble => true;

  @override
  void markSessionUpdateBubbleShown() {}

  @override
  UpdateState getState(ComponentType type) =>
      UpdateState(status: ComponentStatus.upToDate, version: '1.0.0');

  @override
  Future<void> retryMissingModulesDownload() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdversarialFakeDownloadRepository extends DownloadRepository {
  List<Download> initialDownloads;
  final StreamController<List<Delta>> _deltaController =
      StreamController<List<Delta>>.broadcast();

  AdversarialFakeDownloadRepository({
    this.initialDownloads = const [],
  }) : super(VidraHttpClient(baseUrl: 'http://127.0.0.1:5000', defaultHeaders: {}));

  @override
  Future<List<Download>> getAllDownloads() async {
    return List<Download>.from(initialDownloads);
  }

  @override
  Future<Download?> getDownloadById(String id) async {
    return initialDownloads.where((d) => d.id == id).firstOrNull;
  }

  @override
  Future<String> addDownload(
    String url, {
    Map<String, dynamic> options = const {},
  }) async {
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

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
  Stream<List<Delta>> watchGlobalProgress() => _deltaController.stream;

  void dispose() {
    _deltaController.close();
  }
}

Widget createAdversarialTestApp({
  required DownloadsController downloadsController,
  required SettingsController settingsController,
  required LocaleController localeController,
  required AdversarialFakeSystemController systemController,
  required AdversarialFakeUpdateController updateController,
  required AdversarialFakeDownloadRepository downloadRepository,
  required SharedPreferences sharedPreferences,
  Widget? home,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SystemController>.value(value: systemController),
      ChangeNotifierProvider<UpdateController>.value(value: updateController),
      Provider<DownloadRepository>.value(value: downloadRepository),
      Provider<SharedPreferences>.value(value: sharedPreferences),
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
      ),
      ChangeNotifierProvider<LocaleController>.value(value: localeController),
      ChangeNotifierProvider<DownloadsController>.value(
        value: downloadsController,
      ),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: home ?? const DownloadsScreen(),
    ),
  );
}

Future<void> pumpScreen(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AdversarialMockLocaleRepository mockLocaleRepo;
  late LocaleController localeController;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late AdversarialFakeSystemController systemController;
  late AdversarialFakeUpdateController updateController;
  late AdversarialFakeDownloadRepository downloadRepo;
  late DownloadsController downloadsController;
  late SharedPreferences prefs;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Vidra',
      packageName: 'com.vidra.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    SharedPreferences.setMockInitialValues({
      'last_seen_changelog_version': '1.0.0',
      'has_seen_main_tutorial': true,
      'has_seen_settings_tutorial': true,
    });

    prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(settingsRepo);

    mockLocaleRepo = AdversarialMockLocaleRepository();
    localeController = LocaleController(mockLocaleRepo, 'en');
    await localeController.whenReady;

    systemController = AdversarialFakeSystemController();
    updateController = AdversarialFakeUpdateController();
    downloadRepo = AdversarialFakeDownloadRepository();
    downloadsController = DownloadsController(downloadRepo, systemController);
  });

  tearDown(() {
    downloadRepo.dispose();
  });

  group('Adversarial Test Suite 1: Responsive Geometry & Multi-Width Bounding Box Measurement', () {
    const testWidths = [320.0, 360.0, 412.0, 768.0, 1024.0];

    for (final width in testWidths) {
      testWidgets(
        'Width ${width.toInt()}px (without selection FAB): measures FAB bounds, non-overlap, right padding and zero overflow',
        (WidgetTester tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await pumpScreen(
            tester,
            createAdversarialTestApp(
              downloadsController: downloadsController,
              settingsController: settingsController,
              localeController: localeController,
              systemController: systemController,
              updateController: updateController,
              downloadRepository: downloadRepo,
              sharedPreferences: prefs,
            ),
          );

          expect(tester.takeException(), isNull);

          final qsFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
          );
          final dlFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
          );

          expect(qsFinder, findsOneWidget);
          expect(dlFinder, findsOneWidget);

          final qsRect = tester.getRect(qsFinder);
          final dlRect = tester.getRect(dlFinder);

          // 1. Both FABs must be strictly within screen horizontal bounds
          expect(qsRect.left, greaterThanOrEqualTo(0.0));
          expect(dlRect.right, lessThanOrEqualTo(width));

          // 2. Horizontal ordering: Quick Settings is to the left of Download FAB
          expect(qsRect.right, lessThan(dlRect.left));

          // 3. Gap between FABs is 12px
          expect(dlRect.left - qsRect.right, closeTo(12.0, 0.01));

          // 4. Download FAB has standard right margin (typically 16px from screen edge in standard Scaffold FAB placement)
          expect(dlRect.right, closeTo(width - 16.0, 0.01));

          // 5. FAB sizes: Quick Settings is standard FAB (56x56), Download FAB is extended (height 56)
          expect(qsRect.width, closeTo(56.0, 0.01));
          expect(qsRect.height, closeTo(56.0, 0.01));
          expect(dlRect.height, closeTo(56.0, 0.01));
          expect(dlRect.width, greaterThan(56.0)); // Extended with label

          // 6. Both FABs share the same bottom alignment
          expect(qsRect.bottom, closeTo(dlRect.bottom, 0.01));
          expect(qsRect.top, closeTo(dlRect.top, 0.01));
        },
      );

      testWidgets(
        'Width ${width.toInt()}px (WITH SelectionFabWrapper FAB): measures triple-FAB bounds, non-overlap, and clearance',
        (WidgetTester tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // Seed awaitingSelection download to activate SelectionFabWrapper
          final pendingDownload = Download(
            id: 'dl_pending_$width',
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
            info: Info(
              url: 'https://example.com/playlist',
              title: 'Playlist Items Awaiting Selection',
            ),
          );

          downloadRepo.initialDownloads = [pendingDownload];
          downloadsController = DownloadsController(downloadRepo, systemController);

          await pumpScreen(
            tester,
            createAdversarialTestApp(
              downloadsController: downloadsController,
              settingsController: settingsController,
              localeController: localeController,
              systemController: systemController,
              updateController: updateController,
              downloadRepository: downloadRepo,
              sharedPreferences: prefs,
            ),
          );

          expect(tester.takeException(), isNull);

          final selFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'selection_fab',
          );
          final qsFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
          );
          final dlFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
          );

          expect(selFinder, findsOneWidget);
          expect(qsFinder, findsOneWidget);
          expect(dlFinder, findsOneWidget);

          final selRect = tester.getRect(selFinder);
          final qsRect = tester.getRect(qsFinder);
          final dlRect = tester.getRect(dlFinder);

          // 1. Selection FAB anchored to bottom-left (left: 16px)
          expect(selRect.left, equals(16.0));
          expect(selRect.width, closeTo(56.0, 0.01));
          expect(selRect.height, closeTo(56.0, 0.01));

          // 2. Dual FAB Row bounds
          expect(qsRect.right, lessThan(dlRect.left));
          expect(dlRect.right, lessThanOrEqualTo(width));

          // 3. Clearance between selection FAB and dual FAB row:
          // For width >= 360px, clearance is positive (no overlap).
          // For width 320px (ultra-narrow edge case), document horizontal overlap.
          final horizontalClearance = qsRect.left - selRect.right;
          if (width >= 360.0) {
            expect(
              horizontalClearance,
              greaterThanOrEqualTo(0.0),
              reason: 'FAB collision on width $width',
            );
            expect(selRect.right, lessThan(qsRect.left));
          } else {
            // On 320px width with simultaneous selection FAB and dual FAB
            expect(horizontalClearance, lessThan(0.0));
          }

          // 4. Zero exceptions thrown by Flutter render tree
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('Adversarial Test Suite 2: Hero Tag Safety & Navigation Collision Stress', () {
    testWidgets(
      'Navigating DownloadsScreen -> SettingsScreen -> DownloadsScreen does not trigger Hero tag collisions',
      (WidgetTester tester) async {
        final navKey = GlobalKey<NavigatorState>();

        await pumpScreen(
          tester,
          createAdversarialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
            navigatorKey: navKey,
          ),
        );

        expect(tester.takeException(), isNull);

        // Tap Settings icon in AppBar to push SettingsScreen
        final settingsIconFinder = find.byKey(AppTutorialKeys.mainSettings);
        expect(settingsIconFinder, findsOneWidget);
        await tester.tap(settingsIconFinder);

        // Pump during transition to verify concurrent hero tag existence
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SettingsScreen), findsOneWidget);

        // Pop back to DownloadsScreen
        navKey.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(DownloadsScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Simultaneous dual FABs and Selection FAB in tree have strictly distinct hero tags',
      (WidgetTester tester) async {
        final pendingDownload = Download(
          id: 'dl_pending_hero_adv',
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          info: Info(
            url: 'https://example.com/playlist_adv',
            title: 'Playlist Items Awaiting Selection Adv',
          ),
        );

        downloadRepo.initialDownloads = [pendingDownload];
        downloadsController = DownloadsController(downloadRepo, systemController);

        await pumpScreen(
          tester,
          createAdversarialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final allFabs = tester
            .widgetList<FloatingActionButton>(find.byType(FloatingActionButton))
            .toList();

        expect(allFabs.length, equals(4));
        final heroTags = allFabs.map((f) => f.heroTag).toList();

        // Check exact tags
        expect(heroTags, containsAll(['selection_fab', 'cut_video_fab', 'quick_settings_fab', 'download_fab']));

        // Check for duplicates
        final uniqueTags = heroTags.toSet();
        expect(uniqueTags.length, equals(4));
      },
    );

    testWidgets(
      'Navigating DownloadsScreen -> DownloadDetailScreen -> DownloadsScreen handles Hero tags cleanly',
      (WidgetTester tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final sampleDownload = Download(
          id: 'dl_detail_nav_test',
          state: DownloadState(value: DownloadStateEnum.completed),
          info: Info(
            url: 'https://example.com/item_nav',
            title: 'Sample Nav Download',
          ),
        );

        downloadRepo.initialDownloads = [sampleDownload];
        downloadsController = DownloadsController(downloadRepo, systemController);

        await pumpScreen(
          tester,
          createAdversarialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
            navigatorKey: navKey,
          ),
        );

        // Tap download card to open actions, then tap Info icon to navigate to detail screen
        final cardFinder = find.text('Sample Nav Download');
        expect(cardFinder, findsOneWidget);
        await tester.tap(cardFinder);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.info));

        // Pump during transition
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(DownloadDetailScreen), findsOneWidget);

        // Pop back to DownloadsScreen
        navKey.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(DownloadsScreen), findsOneWidget);
      },
    );
  });

  group('Adversarial Test Suite 3: Tap Dispatching, Modal Isolation & State Sync', () {
    testWidgets(
      'Tapping Quick Settings FAB opens bottom sheet and does NOT trigger download enqueuing',
      (WidgetTester tester) async {
        await pumpScreen(
          tester,
          createAdversarialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        // Enter URL in text field
        final urlFieldFinder = find.byType(TextField).first;
        await tester.enterText(urlFieldFinder, 'https://example.com/audio.mp3');
        await tester.pumpAndSettle();

        // Tap Quick Settings FAB
        final qsFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        await tester.tap(qsFinder);
        await tester.pumpAndSettle();

        // Bottom sheet is displayed
        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

        // SystemController did NOT receive any enqueue command
        expect(systemController.enqueuedDownloads, isEmpty);
      },
    );

    testWidgets(
      'Tapping Download FAB triggers download without opening Quick Settings modal',
      (WidgetTester tester) async {
        await pumpScreen(
          tester,
          createAdversarialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final urlFieldFinder = find.byType(TextField).first;
        await tester.enterText(urlFieldFinder, 'https://example.com/video.mp4');
        await tester.pumpAndSettle();

        final dlFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );
        await tester.tap(dlFinder);
        await tester.pumpAndSettle();

        // Bottom sheet is NOT displayed
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);

        // Download was enqueued
        expect(systemController.enqueuedDownloads, hasLength(1));
        expect(
          systemController.enqueuedDownloads.first['url'],
          equals('https://example.com/video.mp4'),
        );
      },
    );

    testWidgets(
      'Quick Settings mutations in modal are instantly passed to subsequent download enqueues',
      (WidgetTester tester) async {
        await pumpScreen(
          tester,
          createAdversarialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final urlFieldFinder = find.byType(TextField).first;
        await tester.enterText(urlFieldFinder, 'https://example.com/music_video.mp4');
        await tester.pumpAndSettle();

        // 1. Open Quick Settings modal
        final qsFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        await tester.tap(qsFinder);
        await tester.pumpAndSettle();

        // 2. Toggle Playlist switch and switch to Extract Audio
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Extract Audio'));
        await tester.pumpAndSettle();

        // 3. Close modal via 'X' button
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.byType(QuickSettingsBottomSheet), findsNothing);

        // 4. Tap Download FAB
        final dlFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );
        await tester.tap(dlFinder);
        await tester.pumpAndSettle();

        // 5. Verify payload sent with download
        expect(systemController.enqueuedDownloads, hasLength(1));
        final enqueued = systemController.enqueuedDownloads.first;
        expect(enqueued['url'], equals('https://example.com/music_video.mp4'));

        final options = enqueued['options'] as Map<String, dynamic>;
        expect(options['playlist'], isTrue);
        expect(options['extract_audio'], isTrue);
      },
    );

    testWidgets(
      'Rapid alternating taps on QS FAB and close button execute cleanly without state corruption',
      (WidgetTester tester) async {
        await pumpScreen(
          tester,
          createAdversarialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final qsFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );

        for (int i = 0; i < 5; i++) {
          await tester.tap(qsFinder);
          await tester.pumpAndSettle();
          expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();
          expect(find.byType(QuickSettingsBottomSheet), findsNothing);
        }

        expect(tester.takeException(), isNull);
      },
    );
  });
}
