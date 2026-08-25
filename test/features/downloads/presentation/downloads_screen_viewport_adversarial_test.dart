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
import 'package:vidra/features/downloads/presentation/widgets/quick_settings_bottom_sheet.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';

class ViewportMockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  ViewportMockLocaleRepository() {
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

class ViewportFakeSystemController extends ChangeNotifier
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
  String? get backendToken => 'viewport_token';

  @override
  String? get serverLogsFilePath => '/tmp/viewport.log';

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

class ViewportFakeUpdateController extends ChangeNotifier
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

class ViewportFakeDownloadRepository extends DownloadRepository {
  List<Download> initialDownloads;
  final StreamController<List<Delta>> _deltaController =
      StreamController<List<Delta>>.broadcast();

  ViewportFakeDownloadRepository({
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
  required ViewportFakeSystemController systemController,
  required ViewportFakeUpdateController updateController,
  required ViewportFakeDownloadRepository downloadRepository,
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

  late ViewportMockLocaleRepository mockLocaleRepo;
  late LocaleController localeControllerEn;
  late LocaleController localeControllerEs;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late ViewportFakeSystemController systemController;
  late ViewportFakeUpdateController updateController;
  late ViewportFakeDownloadRepository downloadRepo;
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

    mockLocaleRepo = ViewportMockLocaleRepository();
    localeControllerEn = LocaleController(mockLocaleRepo, 'en');
    await localeControllerEn.whenReady;

    localeControllerEs = LocaleController(mockLocaleRepo, 'es');
    await localeControllerEs.whenReady;

    systemController = ViewportFakeSystemController();
    updateController = ViewportFakeUpdateController();
    downloadRepo = ViewportFakeDownloadRepository();
    downloadsController = DownloadsController(downloadRepo, systemController);
  });

  tearDown(() {
    downloadRepo.dispose();
  });

