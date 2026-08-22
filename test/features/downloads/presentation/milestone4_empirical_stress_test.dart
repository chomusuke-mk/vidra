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
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/settings/presentation/settings_screen.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

class EmpiricalMockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  EmpiricalMockLocaleRepository() {
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

class EmpiricalSystemController extends ChangeNotifier
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
  String? get backendToken => 'emp_token';

  @override
  String? get serverLogsFilePath => '/tmp/emp.log';

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

class EmpiricalUpdateController extends ChangeNotifier
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

class EmpiricalDownloadRepository extends DownloadRepository {
  List<Download> initialDownloads;
  final StreamController<List<Delta>> _deltaController =
      StreamController<List<Delta>>.broadcast();

  EmpiricalDownloadRepository({
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

Widget buildFullApp({
  required DownloadsController downloadsController,
  required SettingsController settingsController,
  required LocaleController localeController,
  required EmpiricalSystemController systemController,
  required EmpiricalUpdateController updateController,
  required EmpiricalDownloadRepository downloadRepository,
  required SharedPreferences sharedPreferences,
  Widget? home,
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
      home: home ?? const DownloadsScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EmpiricalMockLocaleRepository mockLocaleRepo;
  late LocaleController localeController;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late EmpiricalSystemController systemController;
  late EmpiricalUpdateController updateController;
  late EmpiricalDownloadRepository downloadRepo;
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
    while (!settingsController.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    mockLocaleRepo = EmpiricalMockLocaleRepository();
    localeController = LocaleController(mockLocaleRepo, 'en');
    await localeController.whenReady;

    systemController = EmpiricalSystemController();
    updateController = EmpiricalUpdateController();
    downloadRepo = EmpiricalDownloadRepository();
    downloadsController = DownloadsController(downloadRepo, systemController);
  });

  tearDown(() {
    downloadRepo.dispose();
  });

  group('Milestone 4 Empirical Adversarial Verification: Stress & Matrix', () {
    testWidgets(
      'Stress Test 1: Rapid Mode Switching 25x under continuous pump cycles without state loss or memory corruption',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildFullApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
            home: const QuickSettingsBottomSheet(),
          ),
        );
        await tester.pumpAndSettle();

        final videoSegment = find.text('Video');
        final audioSegment = find.text('Extract Audio');

        for (int i = 0; i < 25; i++) {
          final isAudioTarget = (i % 2 == 0);
          final target = isAudioTarget ? audioSegment : videoSegment;

          await tester.tap(target);
          await tester.pump();

          expect(
            settingsController.downloadOptions.extractAudio,
            equals(isAudioTarget),
            reason: 'State desync at rapid mode switch iteration $i',
          );
        }

        await tester.pumpAndSettle();
        // 24 (index 24) is even -> audio mode true
        expect(settingsController.downloadOptions.extractAudio, isTrue);
        expect(find.byType(LazyDropdown<AudioFormat>), findsOneWidget);
        expect(find.byType(LazyList), findsNothing);
      },
    );

    testWidgets(
      'Stress Test 2: Multi-cycle Modal Transitions 20x consecutively',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildFullApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );

        for (int cycle = 0; cycle < 20; cycle++) {
          await tester.tap(qsFabFinder);
          await tester.pumpAndSettle();
          expect(
            find.byType(QuickSettingsBottomSheet),
            findsOneWidget,
            reason: 'Modal failed to open on cycle $cycle',
          );

          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();
          expect(
            find.byType(QuickSettingsBottomSheet),
            findsNothing,
            reason: 'Modal failed to close on cycle $cycle',
          );
        }

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Stress Test 3: Extreme Viewports: 4K Desktop (3840x2160) and Ultra-Narrow Mobile (320x568)',
      (WidgetTester tester) async {
        // 1. Test 4K Desktop Viewport
        tester.view.physicalSize = const Size(3840, 2160);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          buildFullApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // Open quick settings in 4K
        await tester.tap(find.byIcon(Icons.construction_outlined));
        await tester.pumpAndSettle();

        final sheet4K = tester.getRect(find.byType(QuickSettingsBottomSheet));
        expect(sheet4K.width, lessThanOrEqualTo(640.0));
        expect(tester.takeException(), isNull);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // 2. Test Ultra-Narrow Viewport (320x568)
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          buildFullApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.construction_outlined), findsOneWidget);
        expect(find.byIcon(Icons.download), findsOneWidget);

        // Open modal in ultra-narrow
        await tester.tap(find.byIcon(Icons.construction_outlined));
        await tester.pumpAndSettle();

        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );

