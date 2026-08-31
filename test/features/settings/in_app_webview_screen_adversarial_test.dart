import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/presentation/widgets/in_app_webview_screen.dart';

class MockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  MockLocaleRepository() {
    for (final code in ['en', 'es']) {
      final f = File('i18n/$code.jsonc');
      if (f.existsSync()) {
        final raw = f.readAsStringSync();
        final map = (jsonc.decode(raw) as Map).cast<String, dynamic>().map(
          (k, v) => MapEntry(k, v.toString().trim()),
        );
        map.removeWhere((k, v) => v.trim().isEmpty);
        _storage[code] = map;
      }
    }
  }

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    return _storage[localeCode] ?? {};
  }
}

void main() {
  late MockLocaleRepository mockLocaleRepo;
  late LocaleController localeController;
  late Directory tempDir;

  setUp(() async {
    mockLocaleRepo = MockLocaleRepository();
    localeController = LocaleController(mockLocaleRepo, 'en');
    await localeController.whenReady;
    tempDir = await Directory.systemTemp.createTemp('vidra_webview_adv_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildTestApp(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('InAppWebViewScreen Adversarial URL Normalization', () {
    test('Whitespace and newline inputs all resolve to fallback Brave search URL', () {
      expect(
        InAppWebViewScreen.normalizeUrl(''),
        equals('https://search.brave.com/search?q='),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('   '),
        equals('https://search.brave.com/search?q='),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('\t\r\n  '),
        equals('https://search.brave.com/search?q='),
      );
    });

    test('Complex URLs without scheme are properly prefixed with https://', () {
      expect(
        InAppWebViewScreen.normalizeUrl('vidra.app:443/download?v=1#readme'),
        equals('https://vidra.app:443/download?v=1#readme'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('sub.domain.co.uk/path/to/resource?q=test&page=2'),
        equals('https://sub.domain.co.uk/path/to/resource?q=test&page=2'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('127.0.0.1:8080/api/v1'),
        equals('https://127.0.0.1:8080/api/v1'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('192.168.1.1'),
        equals('https://192.168.1.1'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('[::1]:8000/status'),
        equals('https://[::1]:8000/status'),
      );
    });

    test('Unicode and internationalized query paths preserve characters', () {
      expect(
        InAppWebViewScreen.normalizeUrl('sitio.es/música?género=clásica&filtro=año'),
        equals('https://sitio.es/música?género=clásica&filtro=año'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('https://example.com/search?q=🍪'),
        equals('https://example.com/search?q=🍪'),
      );
    });

    test('Standard and custom network schemes with :// are preserved', () {
      expect(
        InAppWebViewScreen.normalizeUrl('http://insecure-site.com'),
        equals('http://insecure-site.com'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('https://secure-site.com'),
        equals('https://secure-site.com'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('ftp://ftp.example.com/files'),
        equals('ftp://ftp.example.com/files'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('ws://websocket.org/socket'),
        equals('ws://websocket.org/socket'),
      );
      expect(
        InAppWebViewScreen.normalizeUrl('custom-auth://login/callback?code=123'),
        equals('custom-auth://login/callback?code=123'),
      );
    });
  });

  group('InAppWebViewScreen Adversarial Widget & Interaction Matrix', () {
    testWidgets('Renders all controls with correct icons, tooltips, and default state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          InAppWebViewScreen(
            url: 'https://youtube.com',
            saveCookiesPath: tempDir.path,
          ),
        ),
      );

      // Close button
      final closeButtonFinder = find.byIcon(Icons.close);
      expect(closeButtonFinder, findsOneWidget);

      // Address bar TextField
      final textFieldFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextField),
      );
      expect(textFieldFinder, findsOneWidget);
      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.controller?.text, equals('https://youtube.com'));

      // Navigation Action Buttons
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsNWidgets(2)); // 1 in actions, 1 as Go button in address bar
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // Back and forward should initially be disabled (null onPressed)
      final backIconButton = tester.widget<IconButton>(find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == localeController.localeStrings.wvBack,
      ));
      expect(backIconButton.onPressed, isNull);

      final forwardIconButton = tester.widget<IconButton>(find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == localeController.localeStrings.wvForward,
      ));
      expect(forwardIconButton.onPressed, isNull);

      // Verify Shortcuts menu exists
      expect(find.text('Shortcuts'), findsWidgets);

      // Verify manual Save Cookies button is removed (automatic capture)
      expect(find.text('Save Cookies'), findsNothing);
      expect(find.text('Capture'), findsNothing);
    });

    testWidgets('Entering text and tapping Go button updates TextField with normalized URL',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          InAppWebViewScreen(
            url: 'https://search.brave.com/search?q=',
            saveCookiesPath: tempDir.path,
          ),
        ),
      );

      final textFieldFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextField),
      );
      await tester.enterText(textFieldFinder, 'vimeo.com/categories');
      await tester.pump();

      // Tap the Go button
      final goButtonFinder = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == localeController.localeStrings.wvGo,
      );
      await tester.tap(goButtonFinder);
      await tester.pump();

      final updatedTextField = tester.widget<TextField>(textFieldFinder);
      expect(updatedTextField.controller?.text, equals('https://vimeo.com/categories'));
    });

    testWidgets('Submitting URL via keyboard onSubmitted updates TextField with normalized URL',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          InAppWebViewScreen(
            url: 'https://search.brave.com/search?q=',
            saveCookiesPath: tempDir.path,
          ),
        ),
      );

      final textFieldFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextField),
      );
      await tester.enterText(textFieldFinder, 'dailymotion.com');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();

      final updatedTextField = tester.widget<TextField>(textFieldFinder);
      expect(updatedTextField.controller?.text, equals('https://dailymotion.com'));
    });

    testWidgets('show() helper opens dialog fullscreen and pops upon close action',
        (WidgetTester tester) async {
      String? returnedResult = 'initial_non_null';

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returnedResult = await InAppWebViewScreen.show(
                  context,
                  tempDir.path,
                  url: 'https://reddit.com',
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      // Tap open
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(InAppWebViewScreen), findsOneWidget);
      final textField = tester.widget<TextField>(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextField),
      ));
      expect(textField.controller?.text, equals('https://reddit.com'));

      // Tap close
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(InAppWebViewScreen), findsNothing);
      expect(returnedResult, isNull);
    });
  });
}
