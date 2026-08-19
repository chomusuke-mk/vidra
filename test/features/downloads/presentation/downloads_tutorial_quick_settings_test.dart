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
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/utils/tutorial_utils.dart';

class MockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  MockLocaleRepository() {
    for (final code in ['en', 'es', 'de', 'fr']) {
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
  @override
  SystemState get state => SystemState.ready;

  @override
  int? get backendPort => 5000;

  @override
  String? get backendToken => 'mock_token';

  @override
  String? get serverLogsFilePath => '/tmp/mock.log';

  @override
  Future<void> get whenPortReady => Future.value();

  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {}

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDownloadRepository extends DownloadRepository {
  FakeDownloadRepository()
      : super(VidraHttpClient(baseUrl: 'http://127.0.0.1:5000', defaultHeaders: {}));

  @override
  Future<List<Download>> getAllDownloads() async => [];

  @override
  Future<Download?> getDownloadById(String id) async => null;

  @override
  Future<String> addDownload(
    String url, {
    Map<String, dynamic> options = const {},
  }) async => 'id_123';

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
  Stream<List<Delta>> watchGlobalProgress() => const Stream.empty();
}

Widget createTutorialTestApp({
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

Future<void> advanceTutorialStep(WidgetTester tester, String buttonText) async {
  final buttonFinder = find.text(buttonText);
  expect(buttonFinder, findsOneWidget);
  await tester.tap(buttonFinder);
  for (int i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpScreen(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
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

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
  });

  group('Main App Tutorial - Quick Settings Integration', () {
    testWidgets(
      'AppTutorialKeys.mainQuickSettings is attached to the Quick Settings FAB on DownloadsScreen',
      (WidgetTester tester) async {
        await pumpScreen(
          tester,
          createTutorialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final quickSettingsFinder = find.byKey(AppTutorialKeys.mainQuickSettings);
        expect(quickSettingsFinder, findsOneWidget);

        final fab = tester.widget<FloatingActionButton>(quickSettingsFinder);
        expect(fab.heroTag, equals('quick_settings_fab'));
        expect(find.descendant(of: quickSettingsFinder, matching: find.byIcon(Icons.construction_outlined)), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Tutorial target sequence includes mainQuickSettings as the final step after mainSettings',
      (WidgetTester tester) async {
        await pumpScreen(
          tester,
          createTutorialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        // Tap the tutorial help icon button in the AppBar
        final helpIconFinder = find.byIcon(Icons.help_outline);
        expect(helpIconFinder, findsOneWidget);
        await tester.tap(helpIconFinder);
        await tester.pump(const Duration(milliseconds: 10)); // Runs postFrame Future.delayed -> inserts OverlayEntry
        await tester.pump(const Duration(milliseconds: 10)); // Builds OverlayEntry -> runs initState Future.delayed
        await tester.pump(const Duration(milliseconds: 650)); // Runs forward animation -> calls focus()
        await tester.pump(const Duration(milliseconds: 350)); // Completes AnimatedOpacity fade-in

        // 1. First step: Engine State
        expect(find.text('Engine State'), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);
        await advanceTutorialStep(tester, 'Next');

        // 2. Second step: Download Content
        expect(find.text('Download Content'), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);
        await advanceTutorialStep(tester, 'Next');

        // 3. Third step: Filters and Search
        expect(find.text('Filters and Search'), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);
        await advanceTutorialStep(tester, 'Next');

        // 4. Fourth step: Settings (should transition to Quick Settings, so has "Next", not "Understood")
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);
        await advanceTutorialStep(tester, 'Next');

        // 5. Fifth step: Quick Settings (final step, shows "Understood")
        expect(find.text('Quick Settings'), findsOneWidget);
        expect(
          find.text(
            'Open this menu to quickly adjust download options on the fly without leaving the main screen.',
          ),
          findsOneWidget,
        );
        expect(find.text('Understood'), findsOneWidget);

        // Tap Understood to complete tutorial
        await tester.tap(find.text('Understood'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // Tutorial is dismissed and preference is persisted
        expect(prefs.getBool('has_seen_main_tutorial'), isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Tutorial renders Spanish localized title and description for Quick Settings step',
      (WidgetTester tester) async {
        final esLocaleController = LocaleController(mockLocaleRepo, 'es');
        await esLocaleController.whenReady;

        await pumpScreen(
          tester,
          createTutorialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: esLocaleController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        // Tap the tutorial help icon button in the AppBar
        final helpIconFinder = find.byIcon(Icons.help_outline);
        expect(helpIconFinder, findsOneWidget);
        await tester.tap(helpIconFinder);
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump(const Duration(milliseconds: 350));

        // Step 1: Engine state
        expect(find.text('Estado del motor'), findsOneWidget);
        await advanceTutorialStep(tester, 'Próximo');

        // Step 2: Download content
        expect(find.text('Descargar contenido'), findsOneWidget);
        await advanceTutorialStep(tester, 'Próximo');

        // Step 3: Filters
        expect(find.text('Filtros y búsqueda'), findsOneWidget);
        await advanceTutorialStep(tester, 'Próximo');

        // Step 4: Settings
        expect(find.text('Ajustes'), findsOneWidget);
        await advanceTutorialStep(tester, 'Próximo');

        // Step 5: Quick Settings in Spanish
        expect(find.text('Configuración rápida'), findsWidgets);
        expect(
          find.text(
            'Abra este menú para ajustar rápidamente las opciones de descarga sobre la marcha sin salir de la pantalla principal.',
          ),
          findsOneWidget,
        );
        expect(find.text('Comprendido'), findsOneWidget);

        await tester.tap(find.text('Comprendido'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Tutorial renders German localized title and description for Quick Settings step',
      (WidgetTester tester) async {
        final deLocaleController = LocaleController(mockLocaleRepo, 'de');
        await deLocaleController.whenReady;

        await pumpScreen(
          tester,
          createTutorialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: deLocaleController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final helpIconFinder = find.byIcon(Icons.help_outline);
        expect(helpIconFinder, findsOneWidget);
        await tester.tap(helpIconFinder);
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump(const Duration(milliseconds: 350));

        // Step 1: Engine state
        expect(find.text('Motorstatus'), findsOneWidget);
        await advanceTutorialStep(tester, 'Nächste');

        // Step 2: Download content
        expect(find.text('Inhalte herunterladen'), findsOneWidget);
        await advanceTutorialStep(tester, 'Nächste');

        // Step 3: Filters
        expect(find.text('Filter und Suche'), findsOneWidget);
        await advanceTutorialStep(tester, 'Nächste');

        // Step 4: Settings
        expect(find.text('Einstellungen'), findsOneWidget);
        await advanceTutorialStep(tester, 'Nächste');

        // Step 5: Quick Settings in German
        expect(find.text('Schnelleinstellungen'), findsWidgets);
        expect(
          find.text(
            'Öffnen Sie dieses Menü, um die Download-Optionen schnell anzupassen, ohne den Hauptbildschirm zu verlassen.',
          ),
          findsOneWidget,
        );
        expect(find.text('Verstanden'), findsOneWidget);

        await tester.tap(find.text('Verstanden'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Tutorial renders French localized steps for Quick Settings',
      (WidgetTester tester) async {
        final frLocaleController = LocaleController(mockLocaleRepo, 'fr');
        await frLocaleController.whenReady;

        await pumpScreen(
          tester,
          createTutorialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: frLocaleController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final helpIconFinder = find.byIcon(Icons.help_outline);
        expect(helpIconFinder, findsOneWidget);
        await tester.tap(helpIconFinder);
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump(const Duration(milliseconds: 350));

        // Step 1: Engine state
        expect(find.text('État du moteur'), findsOneWidget);
        await advanceTutorialStep(tester, 'Suivant');

        // Step 2: Download content
        expect(find.text('Télécharger du contenu'), findsOneWidget);
        await advanceTutorialStep(tester, 'Suivant');

        // Step 3: Filters
        expect(find.text('Filtres et recherche'), findsOneWidget);
        await advanceTutorialStep(tester, 'Suivant');

        // Step 4: Settings
        expect(find.text('Paramètres'), findsOneWidget);
        await advanceTutorialStep(tester, 'Suivant');

        // Step 5: Quick Settings in French
        expect(find.text('Paramètres rapides'), findsWidgets);
        expect(
          find.text(
            "Ouvrez ce menu pour ajuster rapidement les options de téléchargement à la volée sans quitter l'écran principal.",
          ),
          findsOneWidget,
        );
        expect(find.text('Compris'), findsOneWidget);

        await tester.tap(find.text('Compris'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Skipping tutorial marks has_seen_main_tutorial in SharedPreferences and dismisses overlay',
      (WidgetTester tester) async {
        await prefs.setBool('has_seen_main_tutorial', false);

        await tester.pumpWidget(
          createTutorialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );
        // Let Changelog check, 300ms delay, and tutorial coach mark animation run
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump(const Duration(milliseconds: 350));

        // Tap Skip button on first step
        final skipFinder = find.text('Skip');
        expect(skipFinder, findsOneWidget);
        await tester.tap(skipFinder);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(prefs.getBool('has_seen_main_tutorial'), isTrue);
        expect(find.text('Skip'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'showMainAppTutorial does not show when has_seen_main_tutorial is true and force is false',
      (WidgetTester tester) async {
        await prefs.setBool('has_seen_main_tutorial', true);

        await pumpScreen(
          tester,
          createTutorialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final context = tester.element(find.byType(DownloadsScreen));
        TutorialUtils.showMainAppTutorial(context, force: false);
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Engine State'), findsNothing);
        expect(find.text('Quick Settings'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Tutorial renders Quick Settings step cleanly on compact short height viewport (640x360)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(640, 360);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await pumpScreen(
          tester,
          createTutorialTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final helpIconFinder = find.byIcon(Icons.help_outline);
        expect(helpIconFinder, findsOneWidget);
        await tester.tap(helpIconFinder);
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump(const Duration(milliseconds: 350));

        await advanceTutorialStep(tester, 'Next');
        await advanceTutorialStep(tester, 'Next');
        await advanceTutorialStep(tester, 'Next');
        await advanceTutorialStep(tester, 'Next');

        expect(find.text('Quick Settings'), findsOneWidget);
        expect(find.text('Understood'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Understood'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(prefs.getBool('has_seen_main_tutorial'), isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    test('AppStringKey contains tuPPQuickSettings and tuPPQuickSettingsDesc getters', () {
      final appStrings = AppStringKey();
      expect(appStrings.tuPPQuickSettings, equals(''));
      expect(appStrings.tuPPQuickSettingsDesc, equals(''));
    });
  });
}
