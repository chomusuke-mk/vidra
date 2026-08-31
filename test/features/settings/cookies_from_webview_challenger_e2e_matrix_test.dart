import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/cookie_exporter.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/domain/netscape_cookie_formatter.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/settings/presentation/settings_screen.dart';
import 'package:vidra/features/settings/presentation/widgets/in_app_webview_screen.dart';
import 'package:vidra/shared/widgets/lazy_text_field.dart';
import 'package:vidra/shared/widgets/settings_row.dart';

class MockLocaleRepo extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  MockLocaleRepo() {
    for (final code in ['en', 'es', 'pt', 'fr', 'de']) {
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

  group('CHALLENGER R1 — DownloadOptions Data Model & Serialization Matrix', () {
    test('Default constructor sets disableCookiesFromWebview to false and cookiesFromWebview to null', () {
      final opts = DownloadOptions();
      expect(opts.disableCookiesFromWebview, isFalse);
      expect(opts.cookiesFromWebview, isNull);
    });

    test('toJson produces "cookies_from_webview": false when disabled', () {
      final opts1 = DownloadOptions(disableCookiesFromWebview: true);
      expect(opts1.toJson()['cookies_from_webview'], equals(false));

      // Even if cookiesFromWebview has a path, if disable is true, it MUST serialize to false
      final opts2 = DownloadOptions(
        disableCookiesFromWebview: true,
        cookiesFromWebview: '/tmp/cookies.txt',
      );
      expect(opts2.toJson()['cookies_from_webview'], equals(false));
    });

    test('toJson produces "cookies_from_webview": "<path>" when enabled and path non-empty', () {
      final opts = DownloadOptions(
        disableCookiesFromWebview: false,
        cookiesFromWebview: '/home/user/vidra_cookies.txt',
      );
      expect(opts.toJson()['cookies_from_webview'], equals('/home/user/vidra_cookies.txt'));
    });

    test('toJson omits "cookies_from_webview" when enabled but path is null or empty', () {
      final optsNull = DownloadOptions(
        disableCookiesFromWebview: false,
        cookiesFromWebview: null,
      );
      expect(optsNull.toJson().containsKey('cookies_from_webview'), isFalse);

      final optsEmpty = DownloadOptions(
        disableCookiesFromWebview: false,
        cookiesFromWebview: '',
      );
      expect(optsEmpty.toJson().containsKey('cookies_from_webview'), isFalse);
    });

    test('fromJson sets disableCookiesFromWebview = true and cookiesFromWebview = null on false', () {
      final json = {'cookies_from_webview': false};
      final opts = DownloadOptions.fromJson(json);
      expect(opts.disableCookiesFromWebview, isTrue);
      expect(opts.cookiesFromWebview, isNull);
    });

    test('fromJson parses string path into cookiesFromWebview and sets disable to false', () {
      final json = {'cookies_from_webview': '/var/data/cookies.netscape'};
      final opts = DownloadOptions.fromJson(json);
      expect(opts.disableCookiesFromWebview, isFalse);
      expect(opts.cookiesFromWebview, equals('/var/data/cookies.netscape'));
    });

    test('fromJson handles unexpected types safely without throwing', () {
      expect(() => DownloadOptions.fromJson({'cookies_from_webview': 12345}), returnsNormally);
      expect(() => DownloadOptions.fromJson({'cookies_from_webview': true}), returnsNormally);
      expect(() => DownloadOptions.fromJson({'cookies_from_webview': ['a', 'b']}), returnsNormally);
      expect(() => DownloadOptions.fromJson({'cookies_from_webview': {'nested': true}}), returnsNormally);
    });

    test('copyWith properly updates or preserves cookiesFromWebview and disableCookiesFromWebview', () {
      final base = DownloadOptions(
        cookiesFromWebview: '/original/path.txt',
        disableCookiesFromWebview: false,
      );

      final updatedPath = base.copyWith(cookiesFromWebview: '/new/path.txt');
      expect(updatedPath.cookiesFromWebview, equals('/new/path.txt'));
      expect(updatedPath.disableCookiesFromWebview, isFalse);

      final updatedDisable = base.copyWith(disableCookiesFromWebview: true);
      expect(updatedDisable.cookiesFromWebview, equals('/original/path.txt'));
      expect(updatedDisable.disableCookiesFromWebview, isTrue);
    });

    test('Equality operator == and hashCode differentiate cookiesFromWebview and disableCookiesFromWebview', () {
      final optA = DownloadOptions(
        cookiesFromWebview: '/path/a.txt',
        disableCookiesFromWebview: false,
      );
      final optB = DownloadOptions(
        cookiesFromWebview: '/path/b.txt',
        disableCookiesFromWebview: false,
      );
      final optC = DownloadOptions(
        cookiesFromWebview: '/path/a.txt',
        disableCookiesFromWebview: true,
      );
      final optAClone = DownloadOptions(
        cookiesFromWebview: '/path/a.txt',
        disableCookiesFromWebview: false,
      );

      expect(optA == optAClone, isTrue);
      expect(optA.hashCode, equals(optAClone.hashCode));

      expect(optA == optB, isFalse);
      expect(optA == optC, isFalse);
    });

    test('JSON round-trip idempotence', () {
      final original = DownloadOptions(
        cookiesFromWebview: '/roundtrip/cookies.txt',
        disableCookiesFromWebview: false,
      );
      final json = original.toJson();
      final restored = DownloadOptions.fromJson(json);
      expect(restored.cookiesFromWebview, equals(original.cookiesFromWebview));
      expect(restored.disableCookiesFromWebview, equals(original.disableCookiesFromWebview));
    });
  });

  group('CHALLENGER R2 — Localization (i18n) & Keys Matrix', () {
    test('i18n/en.jsonc and i18n/es.jsonc contain all required webview cookie keys', () {
      for (final code in ['en', 'es']) {
        final file = File('i18n/$code.jsonc');
        expect(file.existsSync(), isTrue, reason: '$code.jsonc must exist');
        final content = file.readAsStringSync();
        final map = (jsonc.decode(content) as Map).cast<String, dynamic>();

        expect(map.containsKey('s_cookies_from_webview'), isTrue, reason: '$code missing s_cookies_from_webview');
        expect(map['s_cookies_from_webview'].toString().trim().isNotEmpty, isTrue);

        expect(map.containsKey('s_cookies_from_webview_desc'), isTrue, reason: '$code missing s_cookies_from_webview_desc');
        expect(map['s_cookies_from_webview_desc'].toString().trim().isNotEmpty, isTrue);

        expect(map.containsKey('s_open_webview'), isTrue, reason: '$code missing s_open_webview');
        expect(map['s_open_webview'].toString().trim().isNotEmpty, isTrue);
      }
    });

    test('AppStringKey getters sCookiesFromWebview, sCookiesFromWebviewDesc, sOpenWebview work properly', () async {
      final rawMap = (jsonc.decode(File('i18n/en.jsonc').readAsStringSync()) as Map).cast<String, dynamic>();
      final enMap = rawMap.map((k, v) => MapEntry(k, v.toString()));
      final keys = AppStringKey();
      await keys.updateFromJson(enMap);

      expect(keys.sCookiesFromWebview, equals(enMap['s_cookies_from_webview']));
      expect(keys.sCookiesFromWebviewDesc, equals(enMap['s_cookies_from_webview_desc']));
      expect(keys.sOpenWebview, equals(enMap['s_open_webview']));
    });

    test('No hardcoded "COOKIES FROM WEBVIEW" remains in settings_screen.dart', () {
      final screenFile = File('lib/features/settings/presentation/settings_screen.dart');
      final content = screenFile.readAsStringSync();
      expect(content.contains('COOKIES FROM WEBVIEW'), isFalse);
    });
  });

  group('CHALLENGER R3 — WebView Normalization & Netscape Formatter & Exporter Matrix', () {
    test('InAppWebViewScreen.normalizeUrl handles diverse inputs correctly', () {
      expect(InAppWebViewScreen.normalizeUrl(''), equals('https://search.brave.com/search?q='));
      expect(InAppWebViewScreen.normalizeUrl('   '), equals('https://search.brave.com/search?q='));
      expect(InAppWebViewScreen.normalizeUrl('youtube.com'), equals('https://youtube.com'));
      expect(InAppWebViewScreen.normalizeUrl('http://example.com/login'), equals('http://example.com/login'));
      expect(InAppWebViewScreen.normalizeUrl('https://sub.domain.org:8080/path?k=v#frag'), equals('https://sub.domain.org:8080/path?k=v#frag'));
      expect(InAppWebViewScreen.normalizeUrl('custom-scheme://app.local'), equals('custom-scheme://app.local'));
    });

    test('NetscapeCookieFormatter produces exact valid 7-column lines and header', () {
      final cookies = [
        Cookie(
          name: 'SID',
          value: 'abc123xyz',
          domain: 'youtube.com',
          path: '/',
          isSecure: true,
          expiresDate: 1893456000, // Year 2030 (seconds)
        ),
        Cookie(
          name: 'SESSION_ID',
          value: 'temp_sess_999',
          domain: '.google.com',
          path: '/auth',
          isSecure: false,
          expiresDate: null, // Session cookie -> 0
        ),
        Cookie(
          name: 'MS_EXPIRY',
          value: 'val_ms',
          domain: '127.0.0.1',
          path: '/',
          isSecure: false,
          expiresDate: 1893456000000, // Milliseconds timestamp (> 100B) -> convert to 1893456000
        ),
      ];

      final formatted = NetscapeCookieFormatter.format(cookies);

      // Verify header lines
      expect(formatted.startsWith('# Netscape HTTP Cookie File\n# https://curl.haxx.se/rfc/cookie_spec.html\n# This file was generated by Vidra! Edit at your own risk.\n\n'), isTrue);

      final lines = formatted.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
      expect(lines.length, equals(3));

      // Line 1: .youtube.com	TRUE	/	TRUE	1893456000	SID	abc123xyz
      final cols1 = lines[0].split('\t');
      expect(cols1.length, equals(7));
      expect(cols1[0], equals('.youtube.com'));
      expect(cols1[1], equals('TRUE'));
      expect(cols1[2], equals('/'));
      expect(cols1[3], equals('TRUE'));
      expect(cols1[4], equals('1893456000'));
      expect(cols1[5], equals('SID'));
      expect(cols1[6], equals('abc123xyz'));

      // Line 2: .google.com	TRUE	/auth	FALSE	0	SESSION_ID	temp_sess_999
      final cols2 = lines[1].split('\t');
      expect(cols2.length, equals(7));
      expect(cols2[0], equals('.google.com'));
      expect(cols2[1], equals('TRUE'));
      expect(cols2[2], equals('/auth'));
      expect(cols2[3], equals('FALSE'));
      expect(cols2[4], equals('0'));
      expect(cols2[5], equals('SESSION_ID'));
      expect(cols2[6], equals('temp_sess_999'));

      // Line 3: 127.0.0.1	FALSE	/	FALSE	1893456000	MS_EXPIRY	val_ms
      final cols3 = lines[2].split('\t');
      expect(cols3.length, equals(7));
      expect(cols3[0], equals('127.0.0.1'));
      expect(cols3[1], equals('FALSE')); // IP address does not match subdomains
      expect(cols3[2], equals('/'));
      expect(cols3[3], equals('FALSE'));
      expect(cols3[4], equals('1893456000'));
      expect(cols3[5], equals('MS_EXPIRY'));
      expect(cols3[6], equals('val_ms'));
    });

    test('NetscapeCookieFormatter sanitizes tab, newline, and carriage return in name and value', () {
      final maliciousCookies = [
        Cookie(
          name: 'EVIL\tNAME\nINJECT',
          value: 'VAL\r\nINJECT\tSECOND_COL',
          domain: 'example.com',
          path: '/path',
          isSecure: true,
          expiresDate: 0,
        ),
      ];

      final output = NetscapeCookieFormatter.format(maliciousCookies);
      final lines = output.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).toList();

      expect(lines.length, equals(1), reason: 'Newline injection must not create extra cookie lines');
      final cols = lines[0].split('\t');
      expect(cols.length, equals(7), reason: 'Tab injection must not create extra columns');
      expect(cols[5], equals('EVILNAMEINJECT'));
      expect(cols[6], equals('VALINJECTSECOND_COL'));
    });

    test('CookieExporter saves to disk and creates parent directory if necessary', () async {
      final tempDir = Directory.systemTemp.createTempSync('vidra_challenger_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final targetFile = File(p.join(tempDir.path, 'nested', 'subdir', 'cookies.txt'));
      final cookies = [
        Cookie(name: 'TEST_COOKIE', value: '12345', domain: 'example.com'),
      ];

      final savedPath = await CookieExporter.saveCookiesToFile(
        cookies,
        savePath: targetFile.path,
      );

      expect(savedPath, equals(targetFile.absolute.path));
      expect(targetFile.existsSync(), isTrue);

      final contents = targetFile.readAsStringSync();
      expect(contents.contains('TEST_COOKIE\t12345'), isTrue);
      expect(contents.contains('# Netscape HTTP Cookie File'), isTrue);
    });
  });

  group('CHALLENGER R4 — Settings UI & Controller Integration Matrix', () {
    late SharedPreferences prefs;
    late SettingsRepository settingsRepo;
    late SettingsController settingsController;
    late MockLocaleRepo mockLocaleRepo;
    late LocaleController localeController;
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('vidra_challenger_ui_test_');
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

      mockLocaleRepo = MockLocaleRepo();
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
          Provider<SharedPreferences>.value(value: prefs),
          ChangeNotifierProvider<SettingsController>.value(value: settingsController),
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      );
    }

    void setupViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    testWidgets('Cookies From WebView setting is in Network category immediately preceding Cookies', (
      WidgetTester tester,
    ) async {
      setupViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Go to Network category
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      final webviewSettingFinder = find.text(localeController.localeStrings.sCookiesFromWebview);
      final cookiesSettingFinder = find.text(localeController.localeStrings.sCookies);

      expect(webviewSettingFinder, findsOneWidget);
      expect(cookiesSettingFinder, findsOneWidget);

      final webviewDy = tester.getTopLeft(webviewSettingFinder).dy;
      final cookiesDy = tester.getTopLeft(cookiesSettingFinder).dy;

      expect(webviewDy, lessThan(cookiesDy));
    });

    testWidgets('Full toggle cycle ON -> Action buttons appear -> toggle OFF -> buttons hidden', (
      WidgetTester tester,
    ) async {
      setupViewport(tester);
      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Go to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      final rowFinder = find.ancestor(
        of: find.text(localeController.localeStrings.sCookiesFromWebview),
        matching: find.byType(SettingRow),
      );
      final switchFinder = find.descendant(of: rowFinder, matching: find.byType(Switch));

      // Initially ON by default (disableCookiesFromWebview == false)
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isFalse);
      expect(find.text(localeController.localeStrings.sOpenWebview), findsOneWidget);
      expect(find.text(localeController.localeStrings.sViewCurrentCookies), findsOneWidget);

      // 1. Toggle OFF
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isTrue);
      expect(settingsController.downloadOptions.toJson()['cookies_from_webview'], equals(false));

      // Verify buttons are hidden
      expect(find.text(localeController.localeStrings.sOpenWebview), findsNothing);
      expect(find.text(localeController.localeStrings.sViewCurrentCookies), findsNothing);

      // 2. Toggle ON
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(settingsController.downloadOptions.disableCookiesFromWebview, isFalse);

      // Verify Open Webview and View current cookies buttons appear
      expect(find.text(localeController.localeStrings.sOpenWebview), findsOneWidget);
      expect(find.text(localeController.localeStrings.sViewCurrentCookies), findsOneWidget);
    });

    testWidgets('Tapping View current cookies button opens modal bottom sheet with cookie viewer', (
      WidgetTester tester,
    ) async {
      setupViewport(tester);
      final vidraCookiesDir = Directory(p.join(tempDir.path, 'vidra_cookies'));
      if (!vidraCookiesDir.existsSync()) {
        vidraCookiesDir.createSync(recursive: true);
      }
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          cookiesFromWebview: vidraCookiesDir.path,
          disableCookiesFromWebview: false,
        ),
      );

      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Go to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      final viewCookiesBtn = find.text(localeController.localeStrings.sViewCurrentCookies);
      expect(viewCookiesBtn, findsOneWidget);

      // Tap View current cookies button
      await tester.tap(viewCookiesBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Verify modal sheet is displayed
      expect(find.text(localeController.localeStrings.sCookiesListTitle), findsOneWidget);
    });

    testWidgets('LazyTextField is not rendered when cookies_from_webview is enabled (replaced by button)', (
      WidgetTester tester,
    ) async {
      setupViewport(tester);
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          disableCookiesFromWebview: false,
        ),
      );

      await tester.pumpWidget(createSettingsApp());
      await tester.pumpAndSettle();

      // Go to Network tab
      await tester.tap(find.byIcon(Icons.wifi).first);
      await tester.pumpAndSettle();

      final lazyFieldFinder = find.descendant(
        of: find.ancestor(
          of: find.text(localeController.localeStrings.sCookiesFromWebview),
          matching: find.byType(SettingRow),
        ),
        matching: find.byType(LazyTextField),
      );

      expect(lazyFieldFinder, findsNothing);
    });
  });
}
