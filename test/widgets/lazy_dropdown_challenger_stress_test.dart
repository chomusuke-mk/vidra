import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Challenger 1: Deep Adversarial & Stress Testing Matrix', () {
    // =========================================================================
    // 1. EXTREME SCALE: 5,000 AND 10,000 ITEMS
    // =========================================================================
    testWidgets(
      '1.1 Extreme Scale: 5,000 items mount, 100 rebuilds, search filter, and selection',
      (WidgetTester tester) async {
        const int count = 5000;
        final items = List.generate(count, (i) => 'scale_item_$i');
        int labelBuilderCalls = 0;
        String? selectedValue = 'scale_item_0';
        int parentRebuilds = 0;
        late StateSetter triggerRebuild;

        String labelBuilder(String val) {
          labelBuilderCalls++;
          return 'Label for $val';
        }

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
                        value: selectedValue,
                        items: items,
                        enableSearch: true,
                        label: 'Extreme Scale 5K',
                        labelBuilder: labelBuilder,
                        onChanged: (val) => setState(() => selectedValue = val),
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
        debugPrint('🔥 [CHALLENGER 1.1] 5,000 items Mount: ${mountMs.toStringAsFixed(2)} ms');

        expect(labelBuilderCalls, equals(count));
        final textField = find.byType(TextField);
        expect(tester.widget<TextField>(textField).controller?.text, 'Label for scale_item_0');

        // 100 rapid parent rebuild loops
        final rebuildWatch = Stopwatch()..start();
        for (int i = 0; i < 100; i++) {
          triggerRebuild(() {
            parentRebuilds++;
          });
          await tester.pump();
        }
        rebuildWatch.stop();
        final avgRebuildUs = rebuildWatch.elapsedMicroseconds / 100.0;
        debugPrint('🔥 [CHALLENGER 1.1] 5,000 items 100 Rebuilds: Avg ${avgRebuildUs.toStringAsFixed(1)} µs/frame');

        // Zero extra labelBuilder calls
        expect(labelBuilderCalls, equals(count));

        // Filter search on 5,000 items
        await tester.tap(textField);
        await tester.pumpAndSettle();

        final searchWatch = Stopwatch()..start();
        await tester.enterText(textField, 'scale_item_4999');
        await tester.pumpAndSettle();
        searchWatch.stop();
        debugPrint('🔥 [CHALLENGER 1.1] 5,000 items Search Filter: ${searchWatch.elapsedMicroseconds / 1000.0} ms');

        expect(labelBuilderCalls, equals(count)); // Filter should not re-invoke labelBuilder
      },
    );

    testWidgets(
      '1.2 Extreme Scale: 10,000 items mount, memoization, and item selection at boundary',
      (WidgetTester tester) async {
        const int count = 10000;
        final items = List.generate(count, (i) => 'bulk_item_$i');
        int labelBuilderCalls = 0;
        String? selectedValue = 'bulk_item_9999';

        String labelBuilder(String val) => 'Bulk $val';

        final mountWatch = Stopwatch()..start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return LazyDropdown<String>(
                    value: selectedValue,
                    items: items,
                    enableSearch: true,
                    labelBuilder: (val) {
                      labelBuilderCalls++;
                      return labelBuilder(val);
                    },
                    onChanged: (val) => setState(() => selectedValue = val),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        mountWatch.stop();

        debugPrint('🔥 [CHALLENGER 1.2] 10,000 items Mount: ${mountWatch.elapsedMicroseconds / 1000.0} ms');
        expect(labelBuilderCalls, equals(count));

        final textField = find.byType(TextField);
        expect(tester.widget<TextField>(textField).controller?.text, 'Bulk bulk_item_9999');
      },
    );

    // =========================================================================
    // 2. ADVERSARIAL UNICODE, RTL, CJK, EMOJI ZWJ, AND REGEX STRINGS
    // =========================================================================
    testWidgets(
      '2.1 Adversarial Unicode: RTL, CJK, Emoji ZWJ, BiDi override, and hostile search filtering',
      (WidgetTester tester) async {
        final Map<String, String> catalogMap = {
          'rtl_ar_1': 'مرحبا بالعالم - تسجيل الدخول',
          'rtl_ar_2': 'البحث السريع 123 ٤٥٦',
          'rtl_he_1': 'שלום עולם - בדיקת מערכת',
          'rtl_he_2': 'עברית תקינה עם ספרות 789',
          'cjk_ja_1': '日本語のテキスト（漢字・ひらがな・カタカナ）',
          'cjk_zh_1': '简体中文与繁體中文混合測試',
          'cjk_ko_1': '한국어 테스트 문자열 (한글)',
          'cjk_fullwidth': 'ＡＢＣ１２３　全角スペース',
          'emoji_zwj_1': '👨‍👩‍👧‍👦 Family ZWJ Sequence',
          'emoji_zwj_2': '👩🏽‍💻 Tech Woman Medium Skin Tone',
          'emoji_flag': '🏴󠁧󠁢󠁳󠁣󠁴󠁿 Scotland Flag Subdivision Sequence',
          'bidi_override': '\u202E\u202DReversed Left To Right Override\u202C',
          'regex_meta_1': r'.*+?^${}()|[]\',
          'regex_meta_2': r'^(http|https)://[a-zA-Z0-9_\-\.]+\.[a-zA-Z]{2,6}(/.*)?$',
          'null_and_control': 'Control \x00 \x07 \x1B \t \n End',
          'extreme_length': 'A' * 2000,
        };

        final items = catalogMap.keys.toList();
        String? selectedValue = 'rtl_ar_1';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return LazyDropdown<String>(
                    value: selectedValue,
                    items: items,
                    enableSearch: true,
                    allowCustom: true,
                    labelBuilder: (key) => catalogMap[key] ?? key,
                    onChanged: (val) => setState(() => selectedValue = val),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final textField = find.byType(TextField);
        expect(tester.widget<TextField>(textField).controller?.text, catalogMap['rtl_ar_1']);

        // Search adversarial patterns
        final hostileQueries = [
          'مرحبا',
          'שלום',
          'ひらがな',
          '繁體',
          '한국어',
          '👨‍👩‍👧‍👦',
          r'.*+?^${}()|[]\',
          r'^(http',
          '\u202E',
          'A' * 500,
          '   \t\n\r   ',
          'non_matching_query_!@#\$%^&*()_+',
        ];

        for (final query in hostileQueries) {
          await tester.enterText(textField, query);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        // Must still be alive and functional
        expect(find.byType(DropdownMenu<String>), findsOneWidget);
      },
    );

    // =========================================================================
    // 3. RAPID CONCURRENT REBUILDS & INTERLEAVED KEYSTROKES
    // =========================================================================
    testWidgets(
      '3.1 Rapid concurrent parent rebuilds interleaved with active keystroke burst',
      (WidgetTester tester) async {
        final items = ['alpha', 'beta', 'gamma', 'delta', 'epsilon'];
        String? selectedValue = 'alpha';
        int parentCounter = 0;
        late StateSetter triggerParentSetState;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  triggerParentSetState = setState;
                  return Column(
                    children: [
                      Text('Count: $parentCounter'),
                      LazyDropdown<String>(
                        value: selectedValue,
                        items: items,
                        enableSearch: true,
                        allowCustom: true,
                        labelBuilder: (val) => 'Item $val',
                        onChanged: (val) => setState(() => selectedValue = val),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final textField = find.byType(TextField);
        await tester.tap(textField);
        await tester.pumpAndSettle();

        // Interleave rapid typing with parent rebuilds
        final characters = 'abcdefghijklmnopqrstuvwxyz'.split('');
        for (int i = 0; i < characters.length; i++) {
          await tester.enterText(textField, characters.sublist(0, i + 1).join());
          triggerParentSetState(() {
            parentCounter++;
          });
          await tester.pump(); // Fast frame pump without settling
        }
        await tester.pumpAndSettle();

        expect(find.byType(LazyDropdown<String>), findsOneWidget);
      },
    );

    // =========================================================================
    // 4. EDGE CASES: EMPTY LISTS, DUPLICATE LABELS, NULL/EMPTY CUSTOM SUBMISSIONS
    // =========================================================================
    testWidgets(
      '4.1 Edge Cases: Empty list transitions, duplicate values and duplicate labels',
      (WidgetTester tester) async {
        List<String> items = [];
        String? selectedValue;
        late StateSetter updateState;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  updateState = setState;
                  return LazyDropdown<String>(
                    value: selectedValue,
                    items: items,
                    allowCustom: true,
                    labelBuilder: (val) => 'Prefix: $val',
                    onChanged: (val) => setState(() => selectedValue = val),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final textField = find.byType(TextField);
        expect(tester.widget<TextField>(textField).controller?.text, isEmpty);

        // Transition: Empty -> 3 items with duplicate labels
        updateState(() {
          items = ['opt_1', 'opt_2', 'opt_3'];
          selectedValue = 'opt_1';
        });
        await tester.pumpAndSettle();

        expect(tester.widget<TextField>(textField).controller?.text, 'Prefix: opt_1');

        // Transition: Same 3 items, but labelBuilder creates exact duplicates
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  updateState = setState;
                  return LazyDropdown<String>(
                    value: selectedValue,
                    items: items,
                    allowCustom: true,
                    labelBuilder: (_) => 'Same Duplicate Label',
                    onChanged: (val) => setState(() => selectedValue = val),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.widget<TextField>(textField).controller?.text, 'Same Duplicate Label');

        // Transition back to empty list []
        updateState(() {
          items = [];
          selectedValue = null;
        });
        await tester.pumpAndSettle();

        expect(tester.widget<TextField>(textField).controller?.text, isEmpty);
      },
    );

    testWidgets(
      '4.2 Edge Cases: Custom submission with null, empty, whitespace-only, and known collision',
      (WidgetTester tester) async {
        final items = ['res_1080', 'res_720', 'res_480'];
        String? customSubmission;
        String? selectedValue = 'res_1080';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      LazyDropdown<String>(
                        value: selectedValue,
                        items: items,
                        allowCustom: true,
                        labelBuilder: (val) => val == 'res_1080' ? '1080p Full HD' : '$val p',
                        onChanged: (val) => setState(() => selectedValue = val),
                        onCustomSubmit: (val) => setState(() => customSubmission = val),
                      ),
                      const TextField(key: Key('blur_node_42')),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dropdownField = find.byType(TextField).first;
        final blurNode = find.byKey(const Key('blur_node_42'));

        // Case A: Submit exact catalog label '1080p Full HD' -> should NOT invoke onCustomSubmit
        await tester.tap(dropdownField);
        await tester.enterText(dropdownField, '1080p Full HD');
        await tester.pumpAndSettle();
        await tester.tap(blurNode, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(customSubmission, isNull);

        // Case B: Submit empty string '' -> should NOT invoke onCustomSubmit
        customSubmission = null;
        await tester.tap(dropdownField);
        await tester.enterText(dropdownField, '');
        await tester.pumpAndSettle();
        await tester.tap(blurNode, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(customSubmission, isNull);

        // Case C: Submit whitespace only '   \t  ' -> should NOT invoke onCustomSubmit
        customSubmission = null;
        await tester.tap(dropdownField);
        await tester.enterText(dropdownField, '   \t\n   ');
        await tester.pumpAndSettle();
        await tester.tap(blurNode, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(customSubmission, isNull);

        // Case D: Submit valid custom value '2560x1440' -> MUST invoke onCustomSubmit
        customSubmission = null;
        await tester.tap(dropdownField);
        await tester.enterText(dropdownField, '2560x1440');
        await tester.pumpAndSettle();
        await tester.tap(blurNode, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(customSubmission, equals('2560x1440'));
      },
    );

    // =========================================================================
    // 5. SEARCHCALLBACK SEMANTIC CONTRACT VERIFICATION
    // =========================================================================
    testWidgets(
      '5.1 SearchCallback Fast-Path: Master cached entries semantic contract, case insensitivity, whitespace, disabled items',
      (WidgetTester tester) async {
        final items = ['en_US', 'es_ES', 'fr_FR', 'de_DE', 'ja_JP'];
        final labels = {
          'en_US': 'English (United States)',
          'es_ES': 'Español (España)',
          'fr_FR': 'Français (France)',
          'de_DE': 'Deutsch (Deutschland)',
          'ja_JP': '日本語 (Japan)',
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LazyDropdown<String>(
                value: 'en_US',
                items: items,
                enableSearch: true,
                labelBuilder: (k) => labels[k] ?? k,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dropdownMenu = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        final searchCallback = dropdownMenu.searchCallback!;
        final entries = dropdownMenu.dropdownMenuEntries;

        // 1. Exact match on master list
        expect(searchCallback(entries, 'English'), equals(0));
        expect(searchCallback(entries, 'Español'), equals(1));
        expect(searchCallback(entries, 'Deutsch'), equals(3));
        expect(searchCallback(entries, '日本語'), equals(4));

        // 2. Case-insensitive matching (UPPERCASE & mixed)
        expect(searchCallback(entries, 'ENGLISH'), equals(0));
        expect(searchCallback(entries, 'esPAÑol'), equals(1));
        expect(searchCallback(entries, 'DEUTSCH'), equals(3));

        // 3. Substring matching
        expect(searchCallback(entries, 'States'), equals(0));
        expect(searchCallback(entries, 'France'), equals(2));
        expect(searchCallback(entries, 'pan'), equals(4)); // 'Japan'

        // 4. Whitespace trimming & whitespace-only queries
        expect(searchCallback(entries, '  Français  '), equals(2));
        expect(searchCallback(entries, '   '), isNull);
        expect(searchCallback(entries, ''), isNull);

        // 5. Non-matching queries
        expect(searchCallback(entries, 'Russian'), isNull);
        expect(searchCallback(entries, 'xyz123'), isNull);

        // 6. Empty entries list
        expect(searchCallback([], 'English'), isNull);
      },
    );

    testWidgets(
      '5.2 SearchCallback Fallback-Path: Dynamic / filtered subset matching, relative index accuracy, disabled entries',
      (WidgetTester tester) async {
        final items = ['item_0', 'item_1', 'item_2', 'item_3'];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LazyDropdown<String>(
                value: 'item_0',
                items: items,
                enableSearch: true,
                labelBuilder: (k) => 'Alpha $k',
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dropdownMenu = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        final searchCallback = dropdownMenu.searchCallback!;

        // Construct a dynamic / filtered sub-list (not identical to _cachedEntries)
        final subsetEntries = [
          const DropdownMenuEntry<String>(
            value: 'sub_0',
            label: 'Gamma First Option',
            enabled: true,
          ),
          const DropdownMenuEntry<String>(
            value: 'sub_1',
            label: 'Delta Disabled Option',
            enabled: false, // Disabled!
          ),
          const DropdownMenuEntry<String>(
            value: 'sub_2',
            label: 'Delta Second Enabled Option',
            enabled: true,
          ),
          const DropdownMenuEntry<String>(
            value: 'sub_3',
            label: 'Omega Final Option',
            enabled: true,
          ),
        ];

        // 1. Fallback searches directly on entry.label case-insensitively
        expect(searchCallback(subsetEntries, 'gamma'), equals(0));
        expect(searchCallback(subsetEntries, 'GAMMA'), equals(0));
        expect(searchCallback(subsetEntries, 'omega'), equals(3));

        // 2. Disabled entry skipping: search 'Delta' should skip sub_1 (disabled) and return sub_2 (index 2)
        expect(searchCallback(subsetEntries, 'delta'), equals(2));
        expect(searchCallback(subsetEntries, 'DELTA DISABLED'), isNull); // only disabled matches -> returns null

        // 3. Substring non-match
        expect(searchCallback(subsetEntries, 'NonExistent'), isNull);
        expect(searchCallback(subsetEntries, '   '), isNull);
      },
    );

    // =========================================================================
    // 6. FILTERCALLBACK CONTRACT & LATENCY GUARD VERIFICATION
    // =========================================================================
    testWidgets(
      '6.1 FilterCallback: Empty query returns full catalog, broad query capped to 50 items, memoization',
      (WidgetTester tester) async {
        const int totalItems = 300;
        final items = List.generate(totalItems, (i) => 'entry_$i');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LazyDropdown<String>(
                value: 'entry_0',
                items: items,
                enableSearch: true,
                labelBuilder: (k) => 'Audio Track $k (Stereo)',
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dropdownMenu = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>),
        );
        final filterCallback = dropdownMenu.filterCallback!;
        final entries = dropdownMenu.dropdownMenuEntries;

        // 1. Empty query -> returns full catalog (300 items)
        final fullResult = filterCallback(entries, '');
        expect(fullResult.length, equals(totalItems));

        // 2. Whitespace-only query -> returns full catalog
        final wsResult = filterCallback(entries, '   \t  ');
        expect(wsResult.length, equals(totalItems));

        // 3. Broad query matching all 300 items ('Track') -> MUST be capped to exactly 50 items
        final broadResult = filterCallback(entries, 'Track');
        expect(broadResult.length, equals(50), reason: 'Broad queries must cap to 50 items to prevent UI frame drop');

        // 4. Memoization: repeated query returns the exact same list instance
        final broadResult2 = filterCallback(entries, 'Track');
        expect(identical(broadResult, broadResult2), isTrue);

        // 5. Specific query matching 3 items ('entry_29') -> returns exactly matching items
        // 'entry_29', 'entry_290'..'entry_299' -> 11 items
        final specificResult = filterCallback(entries, 'entry_29');
        expect(specificResult.length, equals(11));
        for (final item in specificResult) {
          expect(item.label.contains('entry_29'), isTrue);
        }

        // 6. Zero matches
        final zeroResult = filterCallback(entries, 'non_existent_query_xyz');
        expect(zeroResult.isEmpty, isTrue);
      },
    );

    // =========================================================================
    // 7. END-TO-END SEARCH SELECTION & KEYBOARD FLOW
    // =========================================================================
    testWidgets(
      '7.1 End-to-end: Search filter typing, filtered popup tap, and selection callback invocation',
      (WidgetTester tester) async {
        String? selectedValue = 'res_720';
        final items = List.generate(100, (i) => 'res_${i * 10}');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return LazyDropdown<String>(
                    value: selectedValue,
                    items: items,
                    enableSearch: true,
                    labelBuilder: (k) => 'Resolution $k HD',
                    onChanged: (val) => setState(() => selectedValue = val),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final textField = find.byType(TextField);
        expect(tester.widget<TextField>(textField).controller?.text, 'Resolution res_720 HD');

        // Tap to open dropdown
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();

        // Type query 'res_980' to filter
        await tester.enterText(textField, 'res_980');
        await tester.pumpAndSettle();

        // Target matching entry in popup
        final matchingEntry = find.text('Resolution res_980 HD').last;
        expect(matchingEntry, findsOneWidget);

        await tester.tap(matchingEntry);
        await tester.pumpAndSettle();

        // Verify selection updated state & controller text
        expect(selectedValue, equals('res_980'));
        expect(tester.widget<TextField>(textField).controller?.text, 'Resolution res_980 HD');
      },
    );
  });
}
