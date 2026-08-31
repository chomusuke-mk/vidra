import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:vidra/features/locales/domain/locale.dart';

void main() {
  group('Empirical Challenger: Locale M1 Adversarial Suite', () {
    const m1Keys = [
      's_cookies_from_webview',
      's_cookies_from_webview_desc',
      's_open_webview',
    ];

    // ------------------------------------------------------------------------
    // 1. AppStringKey Getters & Uninitialized Fallback Robustness
    // ------------------------------------------------------------------------
    group('1. AppStringKey Getters & Default Fallback', () {
      test('Uninitialized AppStringKey getters return empty string without throwing', () {
        final locale = AppStringKey();
        expect(locale.sCookiesFromWebview, equals(''));
        expect(locale.sCookiesFromWebviewDesc, equals(''));
        expect(locale.sOpenWebview, equals(''));
      });

      test('English translation correctly sets expected strings', () async {
        final locale = AppStringKey();
        await locale.updateFromJson({
          's_cookies_from_webview': 'Cookies from WebView',
          's_cookies_from_webview_desc':
              'Enable this option to extract cookies from the WebView. This is useful for sites that require login or have region restrictions.',
          's_open_webview': 'Open WebView',
        });

        expect(locale.sCookiesFromWebview, equals('Cookies from WebView'));
        expect(
          locale.sCookiesFromWebviewDesc,
          contains('Enable this option to extract cookies from the WebView'),
        );
        expect(locale.sOpenWebview, equals('Open WebView'));
      });

      test('Spanish translation correctly sets expected strings', () async {
        final locale = AppStringKey();
        await locale.updateFromJson({
          's_cookies_from_webview': 'Cookies del WebView',
          's_cookies_from_webview_desc':
              'Habilite esta opción para extraer cookies del WebView. Esto es útil para sitios que requieren inicio de sesión o tienen restricciones regionales.',
          's_open_webview': 'Abrir WebView',
        });

        expect(locale.sCookiesFromWebview, equals('Cookies del WebView'));
        expect(
          locale.sCookiesFromWebviewDesc,
          contains('Habilite esta opción para extraer cookies del WebView'),
        );
        expect(locale.sOpenWebview, equals('Abrir WebView'));
      });
    });

    // ------------------------------------------------------------------------
    // 2. Strict Key Parity & assertAllKeysPresent Enforcement
    // ------------------------------------------------------------------------
    group('2. Missing Key Detection & assertAllKeysPresent Enforcement', () {
      test('updateFromJson with assertAllKeysPresent: true throws when any M1 key is missing', () async {
        // Load en.jsonc as baseline
        final enFile = File('i18n/en.jsonc');
        expect(enFile.existsSync(), isTrue);

        final rawJson = enFile.readAsStringSync();
        final Map<String, dynamic> parsed = (jsonc.decode(rawJson) as Map).cast<String, dynamic>();
        final Map<String, String> baseMap = parsed.map(
          (k, v) => MapEntry(k, v.toString()),
        );

        // Verify baseline passes
        final locale = AppStringKey();
        expect(
          () => locale.updateFromJson(baseMap, assertAllKeysPresent: true),
          returnsNormally,
        );

        // Test dropping each M1 key individually
        for (final keyToDrop in m1Keys) {
          final defectiveMap = Map<String, String>.from(baseMap)..remove(keyToDrop);
          final testLocale = AppStringKey();
          expect(
            () => testLocale.updateFromJson(defectiveMap, assertAllKeysPresent: true),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'exception message',
                contains(keyToDrop),
              ),
            ),
            reason: 'assertAllKeysPresent: true MUST throw when $keyToDrop is missing',
          );
        }
      });
    });

    // ------------------------------------------------------------------------
    // 3. Fallback Preservation Under Partial Locale Updates
    // ------------------------------------------------------------------------
    group('3. Fallback Behavior Under Incomplete Locales', () {
      test('Updating with partial translations preserves existing fallback values', () async {
        final locale = AppStringKey();

        // 1. Initialize with English defaults
        await locale.updateFromJson({
          's_cookies_from_webview': 'Cookies from WebView',
          's_cookies_from_webview_desc': 'English description',
          's_open_webview': 'Open WebView',
        });

        // 2. Update with incomplete locale (only s_cookies_from_webview provided)
        await locale.updateFromJson({
          's_cookies_from_webview': 'Cookies personnalisées',
        });

        // Provided key updated
        expect(locale.sCookiesFromWebview, equals('Cookies personnalisées'));
        // Non-provided keys retain prior values
        expect(locale.sCookiesFromWebviewDesc, equals('English description'));
        expect(locale.sOpenWebview, equals('Open WebView'));
      });
    });

    // ------------------------------------------------------------------------
    // 4. File-System Parity Across All i18n JSONC Files
    // ------------------------------------------------------------------------
    group('4. Global i18n Directory Parity', () {
      test('All non-empty i18n/*.jsonc files contain all M1 keys', () {
        final i18nDir = Directory('i18n');
        expect(i18nDir.existsSync(), isTrue);

        final jsoncFiles = i18nDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jsonc'))
            .toList();

        expect(jsoncFiles.isNotEmpty, isTrue);

        int checkedCount = 0;

        for (final file in jsoncFiles) {
          final content = file.readAsStringSync().trim();
          if (content == '{}' || content.isEmpty) {
            continue;
          }

          final Map<String, dynamic> data = (jsonc.decode(content) as Map).cast<String, dynamic>();
          for (final key in m1Keys) {
            expect(
              data.containsKey(key),
              isTrue,
              reason: 'File ${file.path} is missing key "$key"',
            );
            expect(
              data[key],
              isA<String>(),
              reason: 'File ${file.path} key "$key" must be a non-null String',
            );
          }
          checkedCount++;
        }

        expect(checkedCount, greaterThan(100), reason: 'Must verify all active locale files');
      });
    });

    // ------------------------------------------------------------------------
    // 5. Stress & Special Character Robustness
    // ------------------------------------------------------------------------
    group('5. Stress & Unicode Robustness', () {
      test('Handles complex unicode, RTL, special characters and large strings', () async {
        final locale = AppStringKey();
        final complexMap = {
          's_cookies_from_webview': 'ملفات تعريف الارتباط من WebView 🍪 🚀 <>&"\'',
          's_cookies_from_webview_desc': 'Здесь очень длинное описание с эмодзи 🎉' * 100,
          's_open_webview': '打开 WebView 🌐\n\t\r\\',
        };

        await locale.updateFromJson(complexMap);

        expect(locale.sCookiesFromWebview, equals(complexMap['s_cookies_from_webview']));
        expect(locale.sCookiesFromWebviewDesc, equals(complexMap['s_cookies_from_webview_desc']));
        expect(locale.sOpenWebview, equals(complexMap['s_open_webview']));

        // Verify toJson serialization preserves exact strings
        final exported = locale.toJson();
        expect(exported['s_cookies_from_webview'], equals(complexMap['s_cookies_from_webview']));
        expect(exported['s_open_webview'], equals(complexMap['s_open_webview']));
      });
    });
  });
}
