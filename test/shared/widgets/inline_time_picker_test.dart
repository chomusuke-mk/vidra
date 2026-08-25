import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/shared/widgets/inline_time_picker.dart';

void main() {
  group('InlineTimePicker Widget Tests', () {
    Widget buildTestWidget({
      int initialSeconds = 0,
      required ValueChanged<int> onChanged,
      String? label,
      bool enabled = true,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: InlineTimePicker(
              initialSeconds: initialSeconds,
              onChanged: onChanged,
              label: label,
              enabled: enabled,
            ),
          ),
        ),
      );
    }

    testWidgets('renders initial time of 0 seconds formatted as 00:00:00', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 0,
        onChanged: (_) {},
        label: 'Start Time',
      ));

      expect(find.text('Start Time'), findsOneWidget);
      expect(find.text('00'), findsNWidgets(3));
      expect(find.text(':'), findsNWidgets(2));
      expect(find.text('HH'), findsOneWidget);
      expect(find.text('MM'), findsOneWidget);
      expect(find.text('SS'), findsOneWidget);
    });

    testWidgets('renders non-zero initial seconds correctly decomposed (e.g. 3665s = 01:01:05)', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 3665,
        onChanged: (_) {},
      ));

      expect(find.text('01'), findsNWidgets(2));
      expect(find.text('05'), findsOneWidget);
    });

    testWidgets('entering 2 digits triggers onChanged and auto-focuses next field', (tester) async {
      int? reportedSeconds;
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 0,
        onChanged: (val) => reportedSeconds = val,
      ));

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(3));

      // Enter hours: '02'
      await tester.enterText(textFields.at(0), '02');
      await tester.pump();

      expect(reportedSeconds, equals(7200));

      // Enter minutes: '15'
      await tester.enterText(textFields.at(1), '15');
      await tester.pump();

      expect(reportedSeconds, equals(7200 + (15 * 60)));

      // Enter seconds: '30'
      await tester.enterText(textFields.at(2), '30');
      await tester.pump();

      expect(reportedSeconds, equals(7200 + (15 * 60) + 30));
    });

    testWidgets('clamping on focus lost (minutes > 59 clamps to 59)', (tester) async {
      int? reportedSeconds;
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 0,
        onChanged: (val) => reportedSeconds = val,
      ));

      final textFields = find.byType(TextField);

      // Focus minutes and enter 75
      await tester.tap(textFields.at(1));
      await tester.pump();
      await tester.enterText(textFields.at(1), '75');
      await tester.pump();

      // Tap elsewhere to lose focus
      await tester.tap(find.byType(Scaffold));
      await tester.pump();

      expect(reportedSeconds, equals(59 * 60));
      expect(find.text('59'), findsOneWidget);
    });

    testWidgets('focusing a field selects its entire text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 3665,
        onChanged: (_) {},
      ));

      final textFields = find.byType(TextField);
      await tester.tap(textFields.at(0));
      await tester.pump();

      final editableText = tester.widget<EditableText>(find.descendant(
        of: textFields.at(0),
        matching: find.byType(EditableText),
      ));

      expect(editableText.controller.selection.baseOffset, equals(0));
      expect(editableText.controller.selection.extentOffset, equals(2));
    });

    testWidgets('updates controllers when initialSeconds changes externally', (tester) async {
      int seconds = 100;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  InlineTimePicker(
                    initialSeconds: seconds,
                    onChanged: (_) {},
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => seconds = 7200),
                    child: const Text('Update'),
                  ),
                ],
              ),
            ),
          );
        },
      ));

      expect(find.text('01'), findsOneWidget); // 1 minute
      expect(find.text('40'), findsOneWidget); // 40 seconds

      await tester.tap(find.text('Update'));
      await tester.pump();

      expect(find.text('02'), findsOneWidget); // 2 hours
      expect(find.text('00'), findsNWidgets(2)); // 0 min, 0 sec
    });

    testWidgets('respects enabled = false', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 0,
        onChanged: (_) {},
        enabled: false,
      ));

      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      for (final tf in textFields) {
        expect(tf.enabled, isFalse);
      }
    });
  });
}
