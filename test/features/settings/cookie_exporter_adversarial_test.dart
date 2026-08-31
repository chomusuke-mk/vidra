import 'dart:io';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidra/features/settings/data/cookie_exporter.dart';
import 'package:vidra/features/settings/domain/netscape_cookie_formatter.dart';

void main() {
  group('NetscapeCookieFormatter Adversarial Edge Cases', () {
    test('IP Addresses: IPv4, IPv6, and bracketed IPv6 formats', () {
      final cookies = [
        // IPv4 Addresses
        Cookie(name: 'c_ipv4_local', value: '1', domain: '127.0.0.1'),
        Cookie(name: 'c_ipv4_lan', value: '2', domain: '192.168.1.254'),
        Cookie(name: 'c_ipv4_wan', value: '3', domain: '8.8.8.8'),
        // IPv6 Addresses
        Cookie(name: 'c_ipv6_loopback', value: '4', domain: '::1'),
        Cookie(
          name: 'c_ipv6_full',
          value: '5',
          domain: '2001:0db8:85a3:0000:0000:8a2e:0370:7334',
        ),
        Cookie(name: 'c_ipv6_bracketed', value: '6', domain: '[::1]'),
        Cookie(
          name: 'c_ipv6_linklocal',
          value: '7',
          domain: 'fe80::1ff:fe23:4567:890a',
        ),
        // Localhost and bare hostnames without dots
        Cookie(name: 'c_localhost', value: '8', domain: 'localhost'),
        Cookie(name: 'c_bare_host', value: '9', domain: 'myintranetserver'),
      ];

      final result = NetscapeCookieFormatter.format(cookies);

      final lines = result.trim().split('\n');
      // 4 header lines + 9 cookies = 13 lines
      expect(lines.length, equals(13));

      // Check IPv4 (must NOT have leading dot, domainFlag must be FALSE)
      final ipv4Local = lines[4].split('\t');
      expect(ipv4Local[0], equals('127.0.0.1'));
      expect(ipv4Local[1], equals('FALSE'));

      final ipv4Lan = lines[5].split('\t');
      expect(ipv4Lan[0], equals('192.168.1.254'));
      expect(ipv4Lan[1], equals('FALSE'));

      final ipv4Wan = lines[6].split('\t');
      expect(ipv4Wan[0], equals('8.8.8.8'));
      expect(ipv4Wan[1], equals('FALSE'));

      // Check IPv6 loopback without dots
      final ipv6Loopback = lines[7].split('\t');
      expect(ipv6Loopback[0], equals('::1'));
      expect(ipv6Loopback[1], equals('FALSE'));

      // Check bare hostnames without dots
      final localhostCol = lines[11].split('\t');
      expect(localhostCol[0], equals('localhost'));
      expect(localhostCol[1], equals('FALSE'));

      final bareHostCol = lines[12].split('\t');
      expect(bareHostCol[0], equals('myintranetserver'));
      expect(bareHostCol[1], equals('FALSE'));
    });

    test(
      'Domain Edge Cases: Multi-level subdomains, ports, and empty fallbacks',
      () {
        final cookies = [
          Cookie(name: 'c_deep', value: 'v1', domain: 'a.b.c.d.example.co.uk'),
          Cookie(
            name: 'c_dot_prefix',
            value: 'v2',
            domain: '.music.youtube.com',
          ),
          Cookie(
            name: 'c_spaces',
            value: 'v3',
            domain: '   .sub.domain.org   ',
          ),
          Cookie(name: 'c_null', value: 'v4', domain: null),
          Cookie(name: 'c_empty', value: 'v5', domain: ''),
          Cookie(name: 'c_whitespace', value: 'v6', domain: '   '),
        ];

        final result = NetscapeCookieFormatter.format(cookies);

        final lines = result.trim().split('\n');
        expect(lines.length, equals(10)); // 4 headers + 6 cookies

        final deepCols = lines[4].split('\t');
        expect(deepCols[0], equals('.a.b.c.d.example.co.uk'));
        expect(deepCols[1], equals('TRUE'));

        final prefixCols = lines[5].split('\t');
        expect(prefixCols[0], equals('.music.youtube.com'));
        expect(prefixCols[1], equals('TRUE'));

        final spacesCols = lines[6].split('\t');
        expect(spacesCols[0], equals('.sub.domain.org'));
        expect(spacesCols[1], equals('TRUE'));

        // Fallbacks
        final nullCols = lines[7].split('\t');
        expect(nullCols[0], equals('.fallback-hub.com'));
        expect(nullCols[1], equals('TRUE'));

        final emptyCols = lines[8].split('\t');
        expect(emptyCols[0], equals('.fallback-hub.com'));
        expect(emptyCols[1], equals('TRUE'));

        final whitespaceCols = lines[9].split('\t');
        expect(whitespaceCols[0], equals('.fallback-hub.com'));
        expect(whitespaceCols[1], equals('TRUE'));
      },
    );

    test(
      'Domain Fallback when defaultDomain is also blank defaults to localhost',
      () {
        final cookies = [
          Cookie(name: 'c_blank_all', value: 'val', domain: '  '),
        ];

        final result = NetscapeCookieFormatter.format(cookies);

        final lines = result.trim().split('\n');
        final cols = lines[4].split('\t');
        expect(cols[0], equals('localhost'));
        expect(cols[1], equals('FALSE'));
      },
    );

    test(
      'Expiration Edge Cases: 0, negative, Year 2038, Year 9999, and int64 max',
      () {
        final cookies = [
          // Session / zero / negative
          Cookie(name: 'c_null_exp', value: '1', expiresDate: null),
          Cookie(name: 'c_zero_exp', value: '2', expiresDate: 0),
          Cookie(name: 'c_neg_exp', value: '3', expiresDate: -1),
          Cookie(name: 'c_large_neg', value: '4', expiresDate: -999999999),
          // Normal seconds (< 100 billion)
          Cookie(name: 'c_secs_normal', value: '5', expiresDate: 1780000000),
          // Year 2038 boundary (32-bit signed int overflow at 2147483647)
          Cookie(name: 'c_y2038_boundary', value: '6', expiresDate: 2147483647),
          Cookie(name: 'c_y2038_plus', value: '7', expiresDate: 2147483648),
          // Normal milliseconds (> 100 billion)
          Cookie(name: 'c_ms_normal', value: '8', expiresDate: 1780000000000),
          // Year 9999 (253402300799 seconds / 253402300799000 ms)
          Cookie(name: 'c_year_9999_sec', value: '9', expiresDate: 25340230079),
          Cookie(
            name: 'c_year_9999_ms',
            value: '10',
            expiresDate: 253402300799000,
          ),
          // Extreme 64-bit int max
          Cookie(
            name: 'c_int64_max_ms',
            value: '11',
            expiresDate: 9223372036854775807,
          ),
        ];

        final result = NetscapeCookieFormatter.format(cookies);

        final lines = result.trim().split('\n');
        expect(lines.length, equals(15)); // 4 headers + 11 cookies

        expect(lines[4].split('\t')[4], equals('0')); // null
        expect(lines[5].split('\t')[4], equals('0')); // 0
        expect(lines[6].split('\t')[4], equals('0')); // -1
        expect(lines[7].split('\t')[4], equals('0')); // -999999999
        expect(lines[8].split('\t')[4], equals('1780000000')); // secs normal
        expect(lines[9].split('\t')[4], equals('2147483647')); // Y2038 boundary
        expect(lines[10].split('\t')[4], equals('2147483648')); // Y2038+
        expect(
          lines[11].split('\t')[4],
          equals('1780000000'),
        ); // ms converted to sec
        expect(lines[12].split('\t')[4], equals('25340230079')); // Y9999 sec
        expect(lines[13].split('\t')[4], equals('253402300799')); // Y9999 ms
        expect(
          lines[14].split('\t')[4],
          equals('9223372036854776'),
        ); // int64 max / 1000
      },
    );

    test(
      'Special Characters in Values: JSON, Base64, URL encoding, Unicode & Emojis',
      () {
        final cookies = [
          Cookie(
            name: 'auth_jwt',
            value:
                'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.doNotLeak',
          ),
          Cookie(
            name: 'base64_data',
            value: 'aHR0cHM6Ly95b3V0dWJlLmNvbS93YXRjaD92PWRRd3c0dzlXZ1hjUQ==',
          ),
          Cookie(
            name: 'json_payload',
            value:
                '{"user_id": 9999, "session_active": true, "flags": ["premium", "beta"]}',
          ),
          Cookie(
            name: 'url_encoded_param',
            value:
                'query=flutter+inappwebview&filter=%7B%22date%22%3A%22today%22%7D',
          ),
          Cookie(
            name: 'symbols_and_quotes',
            value: '!@#\$%^&*()-_=+[]{}|;:\'",.<>/?`~',
          ),
          Cookie(
            name: 'unicode_and_emoji',
            value: '🍪_cookies_delicieux_日本語_русский_español_🔥',
          ),
        ];

        final result = NetscapeCookieFormatter.format(cookies);

        final lines = result.trim().split('\n');
        expect(lines.length, equals(10)); // 4 headers + 6 cookies

        for (int i = 4; i < 10; i++) {
          final cols = lines[i].split('\t');
          expect(
            cols.length,
            equals(7),
            reason: 'Line $i should have exactly 7 TSV columns',
          );
        }

        expect(
          lines[4].split('\t')[6],
          equals(
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.doNotLeak',
          ),
        );
        expect(
          lines[5].split('\t')[6],
          equals('aHR0cHM6Ly95b3V0dWJlLmNvbS93YXRjaD92PWRRd3c0dzlXZ1hjUQ=='),
        );
        expect(
          lines[6].split('\t')[6],
          equals(
            '{"user_id": 9999, "session_active": true, "flags": ["premium", "beta"]}',
          ),
        );
        expect(
          lines[7].split('\t')[6],
          equals(
            'query=flutter+inappwebview&filter=%7B%22date%22%3A%22today%22%7D',
          ),
        );
        expect(
          lines[8].split('\t')[6],
          equals('!@#\$%^&*()-_=+[]{}|;:\'",.<>/?`~'),
        );
        expect(
          lines[9].split('\t')[6],
          equals('🍪_cookies_delicieux_日本語_русский_español_🔥'),
        );
      },
    );

    test('CRLF and Tab Injection Sanitization: Prevents TSV corruption', () {
      final cookies = [
        Cookie(
          name: 'clean_name',
          value: 'line1\r\nline2\tline3\rinjected',
          domain: 'site.com',
        ),
        Cookie(
          name: 'injected\tname\r\nhere',
          value: 'clean_value',
          domain: 'site.com',
        ),
        Cookie(
          name: '\r\n\t  \t',
          value: 'should_be_skipped',
          domain: 'site.com',
        ),
      ];

      final result = NetscapeCookieFormatter.format(cookies);

      final lines = result.trim().split('\n');
      // Header 4 lines + 2 valid cookies (3rd is skipped) = 6 lines
      expect(lines.length, equals(6));

      final c1Cols = lines[4].split('\t');
      expect(c1Cols.length, equals(7));
      expect(c1Cols[5], equals('clean_name'));
      expect(c1Cols[6], equals('line1line2line3injected'));

      final c2Cols = lines[5].split('\t');
      expect(c2Cols.length, equals(7));
      expect(c2Cols[5], equals('injectednamehere'));
      expect(c2Cols[6], equals('clean_value'));
    });

    test(
      'Large Batches (1,500+ cookies): Benchmarks formatting throughput and column integrity',
      () {
        const batchSize = 1500;
        final cookies = List.generate(
          batchSize,
          (i) => Cookie(
            name: 'cookie_batch_$i',
            value: 'token_val_${i}_${'x' * (i % 50)}',
            domain: (i % 3 == 0)
                ? 'domain$i.net'
                : ((i % 3 == 1) ? '.sub$i.org' : '10.0.0.$i'),
            path: (i % 2 == 0) ? '/feed/$i' : null,
            isSecure: i.isEven,
            expiresDate: (i % 2 == 0) ? 1750000000000 + i * 1000 : null,
          ),
        );

        final stopwatch = Stopwatch()..start();
        final result = NetscapeCookieFormatter.format(cookies);
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(500),
          reason: 'Formatting 1,500 cookies should take under 500ms',
        );

        final lines = result.trim().split('\n');
        expect(
          lines.length,
          equals(4 + batchSize),
        ); // 4 headers + 1,500 cookies

        for (int i = 0; i < batchSize; i++) {
          final cols = lines[4 + i].split('\t');
          expect(
            cols.length,
            equals(7),
            reason: 'Cookie line index $i must have 7 columns',
          );
          expect(cols[5], equals('cookie_batch_$i'));
        }
      },
    );
  });

  group('CookieExporter Adversarial File I/O and Permissions', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'vidra_exporter_adversarial_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'Large Batch Export (1,000 cookies) persists and matches exact TSV content',
      () async {
        final cookies = List.generate(
          1000,
          (i) => Cookie(
            name: 'bulk_cookie_$i',
            value: 'bulk_val_$i',
            domain: 'youtube.com',
            path: '/watch',
            expiresDate: 1780000000000,
          ),
        );

        final filePath = await CookieExporter.saveCookiesToFile(
          cookies,
          savePath: p.join(tempDir.path, 'cookies.txt'),
        );

        final file = File(filePath);
        expect(await file.exists(), isTrue);

        final content = await file.readAsString();
        final lines = content.trim().split('\n');
        expect(lines.length, equals(1004)); // 4 header lines + 1,000 cookies

        expect(lines[4].split('\t')[5], equals('bulk_cookie_0'));
        expect(lines.last.split('\t')[5], equals('bulk_cookie_999'));
      },
    );

    test(
      'Deeply nested non-existent directory creation (10 levels deep)',
      () async {
        final deepPath = p.join(
          tempDir.path,
          'level1',
          'level2',
          'level3',
          'level4',
          'level5',
          'cookies_deep.txt',
        );

        final cookies = [
          Cookie(name: 'deep_cookie', value: 'v_deep', domain: 'deep.org'),
        ];

        final savedPath = await CookieExporter.saveCookiesToFile(
          cookies,
          savePath: deepPath,
        );

        expect(savedPath, equals(File(deepPath).absolute.path));
        expect(await File(deepPath).exists(), isTrue);

        final content = await File(deepPath).readAsString();
        expect(content, contains('deep_cookie'));
        expect(content, contains('.deep.org'));
      },
    );

    test(
      'Permission & Invalid Path Stress: Throws FileSystemException when parent is a regular file',
      () async {
        // Create a regular file where a directory would need to be created
        final blockerFile = File(p.join(tempDir.path, 'blocker_file.txt'));
        await blockerFile.writeAsString('I am a regular file');

        // Attempt to save to blocker_file.txt/cookies.txt (illegal path on Unix)
        final impossiblePath = p.join(blockerFile.path, 'cookies.txt');

        final cookies = [
          Cookie(name: 'c_fail', value: 'v_fail', domain: 'fail.com'),
        ];

        expect(
          () async => await CookieExporter.saveCookiesToFile(
            cookies,
            savePath: impossiblePath,
          ),
          throwsA(isA<FileSystemException>()),
        );
      },
    );

    test(
      'Concurrent Exports: Multiple parallel writes complete safely and produce valid file',
      () async {
        final futures = List.generate(10, (i) {
          final cookies = [
            Cookie(name: 'c_thread_$i', value: 'val_$i', domain: 'thread.com'),
          ];
          return CookieExporter.saveCookiesToFile(
            cookies,
            savePath: p.join(tempDir.path, 'cookies_$i.txt'),
          );
        });

        final results = await Future.wait(futures);
        expect(results.length, equals(10));

        final defaultFilePath = p.join(
          tempDir.path, 'cookies_0.txt'
        );
        expect(await File(defaultFilePath).exists(), isTrue);

        final content = await File(defaultFilePath).readAsString();
        expect(content, startsWith('# Netscape HTTP Cookie File'));
        final lines = content.trim().split('\n');
        expect(lines.length, equals(5)); // 4 header lines + 1 cookie line
      },
    );
  });
}
