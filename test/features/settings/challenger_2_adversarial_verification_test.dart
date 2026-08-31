import 'dart:io';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidra/features/settings/data/cookie_exporter.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/widgets/in_app_webview_screen.dart';

void main() {
  group('Challenger 2 Empirical Verification: InAppWebViewScreen.normalizeUrl', () {
    const bravePrefix = 'https://search.brave.com/search?q=';

    test('Empty, whitespace-only, and blank strings always resolve to Brave search base URL', () {
      final blankInputs = [
        '',
        ' ',
        '   ',
        '\t',
        '\r\n',
        ' \t \r\n \n \t ',
      ];

      for (final input in blankInputs) {
        final normalized = InAppWebViewScreen.normalizeUrl(input);
        expect(
          normalized,
          equals(bravePrefix),
          reason: 'Input "$input" must fallback to Brave search engine',
        );
        expect(normalized, isNot(contains('google')));
      }
    });

    test('Single-word and multi-word search queries are routed to Brave search with proper URL encoding', () {
      final queries = <String, String>{
        'flutter': '${bravePrefix}flutter',
        'dart programming': '${bravePrefix}dart%20programming',
        'how to download video 4k': '${bravePrefix}how%20to%20download%20video%204k',
        'vidra yt-dlp clean architecture': '${bravePrefix}vidra%20yt-dlp%20clean%20architecture',
        'c++ & rust vs dart': '${bravePrefix}c%2B%2B%20%26%20rust%20vs%20dart',
        'what is 2 + 2 = 4?': '${bravePrefix}what%20is%202%20%2B%202%20%3D%204%3F',
        'search with emojis 🚀 🍪 ✨': '${bravePrefix}search%20with%20emojis%20%F0%9F%9A%80%20%F0%9F%8D%AA%20%E2%9C%A8',
        'quotes "exact match" test': '${bravePrefix}quotes%20%22exact%20match%22%20test',
        'special chars #hash %percent &amp': '${bravePrefix}special%20chars%20%23hash%20%25percent%20%26amp',
      };

      queries.forEach((input, expectedOutput) {
        final normalized = InAppWebViewScreen.normalizeUrl(input);
        expect(normalized, equals(expectedOutput));
        expect(normalized, startsWith(bravePrefix));
        expect(normalized, isNot(contains('google.com')));
        expect(normalized, isNot(contains('google')));
      });
    });

    test('URLs with explicit schemes are preserved unchanged', () {
      final schemeUrls = [
        'http://insecure-site.com',
        'https://secure-site.org/path?key=val#section',
        'https://search.brave.com/search?q=test',
        'ftp://files.example.com/pub/file.tar.gz',
        'ws://realtime.example.com/socket',
        'wss://secure.websocket.org/feed',
        'custom-app://oauth2/callback?token=abc',
      ];

      for (final url in schemeUrls) {
        final normalized = InAppWebViewScreen.normalizeUrl(url);
        expect(normalized, equals(url));
      }
    });

    test('URLs without scheme (domains, IPs, ports) are automatically prefixed with https://', () {
      final domainInputs = <String, String>{
        'vidra.io': 'https://vidra.io',
        'sub.domain.co.uk': 'https://sub.domain.co.uk',
        'sub.domain.co.uk/path/to/resource?param=1&other=2#frag':
            'https://sub.domain.co.uk/path/to/resource?param=1&other=2#frag',
        'localhost': 'https://localhost',
        'localhost:3000': 'https://localhost:3000',
        'localhost:8080/api/v1/health': 'https://localhost:8080/api/v1/health',
        '127.0.0.1': 'https://127.0.0.1',
        '127.0.0.1:8000': 'https://127.0.0.1:8000',
        '192.168.1.1': 'https://192.168.1.1',
        '10.0.0.1:9090/admin': 'https://10.0.0.1:9090/admin',
        '[::1]:8080': 'https://[::1]:8080',
        'example.org:443': 'https://example.org:443',
      };

      domainInputs.forEach((input, expectedOutput) {
        final normalized = InAppWebViewScreen.normalizeUrl(input);
        expect(normalized, equals(expectedOutput));
        expect(normalized, startsWith('https://'));
      });
    });

    test('Strict Google non-existence oracle: InAppWebViewScreen never references Google URLs', () {
      final sampleInputs = [
        '',
        ' ',
        'test query',
        'flutter webview',
        'example.com',
        'http://example.com',
        '127.0.0.1:8080',
      ];

      for (final input in sampleInputs) {
        final normalized = InAppWebViewScreen.normalizeUrl(input);
        expect(
          normalized.toLowerCase(),
          isNot(contains('google.com/search')),
          reason: 'Google search should never be used',
        );
        expect(
          normalized.toLowerCase(),
          isNot(contains('www.google.')),
        );
      }
    });
  });

  group('Challenger 2 Empirical Verification: CookieExporter Error Conditions & Edge Cases', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vidra_c2_exporter_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveCookiesToFile strictly throws ArgumentError on empty or whitespace savePath', () async {
      final invalidPaths = ['', ' ', '   ', '\t', '\r\n', '  \t \n '];

      for (final emptyPath in invalidPaths) {
        expect(
          () => CookieExporter.saveCookiesToFile([], savePath: emptyPath),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('targetPath must be a non-empty string'),
            ),
          ),
          reason: 'Path "$emptyPath" must throw ArgumentError',
        );
      }
    });

    test('saveCookiesToFile creates nested directories and persists Netscape formatted cookies', () async {
      final deepPath = p.join(tempDir.path, 'a', 'b', 'c', 'exported_cookies.txt');
      final cookies = [
        Cookie(
          name: 'SESSION_AUTH',
          value: 'secret_val_123',
          domain: 'vidra.app',
          path: '/api',
          isSecure: true,
          expiresDate: 1800000000,
        ),
      ];

      final outPath = await CookieExporter.saveCookiesToFile(cookies, savePath: deepPath);
      expect(outPath, equals(File(deepPath).absolute.path));

      final file = File(deepPath);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      expect(content, startsWith('# Netscape HTTP Cookie File\n# https://curl.haxx.se/rfc/cookie_spec.html\n'));
      expect(content, contains('.vidra.app\tTRUE\t/api\tTRUE\t1800000000\tSESSION_AUTH\tsecret_val_123'));
    });

    test('saveDomainCookies creates domain-specific file and handles special characters in domain', () async {
      final cookies = [
        Cookie(name: 'SID', value: '123', domain: 'sub.domain.org'),
      ];

      final outPath = await CookieExporter.saveDomainCookies(
        cookies,
        domain: 'https://sub.domain.org:8443/feed',
        directory: tempDir,
      );

      expect(p.basename(outPath), equals('sub.domain.org_cookies.txt'));
      final file = File(outPath);
      expect(await file.exists(), isTrue);
    });

    test('sanitizeDomainFileName matrix: empty, whitespace, special chars, and ports', () {
      expect(CookieExporter.sanitizeDomainFileName(''), equals('default_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('   '), equals('default_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('...'), equals('default_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('___'), equals('default_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('.._.._..'), equals('default_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('.youtube.com'), equals('youtube.com_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('https://youtube.com/watch?v=1'), equals('youtube.com_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('http://192.168.1.1:8080/page'), equals('192.168.1.1_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('domain:9000'), equals('domain_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('trailing.dots....'), equals('trailing.dots_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('bad<chars>in"name|test'), equals('bad_chars_in_name_test_cookies.txt'));
    });

    test('getSavedCookieFiles safely returns empty list for non-existent directory without error', () {
      final nonExistent = Directory(p.join(tempDir.path, 'does_not_exist_xyz'));
      final files = CookieExporter.getSavedCookieFiles(directory: nonExistent);
      expect(files, isEmpty);
    });

    test('getSavedCookieFiles returns only .txt files sorted by lastModified descending', () async {
      final file1 = File(p.join(tempDir.path, '1_cookies.txt'));
      final file2 = File(p.join(tempDir.path, '2_cookies.txt'));
      final file3 = File(p.join(tempDir.path, '3_cookies.txt'));
      final ignore = File(p.join(tempDir.path, 'ignored.json'));

      await file1.writeAsString('1');
      await Future.delayed(const Duration(milliseconds: 30));
      await file2.writeAsString('2');
      await Future.delayed(const Duration(milliseconds: 30));
      await file3.writeAsString('3');
      await ignore.writeAsString('{}');

      final files = CookieExporter.getSavedCookieFiles(directory: tempDir);
      expect(files.length, equals(3));
      expect(files[0].path, equals(file3.path));
      expect(files[1].path, equals(file2.path));
      expect(files[2].path, equals(file1.path));
    });
  });

  group('Challenger 2 Empirical Verification: DownloadOptions Architectural Contract', () {
    test('DownloadOptions constructor defaults disableCookiesFromWebview to false', () {
      final opts = DownloadOptions();
      expect(opts.disableCookiesFromWebview, isFalse);
      expect(opts.cookiesFromWebview, isNull);
    });

    test('DownloadOptions.fromJson() defaults disableCookiesFromWebview to false when key is absent or null', () {
      final fromEmpty = DownloadOptions.fromJson({});
      expect(fromEmpty.disableCookiesFromWebview, isFalse);
      expect(fromEmpty.cookiesFromWebview, isNull);

      final fromNull = DownloadOptions.fromJson({'cookies_from_webview': null});
      expect(fromNull.disableCookiesFromWebview, isFalse);
      expect(fromNull.cookiesFromWebview, isNull);
    });

    test('DownloadOptions.fromJson() deserializes explicit false as disableCookiesFromWebview: true', () {
      final fromFalse = DownloadOptions.fromJson({'cookies_from_webview': false});
      expect(fromFalse.disableCookiesFromWebview, isTrue);
      expect(fromFalse.cookiesFromWebview, isNull);
    });

    test('DownloadOptions.fromJson() deserializes explicit true or path as disableCookiesFromWebview: false', () {
      final fromTrue = DownloadOptions.fromJson({'cookies_from_webview': true});
      expect(fromTrue.disableCookiesFromWebview, isFalse);
      expect(fromTrue.cookiesFromWebview, isNull);

      final fromPath = DownloadOptions.fromJson({'cookies_from_webview': '/custom/cookies.txt'});
      expect(fromPath.disableCookiesFromWebview, isFalse);
      expect(fromPath.cookiesFromWebview, equals('/custom/cookies.txt'));
    });

    test('DownloadOptions.toJson() serializes cookies_from_webview: false only when disabled', () {
      final defaultOpts = DownloadOptions();
      expect(defaultOpts.toJson().containsKey('cookies_from_webview'), isFalse);

      final disabledOpts = defaultOpts.copyWith(disableCookiesFromWebview: true);
      expect(disabledOpts.toJson()['cookies_from_webview'], isFalse);

      final pathOpts = defaultOpts.copyWith(cookiesFromWebview: '/custom/path');
      expect(pathOpts.toJson()['cookies_from_webview'], equals('/custom/path'));
    });
  });

  group('Challenger 2 Empirical Verification: Architectural Hygiene (No path_provider in CookieExporter)', () {
    test('CookieExporter file does not contain path_provider import or usage', () {
      final file = File('lib/features/settings/data/cookie_exporter.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content, isNot(contains('path_provider')));
      expect(content, isNot(contains('getApplicationSupportDirectory')));
      expect(content, isNot(contains('getApplicationDocumentsDirectory')));
    });

    test('InAppWebViewScreen file does not contain path_provider import or usage', () {
      final file = File('lib/features/settings/presentation/widgets/in_app_webview_screen.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content, isNot(contains('path_provider')));
      expect(content, isNot(contains('getApplicationSupportDirectory')));
      expect(content, isNot(contains('getApplicationDocumentsDirectory')));
    });
  });
}
