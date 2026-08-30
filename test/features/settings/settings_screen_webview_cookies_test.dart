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
import 'package:vidra/features/settings/presentation/widgets/in_app_webview_screen.dart';
import 'package:vidra/shared/widgets/lazy_text_field.dart';
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

  Widget createSettingsApp({Locale? locale}) {
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
      child: MaterialApp(
        locale: locale,
        home: const SettingsScreen(),
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

  group('SettingsScreen — Cookies From WebView Setting UI & Controller Integration', () {
    testWidgets('Setting renders in Network tab before "Cookies"', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Network tab
      final networkTab = find.byIcon(Icons.wifi);
      expect(networkTab, findsWidgets);
      await tester.tap(networkTab.first);
      await tester.pumpAndSettle();

      // Verify title and description from locale
      final webviewCookiesTitle = localeController.localeStrings.sCookiesFromWebview;
      final webviewCookiesDesc = localeController.localeStrings.sCookiesFromWebviewDesc;
      final cookiesTitle = localeController.localeStrings.sCookies;

      expect(webviewCookiesTitle.isNotEmpty, isTrue);
      expect(webviewCookiesDesc.isNotEmpty, isTrue);
      expect(find.text(webviewCookiesTitle), findsOneWidget);
      expect(find.text(webviewCookiesDesc), findsOneWidget);

      // Verify setting position: appears before locale.sCookies
      expect(find.text(cookiesTitle), findsOneWidget);
      final webviewTitleTop = tester.getTopLeft(find.text(webviewCookiesTitle)).dy;
      final cookiesTitleTop = tester.getTopLeft(find.text(cookiesTitle)).dy;
      expect(
        webviewTitleTop,
        lessThan(cookiesTitleTop),
        reason: 'Cookies from WebView must be positioned before Cookies',
      );
    });

    testWidgets('Initially disabled: Switch is OFF, button & text field are hidden', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      // Initial state is disableCookiesFromWebview == true
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isTrue);

      // Find the SettingRow for WebView Cookies
      final settingRowFinder = find.ancestor(
        of: find.text(localeController.localeStrings.sCookiesFromWebview),
        matching: find.byType(SettingRow),
      );
      expect(settingRowFinder, findsOneWidget);

      // Find the Switch within the SettingRow
      final switchFinder = find.descendant(
        of: settingRowFinder,
        matching: find.byType(Switch),
      );
      expect(switchFinder, findsOneWidget);
      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isFalse);

      // Open button and text field should NOT be present
      expect(find.text(localeController.localeStrings.sOpenWebview), findsNothing);
      expect(find.byIcon(Icons.open_in_browser), findsNothing);
      expect(
        find.descendant(
          of: settingRowFinder,
          matching: find.byType(LazyTextField),
        ),
        findsNothing,
      );
    });

    testWidgets('Toggling Switch ON sets disableCookiesFromWebview: false and renders action button and text field', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      final settingRowFinder = find.ancestor(
        of: find.text(localeController.localeStrings.sCookiesFromWebview),
        matching: find.byType(SettingRow),
      );
      final switchFinder = find.descendant(
        of: settingRowFinder,
        matching: find.byType(Switch),
      );

      // Tap Switch ON
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Verify controller state
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isFalse);

      // Verify Switch value is now true
      final updatedSwitch = tester.widget<Switch>(switchFinder);
      expect(updatedSwitch.value, isTrue);

      // Verify Action Button with localized label and icon
      final openButtonFinder = find.text(localeController.localeStrings.sOpenWebview);
      expect(openButtonFinder, findsOneWidget);
      expect(find.byIcon(Icons.open_in_browser), findsOneWidget);

      // Verify LazyTextField is rendered with sNotConfigured hint and empty value
      final lazyTextFieldFinder = find.descendant(
        of: settingRowFinder,
        matching: find.byType(LazyTextField),
      );
      expect(lazyTextFieldFinder, findsOneWidget);
      final lazyTextField = tester.widget<LazyTextField>(lazyTextFieldFinder);
      expect(lazyTextField.value, equals(''));
      expect(lazyTextField.hint, equals(localeController.localeStrings.sNotConfigured));
      expect(lazyTextField.readOnly, isTrue);
    });

    testWidgets('Toggling Switch back OFF hides action button and text field and sets disableCookiesFromWebview: true', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      final settingRowFinder = find.ancestor(
        of: find.text(localeController.localeStrings.sCookiesFromWebview),
        matching: find.byType(SettingRow),
      );
      final switchFinder = find.descendant(
        of: settingRowFinder,
        matching: find.byType(Switch),
      );

      // Toggle ON
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isFalse);
      expect(find.text(localeController.localeStrings.sOpenWebview), findsOneWidget);

      // Toggle OFF
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isTrue);

      // Verify child widgets are hidden
      expect(find.text(localeController.localeStrings.sOpenWebview), findsNothing);
      expect(find.byIcon(Icons.open_in_browser), findsNothing);
      expect(
        find.descendant(
          of: settingRowFinder,
          matching: find.byType(LazyTextField),
        ),
        findsNothing,
      );
    });

    testWidgets('When cookiesFromWebview has a path value, LazyTextField displays that path', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      const sampleCookiePath = '/data/user/0/com.vidra/app_flutter/cookies.txt';
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cookiesFromWebview: sampleCookiePath,
          disableCookiesFromWebview: false,
        ),
      );

      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      final settingRowFinder = find.ancestor(
        of: find.text(localeController.localeStrings.sCookiesFromWebview),
        matching: find.byType(SettingRow),
      );

      final lazyTextFieldFinder = find.descendant(
        of: settingRowFinder,
        matching: find.byType(LazyTextField),
      );
      expect(lazyTextFieldFinder, findsOneWidget);
      final lazyTextField = tester.widget<LazyTextField>(lazyTextFieldFinder);
      expect(lazyTextField.value, equals(sampleCookiePath));
      expect(find.text(sampleCookiePath), findsOneWidget);
    });

    testWidgets('Zero hardcoded strings: Verify complete localization under Spanish (es)', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      localeController = LocaleController(mockLocaleRepo, 'es');
      await localeController.whenReady;

      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          disableCookiesFromWebview: false,
        ),
      );

      await tester.pumpWidget(createSettingsApp(locale: const Locale('es')));
      await tester.pumpAndSettle();

      // Navigate to Network tab (Red)
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      final esStrings = localeController.localeStrings;

      // Verify Spanish strings are non-empty and displayed
      expect(esStrings.sCookiesFromWebview.isNotEmpty, isTrue);
      expect(esStrings.sCookiesFromWebviewDesc.isNotEmpty, isTrue);
      expect(esStrings.sOpenWebview.isNotEmpty, isTrue);
      expect(esStrings.sNotConfigured.isNotEmpty, isTrue);

      expect(find.text(esStrings.sCookiesFromWebview), findsOneWidget);
      expect(find.text(esStrings.sCookiesFromWebviewDesc), findsOneWidget);
      expect(find.text(esStrings.sOpenWebview), findsOneWidget);

      // Verify no leftover uppercase hardcoded prototype string
      expect(find.text('COOKIES FROM WEBVIEW'), findsNothing);
    });

    testWidgets('Search query filters and displays Cookies from WebView setting', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Open Search in AppBar
      final searchButton = find.byIcon(Icons.search);
      expect(searchButton, findsOneWidget);
      await tester.tap(searchButton);
      await tester.pumpAndSettle();

      // Enter search term matching WebView cookies
      final searchTextField = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextField),
      );
      expect(searchTextField, findsOneWidget);
      await tester.enterText(searchTextField, localeController.localeStrings.sCookiesFromWebview);
      await tester.pumpAndSettle();

      // Verify search results display the setting and its category header
      expect(
        find.widgetWithText(SettingRow, localeController.localeStrings.sCookiesFromWebview),
        findsOneWidget,
      );
      expect(find.text(localeController.localeStrings.sNetwork), findsWidgets);
    });

    testWidgets('Tapping Open WebView button pushes InAppWebViewScreen and updates path when popped with result', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          disableCookiesFromWebview: false,
        ),
      );

      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      final openButtonFinder = find.text(localeController.localeStrings.sOpenWebview);
      expect(openButtonFinder, findsOneWidget);

      // Tap Open WebView button
      await tester.tap(openButtonFinder);
      await tester.pumpAndSettle();

      // Verify InAppWebViewScreen is shown
      expect(find.byType(InAppWebViewScreen), findsOneWidget);

      // Simulate capturing/returning a cookies file path by popping with result
      const exportedPath = '/app/storage/youtube_cookies.txt';
      final navContext = tester.element(find.byType(InAppWebViewScreen));
      Navigator.of(navContext).pop(exportedPath);
      await tester.pumpAndSettle();

      // Verify returned to SettingsScreen and controller updated
      expect(find.byType(InAppWebViewScreen), findsNothing);
      expect(settingsController.downloadOptions.cookiesFromWebview, equals(exportedPath));
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isFalse);
      expect(find.text(exportedPath), findsOneWidget);
    });

    testWidgets('Category navigation preserves WebView cookies state across tab transitions', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      const customPath = '/tmp/persistent_session_cookies.txt';
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cookiesFromWebview: customPath,
          disableCookiesFromWebview: false,
        ),
      );

      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Start on Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      expect(find.text(customPath), findsOneWidget);

      // Switch to General tab
      await tester.tap(find.byIcon(Icons.settings).last);
      await tester.pumpAndSettle();
      expect(find.text(customPath), findsNothing);

      // Switch to Video tab
      await tester.tap(find.byIcon(Icons.movie).first);
      await tester.pumpAndSettle();
      expect(find.text(customPath), findsNothing);

      // Switch back to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      // Verify state is completely preserved
      expect(find.text(customPath), findsOneWidget);
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isFalse);
      expect(settingsController.downloadOptions.cookiesFromWebview, equals(customPath));
    });

    testWidgets('Direct controller update reactively updates the UI', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Navigate to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.sOpenWebview), findsNothing);

      // Externally update controller options
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cookiesFromWebview: '/external/sync/cookies.txt',
          disableCookiesFromWebview: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(localeController.localeStrings.sOpenWebview), findsOneWidget);
      expect(find.text('/external/sync/cookies.txt'), findsOneWidget);
    });
  });
}
