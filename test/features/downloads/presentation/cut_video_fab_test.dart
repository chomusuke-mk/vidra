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
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/presentation/downloads_screen.dart';
import 'package:vidra/features/downloads/presentation/widgets/cut_video_bottom_sheet.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

class MockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  MockLocaleRepository() {
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

class FakeSystemController extends ChangeNotifier
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

class FakeUpdateController extends ChangeNotifier implements UpdateController {
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

class FakeDownloadRepository extends DownloadRepository {
  List<Download> initialDownloads;
  final StreamController<List<Delta>> _deltaController =
      StreamController<List<Delta>>.broadcast();

  FakeDownloadRepository({
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

Widget createTestApp({
  required DownloadsController downloadsController,
  required SettingsController settingsController,
  required LocaleController localeController,
  required FakeSystemController systemController,
  required FakeUpdateController updateController,
  required FakeDownloadRepository downloadRepository,
  required SharedPreferences sharedPreferences,
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
    child: const MaterialApp(
      home: DownloadsScreen(),
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

  late MockLocaleRepository mockLocaleRepo;
  late LocaleController localeController;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late FakeSystemController systemController;
  late FakeUpdateController updateController;
  late FakeDownloadRepository downloadRepo;
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
    });

    prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(settingsRepo);

    mockLocaleRepo = MockLocaleRepository();
    localeController = LocaleController(mockLocaleRepo, 'en');
    await localeController.whenReady;

    systemController = FakeSystemController();
    updateController = FakeUpdateController();
    downloadRepo = FakeDownloadRepository();
    downloadsController = DownloadsController(downloadRepo, systemController);
  });

  tearDown(() {
    downloadRepo.dispose();
  });

  group('Cut Video FAB Layout, Position & Hero Tag (Tier 1)', () {
    testWidgets(
      'renders Cut Video FAB immediately to the left of Quick Settings FAB and Download FAB',
      (WidgetTester tester) async {
        await pumpScreen(
          tester,
          createTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final cutFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
        );
        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        final dlFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );

        expect(cutFabFinder, findsOneWidget);
        expect(qsFabFinder, findsOneWidget);
        expect(dlFabFinder, findsOneWidget);

        // Verify scissors icon
        expect(
          find.descendant(
            of: cutFabFinder,
            matching: find.byIcon(Icons.cut_outlined),
          ),
          findsOneWidget,
        );

        // Verify horizontal ordering: cutFab.dx < qsFab.dx < dlFab.dx
        final cutTopLeft = tester.getTopLeft(cutFabFinder);
        final qsTopLeft = tester.getTopLeft(qsFabFinder);
        final dlTopLeft = tester.getTopLeft(dlFabFinder);

        expect(cutTopLeft.dx, lessThan(qsTopLeft.dx));
        expect(qsTopLeft.dx, lessThan(dlTopLeft.dx));
      },
    );

    testWidgets('Cut Video FAB has unique heroTag cut_video_fab', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final fabWidgets = tester
          .widgetList<FloatingActionButton>(find.byType(FloatingActionButton))
          .toList();

      final heroTags = fabWidgets.map((f) => f.heroTag).toList();
      expect(heroTags, contains('cut_video_fab'));
      expect(heroTags.where((t) => t == 'cut_video_fab').length, equals(1));
    });

    testWidgets('Cut Video FAB tooltip resolves localized string in English and Spanish', (
      WidgetTester tester,
    ) async {
      // English
      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final cutFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
      );
      final FloatingActionButton cutFabEn = tester.widget(cutFabFinder);
      expect(cutFabEn.tooltip, equals('Cut Video'));

      // Spanish
      final esLocaleController = LocaleController(mockLocaleRepo, 'es');
      await esLocaleController.whenReady;

      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: esLocaleController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final FloatingActionButton cutFabEs = tester.widget(cutFabFinder);
      expect(cutFabEs.tooltip, equals('Cortar vídeo'));
    });
  });

