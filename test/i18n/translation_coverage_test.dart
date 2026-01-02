import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart' show jsoncDecode;
import 'package:path/path.dart' as p;
import 'package:vidra/i18n/i18n.dart';

void main() {
  final localesRoot = Directory(
    p.join(Directory.current.path, 'i18n', 'locales'),
  );
  if (!localesRoot.existsSync()) {
    fail('Expected localization assets in ${localesRoot.path}');
  }
  final envFallback = _resolveFallbackLocale();
  final requiredKeys = <String>{
    ...AppStringKey.values,
    ...ErrorStringKey.values,
  };
  final localeCodes =
      localesRoot
          .listSync()
          .whereType<Directory>()
          .map((dir) => p.basename(dir.path))
          .where((name) => name.trim().isNotEmpty)
          .toList()
        ..sort();

  group('i18n assets', () {
    test('fallback locale stays at 100% coverage', () {
      final fallbackBundle = _loadLocaleBundle(envFallback, localesRoot);
      final missing =
          requiredKeys.where((key) => !_hasValue(fallbackBundle[key])).toList()
            ..sort();
      if (missing.isNotEmpty) {
        // ignore: avoid_print
        print(
          'Fallback "$envFallback" is missing ${missing.length} keys: '
          '${missing.join(', ')}',
        );
      }
      expect(
        missing,
        isEmpty,
        reason: 'Fallback locale must contain every key',
      );
    });

    test('translation progress table', () {
      final buckets = <_Bucket, List<String>>{};
      for (final locale in localeCodes) {
        final bundle = _loadLocaleBundle(locale, localesRoot);
        final translated = requiredKeys
            .where((key) => _hasValue(bundle[key]))
            .length;
        final ratio = requiredKeys.isEmpty
            ? 1.0
            : translated / requiredKeys.length;
        final bucket = _Bucket.fromRatio(ratio);
        buckets.putIfAbsent(bucket, () => <String>[]).add(locale);
      }
      final sortedBuckets = buckets.keys.toList()..sort();
      for (final bucket in sortedBuckets) {
        final locales = buckets[bucket]!..sort();
        // Example: 90%-99%:[de,fr] or 100%:[en]
        // ignore: avoid_print
        print('${bucket.label}:[${locales.join(',')}]');
      }
      expect(sortedBuckets, isNotEmpty);
    });

    test('prints missing keys for selected locale', () {
      const locale = 'fr';
      const maxMissing = -1; // -1 => print all missing keys
      final bundle = _loadLocaleBundle(locale, localesRoot);
      final missing =
          requiredKeys.where((key) => !_hasValue(bundle[key])).toList()..sort();
      final slice = maxMissing < 0
          ? missing
          : missing.take(maxMissing).toList();
      // ignore: avoid_print
      print(
        'Missing keys for $locale (${missing.length} total): ${slice.join(', ')}',
      );
      expect(missing.length, greaterThanOrEqualTo(slice.length));
    });
  });
}

Map<String, String> _loadLocaleBundle(String locale, Directory root) {
  final normalized = locale.toLowerCase();
  final bundle = <String, String>{};
  for (final fileName in const ['ui.jsonc', 'errors.jsonc']) {
    final file = File(p.join(root.path, normalized, fileName));
    if (!file.existsSync()) {
      continue;
    }
    final decoded = jsoncDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw FormatException('Expected object in ${file.path}');
    }
    decoded.forEach((key, value) {
      if (key == null || value == null) {
        return;
      }
      bundle[key.toString()] = value.toString();
    });
  }
  return bundle;
}

bool _hasValue(String? value) {
  return value != null && value.trim().isNotEmpty;
}

String _resolveFallbackLocale() {
  final envFile = File(p.join(Directory.current.path, '.env'));
  if (!envFile.existsSync()) {
    return 'en';
  }
  final lines = envFile.readAsLinesSync();
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final index = line.indexOf('=');
    if (index == -1) {
      continue;
    }
    final key = line.substring(0, index).trim().toLowerCase();
    if (key != 'FALLBACK_LANGUAGE') {
      continue;
    }
    final value = line.substring(index + 1).trim();
    return _normalizeToSupported(value);
  }
  return 'en';
}

String _normalizeToSupported(String? locale) {
  if (locale == null || locale.trim().isEmpty) {
    return 'en';
  }
  final canonical = locale.replaceAll('_', '-').toLowerCase();
  if (I18n.supportedLanguageCodes.contains(canonical)) {
    return canonical;
  }
  final base = canonical.split('-').first;
  if (I18n.supportedLanguageCodes.contains(base)) {
    return base;
  }
  return 'en';
}

class _Bucket implements Comparable<_Bucket> {
  _Bucket(this.lower, this.upper);

  factory _Bucket.fromRatio(double ratio) {
    final percent = (ratio * 100).clamp(0, 100).toDouble();
    if (percent >= 100) {
      return _Bucket(100, 100);
    }
    final floored = percent.floor();
    final lower = (floored ~/ 10) * 10;
    final upper = lower == 90 ? 99 : lower + 9;
    return _Bucket(lower, upper);
  }

  final int lower;
  final int upper;

  String get label {
    if (lower == 100 && upper == 100) {
      return '100%';
    }
    return '${lower.toString().padLeft(2, '0')}%-'
        '${upper.toString().padLeft(2, '0')}%';
  }

  @override
  int compareTo(_Bucket other) {
    return lower.compareTo(other.lower);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _Bucket && other.lower == lower && other.upper == upper;
  }

  @override
  int get hashCode => Object.hash(lower, upper);
}
