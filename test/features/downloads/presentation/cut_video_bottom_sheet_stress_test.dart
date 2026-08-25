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

Widget createStressApp({
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
      home: Scaffold(
        body: Builder(
          builder:
              (ctx) =>
                  child ??
                  Center(
                    child: ElevatedButton(
                      onPressed: () => CutVideoBottomSheet.show(ctx),
                      child: const Text('Open Modal'),
                    ),
                  ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockLocaleRepository mockLocaleRepo;
  late LocaleController localeController;
  late SettingsRepository settingsRepo;
  late SettingsController settingsController;

  const all11Categories = [
    SponsorblockCategory.sponsor,
    SponsorblockCategory.intro,
    SponsorblockCategory.outro,
    SponsorblockCategory.selfpromo,
    SponsorblockCategory.preview,
    SponsorblockCategory.filler,
    SponsorblockCategory.interaction,
    SponsorblockCategory.music_offtopic,
    SponsorblockCategory.hook,
    SponsorblockCategory.poi_highlight,
    SponsorblockCategory.chapter,
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsRepo = SettingsRepository(prefs);
    settingsController = SettingsController(settingsRepo);

    mockLocaleRepo = MockLocaleRepository();
    localeController = LocaleController(mockLocaleRepo, 'en');
    await localeController.whenReady;
  });

  group('Adversarial Stress Test: All 11 SponsorBlock Categories', () {
    testWidgets('Verify exhaustive category inventory contains exactly 11 items', (
      WidgetTester tester,
    ) async {
      expect(SponsorblockCategory.values.length, equals(11));
      expect(
        SponsorblockCategory.values,
        unorderedEquals(all11Categories),
      );
    });

    testWidgets('Rapid sequential addition of all 11 SponsorBlock categories', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
          child: const CutVideoBottomSheet(),
        ),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.descendant(
        of: find.byType(LazyList),
        matching: find.byType(TextField),
      );
      final addBtnFinder = find.byIcon(Icons.add_circle);

      expect(settingsController.downloadOptions.sponsorblockRemove, isEmpty);

      // Sequentially add each of the 11 categories
      for (int i = 0; i < all11Categories.length; i++) {
        final cat = all11Categories[i];
        await tester.enterText(textFieldFinder, cat.name);
        await tester.tap(addBtnFinder);
        await tester.pumpAndSettle();

        expect(
          settingsController.downloadOptions.sponsorblockRemove.length,
          equals(i + 1),
        );
        expect(
          settingsController.downloadOptions.sponsorblockRemove.last,
          equals(cat),
        );
        expect(find.byType(InputChip), findsNWidgets(i + 1));
      }

      // Verify all 11 chips exist
      expect(find.byType(InputChip), findsNWidgets(11));
      expect(
        settingsController.downloadOptions.sponsorblockRemove,
        equals(all11Categories),
      );
    });

    testWidgets('Rapid sequential removal of all 11 categories down to empty', (
      WidgetTester tester,
    ) async {
      // Preload all 11 categories
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: List.from(all11Categories),
        ),
      );

      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
          child: const CutVideoBottomSheet(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNWidgets(11));
      expect(
        settingsController.downloadOptions.sponsorblockRemove.length,
        equals(11),
      );

      // Remove chips one by one from the first chip
      for (int remaining = 11; remaining > 0; remaining--) {
        final cancelIcons = find.descendant(
          of: find.byType(InputChip),
          matching: find.byIcon(Icons.cancel),
        );
        expect(cancelIcons, findsNWidgets(remaining));

        await tester.tap(cancelIcons.first);
        await tester.pumpAndSettle();

        expect(
          settingsController.downloadOptions.sponsorblockRemove.length,
          equals(remaining - 1),
        );
        expect(find.byType(InputChip), findsNWidgets(remaining - 1));
      }

      expect(settingsController.downloadOptions.sponsorblockRemove, isEmpty);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('High-frequency churn: rapid interleaved add, remove, and re-add cycles', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
          child: const CutVideoBottomSheet(),
        ),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.descendant(
        of: find.byType(LazyList),
        matching: find.byType(TextField),
      );
      final addBtnFinder = find.byIcon(Icons.add_circle);

      // Burst 1: Add first 5 categories
      for (int i = 0; i < 5; i++) {
        await tester.enterText(textFieldFinder, all11Categories[i].name);
        await tester.tap(addBtnFinder);
        await tester.pumpAndSettle();
      }
      expect(
        settingsController.downloadOptions.sponsorblockRemove.length,
        equals(5),
      );

      // Burst 2: Delete 2 categories
      final cancelIcons1 = find.descendant(
        of: find.byType(InputChip),
        matching: find.byIcon(Icons.cancel),
      );
      await tester.tap(cancelIcons1.at(0));
      await tester.pumpAndSettle();
      final cancelIcons2 = find.descendant(
        of: find.byType(InputChip),
        matching: find.byIcon(Icons.cancel),
      );
      await tester.tap(cancelIcons2.at(0));
      await tester.pumpAndSettle();
      expect(
        settingsController.downloadOptions.sponsorblockRemove.length,
        equals(3),
      );

      // Burst 3: Add remaining 6 categories (indexes 5..10)
      for (int i = 5; i < 11; i++) {
        await tester.enterText(textFieldFinder, all11Categories[i].name);
        await tester.tap(addBtnFinder);
        await tester.pumpAndSettle();
      }
      expect(
        settingsController.downloadOptions.sponsorblockRemove.length,
        equals(9),
      );

      // Burst 4: Re-add the 2 categories removed earlier (index 0 and 1)
      await tester.enterText(textFieldFinder, all11Categories[0].name);
      await tester.tap(addBtnFinder);
      await tester.pumpAndSettle();
      await tester.enterText(textFieldFinder, all11Categories[1].name);
      await tester.tap(addBtnFinder);
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.sponsorblockRemove.length,
        equals(11),
      );
      expect(find.byType(InputChip), findsNWidgets(11));
      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial Stress Test: Parsing Edge Cases & Fallback to `sponsor`', () {
    testWidgets('Unknown strings in LazyList.onChanged gracefully fallback to SponsorblockCategory.sponsor', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
          child: const CutVideoBottomSheet(),
        ),
      );
      await tester.pumpAndSettle();

      final lazyList = tester.widget<LazyList>(find.byType(LazyList));

      // Trigger onChanged with completely unknown strings
      lazyList.onChanged(['unknown_category_xyz', 'not_a_real_category']);
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.sponsorblockRemove,
        equals([
          SponsorblockCategory.sponsor,
          SponsorblockCategory.sponsor,
        ]),
      );
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text('sponsor'), findsNWidgets(2));
    });

    testWidgets('Mixed valid and invalid category strings resolve cleanly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
          child: const CutVideoBottomSheet(),
        ),
      );
      await tester.pumpAndSettle();

      final lazyList = tester.widget<LazyList>(find.byType(LazyList));

      // Mixed payload: [valid, invalid, valid, invalid, valid]
      lazyList.onChanged([
        'intro',
        'invalid_foo',
        'music_offtopic',
        'SPONSOR_UPPERCASE',
        'outro',
      ]);
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.sponsorblockRemove,
        equals([
          SponsorblockCategory.intro,
          SponsorblockCategory.sponsor,
          SponsorblockCategory.music_offtopic,
          SponsorblockCategory.sponsor,
          SponsorblockCategory.outro,
        ]),
      );
      expect(find.byType(InputChip), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Empty and blank string entries in onChanged fallback to sponsor', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
          child: const CutVideoBottomSheet(),
        ),
      );
      await tester.pumpAndSettle();

      final lazyList = tester.widget<LazyList>(find.byType(LazyList));

      lazyList.onChanged(['', '   ', 'hook']);
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.sponsorblockRemove,
        equals([
          SponsorblockCategory.sponsor,
          SponsorblockCategory.sponsor,
          SponsorblockCategory.hook,
        ]),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial Stress Test: Modal Dismissal Invariants', () {
    testWidgets('Dismiss via backdrop / modal barrier tap', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      // Modal not present initially
      expect(find.byType(CutVideoBottomSheet), findsNothing);

      // Open modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();
      expect(find.byType(CutVideoBottomSheet), findsOneWidget);

      // Tap backdrop outside modal sheet (top left corner)
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byType(CutVideoBottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dismiss via close IconButton in header', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();
      expect(find.byType(CutVideoBottomSheet), findsOneWidget);

      // Tap close button with cvClose tooltip
      final closeButtonFinder = find.byTooltip(
        localeController.localeStrings.cvClose,
      );
      expect(closeButtonFinder, findsOneWidget);

      await tester.tap(closeButtonFinder);
      await tester.pumpAndSettle();

      expect(find.byType(CutVideoBottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dismiss via Android/system back button (handlePopRoute)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();
      expect(find.byType(CutVideoBottomSheet), findsOneWidget);

      // Simulate system pop / back route event
      final didPop = await tester.binding.handlePopRoute();
      expect(didPop, isTrue);
      await tester.pumpAndSettle();

      expect(find.byType(CutVideoBottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rapid repetitive open/dismiss cycle stress test (10 iterations)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      for (int i = 0; i < 10; i++) {
        // Open modal
        await tester.tap(find.text('Open Modal'));
        await tester.pumpAndSettle();
        expect(find.byType(CutVideoBottomSheet), findsOneWidget);

        // Dismiss using alternating methods
        if (i % 3 == 0) {
          // Close button
          await tester.tap(find.byIcon(Icons.close));
        } else if (i % 3 == 1) {
          // Backdrop tap
          await tester.tapAt(const Offset(20, 20));
        } else {
          // System back route
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.byType(CutVideoBottomSheet), findsNothing);
      }

      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial Stress Test: External State Synchronization', () {
    testWidgets('External mutation in SettingsController reactively updates open modal UI', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      // Open modal with empty categories
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();
      expect(find.byType(CutVideoBottomSheet), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);

      // Externally mutate settingsController to have 4 categories
      final externalList1 = [
        SponsorblockCategory.sponsor,
        SponsorblockCategory.intro,
        SponsorblockCategory.outro,
        SponsorblockCategory.preview,
      ];
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: externalList1,
        ),
      );
      await tester.pumpAndSettle();

      // Verify modal immediately shows 4 chips
      expect(find.byType(InputChip), findsNWidgets(4));
      for (final cat in externalList1) {
        expect(find.text(cat.name), findsOneWidget);
      }

      // Externally replace with all 11 categories
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: List.from(all11Categories),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(11));

      // Externally clear all categories
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('User interaction inside modal after external mutation maintains state consistency', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      // Open modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // External mutation: set to [hook, filler]
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: [
            SponsorblockCategory.hook,
            SponsorblockCategory.filler,
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(2));

      // User removes 'hook' chip via modal UI
      final hookCancelIcon = find.descendant(
        of: find.byType(InputChip),
        matching: find.byIcon(Icons.cancel),
      ).first;
      await tester.tap(hookCancelIcon);
      await tester.pumpAndSettle();

      // Controller should reflect only [filler]
      expect(
        settingsController.downloadOptions.sponsorblockRemove,
        equals([SponsorblockCategory.filler]),
      );
      expect(find.byType(InputChip), findsOneWidget);

      // User adds 'chapter' via text field
      final textFieldFinder = find.descendant(
        of: find.byType(LazyList),
        matching: find.byType(TextField),
      );
      await tester.enterText(textFieldFinder, 'chapter');
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.sponsorblockRemove,
        equals([SponsorblockCategory.filler, SponsorblockCategory.chapter]),
      );
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Multiple rapid consecutive external mutations while modal is open', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Rapidly fire 5 mutations without pumping in between, then pumpAndSettle
      for (int i = 1; i <= 5; i++) {
        settingsController.updateDownloadOptions(
          settingsController.downloadOptions.copyWith(
            sponsorblockRemove: all11Categories.take(i).toList(),
          ),
        );
      }
      await tester.pumpAndSettle();

      expect(
        settingsController.downloadOptions.sponsorblockRemove.length,
        equals(5),
      );
      expect(find.byType(InputChip), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial Stress Test: Viewport & Keyboard Insets Stress', () {
    testWidgets('Modal handles dynamic keyboard appearance (viewInsets) without overflow', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Simulate keyboard opening by setting viewInsets
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      addTearDown(() => tester.view.resetViewInsets());

      await tester.pumpAndSettle();

      // Verify no exceptions or overflows occurred
      expect(find.byType(CutVideoBottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Modal handles narrow mobile viewport (320x568)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Seed all 11 categories in narrow screen
      settingsController.updateDownloadOptions(
        settingsController.downloadOptions.copyWith(
          sponsorblockRemove: List.from(all11Categories),
        ),
      );

      await tester.pumpWidget(
        createStressApp(
          settingsController: settingsController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(CutVideoBottomSheet), findsOneWidget);
      expect(find.byType(InputChip), findsNWidgets(11));
      expect(tester.takeException(), isNull);
    });
  });
}
