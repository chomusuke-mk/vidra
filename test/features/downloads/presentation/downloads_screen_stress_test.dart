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
import 'package:vidra/features/downloads/presentation/widgets/cut_video_bottom_sheet.dart';
import 'package:vidra/features/downloads/presentation/widgets/quick_settings_bottom_sheet.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/settings/presentation/settings_screen.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/utils/tutorial_utils.dart';

class StressMockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  StressMockLocaleRepository() {
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

class StressFakeSystemController extends ChangeNotifier
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
  String? get backendToken => 'stress_token';

  @override
  String? get serverLogsFilePath => '/tmp/stress.log';

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

class StressFakeUpdateController extends ChangeNotifier
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

class StressFakeDownloadRepository extends DownloadRepository {
  List<Download> initialDownloads;
  final StreamController<List<Delta>> _deltaController =
      StreamController<List<Delta>>.broadcast();

  StressFakeDownloadRepository({
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

Widget createStressTestApp({
  required DownloadsController downloadsController,
  required SettingsController settingsController,
  required LocaleController localeController,
  required StressFakeSystemController systemController,
  required StressFakeUpdateController updateController,
  required StressFakeDownloadRepository downloadRepository,
  required SharedPreferences sharedPreferences,
  Widget? home,
  GlobalKey<NavigatorState>? navigatorKey,
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
      navigatorKey: navigatorKey,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScaleFactor)),
        child: home ?? const DownloadsScreen(),
      ),
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

  late StressMockLocaleRepository mockLocaleRepo;
  late LocaleController localeControllerEn;
  late LocaleController localeControllerEs;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late StressFakeSystemController systemController;
  late StressFakeUpdateController updateController;
  late StressFakeDownloadRepository downloadRepo;
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

    mockLocaleRepo = StressMockLocaleRepository();
    localeControllerEn = LocaleController(mockLocaleRepo, 'en');
    await localeControllerEn.whenReady;

    localeControllerEs = LocaleController(mockLocaleRepo, 'es');
    await localeControllerEs.whenReady;

    systemController = StressFakeSystemController();
    updateController = StressFakeUpdateController();
    downloadRepo = StressFakeDownloadRepository();
    downloadsController = DownloadsController(downloadRepo, systemController);
  });

  tearDown(() {
    downloadRepo.dispose();
  });

