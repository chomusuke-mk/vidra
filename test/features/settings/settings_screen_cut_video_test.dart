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

  group('SettingsScreen Video Cutter Setting Tests', () {
    testWidgets('Cut Video setting row is visible under Download category with master switch', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Navigate to Download category tab
      final downloadTab = find.byIcon(Icons.download);
      expect(downloadTab, findsOneWidget);
      await tester.tap(downloadTab);
      await tester.pumpAndSettle();

      // Verify Cut Video setting title and description
      expect(find.text(localeController.localeStrings.sCutVideo), findsWidgets);
      expect(find.text(localeController.localeStrings.sCutVideoDesc), findsWidgets);

      // Initially OFF -> InlineTimePicker is not rendered
      expect(find.byType(InlineTimePicker), findsNothing);
    });

    testWidgets('Toggling Cut Video ON inside SettingsScreen expands Start picker and UntilEnd switch', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Navigate to Download tab
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      final masterSwitch = find.widgetWithText(
        SwitchListTile,
        localeController.localeStrings.sCutVideo,
      );
      expect(masterSwitch, findsOneWidget);

      await tester.tap(masterSwitch);
      await tester.pumpAndSettle();

      expect(settingsController.downloadOptions.cutVideo, isTrue);
      expect(find.byType(InlineTimePicker), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoStart), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoUntilEnd), findsOneWidget);
    });

    testWidgets('Toggling UntilEnd OFF expands End InlineTimePicker and updates state', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cutVideo: true,
          cutVideoUntilEnd: true,
          cutVideoStart: 120,
          cutVideoEnd: 300,
        ),
      );

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Navigate to Download tab
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      expect(find.byType(InlineTimePicker), findsOneWidget);

      // Toggle UntilEnd switch OFF
      final untilEndSwitch = find.widgetWithText(
        SwitchListTile,
        localeController.localeStrings.sCutVideoUntilEnd,
      );
      expect(untilEndSwitch, findsOneWidget);

      await tester.tap(untilEndSwitch);
      await tester.pumpAndSettle();

      expect(settingsController.downloadOptions.cutVideoUntilEnd, isFalse);
      expect(find.byType(InlineTimePicker), findsNWidgets(2));
      expect(find.text(localeController.localeStrings.sCutVideoStart), findsOneWidget);
      expect(find.text(localeController.localeStrings.sCutVideoEnd), findsOneWidget);
    });
  });
}
