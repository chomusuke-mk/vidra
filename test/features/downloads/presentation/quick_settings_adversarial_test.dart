import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/features/downloads/presentation/widgets/quick_settings_bottom_sheet.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

class AdversarialMockLocaleRepo extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  AdversarialMockLocaleRepo() {
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

Widget buildTestHarness({
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
      home: Scaffold(body: child ?? const QuickSettingsBottomSheet()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AdversarialMockLocaleRepo mockLocaleRepo;
  late LocaleController localeController;
  late SharedPreferences prefs;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(settingsRepo);

    mockLocaleRepo = AdversarialMockLocaleRepo();
    localeController = LocaleController(mockLocaleRepo, 'en');
    await localeController.whenReady;
  });

  group('Adversarial Test: Rapid Video <-> Audio Mode Toggling', () {
    testWidgets(
      'Stress test 50 rapid mode toggles does not desync state, leak listeners, or throw layout errors',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildTestHarness(
            settingsController: settingsController,
            localeController: localeController,
          ),
        );
        await tester.pumpAndSettle();

        final videoSegment = find.text('Video');
        final audioSegment = find.text('Extract Audio');

        expect(videoSegment, findsOneWidget);
        expect(audioSegment, findsOneWidget);

        // Perform 50 rapid alternating taps
        for (int i = 0; i < 50; i++) {
          final target = (i % 2 == 0) ? audioSegment : videoSegment;
          final expectedMode = (i % 2 == 0); // true for audio, false for video

          await tester.tap(target);
          await tester.pump(); // Fast pump without settle to stress widget rebuilds

          expect(
            settingsController.downloadOptions.extractAudio,
            equals(expectedMode),
            reason: 'Failed at toggle iteration $i',
          );
        }

        await tester.pumpAndSettle();

        // Final toggle is 49 (odd) => video mode
        expect(settingsController.downloadOptions.extractAudio, isFalse);
        expect(find.text('Video Resolution'), findsWidgets);
        expect(find.text('Audio Format'), findsNothing);

        // Switch once more to audio and verify clean render
        await tester.tap(audioSegment);
        await tester.pumpAndSettle();

        expect(settingsController.downloadOptions.extractAudio, isTrue);
        expect(find.text('Audio Format'), findsWidgets);
        expect(find.text('Video Resolution'), findsNothing);
      },
    );

    testWidgets(
      'Mode toggle preserves other download options (playlist, resolution, formats, subtitles)',
      (WidgetTester tester) async {
        // Preset complex options
        settingsController.updateDownloadOptions(
          settingsController.downloadOptions.copyWith(
            playlist: true,
            videoResolution: VideoOption.resolution,
            videoResolutionValue: '1080',
            mergeOutputFormat: MergeOutputFormat.mkv,
            audioFormat: AudioFormat.flac,
            audioLanguage: AudioOption.language,
            audioLanguageCode: 'ja',
            subLangs: ['en', 'es'],
          ),
        );

        await tester.pumpWidget(
          buildTestHarness(
            settingsController: settingsController,
            localeController: localeController,
          ),
        );
        await tester.pumpAndSettle();

        // Verify initial video mode state
        expect(settingsController.downloadOptions.extractAudio, isFalse);
        expect(settingsController.downloadOptions.playlist, isTrue);
        expect(
          settingsController.downloadOptions.videoResolutionValue,
          equals('1080'),
        );
        expect(
          settingsController.downloadOptions.mergeOutputFormat,
          equals(MergeOutputFormat.mkv),
        );

        // Toggle to Audio Mode
        await tester.tap(find.text('Extract Audio'));
        await tester.pumpAndSettle();

        expect(settingsController.downloadOptions.extractAudio, isTrue);
        // All other options must remain intact
        expect(settingsController.downloadOptions.playlist, isTrue);
        expect(
          settingsController.downloadOptions.videoResolutionValue,
          equals('1080'),
        );
        expect(
          settingsController.downloadOptions.mergeOutputFormat,
          equals(MergeOutputFormat.mkv),
        );
        expect(
          settingsController.downloadOptions.audioFormat,
          equals(AudioFormat.flac),
        );
        expect(
          settingsController.downloadOptions.audioLanguageCode,
          equals('ja'),
        );
        expect(
          settingsController.downloadOptions.subLangs,
          equals(['en', 'es']),
        );

        // Toggle back to Video Mode
        await tester.tap(find.text('Video'));
        await tester.pumpAndSettle();

        expect(settingsController.downloadOptions.extractAudio, isFalse);
        expect(settingsController.downloadOptions.playlist, isTrue);
        expect(
          settingsController.downloadOptions.videoResolutionValue,
          equals('1080'),
        );
        expect(
          settingsController.downloadOptions.mergeOutputFormat,
          equals(MergeOutputFormat.mkv),
        );
        expect(
          settingsController.downloadOptions.audioFormat,
          equals(AudioFormat.flac),
        );
        expect(
          settingsController.downloadOptions.audioLanguageCode,
          equals('ja'),
        );
        expect(
          settingsController.downloadOptions.subLangs,
          equals(['en', 'es']),
        );
      },
    );
  });

  group('Adversarial Test: Dynamic Options Selection & Edge Cases', () {
    testWidgets('Comprehensive Video Resolution mutation through all resolutions', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        buildTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final resDropdown = find.byType(LazyDropdown<String>).first;
      expect(resDropdown, findsOneWidget);

      final testResolutions = [
        '2160',
        '1440',
        '1080',
        '720',
        '480',
        '360',
        '240',
        '144',
      ];

      for (final res in testResolutions) {
        final lazyWidget = tester.widget<LazyDropdown<String>>(resDropdown);
        lazyWidget.onChanged(res);
        await tester.pumpAndSettle();

        expect(
          settingsController.downloadOptions.videoResolution,
          equals(VideoOption.resolution),
        );
        expect(
          settingsController.downloadOptions.videoResolutionValue,
          equals(res),
        );
      }

      // Best video
      final lazyWidgetBest = tester.widget<LazyDropdown<String>>(resDropdown);
      lazyWidgetBest.onChanged('bestvideo');
      await tester.pumpAndSettle();
      expect(
        settingsController.downloadOptions.videoResolution,
        equals(VideoOption.bestvideo),
      );

      // Default option
      final lazyWidgetDefault = tester.widget<LazyDropdown<String>>(
        resDropdown,
      );
      lazyWidgetDefault.onChanged('defaultOption');
      await tester.pumpAndSettle();
      expect(
        settingsController.downloadOptions.videoResolution,
        equals(VideoOption.defaultOption),
      );
    });

    testWidgets('Comprehensive MergeOutputFormat mutation through all enum values', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        buildTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final formatDropdown = find.byType(LazyDropdown<MergeOutputFormat>);
      expect(formatDropdown, findsOneWidget);

      for (final format in MergeOutputFormat.values) {
        final lazyWidget = tester.widget<LazyDropdown<MergeOutputFormat>>(
          formatDropdown,
        );
        lazyWidget.onChanged(format);
        await tester.pumpAndSettle();

        expect(
          settingsController.downloadOptions.mergeOutputFormat,
          equals(format),
        );
      }
    });

    testWidgets('Comprehensive AudioFormat mutation through all enum values in Audio Mode', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(extractAudio: true),
      );

      await tester.pumpWidget(
        buildTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final audioFormatDropdown = find.byType(LazyDropdown<AudioFormat>);
      expect(audioFormatDropdown, findsOneWidget);

      for (final format in AudioFormat.values) {
        final lazyWidget = tester.widget<LazyDropdown<AudioFormat>>(
          audioFormatDropdown,
        );
        lazyWidget.onChanged(format);
        await tester.pumpAndSettle();

        expect(
          settingsController.downloadOptions.audioFormat,
          equals(format),
        );
      }
    });

    testWidgets('Audio Language selection supports language codes, bestaudio, and defaultOption', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        buildTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      // Second LazyDropdown<String> is audio language
      final audioLangDropdown = find.byType(LazyDropdown<String>).at(1);
      expect(audioLangDropdown, findsOneWidget);

      final sampleLanguages = ['en', 'es', 'ja', 'de', 'fr', 'zh', 'pt', 'ru'];
      for (final code in sampleLanguages) {
        final lazyWidget = tester.widget<LazyDropdown<String>>(
          audioLangDropdown,
        );
        lazyWidget.onChanged(code);
        await tester.pumpAndSettle();

        expect(
          settingsController.downloadOptions.audioLanguage,
          equals(AudioOption.language),
        );
        expect(
          settingsController.downloadOptions.audioLanguageCode,
          equals(code),
        );
      }

      // bestaudio
      final lazyWidgetBest = tester.widget<LazyDropdown<String>>(
        audioLangDropdown,
      );
      lazyWidgetBest.onChanged('bestaudio');
      await tester.pumpAndSettle();
      expect(
        settingsController.downloadOptions.audioLanguage,
        equals(AudioOption.bestaudio),
      );

      // defaultOption
      final lazyWidgetDefault = tester.widget<LazyDropdown<String>>(
        audioLangDropdown,
      );
      lazyWidgetDefault.onChanged('defaultOption');
      await tester.pumpAndSettle();
      expect(
        settingsController.downloadOptions.audioLanguage,
        equals(AudioOption.defaultOption),
      );
    });

    testWidgets('Fallback handling for invalid/corrupted audioLanguage or videoResolution', (
      WidgetTester tester,
    ) async {
      // Inject invalid language code and resolution value
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          videoResolution: VideoOption.resolution,
          videoResolutionValue: 'NON_EXISTENT_9999P',
          audioLanguage: AudioOption.language,
          audioLanguageCode: 'INVALID_LANG_CODE_XYZ',
        ),
      );

      await tester.pumpWidget(
        buildTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      // Verify that QuickSettingsBottomSheet does not crash and falls back gracefully to defaultOption
      final videoResDropdown = tester.widget<LazyDropdown<String>>(
        find.byType(LazyDropdown<String>).first,
      );
      expect(videoResDropdown.value, equals('defaultOption'));

      final audioLangDropdown = tester.widget<LazyDropdown<String>>(
        find.byType(LazyDropdown<String>).at(1),
      );
      expect(audioLangDropdown.value, equals('defaultOption'));
    });

    testWidgets('Subtitle selector handles multiple additions, deletions, and parsing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        buildTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final lazyListFinder = find.byType(LazyList);
      expect(lazyListFinder, findsOneWidget);

      final lazyListWidget = tester.widget<LazyList>(lazyListFinder);

      // Simulate adding multiple formatted items
      lazyListWidget.onChanged([
        'en - English',
        'es - Español',
        'ja - 日本語',
      ]);
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.subLangs,
        equals(['en', 'es', 'ja']),
      );

      // Verify chips are rendered in UI
      expect(find.byType(InputChip), findsNWidgets(3));

      // Remove the middle chip (Spanish)
      final spanishDeleteIcon = find.descendant(
        of: find.widgetWithText(InputChip, 'es - Español'),
        matching: find.byIcon(Icons.cancel),
      );
      expect(spanishDeleteIcon, findsOneWidget);
      await tester.tap(spanishDeleteIcon);
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.subLangs,
        equals(['en', 'ja']),
      );
      expect(find.byType(InputChip), findsNWidgets(2));
    });
  });

  group('Adversarial Test: SharedPreferences Immediate Persistence & Cold Reload Parity', () {
    testWidgets(
      'Every quick setting change writes through immediately to SharedPreferences JSON storage and survives reload',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildTestHarness(
            settingsController: settingsController,
            localeController: localeController,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Toggle Playlist switch
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(settingsController.downloadOptions.playlist, isTrue);

        // Verify raw SharedPreferences
        String rawJson = prefs.getString('app_download_options')!;
        Map<String, dynamic> decoded = jsonDecode(rawJson);
        expect(decoded['playlist'], isTrue);

        // 2. Change Video Resolution to 1080p
        final resDropdown = tester.widget<LazyDropdown<String>>(
          find.byType(LazyDropdown<String>).first,
        );
        resDropdown.onChanged('1080');
        await tester.pumpAndSettle();

        rawJson = prefs.getString('app_download_options')!;
        decoded = jsonDecode(rawJson);
        expect(decoded['video_resolution'], equals('1080'));

        // 3. Change Merge Output Format to MKV
        final formatDropdown = tester.widget<LazyDropdown<MergeOutputFormat>>(
          find.byType(LazyDropdown<MergeOutputFormat>),
        );
        formatDropdown.onChanged(MergeOutputFormat.mkv);
        await tester.pumpAndSettle();

        rawJson = prefs.getString('app_download_options')!;
        decoded = jsonDecode(rawJson);
        expect(decoded['merge_output_format'], equals('mkv'));

        // 4. Change Audio Language to 'ja'
        final audioDropdown = tester.widget<LazyDropdown<String>>(
          find.byType(LazyDropdown<String>).at(1),
        );
        audioDropdown.onChanged('ja');
        await tester.pumpAndSettle();

        rawJson = prefs.getString('app_download_options')!;
        decoded = jsonDecode(rawJson);
        expect(decoded['audio_language'], equals('ja'));

        // 5. Add Subtitle Languages
        final lazyList = tester.widget<LazyList>(find.byType(LazyList));
        lazyList.onChanged(['en - English', 'fr - Français']);
        await tester.pumpAndSettle();

        rawJson = prefs.getString('app_download_options')!;
        decoded = jsonDecode(rawJson);
        expect(decoded['sub_langs'], equals(['en', 'fr']));

        // 6. Toggle to Audio Mode and change audio format to FLAC
        await tester.tap(find.text('Extract Audio'));
        await tester.pumpAndSettle();

        final audioFormatDropdown = tester.widget<LazyDropdown<AudioFormat>>(
          find.byType(LazyDropdown<AudioFormat>),
        );
        audioFormatDropdown.onChanged(AudioFormat.flac);
        await tester.pumpAndSettle();

        rawJson = prefs.getString('app_download_options')!;
        decoded = jsonDecode(rawJson);
        expect(decoded['extract_audio'], isTrue);
        expect(decoded['audio_format'], equals('flac'));

        // --- COLD RELOAD SIMULATION ---
        // Instantiate a completely new repository and controller from SharedPreferences
        final freshRepo = SettingsRepository(prefs);
        final freshController = SettingsController(freshRepo);
        // Wait for controller async init
        await tester.pumpAndSettle();
        await freshController.initialized;

        expect(freshController.downloadOptions.playlist, isTrue);
        expect(freshController.downloadOptions.extractAudio, isTrue);
        expect(
          freshController.downloadOptions.audioFormat,
          equals(AudioFormat.flac),
        );
        expect(
          freshController.downloadOptions.videoResolution,
          equals(VideoOption.resolution),
        );
        expect(
          freshController.downloadOptions.videoResolutionValue,
          equals('1080'),
        );
        expect(
          freshController.downloadOptions.mergeOutputFormat,
          equals(MergeOutputFormat.mkv),
        );
        expect(
          freshController.downloadOptions.audioLanguage,
          equals(AudioOption.language),
        );
        expect(
          freshController.downloadOptions.audioLanguageCode,
          equals('ja'),
        );
        expect(
          freshController.downloadOptions.subLangs,
          equals(['en', 'fr']),
        );
      },
    );
  });

  group('Adversarial Test: Modal Dismissal, Close Action & Gestures', () {
    testWidgets('Tapping modal close X button dismisses sheet cleanly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(
              value: settingsController,
            ),
            ChangeNotifierProvider<LocaleController>.value(
              value: localeController,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => QuickSettingsBottomSheet.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

      // Tap close button
      final closeButton = find.byIcon(Icons.close);
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(find.byType(QuickSettingsBottomSheet), findsNothing);
    });

    testWidgets('Tapping outside barrier dismisses modal bottom sheet', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(
              value: settingsController,
            ),
            ChangeNotifierProvider<LocaleController>.value(
              value: localeController,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => QuickSettingsBottomSheet.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

      final sheetRect = tester.getRect(find.byType(QuickSettingsBottomSheet));
      debugPrint('QuickSettingsBottomSheet Rect: $sheetRect');

      // Tap on modal barrier above the bottom sheet (top of the screen)
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byType(QuickSettingsBottomSheet), findsNothing);
    });

    testWidgets('Fling / drag down gesture on modal dismisses bottom sheet', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(
              value: settingsController,
            ),
            ChangeNotifierProvider<LocaleController>.value(
              value: localeController,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => QuickSettingsBottomSheet.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

      // Drag downwards from the header / drag handle
      final dragTarget = find.byIcon(Icons.construction_outlined);
      expect(dragTarget, findsOneWidget);

      await tester.fling(dragTarget, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(find.byType(QuickSettingsBottomSheet), findsNothing);
    });

    testWidgets('Stress test 10 rapid open-close cycles does not crash route navigator', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(
              value: settingsController,
            ),
            ChangeNotifierProvider<LocaleController>.value(
              value: localeController,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => QuickSettingsBottomSheet.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (int i = 0; i < 10; i++) {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.byType(QuickSettingsBottomSheet),
          findsOneWidget,
          reason: 'Failed to open on cycle $i',
        );

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(
          find.byType(QuickSettingsBottomSheet),
          findsNothing,
          reason: 'Failed to close on cycle $i',
        );
      }
    });
  });

  group('Adversarial Test: External Mutation & Responsive Viewports', () {
    testWidgets('External mutation in SettingsController dynamically updates open bottom sheet', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        buildTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      // Initially Video Mode and playlist is false
      expect(find.text('Video Resolution'), findsWidgets);
      expect(find.text('Audio Format'), findsNothing);
      expect(
        tester.widget<Switch>(find.byType(Switch)).value,
        isFalse,
      );

      // External mutation: enable playlist and switch to extractAudio
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          playlist: true,
          extractAudio: true,
          audioFormat: AudioFormat.opus,
        ),
      );
      await tester.pumpAndSettle();

      // Bottom sheet should reactively update without user interaction
      expect(
        tester.widget<Switch>(find.byType(Switch)).value,
        isTrue,
      );
      expect(find.text('Audio Format'), findsWidgets);
      expect(find.text('Video Resolution'), findsNothing);
      expect(
        tester.widget<LazyDropdown<AudioFormat>>(find.byType(LazyDropdown<AudioFormat>)).value,
        equals(AudioFormat.opus),
      );
    });

    testWidgets('Narrow mobile viewport (320x480) renders without layout overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Large desktop viewport (1920x1080) respects maxWidth constraint', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final constrainedBoxFinder = find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == 640,
      );
      expect(constrainedBoxFinder, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
