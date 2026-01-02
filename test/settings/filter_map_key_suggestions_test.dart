import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/data/preferences/preference_options.dart';
import 'package:vidra/ui/widgets/preferences/preference_control_shared.dart';
import 'package:vidra/ui/widgets/preferences/preference_control_builder.dart';
import 'package:vidra/ui/widgets/preferences/preference_list_control.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

final List<LocalizationsDelegate<dynamic>> _testLocalizationDelegates =
    <LocalizationsDelegate<dynamic>>[
      VidraLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      const LocaleNamesLocalizationsDelegate(),
    ];

Widget _buildLocalizedApp(Widget home) {
  return MaterialApp(
    locale: const Locale('es'),
    localizationsDelegates: _testLocalizationDelegates,
    supportedLocales: VidraLocalizations.supportedLocales,
    home: home,
  );
}

Future<PreferencesModel> _pumpSponsorblockPreferenceWidget(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({});
  final preferencesModel = PreferencesModel();
  await preferencesModel.initializePreferences();
  addTearDown(preferencesModel.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<PreferencesModel>.value(
      value: preferencesModel,
      child: _buildLocalizedApp(
        const Scaffold(
          body: SafeArea(child: TestSponsorblockPreferenceWidget()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return preferencesModel;
}

Future<PreferencesModel> _pumpFormatPreferenceWidget(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({});
  final preferencesModel = PreferencesModel();
  await preferencesModel.initializePreferences();
  await preferencesModel.preferences.format.setValue(<String>[]);
  addTearDown(preferencesModel.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<PreferencesModel>.value(
      value: preferencesModel,
      child: _buildLocalizedApp(
        const Scaffold(body: SafeArea(child: TestFormatPreferenceWidget())),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return preferencesModel;
}

List<String> _readSponsorblockSelection(PreferencesModel model) {
  final raw = model.preferences.sponsorblockMark.get('value');
  if (raw is List) {
    return raw.map((value) => value.toString()).toList();
  }
  return <String>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await I18n.preloadAll();
  });

  group('filterMapKeySuggestions', () {
    final available = List<String>.from(
      autocompleteOptions['add_headers'] ?? const <String>[],
    );

    test('returns all suggestions when no entries exist', () {
      final result = filterMapKeySuggestions(
        available,
        const <String, String>{},
        query: '',
        currentInput: '',
      );

      expect(result, equals(available));
    });

    test('omits existing keys on initial load with entries', () {
      final result = filterMapKeySuggestions(
        available,
        const <String, String>{'Accept': 'value'},
        query: '',
        currentInput: '',
      );

      expect(result.contains('Accept'), isFalse);
    });

    test('retains option while the user is editing the same key', () {
      final result = filterMapKeySuggestions(
        available,
        const <String, String>{'Accept': 'value'},
        query: 'Ac',
        currentInput: 'Accept',
      );

      expect(result, contains('Accept'));
      expect(
        result.every((option) => option.toLowerCase().contains('ac')),
        isTrue,
      );
    });

    test('drops suggestion immediately after a key is added', () {
      final before = filterMapKeySuggestions(
        available,
        const <String, String>{},
        query: '',
        currentInput: '',
      );
      expect(before, contains('Origin'));

      final after = filterMapKeySuggestions(
        available,
        const <String, String>{'Origin': 'https://example.com'},
        query: '',
        currentInput: '',
      );

      expect(after.contains('Origin'), isFalse);
    });

    test('restores suggestion after a key is removed', () {
      final withEntry = filterMapKeySuggestions(
        available,
        const <String, String>{'Referer': 'https://example.com'},
        query: '',
        currentInput: '',
      );
      expect(withEntry.contains('Referer'), isFalse);

      final cleared = filterMapKeySuggestions(
        available,
        const <String, String>{},
        query: '',
        currentInput: '',
      );

      expect(cleared, contains('Referer'));
    });

    test('removing an entry increases the suggestion count by one', () {
      final withEntry = filterMapKeySuggestions(
        available,
        const <String, String>{'Host': 'example.com'},
        query: '',
        currentInput: '',
      );

      final withoutEntry = filterMapKeySuggestions(
        available,
        const <String, String>{},
        query: '',
        currentInput: '',
      );

      expect(withoutEntry.length, withEntry.length + 1);
    });
  });

  group('format preference widget', () {
    testWidgets(
      'allows adding and removing custom entries without suggestions',
      (WidgetTester tester) async {
        final preferencesModel = await _pumpFormatPreferenceWidget(tester);
        const customValue = 'customformat+best';

        expect(find.byKey(const ValueKey('format_mode_text')), findsOneWidget);

        final customInput = find.byKey(const ValueKey('format_custom_input'));
        await tester.ensureVisible(customInput);
        await tester.enterText(customInput, customValue);

        final addButton = find.byKey(const ValueKey('format_custom_add'));
        await tester.ensureVisible(addButton);
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        final chipFinder = find.byKey(
          const ValueKey('format_chip_$customValue'),
        );
        expect(chipFinder, findsOneWidget);

        final stored = preferencesModel.preferences.format.get('value');
        expect(stored, isA<List>());
        final List<dynamic> storedList = stored as List<dynamic>;
        expect(storedList.contains(customValue), isTrue);

        final deleteFinder = find.byKey(
          const ValueKey('format_delete_$customValue'),
        );
        await tester.ensureVisible(deleteFinder);
        await tester.tap(deleteFinder);
        await tester.pumpAndSettle();

        expect(chipFinder, findsNothing);
        final updated = preferencesModel.preferences.format.get('value');
        expect(updated, isA<List>());
        final List<dynamic> updatedList = updated as List<dynamic>;
        expect(updatedList.contains(customValue), isFalse);
      },
    );
  });

  group('map preference widget suggestions', () {
    testWidgets('renders existing entries after load', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'add_headers': jsonEncode({'Accept': 'value'}),
      });
      final preferencesModel = PreferencesModel();
      await preferencesModel.initializePreferences();
      addTearDown(preferencesModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesModel>.value(
          value: preferencesModel,
          child: _buildLocalizedApp(
            const Scaffold(body: SafeArea(child: TestMapPreferenceWidget())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('map_entry_add_headers_Accept')),
        findsOneWidget,
      );
    });

    testWidgets('suggestions refresh after add and remove', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final preferencesModel = PreferencesModel();
      await preferencesModel.initializePreferences();
      await preferencesModel.preferences.addHeaders.setValue(
        <String, String>{},
      );
      addTearDown(preferencesModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesModel>.value(
          value: preferencesModel,
          child: _buildLocalizedApp(
            const Scaffold(body: SafeArea(child: TestMapPreferenceWidget())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final keyField = find.byKey(const ValueKey('map_key_add_headers'));
      final valueField = find.byKey(const ValueKey('map_value_add_headers'));

      await tester.tap(keyField);
      await tester.enterText(keyField, 'Ac');
      await tester.pumpAndSettle();
      final acceptOptionKey = find.byKey(
        const ValueKey('map_key_autocomplete_add_headers_Accept'),
      );
      expect(acceptOptionKey, findsOneWidget);

      await tester.tap(acceptOptionKey);
      await tester.pumpAndSettle();

      await tester.enterText(valueField, 'value');
      await tester.tap(find.byKey(const ValueKey('map_add_add_headers')));
      await tester.pumpAndSettle();

      final currentValue = preferencesModel.preferences.addHeaders.get('value');
      expect(currentValue, isA<Map>());
      final currentMap = (currentValue as Map).map(
        (key, value) => MapEntry('$key', '${value ?? ''}'),
      );
      expect(currentMap.containsKey('Accept'), isTrue);
      final availableOptions =
          autocompleteOptions['add_headers'] ?? const <String>[];
      final filteredAfterAdd = filterMapKeySuggestions(
        availableOptions,
        currentMap,
        query: 'Ac',
        currentInput: 'Ac',
      );
      expect(filteredAfterAdd.contains('Accept'), isFalse);

      await tester.tap(keyField);
      await tester.pump();
      await tester.enterText(keyField, 'Ac');
      await tester.pumpAndSettle();
      expect(acceptOptionKey, findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('map_entry_add_headers_Accept_remove')),
      );
      await tester.pumpAndSettle();

      await tester.tap(keyField);
      await tester.pump();
      await tester.enterText(keyField, 'Ac');
      await tester.pumpAndSettle();
      expect(acceptOptionKey, findsOneWidget);
    });
  });

  group('list preference suggestions', () {
    testWidgets('hides already selected options for suggestions-only lists', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final preferencesModel = PreferencesModel();
      await preferencesModel.initializePreferences();
      await preferencesModel.preferences.subLangs.setValue(<String>[]);
      addTearDown(preferencesModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesModel>.value(
          value: preferencesModel,
          child: _buildLocalizedApp(
            const Scaffold(body: SafeArea(child: TestListPreferenceWidget())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('sub_langs_custom_input'));
      final listState = tester.state<PreferenceListControlState>(
        find.byType(PreferenceListControl),
      );

      List<String> snapshot() => listState.debugLastAutocompleteOptions();

      await tester.tap(inputFinder);
      await tester.enterText(inputFinder, 'en');
      await tester.pumpAndSettle();

      expect(snapshot(), contains('en'));

      final addButton = find.byKey(const ValueKey('sub_langs_custom_add'));
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sub_langs_chip_en')), findsOneWidget);

      await tester.tap(inputFinder);
      await tester.enterText(inputFinder, 'en');
      await tester.pumpAndSettle();

      expect(snapshot().contains('en'), isFalse);

      final stored = preferencesModel.preferences.subLangs.get('value');
      expect(stored, isA<List>());
      final List<dynamic> storedList = stored as List<dynamic>;
      expect(storedList.contains('en'), isTrue);

      await tester.tap(find.byKey(const ValueKey('sub_langs_delete_en')));
      await tester.pumpAndSettle();

      await tester.tap(inputFinder);
      await tester.enterText(inputFinder, '');
      await tester.pumpAndSettle();
      await tester.enterText(inputFinder, 'en');
      await tester.pumpAndSettle();

      expect(snapshot(), contains('en'));
    });
  });

  group('spinner preference behavior', () {
    testWidgets('cycles retries through integers and infinite sentinel', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final preferencesModel = PreferencesModel();
      await preferencesModel.initializePreferences();
      await preferencesModel.preferences.retries.setValue(2);
      addTearDown(preferencesModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesModel>.value(
          value: preferencesModel,
          child: _buildLocalizedApp(
            const Scaffold(
              body: SafeArea(child: TestSpinnerPreferenceWidget()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fieldFinder = find.byKey(const ValueKey('control_retries'));
      expect(fieldFinder, findsOneWidget);

      TextField resolveField() => tester.widget<TextField>(fieldFinder);
      expect(resolveField().controller!.text, '2');

      Future<void> tapDown() async {
        final downButton = find.descendant(
          of: fieldFinder,
          matching: find.byIcon(Icons.keyboard_arrow_down),
        );
        expect(downButton, findsOneWidget);
        await tester.tap(downButton);
        await tester.pumpAndSettle();
      }

      await tapDown();
      expect(resolveField().controller!.text, '1');

      await tapDown();
      expect(resolveField().controller!.text, '0');

      await tapDown();
      expect(resolveField().controller!.text.toLowerCase(), 'infinite');
      expect(
        preferencesModel.preferences.retries.get('value'),
        equals('infinite'),
      );

      final upButton = find.descendant(
        of: fieldFinder,
        matching: find.byIcon(Icons.keyboard_arrow_up),
      );
      expect(upButton, findsOneWidget);
      await tester.tap(upButton);
      await tester.pumpAndSettle();
      expect(resolveField().controller!.text, '0');
      expect(preferencesModel.preferences.retries.get('value'), equals(0));

      await tester.enterText(fieldFinder, 'infinite');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(resolveField().controller!.text.toLowerCase(), 'infinite');
      expect(
        preferencesModel.preferences.retries.get('value'),
        equals('infinite'),
      );

      await tester.enterText(fieldFinder, 'foo');
      await tester.pump();
      expect(resolveField().controller!.text.toLowerCase(), 'infinite');
      expect(
        preferencesModel.preferences.retries.get('value'),
        equals('infinite'),
      );
    });
  });

  group('sponsorblock preference widget', () {
    testWidgets('allows adding and removing custom categories', (
      WidgetTester tester,
    ) async {
      final preferencesModel = await _pumpSponsorblockPreferenceWidget(tester);
      const customValue = 'mycustom';

      expect(
        find.byKey(const ValueKey('sponsorblock_mark_chip_sponsor')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sponsorblock_mark_custom_input')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sponsorblock_mark_mode_text')),
        findsOneWidget,
      );

      final customInput = find.byKey(
        const ValueKey('sponsorblock_mark_custom_input'),
      );
      await tester.ensureVisible(customInput);
      await tester.enterText(customInput, customValue);

      final addButton = find.byKey(
        const ValueKey('sponsorblock_mark_custom_add'),
      );
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      final customChip = find.byKey(
        const ValueKey('sponsorblock_mark_chip_mycustom'),
      );
      expect(customChip, findsOneWidget);

      expect(
        _readSponsorblockSelection(preferencesModel),
        contains(customValue),
      );

      final removeButton = find.byKey(
        const ValueKey('sponsorblock_mark_delete_mycustom'),
      );
      expect(removeButton, findsOneWidget);
      await tester.ensureVisible(removeButton);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();

      expect(customChip, findsNothing);
      expect(
        _readSponsorblockSelection(preferencesModel),
        isNot(contains(customValue)),
      );
      expect(
        find.byKey(const ValueKey('sponsorblock_mark_delete_sponsor')),
        findsNothing,
      );
    });

    testWidgets('keeps custom chip when toggled off and allows reselection', (
      WidgetTester tester,
    ) async {
      final preferencesModel = await _pumpSponsorblockPreferenceWidget(tester);
      const customValue = 'mycustom';

      final customInput = find.byKey(
        const ValueKey('sponsorblock_mark_custom_input'),
      );
      await tester.ensureVisible(customInput);
      await tester.enterText(customInput, customValue);
      await tester.tap(
        find.byKey(const ValueKey('sponsorblock_mark_custom_add')),
      );
      await tester.pumpAndSettle();

      final customChip = find.byKey(
        const ValueKey('sponsorblock_mark_chip_mycustom'),
      );
      await tester.ensureVisible(customChip);
      expect(customChip, findsOneWidget);

      InputChip chip = tester.widget<InputChip>(customChip);
      expect(chip.selected, isTrue);
      expect(
        _readSponsorblockSelection(preferencesModel),
        contains(customValue),
      );

      await tester.tap(customChip);
      await tester.pumpAndSettle();

      chip = tester.widget<InputChip>(customChip);
      expect(chip.selected, isFalse);
      expect(
        _readSponsorblockSelection(preferencesModel),
        isNot(contains(customValue)),
      );

      await tester.tap(customChip);
      await tester.pumpAndSettle();

      chip = tester.widget<InputChip>(customChip);
      expect(chip.selected, isTrue);
      expect(
        _readSponsorblockSelection(preferencesModel),
        contains(customValue),
      );

      final removeButton = find.byKey(
        const ValueKey('sponsorblock_mark_delete_mycustom'),
      );
      await tester.ensureVisible(removeButton);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();

      expect(customChip, findsNothing);
      expect(
        _readSponsorblockSelection(preferencesModel),
        isNot(contains(customValue)),
      );
    });
  });

  group('output preference widget', () {
    Future<PreferencesModel> setUpModel() async {
      SharedPreferences.setMockInitialValues({});
      final preferencesModel = PreferencesModel();
      await preferencesModel.initializePreferences();
      await preferencesModel.preferences.output.setValue(<String>[
        'title',
        '-',
        'artist',
        '.',
        'ext',
      ]);
      return preferencesModel;
    }

    testWidgets('allows adding custom entries', (WidgetTester tester) async {
      final preferencesModel = await setUpModel();
      addTearDown(preferencesModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesModel>.value(
          value: preferencesModel,
          child: _buildLocalizedApp(
            const Scaffold(body: SafeArea(child: TestOutputPreferenceWidget())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('output_custom_input'));
      await tester.tap(inputFinder);
      await tester.pump();
      await tester.enterText(inputFinder, 'customvalue');

      await tester.tap(find.byKey(const ValueKey('output_custom_add')));
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(const ValueKey('output_chip_customvalue'));
      expect(chipFinder, findsOneWidget);

      final chipWidget = tester.widget<InputChip>(chipFinder);
      expect(chipWidget.isEnabled, isTrue);

      final stored = preferencesModel.preferences.output.get('value');
      expect(stored, isA<List>());
      final List<dynamic> storedList = stored as List<dynamic>;
      expect(storedList.contains('customvalue'), isTrue);
    });

    testWidgets('autocomplete inserts placeholder entries', (
      WidgetTester tester,
    ) async {
      final preferencesModel = await setUpModel();
      addTearDown(preferencesModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesModel>.value(
          value: preferencesModel,
          child: _buildLocalizedApp(
            const Scaffold(body: SafeArea(child: TestOutputPreferenceWidget())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('output_custom_input'));
      await tester.tap(inputFinder);
      await tester.pump();
      await tester.enterText(inputFinder, 'album');
      await tester.pumpAndSettle();

      final addButton = find.byKey(const ValueKey('output_custom_add'));
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(const ValueKey('output_chip_album'));
      expect(chipFinder, findsOneWidget);

      final chipWidget = tester.widget<InputChip>(chipFinder);
      expect(chipWidget.isEnabled, isTrue);

      final stored = preferencesModel.preferences.output.get('value');
      expect(stored, isA<List>());
      final List<dynamic> storedList = stored as List<dynamic>;
      expect(storedList.contains('album'), isTrue);
    });

    testWidgets('keeps focus and removes added placeholder from suggestions', (
      WidgetTester tester,
    ) async {
      final preferencesModel = await setUpModel();
      addTearDown(preferencesModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesModel>.value(
          value: preferencesModel,
          child: _buildLocalizedApp(
            const Scaffold(body: SafeArea(child: TestOutputPreferenceWidget())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('output_custom_input'));
      await tester.showKeyboard(inputFinder);
      await tester.enterText(inputFinder, 'id');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('output_autocomplete_option_id')),
        findsOneWidget,
      );

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(inputFinder);
      final focusNode = textField.focusNode;
      expect(focusNode?.hasPrimaryFocus ?? false, isTrue);

      await tester.showKeyboard(inputFinder);
      await tester.pump();

      final listState = tester.state<PreferenceListControlState>(
        find.byType(PreferenceListControl),
      );
      final options = listState.debugLastAutocompleteOptions();
      expect(options.isNotEmpty, isTrue);
      expect(options.contains('id'), isFalse);
      expect(
        find.byKey(const ValueKey('output_autocomplete_option_id')),
        findsNothing,
      );
    });
  });
}

const PreferenceControlBuilder _testControlBuilder = PreferenceControlBuilder();

class TestMapPreferenceWidget extends StatelessWidget {
  const TestMapPreferenceWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PreferencesModel>();
    final preference = model.preferences.addHeaders;
    final control = _testControlBuilder.build(
      context: context,
      preference: preference,
      languageOverride: model.effectiveLanguage,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (control.headerTrailing != null)
            Align(
              alignment: Alignment.centerRight,
              child: control.headerTrailing!,
            ),
          control.control,
        ],
      ),
    );
  }
}

class TestListPreferenceWidget extends StatelessWidget {
  const TestListPreferenceWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PreferencesModel>();
    final preference = model.preferences.subLangs;
    final control = _testControlBuilder.build(
      context: context,
      preference: preference,
      languageOverride: model.effectiveLanguage,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (control.headerTrailing != null)
            Align(
              alignment: Alignment.centerRight,
              child: control.headerTrailing!,
            ),
          control.control,
        ],
      ),
    );
  }
}

class TestSpinnerPreferenceWidget extends StatelessWidget {
  const TestSpinnerPreferenceWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PreferencesModel>();
    final preference = model.preferences.retries;
    final control = _testControlBuilder.build(
      context: context,
      preference: preference,
      languageOverride: model.effectiveLanguage,
    );

    return Padding(padding: const EdgeInsets.all(16), child: control.control);
  }
}

class TestSponsorblockPreferenceWidget extends StatelessWidget {
  const TestSponsorblockPreferenceWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PreferencesModel>();
    final preference = model.preferences.sponsorblockMark;
    final control = _testControlBuilder.build(
      context: context,
      preference: preference,
      languageOverride: model.effectiveLanguage,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (control.headerTrailing != null)
            Align(
              alignment: Alignment.centerRight,
              child: control.headerTrailing!,
            ),
          control.control,
        ],
      ),
    );
  }
}

class TestFormatPreferenceWidget extends StatelessWidget {
  const TestFormatPreferenceWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PreferencesModel>();
    final preference = model.preferences.format;
    final control = _testControlBuilder.build(
      context: context,
      preference: preference,
      languageOverride: model.effectiveLanguage,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (control.headerTrailing != null)
            Align(
              alignment: Alignment.centerRight,
              child: control.headerTrailing!,
            ),
          control.control,
        ],
      ),
    );
  }
}

class TestOutputPreferenceWidget extends StatelessWidget {
  const TestOutputPreferenceWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PreferencesModel>();
    final preference = model.preferences.output;
    final control = _testControlBuilder.build(
      context: context,
      preference: preference,
      languageOverride: model.effectiveLanguage,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (control.headerTrailing != null)
            Align(
              alignment: Alignment.centerRight,
              child: control.headerTrailing!,
            ),
          control.control,
        ],
      ),
    );
  }
}
