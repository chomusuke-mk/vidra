import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/settings/presentation/settings_screen.dart';
import 'package:vidra/shared/widgets/inline_time_picker.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late MockLocaleRepository mockLocaleRepo;
  late LocaleController localeController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'has_seen_settings_tutorial': true});
    prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_settings_tutorial', true);
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(settingsRepo);

    mockLocaleRepo = MockLocaleRepository();
    localeController = LocaleController(mockLocaleRepo, 'en');
    await localeController.whenReady;
  });

  Widget createSettingsApp() {
    return MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(
          value: prefs,
        ),
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
        ChangeNotifierProvider<LocaleController>.value(
          value: localeController,
        ),
      ],
      child: const MaterialApp(
        home: SettingsScreen(),
      ),
    );
  }

  group('SettingsScreen — Video Cutter Multi-State & Rapid Toggling Stress', () {
    testWidgets('Rapid 20x master switch toggling under Download tab', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Download tab
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      final masterSwitchFinder = find.widgetWithText(
        SwitchListTile,
        localeController.localeStrings.sCutVideo,
      );
      expect(masterSwitchFinder, findsOneWidget);

      for (int i = 0; i < 20; i++) {
        await tester.tap(masterSwitchFinder);
        await tester.pump();
        final expected = (i % 2 == 0);
        expect(settingsController.downloadOptions.cutVideo, equals(expected));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rapid 20x UntilEnd switch toggling under Download tab', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cutVideo: true,
          cutVideoUntilEnd: true,
        ),
      );

      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Download tab
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      final untilEndSwitchFinder = find.widgetWithText(
        SwitchListTile,
        localeController.localeStrings.sCutVideoUntilEnd,
      );
      expect(untilEndSwitchFinder, findsOneWidget);

      for (int i = 0; i < 20; i++) {
        await tester.tap(untilEndSwitchFinder);
        await tester.pump();
        final expected = (i % 2 != 0);
        expect(settingsController.downloadOptions.cutVideoUntilEnd, equals(expected));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tab switching churn preserves Cut Video state integrity', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cutVideo: true,
          cutVideoUntilEnd: false,
          cutVideoStart: 45,
          cutVideoEnd: 150,
        ),
      );

      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Switch to General tab
      await tester.tap(find.byIcon(Icons.settings).last);
      await tester.pumpAndSettle();

      // Switch to Network tab
      await tester.tap(find.byIcon(Icons.wifi));
      await tester.pumpAndSettle();

      // Switch back to Download tab
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      expect(settingsController.downloadOptions.cutVideo, isTrue);
      expect(settingsController.downloadOptions.cutVideoUntilEnd, isFalse);
      expect(settingsController.downloadOptions.cutVideoStart, equals(45));
      expect(settingsController.downloadOptions.cutVideoEnd, equals(150));
      expect(find.byType(InlineTimePicker), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsScreen — Multi-Viewport Matrix (320x568 to 1400x900)', () {
    const viewports = [
      Size(320, 568),
      Size(360, 640),
      Size(800, 1280),
      Size(1400, 900),
    ];

    for (final vp in viewports) {
      testWidgets('Renders SettingsScreen with expanded Cut Video setting without overflow on ${vp.width.toInt()}x${vp.height.toInt()}', (
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
            cutVideo: true,
            cutVideoUntilEnd: false,
            cutVideoStart: 10,
            cutVideoEnd: 60,
          ),
        );

        await tester.pumpWidget(createSettingsApp());
        await tester.pumpAndSettle();

        // Navigate to Download tab
        await tester.tap(find.byIcon(Icons.download));
        await tester.pumpAndSettle();

        expect(find.text(localeController.localeStrings.sCutVideo), findsWidgets);
        expect(find.byType(InlineTimePicker), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('SettingsScreen — Runtime Dynamic Locale Switch', () {
    testWidgets('Live dynamic locale switch EN <-> ES in SettingsScreen Download tab', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cutVideo: true,
          cutVideoUntilEnd: false,
        ),
      );

      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Download tab in English
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.sCutVideo), findsWidgets);
      expect(find.text(localeController.localeStrings.sCutVideoStart), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoEnd), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoUntilEnd), findsOneWidget);

      // Switch to Spanish
      localeController.setLocale('es');
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.sCutVideo), findsWidgets);
      expect(find.text(localeController.localeStrings.sCutVideoStart), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoEnd), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoUntilEnd), findsOneWidget);

      // Switch back to English
      localeController.setLocale('en');
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.sCutVideo), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
