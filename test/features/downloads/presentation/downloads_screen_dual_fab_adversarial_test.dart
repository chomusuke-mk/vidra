import 'dart:async';
import 'dart:convert';
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
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';

class AdversarialLocaleRepo extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  AdversarialLocaleRepo() {
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
  String? get backendToken => 'adv_token';

  @override
  String? get serverLogsFilePath => '/tmp/adv.log';

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
  }) : super(
          VidraHttpClient(
            baseUrl: 'http://127.0.0.1:5000',
            defaultHeaders: {},
          ),
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

Widget createAdversarialApp({
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

Future<void> pumpTestScreen(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AdversarialLocaleRepo mockLocaleRepo;
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

    mockLocaleRepo = AdversarialLocaleRepo();
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

  group('Adversarial Test 1: Rapid Multi-Tap & Modal Lifecycle', () {
    testWidgets(
      'Rapid consecutive taps on Quick Settings FAB opens sheet without navigator crash or double modal push',
      (WidgetTester tester) async {
        await pumpTestScreen(
          tester,
          createAdversarialApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );

        // Tap 5 times with minimal frame interval
        for (int i = 0; i < 5; i++) {
          await tester.tap(qsFabFinder, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pumpAndSettle();

        // Should have exactly 1 bottom sheet open
        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Close bottom sheet
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.byType(QuickSettingsBottomSheet), findsNothing);
      },
    );

    testWidgets(
      'Stress test 10 rapid open-close cycles between FAB tap and close button',
      (WidgetTester tester) async {
        await pumpTestScreen(
          tester,
          createAdversarialApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );

        for (int i = 0; i < 10; i++) {
          await tester.tap(qsFabFinder);
          await tester.pumpAndSettle();
          expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

          final closeBtn = find.byIcon(Icons.close);
          expect(closeBtn, findsOneWidget);
          await tester.tap(closeBtn);
          await tester.pumpAndSettle();
          expect(find.byType(QuickSettingsBottomSheet), findsNothing);
        }

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Tapping outside modal barrier dismisses sheet cleanly returning focus to DownloadsScreen',
      (WidgetTester tester) async {
        await pumpTestScreen(
          tester,
          createAdversarialApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();
        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

        // Tap on modal barrier outside the 640px sheet (top-left corner)
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        expect(find.byType(QuickSettingsBottomSheet), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Adversarial Test 2: Full State Sync Pipeline (QS Modal -> DownloadsScreen FAB)', () {
    testWidgets(
      'Modifications in Quick Settings immediately propagate to DownloadsScreen enqueue payload in Video Mode',
      (WidgetTester tester) async {
        await pumpTestScreen(
          tester,
          createAdversarialApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        // 1. Open Quick Settings modal
        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();

        // 2. Toggle Playlist switch
        final playlistSwitch = find.byType(SwitchListTile);
        expect(playlistSwitch, findsOneWidget);
        await tester.tap(playlistSwitch);
        await tester.pumpAndSettle();

        // 3. Change Video Resolution to 720p
        final resolutionDropdown = find.byWidgetPredicate(
          (w) => w is LazyDropdown<String> && w.label == 'Video Resolution',
        );
        expect(resolutionDropdown, findsOneWidget);
        tester.widget<LazyDropdown<String>>(resolutionDropdown).onChanged('720');
        await tester.pumpAndSettle();

        // 4. Change Merge Output Format to MKV
        final formatDropdown = find.byType(LazyDropdown<MergeOutputFormat>);
        expect(formatDropdown, findsOneWidget);
        tester
            .widget<LazyDropdown<MergeOutputFormat>>(formatDropdown)
            .onChanged(MergeOutputFormat.mkv);
        await tester.pumpAndSettle();

        // 5. Close Quick Settings
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(QuickSettingsBottomSheet), findsNothing);

        // 6. Enter a URL on DownloadsScreen
        final urlFieldFinder = find.byType(TextField).first;
        await tester.enterText(
          urlFieldFinder,
          'https://www.youtube.com/watch?v=adv_test_123',
        );
        await tester.pumpAndSettle();

        // 7. Tap Download FAB
        final dlFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );
        await tester.tap(dlFabFinder);
        await tester.pumpAndSettle();

        // 8. Assert systemController enqueued download payload matches mutated options!
        expect(systemController.enqueuedDownloads, hasLength(1));
        final enqueued = systemController.enqueuedDownloads.first;
        expect(
          enqueued['url'],
          equals('https://www.youtube.com/watch?v=adv_test_123'),
        );

        final Map<String, dynamic> optionsPayload =
            (enqueued['options'] as Map).cast<String, dynamic>();
        expect(optionsPayload['playlist'], isTrue);
        expect(optionsPayload['extract_audio'], isFalse);
        expect(optionsPayload['video_resolution'], equals('720'));
        expect(optionsPayload['merge_output_format'], equals('mkv'));
      },
    );

    testWidgets(
      'Modifications in Quick Settings immediately propagate to DownloadsScreen enqueue payload in Audio Mode',
      (WidgetTester tester) async {
        await pumpTestScreen(
          tester,
          createAdversarialApp(
            downloadsController: downloadsController,
            settingsController: settingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        // 1. Open Quick Settings
        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();

        // 2. Switch to Extract Audio mode
        final audioSegment = find.text('Extract Audio');
        await tester.tap(audioSegment);
        await tester.pumpAndSettle();

        // 3. Select MP3 Audio Format
        final audioFormatDropdown = find.byWidgetPredicate(
          (w) => w is LazyDropdown<AudioFormat> && w.label == 'Audio Format',
        );
        expect(audioFormatDropdown, findsOneWidget);
        tester
            .widget<LazyDropdown<AudioFormat>>(audioFormatDropdown)
            .onChanged(AudioFormat.mp3);
        await tester.pumpAndSettle();

        // 4. Close modal via 'X'
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // 5. Enter URL and tap Download FAB
        final urlFieldFinder = find.byType(TextField).first;
        await tester.enterText(
          urlFieldFinder,
          'https://soundcloud.com/artist/track-456',
        );
        await tester.pumpAndSettle();

        final dlFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );
        await tester.tap(dlFabFinder);
        await tester.pumpAndSettle();

        // 6. Assert options payload
        expect(systemController.enqueuedDownloads, hasLength(1));
        final enqueued = systemController.enqueuedDownloads.first;
        expect(
          enqueued['url'],
          equals('https://soundcloud.com/artist/track-456'),
        );

        final Map<String, dynamic> optionsPayload =
            (enqueued['options'] as Map).cast<String, dynamic>();
        expect(optionsPayload['extract_audio'], isTrue);
        expect(optionsPayload['audio_format'], equals('mp3'));
      },
    );

    testWidgets(
      'Persisted options survive simulated cold reload and DownloadsScreen uses persisted options',
      (WidgetTester tester) async {
        // Set specific options directly in SharedPreferences
        final customOptions = DownloadOptions(
          playlist: true,
          extractAudio: true,
          audioFormat: AudioFormat.flac,
          videoResolution: VideoOption.resolution,
          videoResolutionValue: '720p',
          mergeOutputFormat: MergeOutputFormat.mp4,
          audioLanguage: AudioOption.language,
          audioLanguageCode: 'es',
          subLangs: ['en', 'es'],
        );
        await prefs.setString(
          'app_download_options',
          jsonEncode(customOptions.toJson()),
        );

        // Recreate settings repository and controller
        final coldSettingsRepo = SettingsRepository(prefs);
        final coldSettingsController = SettingsController(coldSettingsRepo);
        final coldDownloadsController = DownloadsController(
          downloadRepo,
          systemController,
        );

        await pumpTestScreen(
          tester,
          createAdversarialApp(
            downloadsController: coldDownloadsController,
            settingsController: coldSettingsController,
            localeController: localeController,
            systemController: systemController,
            updateController: updateController,
            downloadRepository: downloadRepo,
            sharedPreferences: prefs,
          ),
        );

        // Verify options in modal
        final qsFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
        );
        await tester.tap(qsFabFinder);
        await tester.pumpAndSettle();

        expect(find.text('FLAC'), findsWidgets);
        expect(coldSettingsController.downloadOptions.extractAudio, isTrue);
        expect(
          coldSettingsController.downloadOptions.audioFormat,
          equals(AudioFormat.flac),
        );

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Enqueue download directly
        final urlFieldFinder = find.byType(TextField).first;
        await tester.enterText(urlFieldFinder, 'https://example.com/audio.flac');
        await tester.pumpAndSettle();

        final dlFabFinder = find.byWidgetPredicate(
          (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
        );
        await tester.tap(dlFabFinder);
        await tester.pumpAndSettle();

        expect(systemController.enqueuedDownloads, hasLength(1));
        final options = systemController.enqueuedDownloads.first['options'];
        expect(options['extract_audio'], isTrue);
        expect(options['audio_format'], equals('flac'));
      },
    );
  });

  group('Adversarial Test 3: Tooltip & Accessibility Semantics Verification', () {
    testWidgets('English (en) Tooltips and Semantics are complete and correct', (
      WidgetTester tester,
    ) async {
      await pumpTestScreen(
        tester,
        createAdversarialApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      // 1. Quick Settings FAB Tooltip
      final qsFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
      );
      final FloatingActionButton qsFab = tester.widget(qsFabFinder);
      expect(qsFab.tooltip, equals('Quick Settings'));

      // 2. Download FAB Label
      final dlFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
      );
      expect(find.descendant(of: dlFabFinder, matching: find.text('Download')), findsOneWidget);

      // 3. Top bar tooltips
      final pasteFinder = find.byTooltip('Paste URL');
      expect(pasteFinder, findsOneWidget);

      final tutorialFinder = find.byTooltip('Show Tutorial');
      expect(tutorialFinder, findsOneWidget);

      final filtersFinder = find.byTooltip('Filters');
      expect(filtersFinder, findsOneWidget);

      final settingsFinder = find.byTooltip('Settings');
      expect(settingsFinder, findsOneWidget);

      // 4. Open Quick Settings modal and check Close tooltip
      await tester.tap(qsFabFinder);
      await tester.pumpAndSettle();

      final closeFinder = find.byTooltip('Close');
      expect(closeFinder, findsOneWidget);

      await tester.tap(closeFinder);
      await tester.pumpAndSettle();
    });

    testWidgets('Spanish (es) Tooltips and Semantics are complete and correct', (
      WidgetTester tester,
    ) async {
      final esLocaleController = LocaleController(mockLocaleRepo, 'es');
      await esLocaleController.whenReady;

      await pumpTestScreen(
        tester,
        createAdversarialApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: esLocaleController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      // 1. Quick Settings FAB Tooltip in Spanish
      final qsFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'quick_settings_fab',
      );
      final FloatingActionButton qsFab = tester.widget(qsFabFinder);
      expect(qsFab.tooltip, equals('Configuración rápida'));

      // 2. Download FAB Label in Spanish
      final dlFabFinder = find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'download_fab',
      );
      expect(find.descendant(of: dlFabFinder, matching: find.text('Descargar')), findsOneWidget);

      // 3. Top bar tooltips in Spanish
      expect(find.byTooltip('Pegar URL'), findsOneWidget);
      expect(find.byTooltip('Mostrar tutorial'), findsOneWidget);
      expect(find.byTooltip('Filtros'), findsOneWidget);
      expect(find.byTooltip('Ajustes'), findsOneWidget);

      // 4. Open Quick Settings modal and check Spanish strings
      await tester.tap(qsFabFinder);
      await tester.pumpAndSettle();

      expect(find.text(esLocaleController.localeStrings.qsTitle), findsOneWidget);
      expect(find.byTooltip(esLocaleController.localeStrings.qsClose), findsOneWidget);
      expect(find.text(esLocaleController.localeStrings.sPlaylist), findsOneWidget);
      expect(find.text(esLocaleController.localeStrings.sVideo), findsOneWidget);
      expect(find.text(esLocaleController.localeStrings.sExtractAudio), findsOneWidget);

      await tester.tap(find.byTooltip(esLocaleController.localeStrings.qsClose));
      await tester.pumpAndSettle();
    });
  });

  group('Adversarial Test 4: Zero Hardcoded Strings & Key Parity', () {
    test('DownloadsScreen and QuickSettingsBottomSheet source code contains zero raw UI strings', () {
      final dsFile = File('lib/features/downloads/presentation/downloads_screen.dart');
      final qsFile = File('lib/features/downloads/presentation/widgets/quick_settings_bottom_sheet.dart');

      expect(dsFile.existsSync(), isTrue);
      expect(qsFile.existsSync(), isTrue);

      final dsContent = dsFile.readAsStringSync();
      final qsContent = qsFile.readAsStringSync();

      // Check forbidden hardcoded strings that might have bypassed i18n
      final forbiddenHardcodedPatterns = [
        RegExp(r'''Text\(['"]Quick Settings['"]\)'''),
        RegExp(r'''Text\(['"]Configuración rápida['"]\)'''),
        RegExp(r'''Text\(['"]Download['"]\)'''),
        RegExp(r'''Text\(['"]Descargar['"]\)'''),
        RegExp(r'''Text\(['"]Playlist['"]\)'''),
        RegExp(r'''tooltip:\s*['"]Quick Settings['"]'''),
        RegExp(r'''tooltip:\s*['"]Close['"]'''),
        RegExp(r'''tooltip:\s*['"]Settings['"]'''),
        RegExp(r'''tooltip:\s*['"]Filters['"]'''),
        RegExp(r'''hintText:\s*['"]Search downloads['"]'''),
      ];

      for (final pattern in forbiddenHardcodedPatterns) {
        expect(
          pattern.hasMatch(dsContent),
          isFalse,
          reason: 'Hardcoded string pattern ${pattern.pattern} found in downloads_screen.dart',
        );
        expect(
          pattern.hasMatch(qsContent),
          isFalse,
          reason: 'Hardcoded string pattern ${pattern.pattern} found in quick_settings_bottom_sheet.dart',
        );
      }
    });

    test('Locale dictionary keys for Quick Settings and FAB exist in en.jsonc and es.jsonc', () {
      final enFile = File('i18n/en.jsonc');
      final esFile = File('i18n/es.jsonc');

      final enMap = (jsonc.decode(enFile.readAsStringSync()) as Map).cast<String, dynamic>();
      final esMap = (jsonc.decode(esFile.readAsStringSync()) as Map).cast<String, dynamic>();

      const requiredKeys = [
        'd_quick_settings',
        'qs_title',
        'qs_close',
        'qs_audio',
        'd_download',
        'd_video_url',
        'd_paste',
        'd_show_tutorial',
        'd_filters',
        'd_settings',
        's_playlist',
        's_playlist_desc',
        's_video',
        's_extract_audio',
        's_audio_format',
        's_video_resolution',
        's_merge_output_format',
        's_audio_language',
        's_sub_langs',
      ];

      for (final key in requiredKeys) {
        expect(enMap.containsKey(key), isTrue, reason: 'en.jsonc missing $key');
        expect(esMap.containsKey(key), isTrue, reason: 'es.jsonc missing $key');
        expect(enMap[key].toString().trim().isNotEmpty, isTrue, reason: 'en.jsonc empty $key');
        expect(esMap[key].toString().trim().isNotEmpty, isTrue, reason: 'es.jsonc empty $key');
      }
    });
  });

  group('Adversarial Test 5: Extreme Responsive Viewports & Layout Stress', () {
    testWidgets('Ultra narrow viewport (280x500) renders cleanly with no overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(280, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpTestScreen(
        tester,
        createAdversarialApp(
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

      // Open bottom sheet
      await tester.tap(find.byIcon(Icons.construction_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });

    testWidgets('Large tablet viewport (1024x768) constrains bottom sheet maxWidth to 640', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpTestScreen(
        tester,
        createAdversarialApp(
          downloadsController: downloadsController,
          settingsController: settingsController,
          localeController: localeController,
          systemController: systemController,
          updateController: updateController,
          downloadRepository: downloadRepo,
          sharedPreferences: prefs,
        ),
      );

      await tester.tap(find.byIcon(Icons.construction_outlined));
      await tester.pumpAndSettle();

      final constrainedBoxFinder = find.descendant(
        of: find.byType(QuickSettingsBottomSheet),
        matching: find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth == 640,
        ),
      );
      expect(constrainedBoxFinder, findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });
  });
}
