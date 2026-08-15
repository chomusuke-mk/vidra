import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/system/presentation/fatal_error_dialog.dart';

class LocalFileLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final raw = file.readAsStringSync();
    final decoded = jsonc.decode(raw) as Map;
    return decoded.cast<String, dynamic>().map((k, v) => MapEntry(k, v.toString()));
  }
}

void main() {
  group('FatalErrorDialog Stress & Adversarial Tests', () {
    testWidgets('renders FatalErrorDialog with default fallback strings, icon, and disabled PopScope', (
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

      // Verify AlertDialog and Error Icon presence
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, equals(Colors.red));
      expect(icon.size, equals(48.0));

      // Verify exact default text presence
      expect(find.text('Fatal System Error'), findsOneWidget);
      expect(
        find.text(
          'The download engine failed to load after an update. Please restart the application.',
        ),
        findsOneWidget,
      );
      expect(find.text('Restart Application'), findsOneWidget);

      // Verify PopScope blocks popping
      final popScopeFinder = find.byType(PopScope);
      expect(popScopeFinder, findsOneWidget);
      final popScope = tester.widget<PopScope>(popScopeFinder);
      expect(popScope.canPop, isFalse);

      // Tap restart button and verify callback execution
      await tester.tap(find.text('Restart Application'));
      await tester.pumpAndSettle();

      expect(restarted, isTrue);
    });

    testWidgets('PopScope and barrierDismissible prevent back-button and outside taps from dismissing dialog', (
      WidgetTester tester,
    ) async {
      late BuildContext dialogContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => FatalErrorDialog.show(
                    context,
                    () {
                      // Custom restart callback that dismisses dialog for test cleanup
                      Navigator.of(dialogContext, rootNavigator: true).pop();
                    },
                  ),
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      dialogContext = tester.element(find.byType(AlertDialog));

      // PopScope canPop is false
      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);

      // 1. Attempt to pop route via Navigator.maybePop (simulates system back event)
      await Navigator.of(dialogContext).maybePop();
      await tester.pumpAndSettle();

      // Dialog MUST still be mounted and visible
      expect(find.byType(AlertDialog), findsOneWidget);

      // 2. Attempt tapping outside barrier
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tapAt(const Offset(795, 5));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // 3. Tapping restart button invokes callback and cleans up
      await tester.tap(find.text('Restart Application'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Integrates with LocaleController to display localized strings (Spanish)', (
      WidgetTester tester,
    ) async {
      final mockRepo = LocalFileLocaleRepository();
      final localeController = LocaleController(mockRepo, 'es');
      await localeController.whenReady;

      await tester.pumpWidget(
        ChangeNotifierProvider<LocaleController>.value(
          value: localeController,
          child: MaterialApp(
            home: Scaffold(
              body: FatalErrorDialog(
                onRestart: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Error fatal del sistema'), findsOneWidget);
      expect(
        find.text(
          'El motor de descargas no pudo cargarse tras la actualización. Por favor, reinicia la aplicación.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reiniciar aplicación'), findsOneWidget);
    });

    testWidgets('Re-entrancy protection: multiple show() calls do not spawn duplicate dialogs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    // Fire two show calls in immediate succession
                    FatalErrorDialog.show(
                      context,
                      () => Navigator.of(context, rootNavigator: true).pop(),
                    );
                    FatalErrorDialog.show(
                      context,
                      () => Navigator.of(context, rootNavigator: true).pop(),
                    );
                  },
                  child: const Text('Double Show'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Double Show'));
      await tester.pumpAndSettle();

      // Exactly ONE AlertDialog should be present
      expect(find.byType(AlertDialog), findsOneWidget);

      // Clean up dialog
      await tester.tap(find.text('Restart Application'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
