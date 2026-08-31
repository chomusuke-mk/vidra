import 'dart:io';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/settings/data/cookie_exporter.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/domain/netscape_cookie_formatter.dart';
import 'package:vidra/features/settings/presentation/widgets/in_app_webview_screen.dart';

void main() {
  group('Adversarial Empirical Stress — DownloadOptions', () {
    test('Default constructor guarantees disableCookiesFromWebview == false', () {
      final opts = DownloadOptions();
      expect(opts.disableCookiesFromWebview, isFalse);
      expect(opts.cookiesFromWebview, isNull);
    });

    test('toJson serialization semantics for disableCookiesFromWebview', () {
      // 1. Default instance: omitted from map
      final defaultOpts = DownloadOptions();
      final defaultJson = defaultOpts.toJson();
      expect(defaultJson.containsKey('cookies_from_webview'), isFalse);

      // 2. Explicitly disabled: 'cookies_from_webview': false
      final disabledOpts = defaultOpts.copyWith(disableCookiesFromWebview: true);
      final disabledJson = disabledOpts.toJson();
      expect(disabledJson['cookies_from_webview'], isFalse);

      // 3. Explicit path provided: 'cookies_from_webview': '/path/to/cookies'
      final pathOpts = defaultOpts.copyWith(
        disableCookiesFromWebview: false,
        cookiesFromWebview: '/custom/storage/cookies',
      );
      final pathJson = pathOpts.toJson();
      expect(pathJson['cookies_from_webview'], equals('/custom/storage/cookies'));

      // 4. Empty path string: omitted from map
      final emptyPathOpts = defaultOpts.copyWith(
        disableCookiesFromWebview: false,
        cookiesFromWebview: '',
      );
      final emptyPathJson = emptyPathOpts.toJson();
      expect(emptyPathJson.containsKey('cookies_from_webview'), isFalse);
    });

    test('fromJson deserialization matrix for cookies_from_webview', () {
      // Empty JSON -> defaults to false (enabled)
      expect(DownloadOptions.fromJson({}).disableCookiesFromWebview, isFalse);
      expect(DownloadOptions.fromJson({}).cookiesFromWebview, isNull);

      // null value -> defaults to false (enabled)
      expect(
        DownloadOptions.fromJson({'cookies_from_webview': null}).disableCookiesFromWebview,
        isFalse,
      );

      // boolean false -> disableCookiesFromWebview is true
      final fromFalse = DownloadOptions.fromJson({'cookies_from_webview': false});
      expect(fromFalse.disableCookiesFromWebview, isTrue);
      expect(fromFalse.cookiesFromWebview, isNull);

      // boolean true -> disableCookiesFromWebview is false
      final fromTrue = DownloadOptions.fromJson({'cookies_from_webview': true});
      expect(fromTrue.disableCookiesFromWebview, isFalse);
      expect(fromTrue.cookiesFromWebview, isNull);

      // string path -> disableCookiesFromWebview is false, path is extracted
      final fromPath = DownloadOptions.fromJson({
        'cookies_from_webview': '/var/app/cookies',
      });
      expect(fromPath.disableCookiesFromWebview, isFalse);
      expect(fromPath.cookiesFromWebview, equals('/var/app/cookies'));

      // numeric or other unexpected types -> disableCookiesFromWebview is false, path is null
      final fromNumber = DownloadOptions.fromJson({'cookies_from_webview': 12345});
      expect(fromNumber.disableCookiesFromWebview, isFalse);
      expect(fromNumber.cookiesFromWebview, isNull);
    });

    test('copyWith preserves or mutates disableCookiesFromWebview correctly', () {
      final initial = DownloadOptions();
      expect(initial.disableCookiesFromWebview, isFalse);

      final modified = initial.copyWith(disableCookiesFromWebview: true);
      expect(modified.disableCookiesFromWebview, isTrue);

      final reverted = modified.copyWith(disableCookiesFromWebview: false);
      expect(reverted.disableCookiesFromWebview, isFalse);

      final unchanged = reverted.copyWith(ffmpegLocation: '/bin/ffmpeg');
      expect(unchanged.disableCookiesFromWebview, isFalse);
      expect(unchanged.ffmpegLocation, equals('/bin/ffmpeg'));
    });

    test('Equality and hashCode contracts for webview cookie fields', () {
      final opt1 = DownloadOptions(
        disableCookiesFromWebview: false,
        cookiesFromWebview: '/test/dir',
      );
      final opt2 = DownloadOptions(
        disableCookiesFromWebview: false,
        cookiesFromWebview: '/test/dir',
      );
      final opt3 = DownloadOptions(
        disableCookiesFromWebview: true,
        cookiesFromWebview: '/test/dir',
      );
      final opt4 = DownloadOptions(
        disableCookiesFromWebview: false,
        cookiesFromWebview: '/other/dir',
      );

      expect(opt1, equals(opt2));
      expect(opt1.hashCode, equals(opt2.hashCode));

      expect(opt1, isNot(equals(opt3)));
      expect(opt1, isNot(equals(opt4)));
    });
  });

  group('Adversarial Empirical Stress — NetscapeCookieFormatter', () {
    test('Empty list returns standard 4-line Netscape header', () {
      final result = NetscapeCookieFormatter.format([]);
      final lines = result.split('\n');

      expect(lines[0], equals('# Netscape HTTP Cookie File'));
      expect(lines[1], equals('# https://curl.haxx.se/rfc/cookie_spec.html'));
      expect(lines[2], equals('# This file was generated by Vidra! Edit at your own risk.'));
      expect(lines[3], isEmpty);
    });

    test('Domainless cookies (null, empty, whitespace) are strictly skipped', () {
      final cookies = [
        Cookie(name: 'c_null_domain', value: '1', domain: null),
        Cookie(name: 'c_empty_domain', value: '2', domain: ''),
        Cookie(name: 'c_whitespace_domain', value: '3', domain: '   \t  '),
        Cookie(name: 'c_valid', value: '4', domain: 'vidra.app'),
      ];

      final result = NetscapeCookieFormatter.format(cookies);
      expect(result, isNot(contains('c_null_domain')));
      expect(result, isNot(contains('c_empty_domain')));
      expect(result, isNot(contains('c_whitespace_domain')));
      expect(result, contains('c_valid'));
      expect(result, contains('.vidra.app\tTRUE\t/\tFALSE\t0\tc_valid\t4'));
    });

    test('Nameless cookies (null, empty, whitespace) are strictly skipped', () {
      final cookies = [
        Cookie(name: '', value: 'val', domain: 'vidra.app'),
        Cookie(name: '   \n\t  ', value: 'val', domain: 'vidra.app'),
        Cookie(name: 'valid_name', value: 'val', domain: 'vidra.app'),
      ];

      final result = NetscapeCookieFormatter.format(cookies);
      expect(result, contains('valid_name'));
      expect(result.split('\n').where((l) => l.trim().isNotEmpty && !l.startsWith('#')).length, equals(1));
    });

    test('Carriage returns, newlines, and tabs inside names and values are sanitized to prevent injection', () {
      final cookies = [
        Cookie(
          name: 'session\ttoken\r\ninjection',
          value: 'secret\tvalue\r\nnext_line\tmalicious',
          domain: 'security.org',
          path: '/auth',
          isSecure: true,
          expiresDate: 1893456000,
        ),
      ];

      final result = NetscapeCookieFormatter.format(cookies);
      final dataLines = result.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).toList();

      expect(dataLines.length, equals(1));
      final columns = dataLines.first.split('\t');
      expect(columns.length, equals(7), reason: 'Must have exactly 7 tab-separated columns without extra lines or injected tabs');
      expect(columns[0], equals('.security.org'));
      expect(columns[1], equals('TRUE'));
      expect(columns[2], equals('/auth'));
      expect(columns[3], equals('TRUE'));
      expect(columns[4], equals('1893456000'));
      expect(columns[5], equals('sessiontokeninjection'));
      expect(columns[6], equals('secretvaluenext_linemalicious'));
    });

    test('Domain parsing stress: IP addresses, leading dots, URLs, ports, localhost', () {
      final cookies = [
        Cookie(name: 'c_ip', value: '1', domain: '127.0.0.1'),
        Cookie(name: 'c_dot', value: '2', domain: '.example.com'),
        Cookie(name: 'c_nodot', value: '3', domain: 'example.com'),
        Cookie(name: 'c_url', value: '4', domain: 'https://sub.domain.org:8443/test'),
        Cookie(name: 'c_localhost', value: '5', domain: 'localhost'),
      ];

      final result = NetscapeCookieFormatter.format(cookies);

      expect(result, contains('127.0.0.1\tFALSE\t/\tFALSE\t0\tc_ip\t1'));
      expect(result, contains('.example.com\tTRUE\t/\tFALSE\t0\tc_dot\t2'));
      expect(result, contains('.example.com\tTRUE\t/\tFALSE\t0\tc_nodot\t3'));
      expect(result, contains('.sub.domain.org\tTRUE\t/\tFALSE\t0\tc_url\t4'));
      expect(result, contains('localhost\tFALSE\t/\tFALSE\t0\tc_localhost\t5'));
    });

    test('Path resolution stress: null, empty, relative path, root path', () {
      final cookies = [
        Cookie(name: 'c_null_path', value: '1', domain: 'a.com', path: null),
        Cookie(name: 'c_empty_path', value: '2', domain: 'a.com', path: ''),
        Cookie(name: 'c_relative', value: '3', domain: 'a.com', path: 'api/v2'),
        Cookie(name: 'c_absolute', value: '4', domain: 'a.com', path: '/api/v2'),
      ];

      final result = NetscapeCookieFormatter.format(cookies);

      expect(result, contains('.a.com\tTRUE\t/\tFALSE\t0\tc_null_path\t1'));
      expect(result, contains('.a.com\tTRUE\t/\tFALSE\t0\tc_empty_path\t2'));
      expect(result, contains('.a.com\tTRUE\t/api/v2\tFALSE\t0\tc_relative\t3'));
      expect(result, contains('.a.com\tTRUE\t/api/v2\tFALSE\t0\tc_absolute\t4'));
    });

    test('Timestamp expiration conversion: null, zero, negative, ms (> 100B), and seconds', () {
      final cookies = [
        Cookie(name: 'c_null_exp', value: '1', domain: 'a.com', expiresDate: null),
        Cookie(name: 'c_zero_exp', value: '2', domain: 'a.com', expiresDate: 0),
        Cookie(name: 'c_neg_exp', value: '3', domain: 'a.com', expiresDate: -500),
        Cookie(name: 'c_sec_exp', value: '4', domain: 'a.com', expiresDate: 1700000000),
        Cookie(name: 'c_ms_exp', value: '5', domain: 'a.com', expiresDate: 1700000000000),
      ];

      final result = NetscapeCookieFormatter.format(cookies);

      expect(result, contains('\t0\tc_null_exp\t1'));
      expect(result, contains('\t0\tc_zero_exp\t2'));
      expect(result, contains('\t0\tc_neg_exp\t3'));
      expect(result, contains('\t1700000000\tc_sec_exp\t4'));
      expect(result, contains('\t1700000000\tc_ms_exp\t5'));
    });
  });

  group('Adversarial Empirical Stress — CookieExporter', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vidra_cookie_exporter_stress_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('sanitizeDomainFileName handles edge cases and exotic characters', () {
      expect(CookieExporter.sanitizeDomainFileName('example.com'), equals('example.com_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('https://sub.domain.co.uk/path'), equals('sub.domain.co.uk_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('http://localhost:8080'), equals('localhost_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('...___special.site.org...'), equals('special.site.org_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName(r'weird name with $#@ symbols'), equals('weird_name_with_____symbols_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName(''), equals('default_cookies.txt'));
      expect(CookieExporter.sanitizeDomainFileName('   '), equals('default_cookies.txt'));
    });

    test('saveCookiesToFile throws ArgumentError when savePath is empty or whitespace', () async {
      expect(
        () => CookieExporter.saveCookiesToFile([], savePath: ''),
        throwsArgumentError,
      );
      expect(
        () => CookieExporter.saveCookiesToFile([], savePath: '   '),
        throwsArgumentError,
      );
    });

    test('saveCookiesToFile writes parent directories recursively and creates valid Netscape file', () async {
      final nestedPath = '${tempDir.path}/nested/deep/cookies.txt';
      final cookies = [
        Cookie(name: 'session_id', value: 'xyz987', domain: 'vidra.io', isSecure: true),
      ];

      final returnedPath = await CookieExporter.saveCookiesToFile(cookies, savePath: nestedPath);
      expect(returnedPath, equals(File(nestedPath).absolute.path));

      final file = File(nestedPath);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      expect(content, contains('.vidra.io\tTRUE\t/\tTRUE\t0\tsession_id\txyz987'));
    });

    test('saveDomainCookies creates domain-named file inside target directory', () async {
      final cookies = [
        Cookie(name: 'auth', value: 'token123', domain: 'api.github.com'),
      ];

      final savedPath = await CookieExporter.saveDomainCookies(
        cookies,
        domain: 'api.github.com',
        directory: tempDir,
      );

      final expectedFile = File('${tempDir.path}/api.github.com_cookies.txt');
      expect(savedPath, equals(expectedFile.absolute.path));
      expect(await expectedFile.exists(), isTrue);
    });

    test('getSavedCookieFiles filters non-txt files and sorts by lastModified desc', () async {
      final file1 = File('${tempDir.path}/alpha_cookies.txt');
      final file2 = File('${tempDir.path}/beta_cookies.txt');
      final nonTxt = File('${tempDir.path}/ignore_me.json');

      await file1.writeAsString('file1');
      await Future.delayed(const Duration(milliseconds: 50));
      await file2.writeAsString('file2');
      await nonTxt.writeAsString('{}');

      final list = CookieExporter.getSavedCookieFiles(directory: tempDir);
      expect(list.length, equals(2));
      expect(list.first.path, equals(file2.path));
      expect(list.last.path, equals(file1.path));

      final nonExistent = Directory('${tempDir.path}/does_not_exist');
      expect(CookieExporter.getSavedCookieFiles(directory: nonExistent), isEmpty);
    });
  });

  group('Adversarial Empirical Stress — InAppWebViewScreen Search Engine & Normalization', () {
    test('normalizeUrl enforces Brave as sole search engine for empty and non-url query inputs', () {
      expect(
        InAppWebViewScreen.normalizeUrl(''),
        equals('https://search.brave.com/search?q='),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('   '),
        equals('https://search.brave.com/search?q='),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('flutter tutorial'),
        equals('https://search.brave.com/search?q=flutter%20tutorial'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('vidra video downloader'),
        equals('https://search.brave.com/search?q=vidra%20video%20downloader'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('how to download? q=test&lang=en'),
        equals('https://search.brave.com/search?q=how%20to%20download%3F%20q%3Dtest%26lang%3Den'),
      );
    });

    test('normalizeUrl handles standard URLs, schemes, and domains without search engine redirection', () {
      expect(
        InAppWebViewScreen.normalizeUrl('https://example.com/search?q=123'),
        equals('https://example.com/search?q=123'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('http://insecure.site'),
        equals('http://insecure.site'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('example.com'),
        equals('https://example.com'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('sub.example.com/path'),
        equals('https://sub.example.com/path'), // sanity check
      );
      expect(
        InAppWebViewScreen.normalizeUrl('localhost'),
        equals('https://localhost'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('localhost:8080'),
        equals('https://localhost:8080'),
      );
    });
  });
}
