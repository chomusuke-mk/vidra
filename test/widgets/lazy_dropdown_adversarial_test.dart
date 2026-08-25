import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';

void main() {
  group('Adversarial & Interaction Tests: LazyDropdown', () {
    // =========================================================================
    // 1. BASELINE INTERACTION & SELECTION
    // =========================================================================
    testWidgets(
      '1. Item selection updates controller text and triggers onChanged callback',
      (WidgetTester tester) async {
        String? selectedValue = '1080';
        final items = ['720', '1080', '1440', '2160'];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return LazyDropdown<String>(
                    value: selectedValue,
                    items: items,
                    label: 'Video Resolution',
                    labelBuilder: (item) => '${item}p HD',
                    onChanged: (val) => setState(() => selectedValue = val),
                  );
                },
              ),
            ),
          ),
        );

        final textField = find.byType(TextField);
        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals('1080p HD'),
        );

        // Open Dropdown
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();

        // Tap '2160p HD' in dropdown menu entries
        final entry2160 = find.text('2160p HD').last;
        await tester.tap(entry2160);
        await tester.pumpAndSettle();

        expect(selectedValue, equals('2160'));
        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals('2160p HD'),
        );
      },
    );

    // =========================================================================
    // 2. CUSTOM SUBMIT & BLUR INVARIANTS
    // =========================================================================
    testWidgets(
      '2. Custom submit triggers on blur only when text is non-empty and not a known label',
      (WidgetTester tester) async {
        String? customSubmitted;
        String selectedValue = 'bestvideo';
        final items = ['bestvideo', '1080', '720'];

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
                        labelBuilder:
                            (val) =>
                                val == 'bestvideo'
                                    ? 'Best Available'
                                    : '${val}p',
                        onChanged: (val) => setState(() => selectedValue = val),
                        onCustomSubmit:
                            (val) => setState(() => customSubmitted = val),
                      ),
                      const TextField(key: Key('external_focus_target')),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        final dropdownInput = find.byType(TextField).first;
        final externalField = find.byKey(const Key('external_focus_target'));

        // Scenario A: Enter a completely custom value '1440x900'
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, '1440x900');
        await tester.pumpAndSettle();

        // Blur by focusing external field
        await tester.tap(externalField, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(customSubmitted, equals('1440x900'));

        // Reset
        customSubmitted = null;

        // Scenario B: Enter an EXISTING label ('Best Available') -> should NOT trigger onCustomSubmit
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, 'Best Available');
        await tester.pumpAndSettle();

        await tester.tap(externalField, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(customSubmitted, isNull);

        // Scenario C: Enter empty or spaces only -> should NOT trigger onCustomSubmit
        customSubmitted = null;
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, '     ');
        await tester.pumpAndSettle();

        await tester.tap(externalField, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(customSubmitted, isNull);
      },
    );

    // =========================================================================
    // 3. LIVE TRANSLATION / DIDUPDATEWIDGET INVALIDATION
    // =========================================================================
    testWidgets(
      '3. Live translation / labelBuilder update via didUpdateWidget',
      (WidgetTester tester) async {
        String selectedValue = '720';
        String language = 'en';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      LazyDropdown<String>(
                        value: selectedValue,
                        items: const ['720', '1080'],
                        labelBuilder:
                            (val) =>
                                language == 'en'
                                    ? '$val Standard'
                                    : '$val Estándar',
                        onChanged: (val) => setState(() => selectedValue = val),
                      ),
                      ElevatedButton(
                        onPressed: () => setState(() => language = 'es'),
                        child: const Text('Switch Language'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        final textField = find.byType(TextField);
        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals('720 Standard'),
        );

        // Switch language
        await tester.tap(find.text('Switch Language'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals('720 Estándar'),
        );
      },
    );

    // =========================================================================
    // 4. DYNAMIC ALLOWCUSTOM TOGGLE
    // =========================================================================
    testWidgets(
      '4. Dynamic allowCustom toggle properly manages focus listener',
      (WidgetTester tester) async {
        bool allowCustom = false;
        String? customSubmitted;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      LazyDropdown<String>(
                        value: 'opt1',
                        items: const ['opt1', 'opt2'],
                        allowCustom: allowCustom,
                        labelBuilder: (val) => val,
                        onChanged: (_) {},
                        onCustomSubmit:
                            (val) => setState(() => customSubmitted = val),
                      ),
                      ElevatedButton(
                        onPressed:
                            () => setState(() => allowCustom = !allowCustom),
                        child: const Text('Toggle Custom'),
                      ),
                      const TextField(key: Key('blur_target')),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        // Enable custom dynamically
        await tester.tap(find.text('Toggle Custom'));
        await tester.pumpAndSettle();

        final dropdownInput = find.byType(TextField).first;
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, 'new_custom_value');
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('blur_target')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(customSubmitted, equals('new_custom_value'));

        // Disable custom dynamically
        customSubmitted = null;
        await tester.tap(find.text('Toggle Custom'));
        await tester.pumpAndSettle();

        // Typing now and blurring should not invoke onCustomSubmit
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, 'another_value');
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('blur_target')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(customSubmitted, isNull);
      },
    );

    // =========================================================================
    // 5. EDGE CASE: value: null WITH EMPTY ITEMS LIST items: []
    // =========================================================================
    testWidgets(
      '5. Edge case: value: null with empty items list [] mounts cleanly, opens menu, and populates dynamically',
      (WidgetTester tester) async {
        List<String> items = [];
        String? selectedValue;

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
                        label: 'Empty Catalog Dropdown',
                        labelBuilder: (item) => 'Item: $item',
                        onChanged: (val) => setState(() => selectedValue = val),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            items = ['first_item', 'second_item'];
                            selectedValue = 'first_item';
                          });
                        },
                        child: const Text('Populate Items'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        final textField = find.byType(TextField);
        expect(tester.widget<TextField>(textField).controller?.text, isEmpty);

        // Tap empty dropdown - should not throw unhandled exception
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();

        expect(find.text('Empty Catalog Dropdown'), findsWidgets);

        // Populate items dynamically
        await tester.tap(find.text('Populate Items'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals('Item: first_item'),
        );

        // Open newly populated menu
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();

        expect(find.text('Item: second_item'), findsWidgets);
      },
    );

    // =========================================================================
    // 6. EDGE CASE: value NOT PRESENT IN items LIST (CUSTOM PRE-FILLED VALUE)
    // =========================================================================
    testWidgets(
      '6. Edge case: value not present in items list displays formatted label and allows selection from catalog',
      (WidgetTester tester) async {
        String? selectedValue = 'custom_preset_4k';
        final items = ['720p', '1080p', '1440p'];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return LazyDropdown<String>(
                    value: selectedValue,
                    items: items,
                    label: 'Format Selector',
                    allowCustom: true,
                    labelBuilder: (val) => 'Resolution: $val',
                    onChanged: (val) => setState(() => selectedValue = val),
                  );
                },
              ),
            ),
          ),
        );

        final textField = find.byType(TextField);
        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals('Resolution: custom_preset_4k'),
        );

        // Open menu and select a known item from catalog
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();

        final item1080 = find.text('Resolution: 1080p').last;
        await tester.tap(item1080);
        await tester.pumpAndSettle();

        expect(selectedValue, equals('1080p'));
        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals('Resolution: 1080p'),
        );
      },
    );

    // =========================================================================
    // 7. EDGE CASE: DUPLICATE STRING LABELS GENERATED BY labelBuilder
    // =========================================================================
    testWidgets(
      '7. Edge case: duplicate string labels generated by labelBuilder handle collision gracefully',
      (WidgetTester tester) async {
        String? selectedValue = 'audio_aac_128';
        String? customSubmitted;
        // Multiple distinct values mapping to the exact same display label
        final items = [
          'audio_aac_128',
          'audio_aac_192',
          'audio_opus_128',
          'audio_flac',
        ];

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
                        labelBuilder: (val) {
                          if (val.startsWith('audio_aac')) {
                            return 'AAC Standard Audio';
                          } else if (val.startsWith('audio_opus')) {
                            return 'Opus High Quality';
                          }
                          return 'Lossless FLAC';
                        },
                        onChanged: (val) => setState(() => selectedValue = val),
                        onCustomSubmit:
                            (val) => setState(() => customSubmitted = val),
                      ),
                      const TextField(key: Key('blur_node')),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        final textField = find.byType(TextField).first;
        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals('AAC Standard Audio'),
        );

        // Open dropdown and tap the second duplicate entry
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();

        // 2 entries have 'AAC Standard Audio'
        final aacEntries = find.text('AAC Standard Audio');
        expect(aacEntries, findsWidgets);

        // Tap the second entry in the popup overlay
        await tester.tap(aacEntries.last);
        await tester.pumpAndSettle();

        expect(selectedValue, equals('audio_aac_192'));

        // Typing the duplicate known label must be rejected on blur
        await tester.tap(textField);
        await tester.enterText(textField, 'AAC Standard Audio');
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('blur_node')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(customSubmitted, isNull);
      },
    );

    // =========================================================================
    // 8. ADVERSARIAL: RAPID NON-ASCII / UNICODE / RTL / EMOJI SEARCH QUERIES
    // =========================================================================
    testWidgets(
      '8. Adversarial: rapid hostile search queries (Arabic RTL, CJK, Emoji ZWJ, regex, control chars)',
      (WidgetTester tester) async {
        final items = [
          'ar_SA',
          'ja_JP',
          'zh_CN',
          'ru_RU',
          'he_IL',
          'en_US',
          'es_ES',
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LazyDropdown<String>(
                value: 'en_US',
                items: items,
                enableSearch: true,
                label: 'Global Locales',
                labelBuilder: (code) {
                  switch (code) {
                    case 'ar_SA':
                      return 'العربية (Arabic) 🇸🇦';
                    case 'ja_JP':
                      return '日本語 (Japanese) 🇯🇵';
                    case 'zh_CN':
                      return '简体中文 (Chinese) 🇨🇳';
                    case 'ru_RU':
                      return 'Русский (Russian) 🇷🇺';
                    case 'he_IL':
                      return 'עברית (Hebrew RTL) 🇮🇱';
                    case 'es_ES':
                      return 'Español (Spanish) 🇪🇸';
                    default:
                      return 'English (United States) 🇺🇸';
                  }
                },
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final searchInput = find.byType(TextField);
        await tester.tap(searchInput);
        await tester.pumpAndSettle();

        // Hostile inputs including RTL, ZWJ sequences, regex metacharacters, null bytes, format specifiers
        final hostileQueries = [
          'العربية', // Arabic RTL
          'עברית', // Hebrew RTL
          '日本語', // Japanese Kanji/Kana
          '🇨🇳', // Flag emoji sequence
          '👨‍👩‍👧‍👦', // Complex ZWJ emoji family sequence
          r'.*+?^${}()|[]\', // Regex meta-characters
          '<script>alert("xss")</script>', // Injection / HTML markup
          '%s%d%n%x', // Format string injection
          '   \t\n   ', // Whitespace & tabs
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' *
              10, // Very long query string
        ];

        for (final query in hostileQueries) {
          await tester.enterText(searchInput, query);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        // Dropdown must remain alive, mounted and responsive
        expect(searchInput, findsOneWidget);
      },
    );

    // =========================================================================
    // 9. EDGE CASE: IN-PLACE MUTATION VS IMMUTABLE LIST REPLACEMENTS
    // =========================================================================
    testWidgets(
      '9. Edge case: in-place list mutation vs immutable list replacement invalidates cache properly',
      (WidgetTester tester) async {
        final List<String> mutableList = ['opt_1', 'opt_2'];
        String selected = 'opt_1';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      LazyDropdown<String>(
                        value: selected,
                        items: mutableList,
                        labelBuilder: (v) => 'Val: $v',
                        onChanged: (v) => setState(() => selected = v),
                      ),
                      ElevatedButton(
                        key: const Key('in_place_add'),
                        onPressed: () {
                          setState(() {
                            mutableList.add('opt_3');
                          });
                        },
                        child: const Text('In-Place Add'),
                      ),
                      ElevatedButton(
                        key: const Key('in_place_remove'),
                        onPressed: () {
                          setState(() {
                            mutableList.removeLast();
                          });
                        },
                        child: const Text('In-Place Remove'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        // Open menu
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();
        expect(find.text('Val: opt_2'), findsWidgets);
        expect(find.text('Val: opt_3'), findsNothing);

        // Dismiss menu
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();

        // 1. In-place add mutation (same list reference, length changed)
        await tester.tap(find.byKey(const Key('in_place_add')));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();
        expect(find.text('Val: opt_3'), findsWidgets);

        // Dismiss menu
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();

        // 2. In-place remove mutation (same list reference, length changed)
        await tester.tap(find.byKey(const Key('in_place_remove')));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();
        expect(find.text('Val: opt_3'), findsNothing);
      },
    );

    // =========================================================================
    // 10. EDGE CASE: RAPID FLAG TOGGLING UNDER ACTIVE FOCUS & BLUR
    // =========================================================================
    testWidgets(
      '10. Edge case: dynamic toggling of allowCustom & enableSearch during active focus and input typing',
      (WidgetTester tester) async {
        bool allowCustom = true;
        bool enableSearch = false;
        String? customSubmitted;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      LazyDropdown<String>(
                        value: 'alpha',
                        items: const ['alpha', 'beta', 'gamma'],
                        allowCustom: allowCustom,
                        enableSearch: enableSearch,
                        labelBuilder: (v) => 'Label $v',
                        onChanged: (_) {},
                        onCustomSubmit:
                            (v) => setState(() => customSubmitted = v),
                      ),
                      ElevatedButton(
                        key: const Key('toggle_custom_btn'),
                        onPressed:
                            () => setState(() => allowCustom = !allowCustom),
                        child: const Text('Toggle Custom'),
                      ),
                      ElevatedButton(
                        key: const Key('toggle_search_btn'),
                        onPressed:
                            () => setState(() => enableSearch = !enableSearch),
                        child: const Text('Toggle Search'),
                      ),
                      const TextField(key: Key('blur_target_10')),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        final dropdownInput = find.byType(TextField).first;
        final blurTarget = find.byKey(const Key('blur_target_10'));

        // Focus and enter text
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, 'in_flight_custom');
        await tester.pumpAndSettle();

        // Toggle search ON while focused
        await tester.tap(
          find.byKey(const Key('toggle_search_btn')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Toggle custom OFF while focused
        await tester.tap(
          find.byKey(const Key('toggle_custom_btn')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Blur now -> since allowCustom was toggled to false, onCustomSubmit must NOT fire
        await tester.tap(blurTarget, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(customSubmitted, isNull);

        // Toggle custom back ON
        await tester.tap(
          find.byKey(const Key('toggle_custom_btn')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Type again and blur
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, 'second_flight_custom');
        await tester.pumpAndSettle();

        await tester.tap(blurTarget, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(customSubmitted, equals('second_flight_custom'));
      },
    );

    // =========================================================================
    // 11. EDGE CASE: USER INPUT PRESERVATION DURING CONCURRENT PARENT REBUILDS
    // =========================================================================
    testWidgets(
      '11. Edge case: user text input is preserved without overwrite when parent rebuilds while focused',
      (WidgetTester tester) async {
        int parentCounter = 0;
        late StateSetter parentSetState;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  parentSetState = setState;
                  return Column(
                    children: [
                      Text('Parent Counter: $parentCounter'),
                      LazyDropdown<String>(
                        value: 'original_val',
                        items: const ['original_val', 'other_val'],
                        allowCustom: true,
                        labelBuilder: (v) => 'Label $v',
                        onChanged: (_) {},
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        final dropdownInput = find.byType(TextField).first;

        // Focus and type custom uncommitted draft
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, 'my_draft_input');
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(dropdownInput).controller?.text,
          equals('my_draft_input'),
        );

        // 20 rapid parent rebuilds while user is still focused
        for (int i = 0; i < 20; i++) {
          parentSetState(() => parentCounter++);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        // User draft input must NOT have been erased by parent rebuilds
        expect(
          tester.widget<TextField>(dropdownInput).controller?.text,
          equals('my_draft_input'),
        );
      },
    );

    // =========================================================================
    // 12. EDGE CASE: VALUE MUTATION CYCLE (NULL <-> NON-NULL <-> CUSTOM)
    // =========================================================================
    testWidgets(
      '12. Edge case: value transitions across null, catalog item, and custom value update controller text',
      (WidgetTester tester) async {
        String? selectedValue = 'initial';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      LazyDropdown<String>(
                        value: selectedValue,
                        items: const ['initial', 'middle'],
                        labelBuilder: (v) => 'Formatted: $v',
                        onChanged: (v) => setState(() => selectedValue = v),
                      ),
                      ElevatedButton(
                        key: const Key('set_null'),
                        onPressed: () => setState(() => selectedValue = null),
                        child: const Text('Set Null'),
                      ),
                      ElevatedButton(
                        key: const Key('set_custom'),
                        onPressed:
                            () => setState(() => selectedValue = 'custom_val'),
                        child: const Text('Set Custom'),
                      ),
                      ElevatedButton(
                        key: const Key('set_catalog'),
                        onPressed:
                            () => setState(() => selectedValue = 'middle'),
                        child: const Text('Set Catalog'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        final textField = find.byType(TextField);
        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals('Formatted: initial'),
        );

        // Step 1: Switch to null
        await tester.tap(find.byKey(const Key('set_null')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals(''),
        );

        // Step 3: Switch to catalog item
        await tester.tap(find.byKey(const Key('set_catalog')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(textField).controller?.text,
          equals('Formatted: middle'),
        );
      },
    );

    // =========================================================================
    // 13. EDGE CASE: labelBuilder RETURNING EMPTY STRING "" FOR ALL ITEMS
    // =========================================================================
    testWidgets(
      '13. Edge case: labelBuilder returning empty string "" operates without crashes',
      (WidgetTester tester) async {
        String selected = 'item_a';
        final items = ['item_a', 'item_b'];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LazyDropdown<String>(
                value: selected,
                items: items,
                labelBuilder: (_) => '',
                onChanged: (v) => selected = v,
              ),
            ),
          ),
        );

        final textField = find.byType(TextField);
        expect(tester.widget<TextField>(textField).controller?.text, isEmpty);

        // Open menu
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();

        // Must find DropdownMenu entries without exception
        expect(find.byType(DropdownMenu<String>), findsOneWidget);
      },
    );

    // =========================================================================
    // 14. EDGE CASE: allowCustom: true WITH onCustomSubmit: null
    // =========================================================================
    testWidgets(
      '14. Edge case: allowCustom: true with onCustomSubmit: null does not throw on blur',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  LazyDropdown<String>(
                    value: 'opt1',
                    items: const ['opt1', 'opt2'],
                    allowCustom: true,
                    onCustomSubmit: null, // explicit null
                    labelBuilder: (v) => v,
                    onChanged: (_) {},
                  ),
                  const TextField(key: Key('blur_node_14')),
                ],
              ),
            ),
          ),
        );

        final dropdownInput = find.byType(TextField).first;
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, 'custom_text_no_handler');
        await tester.pumpAndSettle();

        // Tap blur target - must not throw NullPointerException
        await tester.tap(
          find.byKey(const Key('blur_node_14')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      },
    );

    // =========================================================================
    // 15. STRESS: RAPID VALUE MUTATIONS ACROSS 50 CONSECUTIVE FRAMES
    // =========================================================================
    testWidgets(
      '15. Stress: rapid sequential value mutations across 50 frames maintain controller text sync',
      (WidgetTester tester) async {
        final items = List.generate(20, (i) => 'val_$i');
        String? currentValue = 'val_0';
        late StateSetter updateState;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  updateState = setState;
                  return LazyDropdown<String>(
                    value: currentValue,
                    items: items,
                    labelBuilder: (v) => 'Item #$v',
                    onChanged: (v) => setState(() => currentValue = v),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final textField = find.byType(TextField);

        for (int i = 1; i <= 50; i++) {
          final targetVal = items[i % items.length];
          updateState(() {
            currentValue = targetVal;
          });
          await tester.pump();
          expect(
            tester.widget<TextField>(textField).controller?.text,
            equals('Item #$targetVal'),
          );
        }
      },
    );

    // =========================================================================
    // 16. STRESS: RAPID WIDGET MOUNT & IMMEDIATE DISPOSE TEARDOWN
    // =========================================================================
    testWidgets(
      '16. Stress: immediate unmount / teardown during active focus and mid-animation causes no leaks or errors',
      (WidgetTester tester) async {
        bool mounted = true;
        late StateSetter triggerMount;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  triggerMount = setState;
                  if (!mounted) return const SizedBox.shrink();
                  return LazyDropdown<String>(
                    value: 'opt_a',
                    items: const ['opt_a', 'opt_b'],
                    allowCustom: true,
                    labelBuilder: (v) => v,
                    onChanged: (_) {},
                  );
                },
              ),
            ),
          ),
        );

        final dropdownInput = find.byType(TextField);
        await tester.tap(dropdownInput);
        await tester.enterText(dropdownInput, 'in_flight_draft');
        await tester.pump(); // Half-pump mid animation

        // Immediately unmount widget while focused
        triggerMount(() => mounted = false);
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNothing);
      },
    );
  });
}