  group('Task 1: DownloadsScreen Dual FAB Viewport Matrix (320px, 360px, 480px, 800px, 1400px)', () {
    const requiredViewports = [
      Size(320, 568),   // iPhone SE 1st gen / ultra narrow mobile
      Size(360, 640),   // Compact Android
      Size(480, 800),   // Mid mobile / mini tablet
      Size(800, 1280),  // Tablet portrait
      Size(1400, 900),  // Desktop widescreen
    ];

    for (final size in requiredViewports) {
      testWidgets('Viewport ${size.width.toInt()}x${size.height.toInt()} (EN): Dual FAB geometry, bounds, and modal invocation', (
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

        expect(tester.takeException(), isNull);

        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        final dlFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );

        expect(qsFabFinder, findsOneWidget);
        expect(dlFabFinder, findsOneWidget);

        final qsRect = tester.getRect(qsFabFinder);
        final dlRect = tester.getRect(dlFabFinder);

        // 1. Verify FAB dimensions
        expect(qsRect.width, closeTo(56.0, 0.01));
        expect(qsRect.height, closeTo(56.0, 0.01));
        expect(dlRect.height, closeTo(56.0, 0.01));
        expect(dlRect.width, greaterThan(56.0)); // Extended button

        // 2. Horizontal ordering: Quick Settings left of Download FAB
        expect(qsRect.right, lessThan(dlRect.left));
        expect(dlRect.left - qsRect.right, lessThanOrEqualTo(12.01));
        expect(dlRect.left - qsRect.right, greaterThan(0.0));

        // 3. Screen bounds check: Both must be inside screen
        expect(qsRect.left, greaterThanOrEqualTo(0.0));
        expect(dlRect.right, lessThanOrEqualTo(size.width));

        // 4. Modal opening on this viewport
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();

        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
        expect(tester.takeException(), isNull);

        final sheetRect = tester.getRect(find.byType(QuickSettingsBottomSheet));
        expect(sheetRect.width, lessThanOrEqualTo(640.0));
        expect(sheetRect.width, lessThanOrEqualTo(size.width));

        // Close modal
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);
      });

      testWidgets('Viewport ${size.width.toInt()}x${size.height.toInt()} (ES): Dual FAB geometry with Spanish text ("Descargar")', (
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
          buildTestApp(
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

        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        final dlFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );

        expect(qsFabFinder, findsOneWidget);
        expect(dlFabFinder, findsOneWidget);
        expect(find.text('Descargar'), findsOneWidget);

        final qsRect = tester.getRect(qsFabFinder);
        final dlRect = tester.getRect(dlFabFinder);

        expect(qsRect.left, greaterThanOrEqualTo(0.0));
        expect(dlRect.right, lessThanOrEqualTo(size.width));
        expect(dlRect.left - qsRect.right, lessThanOrEqualTo(12.01));
        expect(dlRect.left - qsRect.right, greaterThan(0.0));
      });
    }
  });

  group('Task 2: Multi-Download SelectionFabWrapper Coexistence & Clearance Matrix', () {
    const viewports = [
      Size(320, 568),
      Size(360, 640),
      Size(480, 800),
      Size(800, 1280),
      Size(1400, 900),
    ];

    for (final size in viewports) {
      testWidgets('Viewport ${size.width.toInt()}px with 3 pending downloads awaiting selection', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 3 pending items awaiting selection
        final pendingDownloads = [
          Download(
            id: 'dl_pending_1',
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
            info: Info(url: 'https://example.com/item1', title: 'Pending Item 1'),
          ),
          Download(
            id: 'dl_pending_2',
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
            info: Info(url: 'https://example.com/item2', title: 'Pending Item 2'),
          ),
          Download(
            id: 'dl_pending_3',
            state: DownloadState(value: DownloadStateEnum.awaitingSelection),
            info: Info(url: 'https://example.com/item3', title: 'Pending Item 3'),
          ),
        ];

        downloadRepo.initialDownloads = pendingDownloads;
        downloadsController = DownloadsController(downloadRepo, systemController);

        await pumpScreen(
          tester,
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

        expect(tester.takeException(), isNull);

        // Selection FAB on bottom-left
        final selFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'selection_fab',
        );
        // Dual FAB on bottom-right
        final qsFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        final dlFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );

        expect(selFinder, findsOneWidget);
        expect(qsFinder, findsOneWidget);
        expect(dlFinder, findsOneWidget);

        // Badge count verification
        expect(find.text('3'), findsOneWidget);

        final selRect = tester.getRect(selFinder);
        final qsRect = tester.getRect(qsFinder);
        final dlRect = tester.getRect(dlFinder);

        // Left anchor
        expect(selRect.left, equals(16.0));
        expect(selRect.width, closeTo(56.0, 0.01));

        // Right anchor
        expect(dlRect.right, closeTo(size.width - 16.0, 0.01));

        final clearance = qsRect.left - selRect.right;
        if (size.width >= 360) {
          // On standard mobile (360px) and above, positive clearance (no collision)
          expect(clearance, greaterThanOrEqualTo(0.0));
          expect(selRect.right, lessThanOrEqualTo(qsRect.left));
        } else {
          // On 320px ultra-compact width, record geometric overlap:
          // selRect: [16, 72], dual FAB: [55.2, 304]
          expect(clearance, lessThan(0.0));
        }

        // Both FABs remain interactive
        // Tap QS FAB opens bottom sheet
        await tester.tap(qsFinder);
        await tester.pumpAndSettle();
        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Close bottom sheet
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);
      });
    }

    testWidgets('10 pending downloads correctly renders double-digit badge alongside dual FAB', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(412, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final pendingDownloads = List.generate(
        10,
        (i) => Download(
          id: 'dl_pending_$i',
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          info: Info(url: 'https://example.com/item$i', title: 'Pending Item $i'),
        ),
      );

      downloadRepo.initialDownloads = pendingDownloads;
      downloadsController = DownloadsController(downloadRepo, systemController);

      await pumpScreen(
        tester,
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

      expect(find.text('10'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'selection_fab'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'download_fab'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
