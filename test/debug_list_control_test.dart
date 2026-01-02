import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/ui/widgets/preferences/preference_control_builder.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await I18n.preloadAll();
  });

  testWidgets('debug format preference tree', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final model = PreferencesModel();
    await model.initializePreferences();
    await model.setPreferenceValue(model.preferences.language, 'es');
    await model.preferences.format.setValue(<String>[]);
    addTearDown(model.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<PreferencesModel>.value(
        value: model,
        child: _buildLocalizedApp(
          const Scaffold(body: SafeArea(child: _DebugFormatWidget())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('format_custom_input')), findsOneWidget);
  });

  testWidgets('debug sponsorblock custom chip', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final model = PreferencesModel();
    await model.initializePreferences();
    await model.setPreferenceValue(model.preferences.language, 'es');
    addTearDown(model.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<PreferencesModel>.value(
        value: model,
        child: _buildLocalizedApp(
          const Scaffold(body: SafeArea(child: _DebugSponsorblockWidget())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inputFinder = find.byKey(
      const ValueKey('sponsorblock_mark_custom_input'),
    );
    await tester.enterText(inputFinder, 'mycustom');
    await tester.tap(
      find.byKey(const ValueKey('sponsorblock_mark_custom_add')),
    );
    await tester.pumpAndSettle();

    final chipFinder = find.byKey(
      const ValueKey('sponsorblock_mark_chip_mycustom'),
    );
    await tester.ensureVisible(chipFinder);
    expect(chipFinder, findsOneWidget);
    final chip = tester.widget<InputChip>(chipFinder);
    expect(chip.selected, isTrue);
  });
}

class _DebugFormatWidget extends StatelessWidget {
  const _DebugFormatWidget();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PreferencesModel>();
    final preference = model.preferences.format;
    final builder = const PreferenceControlBuilder();
    final control = builder.build(
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

class _DebugSponsorblockWidget extends StatelessWidget {
  const _DebugSponsorblockWidget();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PreferencesModel>();
    final preference = model.preferences.sponsorblockMark;
    final builder = const PreferenceControlBuilder();
    final control = builder.build(
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
