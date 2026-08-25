import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/features/downloads/presentation/widgets/cut_video_bottom_sheet.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

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

Widget createTestApp({
  required SettingsController settingsController,
  required LocaleController localeController,
  Widget? child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
      ),
      ChangeNotifierProvider<LocaleController>.value(value: localeController),
    ],
    child: MaterialApp(
      home: Scaffold(body: child ?? const CutVideoBottomSheet()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockLocaleRepository mockLocaleRepo;
  late LocaleController localeController;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(settingsRepo);

    mockLocaleRepo = MockLocaleRepository();
    localeController = LocaleController(mockLocaleRepo, 'en');
    await localeController.whenReady;
  });

  group('CutVideoBottomSheet UI Structure & Visual Rendering (Tier 1)', () {
    testWidgets(
      'renders drag handle, scissors icon, bold title, close button, divider, and LazyList',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          createTestApp(
            settingsController: settingsController,
            localeController: localeController,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Root structure and ClipRRect
        expect(find.byType(CutVideoBottomSheet), findsOneWidget);
        expect(find.byType(ClipRRect), findsWidgets);
        expect(find.byType(Divider), findsOneWidget);

        // 2. Drag handle (Container 40x4)
        final dragHandleFinder = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints == const BoxConstraints.tightFor(width: 40.0, height: 4.0),
        );
        expect(dragHandleFinder, findsOneWidget);

        // 3. Scissors icon and localized bold title
        expect(find.byIcon(Icons.cut_outlined), findsOneWidget);
        expect(find.text(localeController.localeStrings.cvTitle), findsOneWidget);

        // 4. Close button
        final closeBtnFinder = find.byTooltip(localeController.localeStrings.cvClose);
        expect(closeBtnFinder, findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);

        // 5. Section title & description
        expect(find.text(localeController.localeStrings.sSponsorblockRemove), findsOneWidget);
        expect(
          find.text(localeController.localeStrings.cvDescription),
          findsOneWidget,
        );

        // 6. LazyList component
        expect(find.byType(LazyList), findsOneWidget);
        expect(find.text(localeController.localeStrings.sSearchCategory), findsOneWidget);
      },
    );

    testWidgets('respects max width constraint of 640px', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final constrainedBoxes = tester
          .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
          .where((cb) => cb.constraints.maxWidth == 640)
          .toList();
      expect(constrainedBoxes, isNotEmpty);
    });
  });

  group('Modal Bottom Sheet Invocation & Dismissal (Tier 1 & Tier 2)', () {
    testWidgets('CutVideoBottomSheet.show opens modal and close button dismisses it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(
              value: settingsController,
            ),
            ChangeNotifierProvider<LocaleController>.value(
              value: localeController,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (ctx) => ElevatedButton(
                      onPressed: () => CutVideoBottomSheet.show(ctx),
                      child: const Text('Open Cut Video Modal'),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bottom sheet not present initially
      expect(find.byType(CutVideoBottomSheet), findsNothing);

      // Open bottom sheet
      await tester.tap(find.text('Open Cut Video Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(CutVideoBottomSheet), findsOneWidget);
      expect(find.text(localeController.localeStrings.cvTitle), findsOneWidget);

      // Tap close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Modal is dismissed
      expect(find.byType(CutVideoBottomSheet), findsNothing);
    });

    testWidgets('tapping modal barrier dismisses bottom sheet', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(
              value: settingsController,
            ),
            ChangeNotifierProvider<LocaleController>.value(
              value: localeController,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (ctx) => ElevatedButton(
                      onPressed: () => CutVideoBottomSheet.show(ctx),
                      child: const Text('Open Cut Video Modal'),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Cut Video Modal'));
      await tester.pumpAndSettle();
      expect(find.byType(CutVideoBottomSheet), findsOneWidget);

      // Tap top-left outside modal sheet
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byType(CutVideoBottomSheet), findsNothing);
    });
  });

  group('SponsorBlock Category Selection & SettingsController Binding (Tier 1 & Tier 2)', () {
    testWidgets('LazyList contains suggestions matching all SponsorblockCategory enum names', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final lazyList = tester.widget<LazyList>(find.byType(LazyList));
      final expectedNames =
          SponsorblockCategory.values.map((e) => e.name).toList();

      expect(lazyList.suggestions, equals(expectedNames));
      expect(lazyList.suggestions, contains('sponsor'));
      expect(lazyList.suggestions, contains('intro'));
      expect(lazyList.suggestions, contains('outro'));
      expect(lazyList.suggestions, contains('selfpromo'));
      expect(lazyList.suggestions, contains('preview'));
      expect(lazyList.suggestions, contains('filler'));
      expect(lazyList.suggestions, contains('interaction'));
      expect(lazyList.suggestions, contains('music_offtopic'));
      expect(lazyList.suggestions, contains('hook'));
      expect(lazyList.suggestions, contains('poi_highlight'));
      expect(lazyList.suggestions, contains('chapter'));
    });

    testWidgets('adding a category chip updates SettingsController.downloadOptions.sponsorblockRemove', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(settingsController.downloadOptions.sponsorblockRemove, isEmpty);

      // Find text input in LazyList
      final textFieldFinder = find.descendant(
        of: find.byType(LazyList),
        matching: find.byType(TextField),
      );
      expect(textFieldFinder, findsOneWidget);

      // Enter 'sponsor' and add
      await tester.enterText(textFieldFinder, 'sponsor');
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.sponsorblockRemove,
        equals([SponsorblockCategory.sponsor]),
      );

      // Add 'intro'
      await tester.enterText(textFieldFinder, 'intro');
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.sponsorblockRemove,
        equals([SponsorblockCategory.sponsor, SponsorblockCategory.intro]),
      );
    });

    testWidgets('removing a category chip updates SettingsController', (
      WidgetTester tester,
    ) async {
      // Pre-seed options with categories
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [
            SponsorblockCategory.sponsor,
            SponsorblockCategory.outro,
          ],
        ),
      );

      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text('sponsor'), findsOneWidget);
      expect(find.text('outro'), findsOneWidget);

      // Delete the first chip ('sponsor')
      final cancelIcons = find.descendant(
        of: find.byType(InputChip),
        matching: find.byIcon(Icons.cancel),
      );
      expect(cancelIcons, findsNWidgets(2));

      await tester.tap(cancelIcons.first);
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.sponsorblockRemove,
        equals([SponsorblockCategory.outro]),
      );
      expect(find.byType(InputChip), findsOneWidget);
      expect(find.text('outro'), findsOneWidget);
    });

    testWidgets('selecting all categories sequentially updates SettingsController', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.descendant(
        of: find.byType(LazyList),
        matching: find.byType(TextField),
      );

      final categoriesToAdd = [
        SponsorblockCategory.sponsor,
        SponsorblockCategory.selfpromo,
        SponsorblockCategory.music_offtopic,
      ];

      for (final cat in categoriesToAdd) {
        await tester.enterText(textFieldFinder, cat.name);
        await tester.tap(find.byIcon(Icons.add_circle));
        await tester.pumpAndSettle();
      }

      expect(
        settingsController.downloadOptions.sponsorblockRemove,
        equals(categoriesToAdd),
      );
    });
  });

  group('Empty and Multi-Category Initial States & Dynamic Reactivity (Tier 2 & Tier 3)', () {
    testWidgets('initial empty state renders no chips', (
      WidgetTester tester,
    ) async {
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(sponsorblockRemove: []),
      );

      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('initial multi-category state renders all chips', (
      WidgetTester tester,
    ) async {
      final initialCategories = [
        SponsorblockCategory.sponsor,
        SponsorblockCategory.intro,
        SponsorblockCategory.outro,
        SponsorblockCategory.selfpromo,
        SponsorblockCategory.music_offtopic,
      ];
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: initialCategories,
        ),
      );

      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNWidgets(5));
      for (final cat in initialCategories) {
        expect(find.text(cat.name), findsOneWidget);
      }
    });

    testWidgets('external state mutation in SettingsController reactively updates UI chips', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNothing);

      // Mutate controller externally
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [
            SponsorblockCategory.preview,
            SponsorblockCategory.hook,
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text('preview'), findsOneWidget);
      expect(find.text('hook'), findsOneWidget);
    });
  });

  group('Spanish (es) Localization (Tier 1 & Tier 5)', () {
    testWidgets('renders all Spanish translated strings correctly', (
      WidgetTester tester,
    ) async {
      final esLocaleController = LocaleController(mockLocaleRepo, 'es');
      await esLocaleController.whenReady;

      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: esLocaleController,
        ),
      );
      await tester.pumpAndSettle();

      // Title
      expect(find.text(esLocaleController.localeStrings.cvTitle), findsOneWidget);
      expect(esLocaleController.localeStrings.cvTitle, equals('Cortar vídeo'));

      // Close button tooltip
      expect(find.byTooltip(esLocaleController.localeStrings.cvClose), findsOneWidget);
      expect(esLocaleController.localeStrings.cvClose, equals('Cerrar'));

      // Section title & description
      expect(
        find.text(esLocaleController.localeStrings.sSponsorblockRemove),
        findsOneWidget,
      );
      expect(
        find.text(esLocaleController.localeStrings.cvDescription),
        findsOneWidget,
      );
      expect(
        esLocaleController.localeStrings.cvDescription,
        equals('Elimina segmentos de las categorías de SponsorBlock.'),
      );

      // LazyList search category placeholder
      expect(
        find.text(esLocaleController.localeStrings.sSearchCategory),
        findsOneWidget,
      );
    });
  });

  group('Adversarial Stress & Edge Cases (Tier 5)', () {
    testWidgets('stress test rapid addition and deletion of categories', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.descendant(
        of: find.byType(LazyList),
        matching: find.byType(TextField),
      );

      final categoriesToAdd = ['sponsor', 'intro', 'outro', 'filler', 'chapter'];
      for (final cat in categoriesToAdd) {
        await tester.enterText(textFieldFinder, cat);
        await tester.tap(find.byIcon(Icons.add_circle));
        await tester.pumpAndSettle();
      }

      expect(
        settingsController.downloadOptions.sponsorblockRemove.length,
        equals(5),
      );
      expect(find.byType(InputChip), findsNWidgets(5));

      // Remove all chips one by one
      while (find.byType(InputChip).evaluate().isNotEmpty) {
        final cancelIcon = find.descendant(
          of: find.byType(InputChip),
          matching: find.byIcon(Icons.cancel),
        ).first;
        await tester.tap(cancelIcon);
        await tester.pumpAndSettle();
      }

      expect(settingsController.downloadOptions.sponsorblockRemove, isEmpty);
      expect(find.byType(InputChip), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
