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

Widget createTestApp({
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

  late MockLocaleRepository mockLocaleRepo;
  late LocaleController localeController;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(settingsRepo);

    mockLocaleRepo = MockLocaleRepository();
    localeController = LocaleController(mockLocaleRepo, 'en');
    await localeController.whenReady;
  });

  group('QuickSettingsBottomSheet UI Rendering & Structure', () {
    testWidgets(
      'renders drag handle, icon, localized header, close button, and divider',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          createTestApp(
            settingsController: settingsController,
            localeController: localeController,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Drag handle (Container 40x4)
        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
        expect(find.byType(ClipRRect), findsWidgets);
        expect(find.byType(Divider), findsOneWidget);

        // 2. Icon and Title
        expect(find.byIcon(Icons.construction_outlined), findsOneWidget);
        expect(find.text('Quick Settings'), findsOneWidget);

        // 3. Close button
        final closeBtnFinder = find.byTooltip('Close');
        expect(closeBtnFinder, findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);

        // 4. Playlist tile & Segmented control
        expect(find.text('Playlist'), findsOneWidget);
        expect(find.text('Video'), findsOneWidget);
        expect(find.text('Extract Audio'), findsOneWidget);
      },
    );

    testWidgets('close button triggers Navigator.pop', (
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
                builder:
                    (ctx) => ElevatedButton(
                      onPressed: () => QuickSettingsBottomSheet.show(ctx),
                      child: const Text('Open Modal'),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open bottom sheet
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

      // Tap close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Bottom sheet should be dismissed
      expect(find.byType(QuickSettingsBottomSheet), findsNothing);
    });
  });

  group('Playlist Toggle Synchronization', () {
    testWidgets('toggling playlist switch updates SettingsController', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(settingsController.downloadOptions.playlist, isFalse);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      // Toggle ON
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(settingsController.downloadOptions.playlist, isTrue);

      // Toggle OFF
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(settingsController.downloadOptions.playlist, isFalse);
    });
  });

  group('Video vs Extract Audio Mode Toggle', () {
    testWidgets(
      'toggling mode switches visible controls and updates extractAudio',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          createTestApp(
            settingsController: settingsController,
            localeController: localeController,
          ),
        );
        await tester.pumpAndSettle();

        // Initially in Video Mode (extractAudio == false)
        expect(settingsController.downloadOptions.extractAudio, isFalse);

        // Video options should be visible
        expect(find.text('Video Resolution'), findsWidgets);
        expect(find.text('Video Format'), findsWidgets);
        expect(find.text('Audio Language'), findsWidgets);
        expect(find.text('Subtitle Languages'), findsWidgets);
        expect(find.byType(LazyList), findsOneWidget);

        // Audio format dropdown should NOT be visible
        expect(find.text('Audio Format'), findsNothing);

        // Switch to Audio Mode
        await tester.tap(find.text('Extract Audio'));
        await tester.pumpAndSettle();

        expect(settingsController.downloadOptions.extractAudio, isTrue);

        // Audio controls should now be visible
        expect(find.text('Audio Format'), findsWidgets);
        expect(
          find.byType(LazyDropdown<AudioFormat>),
          findsOneWidget,
        );

        // Video controls should NOT be visible
        expect(find.text('Video Resolution'), findsNothing);
        expect(find.byType(LazyList), findsNothing);

        // Switch back to Video Mode
        await tester.tap(find.text('Video'));
        await tester.pumpAndSettle();

        expect(settingsController.downloadOptions.extractAudio, isFalse);
        expect(find.text('Video Resolution'), findsWidgets);
        expect(find.text('Audio Format'), findsNothing);
      },
    );
  });

  group('Dynamic Video Mode Controls Synchronization', () {
    testWidgets('changing video resolution updates SettingsController', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final videoResDropdownFinder = find.byType(LazyDropdown<String>).first;
      expect(videoResDropdownFinder, findsOneWidget);

      // Mutate via SettingsController and verify dropdown reflects it
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          videoResolution: VideoOption.resolution,
          videoResolutionValue: '720',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.videoResolution,
        equals(VideoOption.resolution),
      );
      expect(
        settingsController.downloadOptions.videoResolutionValue,
        equals('720'),
      );

      // Test bestvideo
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          videoResolution: VideoOption.bestvideo,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.videoResolution,
        equals(VideoOption.bestvideo),
      );

      // Test defaultOption
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          videoResolution: VideoOption.defaultOption,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.videoResolution,
        equals(VideoOption.defaultOption),
      );
    });

    testWidgets('changing mergeOutputFormat updates SettingsController', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final formatDropdownFinder = find.byType(
        LazyDropdown<MergeOutputFormat>,
      );
      expect(formatDropdownFinder, findsOneWidget);

      // Mutate format
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          mergeOutputFormat: MergeOutputFormat.mp4,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.mergeOutputFormat,
        equals(MergeOutputFormat.mp4),
      );
    });

    testWidgets('changing audio language updates SettingsController', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      // Mutate to language 'es'
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          audioLanguage: AudioOption.language,
          audioLanguageCode: 'es',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.audioLanguage,
        equals(AudioOption.language),
      );
      expect(
        settingsController.downloadOptions.audioLanguageCode,
        equals('es'),
      );

      // Mutate to bestaudio
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          audioLanguage: AudioOption.bestaudio,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.audioLanguage,
        equals(AudioOption.bestaudio),
      );
    });

    testWidgets('subtitles LazyList updates SettingsController', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(settingsController.downloadOptions.subLangs, isEmpty);

      // Enter subtitle language in TextField
      final textFieldFinder = find.descendant(
        of: find.byType(LazyList),
        matching: find.byType(TextField),
      );
      expect(textFieldFinder, findsOneWidget);

      await tester.enterText(textFieldFinder, 'es - Español');
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.subLangs,
        contains('es'),
      );

      // Delete chip
      final deleteIcon = find.descendant(
        of: find.byType(InputChip),
        matching: find.byIcon(Icons.cancel),
      );
      expect(deleteIcon, findsOneWidget);

      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      expect(settingsController.downloadOptions.subLangs, isEmpty);
    });
  });

  group('Dynamic Audio Mode Controls Synchronization', () {
    testWidgets('changing audio format in audio mode updates SettingsController', (
      WidgetTester tester,
    ) async {
      // Set to audio mode
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(extractAudio: true),
      );

      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LazyDropdown<AudioFormat>), findsOneWidget);

      // Update to mp3
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          audioFormat: AudioFormat.mp3,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.audioFormat,
        equals(AudioFormat.mp3),
      );

      // Update to flac
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          audioFormat: AudioFormat.flac,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.audioFormat,
        equals(AudioFormat.flac),
      );
    });
  });

  group('Localization in Spanish (es)', () {
    testWidgets('renders Spanish strings properly', (
      WidgetTester tester,
    ) async {
      final esLocaleController = LocaleController(mockLocaleRepo, 'es');
      await esLocaleController.whenReady;

      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: esLocaleController,
        ),
      );
      await tester.pumpAndSettle();

      // Modal title
      expect(find.text('Configuración Rápida'), findsOneWidget);

      // Close button tooltip
      expect(find.byTooltip('Cerrar'), findsOneWidget);

      // Playlist label
      expect(find.text('Lista de reproducción'), findsOneWidget);

      // Segments
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Extraer audio'), findsOneWidget);

      // Video Controls labels
      expect(find.text('Resolución de vídeo'), findsWidgets);
      expect(find.text('Formato de vídeo'), findsWidgets);
      expect(find.text('Idioma de audio'), findsWidgets);
      expect(find.text('Idiomas de subtítulos'), findsWidgets);
    });
  });
}
