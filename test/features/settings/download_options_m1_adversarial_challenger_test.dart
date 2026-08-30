import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

void main() {
  group('Empirical Challenger: DownloadOptions M1 Adversarial Suite', () {
    // ------------------------------------------------------------------------
    // 1. Serialization Edge Cases & Precedence Rules
    // ------------------------------------------------------------------------
    group('1. Serialization Precedence & Edge Cases', () {
      test('disableCookiesFromWebview: true MUST serialize to false regardless of cookiesFromWebview content', () {
        final scenarios = <String?, dynamic>{
          null: false,
          '': false,
          '   ': false,
          '/valid/path/cookies.txt': false,
          'C:\\Windows\\System32\\drivers\\etc\\cookies.txt': false,
          'special/!@#\$%^&*()_+/cookies.txt': false,
          'unicode/🍪/cookies.txt': false,
          'A' * 5000: false,
        };

        for (final entry in scenarios.entries) {
          final options = DownloadOptions(
            cookiesFromWebview: entry.key,
            disableCookiesFromWebview: true,
          );
          final json = options.toJson();
          expect(
            json['cookies_from_webview'],
            equals(false),
            reason: 'When disabled, cookies_from_webview must serialize to false for path "${entry.key}"',
          );
        }
      });

      test('disableCookiesFromWebview: false with non-empty path MUST serialize to exact string path', () {
        final testPaths = [
          '/home/user/.config/vidra/cookies.txt',
          'C:\\Users\\User\\AppData\\Local\\Vidra\\cookies_netscape.txt',
          '/var/tmp/space in path/cookies.txt',
          '/tmp/cookies-!@#\$%^&*()-_=+[]{};:,.<>?.txt',
          '/tmp/🍪_unicode_cookies_🚀.txt',
          'https://not-a-file-path-but-arbitrary-string',
          'A' * 2048,
        ];

        for (final path in testPaths) {
          final options = DownloadOptions(
            cookiesFromWebview: path,
            disableCookiesFromWebview: false,
          );
          final json = options.toJson();
          expect(
            json['cookies_from_webview'],
            equals(path),
            reason: 'When enabled with path, must serialize exact string',
          );
        }
      });

      test('disableCookiesFromWebview: false with empty or null path MUST omit cookies_from_webview key', () {
        final optionsNull = DownloadOptions(
          cookiesFromWebview: null,
          disableCookiesFromWebview: false,
        );
        expect(optionsNull.toJson().containsKey('cookies_from_webview'), isFalse);

        final optionsEmpty = DownloadOptions(
          cookiesFromWebview: '',
          disableCookiesFromWebview: false,
        );
        expect(optionsEmpty.toJson().containsKey('cookies_from_webview'), isFalse);
      });
    });

    // ------------------------------------------------------------------------
    // 2. Deserialization Robustness & Type Coercion Fuzzing
    // ------------------------------------------------------------------------
    group('2. Deserialization & Type Coercion Fuzzing', () {
      test('fromJson parses boolean false as disabled', () {
        final json = {'cookies_from_webview': false};
        final options = DownloadOptions.fromJson(json);
        expect(options.disableCookiesFromWebview, isTrue);
        expect(options.cookiesFromWebview, isNull);
      });

      test('fromJson parses string path as enabled with path', () {
        final json = {'cookies_from_webview': '/path/to/extracted/cookies.txt'};
        final options = DownloadOptions.fromJson(json);
        expect(options.disableCookiesFromWebview, isFalse);
        expect(options.cookiesFromWebview, equals('/path/to/extracted/cookies.txt'));
      });

      test('fromJson handles arbitrary malformed types without throwing', () {
        final adversarialPayloads = <dynamic>[
          true,
          0,
          1,
          -1,
          999999,
          3.14159,
          double.nan,
          double.infinity,
          [],
          ['/path/to/cookies.txt'],
          {},
          {'path': '/path/to/cookies.txt'},
          null,
        ];

        for (final payload in adversarialPayloads) {
          final json = {'cookies_from_webview': payload};
          expect(
            () => DownloadOptions.fromJson(json),
            returnsNormally,
            reason: 'fromJson must not throw for payload: $payload',
          );

          final options = DownloadOptions.fromJson(json);
          // When payload is not boolean false, disableCookiesFromWebview is false
          expect(options.disableCookiesFromWebview, isFalse);
          // When payload is not a String, cookiesFromWebview is null
          expect(options.cookiesFromWebview, isNull);
        }
      });

      test('fromJson handles string "false" as valid path string, not boolean false', () {
        // String literal "false" is a valid string/path name, should not be confused with bool false
        final json = {'cookies_from_webview': 'false'};
        final options = DownloadOptions.fromJson(json);
        expect(options.disableCookiesFromWebview, isFalse);
        expect(options.cookiesFromWebview, equals('false'));
      });

      test('fromJson handles missing key in map', () {
        final json = <String, dynamic>{};
        final options = DownloadOptions.fromJson(json);
        expect(options.disableCookiesFromWebview, isFalse);
        expect(options.cookiesFromWebview, isNull);
      });
    });

    // ------------------------------------------------------------------------
    // 3. Round-Trip Serialization and State Invariants
    // ------------------------------------------------------------------------
    group('3. Round-Trip Invariants', () {
      test('Default DownloadOptions round-trips with exact state preservation', () {
        final initial = DownloadOptions();
        expect(initial.disableCookiesFromWebview, isTrue);
        expect(initial.cookiesFromWebview, isNull);

        final json = initial.toJson();
        expect(json['cookies_from_webview'], equals(false));

        final reconstructed = DownloadOptions.fromJson(json);
        expect(reconstructed.disableCookiesFromWebview, isTrue);
        expect(reconstructed.cookiesFromWebview, isNull);
        expect(reconstructed == initial, isTrue);
      });

      test('Enabled DownloadOptions with path round-trips with exact state preservation', () {
        final initial = DownloadOptions(
          cookiesFromWebview: '/secure/vault/netscape_cookies.txt',
          disableCookiesFromWebview: false,
        );

        final json = initial.toJson();
        expect(json['cookies_from_webview'], equals('/secure/vault/netscape_cookies.txt'));

        final reconstructed = DownloadOptions.fromJson(json);
        expect(reconstructed.disableCookiesFromWebview, isFalse);
        expect(reconstructed.cookiesFromWebview, equals('/secure/vault/netscape_cookies.txt'));
        expect(reconstructed == initial, isTrue);
      });

      test('Disabled DownloadOptions with configured path round-trips normalized to disabled null path', () {
        // When serialized, disabled takes precedence and emits false, so deserialization reconstructs as disabled with null path
        final initial = DownloadOptions(
          cookiesFromWebview: '/cached/path/cookies.txt',
          disableCookiesFromWebview: true,
        );

        final json = initial.toJson();
        expect(json['cookies_from_webview'], equals(false));

        final reconstructed = DownloadOptions.fromJson(json);
        expect(reconstructed.disableCookiesFromWebview, isTrue);
        expect(reconstructed.cookiesFromWebview, isNull);
      });
    });

    // ------------------------------------------------------------------------
    // 4. copyWith Mutation Isolation & Deep Field Integrity
    // ------------------------------------------------------------------------
    group('4. copyWith Mutation Isolation', () {
      test('copyWith preserves all other fields when modifying cookies_from_webview', () {
        final baseline = DownloadOptions(
          proxy: 'http://proxy.vidra.local:8080',
          audioQuality: 5,
          concurrentFragments: 4,
          format: 'bv*+ba/b',
          cookies: '/old/cookies.txt',
          cookiesFromWebview: '/old/webview_cookies.txt',
          disableCookiesFromWebview: false,
        );

        final updated = baseline.copyWith(
          cookiesFromWebview: '/new/webview_cookies.txt',
          disableCookiesFromWebview: true,
        );

        // Targeted fields changed
        expect(updated.cookiesFromWebview, equals('/new/webview_cookies.txt'));
        expect(updated.disableCookiesFromWebview, isTrue);

        // All non-targeted fields preserved
        expect(updated.proxy, equals(baseline.proxy));
        expect(updated.audioQuality, equals(baseline.audioQuality));
        expect(updated.concurrentFragments, equals(baseline.concurrentFragments));
        expect(updated.format, equals(baseline.format));
        expect(updated.cookies, equals(baseline.cookies));
      });

      test('copyWith with no arguments produces equivalent instance', () {
        final baseline = DownloadOptions(
          cookiesFromWebview: '/webview/cookies.txt',
          disableCookiesFromWebview: false,
        );

        final cloned = baseline.copyWith();
        expect(cloned == baseline, isTrue);
        expect(cloned.hashCode, equals(baseline.hashCode));
        expect(cloned.cookiesFromWebview, equals(baseline.cookiesFromWebview));
        expect(cloned.disableCookiesFromWebview, equals(baseline.disableCookiesFromWebview));
      });
    });

    // ------------------------------------------------------------------------
    // 5. Equality, Hash Code & Collection Collision Resistance
    // ------------------------------------------------------------------------
    group('5. Equality and Hash Collision Resistance', () {
      test('instances with distinct cookiesFromWebview values are NOT equal', () {
        final a = DownloadOptions(cookiesFromWebview: '/path/a.txt', disableCookiesFromWebview: false);
        final b = DownloadOptions(cookiesFromWebview: '/path/b.txt', disableCookiesFromWebview: false);
        final c = DownloadOptions(cookiesFromWebview: null, disableCookiesFromWebview: false);

        expect(a == b, isFalse);
        expect(a == c, isFalse);
        expect(b == c, isFalse);
      });

      test('instances with distinct disableCookiesFromWebview values are NOT equal', () {
        final a = DownloadOptions(cookiesFromWebview: '/path.txt', disableCookiesFromWebview: true);
        final b = DownloadOptions(cookiesFromWebview: '/path.txt', disableCookiesFromWebview: false);

        expect(a == b, isFalse);
      });

      test('Set and Map maintain uniqueness and lookup precision with cookies_from_webview', () {
        final instances = <DownloadOptions>{};
        final map = <DownloadOptions, String>{};

        const sampleSize = 100;
        for (int i = 0; i < sampleSize; i++) {
          final opt = DownloadOptions(
            cookiesFromWebview: '/path/cookies_$i.txt',
            disableCookiesFromWebview: i % 2 == 0,
            proxy: 'proxy_$i',
          );
          instances.add(opt);
          map[opt] = 'value_$i';
        }

        expect(instances.length, equals(sampleSize));
        expect(map.length, equals(sampleSize));

        // Lookup validation
        for (int i = 0; i < sampleSize; i++) {
          final query = DownloadOptions(
            cookiesFromWebview: '/path/cookies_$i.txt',
            disableCookiesFromWebview: i % 2 == 0,
            proxy: 'proxy_$i',
          );
          expect(instances.contains(query), isTrue);
          expect(map[query], equals('value_$i'));
        }
      });

      test('Randomized fuzz stress test over 1,000 permutations', () {
        final rng = Random(42);
        final seen = <DownloadOptions>{};
        int uniqueCount = 0;

        for (int i = 0; i < 1000; i++) {
          final pathChoice = rng.nextBool() ? '/path/${rng.nextInt(50)}.txt' : null;
          final disableChoice = rng.nextBool();
          final opt = DownloadOptions(
            cookiesFromWebview: pathChoice,
            disableCookiesFromWebview: disableChoice,
            username: 'user_${rng.nextInt(10)}',
          );

          if (!seen.contains(opt)) {
            uniqueCount++;
            seen.add(opt);
          }

          // Invariant check: identical reconstructed instance must match
          final clone = DownloadOptions(
            cookiesFromWebview: pathChoice,
            disableCookiesFromWebview: disableChoice,
            username: opt.username,
          );
          expect(opt == clone, isTrue);
          expect(opt.hashCode, equals(clone.hashCode));
        }

        expect(seen.length, equals(uniqueCount));
      });
    });
  });
}
