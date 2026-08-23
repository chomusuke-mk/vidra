import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/core/theme/app_theme.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/presentation/downloads_screen.dart';
import 'package:vidra/features/downloads/presentation/widgets/quick_settings_bottom_sheet.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/utils/tutorial_utils.dart';
import 'package:vidra/shared/widgets/download_card.dart';

class ChallengerLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  ChallengerLocaleRepository() {
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

class ChallengerSystemController extends ChangeNotifier
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
  String? get backendToken => 'challenger_token';

  @override
  String? get serverLogsFilePath => '/tmp/challenger.log';

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

class ChallengerUpdateController extends ChangeNotifier
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

class ChallengerDownloadRepository extends DownloadRepository {
  List<Download> initialDownloads;
  final StreamController<List<Delta>> _deltaController =
      StreamController<List<Delta>>.broadcast();

  ChallengerDownloadRepository({
    this.initialDownloads = const [],
  }) : super(
          VidraHttpClient(baseUrl: 'http://127.0.0.1:5000', defaultHeaders: {}),
        );

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

Widget buildTestApp({
  required DownloadsController downloadsController,
  required SettingsController settingsController,
  required LocaleController localeController,
  required ChallengerSystemController systemController,
  required ChallengerUpdateController updateController,
  required ChallengerDownloadRepository downloadRepository,
  required SharedPreferences sharedPreferences,
  ThemeMode themeMode = ThemeMode.light,
  double textScaleFactor = 1.0,
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
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: child!,
        );
      },
      home: const DownloadsScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChallengerLocaleRepository mockLocaleRepo;
  late LocaleController localeControllerEn;
  late LocaleController localeControllerEs;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late ChallengerSystemController systemController;
  late ChallengerUpdateController updateController;
  late ChallengerDownloadRepository downloadRepo;
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

    mockLocaleRepo = ChallengerLocaleRepository();
    localeControllerEn = LocaleController(mockLocaleRepo, 'en');
    await localeControllerEn.whenReady;

    localeControllerEs = LocaleController(mockLocaleRepo, 'es');
    await localeControllerEs.whenReady;