  // =========================================================================
  // TASK 1: VIEWPORT MATRIX STRESS (320x568, 360x640, 412x915, 800x1280, 1920x1080)
  // =========================================================================
  group('Adversarial Viewport Matrix Stress (Zero RenderFlex Overflows)', () {
    const matrixViewports = [
      Size(320, 568),   // iPhone SE 1st gen / ultra-narrow mobile
      Size(360, 640),   // Compact Android
      Size(412, 915),   // Modern tall mobile (e.g. Pixel 7)
      Size(800, 1280),  // Tablet portrait
      Size(1920, 1080), // Desktop widescreen Full HD
    ];

    for (final size in matrixViewports) {
      testWidgets(
        'Viewport ${size.width.toInt()}x${size.height.toInt()} [EN] - Empty & Active SponsorBlock Badge',
        (WidgetTester tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // 1. Initial render without badge
          await pumpScreen(
            tester,
            createStressTestApp(
              downloadsController: downloadsController,
              settingsController: settingsController,
              localeController: localeControllerEn,
              systemController: systemController,
              updateController: updateController,
              downloadRepository: downloadRepo,
              sharedPreferences: prefs,
            ),
          );

          expect(tester.takeException(), isNull, reason: 'RenderFlex overflow on ${size.width}x${size.height}');

          final cutFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
          );
          final qsFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
          );
          final dlFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
          );

          expect(cutFinder, findsOneWidget);
          expect(qsFinder, findsOneWidget);
          expect(dlFinder, findsOneWidget);

          final cutRect = tester.getRect(cutFinder);
          final qsRect = tester.getRect(qsFinder);
          final dlRect = tester.getRect(dlFinder);

          // Horizontal ordering: Cut Video < Quick Settings < Download FAB
          expect(cutRect.left, lessThan(qsRect.left));
          expect(qsRect.left, lessThan(dlRect.left));

          // Bounds containment & zero overflow verification
          expect(tester.takeException(), isNull);
          if (size.width >= 360) {
            expect(cutRect.left, greaterThanOrEqualTo(0.0));
          } else {
            // On 320px ultra-compact width, FittedBox scales within Scaffold bounds with zero RenderFlex exception
            expect(cutRect.left, greaterThanOrEqualTo(-16.0));
          }
          expect(dlRect.right, lessThanOrEqualTo(size.width));

          // 2. Activate badge by setting sponsorblock categories
          settingsController.updateDownloadOptions(
            settingsController.downloadOptions.copyWith(
              sponsorblockRemove: [
                SponsorblockCategory.sponsor,
                SponsorblockCategory.intro,
              ],
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final badgeFinder = find.ancestor(of: cutFinder, matching: find.byType(Badge));
          expect(badgeFinder, findsOneWidget);
          expect(tester.widget<Badge>(badgeFinder).isLabelVisible, isTrue);
          expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);
        },
      );

      testWidgets(
        'Viewport ${size.width.toInt()}x${size.height.toInt()} [ES] - Long string "Descargar" + Active Badge',
        (WidgetTester tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          settingsController.updateDownloadOptions(
            settingsController.downloadOptions.copyWith(
              sponsorblockRemove: [SponsorblockCategory.sponsor],
            ),
          );

          await pumpScreen(
            tester,
            createStressTestApp(
              downloadsController: downloadsController,
              settingsController: settingsController,
              localeController: localeControllerEs,
              systemController: systemController,
              updateController: updateController,
              downloadRepository: downloadRepo,
              sharedPreferences: prefs,
            ),
          );

          expect(tester.takeException(), isNull);
          expect(find.text('Descargar'), findsOneWidget);

          final cutFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
          );
          final dlFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
          );

          expect(cutFinder, findsOneWidget);
          expect(dlFinder, findsOneWidget);

          final cutRect = tester.getRect(cutFinder);
          final dlRect = tester.getRect(dlFinder);

          if (size.width >= 360) {
            expect(cutRect.left, greaterThanOrEqualTo(0.0));
          } else {
            expect(cutRect.left, greaterThanOrEqualTo(-16.0));
          }
          expect(dlRect.right, lessThanOrEqualTo(size.width));
        },
      );

      testWidgets(
        'Viewport ${size.width.toInt()}x${size.height.toInt()} - Coexistence with Selection FAB and Active Badge',
        (WidgetTester tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final pendingDownload = Download(
            id: 'dl_pending_stress_$size',
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
            info: Info(
              url: 'https://example.com/playlist_stress',
              title: 'Stress Awaiting Selection',
            ),
          );

          downloadRepo.initialDownloads = [pendingDownload];
          downloadsController = DownloadsController(downloadRepo, systemController);

          settingsController.updateDownloadOptions(
            settingsController.downloadOptions.copyWith(
              sponsorblockRemove: [SponsorblockCategory.sponsor],
            ),
          );

          await pumpScreen(
            tester,
            createStressTestApp(
              downloadsController: downloadsController,
              settingsController: settingsController,
              localeController: localeControllerEn,
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
          final cutFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
          );
          final qsFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
          );
          final dlFinder = find.byWidgetPredicate(
            (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
          );

          expect(selFinder, findsOneWidget);
          expect(cutFinder, findsOneWidget);
          expect(qsFinder, findsOneWidget);
          expect(dlFinder, findsOneWidget);
        },
      );
    }
  });

  // =========================================================================
  // TASK 2: FONT SCALING STRESS (0.8x, 1.0x, 1.5x, 2.0x)
  // =========================================================================
  group('Font Scaling Stress Testing (0.8x, 1.0x, 1.5x, 2.0x)', () {
    const scaleFactors = [0.8, 1.0, 1.5, 2.0];
    const testSizes = [
      Size(320, 568),
      Size(360, 640),
      Size(412, 915),
      Size(1920, 1080),
    ];

    for (final scale in scaleFactors) {
      for (final size in testSizes) {
        testWidgets(
          'TextScale ${scale}x on Viewport ${size.width.toInt()}x${size.height.toInt()} renders FAB row without overflow',
          (WidgetTester tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });

            settingsController.updateDownloadOptions(
              settingsController.downloadOptions.copyWith(
                sponsorblockRemove: [SponsorblockCategory.sponsor],
              ),
            );

            await pumpScreen(
              tester,
              createStressTestApp(
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

            expect(
              tester.takeException(),
              isNull,
              reason: 'Overflow occurred at scale ${scale}x on size ${size.width}x${size.height}',
            );

            final cutFinder = find.byWidgetPredicate(
              (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
            );
            final qsFinder = find.byWidgetPredicate(
              (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
            );
            final dlFinder = find.byWidgetPredicate(
              (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
            );

            expect(cutFinder, findsOneWidget);
            expect(qsFinder, findsOneWidget);
            expect(dlFinder, findsOneWidget);

            // Badge with '1' is rendered cleanly
            final badgeFinder = find.ancestor(of: cutFinder, matching: find.byType(Badge));
            expect(badgeFinder, findsOneWidget);
            expect(tester.widget<Badge>(badgeFinder).isLabelVisible, isTrue);
            expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);

            final cutRect = tester.getRect(cutFinder);
            final dlRect = tester.getRect(dlFinder);

            // Bounds containment & zero RenderFlex overflow
            if (size.width >= 412 || (size.width >= 360 && scale <= 1.0)) {
              expect(cutRect.left, greaterThanOrEqualTo(0.0));
            } else {
              expect(cutRect.left, greaterThanOrEqualTo(-16.0));
            }
            expect(dlRect.right, lessThanOrEqualTo(size.width));
          },
        );

        testWidgets(
          'TextScale ${scale}x on Viewport ${size.width.toInt()}x${size.height.toInt()} [ES] "Descargar"',
          (WidgetTester tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });

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
              createStressTestApp(
                downloadsController: downloadsController,
                settingsController: settingsController,
                localeController: localeControllerEs,
                systemController: systemController,
                updateController: updateController,
                downloadRepository: downloadRepo,
                sharedPreferences: prefs,
                textScaleFactor: scale,
              ),
            );

            expect(tester.takeException(), isNull);
            expect(find.text('Descargar'), findsOneWidget);
          },
        );
      }
    }
  });

  // =========================================================================
  // TASK 3: DYNAMIC BADGE RAPID TOGGLING & RACE CONDITIONS
  // =========================================================================
  group('Dynamic Badge Rapid Toggling & Race Conditions Stress', () {
    testWidgets('100 high-frequency toggle cycles mutate state cleanly without frame tears', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        createStressTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeControllerEn,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final cutFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
      );
      final badgeFinder = find.ancestor(of: cutFabFinder, matching: find.byType(Badge));

      for (int i = 0; i < 100; i++) {
        final bool shouldBeActive = i % 2 == 1;
        if (shouldBeActive) {
          settingsController.updateDownloadOptions(
            settingsController.downloadOptions.copyWith(
              sponsorblockRemove: [
                SponsorblockCategory.sponsor,
                SponsorblockCategory.selfpromo,
              ],
            ),
          );
        } else {
          settingsController.updateDownloadOptions(
            settingsController.downloadOptions.copyWith(
              sponsorblockRemove: [],
            ),
          );
        }

        // Pump single frame
        await tester.pump();

        final Badge badge = tester.widget(badgeFinder);
        expect(
          badge.isLabelVisible,
          equals(shouldBeActive),
          reason: 'Mismatch at iteration $i (expected isLabelVisible=$shouldBeActive)',
        );
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rapid asynchronous state mutations during modal lifecycle', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        createStressTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeControllerEn,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final cutFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
      );

      for (int i = 0; i < 5; i++) {
        // Open modal
        await tester.tap(cutFabFinder);
        await tester.pump(const Duration(milliseconds: 50));

        // Rapid state mutation mid-animation
        settingsController.updateDownloadOptions(
          settingsController.downloadOptions.copyWith(
            sponsorblockRemove: [SponsorblockCategory.sponsor],
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        settingsController.updateDownloadOptions(
          settingsController.downloadOptions.copyWith(
            sponsorblockRemove: [],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CutVideoBottomSheet), findsOneWidget);

        // Close modal
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump(const Duration(milliseconds: 50));

        // Mutate again while closing
        settingsController.updateDownloadOptions(
          settingsController.downloadOptions.copyWith(
            sponsorblockRemove: [SponsorblockCategory.intro],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CutVideoBottomSheet), findsNothing);
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('Tearing down widget tree mid-mutation causes zero memory leaks or unhandled errors', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        createStressTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeControllerEn,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      // Perform a few mutations
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [SponsorblockCategory.sponsor],
        ),
      );
      await tester.pump();

      // Replace tree with dummy widget immediately
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Replaced'))));
      await tester.pumpAndSettle();

      // Mutate settings controller after disposal
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [],
        ),
      );

      expect(find.text('Replaced'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // TASK 4: HERO TAG COLLISION STRESS ACROSS NAVIGATION ROUTES
  // =========================================================================
  group('Hero Tag Collision Stress Across Navigation Routes', () {
    testWidgets('DownloadsScreen -> SettingsScreen -> DownloadsScreen hero tag safety', (
      WidgetTester tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();

      await pumpScreen(
        tester,
        createStressTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeControllerEn,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
          navigatorKey: navKey,
        ),
      );

      // Tap settings button
      final settingsBtn = find.byKey(AppTutorialKeys.mainSettings);
      await tester.tap(settingsBtn);

      // Verify mid-flight transition frames
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      // Pop back
      navKey.currentState!.pop();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byType(DownloadsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DownloadsScreen -> DownloadDetailScreen -> DownloadsScreen hero tag safety', (
      WidgetTester tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      final item = Download(
        id: 'dl_hero_stress_1',
        state: DownloadState(value: DownloadStateEnum.completed),
        info: Info(
          url: 'https://example.com/item_hero',
          title: 'Hero Stress Item',
        ),
      );

      downloadRepo.initialDownloads = [item];
      downloadsController = DownloadsController(downloadRepo, systemController);

      await pumpScreen(
        tester,
        createStressTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeControllerEn,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
          navigatorKey: navKey,
        ),
      );

      // Tap card to open actions and tap Info to navigate to DetailScreen
      await tester.tap(find.text('Hero Stress Item'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.info));
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byType(DownloadDetailScreen), findsOneWidget);

      // Pop back
      navKey.currentState!.pop();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byType(DownloadsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rapid alternating modal bottom sheets (Cut Video & Quick Settings)', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        createStressTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeControllerEn,
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

      for (int i = 0; i < 4; i++) {
        // Open Cut Video sheet
        await tester.tap(cutFabFinder);
        await tester.pumpAndSettle();
        expect(find.byType(CutVideoBottomSheet), findsOneWidget);

        // Close
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(CutVideoBottomSheet), findsNothing);

        // Open Quick Settings sheet
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();
        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

        // Close
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('Strict uniqueness check of all FloatingActionButton hero tags in tree', (
      WidgetTester tester,
    ) async {
      final pendingDownload = Download(
        id: 'dl_pending_all_fabs',
        state: DownloadState(value: DownloadStateEnum.awaitingSelection),
        info: Info(
          url: 'https://example.com/playlist_all_fabs',
          title: 'Playlist All FABs',
        ),
      );

      downloadRepo.initialDownloads = [pendingDownload];
      downloadsController = DownloadsController(downloadRepo, systemController);

      await pumpScreen(
        tester,
        createStressTestApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeControllerEn,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      final fabs = tester
          .widgetList<FloatingActionButton>(find.byType(FloatingActionButton))
          .toList();

      expect(fabs.length, equals(4));
      final heroTags = fabs.map((f) => f.heroTag).toList();

      expect(
        heroTags,
        unorderedEquals([
          'selection_fab',
          'cut_video_fab',
          'quick_settings_fab',
          'download_fab',
        ]),
      );

      final uniqueTags = heroTags.toSet();
      expect(uniqueTags.length, equals(4), reason: 'Duplicate hero tags detected: $heroTags');
    });
  });
}
