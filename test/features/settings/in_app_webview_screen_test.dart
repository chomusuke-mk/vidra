import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:path/path.dart' as p;
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
    tempDir = await Directory.systemTemp.createTemp('vidra_webview_test_');
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

  group('InAppWebViewScreen URL Normalization', () {
    test('normalizes empty and whitespace input to Brave search URL', () {
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

    test('routes plain text search queries to Brave search URL', () {
      expect(
        InAppWebViewScreen.normalizeUrl('flutter inappwebview tutorial'),
        equals('https://search.brave.com/search?q=flutter%20inappwebview%20tutorial'),
      );
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
        buildTestApp(
          InAppWebViewScreen(
            url: 'https://youtube.com',
            saveCookiesPath: tempDir.path,
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
      expect(find.byIcon(Icons.arrow_forward), findsNWidgets(2)); // 1 in footer, 1 as Go button in address bar
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // Verify 3-dot menu and Shortcuts menu
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.text('Shortcuts'), findsWidgets);

      // Verify manual Save Cookies button is removed (automatic capture)
      expect(find.text('Save Cookies'), findsNothing);
      expect(find.text('Capture'), findsNothing);
    });

    testWidgets('allows entering custom URL into address bar',
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
      await tester.enterText(textFieldFinder, 'vimeo.com/watch');
      await tester.pump();

      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.controller?.text, equals('vimeo.com/watch'));
    });

    testWidgets('close button pops the route', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => InAppWebViewScreen.show(
                context,
                tempDir.path,
                url: 'https://youtube.com',
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

    testWidgets('triggers cookie management modal and verifies no layout overflow exceptions',
        (WidgetTester tester) async {
      // Create cookie files
      for (int i = 1; i <= 15; i++) {
        final f = File(p.join(tempDir.path, 'site_$i.com_cookies.txt'));
        f.writeAsStringSync('cookie_test_data_$i');
      }

      await tester.pumpWidget(
        buildTestApp(
          InAppWebViewScreen(
            url: 'https://youtube.com',
            saveCookiesPath: tempDir.path,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open 3-dot menu and select Manage cookies
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manage cookies'));
      await tester.pumpAndSettle();

      // Explicitly check for layout exceptions
      expect(tester.takeException(), isNull);

      // Verify modal and scrollable list are open
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );

      // Scroll modal list
      await tester.drag(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SingleChildScrollView),
        ),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
