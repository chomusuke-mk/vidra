import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/ui/screens/settings/settings_screen.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await I18n.preloadAll();
  });

  Future<void> runWithoutLayoutLogs(Future<void> Function() body) async {
    final DebugPrintCallback originalCallback = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null) {
        return;
      }
      final normalized = message.trimLeft();
      const suppressedPrefixes = [
        '_alignControl',
        'PreferenceTile',
        'controlsRow',
        'addField',
        'chip ',
      ];
      if (suppressedPrefixes.any(normalized.startsWith)) {
        return;
      }
      const suppressedFragments = [' width=', ' maxWidth=', ' constraints='];
      if (suppressedFragments.any(normalized.contains)) {
        return;
      }
      originalCallback(message, wrapWidth: wrapWidth);
    };

    try {
      await body();
    } finally {
      debugPrint = originalCallback;
    }
  }

  void silentTestWidgets(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      await runWithoutLayoutLogs(() => body(tester));
    });
  }

  group('SettingsScreen', () {
    FlutterExceptionHandler? originalOnError;
    late PreferencesModel preferencesModel;

    setUpAll(() {
      originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        FlutterError.dumpErrorToConsole(details, forceReport: true);
        originalOnError?.call(details);
      };
    });

    tearDownAll(() {
      FlutterError.onError = originalOnError;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferencesModel = PreferencesModel();
      await preferencesModel.initializePreferences();
      await preferencesModel.setPreferenceValue(
        preferencesModel.preferences.language,
        'es',
      );
    });

    tearDown(() {
      preferencesModel.dispose();
    });

    Widget createTestWidget() {
      final locale = _localeFromCode(preferencesModel.effectiveLanguage);
      return ChangeNotifierProvider<PreferencesModel>.value(
        value: preferencesModel,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: [
            VidraLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            LocaleNamesLocalizationsDelegate(),
          ],
          supportedLocales: VidraLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      );
    }

    Future<void> navigateTo(String labelKey, WidgetTester tester) async {
      final label = resolveAppString(
        labelKey,
        preferencesModel.effectiveLanguage,
      );
      Finder target = find.text(label);
      if (target.evaluate().isEmpty) {
        final tooltipFinder = find.byTooltip(label);
        expect(
          tooltipFinder,
          findsOneWidget,
          reason: 'No navigation tab found for $label',
        );
        target = find.descendant(
          of: tooltipFinder,
          matching: find.byType(Icon),
        );
      }
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<Finder> ensureControlVisible(String key, WidgetTester tester) async {
      final finder = find.byKey(ValueKey(key));
      final scrollableList = find.byType(Scrollable);
      if (scrollableList.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: scrollableList.first,
        );
      }
      await tester.pumpAndSettle();
      expect(finder, findsOneWidget);
      return finder;
    }

    silentTestWidgets('shows key general preferences', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tile_theme_dark')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile_language')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile_font_size')), findsOneWidget);
    });

    silentTestWidgets('navigates to Network section', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tile_proxy')), findsNothing);

      await navigateTo(AppStringKey.network, tester);

      expect(find.byKey(const ValueKey('tile_proxy')), findsOneWidget);
    });

    silentTestWidgets('navigates to Video section', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('tile_video_multistreams')),
        findsNothing,
      );

      await navigateTo(AppStringKey.video, tester);

      expect(
        find.byKey(const ValueKey('tile_video_multistreams')),
        findsOneWidget,
      );
    });

    silentTestWidgets('navigates to Download section', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tile_output')), findsNothing);

      await navigateTo(AppStringKey.downloadSection, tester);

      expect(find.byKey(const ValueKey('tile_output')), findsOneWidget);
    });

    silentTestWidgets('toggles dark theme preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final switchFinder = await ensureControlVisible(
        'control_theme_dark_switch',
        tester,
      );
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(preferencesModel.preferences.isDarkTheme.getValue<bool>(), isTrue);
    });

    silentTestWidgets('changes language preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final dropdownFinder = await ensureControlVisible(
        'control_language',
        tester,
      );
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      final searchField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Buscar',
      );
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'English');
      await tester.pumpAndSettle();

      final englishOption = find.widgetWithText(ListTile, 'English');
      expect(englishOption, findsOneWidget);
      await tester.tap(englishOption);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.language.getValue<String>(),
        equals('en'),
      );
    });

    silentTestWidgets('updates font size preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final dropdownFinder = await ensureControlVisible(
        'control_font_size',
        tester,
      );
      final fieldFinder = find.descendant(
        of: dropdownFinder,
        matching: find.byType(EditableText),
      );
      await tester.tap(fieldFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('18').last);
      await tester.pumpAndSettle();

      expect(preferencesModel.preferences.fontSize.getValue<int>(), equals(18));
    });

    silentTestWidgets('toggles wait for video preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final switchFinder = await ensureControlVisible(
        'control_wait_for_video_switch',
        tester,
      );
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.waitForVideo.getValue<int>(),
        equals(0),
      );
      expect(
        find.byKey(const ValueKey('control_wait_for_video')),
        findsOneWidget,
      );
    });

    silentTestWidgets('updates proxy text preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.network, tester);

      final proxyField = await ensureControlVisible('control_proxy', tester);

      await tester.enterText(proxyField, 'http://proxy:8080');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.proxy.getValue<String?>(),
        equals('http://proxy:8080'),
      );
    });

    silentTestWidgets('updates socket timeout integer preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.network, tester);

      final timeoutField = await ensureControlVisible(
        'control_socket_timeout',
        tester,
      );

      await tester.enterText(timeoutField, '30');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.socketTimeout.getValue<int>(),
        equals(30),
      );
    });

    silentTestWidgets('toggles enable file urls preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.network, tester);

      final switchFinder = await ensureControlVisible(
        'control_enable_file_urls_switch',
        tester,
      );
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.enableFileUrls.getValue<bool>(),
        isTrue,
      );
    });

    silentTestWidgets('toggles prefer insecure preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.network, tester);

      final switchFinder = await ensureControlVisible(
        'control_prefer_insecure_switch',
        tester,
      );
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.preferInsecure.getValue<bool>(),
        isTrue,
      );
    });

    silentTestWidgets('updates merge output format preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.video, tester);

      final mergeDropdown = await ensureControlVisible(
        'control_merge_output_format',
        tester,
      );
      expect(
        preferencesModel.preferences.mergeOutputFormat.getValue<String?>(),
        equals('mkv'),
      );

      await preferencesModel.setPreferenceValue(
        preferencesModel.preferences.mergeOutputFormat,
        'mp4',
      );
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.mergeOutputFormat.getValue<String?>(),
        equals('mp4'),
      );
      expect(
        find.descendant(of: mergeDropdown, matching: find.text('mp4')),
        findsWidgets,
      );
    });

    silentTestWidgets('toggles video multistreams preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.video, tester);

      final switchFinder = await ensureControlVisible(
        'control_video_multistreams_switch',
        tester,
      );
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.videoMultistreams.getValue<bool>(),
        isFalse,
      );
    });

    silentTestWidgets('toggles audio multistreams preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.video, tester);

      final switchFinder = await ensureControlVisible(
        'control_audio_multistreams_switch',
        tester,
      );
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.audioMultistreams.getValue<bool>(),
        isFalse,
      );
    });

    silentTestWidgets('updates audio quality integer preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.video, tester);

      final audioQualityField = await ensureControlVisible(
        'control_audio_quality',
        tester,
      );

      await tester.enterText(audioQualityField, '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.audioQuality.getValue<int>(),
        equals(5),
      );
    });

    silentTestWidgets('updates output template preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      final outputField = await ensureControlVisible(
        'output_custom_input',
        tester,
      );
      await tester.tap(outputField);
      await tester.enterText(outputField, 'custom_output_value');

      final addButton = await ensureControlVisible('output_custom_add', tester);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      final storedOutput = preferencesModel.preferences.output.get('value');
      expect(storedOutput, isA<List>());
      expect(
        (storedOutput as List).cast<String>(),
        contains('custom_output_value'),
      );
      expect(
        find.byKey(const ValueKey('output_chip_custom_output_value')),
        findsOneWidget,
      );
    });

    silentTestWidgets('toggles playlist preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      final tileFinder = await ensureControlVisible('tile_playlist', tester);
      await tester.tap(tileFinder);
      await tester.pumpAndSettle();

      expect(preferencesModel.preferences.playlist.getValue<bool>(), isTrue);
    });

    silentTestWidgets('updates retries integer preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      final retriesField = await ensureControlVisible(
        'control_retries',
        tester,
      );

      await tester.enterText(retriesField, '3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(preferencesModel.preferences.retries.getValue<int>(), equals(3));
    });

    silentTestWidgets(
      'retries field shows spinner arrows when restricted to int',
      (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        await navigateTo(AppStringKey.downloadSection, tester);

        final retriesField = await ensureControlVisible(
          'control_retries',
          tester,
        );

        expect(retriesField, findsOneWidget);

        final controlScope = find.byKey(const ValueKey('control_retries'));
        expect(
          find.descendant(
            of: controlScope,
            matching: find.byIcon(Icons.keyboard_arrow_up),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: controlScope,
            matching: find.byIcon(Icons.keyboard_arrow_down),
          ),
          findsOneWidget,
        );
      },
    );

    silentTestWidgets('adjusts socket timeout using spinner arrows', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.network, tester);

      final timeoutField = await ensureControlVisible(
        'control_socket_timeout',
        tester,
      );

      await tester.enterText(timeoutField, '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final incrementButton = find.descendant(
        of: find.byKey(const ValueKey('control_socket_timeout')),
        matching: find.byIcon(Icons.keyboard_arrow_up),
      );
      await tester.tap(incrementButton);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.socketTimeout.getValue<int>(),
        equals(6),
      );

      final decrementButton = find.descendant(
        of: find.byKey(const ValueKey('control_socket_timeout')),
        matching: find.byIcon(Icons.keyboard_arrow_down),
      );
      await tester.tap(decrementButton);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.socketTimeout.getValue<int>(),
        equals(5),
      );
    });

    silentTestWidgets('toggles force overwrites preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      final switchFinder = await ensureControlVisible(
        'control_force_overwrites_switch',
        tester,
      );
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(
        preferencesModel.preferences.forceOverwrites.getValue<bool>(),
        isFalse,
      );
    });

    silentTestWidgets('updates sponsorblock mark preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.video, tester);

      final sponsorTile = await ensureControlVisible(
        'sponsorblock_mark_chip_sponsor',
        tester,
      );

      await tester.tap(sponsorTile);
      await tester.pumpAndSettle();

      final sponsorValue = preferencesModel.preferences.sponsorblockMark
          .getValue<List<String>>();
      expect(sponsorValue, isNot(contains('sponsor')));
    });

    silentTestWidgets('updates sponsorblock remove preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.video, tester);

      final sponsorTile = await ensureControlVisible(
        'sponsorblock_remove_chip_sponsor',
        tester,
      );

      await tester.tap(sponsorTile);
      await tester.pumpAndSettle();

      final sponsorValue = preferencesModel.preferences.sponsorblockRemove
          .getValue<List<String>>();
      expect(sponsorValue, contains('sponsor'));
    });

    silentTestWidgets('updates limit rate preference', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      final limitRateField = await ensureControlVisible(
        'control_limit_rate',
        tester,
      );

      await tester.enterText(limitRateField, '4.2M');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final limitRateValue = preferencesModel.preferences.limitRate
          .getValue<String>();
      expect(limitRateValue, equals('4.2M'));
    });

    silentTestWidgets('adds subtitle language via autocomplete entry', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.video, tester);

      final addField = await ensureControlVisible(
        'sub_langs_custom_input',
        tester,
      );
      await tester.tap(addField);
      await tester.pumpAndSettle();

      await tester.enterText(addField, 'es');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final stored = preferencesModel.preferences.subLangs.get('value');
      expect(stored, isA<List>());
      expect((stored as List).cast<String>(), contains('es'));
      expect(find.byKey(const ValueKey('sub_langs_chip_es')), findsOneWidget);
    });

    silentTestWidgets('hides output suggestion chips in list editor', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      await ensureControlVisible('output_chip_wrap', tester);
      expect(find.byKey(const ValueKey('output_chip_album')), findsNothing);
    });

    silentTestWidgets('adds path entry via map editor', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      final keyField = await ensureControlVisible('map_key_paths', tester);
      final valueField = await ensureControlVisible('map_value_paths', tester);

      await tester.enterText(keyField, 'home');
      await tester.enterText(valueField, '~/Downloads');

      final addButton = await ensureControlVisible('map_add_paths', tester);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      final stored = preferencesModel.preferences.paths.get('value');
      expect(stored, isA<Map>());
      expect((stored as Map)['home'], '~/Downloads');
    });

    silentTestWidgets('paths map editor stays in structured mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      expect(
        find.byKey(const ValueKey('map_mode_toggle_paths_text')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('map_key_paths')), findsOneWidget);
    });

    silentTestWidgets('add headers map editor toggles text mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.network, tester);

      final toTextToggle = await ensureControlVisible(
        'map_mode_toggle_add_headers_text',
        tester,
      );
      await tester.tap(toTextToggle);
      await tester.pumpAndSettle();

      final textField = find.byKey(const ValueKey('map_text_add_headers'));
      expect(textField, findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('map_mode_toggle_add_headers_map')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_key_add_headers')), findsOneWidget);
    });

    silentTestWidgets('output preference hides text mode toggle', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      expect(find.byKey(const ValueKey('output_mode_text')), findsNothing);
      expect(find.byKey(const ValueKey('output_custom_input')), findsOneWidget);
    });

    silentTestWidgets('output add field width capped on wide layout', (
      WidgetTester tester,
    ) async {
      final view = tester.view;
      view.physicalSize = const Size(1440, 900);
      view.devicePixelRatio = 1.0;
      addTearDown(() {
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      final addField = await ensureControlVisible(
        'output_custom_input',
        tester,
      );
      final width = tester.getSize(addField).width;
      expect(width, lessThanOrEqualTo(320));
    });

    silentTestWidgets('output list remains usable on narrow layout', (
      WidgetTester tester,
    ) async {
      final view = tester.view;
      view.physicalSize = const Size(390, 740); //360,740
      view.devicePixelRatio = 1.0;
      addTearDown(() {
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await navigateTo(AppStringKey.downloadSection, tester);

      final addField = await ensureControlVisible(
        'output_custom_input',
        tester,
      );
      await tester.enterText(addField, '%(title)s.%(ext)s');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final error = tester.takeException();
      if (error != null) {
        // ignore: avoid_print
        print('Encountered test exception: $error');
        if (error is FlutterError) {
          for (final _ in error.diagnostics) {
            // Intentionally left blank; iterate to surface diagnostic access when debugging locally.
          }
          // ignore: avoid_print
          //print(error.toStringDeep());
          //debugDumpRenderTree();
        }
      }
      expect(error, isNull);
      final rect = tester.getRect(addField);
      expect(rect.right, lessThanOrEqualTo(360));
    });
  });
}

Locale _localeFromCode(String code) {
  final safeCode = code.trim().isEmpty ? 'en' : code;
  final segments = safeCode
      .split(RegExp('[-_]'))
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) {
    return const Locale('en');
  }
  if (segments.length == 1) {
    return Locale(segments.first.toLowerCase());
  }
  if (segments.length == 2) {
    return Locale(segments[0].toLowerCase(), segments[1].toUpperCase());
  }
  return Locale.fromSubtags(
    languageCode: segments[0].toLowerCase(),
    scriptCode: segments[1],
    countryCode: segments[2].toUpperCase(),
  );
}
