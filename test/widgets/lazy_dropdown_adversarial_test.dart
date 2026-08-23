import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';

void main() {
  group('Adversarial & Interaction Tests: LazyDropdown', () {
    testWidgets('1. Item selection updates controller text and triggers onChanged callback', (
      WidgetTester tester,
    ) async {
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
      expect(tester.widget<TextField>(textField).controller?.text, equals('1080p HD'));

      // Open Dropdown
      await tester.tap(find.byType(DropdownMenu<String>));
      await tester.pumpAndSettle();

      // Tap '2160p HD' in dropdown menu entries
      final entry2160 = find.text('2160p HD').last;
      await tester.tap(entry2160);
      await tester.pumpAndSettle();

      expect(selectedValue, equals('2160'));
      expect(tester.widget<TextField>(textField).controller?.text, equals('2160p HD'));
    });

    testWidgets('2. Custom submit triggers on blur only when text is non-empty and not a known label', (
      WidgetTester tester,
    ) async {
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
                      labelBuilder: (val) => val == 'bestvideo' ? 'Best Available' : '${val}p',
                      onChanged: (val) => setState(() => selectedValue = val),
                      onCustomSubmit: (val) => setState(() => customSubmitted = val),
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
    });

    testWidgets('3. Live translation / labelBuilder update via didUpdateWidget', (
      WidgetTester tester,
    ) async {
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
                      labelBuilder: (val) => language == 'en' ? '$val Standard' : '$val Estándar',
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
      expect(tester.widget<TextField>(textField).controller?.text, equals('720 Standard'));

      // Switch language
      await tester.tap(find.text('Switch Language'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(textField).controller?.text, equals('720 Estándar'));
    });

    testWidgets('4. Dynamic allowCustom toggle properly manages focus listener', (
      WidgetTester tester,
    ) async {
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
                      onCustomSubmit: (val) => setState(() => customSubmitted = val),
                    ),
                    ElevatedButton(
                      onPressed: () => setState(() => allowCustom = !allowCustom),
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

      await tester.tap(find.byKey(const Key('blur_target')), warnIfMissed: false);
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

      await tester.tap(find.byKey(const Key('blur_target')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(customSubmitted, isNull);
    });
  });
}
