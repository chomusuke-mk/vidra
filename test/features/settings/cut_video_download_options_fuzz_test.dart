import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

void main() {
  group('Adversarial & Fuzz Tests: Cut Video DownloadOptions Serialization', () {
    test('1. Deterministic round-trip fuzz matrix for valid cutVideo configurations', () {
      final startTimes = [0, 1, 15, 59, 60, 3599, 3600, 7200, 86400, 359999];
      final endTimes = [0, 1, 30, 60, 120, 3600, 7200, 86400, 359999];
      final untilEndOptions = [true, false];
      final cutVideoFlags = [true, false];

      for (final cut in cutVideoFlags) {
        for (final start in startTimes) {
          for (final untilEnd in untilEndOptions) {
            for (final end in endTimes) {
              final options = DownloadOptions(
                cutVideo: cut,
                cutVideoStart: start,
                cutVideoUntilEnd: untilEnd,
                cutVideoEnd: end,
              );

              final json = options.toJson();

              if (!cut) {
                expect(json['cut_video'], isFalse);
              } else if (untilEnd) {
                expect(json['cut_video'], equals([start, 'inf']));
              } else {
                expect(json['cut_video'], equals([start, end]));
              }

              final restored = DownloadOptions.fromJson(json);

              if (!cut) {
                expect(restored.cutVideo, isFalse);
                // When cutVideo is false, default deserialization preserves defaults
                expect(restored.cutVideoStart, equals(0));
                expect(restored.cutVideoUntilEnd, isTrue);
                expect(restored.cutVideoEnd, equals(0));
              } else {
                expect(restored.cutVideo, isTrue);
                expect(restored.cutVideoStart, equals(start));
                expect(restored.cutVideoUntilEnd, equals(untilEnd));
                if (!untilEnd) {
                  expect(restored.cutVideoEnd, equals(end));
                }
              }
            }
          }
        }
      }
    });

    test('2. Fuzzing cut_video deserialization against malformed & adversary payloads', () {
      final adversarialPayloads = <dynamic>[
        null,
        false,
        true,
        0,
        -1,
        100,
        3.14,
        double.nan,
        double.infinity,
        "",
        "inf",
        "infinite",
        "false",
        "true",
        "random_string",
        [],
        [10],
        ["inf"],
        [null],
        [false],
        [true],
        [{}],
        [[]],
        [10, 20, 30, 40],
        [null, null],
        [null, "inf"],
        [10, null],
        ["invalid_start", "invalid_end"],
        ["15", "300"],
        ["15", "inf"],
        ["15", "infinite"],
        ["15", "INF"],
        ["15", "INFINITE"],
        [-100, -200],
        [-50, "inf"],
        [0, 0],
        [999999, 9999999],
        [3.5, 9.8],
        [double.nan, double.infinity],
        [true, false],
        [false, true],
        [{}, {}],
        [[], []],
        {"start": 10, "end": 20},
        {"cut_video": true},
      ];

      for (final payload in adversarialPayloads) {
        final rawJson = {'cut_video': payload};

        // Invariant: fromJson must never throw an unhandled exception
        DownloadOptions? restored;
        expect(() {
          restored = DownloadOptions.fromJson(rawJson);
        }, returnsNormally, reason: 'Failed with payload: $payload');

        expect(restored, isNotNull);
        expect(restored!.cutVideo, isA<bool>());
        expect(restored!.cutVideoStart, isA<int>());
        expect(restored!.cutVideoUntilEnd, isA<bool>());
        expect(restored!.cutVideoEnd, isA<int>());

        // Invariant: toJson after adversarial fromJson must serialize cleanly
        Map<String, dynamic>? serialized;
        expect(() {
          serialized = restored!.toJson();
        }, returnsNormally);

        expect(serialized, isNotNull);
        expect(serialized!['cut_video'], isNotNull);
      }
    });

    test('3. Randomized high-volume fuzz generator (1,000 iterations)', () {
      final rand = Random(42);
      final randomTypes = [
        () => rand.nextInt(5000) - 1000,
        () => rand.nextDouble() * 1000.0,
        () => (rand.nextInt(5000) - 1000).toString(),
        () => rand.nextBool(),
        () => 'inf',
        () => 'infinite',
        () => 'INF',
        () => 'invalid_${rand.nextInt(100)}',
        () => null,
        () => <dynamic>[rand.nextInt(100)],
        () => <String, dynamic>{'nested': rand.nextInt(100)},
      ];

      for (int i = 0; i < 1000; i++) {
        final listLength = rand.nextInt(5);
        final list = List<dynamic>.generate(
          listLength,
          (_) => randomTypes[rand.nextInt(randomTypes.length)](),
        );

        final json = <String, dynamic>{'cut_video': list};

        DownloadOptions? options;
        expect(() {
          options = DownloadOptions.fromJson(json);
        }, returnsNormally);

        expect(options, isNotNull);
        expect(options!.cutVideo, isA<bool>());
        expect(options!.cutVideoStart, isA<int>());
        expect(options!.cutVideoUntilEnd, isA<bool>());
        expect(options!.cutVideoEnd, isA<int>());

        final reJson = options!.toJson();
        final reRestored = DownloadOptions.fromJson(reJson);
        expect(reRestored.cutVideo, equals(options!.cutVideo));
        expect(reRestored.cutVideoStart, equals(options!.cutVideoStart));
        expect(reRestored.cutVideoUntilEnd, equals(options!.cutVideoUntilEnd));
        expect(reRestored.cutVideoEnd, equals(options!.cutVideoEnd));
      }
    });

    test('4. HashCode and Equality stress test with cut_video combinations', () {
      final base = DownloadOptions(
        cutVideo: true,
        cutVideoStart: 100,
        cutVideoUntilEnd: false,
        cutVideoEnd: 200,
      );

      final identicalInstance = DownloadOptions(
        cutVideo: true,
        cutVideoStart: 100,
        cutVideoUntilEnd: false,
        cutVideoEnd: 200,
      );

      final diffCut = base.copyWith(cutVideo: false);
      final diffStart = base.copyWith(cutVideoStart: 101);
      final diffUntilEnd = base.copyWith(cutVideoUntilEnd: true);
      final diffEnd = base.copyWith(cutVideoEnd: 201);

      expect(base, equals(identicalInstance));
      expect(base.hashCode, equals(identicalInstance.hashCode));

      expect(base, isNot(equals(diffCut)));
      expect(base, isNot(equals(diffStart)));
      expect(base, isNot(equals(diffUntilEnd)));
      expect(base, isNot(equals(diffEnd)));

      final set = <DownloadOptions>{
        base,
        identicalInstance,
        diffCut,
        diffStart,
        diffUntilEnd,
        diffEnd,
      };
      expect(set.length, equals(5));
    });
  });
}
