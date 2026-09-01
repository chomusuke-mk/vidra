import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/cookie_exporter.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CookieExporter Domain Extraction & Deletion Logic', () {
    test('extractDomainFromFileName accurately parses domains from filenames', () {
      expect(
        CookieExporter.extractDomainFromFileName('youtube.com_cookies.txt'),
        equals('youtube.com'),
      );
      expect(
        CookieExporter.extractDomainFromFileName('m.facebook.com_cookies.txt'),
        equals('m.facebook.com'),
      );
      expect(
        CookieExporter.extractDomainFromFileName('bbc.co.uk_cookies.txt'),
        equals('bbc.co.uk'),
      );
      expect(
        CookieExporter.extractDomainFromFileName('sub.domain.co.uk_cookies.txt'),
        equals('sub.domain.co.uk'),
      );
      expect(
        CookieExporter.extractDomainFromFileName('dailymotion.com.txt'),
        equals('dailymotion.com'),
      );
      expect(
        CookieExporter.extractDomainFromFileName('cookies.txt'),
        equals('cookies'),
      );
      expect(
        CookieExporter.extractDomainFromFileName('default_cookies.txt'),
        equals('default'),
      );
      expect(
        CookieExporter.extractDomainFromFileName('VIMEO.COM_COOKIES.TXT'),
        equals('VIMEO.COM'),
      );
      expect(
        CookieExporter.extractDomainFromFileName('/custom/path/twitch.tv_cookies.txt'),
        equals('twitch.tv'),
      );
    });

    test('deleteCookieFileAndAssociatedCookies removes file from filesystem', () async {
      final tempDir = await Directory.systemTemp.createTemp('vidra_del_cookie_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final testFile = File(p.join(tempDir.path, 'youtube.com_cookies.txt'));
      await testFile.writeAsString('# Netscape HTTP Cookie File\n');
      expect(testFile.existsSync(), isTrue);

      await CookieExporter.deleteCookieFileAndAssociatedCookies(testFile);
      expect(testFile.existsSync(), isFalse);
    });

    test('deleteCookieFileAndAssociatedCookies handles non-existent file gracefully without throwing', () async {
      final nonExistentFile = File('/tmp/vidra_non_existent_cookie_file_12345.txt');
      expect(() => CookieExporter.deleteCookieFileAndAssociatedCookies(nonExistentFile), returnsNormally);
    });
  });

  group('InAppWebViewScreen Manage Cookies UI & Deletion Flow', () {
    late MockLocaleRepository mockLocaleRepo;
    late LocaleController localeController;
    late Directory tempDir;

    setUp(() async {
      mockLocaleRepo = MockLocaleRepository();
      localeController = LocaleController(mockLocaleRepo, 'en');
      await localeController.whenReady;
      tempDir = await Directory.systemTemp.createTemp('vidra_webview_manage_cookies_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Widget buildTestApp({LocaleController? customController}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(
            value: customController ?? localeController,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: InAppWebViewScreen(
            url: 'https://youtube.com',
            saveCookiesPath: tempDir.path,
          ),
        ),
      );
    }

    testWidgets(
      'R1: 3-dot menu button is rendered to the left of shortcuts and opens Manage cookies option (EN)',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        final moreBtnFinder = find.byIcon(Icons.more_vert);
        expect(moreBtnFinder, findsOneWidget);

        final shortcutsFinder = find.text('Shortcuts');
        expect(shortcutsFinder, findsWidgets);

        // Verify geometry: 3-dot button is to the left of Shortcuts dropdown
        final moreDx = tester.getTopLeft(moreBtnFinder).dx;
        final shortcutsDx = tester.getTopLeft(shortcutsFinder.first).dx;
        expect(moreDx, lessThan(shortcutsDx));

        // Tap 3-dot menu
        await tester.tap(moreBtnFinder);
        await tester.pumpAndSettle();

        // Verify "Manage cookies" option is displayed
        expect(find.text('Manage cookies'), findsOneWidget);

        // Dismiss popup
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'R1: 3-dot menu displays "Administrar cookies" when language is Spanish (ES)',
      (WidgetTester tester) async {
        final esController = LocaleController(mockLocaleRepo, 'es');
        await esController.whenReady;

        await tester.pumpWidget(buildTestApp(customController: esController));
        await tester.pumpAndSettle();

        final moreBtnFinder = find.byIcon(Icons.more_vert);
        expect(moreBtnFinder, findsOneWidget);

        // Tap 3-dot menu
        await tester.tap(moreBtnFinder);
        await tester.pumpAndSettle();

        // Verify Spanish localized text
        expect(find.text('Administrar cookies'), findsOneWidget);

        // Dismiss popup
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'R2: Selecting Manage cookies opens Bottom Sheet displaying empty state when no cookies exist',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        // Tap 3-dot menu
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        // Tap Manage cookies
        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        // Verify Bottom Sheet is open with title and empty message
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Manage cookies'),
          ),
          findsOneWidget,
        );
        expect(
          find.text(localeController.localeStrings.sNoCookiesFound),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.cookie_outlined), findsWidgets);

        // Dismiss sheet
        final sheetCloseBtn1 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(sheetCloseBtn1);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'R2 & R3: Bottom Sheet displays cookie files, file sizes, and deleting an item removes file and updates UI',
      (WidgetTester tester) async {
        // Create test cookie files synchronously
        final file1 = File(p.join(tempDir.path, 'youtube.com_cookies.txt'));
        file1.writeAsStringSync('cookie_line_1_test_payload_1234567890');

        final file2 = File(p.join(tempDir.path, 'tiktok.com_cookies.txt'));
        file2.writeAsStringSync('short');

        expect(file1.existsSync(), isTrue);
        expect(file2.existsSync(), isTrue);

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        // Open 3-dot menu and select Manage cookies
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        // Verify files are listed with names and sizes
        expect(find.text('youtube.com_cookies.txt'), findsOneWidget);
        expect(find.text('tiktok.com_cookies.txt'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));

        // Tap delete on first item
        await tester.tap(find.byIcon(Icons.delete_outline).first);
        await tester.pumpAndSettle();

        // Verify file is deleted from disk and 1 item remains in UI
        final remaining = CookieExporter.getSavedCookieFiles(
          directory: tempDir,
        );
        expect(remaining.length, equals(1));
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);

        // Dismiss sheet
        final sheetCloseBtn = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(sheetCloseBtn);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('Close button on Bottom Sheet closes sheet cleanly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manage cookies'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Manage cookies'),
        ),
        findsOneWidget,
      );

      // Tap close button inside bottom sheet
      final closeBtnFinder = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byIcon(Icons.close),
      );
      expect(closeBtnFinder, findsOneWidget);
      await tester.tap(closeBtnFinder);
      await tester.pumpAndSettle();

      // Bottom sheet is dismissed
      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}
