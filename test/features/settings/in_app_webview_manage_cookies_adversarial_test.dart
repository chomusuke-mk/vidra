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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InAppWebViewScreen Manage Cookies Adversarial Suite', () {
    late MockLocaleRepository mockLocaleRepo;
    late LocaleController localeController;
    late Directory tempDir;

    setUp(() async {
      mockLocaleRepo = MockLocaleRepository();
      localeController = LocaleController(mockLocaleRepo, 'en');
      await localeController.whenReady;
      tempDir = await Directory.systemTemp.createTemp('vidra_webview_cookies_adv_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Widget buildTestApp({
      LocaleController? customController,
      String? customSavePath,
      TextScaler? textScaler,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(
            value: customController ?? localeController,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          builder: (context, child) {
            if (textScaler != null) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              );
            }
            return child!;
          },
          home: InAppWebViewScreen(
            url: 'https://youtube.com',
            saveCookiesPath: customSavePath ?? tempDir.path,
          ),
        ),
      );
    }

    testWidgets(
      'ADV 1: Extreme accessibility text scaling (3.0x) with long filenames does not trigger RenderFlex overflow',
      (WidgetTester tester) async {
        // Create files with exceptionally long filenames
        for (int i = 1; i <= 8; i++) {
          final file = File(
            p.join(
              tempDir.path,
              'super-ultra-mega-long-domain-name-with-many-parts-and-subdomains-$i.production.cdn.network.example.com_cookies.txt',
            ),
          );
          file.writeAsStringSync('cookie_payload_for_extreme_scaling_test_$i');
        }

        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestApp(textScaler: const TextScaler.linear(3.0)),
        );
        await tester.pumpAndSettle();

        // Tap 3-dot menu and open Manage cookies
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        // Must have zero layout overflow exceptions
        expect(tester.takeException(), isNull);
        expect(find.byType(BottomSheet), findsOneWidget);

        // Verify scrolling operates without layout overflow under 3.0x text scaling
        final scrollable = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SingleChildScrollView),
        );
        expect(scrollable, findsOneWidget);

        await tester.drag(scrollable, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.drag(scrollable, const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ADV 2: Extreme viewport matrix (240x320, 800x200 landscape, 180x400) renders modal without overflow',
      (WidgetTester tester) async {
        for (int i = 1; i <= 6; i++) {
          final file = File(p.join(tempDir.path, 'site_$i.com_cookies.txt'));
          file.writeAsStringSync('sample_cookie_bytes_$i');
        }

        final extremeViewports = [
          const Size(240, 320), // Ultra small portrait
          const Size(800, 200), // Ultra short landscape
          const Size(400, 120), // Ultra constrained height
          const Size(180, 400), // Ultra narrow
        ];

        for (final vp in extremeViewports) {
          tester.view.physicalSize = vp;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(buildTestApp());
          await tester.pumpAndSettle();

          await tester.tap(find.byIcon(Icons.more_vert));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Manage cookies'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(BottomSheet), findsOneWidget);

          final scrollable = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(SingleChildScrollView),
          );
          expect(scrollable, findsOneWidget);

          await tester.drag(scrollable, const Offset(0, -100));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final closeBtn = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byIcon(Icons.close),
          );
          await tester.tap(closeBtn);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'ADV 3: Large scale (50 items) with progressive deletion down to 0 transitions cleanly to empty state',
      (WidgetTester tester) async {
        // Create 50 files
        for (int i = 1; i <= 50; i++) {
          final prefix = i < 10 ? '0$i' : '$i';
          final file = File(p.join(tempDir.path, 'bulk_site_$prefix.org_cookies.txt'));
          file.writeAsStringSync('cookie_content_$i');
        }

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(BottomSheet), findsOneWidget);

        // Delete first 5 items from the top
        for (int i = 0; i < 5; i++) {
          final deleteButtons = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byIcon(Icons.delete_outline),
          );
          expect(deleteButtons, findsWidgets);
          await tester.tap(deleteButtons.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        // Delete all remaining files directly from disk to simulate full purge and trigger setModalState
        for (final f in tempDir.listSync()) {
          if (f is File) {
            f.deleteSync();
          }
        }

        // Tap the remaining first delete button to trigger setModalState with now 0 files
        final deleteBtns = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.delete_outline),
        );
        if (deleteBtns.evaluate().isNotEmpty) {
          await tester.tap(deleteBtns.first);
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
        // Should now show empty state without overflow
        expect(
          find.text(localeController.localeStrings.sNoCookiesFound),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'ADV 4: Formats cookie file sizes accurately (0 B, 1.5 KB, 2.0 MB) without errors',
      (WidgetTester tester) async {
        // 0 B file
        final zeroFile = File(p.join(tempDir.path, 'zero_domain.com_cookies.txt'));
        zeroFile.writeAsStringSync('');

        // 1.5 KB file
        final kbFile = File(p.join(tempDir.path, 'kb_domain.com_cookies.txt'));
        kbFile.writeAsBytesSync(List.filled(1536, 65));

        // 2.0 MB file
        final mbFile = File(p.join(tempDir.path, 'mb_domain.com_cookies.txt'));
        mbFile.writeAsBytesSync(List.filled(2 * 1024 * 1024, 66));

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('0 B'), findsOneWidget);
        expect(find.text('1.5 KB'), findsOneWidget);
        expect(find.text('2.0 MB'), findsOneWidget);
      },
    );

    testWidgets(
      'ADV 5: Whitespace and invalid saveCookiesPath gracefully renders empty state without throwing',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildTestApp(customSavePath: '   '),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.text(localeController.localeStrings.sNoCookiesFound),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'ADV 6: Dynamic locale change updates modal strings seamlessly without layout exceptions',
      (WidgetTester tester) async {
        final f = File(p.join(tempDir.path, 'sample.org_cookies.txt'));
        f.writeAsStringSync('cookie_data');

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Manage cookies'), findsOneWidget);

        // Switch to Spanish
        localeController.setLocale('es');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(localeController.localeStrings.wvManageCookies), findsOneWidget);
      },
    );

    testWidgets(
      'ADV 7: Unicode, CJK, Arabic RTL, and Emoji filenames render cleanly with ellipsis and zero overflow',
      (WidgetTester tester) async {
        final complexNames = [
          '🍪_super_cookie_🍪_cookies.txt',
          'موقع_ملفات_الكوكيز_الرسمي_cookies.txt',
          '日本語クッキーデータ_サイト_cookies.txt',
          'русский_домен_файлы_cookies.txt',
          'very_long_string_without_any_break_or_delimiter_abcdefghijklmnopqrstuvwxyz0123456789_cookies.txt',
        ];

        for (final name in complexNames) {
          final f = File(p.join(tempDir.path, name));
          f.writeAsStringSync('dummy_payload');
        }

        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(BottomSheet), findsOneWidget);

        // Verify delete on RTL / Unicode item works cleanly
        final deleteBtns = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.delete_outline),
        );
        expect(deleteBtns, findsNWidgets(5));
        await tester.tap(deleteBtns.first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ADV 8: Live orientation / viewport resize while modal is open does not crash or cause overflow',
      (WidgetTester tester) async {
        for (int i = 1; i <= 10; i++) {
          final f = File(p.join(tempDir.path, 'resize_test_$i.org_cookies.txt'));
          f.writeAsStringSync('cookie_content');
        }

        // Start in portrait
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Rotate to landscape
        tester.view.physicalSize = const Size(640, 360);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Resize to ultra-compact
        tester.view.physicalSize = const Size(300, 200);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Scroll inside modal under new dimensions
        final scrollable = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SingleChildScrollView),
        );
        await tester.drag(scrollable, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ADV 9: Sudden deletion of backing saveCookiesPath directory while modal is open handled gracefully',
      (WidgetTester tester) async {
        final f = File(p.join(tempDir.path, 'deleted_dir_test.com_cookies.txt'));
        f.writeAsStringSync('cookie_test');

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Delete entire temp directory
        tempDir.deleteSync(recursive: true);

        // Tap delete button on the item
        final deleteBtn = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.delete_outline),
        );
        if (deleteBtn.evaluate().isNotEmpty) {
          await tester.tap(deleteBtn.first);
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
        expect(
          find.text(localeController.localeStrings.sNoCookiesFound),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'ADV 10: 50 items with rapid drag flinging and close cycle throws zero exceptions',
      (WidgetTester tester) async {
        for (int i = 1; i <= 50; i++) {
          final prefix = i < 10 ? '0$i' : '$i';
          final f = File(p.join(tempDir.path, 'fling_$prefix.org_cookies.txt'));
          f.writeAsStringSync('fling_payload_$i');
        }

        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Manage cookies'));
        await tester.pumpAndSettle();

        final scrollable = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SingleChildScrollView),
        );

        // Rapid fling downward and upward
        await tester.fling(scrollable, const Offset(0, -2000), 5000);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.fling(scrollable, const Offset(0, 2000), 5000);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Dismiss
        final closeBtn = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
