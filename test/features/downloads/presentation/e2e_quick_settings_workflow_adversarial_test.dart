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
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/settings/presentation/settings_screen.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

class MockLocaleRepo extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  MockLocaleRepo() {
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
  final SystemState _state = SystemState.ready;
  @override
  SystemState get state => _state;

  @override
  int? get backendPort => 5000;

  @override
  String? get backendToken => 'test_token';

  @override
  String? get serverLogsFilePath => '/tmp/test.log';

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
  final StreamController<List<Delta>> _deltaController =
      StreamController<List<Delta>>.broadcast();

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
  }) async {
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

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

  late MockLocaleRepo mockLocaleRepo;
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

    mockLocaleRepo = MockLocaleRepo();
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

  group('Milestone 4 E2E Workflow 1: Quick Settings FAB -> Audio Mode -> FLAC -> Enqueue Download Payload', () {
    testWidgets(
      'Full flow: Launch -> Tap Quick Settings FAB -> Toggle Playlist -> Switch to Audio Mode -> Select FLAC -> Close Modal -> Tap Download FAB -> Verify enqueued download payload',
      (WidgetTester tester) async {
        await pumpScreen(
          tester,
          buildTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        // 1. Initial State Assertions
        expect(settingsController.downloadOptions.playlist, isFalse);
        expect(settingsController.downloadOptions.extractAudio, isFalse);
        expect(systemController.enqueuedDownloads, isEmpty);

        // 2. Tap Quick Settings FAB
        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        expect(qsFabFinder, findsOneWidget);
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();

        // 3. Verify Modal is Open
        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
        expect(find.text('Quick Settings'), findsOneWidget);

        // 4. Toggle Playlist Switch
        final playlistSwitch = find.byType(Switch).first;
        expect(playlistSwitch, findsOneWidget);
        await tester.tap(playlistSwitch);
        await tester.pumpAndSettle();

        expect(settingsController.downloadOptions.playlist, isTrue);

        // 5. Switch to Audio Mode (SegmentedButton)
        final extractAudioSegment = find.text('Extract Audio');
        expect(extractAudioSegment, findsOneWidget);
        await tester.tap(extractAudioSegment);
        await tester.pumpAndSettle();

        expect(settingsController.downloadOptions.extractAudio, isTrue);

        // 6. Select FLAC from Audio Format Dropdown
        final audioFormatDropdownFinder = find.byType(LazyDropdown<AudioFormat>);
        expect(audioFormatDropdownFinder, findsOneWidget);

        final audioFormatDropdown = tester.widget<LazyDropdown<AudioFormat>>(
          audioFormatDropdownFinder,
        );
        audioFormatDropdown.onChanged(AudioFormat.flac);
        await tester.pumpAndSettle();

        expect(
          settingsController.downloadOptions.audioFormat,
          equals(AudioFormat.flac),
        );

        // 7. Close Modal via 'X' button
        final closeBtnFinder = find.byIcon(Icons.close);
        expect(closeBtnFinder, findsOneWidget);
        await tester.tap(closeBtnFinder);
        await tester.pumpAndSettle();

        // Verify Modal is dismissed
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);

        // 8. Enter URL in the input field
        const testUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
        final urlFieldFinder = find.byType(TextField).first;
        await tester.enterText(urlFieldFinder, testUrl);
        await tester.pumpAndSettle();

        // 9. Tap Download FAB
        final downloadFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );
        expect(downloadFabFinder, findsOneWidget);
        await tester.tap(downloadFabFinder);
        await tester.pumpAndSettle();

        // 10. Verify enqueued download payload has updated FLAC, audio extraction and playlist options
        expect(systemController.enqueuedDownloads, hasLength(1));
        final payload = systemController.enqueuedDownloads.first;
        expect(payload['url'], equals(testUrl));

        final options = payload['options'] as Map<String, dynamic>;
        expect(options['playlist'], isTrue);
        expect(options['extract_audio'], isTrue);
        expect(options['audio_format'], equals('flac'));
      },
    );
  });

  group('Milestone 4 E2E Workflow 2: Two-Way Synchronization (Quick Settings <-> SettingsScreen)', () {
    testWidgets(
      'Full flow: Change options in Quick Settings -> Navigate to SettingsScreen -> Verify SettingsScreen displays matching values -> Change value in SettingsScreen -> Open Quick Settings -> Verify Quick Settings displays matching value',
      (WidgetTester tester) async {
        await pumpScreen(
          tester,
          buildTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        // --- STEP A: Mutate in Quick Settings Modal ---
        // 1. Open Quick Settings modal
        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();

        // 2. Mutate Playlist -> true
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        expect(settingsController.downloadOptions.playlist, isTrue);

        // 3. Mutate Video Resolution -> '1080'
        final videoResDropdownFinder = find.byType(LazyDropdown<String>).first;
        final videoResDropdown = tester.widget<LazyDropdown<String>>(
          videoResDropdownFinder,
        );
        videoResDropdown.onChanged('1080');
        await tester.pumpAndSettle();

        // 4. Mutate Merge Output Format -> MKV
        final mergeFormatDropdownFinder = find.byType(
          LazyDropdown<MergeOutputFormat>,
        );
        final mergeFormatDropdown = tester.widget<LazyDropdown<MergeOutputFormat>>(
          mergeFormatDropdownFinder,
        );
        mergeFormatDropdown.onChanged(MergeOutputFormat.mkv);
        await tester.pumpAndSettle();

        // 5. Mutate Audio Language -> 'es'
        final audioLangDropdownFinder = find.byType(LazyDropdown<String>).at(1);
        final audioLangDropdown = tester.widget<LazyDropdown<String>>(
          audioLangDropdownFinder,
        );
        audioLangDropdown.onChanged('es');
        await tester.pumpAndSettle();

        // 6. Mutate Subtitle Languages -> ['en', 'es']
        final lazyListFinder = find.byType(LazyList);
        final lazyList = tester.widget<LazyList>(lazyListFinder);
        lazyList.onChanged(['en - English', 'es - Español']);
        await tester.pumpAndSettle();

        // Close Quick Settings modal
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);

        // --- STEP B: Navigate to SettingsScreen and Verify Matching Values ---
        final settingsIconFinder = find.byIcon(Icons.settings);
        expect(settingsIconFinder, findsOneWidget);
        await tester.tap(settingsIconFinder);
        await tester.pumpAndSettle();

        // Verify SettingsScreen is active
        expect(find.byType(SettingsScreen), findsOneWidget);

        // Verify values in SettingsController accessed by SettingsScreen
        expect(settingsController.downloadOptions.playlist, isTrue);
        expect(
          settingsController.downloadOptions.videoResolution,
          equals(VideoOption.resolution),
        );
        expect(
          settingsController.downloadOptions.videoResolutionValue,
          equals('1080'),
        );
        expect(
          settingsController.downloadOptions.mergeOutputFormat,
          equals(MergeOutputFormat.mkv),
        );
        expect(
          settingsController.downloadOptions.audioLanguage,
          equals(AudioOption.language),
        );
        expect(
          settingsController.downloadOptions.audioLanguageCode,
          equals('es'),
        );
        expect(
          settingsController.downloadOptions.subLangs,
          equals(['en', 'es']),
        );

        // --- STEP C: Mutate Values within SettingsScreen ---
        // Change playlist to false, extractAudio to true, audioFormat to mp3
        settingsController.updateDownloadOptions(
          settingsController.downloadOptions.copyWith(
            playlist: false,
            extractAudio: true,
            audioFormat: AudioFormat.mp3,
          ),
        );
        await tester.pumpAndSettle();

        // Pop back to DownloadsScreen
        final backButtonFinder = find.byTooltip('Back');
        if (backButtonFinder.evaluate().isNotEmpty) {
          await tester.tap(backButtonFinder);
        } else {
          final backIconFinder = find.byIcon(Icons.arrow_back);
          if (backIconFinder.evaluate().isNotEmpty) {
            await tester.tap(backIconFinder);
          } else {
            Navigator.pop(tester.element(find.byType(SettingsScreen)));
          }
        }
        await tester.pumpAndSettle();

        // Verify back on DownloadsScreen
        expect(find.byType(DownloadsScreen), findsOneWidget);
        expect(find.byType(SettingsScreen), findsNothing);

        // --- STEP D: Reopen Quick Settings Modal and Verify Matching Values ---
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();

        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

        // Playlist Switch should be false
        final playlistSwitchWidget = tester.widget<Switch>(
          find.byType(Switch).first,
        );
        expect(playlistSwitchWidget.value, isFalse);

        // Segmented button should have Extract Audio selected
        final segmentedBtn = tester.widget<SegmentedButton<bool>>(
          find.byType(SegmentedButton<bool>),
        );
        expect(segmentedBtn.selected, equals({true}));

        // Audio Format dropdown should show MP3
        final audioDropdownWidget = tester.widget<LazyDropdown<AudioFormat>>(
          find.byType(LazyDropdown<AudioFormat>),
        );
        expect(audioDropdownWidget.value, equals(AudioFormat.mp3));
      },
    );
  });

  group('Milestone 4 i18n & Static String Parity Stress Tests', () {
    testWidgets(
      'Verify all UI elements and labels in both English (en) and Spanish (es) locales',
      (WidgetTester tester) async {
        // 1. Test in English
        await pumpScreen(
          tester,
          buildTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        // Open modal in English
        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();

        expect(find.text('Quick Settings'), findsOneWidget);
        expect(find.text('Playlist'), findsOneWidget);
        expect(find.text('Video'), findsOneWidget);
        expect(find.text('Extract Audio'), findsOneWidget);
        expect(find.text('Video Resolution'), findsWidgets);
        expect(find.text('Video Format'), findsWidgets);
        expect(find.text('Audio Language'), findsWidgets);
        expect(find.text('Subtitle Languages'), findsWidgets);

        // Close modal
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // 2. Switch to Spanish dynamically
        final esLocaleController = LocaleController(mockLocaleRepo, 'es');
        await esLocaleController.whenReady;

        await pumpScreen(
          tester,
          buildTestApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: esLocaleController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        // Open modal in Spanish
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();

        expect(find.text('Configuración Rápida'), findsOneWidget);
        expect(find.text('Lista de reproducción'), findsOneWidget);
        expect(find.text('Video'), findsOneWidget);
        expect(find.text('Extraer audio'), findsOneWidget);
        expect(find.text('Resolución de vídeo'), findsWidgets);
        expect(find.text('Formato de vídeo'), findsWidgets);
        expect(find.text('Idioma de audio'), findsWidgets);
        expect(find.text('Idiomas de subtítulos'), findsWidgets);
      },
    );

    test('Zero raw strings verification in production files', () {
      final quickSettingsFile = File(
        'lib/features/downloads/presentation/widgets/quick_settings_bottom_sheet.dart',
      );
      expect(quickSettingsFile.existsSync(), isTrue);
      final content = quickSettingsFile.readAsStringSync();

      // Ensure no raw user-facing English/Spanish strings are hardcoded in Text widgets
      expect(content.contains("Text('Quick Settings')"), isFalse);
      expect(content.contains("Text('Configuración Rápida')"), isFalse);
      expect(content.contains("Text('Playlist')"), isFalse);
      expect(content.contains("Text('Extract Audio')"), isFalse);
      expect(content.contains("Text('Video Resolution')"), isFalse);
      expect(content.contains("Text('Close')"), isFalse);
      expect(content.contains("Text('Cerrar')"), isFalse);
    });
  });
}