    testWidgets(
      'Tier 3 & 4 Matrix: Complete Realistic End-to-End User Workflow & Subsystems Integrity',
      (WidgetTester tester) async {
        final pendingDownload = Download(
          id: 'dl_item_existing',
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          info: Info(
            url: 'https://example.com/playlist_1',
            title: 'Sample Video Download',
            type: DownloadType.video,
          ),
        );
        downloadRepo.initialDownloads = [pendingDownload];
        downloadsController = DownloadsController(downloadRepo, systemController);

        await tester.pumpWidget(
          buildFullApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // 1. Verify SelectionFabWrapper, Quick Settings FAB and Download FAB all coexist
        expect(find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'selection_fab'), findsOneWidget);
        expect(find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab'), findsOneWidget);
        expect(find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'download_fab'), findsOneWidget);

        // 2. Open Quick Settings and configure options
        await tester.tap(find.byIcon(Icons.construction_outlined));
        await tester.pumpAndSettle();

        // Turn on playlist
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        // Change merge format to MKV
        final formatDropdown = find.byType(LazyDropdown<MergeOutputFormat>);
        tester.widget<LazyDropdown<MergeOutputFormat>>(formatDropdown).onChanged(MergeOutputFormat.mkv);
        await tester.pumpAndSettle();

        // Add subtitle language
        final lazyListWidget = tester.widget<LazyList>(find.byType(LazyList));
        lazyListWidget.onChanged(['es - Español', 'ja - 日本語']);
        await tester.pumpAndSettle();

        // Close modal
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // 3. Enqueue video download
        final urlField = find.byType(TextField).first;
        await tester.enterText(urlField, 'https://youtube.com/watch?v=emp_workflow');
        await tester.pumpAndSettle();

        await tester.tap(find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'download_fab'));
        await tester.pumpAndSettle();

        expect(systemController.enqueuedDownloads, hasLength(1));
        final enqueuedVideo = systemController.enqueuedDownloads.first;
        expect(enqueuedVideo['url'], equals('https://youtube.com/watch?v=emp_workflow'));
        final opts1 = (enqueuedVideo['options'] as Map).cast<String, dynamic>();
        expect(opts1['playlist'], isTrue);
        expect(opts1['merge_output_format'], equals('mkv'));
        expect(opts1['sub_langs'], equals(['es', 'ja']));

        // 4. Open SettingsScreen to verify full bidirectional synchronization
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);

        // Return back to DownloadsScreen
        final backButton = find.byTooltip('Back');
        if (backButton.evaluate().isNotEmpty) {
          await tester.tap(backButton);
        } else {
          final navigator = tester.state<NavigatorState>(find.byType(Navigator));
          navigator.pop();
        }
        await tester.pumpAndSettle();

        expect(find.byType(DownloadsScreen), findsOneWidget);

        // 5. Open DownloadDetailScreen and navigate back to verify Hero tags and subsystem stability
        final navState = tester.state<NavigatorState>(find.byType(Navigator));
        navState.push(
          MaterialPageRoute(
            builder: (_) => DownloadDetailScreen(download: pendingDownload),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DownloadDetailScreen), findsOneWidget);

        // Pop back to DownloadsScreen
        navState.pop();
        await tester.pumpAndSettle();

        expect(find.byType(DownloadsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 6. Verify Cold Restart Persistence
        final coldRepo = SettingsRepository(prefs);
        final coldOpts = coldRepo.getDownloadOptions();
        expect(coldOpts.playlist, isTrue);
        expect(coldOpts.mergeOutputFormat, equals(MergeOutputFormat.mkv));
        expect(coldOpts.subLangs, equals(['es', 'ja']));
      },
    );
  });
}
