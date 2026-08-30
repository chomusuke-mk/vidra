import 'dart:math';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/settings/domain/netscape_cookie_formatter.dart';

void main() {
  group('NetscapeCookieFormatter Adversarial & Stress Suite', () {
    test('Adversarial 1: Boundary & Overflow Expirations', () {
      final cookies = [
        Cookie(
          name: 'c_zero',
          value: 'v',
          domain: 'example.com',
          expiresDate: 0,
        ),
        Cookie(
          name: 'c_neg',
          value: 'v',
          domain: 'example.com',
          expiresDate: -999999,
        ),
        Cookie(
          name: 'c_y2038',
          value: 'v',
          domain: 'example.com',
          expiresDate: 2147483647000, // 2038 in ms
        ),
        Cookie(
          name: 'c_year3000',
          value: 'v',
          domain: 'example.com',
          expiresDate: 32503680000000, // Year 3000 in ms
        ),
        Cookie(
          name: 'c_seconds_direct',
          value: 'v',
          domain: 'example.com',
          expiresDate: 1780000000, // Already in seconds
        ),
      ];

      final result = NetscapeCookieFormatter.format(
        cookies,
        defaultDomain: 'example.com',
      );

      final lines = result.trim().split('\n');
      expect(lines.length, equals(9)); // 4 header lines + 5 cookies

      expect(lines[4].split('\t')[4], equals('0'));
      expect(lines[5].split('\t')[4], equals('0'));
      expect(lines[6].split('\t')[4], equals('2147483647'));
      expect(lines[7].split('\t')[4], equals('32503680000'));
      expect(lines[8].split('\t')[4], equals('1780000000'));
    });

    test('Adversarial 2: Domain Matrix & Subdomain Matching Rules', () {
      final cookies = [
        Cookie(name: 'c1', value: 'v', domain: '192.168.1.1'),
        Cookie(name: 'c2', value: 'v', domain: '10.0.0.1'),
        Cookie(name: 'c3', value: 'v', domain: '127.0.0.1'),
        Cookie(name: 'c4', value: 'v', domain: 'localhost'),
        Cookie(name: 'c5', value: 'v', domain: 'my-nas-server'),
        Cookie(name: 'c6', value: 'v', domain: 'google.com'),
        Cookie(name: 'c7', value: 'v', domain: '.google.com'),
        Cookie(name: 'c8', value: 'v', domain: 'sub.deep.domain.co.uk'),
        Cookie(name: 'c9', value: 'v', domain: '.sub.deep.domain.co.uk'),
        Cookie(name: 'c10', value: 'v', domain: '  '),
        Cookie(name: 'c11', value: 'v', domain: null),
      ];

      final result = NetscapeCookieFormatter.format(
        cookies,
        defaultDomain: 'fallback.org',
      );

      final lines = result.trim().split('\n');
      expect(lines.length, equals(15)); // 4 header + 11 cookies

      // IPv4 -> FALSE, no leading dot
      expect(lines[4].split('\t')[0], equals('192.168.1.1'));
      expect(lines[4].split('\t')[1], equals('FALSE'));
      expect(lines[5].split('\t')[0], equals('10.0.0.1'));
      expect(lines[5].split('\t')[1], equals('FALSE'));
      expect(lines[6].split('\t')[0], equals('127.0.0.1'));
      expect(lines[6].split('\t')[1], equals('FALSE'));

      // Local single hostnames -> FALSE, no leading dot
      expect(lines[7].split('\t')[0], equals('localhost'));
      expect(lines[7].split('\t')[1], equals('FALSE'));
      expect(lines[8].split('\t')[0], equals('my-nas-server'));
      expect(lines[8].split('\t')[1], equals('FALSE'));

      // Domains -> TRUE, leading dot
      expect(lines[9].split('\t')[0], equals('.google.com'));
      expect(lines[9].split('\t')[1], equals('TRUE'));
      expect(lines[10].split('\t')[0], equals('.google.com'));
      expect(lines[10].split('\t')[1], equals('TRUE'));
      expect(lines[11].split('\t')[0], equals('.sub.deep.domain.co.uk'));
      expect(lines[11].split('\t')[1], equals('TRUE'));
      expect(lines[12].split('\t')[0], equals('.sub.deep.domain.co.uk'));
      expect(lines[12].split('\t')[1], equals('TRUE'));

      // Fallbacks -> .fallback.org, TRUE
      expect(lines[13].split('\t')[0], equals('.fallback.org'));
      expect(lines[13].split('\t')[1], equals('TRUE'));
      expect(lines[14].split('\t')[0], equals('.fallback.org'));
      expect(lines[14].split('\t')[1], equals('TRUE'));
    });

    test('Adversarial 3: Special characters, JSON, and complex payloads in values', () {
      final cookies = [
        Cookie(
          name: 'auth_token',
          value: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c',
          domain: 'auth.service.io',
        ),
        Cookie(
          name: 'complex_cookie',
          value: '{"user_id":123,"roles":["admin","vip"],"prefs":{"dark_mode":true,"volume":0.8}}',
          domain: 'app.example.org',
        ),
        Cookie(
          name: 'url_encoded',
          value: 'foo%20bar%3D123%26baz%3Dhello%2Bworld%21%23%24',
          domain: 'site.com',
        ),
        Cookie(
          name: 'unicode_emoji',
          value: '🚀🌟VidraCookie_⚡_ñáéíóú_日本語_中文',
          domain: 'unicode.org',
        ),
        Cookie(
          name: 'tab_newline_injection',
          value: 'safe_prefix\tINJECTED_COLUMN\r\nINJECTED_ROW\tFALSE\t/',
          domain: 'safe.com',
        ),
      ];

      final result = NetscapeCookieFormatter.format(
        cookies,
        defaultDomain: 'test.com',
      );

      final lines = result.trim().split('\n');
      expect(lines.length, equals(9)); // 4 header + 5 cookies

      for (int i = 4; i < lines.length; i++) {
        final cols = lines[i].split('\t');
        expect(cols.length, equals(7), reason: 'Line $i must have strictly 7 columns');
        expect(cols[1], isIn(['TRUE', 'FALSE']));
        expect(cols[3], isIn(['TRUE', 'FALSE']));
        expect(int.tryParse(cols[4]), isNotNull);
        expect(cols[5], isNotEmpty);
      }

      // Check tab/newline injection was neutralized
      final sanitizedLine = lines[8];
      final sanitizedCols = sanitizedLine.split('\t');
      expect(sanitizedCols.length, equals(7));
      expect(sanitizedCols[6], equals('safe_prefixINJECTED_COLUMNINJECTED_ROWFALSE/'));
    });

    test('Adversarial 4: High-volume randomized fuzz matrix (2,000 cookies)', () {
      final random = Random(42);
      final cookies = <Cookie>[];

      final domainPool = [
        'youtube.com',
        '.google.com',
        'sub.vimeo.com',
        '192.168.1.50',
        'localhost',
        '127.0.0.1',
        'twitch.tv',
        '  ',
        null,
      ];

      for (int i = 0; i < 2000; i++) {
        final isSecure = random.nextBool();
        final domain = domainPool[random.nextInt(domainPool.length)];
        final path = random.nextBool() ? '/path/$i' : null;
        final expiry = random.nextBool()
            ? (random.nextBool() ? random.nextInt(2000000000) * 1000 : random.nextInt(2000000000))
            : null;

        cookies.add(
          Cookie(
            name: 'cookie_fuzz_$i',
            value: 'val_${random.nextInt(1000000)}_hash#${random.nextDouble()}',
            domain: domain,
            path: path,
            isSecure: isSecure,
            expiresDate: expiry,
          ),
        );
      }

      final result = NetscapeCookieFormatter.format(
        cookies,
        defaultDomain: 'vidra.default.org',
      );

      final lines = result.trim().split('\n');
      expect(lines.length, equals(2004)); // 4 header + 2000 cookies

      for (int i = 4; i < lines.length; i++) {
        final cols = lines[i].split('\t');
        expect(cols.length, equals(7));
        expect(cols[1], isIn(['TRUE', 'FALSE']));
        expect(cols[3], isIn(['TRUE', 'FALSE']));
        expect(int.tryParse(cols[4]), isNotNull);
        expect(cols[5], startsWith('cookie_fuzz_'));
      }
    });
  });
}
