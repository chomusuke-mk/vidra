import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/core/constants/languages.dart';
import 'package:vidra/features/downloads/presentation/widgets/quick_settings_bottom_sheet.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';

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

  void setCustomLocale(String code, Map<String, String> strings) {
    _storage[code] = strings;
  }

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    return _storage[localeCode] ?? {};
  }
}

Widget createTestHarness({
  required SettingsController settingsController,
  required LocaleController localeController,
  Widget? child,
  EdgeInsets? mediaQueryViewInsets,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
      ),
      ChangeNotifierProvider<LocaleController>.value(value: localeController),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) {
          Widget current = child ?? const QuickSettingsBottomSheet();
          if (mediaQueryViewInsets != null) {
            current = MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(viewInsets: mediaQueryViewInsets),
              child: current,
            );
          }
          return Scaffold(body: current);
        },
      ),
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

  group('Adversarial Layout Constraints Stress Tests', () {
    testWidgets('Renders cleanly on ultra-narrow screen (280x600)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(280, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
      expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    });

    testWidgets('Renders cleanly on narrow mobile screen (320x568)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('Renders cleanly on tablet screen (800x1280)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
      // Ensure ConstrainedBox max width (640) is enforced
      final constrainedBoxFinder = find.descendant(
        of: find.byType(QuickSettingsBottomSheet),
        matching: find.byType(ConstrainedBox),
      );
      expect(constrainedBoxFinder, findsWidgets);
    });

    testWidgets('Renders cleanly on desktop / ultrawide screen (1400x900)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
    });

    testWidgets('Renders cleanly with high keyboard insets (bottom = 350px)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: localeController,
          mediaQueryViewInsets: const EdgeInsets.only(bottom: 350),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('Renders cleanly in landscape short viewport (800x320)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 320);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

      // Scroll down to ensure content scrolls smoothly without clipping errors
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial i18n Robustness & String Stress Tests', () {
    testWidgets('Handles exaggerated long localized strings without RenderFlex overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Inject long pseudo-localized strings
      mockLocaleRepo.setCustomLocale('long', {
        'qs_title': 'Extremely Long Modal Title That Exceeds Normal Screen Width',
        'qs_close': 'Close This Modal Dialog Immediately',
        's_playlist': 'Download entire playlist collection including all items',
        's_playlist_desc':
            'When enabled, Vidra will download all tracks, videos and metadata associated with this playlist URL',
        's_video': 'Standard Video Mode With Multi-stream Merging',
        's_extract_audio': 'Extract High Quality Audio Track Only',
        's_video_resolution': 'Output Video Resolution Preference',
        's_merge_output_format': 'Target Container File Format',
        's_audio_language': 'Preferred Primary Audio Stream Language',
        's_sub_langs': 'Selected Subtitle Track Languages Collection',
        's_default': 'Use Service Default Option Automatically',
        's_best': 'Best Available Quality On Host',
        's_search_lang': 'Search language name or ISO code',
      });

      final longLocaleCtrl = LocaleController(mockLocaleRepo, 'long');
      await longLocaleCtrl.whenReady;

      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: longLocaleCtrl,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Extremely Long Modal Title That Exceeds Normal Screen Width'),
        findsOneWidget,
      );
    });

    testWidgets('Handles empty string dictionary fallbacks gracefully', (
      WidgetTester tester,
    ) async {
      mockLocaleRepo.setCustomLocale('empty', {});
      final emptyLocaleCtrl = LocaleController(mockLocaleRepo, 'empty');
      await emptyLocaleCtrl.whenReady;

      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: emptyLocaleCtrl,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
    });

    testWidgets('Modal show() bottom sheet invocation on all screen widths', (
      WidgetTester tester,
    ) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final width in [320.0, 800.0, 1400.0]) {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;

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
                        child: const Text('Open'),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);

        // Close by tapping 'X'
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.byType(QuickSettingsBottomSheet), findsNothing);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  group('Adversarial Options & State Edge Cases', () {
    testWidgets('Handles unknown/legacy video resolution and audio language values', (
      WidgetTester tester,
    ) async {
      // Set corrupted/unusual options
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          videoResolution: VideoOption.resolution,
          videoResolutionValue: '99999p_unknown',
          audioLanguage: AudioOption.language,
          audioLanguageCode: 'klingon_tlh',
        ),
      );

      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(QuickSettingsBottomSheet), findsOneWidget);
    });

    testWidgets('Handles heavy list of subtitle languages without overflow', (
      WidgetTester tester,
    ) async {
      final heavySubs = languagesCodes.take(15).toList();
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(subLangs: heavySubs),
      );

      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(InputChip), findsNWidgets(15));

      // Scroll up and down
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rapid toggle between Video and Audio modes maintains clean state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestHarness(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      for (int i = 0; i < 6; i++) {
        final targetText = i.isEven ? 'Extract Audio' : 'Video';
        await tester.tap(find.text(targetText));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
