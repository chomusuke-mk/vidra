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
import 'package:vidra/shared/utils/tutorial_utils.dart';

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

  group('DownloadsScreen Floating Action Buttons Layout & Properties', () {
    testWidgets(
      'renders both Quick Settings FAB and Download FAB side-by-side in a Row',
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

        // 1. Verify Scaffold floatingActionButton contains Row(mainAxisSize: MainAxisSize.min)
        final rowFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Row &&
              widget.mainAxisSize == MainAxisSize.min &&
              widget.children.any(
                (c) =>
                    c is FloatingActionButton &&
                    c.heroTag == 'quick_settings_fab',
              ),
        );
        expect(rowFinder, findsOneWidget);

        // 2. Verify Spacing between FABs is 12px
        final sizedBoxFinder = find.descendant(
          of: rowFinder,
          matching: find.byWidgetPredicate(
            (widget) => widget is SizedBox && widget.width == 12,
          ),
        );
        expect(sizedBoxFinder, findsNWidgets(2));

        // 3. Verify Quick Settings FAB properties
        final quickSettingsFabFinder = find.byWidgetPredicate(
          (widget) =>
              widget is FloatingActionButton &&
              widget.heroTag == 'quick_settings_fab',
        );
        expect(quickSettingsFabFinder, findsOneWidget);

        final FloatingActionButton qsFab =
            tester.widget(quickSettingsFabFinder);
        expect(qsFab.key, equals(AppTutorialKeys.mainQuickSettings));
        expect(qsFab.heroTag, equals('quick_settings_fab'));
        expect(qsFab.tooltip, equals('Quick Settings'));
        expect(find.byIcon(Icons.construction_outlined), findsOneWidget);
        expect(find.byKey(AppTutorialKeys.mainQuickSettings), findsOneWidget);

        // 4. Verify Download FAB properties
        final downloadFabFinder = find.byWidgetPredicate(
          (widget) =>
              widget is FloatingActionButton &&
              widget.heroTag == 'download_fab',
        );
        expect(downloadFabFinder, findsOneWidget);

        final FloatingActionButton dlFab = tester.widget(downloadFabFinder);
        expect(dlFab.heroTag, equals('download_fab'));
        expect(find.byIcon(Icons.download), findsOneWidget);
        expect(find.text('Download'), findsOneWidget);

        // 5. Verify horizontal arrangement (Quick Settings is to the left of Download FAB)
        final qsFabTopLeft = tester.getTopLeft(quickSettingsFabFinder);
        final dlFabTopLeft = tester.getTopLeft(downloadFabFinder);
        expect(qsFabTopLeft.dx, lessThan(dlFabTopLeft.dx));
      },
    );

    testWidgets('renders Spanish localized tooltip and label', (
      WidgetTester tester,
    ) async {
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

      final quickSettingsFabFinder = find.byWidgetPredicate(
        (widget) =>
            widget is FloatingActionButton &&
            widget.heroTag == 'quick_settings_fab',
      );
      expect(quickSettingsFabFinder, findsOneWidget);
      final FloatingActionButton qsFab =
          tester.widget(quickSettingsFabFinder);
      expect(qsFab.tooltip, equals('Configuración rápida'));

      expect(find.text('Descargar'), findsOneWidget);
    });
  });

  group('Quick Settings Modal Bottom Sheet Invocation & Interaction', () {
    testWidgets(
      'tapping Quick Settings FAB opens QuickSettingsBottomSheet and dismisses cleanly',
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

        // Bottom sheet not present initially
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);

        // Tap Quick Settings FAB
        final quickSettingsFabFinder = find.byWidgetPredicate(
          (widget) =>
              widget is FloatingActionButton &&
              widget.heroTag == 'quick_settings_fab',
        );
        await tester.tap(quickSettingsFabFinder);
        await tester.pumpAndSettle();

        // QuickSettingsBottomSheet is now visible
        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
        expect(find.text('Quick Settings'), findsOneWidget);
        expect(find.text('Playlist'), findsOneWidget);
        expect(find.text('Video'), findsOneWidget);
        expect(find.text('Extract Audio'), findsOneWidget);

        // Close bottom sheet
        final closeButtonFinder = find.byIcon(Icons.close);
        expect(closeButtonFinder, findsOneWidget);
        await tester.tap(closeButtonFinder);
        await tester.pumpAndSettle();

        // Bottom sheet dismissed
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);
      },
    );

    testWidgets(
      'tapping Download FAB with empty URL does nothing, with URL triggers enqueue',
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

        final downloadFabFinder = find.byWidgetPredicate(
          (widget) =>
              widget is FloatingActionButton &&
              widget.heroTag == 'download_fab',
        );

        // Tap with empty URL
        await tester.tap(downloadFabFinder);
        await tester.pumpAndSettle();
        expect(systemController.enqueuedDownloads, isEmpty);

        // Enter URL into TextField
        final urlFieldFinder = find.byType(TextField).first;
        await tester.enterText(urlFieldFinder, 'https://example.com/video.mp4');
        await tester.pumpAndSettle();

        // Tap download
        await tester.tap(downloadFabFinder);
        await tester.pumpAndSettle();

        expect(systemController.enqueuedDownloads, hasLength(1));
        expect(
          systemController.enqueuedDownloads.first['url'],
          equals('https://example.com/video.mp4'),
        );
      },
    );
  });

  group('Narrow Viewport (360px) & Multi-FAB Coexistence with SelectionFabWrapper', () {
    testWidgets(
      'renders both left selection FAB and right dual FAB row on 360px viewport without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Seed with a pending download that requires SelectionFabWrapper FAB
        final pendingDownload = Download(
          id: 'dl_pending_1',
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

        // 1. Verify Selection FAB is rendered on bottom-left
        final selectionFabFinder = find.byWidgetPredicate(
          (widget) =>
              widget is FloatingActionButton &&
              widget.heroTag == 'selection_fab',
        );
        expect(selectionFabFinder, findsOneWidget);

        // 2. Verify Quick Settings FAB and Download FAB are rendered on bottom-right
        final quickSettingsFabFinder = find.byWidgetPredicate(
          (widget) =>
              widget is FloatingActionButton &&
              widget.heroTag == 'quick_settings_fab',
        );
        final downloadFabFinder = find.byWidgetPredicate(
          (widget) =>
              widget is FloatingActionButton &&
              widget.heroTag == 'download_fab',
        );
        expect(quickSettingsFabFinder, findsOneWidget);
        expect(downloadFabFinder, findsOneWidget);

        // 3. Verify bounds and non-overlapping layout
        final selectionFabRect = tester.getRect(selectionFabFinder);
        final quickSettingsFabRect = tester.getRect(quickSettingsFabFinder);
        final downloadFabRect = tester.getRect(downloadFabFinder);

        // Selection FAB should be on the left (x ~ 16)
        expect(selectionFabRect.left, equals(16.0));

        // Quick Settings and Download FABs should be to the right of Selection FAB
        expect(quickSettingsFabRect.left, greaterThan(selectionFabRect.right));
        expect(downloadFabRect.left, greaterThan(quickSettingsFabRect.right));

        // Download FAB must stay within screen bounds (right <= 360)
        expect(downloadFabRect.right, lessThanOrEqualTo(360.0));

        // 4. Verify no RenderFlex overflow errors occurred
        expect(tester.takeException(), isNull);

        // 5. Verify tapping Quick Settings FAB still opens bottom sheet cleanly on 360px
        await tester.tap(quickSettingsFabFinder);
        await tester.pumpAndSettle();

        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Dismiss sheet
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);
      },
    );

    testWidgets(
      'renders cleanly on 320px viewport without throwing exceptions',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 568);
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

        expect(find.byIcon(Icons.construction_outlined), findsOneWidget);
        expect(find.byIcon(Icons.download), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Hero Tag Uniqueness & Safety', () {
    testWidgets('all FABs have unique hero tags across the widget tree', (
      WidgetTester tester,
    ) async {
      final pendingDownload = Download(
        id: 'dl_pending_hero_test',
        state: DownloadState(value: DownloadStateEnum.awaitingSelection),
        info: Info(
          url: 'https://example.com/item',
          title: 'Hero Tag Test Download',
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

      final fabWidgets = tester
          .widgetList<FloatingActionButton>(find.byType(FloatingActionButton))
          .toList();

      final heroTags = fabWidgets.map((f) => f.heroTag).toList();
      expect(heroTags, contains('selection_fab'));
      expect(heroTags, contains('cut_video_fab'));
      expect(heroTags, contains('quick_settings_fab'));
      expect(heroTags, contains('download_fab'));

      // Ensure no duplicate tags
      expect(heroTags.toSet().length, equals(heroTags.length));
    });
  });
}
