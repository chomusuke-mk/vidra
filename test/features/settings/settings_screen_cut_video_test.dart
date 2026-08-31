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

  Widget createTestApp() {
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

  void configureViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('SettingsScreen Settings Tests', () {
    testWidgets('Cut Video setting is not in SettingsScreen (moved to CutVideoBottomSheet in Downloads)', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Navigate to Download category tab
      final downloadTab = find.byIcon(Icons.download);
      expect(downloadTab, findsOneWidget);
      await tester.tap(downloadTab);
      await tester.pumpAndSettle();

      // Verify Cut Video is not rendered in SettingsScreen
      expect(find.text(localeController.localeStrings.sCutVideo), findsNothing);
    });

    testWidgets('General category tab renders standard settings like extractAudio', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Verify sExtractAudio setting is rendered
      expect(find.text(localeController.localeStrings.sExtractAudio), findsOneWidget);

      final rowFinder = find.ancestor(
        of: find.text(localeController.localeStrings.sExtractAudio),
        matching: find.byType(SettingRow),
      );
      final switchFinder = find.descendant(
        of: rowFinder,
        matching: find.byType(Switch),
      );

      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(settingsController.downloadOptions.extractAudio, isTrue);
    });
  });
}