  group('Dynamic Badge Behavior (Tier 1 & Tier 2)', () {
    testWidgets('Badge is hidden when sponsorblockRemove is empty', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(sponsorblockRemove: []),
      );

      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final badgeFinder = find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
        ),
        matching: find.byType(Badge),
      );
      expect(badgeFinder, findsOneWidget);

      final Badge badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isFalse);
    });

    testWidgets('Badge displays red 1 indicator when sponsorblockRemove has 1 item', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [SponsorblockCategory.sponsor],
        ),
      );

      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final badgeFinder = find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
        ),
        matching: find.byType(Badge),
      );
      expect(badgeFinder, findsOneWidget);

      final Badge badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(badge.backgroundColor, equals(Colors.red));
      expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);
    });

    testWidgets('Badge displays red 1 indicator when sponsorblockRemove has multiple items', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [
            SponsorblockCategory.sponsor,
            SponsorblockCategory.intro,
            SponsorblockCategory.outro,
            SponsorblockCategory.music_offtopic,
          ],
        ),
      );

      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final badgeFinder = find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
        ),
        matching: find.byType(Badge),
      );

      final Badge badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(badge.backgroundColor, equals(Colors.red));
      expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);
    });

    testWidgets('State mutation reactivity: dynamically adding/removing categories shows/hides badge', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final badgeFinder = find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
        ),
        matching: find.byType(Badge),
      );

      // Initially empty -> badge hidden
      Badge badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isFalse);

      // Mutate to 1 category -> badge becomes visible
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [SponsorblockCategory.sponsor],
        ),
      );
      await tester.pumpAndSettle();

      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);

      // Mutate to multiple categories -> badge remains visible
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [
            SponsorblockCategory.sponsor,
            SponsorblockCategory.selfpromo,
          ],
        ),
      );
      await tester.pumpAndSettle();

      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);

      // Clear categories -> badge becomes hidden
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [],
        ),
      );
      await tester.pumpAndSettle();

      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isFalse);
    });

    testWidgets('Badge displays red 1 indicator when only cutVideo is enabled', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [],
          cutVideo: true,
        ),
      );

      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final badgeFinder = find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
        ),
        matching: find.byType(Badge),
      );
      expect(badgeFinder, findsOneWidget);

      final Badge badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(badge.backgroundColor, equals(Colors.red));
      expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);
    });

    testWidgets('Badge displays red 2 indicator when both sponsorblockRemove and cutVideo are active', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [SponsorblockCategory.sponsor],
          cutVideo: true,
        ),
      );

      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final badgeFinder = find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
        ),
        matching: find.byType(Badge),
      );
      expect(badgeFinder, findsOneWidget);

      final Badge badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(badge.backgroundColor, equals(Colors.red));
      expect(find.descendant(of: badgeFinder, matching: find.text('2')), findsOneWidget);
    });

    testWidgets('Badge count updates reactively: 0 -> 1 (SB) -> 2 (SB+Cut) -> 1 (Cut only) -> 0', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [],
          cutVideo: false,
        ),
      );

      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final badgeFinder = find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
        ),
        matching: find.byType(Badge),
      );

      // 0: hidden
      Badge badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isFalse);

      // 1: Add Sponsorblock -> '1'
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [SponsorblockCategory.intro],
        ),
      );
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);

      // 2: Enable cutVideo -> '2'
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cutVideo: true,
        ),
      );
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(find.descendant(of: badgeFinder, matching: find.text('2')), findsOneWidget);

      // 1: Clear Sponsorblock (cutVideo still true) -> '1'
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [],
        ),
      );
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);

      // 0: Disable cutVideo -> hidden
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cutVideo: false,
        ),
      );
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isFalse);
    });
  });

  group('Cut Video Bottom Sheet Invocation from FAB (Tier 1 & Tier 3)', () {
    testWidgets('tapping Cut Video FAB opens CutVideoBottomSheet', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      expect(find.byType(CutVideoBottomSheet), findsNothing);

      final cutFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
      );
      await tester.tap(cutFabFinder);
      await tester.pumpAndSettle();

      expect(find.byType(CutVideoBottomSheet), findsOneWidget);
      expect(find.text(localeController.localeStrings.cvTitle), findsWidgets);

      // Close modal
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(CutVideoBottomSheet), findsNothing);
    });
  });

  group('Responsive Viewport Geometry Matrix (Tier 2 & Tier 4)', () {
    const testViewports = [
      Size(320, 568),
      Size(360, 640),
      Size(480, 800),
      Size(800, 1280),
      Size(1400, 900),
    ];

    for (final size in testViewports) {
      testWidgets('Renders all 3 FABs without RenderFlex overflow on viewport ${size.width.toInt()}x${size.height.toInt()}', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await pumpScreen(
          tester,
          createTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final cutFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
        );
        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        final dlFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );

        expect(cutFabFinder, findsOneWidget);
        expect(qsFabFinder, findsOneWidget);
        expect(dlFabFinder, findsOneWidget);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Coexistence with SelectionFabWrapper on 360px viewport', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final pendingDownload = Download(
        id: 'dl_awaiting_1',
        state: DownloadState(value: DownloadStateEnum.awaitingSelection),
        info: Info(
          url: 'https://example.com/playlist',
          title: 'Awaiting Selection',
        ),
      );

      downloadRepo.initialDownloads = [pendingDownload];
      downloadsController = DownloadsController(downloadRepo, systemController);

      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final selectionFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'selection_fab',
      );
      final cutFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
      );
      final qsFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
      );
      final dlFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
      );

      expect(selectionFabFinder, findsOneWidget);
      expect(cutFabFinder, findsOneWidget);
      expect(qsFabFinder, findsOneWidget);
      expect(dlFabFinder, findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });

  group('Real-World Application Workflows (Tier 4)', () {
    testWidgets('Scenario 1: Cold start -> Empty badge -> Open modal -> Select category -> Close -> Badge appears', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final cutFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
      );
      final badgeFinder = find.ancestor(
        of: cutFabFinder,
        matching: find.byType(Badge),
      );

      // 1. Initially no badge
      expect(tester.widget<Badge>(badgeFinder).isLabelVisible, isFalse);

      // 2. Open Cut Video Modal
      await tester.tap(cutFabFinder);
      await tester.pumpAndSettle();
      expect(find.byType(CutVideoBottomSheet), findsOneWidget);

      // 3. Add 'sponsor' category
      final textFieldFinder = find.descendant(
        of: find.byType(LazyList),
        matching: find.byType(TextField),
      );
      await tester.enterText(textFieldFinder, 'sponsor');
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      // 4. Close modal
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(CutVideoBottomSheet), findsNothing);

      // 5. Badge with '1' is now visible on Cut Video FAB
      expect(tester.widget<Badge>(badgeFinder).isLabelVisible, isTrue);
      expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);
    });

    testWidgets('Scenario 2: Active categories -> Open modal -> Remove all -> Close -> Badge disappears', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [
            SponsorblockCategory.sponsor,
            SponsorblockCategory.intro,
          ],
        ),
      );

      await pumpScreen(
        tester,
        createTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final cutFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
      );
      final badgeFinder = find.ancestor(
        of: cutFabFinder,
        matching: find.byType(Badge),
      );

      // 1. Badge is active
      expect(tester.widget<Badge>(badgeFinder).isLabelVisible, isTrue);

      // 2. Open modal
      await tester.tap(cutFabFinder);
      await tester.pumpAndSettle();
      expect(find.byType(CutVideoBottomSheet), findsOneWidget);

      // 3. Remove both chips
      while (find.byType(InputChip).evaluate().isNotEmpty) {
        final cancelIcon = find.descendant(
          of: find.byType(InputChip),
          matching: find.byIcon(Icons.cancel),
        ).first;
        await tester.tap(cancelIcon);
        await tester.pumpAndSettle();
      }

      // 4. Close modal
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(CutVideoBottomSheet), findsNothing);

      // 5. Badge is now hidden
      expect(tester.widget<Badge>(badgeFinder).isLabelVisible, isFalse);
    });
  });
}