    systemController = ChallengerSystemController();
    updateController = ChallengerUpdateController();
    downloadRepo = ChallengerDownloadRepository();
    downloadsController = DownloadsController(downloadRepo, systemController);
  });

  tearDown(() {
    downloadRepo.dispose();
  });

  group('CHALLENGER SUITE 1: Comprehensive Viewport Matrix & Dual FAB Persistence', () {
    const fullViewportMatrix = <String, Size>{
      '320x568 (Ultra-Narrow Mobile / iPhone SE 1)': Size(320, 568),
      '360x640 (Compact Android Mobile)': Size(360, 640),
      '480x800 (Mid-Size Mobile / WVGA)': Size(480, 800),
      '800x1280 (Tablet Portrait / WXGA)': Size(800, 1280),
      '1400x900 (Desktop Widescreen / Laptop)': Size(1400, 900),
      '3840x2160 (4K UHD Extreme Desktop)': Size(3840, 2160),
    };

    for (final entry in fullViewportMatrix.entries) {
      final name = entry.key;
      final size = entry.value;

      testWidgets('Viewport $name (EN): Dual FAB strict presence, geometry, and full interactability', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeControllerEn,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
            themeMode: ThemeMode.dark,
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Layout/rendering exception at viewport $name');

        // 1. Verify Quick Settings FAB
        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        expect(qsFabFinder, findsOneWidget, reason: 'quick_settings_fab must exist on $name');

        // 2. Verify Download FAB (extended)
        final dlFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );
        expect(dlFabFinder, findsOneWidget, reason: 'download_fab must exist on $name');

        // 3. Verify Download FAB contains Download text in English
        expect(find.text('Download'), findsOneWidget);

        // 4. Verify no miniature FAB exists
        expect(
          find.byWidgetPredicate((w) => w is FloatingActionButton && w.mini == true),
          findsNothing,
          reason: 'No FloatingActionButton.small / mini should exist on $name',
        );

        // 5. Geometry & Bounds check
        final qsRect = tester.getRect(qsFabFinder);
        final dlRect = tester.getRect(dlFabFinder);

        expect(qsRect.width, closeTo(56.0, 0.01));
        expect(qsRect.height, closeTo(56.0, 0.01));
        expect(dlRect.height, closeTo(56.0, 0.01));
        expect(dlRect.width, greaterThan(56.0), reason: 'Download FAB must be extended');

        // Quick Settings must be to the left of Download FAB
        expect(qsRect.right, lessThan(dlRect.left));
        expect(dlRect.left - qsRect.right, closeTo(12.0, 0.01));

        // Both FABs must fit inside the viewport boundaries
        expect(qsRect.left, greaterThanOrEqualTo(0.0), reason: 'Quick Settings FAB left bound out of screen');
        expect(dlRect.right, lessThanOrEqualTo(size.width), reason: 'Download FAB right bound out of screen');
        expect(qsRect.top, greaterThanOrEqualTo(0.0));
        expect(dlRect.bottom, lessThanOrEqualTo(size.height));

        // 6. Test Interactability: Quick Settings FAB opens BottomSheet
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();

        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget, reason: 'QuickSettingsBottomSheet should open upon tapping QS FAB on $name');
        expect(tester.takeException(), isNull);

        // Close BottomSheet
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);

        // 7. Test Interactability: Download FAB triggers add download
        final urlInput = find.byType(TextField).first;
        await tester.enterText(urlInput, 'https://youtube.com/watch?v=stress_test');
        await tester.pumpAndSettle();

        await tester.tap(dlFabFinder);
        await tester.pumpAndSettle();

        expect(systemController.enqueuedDownloads, isNotEmpty);
        expect(systemController.enqueuedDownloads.last['url'], equals('https://youtube.com/watch?v=stress_test'));
      });

      testWidgets('Viewport $name (ES): Dual FAB presence with Spanish text ("Descargar")', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeControllerEs,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
            themeMode: ThemeMode.light,
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        final dlFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );

        expect(qsFabFinder, findsOneWidget);
        expect(dlFabFinder, findsOneWidget);
        expect(find.text('Descargar'), findsOneWidget, reason: 'Spanish label "Descargar" must be rendered');

        final qsRect = tester.getRect(qsFabFinder);
        final dlRect = tester.getRect(dlFabFinder);

        expect(qsRect.left, greaterThanOrEqualTo(0.0));
        expect(dlRect.right, lessThanOrEqualTo(size.width));
        expect(dlRect.left - qsRect.right, closeTo(12.0, 0.01));
      });
    }
  });

  group('CHALLENGER SUITE 2: Dynamic Text Scaling (1.0x -> 2.0x) on 320dp Ultra-Narrow Width', () {
    const scales = [1.0, 1.25, 1.5, 1.75, 2.0];

    final sampleDownloads = [
      Download(
        id: 'dl_active_1',
        state: DownloadState(
          value: DownloadStateEnum.inProgress,
          progressValue: 0.65,
          progressLabel: '65%',
          speed: '12.4 MB/s',
          timeLeft: '00:45',
        ),
        info: Info(
          url: 'https://youtube.com/watch?v=sample1',
          title: 'Very Long Video Title That Might Cause RenderFlex Overflow On Constrained Screens Under Dynamic Text Scaling',
          autor: 'Content Creator Long Name Channel',
          platform: 'YouTube',
          duration: '01:00:00',
        ),
      ),
      Download(
        id: 'dl_error_1',
        state: DownloadState(
          value: DownloadStateEnum.failed,
          errorMessage: 'HTTP Error 403 Forbidden: Content is geo-blocked or restricted',
        ),
        info: Info(
          url: 'https://youtube.com/watch?v=sample2',
          title: 'Failed Download With Long Error Message And Metadata Pills',
          autor: 'Another Creator',
          platform: 'Vimeo',
        ),
      ),
      Download(
        id: 'dl_completed_1',
        state: DownloadState(
          value: DownloadStateEnum.completed,
          progressValue: 1.0,
          progressLabel: '100%',
        ),
        info: Info(
          url: 'https://youtube.com/watch?v=sample3',
          title: 'Completed Download With File Details Ready For Playback',
          autor: 'Educational Series',
          platform: 'YouTube',
        ),
      ),
    ];

    for (final scale in scales) {
      testWidgets('Scale factor ${scale}x on 320x568 viewport: Zero RenderFlex overflows with active download cards and filter bar', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        downloadRepo.initialDownloads = sampleDownloads;
        downloadsController = DownloadsController(downloadRepo, systemController);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrint('FULL FLUTTER ERROR:\n${details.toString()}');
          originalOnError?.call(details);
        };
        addTearDown(() {
          FlutterError.onError = originalOnError;
        });

        await tester.pumpWidget(
          buildTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeControllerEn,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
            textScaleFactor: scale,
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        final ex = tester.takeException();
        if (ex != null) {
          debugPrint('DEBUG EXCEPTION at ${scale}x: $ex');
        }
        expect(ex, isNull, reason: 'RenderFlex overflow or layout crash at ${scale}x scale');

        // Verify DownloadCard widgets are rendered
        expect(find.byType(DownloadCard), findsWidgets);

        // 1. Toggle filter bar open
        final filterButton = find.byKey(AppTutorialKeys.mainFilter);
        await tester.tap(filterButton);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'RenderFlex overflow when filter bar opened at ${scale}x scale');

        // Type in filter search
        final searchField = find.byType(TextField).at(1);
        await tester.enterText(searchField, 'Video');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // 2. Switch tabs across TabBar
        final inProgressTab = find.text('In progress');
        if (inProgressTab.evaluate().isNotEmpty) {
          await tester.tap(inProgressTab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Exception switching to In Progress tab at ${scale}x scale');
        }

        final completedTab = find.text('Completed');
        if (completedTab.evaluate().isNotEmpty) {
          await tester.tap(completedTab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Exception switching to Completed tab at ${scale}x scale');
        }

        final errorsTab = find.text('Error');
        if (errorsTab.evaluate().isNotEmpty) {
          await tester.tap(errorsTab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Exception switching to Error tab at ${scale}x scale');
        }

        // 3. Verify Dual FAB is interactable at scale
        final qsFab = find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab');
        expect(qsFab, findsOneWidget);

        await tester.tap(qsFab);
        await tester.pumpAndSettle();

        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Exception opening QuickSettingsBottomSheet at ${scale}x scale');

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('CHALLENGER SUITE 3: Adversarial Edge Cases & Hostile Layout Scenarios', () {
    testWidgets('Extreme Aspect Ratio: Ultra-Wide Banner (2560x400) Desktop Display', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(2560, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeControllerEn,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'download_fab'), findsOneWidget);
    });

    testWidgets('Isolated DownloadCard at 320dp with 2.0x Dynamic Text Scale renders with zero overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final card = DownloadCard(
        downloadId: 'test_card_1',
        info: Info(
          url: 'https://youtube.com/watch?v=sample1',
          title: 'Very Long Video Title That Might Cause RenderFlex Overflow On Constrained Screens Under Dynamic Text Scaling',
          autor: 'Content Creator Long Name Channel',
          platform: 'YouTube',
          duration: '01:00:00',
        ),
        state: DownloadState(
          value: DownloadStateEnum.inProgress,
          progressValue: 0.65,
          progressLabel: '65%',
          speed: '12.4 MB/s',
          timeLeft: '00:45',
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsController),
            ChangeNotifierProvider<LocaleController>.value(value: localeControllerEn),
            ChangeNotifierProvider<SettingsController>.value(value: settingsController),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2.0),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                children: [card],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'Isolated DownloadCard should not overflow at 2.0x text scale');
      expect(find.byType(DownloadCard), findsOneWidget);
    });

    testWidgets('Isolated TabBar & SegmentedButton at 320dp with 2.0x text scale renders with zero overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleController>.value(value: localeControllerEn),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2.0),
              ),
              child: child!,
            ),
            home: DefaultTabController(
              length: 4,
              child: Scaffold(
                appBar: AppBar(
                  bottom: const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'Everything'),
                      Tab(text: 'In progress'),
                      Tab(text: 'Completed'),
                      Tab(text: 'Error'),
                    ],
                  ),
                ),
                body: Container(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('Everything', overflow: TextOverflow.ellipsis)),
                      ButtonSegment(value: 'video', label: Text('Video/Audio', overflow: TextOverflow.ellipsis)),
                      ButtonSegment(value: 'list', label: Text('Playlists', overflow: TextOverflow.ellipsis)),
                    ],
                    selected: const {'all'},
                    onSelectionChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'TabBar and SegmentedButton should not overflow at 2.0x scale');
    });
  });
}
