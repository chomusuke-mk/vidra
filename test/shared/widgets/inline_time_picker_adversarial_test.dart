import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/shared/widgets/inline_time_picker.dart';

void main() {
  group('Adversarial & Stress Tests: InlineTimePicker Widget', () {
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

    testWidgets('1. Rapid sequential typing across fields with auto-focus progression', (tester) async {
      int? lastReportedSeconds;
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 0,
        onChanged: (val) => lastReportedSeconds = val,
      ));

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(3));

      // Focus hours field
      await tester.tap(textFields.at(0));
      await tester.pump();

      // Enter '10' into hours -> should auto-advance to minutes
      await tester.enterText(textFields.at(0), '10');
      await tester.pump();
      expect(lastReportedSeconds, equals(10 * 3600));

      // Enter '30' into minutes -> should auto-advance to seconds
      await tester.enterText(textFields.at(1), '30');
      await tester.pump();
      expect(lastReportedSeconds, equals(10 * 3600 + 30 * 60));

      // Enter '45' into seconds -> should unfocus
      await tester.enterText(textFields.at(2), '45');
      await tester.pump();
      expect(lastReportedSeconds, equals(10 * 3600 + 30 * 60 + 45));
    });

    testWidgets('2. Out-of-bounds input values clamping on blur and auto-clamping on 2 digits', (tester) async {
      int? lastReportedSeconds;
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 0,
        onChanged: (val) => lastReportedSeconds = val,
      ));

      final textFields = find.byType(TextField);

      // Focus minutes field
      await tester.tap(textFields.at(1));
      await tester.pump();

      // In minutes, typing '99' should immediately clamp to '59' because maxVal is 59
      await tester.enterText(textFields.at(1), '99');
      await tester.pump();

      expect(lastReportedSeconds, equals(59 * 60));
      expect(find.text('59'), findsOneWidget);

      // In seconds, typing '88' should clamp to '59'
      await tester.enterText(textFields.at(2), '88');
      await tester.pump();

      expect(lastReportedSeconds, equals(59 * 60 + 59));
      expect(find.text('59'), findsNWidgets(2));
    });

    testWidgets('3. Backspacing to empty text and single digit behavior with blur formatting', (tester) async {
      int? lastReportedSeconds;
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 3665, // 01:01:05
        onChanged: (val) => lastReportedSeconds = val,
      ));

      final textFields = find.byType(TextField);

      // Focus hours field
      await tester.tap(textFields.at(0));
      await tester.pump();

      // Clear hours text completely
      await tester.enterText(textFields.at(0), '');
      await tester.pump();

      // Invariant: Empty text is treated as 0 without throwing FormatException
      expect(lastReportedSeconds, equals(1 * 60 + 5));

      // Blur hours field by moving focus to minutes
      await tester.tap(textFields.at(1));
      await tester.pump();

      // Clamping/formatting on blur should restore '00' in hours
      expect(find.text('00'), findsOneWidget);

      // Focus hours and enter a single digit '7' (length == 1, no auto-focus yet)
      await tester.tap(textFields.at(0));
      await tester.pump();
      await tester.enterText(textFields.at(0), '7');
      await tester.pump();
      expect(lastReportedSeconds, equals(7 * 3600 + 1 * 60 + 5));

      // Blur hours field by unfocusing
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('07'), findsOneWidget);
    });

    testWidgets('4. Boundary extreme initialSeconds values (negative, zero, max allowed)', (tester) async {
      // Test negative initialSeconds
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: -9999,
        onChanged: (_) {},
      ));

      // Negative seconds are clamped to 00:00:00
      expect(find.text('00'), findsNWidgets(3));

      // Test max boundary initialSeconds (99 hours, 59 minutes, 59 seconds = 359999)
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 359999,
        onChanged: (_) {},
      ));

      expect(find.text('99'), findsOneWidget);
      expect(find.text('59'), findsNWidgets(2));

      // Test beyond max (e.g. 10,000,000 seconds -> clamped to 99h 59m 59s)
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 10000000,
        onChanged: (_) {},
      ));

      expect(find.text('99'), findsOneWidget);
    });

    testWidgets('5. Focus retention: External update does NOT overwrite while user is typing', (tester) async {
      int seconds = 100;
      late StateSetter stateSetter;

      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) {
          stateSetter = setState;
          return MaterialApp(
            home: Scaffold(
              body: InlineTimePicker(
                initialSeconds: seconds,
                onChanged: (_) {},
              ),
            ),
          );
        },
      ));

      final textFields = find.byType(TextField);

      // Focus hours field
      await tester.tap(textFields.at(0));
      await tester.pump();

      // Type '12'
      await tester.enterText(textFields.at(0), '12');
      await tester.pump();

      // Trigger external parent rebuild with new initialSeconds while hours/minutes are active
      stateSetter(() => seconds = 5000);
      await tester.pump();

      // Hours should still be '12' (not clobbered by external didUpdateWidget)
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('6. All inputs disabled when enabled = false', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        initialSeconds: 7200,
        onChanged: (_) {},
        enabled: false,
      ));

      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      for (final tf in textFields) {
        expect(tf.enabled, isFalse);
      }

      final inputDecorators = tester.widgetList<InputDecorator>(find.byType(InputDecorator));
      expect(inputDecorators.first.decoration.enabled, isFalse);
    });
  });
}
