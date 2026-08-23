import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';

void main() {
  testWidgets('LazyDropdown renders items with labelBuilder and notifies onChanged upon selection', (
    WidgetTester tester,
  ) async {
    String selectedValue = 'item1';
    final items = ['item1', 'item2', 'item3'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return LazyDropdown<String>(
                value: selectedValue,
                items: items,
                label: 'Test Dropdown',
                labelBuilder: (item) => 'Label: $item',
                onChanged: (val) => setState(() => selectedValue = val),
              );
            },
          ),
        ),
      ),
    );

    final dropdownField = find.byType(TextField);
    expect(tester.widget<TextField>(dropdownField).controller?.text, 'Label: item1');

    // Open dropdown menu
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();

    // Select second item from overlay menu
    final item2 = find.text('Label: item2').last;
    await tester.tap(item2);
    await tester.pumpAndSettle();

    expect(selectedValue, 'item2');
    expect(tester.widget<TextField>(dropdownField).controller?.text, 'Label: item2');
  });

  testWidgets('LazyDropdown didUpdateWidget updates displayed text when external value/translation changes', (
    WidgetTester tester,
  ) async {
    String selectedValue = 'optA';
    String prefix = 'EN';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  LazyDropdown<String>(
                    value: selectedValue,
                    items: const ['optA', 'optB'],
                    labelBuilder: (val) => '$prefix: $val',
                    onChanged: (val) => setState(() => selectedValue = val),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => prefix = 'ES'),
                    child: const Text('Change Language'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    final dropdownField = find.byType(TextField);
    expect(tester.widget<TextField>(dropdownField).controller?.text, 'EN: optA');

    await tester.tap(find.text('Change Language'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(dropdownField).controller?.text, 'ES: optA');
  });

  testWidgets('LazyDropdown allowCustom submits custom text on focus loss', (
    WidgetTester tester,
  ) async {
    String? customSubmitted;
    String selectedValue = 'default';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  LazyDropdown<String>(
                    value: selectedValue,
                    items: const ['default', 'option1'],
                    allowCustom: true,
                    labelBuilder: (val) => val.toUpperCase(),
                    onChanged: (val) => setState(() => selectedValue = val),
                    onCustomSubmit: (val) => setState(() => customSubmitted = val),
                  ),
                  const TextField(key: Key('other_field')),
                ],
              );
            },
          ),
        ),
      ),
    );

    final dropdownField = find.byType(TextField).first;
    await tester.tap(dropdownField);
    await tester.enterText(dropdownField, 'my_custom_resolution');
    await tester.pumpAndSettle();

    // Tap other field to blur
    await tester.tap(find.byKey(const Key('other_field')));
    await tester.pumpAndSettle();

    expect(customSubmitted, 'my_custom_resolution');
  });
}
