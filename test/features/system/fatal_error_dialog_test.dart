import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/system/presentation/fatal_error_dialog.dart';

void main() {
  group('FatalErrorDialog', () {
    testWidgets('renders FatalErrorDialog with default fallback strings and icon', (
      WidgetTester tester,
    ) async {
      bool restarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FatalErrorDialog(
              onRestart: () {
                restarted = true;
              },
            ),
          ),
        ),
      );

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Fatal System Error'), findsOneWidget);
      expect(
        find.text(
          'The download engine failed to load after an update. Please restart the application.',
        ),
        findsOneWidget,
      );
      expect(find.text('Restart Application'), findsOneWidget);

      // Verify PopScope cannot pop
      final popScopeFinder = find.byType(PopScope);
      expect(popScopeFinder, findsOneWidget);
      final popScope = tester.widget<PopScope>(popScopeFinder);
      expect(popScope.canPop, isFalse);

      // Tap restart button
      await tester.tap(find.text('Restart Application'));
      await tester.pumpAndSettle();

      expect(restarted, isTrue);
    });

    testWidgets('FatalErrorDialog.show opens non-dismissible dialog', (
      WidgetTester tester,
    ) async {
      bool restarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => FatalErrorDialog.show(
                  context,
                  () => restarted = true,
                ),
                child: const Text('Trigger Fatal Error'),
              ),
            ),
          ),
        ),
      );

      // Tap to trigger dialog
      await tester.tap(find.text('Trigger Fatal Error'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Fatal System Error'), findsOneWidget);

      // Tapping outside barrier does not dismiss because barrierDismissible is false
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Tapping Restart invokes onRestart
      await tester.tap(find.text('Restart Application'));
      await tester.pumpAndSettle();
      expect(restarted, isTrue);
    });
  });
}
