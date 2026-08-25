import 'dart:async';
import 'dart:io';
import 'dart:math';
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
import 'package:vidra/shared/widgets/inline_time_picker.dart';
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
    return _storage[localeCode] ?? _storage['en'] ?? {};
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

Widget createCutVideoModalApp({
  required SettingsController settingsController,
  required LocaleController localeController,
  Widget? child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
      ),
      ChangeNotifierProvider<LocaleController>.value(value: localeController),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder:
              (ctx) =>
                  child ??
                  Center(
                    child: ElevatedButton(
                      onPressed: () => CutVideoBottomSheet.show(ctx),
                      child: const Text('Open Cut Video Sheet'),
                    ),
                  ),
        ),
      ),
    ),
  );
}

Widget createDownloadsScreenApp({
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

Future<void> pumpDownloadsScreen(WidgetTester tester, Widget app) async {
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
      'has_seen_settings_tutorial': true,
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

  group('CutVideoBottomSheet — Rapid Multi-State Toggling Stress', () {
    testWidgets('Rapid 30x master cutVideo toggle stress test retains valid state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createCutVideoModalApp(
          settingsController: settingsController,
          localeController: localeController,
          child: const CutVideoBottomSheet(),
        ),
      );
      await tester.pumpAndSettle();

      final masterSwitchFinder = find.widgetWithText(
        SwitchListTile,
        localeController.localeStrings.sCutVideo,
      );
      expect(masterSwitchFinder, findsOneWidget);

      for (int i = 0; i < 30; i++) {
        await tester.tap(masterSwitchFinder);
        await tester.pump();
        final expected = (i % 2 == 0);
        expect(settingsController.downloadOptions.cutVideo, equals(expected));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rapid 30x UntilEnd toggle stress test while cutVideo is enabled', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(cutVideo: true, cutVideoUntilEnd: true),
      );

      await tester.pumpWidget(
        createCutVideoModalApp(
          settingsController: settingsController,
          localeController: localeController,
          child: const CutVideoBottomSheet(),
        ),
      );
      await tester.pumpAndSettle();

      final untilEndSwitchFinder = find.widgetWithText(
        SwitchListTile,
        localeController.localeStrings.sCutVideoUntilEnd,
      );
      expect(untilEndSwitchFinder, findsOneWidget);

      for (int i = 0; i < 30; i++) {
        await tester.tap(untilEndSwitchFinder);
        await tester.pump();
        final expected = (i % 2 != 0);
        expect(settingsController.downloadOptions.cutVideoUntilEnd, equals(expected));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Interleaved chaotic state fuzz test: toggling cutVideo, untilEnd, and modifying times', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createCutVideoModalApp(
          settingsController: settingsController,
          localeController: localeController,
          child: const CutVideoBottomSheet(),
        ),
      );
      await tester.pumpAndSettle();

      final random = Random(42);
      for (int step = 0; step < 40; step++) {
        final action = random.nextInt(4);
        switch (action) {
          case 0:
            final nextVal = !settingsController.downloadOptions.cutVideo;
            settingsController.updateDownloadOptions(
              settingsController.downloadOptions.copyWith(cutVideo: nextVal),
            );
            break;
          case 1:
            final nextVal = !settingsController.downloadOptions.cutVideoUntilEnd;
            settingsController.updateDownloadOptions(
              settingsController.downloadOptions.copyWith(cutVideoUntilEnd: nextVal),
            );
            break;
          case 2:
            final startSec = random.nextInt(3600);
            settingsController.updateDownloadOptions(
              settingsController.downloadOptions.copyWith(cutVideoStart: startSec),
            );
            break;
          case 3:
            final endSec = random.nextInt(7200);
            settingsController.updateDownloadOptions(
              settingsController.downloadOptions.copyWith(cutVideoEnd: endSec),
            );
            break;
        }
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('CutVideoBottomSheet — Multi-Viewport Matrix (320x568 to 1400x900)', () {
    const viewports = [
      Size(320, 568),
      Size(568, 320),
      Size(360, 640),
      Size(640, 360),
      Size(412, 915),
      Size(768, 1024),
      Size(1024, 768),
      Size(1280, 720),
      Size(1400, 900),
    ];

    for (final vp in viewports) {
      testWidgets('Renders fully expanded CutVideoBottomSheet without overflow on ${vp.width.toInt()}x${vp.height.toInt()}', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = vp;
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
              SponsorblockCategory.outro,
            ],
            cutVideo: true,
            cutVideoUntilEnd: false,
            cutVideoStart: 65,
            cutVideoEnd: 360,
          ),
        );

        await tester.pumpWidget(
          createCutVideoModalApp(
            settingsController: settingsController,
            localeController: localeController,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Cut Video Sheet'));
        await tester.pumpAndSettle();

        expect(find.byType(CutVideoBottomSheet), findsOneWidget);
        expect(find.byType(InlineTimePicker), findsNWidgets(2));
        expect(find.byType(LazyList), findsOneWidget);

        final scrollableFinder = find.descendant(
          of: find.byType(CutVideoBottomSheet),
          matching: find.byType(SingleChildScrollView),
        );
        expect(scrollableFinder, findsOneWidget);

        await tester.drag(scrollableFinder, const Offset(0, -200));
        await tester.pumpAndSettle();
        await tester.drag(scrollableFinder, const Offset(0, 200));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('CutVideoBottomSheet enforces max width constraint 640 on 1400px wide display', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createCutVideoModalApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Cut Video Sheet'));
      await tester.pumpAndSettle();

      final sheetBoxFinder = find.descendant(
        of: find.byType(CutVideoBottomSheet),
        matching: find.byType(ConstrainedBox),
      );
      final boxes = tester.widgetList<ConstrainedBox>(sheetBoxFinder);
      final maxWidth640 = boxes.where((cb) => cb.constraints.maxWidth == 640);
      expect(maxWidth640, isNotEmpty);
    });
  });

  group('CutVideoBottomSheet — Runtime Dynamic Locale Switch', () {
    testWidgets('Live dynamic locale switch EN <-> ES updates all labels without modal recreation', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cutVideo: true,
          cutVideoUntilEnd: false,
          cutVideoStart: 30,
          cutVideoEnd: 90,
        ),
      );

      await tester.pumpWidget(
        createCutVideoModalApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Cut Video Sheet'));
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.cvTitle), findsWidgets);
      expect(find.text(localeController.localeStrings.sCutVideoStart), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoEnd), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoUntilEnd), findsOneWidget);

      // Switch to Spanish at runtime
      localeController.setLocale('es');
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.cvTitle), findsWidgets);
      expect(find.text(localeController.localeStrings.sCutVideoStart), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoEnd), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoUntilEnd), findsOneWidget);

      // Switch back to English at runtime
      localeController.setLocale('en');
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.cvTitle), findsWidgets);
      expect(find.text(localeController.localeStrings.sCutVideoStart), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoEnd), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('DownloadsScreen FAB Badge — Dynamic Count Transitions (0->1->2->1->0->2)', () {
    testWidgets('Complete state transition sequence 0 -> 1 -> 2 -> 1 -> 0 -> 2 -> 0', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [],
          cutVideo: false,
        ),
      );

      await pumpDownloadsScreen(
        tester,
        createDownloadsScreenApp(
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

      // Step 0: Count = 0 -> hidden
      Badge badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isFalse);

      // Step 1: Add SponsorBlock -> Count = 1 -> Badge visible '1'
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [SponsorblockCategory.sponsor],
        ),
      );
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);

      // Step 2: Add multiple SB categories -> Count remains 1 -> Badge visible '1'
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
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);

      // Step 3: Enable cutVideo -> Count = 2 -> Badge visible '2'
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cutVideo: true,
        ),
      );
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(find.descendant(of: badgeFinder, matching: find.text('2')), findsOneWidget);

      // Step 4: Clear SponsorBlock -> Count = 1 (cutVideo only) -> Badge visible '1'
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [],
        ),
      );
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(find.descendant(of: badgeFinder, matching: find.text('1')), findsOneWidget);

      // Step 5: Disable cutVideo -> Count = 0 -> Badge hidden
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cutVideo: false,
        ),
      );
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isFalse);

      // Step 6: Directly activate both SB and cutVideo -> Count = 2 -> Badge visible '2'
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [SponsorblockCategory.preview],
          cutVideo: true,
        ),
      );
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect(find.descendant(of: badgeFinder, matching: find.text('2')), findsOneWidget);

      // Step 7: Clear both -> Count = 0 -> Badge hidden
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [],
          cutVideo: false,
        ),
      );
      await tester.pumpAndSettle();
      badge = tester.widget(badgeFinder);
      expect(badge.isLabelVisible, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Randomized 60-transition state fuzzing on DownloadsScreen FAB badge count', (
      WidgetTester tester,
    ) async {
      await pumpDownloadsScreen(
        tester,
        createDownloadsScreenApp(
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

      final random = Random(12345);
      for (int i = 0; i < 60; i++) {
        final hasSb = random.nextBool();
        final hasCut = random.nextBool();

        final sbList = hasSb
            ? [SponsorblockCategory.sponsor, SponsorblockCategory.intro]
            : <SponsorblockCategory>[];

        settingsController.updateDownloadOptions(
          settingsController.downloadOptions.copyWith(
            sponsorblockRemove: sbList,
            cutVideo: hasCut,
          ),
        );
        await tester.pump();

        final activeCount = (hasSb ? 1 : 0) + (hasCut ? 1 : 0);
        final Badge badge = tester.widget(badgeFinder);

        if (activeCount == 0) {
          expect(badge.isLabelVisible, isFalse);
        } else {
          expect(badge.isLabelVisible, isTrue);
          expect(
            find.descendant(of: badgeFinder, matching: find.text('$activeCount')),
            findsOneWidget,
          );
        }
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('DownloadsScreen — Multi-Viewport FAB Row Layout Matrix (320x568 to 1400x900)', () {
    const viewports = [
      Size(320, 568),
      Size(360, 640),
      Size(480, 800),
      Size(800, 1280),
      Size(1400, 900),
    ];

    for (final size in viewports) {
      testWidgets('Renders all 3 FABs without RenderFlex overflow on viewport ${size.width.toInt()}x${size.height.toInt()} with active count 2', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        settingsController.updateDownloadOptions(
          settingsController.downloadOptions.copyWith(
            sponsorblockRemove: [SponsorblockCategory.sponsor],
            cutVideo: true,
          ),
        );

        await pumpDownloadsScreen(
          tester,
          createDownloadsScreenApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final cutFab = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'cut_video_fab',
        );
        final qsFab = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        final dlFab = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );

        expect(cutFab, findsOneWidget);
        expect(qsFab, findsOneWidget);
        expect(dlFab, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('DownloadsScreen FAB tooltip updates immediately on live locale switch EN <-> ES', (
      WidgetTester tester,
    ) async {
      await pumpDownloadsScreen(
        tester,
        createDownloadsScreenApp(
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
      FloatingActionButton cutFab = tester.widget(cutFabFinder);
      expect(cutFab.tooltip, equals('Cut Video'));

      // Switch to ES
      localeController.setLocale('es');
      await tester.pumpAndSettle();

      cutFab = tester.widget(cutFabFinder);
      expect(cutFab.tooltip, equals('Cortar vídeo'));

      // Switch back to EN
      localeController.setLocale('en');
      await tester.pumpAndSettle();

      cutFab = tester.widget(cutFabFinder);
      expect(cutFab.tooltip, equals('Cut Video'));
      expect(tester.takeException(), isNull);
    });
  });
}
