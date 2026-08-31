import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/settings/presentation/settings_screen.dart';
import 'package:vidra/shared/widgets/settings_row.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;
  late MockLocaleRepository mockLocaleRepo;
  late LocaleController localeController;
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('vidra_ui_stress_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );

    SharedPreferences.setMockInitialValues({'has_seen_settings_tutorial': true});
    prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_settings_tutorial', true);
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(settingsRepo);

    mockLocaleRepo = MockLocaleRepository();
    localeController = LocaleController(mockLocaleRepo, 'en');
    await localeController.whenReady;
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
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

  void configureViewport(WidgetTester tester, [Size size = const Size(1200, 2400)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('SettingsScreen — Multi-State & Rapid Toggling Stress', () {
    testWidgets('Rapid 20x extractAudio switch toggling under General tab', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final rowFinder = find.ancestor(
        of: find.text(localeController.localeStrings.sExtractAudio),
        matching: find.byType(SettingRow),
      );
      final switchFinder = find.descendant(
        of: rowFinder,
        matching: find.byType(Switch),
      );
      expect(switchFinder, findsOneWidget);

      for (int i = 0; i < 20; i++) {
        await tester.tap(switchFinder);
        await tester.pump(const Duration(milliseconds: 50));
        final expected = (i % 2 == 0);
        expect(settingsController.downloadOptions.extractAudio, equals(expected));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rapid 20x cookiesFromWebview switch toggling under Network tab', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      final rowFinder = find.ancestor(
        of: find.text(localeController.localeStrings.sCookiesFromWebview),
        matching: find.byType(SettingRow),
      );
      final switchFinder = find.descendant(
        of: rowFinder,
        matching: find.byType(Switch),
      );
      expect(switchFinder, findsOneWidget);

      for (int i = 0; i < 20; i++) {
        await tester.tap(switchFinder);
        await tester.pump(const Duration(milliseconds: 50));
        final expectedDisabled = (i % 2 == 0);
        expect(settingsController.downloadOptions.disableCookiesFromWebview, equals(expectedDisabled));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tab switching churn preserves settings state integrity', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          extractAudio: true,
          disableCookiesFromWebview: false,
          cookiesFromWebview: '/tmp/test_cookies.txt',
        ),
      );

      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Switch to General tab
      await tester.tap(find.byIcon(Icons.settings).last);
      await tester.pumpAndSettle();
      expect(settingsController.downloadOptions.extractAudio, isTrue);

      // Switch to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isFalse);

      // Switch to Video tab
      await tester.tap(find.byIcon(Icons.movie).first);
      await tester.pumpAndSettle();

      // Switch to Download tab
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      expect(settingsController.downloadOptions.extractAudio, isTrue);
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isFalse);
      expect(settingsController.downloadOptions.cookiesFromWebview, equals('/tmp/test_cookies.txt'));
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
      testWidgets('Renders SettingsScreen without overflow on ${vp.width.toInt()}x${vp.height.toInt()}', (
        WidgetTester tester,
      ) async {
        configureViewport(tester, vp);

        await tester.pumpWidget(createSettingsApp());
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('SettingsScreen — Runtime Dynamic Locale Switch', () {
    testWidgets('Live dynamic locale switch EN <-> ES in SettingsScreen Network tab', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Network tab in English
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.sCookiesFromWebview), findsOneWidget);
      expect(find.text(localeController.localeStrings.sOpenWebview), findsOneWidget);

      // Switch to Spanish
      localeController.setLocale('es');
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.sCookiesFromWebview), findsOneWidget);
      expect(find.text(localeController.localeStrings.sOpenWebview), findsOneWidget);

      // Switch back to English
      localeController.setLocale('en');
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.sCookiesFromWebview), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
