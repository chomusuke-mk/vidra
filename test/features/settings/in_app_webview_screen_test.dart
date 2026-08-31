import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/settings/presentation/widgets/in_app_webview_screen.dart';

void main() {
  group('InAppWebViewScreen URL Normalization', () {
    test('normalizes empty input to https://google.com', () {
      expect(InAppWebViewScreen.normalizeUrl(''), equals('https://google.com'));
      expect(InAppWebViewScreen.normalizeUrl('   '), equals('https://google.com'));
    });

    test('prepends https:// to domain strings missing scheme', () {
      expect(
        InAppWebViewScreen.normalizeUrl('youtube.com'),
        equals('https://youtube.com'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('sub.example.org/path?q=1'),
        equals('https://sub.example.org/path?q=1'),
      );
    });

    test('preserves existing schemes intact', () {
      expect(
        InAppWebViewScreen.normalizeUrl('http://insecure.site'),
        equals('http://insecure.site'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('https://secure.site'),
        equals('https://secure.site'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('custom-scheme://host'),
        equals('custom-scheme://host'),
      );
    });
  });

  group('InAppWebViewScreen UI Elements', () {
    testWidgets('renders top bar with address bar, controls and shortcuts footer',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InAppWebViewScreen(
            initialUrl: 'https://youtube.com',
            webView: SizedBox(key: Key('mock_webview')),
          ),
        ),
      );

      // Verify Close button
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Verify TextField exists with normalized initial URL in AppBar
      final textFieldFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextField),
      );
      expect(textFieldFinder, findsOneWidget);
      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.controller?.text, equals('https://youtube.com'));

      // Verify Navigation controls
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsNWidgets(2)); // 1 in actions, 1 as Go button in address bar
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // Verify Shortcuts menu
      expect(find.text('Shortcuts'), findsWidgets);

      // Verify manual Save Cookies button is removed (automatic capture)
      expect(find.text('Save Cookies'), findsNothing);
      expect(find.text('Capture'), findsNothing);

      // Verify Body
      expect(find.byKey(const Key('mock_webview')), findsOneWidget);
    });

    testWidgets('allows entering custom URL into address bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InAppWebViewScreen(
            initialUrl: 'https://google.com',
            webView: SizedBox(key: Key('mock_webview')),
          ),
        ),
      );

      final textFieldFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextField),
      );
      await tester.enterText(textFieldFinder, 'vimeo.com/watch');
      await tester.pump();

      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.controller?.text, equals('vimeo.com/watch'));
    });

    testWidgets('close button pops the route', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => InAppWebViewScreen.show(
                context,
                webView: const SizedBox(key: Key('mock_webview')),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      // Open the screen
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(InAppWebViewScreen), findsOneWidget);

      // Tap close
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(InAppWebViewScreen), findsNothing);
    });
  });
}
