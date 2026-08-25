import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/settings/domain/download_option_formatters.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppStringKey enLocale;
  late AppStringKey esLocale;
  late List<String> languageCatalog;

  setUpAll(() async {
    enLocale = AppStringKey();
    await enLocale.updateFromJson({
      's_default': 'Default (Recommended)',
      's_best': 'Best Available',
      's_audio_language': 'Audio Language',
      's_video_resolution': 'Video Resolution',
    });

    esLocale = AppStringKey();
    await esLocale.updateFromJson({
      's_default': 'Predeterminado (Recomendado)',
      's_best': 'Mejor Disponible',
      's_audio_language': 'Idioma del Audio',
      's_video_resolution': 'Resolución de Video',
    });

    languageCatalog = DownloadOptionFormatters.audioLanguageOptions;
  });

  group('LazyDropdown Performance & Benchmark Suite', () {
    // =========================================================================
    // GROUP 1: INITIAL MOUNT & CONSTRUCTION BENCHMARK (~185 ITEMS)
    // =========================================================================
    testWidgets(
      '1. Initial mount & render latency with full language catalog (~186 items)',
      (WidgetTester tester) async {
        int labelBuilderCalls = 0;
        String labelBuilder(String code) {
          labelBuilderCalls++;
          return DownloadOptionFormatters.formatLanguage(code, enLocale);
        }

        // Warm up test binding / widget framework to avoid measuring one-time JIT boot
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: SizedBox.shrink()),
          ),
        );
        await tester.pumpAndSettle();

        final stopwatch = Stopwatch()..start();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LazyDropdown<String>(
                value: 'defaultOption',
                items: languageCatalog,
                label: 'Audio Language',
                labelBuilder: labelBuilder,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        stopwatch.stop();

        final mountTimeMs = stopwatch.elapsedMicroseconds / 1000.0;
        debugPrint(
          '📊 [BENCHMARK 1] Initial Mount (~186 items): '
          '${mountTimeMs.toStringAsFixed(2)} ms | labelBuilder calls: $labelBuilderCalls',
        );

        // Deterministic assertions:
        // Exactly 186 items built once during initial mount
        expect(labelBuilderCalls, equals(languageCatalog.length));
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Default (Recommended)',
        );
        expect(
          mountTimeMs,
          lessThan(2000.0),
          reason: 'Initial mount must finish within generous bound',
        );
      },
    );

    // =========================================================================
    // GROUP 2: HIGH-FREQUENCY REBUILD & MEMOIZATION BENCHMARK (100 CYCLES)
    // =========================================================================
    testWidgets(
      '2. High-frequency 100 rebuild cycles validates memoization & zero allocation churn',
      (WidgetTester tester) async {
        int labelBuilderCalls = 0;
        int parentRebuildCount = 0;
        late StateSetter triggerParentSetState;

        String labelBuilder(String code) {
          labelBuilderCalls++;
          return DownloadOptionFormatters.formatLanguage(code, enLocale);
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  triggerParentSetState = setState;
                  return Column(
                    children: [
                      Text('Rebuild Count: $parentRebuildCount'),
                      LazyDropdown<String>(
                        value: 'es',
                        items: languageCatalog,
                        label: 'Audio Language',
                        labelBuilder: labelBuilder,
                        onChanged: (_) {},
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final initialCalls = labelBuilderCalls;
        expect(initialCalls, equals(languageCatalog.length));

        // Capture initial DropdownMenu widget entries reference
        final initialDropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        final initialEntries = initialDropdown.dropdownMenuEntries;

        const int rebuildCycles = 100;
        final stopwatch = Stopwatch()..start();

        for (int i = 0; i < rebuildCycles; i++) {
          triggerParentSetState(() {
            parentRebuildCount++;
          });
          await tester.pump();
        }

        stopwatch.stop();
        final totalRebuildTimeMs = stopwatch.elapsedMicroseconds / 1000.0;
        final avgRebuildTimeUs = stopwatch.elapsedMicroseconds / rebuildCycles;
        final callsAfterRebuild = labelBuilderCalls;
        final callsDelta = callsAfterRebuild - initialCalls;

        final finalDropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        final finalEntries = finalDropdown.dropdownMenuEntries;

        debugPrint(
          '📊 [BENCHMARK 2] 100 Rebuilds: Total ${totalRebuildTimeMs.toStringAsFixed(2)} ms '
          '(${avgRebuildTimeUs.toStringAsFixed(1)} µs/frame) | Extra labelBuilder calls: $callsDelta '
          '| Avoided allocations: ${languageCatalog.length * rebuildCycles} entries',
        );

        // Deterministic assertions:
        // ZERO extra labelBuilder invocations across 100 rebuilds
        expect(
          callsDelta,
          equals(0),
          reason:
              'Memoized LazyDropdown must not re-invoke labelBuilder during rebuilds',
        );
        expect(callsAfterRebuild, equals(languageCatalog.length));

        // Object identity of entries list preserved
        expect(
          identical(initialEntries, finalEntries),
          isTrue,
          reason: 'DropdownMenuEntry list must maintain reference identity',
        );
        expect(
          totalRebuildTimeMs,
          lessThan(2000.0),
          reason: '100 rebuilds must complete within generous bound',
        );
      },
    );

    // =========================================================================
    // GROUP 3: SEARCH, AUTOCOMPLETE & KEYSTROKE FILTERING LATENCY BENCHMARK
    // =========================================================================
    testWidgets(
      '3. Interactive search & keystroke filtering latency with enableSearch: true',
      (WidgetTester tester) async {
        int labelBuilderCalls = 0;
        String labelBuilder(String code) {
          labelBuilderCalls++;
          return DownloadOptionFormatters.formatLanguage(code, enLocale);
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LazyDropdown<String>(
                value: 'defaultOption',
                items: languageCatalog,
                enableSearch: true,
                label: 'Search Language',
                labelBuilder: labelBuilder,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final callsBeforeSearch = labelBuilderCalls;
        expect(callsBeforeSearch, equals(languageCatalog.length));

        final dropdownField = find.byType(TextField);
        expect(dropdownField, findsOneWidget);

        // Open menu
        await tester.tap(dropdownField);
        await tester.pumpAndSettle();

        final searchQueries = ['e', 'es', 'esp'];
        final List<double> keystrokeTimesMs = [];

        for (final query in searchQueries) {
          final keyStopwatch = Stopwatch()..start();
          await tester.enterText(dropdownField, query);
          await tester.pump();
          keyStopwatch.stop();
          keystrokeTimesMs.add(keyStopwatch.elapsedMicroseconds / 1000.0);
        }
        await tester.pumpAndSettle();

        debugPrint(
          '📊 [BENCHMARK 3] Keystroke Latencies for queries $searchQueries: '
          '${keystrokeTimesMs.map((t) => "${t.toStringAsFixed(2)}ms").toList()} | '
          'Calls delta: ${labelBuilderCalls - callsBeforeSearch}',
        );

        // Deterministic assertions:
        // Typing does not trigger re-generation of master dropdownMenuEntries
        expect(labelBuilderCalls - callsBeforeSearch, equals(0));

        for (final lat in keystrokeTimesMs) {
          expect(
            lat,
            lessThan(300.0),
            reason: 'Each search keystroke must filter within generous bound',
          );
        }
      },
    );

    // =========================================================================
    // GROUP 4: CUSTOM INPUT SUBMISSION & FOCUS BLUR LATENCY BENCHMARK
    // =========================================================================
    testWidgets(
      '4. Custom input submission and O(1) set lookup on blur with allowCustom: true',
      (WidgetTester tester) async {
        int labelBuilderCalls = 0;
        String? customSubmitted;

        String labelBuilder(String code) {
          labelBuilderCalls++;
          return DownloadOptionFormatters.formatLanguage(code, enLocale);
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  LazyDropdown<String>(
                    value: 'defaultOption',
                    items: languageCatalog,
                    allowCustom: true,
                    label: 'Custom Language',
                    labelBuilder: labelBuilder,
                    onChanged: (_) {},
                    onCustomSubmit: (val) => customSubmitted = val,
                  ),
                  const TextField(key: Key('blur_target')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final callsBeforeCustom = labelBuilderCalls;
        final dropdownInput = find.byType(TextField).first;
        final blurTarget = find.byKey(const Key('blur_target'));

        // 1. Submit truly custom value
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, 'custom-lang-xyz');
        await tester.pumpAndSettle();

        final blurStopwatch = Stopwatch()..start();
        await tester.tap(blurTarget, warnIfMissed: false);
        await tester.pumpAndSettle();
        blurStopwatch.stop();

        final blurTimeMs = blurStopwatch.elapsedMicroseconds / 1000.0;
        debugPrint(
          '📊 [BENCHMARK 4] Custom submit blur latency: ${blurTimeMs.toStringAsFixed(2)} ms',
        );

        expect(customSubmitted, equals('custom-lang-xyz'));
        expect(
          labelBuilderCalls - callsBeforeCustom,
          equals(0),
          reason:
              'Blur lookup must use cached Set and avoid re-mapping items',
        );

        // 2. Submit existing label -> rejected in O(1) time
        customSubmitted = null;
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, 'es - Español');
        await tester.pumpAndSettle();

        await tester.tap(blurTarget, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(
          customSubmitted,
          isNull,
          reason: 'Existing label must not trigger onCustomSubmit',
        );
        expect(labelBuilderCalls - callsBeforeCustom, equals(0));
      },
    );

    // =========================================================================
    // GROUP 5: DYNAMIC INVALIDATION & LOCALE SWITCHING BENCHMARK
    // =========================================================================
    testWidgets(
      '5. Dynamic locale switch triggers precise invalidation and restores memoization',
      (WidgetTester tester) async {
        int labelBuilderCalls = 0;
        AppStringKey currentLocale = enLocale;
        late StateSetter triggerLocaleSetState;

        String labelBuilder(String code) {
          labelBuilderCalls++;
          return DownloadOptionFormatters.formatLanguage(code, currentLocale);
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  triggerLocaleSetState = setState;
                  return LazyDropdown<String>(
                    value: 'defaultOption',
                    items: languageCatalog,
                    label: currentLocale.sAudioLanguage,
                    labelBuilder: labelBuilder,
                    onChanged: (_) {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(labelBuilderCalls, equals(languageCatalog.length));
        final dropdownField = find.byType(TextField);
        expect(
          tester.widget<TextField>(dropdownField).controller?.text,
          'Default (Recommended)',
        );

        // Switch Locale EN -> ES
        final switchStopwatch = Stopwatch()..start();
        triggerLocaleSetState(() {
          currentLocale = esLocale;
        });
        await tester.pumpAndSettle();
        switchStopwatch.stop();

        final switchTimeMs = switchStopwatch.elapsedMicroseconds / 1000.0;
        debugPrint(
          '📊 [BENCHMARK 5] Dynamic Locale Switch EN->ES: '
          '${switchTimeMs.toStringAsFixed(2)} ms | Total calls: $labelBuilderCalls',
        );

        // Invalidation occurred: exactly 186 additional calls for Spanish entries
        expect(labelBuilderCalls, equals(languageCatalog.length * 2));
        expect(
          tester.widget<TextField>(dropdownField).controller?.text,
          'Predeterminado (Recomendado)',
        );

        // 50 subsequent rebuilds in Spanish must be fully memoized (0 additional calls)
        final callsAfterSwitch = labelBuilderCalls;
        for (int i = 0; i < 50; i++) {
          triggerLocaleSetState(() {});
          await tester.pump();
        }

        expect(
          labelBuilderCalls - callsAfterSwitch,
          equals(0),
          reason: 'Rebuilds post-invalidation must remain memoized',
        );
      },
    );

    // =========================================================================
    // GROUP 6: LARGE DATASET SCALABILITY MATRIX (500 & 1,000 ITEMS)
    // =========================================================================
    testWidgets(
      '6. Scalability stress test with 500 and 1,000 synthetic items',
      (WidgetTester tester) async {
        for (final count in [500, 1000]) {
          int labelBuilderCalls = 0;
          final items = List.generate(count, (i) => 'item_$i');

          final stopwatch = Stopwatch()..start();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: LazyDropdown<String>(
                  value: 'item_0',
                  items: items,
                  labelBuilder: (item) {
                    labelBuilderCalls++;
                    return 'Label: $item';
                  },
                  onChanged: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          stopwatch.stop();

          final mountMs = stopwatch.elapsedMicroseconds / 1000.0;
          expect(labelBuilderCalls, equals(count));

          // 20 Rebuilds
          final rebuildStopwatch = Stopwatch()..start();
          for (int i = 0; i < 20; i++) {
            await tester.pump();
          }
          rebuildStopwatch.stop();

          final avgRebuildUs = rebuildStopwatch.elapsedMicroseconds / 20.0;
          debugPrint(
            '📊 [BENCHMARK 6] Scale ($count items): Initial Mount: ${mountMs.toStringAsFixed(2)} ms | '
            'Avg Rebuild: ${avgRebuildUs.toStringAsFixed(1)} µs/frame | Extra calls: 0',
          );

          expect(
            labelBuilderCalls,
            equals(count),
            reason: 'No extra calls during rebuilds for $count items',
          );
        }
      },
    );
  });
}
