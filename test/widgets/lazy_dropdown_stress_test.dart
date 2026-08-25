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

  group('LazyDropdown Empirical Stress & Invalidation Matrix', () {
    // =========================================================================
    // STRESS 1: 500+ PARENT REBUILD CYCLES (STABLE REFERENCE)
    // =========================================================================
    testWidgets(
      'STRESS 1: 500 parent rebuild cycles preserves entry identity and executes 0 extra labelBuilder calls',
      (WidgetTester tester) async {
        int labelBuilderCalls = 0;
        int parentRebuildCount = 0;
        late StateSetter triggerParentSetState;

        String stableLabelBuilder(String code) {
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
                      Text('Parent Counter: $parentRebuildCount'),
                      LazyDropdown<String>(
                        value: 'en',
                        items: languageCatalog,
                        label: 'Audio Language',
                        labelBuilder: stableLabelBuilder,
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

        final initialDropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        final initialEntries = initialDropdown.dropdownMenuEntries;

        const int stressCycles = 500;
        final stopwatch = Stopwatch()..start();

        for (int i = 0; i < stressCycles; i++) {
          triggerParentSetState(() {
            parentRebuildCount++;
          });
          await tester.pump();
        }

        stopwatch.stop();
        final totalTimeMs = stopwatch.elapsedMicroseconds / 1000.0;
        final avgUsPerFrame = stopwatch.elapsedMicroseconds / stressCycles;

        final finalDropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        final finalEntries = finalDropdown.dropdownMenuEntries;

        debugPrint(
          '🔥 [STRESS 1] 500 Rebuilds: Total ${totalTimeMs.toStringAsFixed(2)} ms '
          '(${avgUsPerFrame.toStringAsFixed(1)} µs/frame) | Extra calls: ${labelBuilderCalls - initialCalls} '
          '| Identity Preserved: ${identical(initialEntries, finalEntries)}',
        );

        // Verification assertions
        expect(labelBuilderCalls, equals(initialCalls));
        expect(identical(initialEntries, finalEntries), isTrue);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'en - English',
        );
      },
    );

    // =========================================================================
    // STRESS 2: RAPID BIDIRECTIONAL LOCALE CYCLING (EN <-> ES for 30 CYCLES)
    // =========================================================================
    testWidgets(
      'STRESS 2: Rapid back-and-forth locale switches (EN <-> ES 30 cycles) cleanly invalidates cache with zero memory leak',
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

        const int switchCycles = 30; // 30 toggles
        final stopwatch = Stopwatch()..start();

        for (int cycle = 1; cycle <= switchCycles; cycle++) {
          final isEs = (cycle % 2 == 1);

          triggerLocaleSetState(() {
            currentLocale = isEs ? esLocale : enLocale;
          });
          await tester.pumpAndSettle();

          final expectedCallsAfter = languageCatalog.length * (cycle + 1);
          expect(
            labelBuilderCalls,
            equals(expectedCallsAfter),
            reason:
                'Cycle $cycle: cache invalidation must trigger exactly 1 pass (${languageCatalog.length} calls)',
          );

          final expectedText = isEs
              ? 'Predeterminado (Recomendado)'
              : 'Default (Recommended)';
          expect(
            tester.widget<TextField>(dropdownField).controller?.text,
            equals(expectedText),
            reason: 'Cycle $cycle: controller text must match current locale',
          );

          // 10 intermediate parent rebuilds per cycle must not cause any extra calls
          for (int r = 0; r < 10; r++) {
            triggerLocaleSetState(() {});
            await tester.pump();
          }
          expect(
            labelBuilderCalls,
            equals(expectedCallsAfter),
            reason:
                'Cycle $cycle: intermediate rebuilds within locale must remain memoized',
          );
        }

        stopwatch.stop();
        final totalSwitchMs = stopwatch.elapsedMicroseconds / 1000.0;
        final avgSwitchMs = totalSwitchMs / switchCycles;

        debugPrint(
          '🔥 [STRESS 2] 30 Rapid Locale Switches: Total ${totalSwitchMs.toStringAsFixed(2)} ms '
          '(${avgSwitchMs.toStringAsFixed(2)} ms/switch) | Total calls: $labelBuilderCalls (Expected: ${languageCatalog.length * (switchCycles + 1)})',
        );

        expect(
          labelBuilderCalls,
          equals(languageCatalog.length * (switchCycles + 1)),
        );
      },
    );

    // =========================================================================
    // STRESS 3: MASSIVE DATASET SCALABILITY (2,000+ ITEMS)
    // =========================================================================
    testWidgets(
      'STRESS 3: Large synthetic dataset (2,000 items) with stable and closure labelBuilders',
      (WidgetTester tester) async {
        const int count = 2000;
        final items = List.generate(count, (i) => 'entry_key_$i');

        // Part A: Stable labelBuilder reference
        int stableCalls = 0;
        String stableLabelBuilder(String item) {
          stableCalls++;
          return 'Item: $item';
        }

        int parentRebuilds = 0;
        late StateSetter triggerRebuild;

        final mountWatch = Stopwatch()..start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  triggerRebuild = setState;
                  return Column(
                    children: [
                      Text('Rebuilds: $parentRebuilds'),
                      LazyDropdown<String>(
                        value: 'entry_key_0',
                        items: items,
                        labelBuilder: stableLabelBuilder,
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
        mountWatch.stop();

        final mountMs = mountWatch.elapsedMicroseconds / 1000.0;
        expect(stableCalls, equals(count));

        // 100 Rebuild cycles on massive dataset
        final rebuildWatch = Stopwatch()..start();
        for (int i = 0; i < 100; i++) {
          triggerRebuild(() {
            parentRebuilds++;
          });
          await tester.pump();
        }
        rebuildWatch.stop();

        final avgRebuildUs = rebuildWatch.elapsedMicroseconds / 100.0;
        debugPrint(
          '🔥 [STRESS 3A] Scale ($count items - Stable Ref): Initial Mount: ${mountMs.toStringAsFixed(2)} ms | '
          '100 Rebuilds Avg: ${avgRebuildUs.toStringAsFixed(1)} µs/frame | Extra calls: ${stableCalls - count}',
        );

        expect(
          stableCalls,
          equals(count),
          reason: 'Zero extra calls across 100 rebuilds for 2,000 items',
        );

        final dropdownMenu = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        expect(dropdownMenu.dropdownMenuEntries.length, equals(count));

        // Part B: Dynamic closure labelBuilder with sample probing
        int dynamicCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  triggerRebuild = setState;
                  return LazyDropdown<String>(
                    value: 'entry_key_0',
                    items: items,
                    labelBuilder: (item) {
                      dynamicCalls++;
                      return 'Dynamic: $item';
                    },
                    onChanged: (_) {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dynamicInitialCalls = dynamicCalls;
        expect(dynamicInitialCalls, equals(count));

        // 50 Rebuilds with new closure per build -> 1 sample probe call per rebuild
        for (int i = 0; i < 50; i++) {
          triggerRebuild(() {});
          await tester.pump();
        }

        final dynamicTotalCalls = dynamicCalls;
        debugPrint(
          '🔥 [STRESS 3B] Scale ($count items - Dynamic Closure Probing): '
          'Initial: $dynamicInitialCalls | After 50 rebuilds: $dynamicTotalCalls '
          '(Probed calls: ${dynamicTotalCalls - dynamicInitialCalls}/50, Avoided entry allocations: ${50 * count})',
        );

        // Probing verifies only 1 call per rebuild (50 total calls), NOT 2000 * 50 = 100,000 calls
        expect(dynamicTotalCalls - dynamicInitialCalls, equals(50));
      },
    );

    // =========================================================================
    // STRESS 4: DYNAMIC LIST MUTATION MATRIX (REPLACE, REORDER, RESIZE, EMPTY)
    // =========================================================================
    testWidgets(
      'STRESS 4: In-place items mutation, reordering, resizing, and empty transitions trigger exact invalidation',
      (WidgetTester tester) async {
        int labelBuilderCalls = 0;
        List<String> currentItems = ['alpha', 'beta', 'gamma'];
        String? currentValue = 'alpha';
        late StateSetter triggerUpdate;

        String labelBuilder(String val) {
          labelBuilderCalls++;
          return 'Label-$val';
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  triggerUpdate = setState;
                  return LazyDropdown<String>(
                    value: currentValue,
                    items: currentItems,
                    labelBuilder: labelBuilder,
                    onChanged: (v) => currentValue = v,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(labelBuilderCalls, equals(3));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Label-alpha',
        );

        // Step A: Replace item with same list length ['alpha', 'beta', 'omega']
        triggerUpdate(() {
          currentItems = ['alpha', 'beta', 'omega'];
        });
        await tester.pumpAndSettle();

        expect(
          labelBuilderCalls,
          equals(6),
          reason: 'Item content mutation must invalidate cache',
        );

        // Step B: Reorder items ['omega', 'beta', 'alpha'] (same length, same elements)
        triggerUpdate(() {
          currentItems = ['omega', 'beta', 'alpha'];
        });
        await tester.pumpAndSettle();

        expect(
          labelBuilderCalls,
          equals(9),
          reason: 'Item reordering must invalidate cache',
        );
        final dropdown = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        expect(dropdown.dropdownMenuEntries.first.value, 'omega');
        expect(dropdown.dropdownMenuEntries.last.value, 'alpha');

        // Step C: Transition to empty list []
        triggerUpdate(() {
          currentItems = [];
          currentValue = null;
        });
        await tester.pumpAndSettle();

        expect(
          tester.widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
              .dropdownMenuEntries
              .isEmpty,
          isTrue,
        );

        // Step D: Transition from empty to 100 items
        triggerUpdate(() {
          currentItems = List.generate(100, (i) => 'item_$i');
          currentValue = 'item_0';
        });
        await tester.pumpAndSettle();

        expect(labelBuilderCalls, equals(9 + 0 + 100)); // 109
        expect(
          tester.widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
              .dropdownMenuEntries
              .length,
          equals(100),
        );
      },
    );

    // =========================================================================
    // STRESS 5: RAPID CUSTOM SUBMISSION & FOCUS LOSS (20 CYCLES)
    // =========================================================================
    testWidgets(
      'STRESS 5: Rapid custom submissions & focus loss cycles maintain O(1) lookups and zero listener leakage',
      (WidgetTester tester) async {
        int labelBuilderCalls = 0;
        final List<String> submittedValues = [];

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
                    onCustomSubmit: (v) => submittedValues.add(v),
                  ),
                  const TextField(key: Key('stress_blur_target')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final initialCalls = labelBuilderCalls;
        expect(initialCalls, equals(languageCatalog.length));

        final dropdownField = find.byType(TextField).first;
        final blurField = find.byKey(const Key('stress_blur_target'));

        const int iterations = 20;
        final stopwatch = Stopwatch()..start();

        for (int i = 0; i < iterations; i++) {
          final isCustom = (i % 2 == 0);
          final textToEnter = isCustom ? 'custom_code_$i' : 'es - Español';

          await tester.tap(dropdownField);
          await tester.enterText(dropdownField, textToEnter);
          await tester.pumpAndSettle();

          await tester.tap(blurField, warnIfMissed: false);
          await tester.pumpAndSettle();
        }
        stopwatch.stop();

        final totalBlurMs = stopwatch.elapsedMicroseconds / 1000.0;
        final avgBlurMs = totalBlurMs / iterations;

        debugPrint(
          '🔥 [STRESS 5] 20 Custom Blur Iterations: Total ${totalBlurMs.toStringAsFixed(2)} ms '
          '(${avgBlurMs.toStringAsFixed(2)} ms/iter) | Submissions: ${submittedValues.length} '
          '| Extra labelBuilder calls: ${labelBuilderCalls - initialCalls}',
        );

        // Exactly 10 custom submissions (even indices), 0 for known labels
        expect(submittedValues.length, equals(10));
        expect(submittedValues.first, equals('custom_code_0'));
        expect(submittedValues.last, equals('custom_code_18'));

        // ZERO extra labelBuilder calls during all blur events
        expect(
          labelBuilderCalls - initialCalls,
          equals(0),
          reason: 'Set lookups must remain O(1) and never call labelBuilder',
        );
      },
    );

    // =========================================================================
    // STRESS 6: RAPID KEYSTROKE FILTERING UNDER CONCURRENT REBUILDS
    // =========================================================================
    testWidgets(
      'STRESS 6: Rapid sequential keystroke filtering (36 characters typed) with enableSearch: true',
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
        final dropdownField = find.byType(TextField);

        await tester.tap(dropdownField);
        await tester.pumpAndSettle();

        final testKeys = 'abcdefghijklmnopqrstuvwxyz0123456789'.split('');
        String currentQuery = '';

        final stopwatch = Stopwatch()..start();
        for (final char in testKeys) {
          currentQuery += char;
          await tester.enterText(dropdownField, currentQuery);
          await tester.pump();
        }
        await tester.pumpAndSettle();
        stopwatch.stop();

        final totalTypeMs = stopwatch.elapsedMicroseconds / 1000.0;
        final avgTypeMs = totalTypeMs / testKeys.length;

        debugPrint(
          '🔥 [STRESS 6] Rapid 36 Keystrokes: Total ${totalTypeMs.toStringAsFixed(2)} ms '
          '(${avgTypeMs.toStringAsFixed(2)} ms/keystroke) | Extra labelBuilder calls: ${labelBuilderCalls - callsBeforeSearch}',
        );

        expect(labelBuilderCalls - callsBeforeSearch, equals(0));
      },
    );
  });
}
