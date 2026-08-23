import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:vidra/features/locales/domain/locale.dart';

void main() {
  group('Adversarial & Empirical Tests: Milestone 1 Localization', () {
    late File enFile;
    late File esFile;
    late Map<String, String> enMap;
    late Map<String, String> esMap;

    setUp(() {
      enFile = File('i18n/en.jsonc');
      esFile = File('i18n/es.jsonc');

      expect(enFile.existsSync(), isTrue, reason: 'en.jsonc must exist');
      expect(esFile.existsSync(), isTrue, reason: 'es.jsonc must exist');

      final enRaw = enFile.readAsStringSync();
      final esRaw = esFile.readAsStringSync();

      final dynamic enDecoded = jsonc.decode(enRaw);
      expect(enDecoded, isA<Map>(), reason: 'en.jsonc should decode to a Map');
      enMap = (enDecoded as Map).cast<String, dynamic>().map(
            (k, v) => MapEntry(k, v.toString()),
          );

      final dynamic esDecoded = jsonc.decode(esRaw);
      expect(esDecoded, isA<Map>(), reason: 'es.jsonc should decode to a Map');
      esMap = (esDecoded as Map).cast<String, dynamic>().map(
            (k, v) => MapEntry(k, v.toString()),
          );
    });

    test('1. JSONC Deserialization and Key Presence for New Keys', () {
      const requiredNewKeys = [
        'd_quick_settings',
        'qs_title',
        'qs_close',
        'qs_audio',
        'shw_overlay_denied_downloading',
        'p_optional',
        'tu_quick_settings',
        'tu_quick_settings_desc',
        'sd_app_engine',
        'sd_app_engine_connected',
        'sd_all_working_normally',
        'sd_app_engine_starting',
        'sd_app_engine_initializing',
        'sd_app_engine_reconnecting',
        'sd_app_engine_missing_permissions',
        'sd_app_engine_missing_resources',
        'sd_app_engine_error',
        'sd_state_ready',
        'sd_state_initializing',
        'sd_state_starting_backend',
        'sd_state_retrying',
        'sd_state_missing_permissions',
        'sd_state_missing_resources',
        'sd_state_fatal_error',
      ];

      for (final key in requiredNewKeys) {
        expect(
          enMap.containsKey(key),
          isTrue,
          reason: 'en.jsonc must contain new key $key',
        );
        expect(
          enMap[key],
          isNotNull,
          reason: 'en.jsonc[$key] must not be null',
        );
        expect(
          enMap[key]!.trim().isNotEmpty,
          isTrue,
          reason: 'en.jsonc[$key] must not be empty',
        );

        expect(
          esMap.containsKey(key),
          isTrue,
          reason: 'es.jsonc must contain new key $key',
        );
        expect(
          esMap[key],
          isNotNull,
          reason: 'es.jsonc[$key] must not be null',
        );
        expect(
          esMap[key]!.trim().isNotEmpty,
          isTrue,
          reason: 'es.jsonc[$key] must not be empty',
        );
      }

      // Expected values
      expect(enMap['d_quick_settings'], equals('Quick Settings'));
      expect(enMap['qs_title'], equals('Quick Settings'));
      expect(enMap['qs_close'], equals('Close'));
      expect(enMap['qs_audio'], equals('Audio'));
      expect(
        enMap['shw_overlay_denied_downloading'],
        equals('Overlay permission denied, downloading directly'),
      );
      expect(enMap['p_optional'], equals('Optional'));
      expect(enMap['tu_quick_settings'], equals('Quick Settings'));
      expect(
        enMap['tu_quick_settings_desc'],
        equals(
          'Open this menu to quickly adjust download options on the fly without leaving the main screen.',
        ),
      );
      expect(enMap['sd_app_engine'], equals('App Engine'));
      expect(enMap['sd_app_engine_connected'], equals('App Engine: Connected'));
      expect(enMap['sd_all_working_normally'], equals('Everything is running normally'));

      expect(esMap['d_quick_settings'], equals('Configuración rápida'));
      expect(esMap['qs_title'], equals('Configuración Rápida'));
      expect(esMap['qs_close'], equals('Cerrar'));
      expect(esMap['qs_audio'], equals('Audio'));
      expect(
        esMap['shw_overlay_denied_downloading'],
        equals('Permiso de superposición denegado, descargando directamente'),
      );
      expect(esMap['p_optional'], equals('Opcional'));
      expect(esMap['tu_quick_settings'], equals('Configuración rápida'));
      expect(
        esMap['tu_quick_settings_desc'],
        equals(
          'Abra este menú para ajustar rápidamente las opciones de descarga sobre la marcha sin salir de la pantalla principal.',
        ),
      );
      expect(esMap['sd_app_engine'], equals('Motor de la App'));
      expect(esMap['sd_app_engine_connected'], equals('Motor de la App: Conectado'));
      expect(esMap['sd_all_working_normally'], equals('Todo funciona con normalidad'));
    });

    test('2. AppStringKey Getters resolve new keys accurately in English and Spanish', () async {
      // English resolution
      final enStrings = AppStringKey();
      await enStrings.updateFromJson(enMap, assertAllKeysPresent: true);

      expect(enStrings.dQuickSettings, equals('Quick Settings'));
      expect(enStrings.qsTitle, equals('Quick Settings'));
      expect(enStrings.qsClose, equals('Close'));
      expect(enStrings.qsAudio, equals('Audio'));
      expect(
        enStrings.shwOverlayDeniedDownloading,
        equals('Overlay permission denied, downloading directly'),
      );
      expect(enStrings.pOptional, equals('Optional'));
      expect(enStrings.tuPPQuickSettings, equals('Quick Settings'));
      expect(
        enStrings.tuPPQuickSettingsDesc,
        equals(
          'Open this menu to quickly adjust download options on the fly without leaving the main screen.',
        ),
      );
      expect(enStrings.sdAppEngine, equals('App Engine'));
      expect(enStrings.sdAppEngineConnected, equals('App Engine: Connected'));
      expect(enStrings.sdAllWorkingNormally, equals('Everything is running normally'));

      // Spanish resolution (overlaying on top of base or direct)
      final esStrings = AppStringKey();
      await esStrings.updateFromJson(enMap);
      await esStrings.updateFromJson(esMap);

      expect(esStrings.dQuickSettings, equals('Configuración rápida'));
      expect(esStrings.qsTitle, equals('Configuración Rápida'));
      expect(esStrings.qsClose, equals('Cerrar'));
      expect(esStrings.qsAudio, equals('Audio'));
      expect(
        esStrings.shwOverlayDeniedDownloading,
        equals('Permiso de superposición denegado, descargando directamente'),
      );
      expect(esStrings.pOptional, equals('Opcional'));
      expect(esStrings.tuPPQuickSettings, equals('Configuración rápida'));
      expect(
        esStrings.tuPPQuickSettingsDesc,
        equals(
          'Abra este menú para ajustar rápidamente las opciones de descarga sobre la marcha sin salir de la pantalla principal.',
        ),
      );
      expect(esStrings.sdAppEngine, equals('Motor de la App'));
      expect(esStrings.sdAppEngineConnected, equals('Motor de la App: Conectado'));
      expect(esStrings.sdAllWorkingNormally, equals('Todo funciona con normalidad'));
    });

    test('3. updateFromJson with assertAllKeysPresent: true passes cleanly on en.jsonc', () async {
      final appStrings = AppStringKey();
      expect(
        () async => await appStrings.updateFromJson(enMap, assertAllKeysPresent: true),
        returnsNormally,
      );
    });

    test('4. Adversarial Edge Case: assertAllKeysPresent: true MUST throw if any key is missing', () async {
      const keysToTest = [
        'd_quick_settings',
        'qs_title',
        'qs_close',
        'qs_audio',
        'd_title',
        'fe_title',
        'tu_quick_settings',
        'tu_quick_settings_desc',
      ];

      for (final missingKey in keysToTest) {
        final incompleteMap = Map<String, String>.from(enMap)..remove(missingKey);
        final testAppStrings = AppStringKey();

        expect(
          () async => await testAppStrings.updateFromJson(
            incompleteMap,
            assertAllKeysPresent: true,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains(missingKey),
            ),
          ),
          reason: 'Should throw Exception with missing key: $missingKey',
        );
      }
    });

    test('5. Adversarial Edge Case: Uninitialized getters return empty string without null crash', () {
      final freshStrings = AppStringKey();
      expect(freshStrings.dQuickSettings, equals(''));
      expect(freshStrings.qsTitle, equals(''));
      expect(freshStrings.qsClose, equals(''));
      expect(freshStrings.qsAudio, equals(''));
      expect(freshStrings.tuPPQuickSettings, equals(''));
      expect(freshStrings.tuPPQuickSettingsDesc, equals(''));
    });

    test('6. Full Key Parity Verification across all keys and registry integrity', () {
      final appStrings = AppStringKey();
      // Serialization test
      final exportedJson = appStrings.toJson();
      expect(exportedJson, isA<Map<String, String>>());

      // Ensure every single key in enMap is loaded into toJson
      final loadedStrings = AppStringKey();
      loadedStrings.updateFromJson(enMap);
      final loadedJson = loadedStrings.toJson();
      for (final key in enMap.keys) {
        expect(loadedJson.containsKey(key), isTrue, reason: 'Key $key must be preserved in toJson()');
        expect(loadedJson[key], equals(enMap[key]));
      }

      // Check for duplicate keys in JSON files via raw string inspection
      final enRaw = enFile.readAsStringSync();
      final keyRegex = RegExp(r'"([a-zA-Z0-9_]+)"\s*:');
      final enKeysFound = keyRegex.allMatches(enRaw).map((m) => m.group(1)!).toList();
      final enUniqueKeys = enKeysFound.toSet();
      expect(enKeysFound.length, equals(enUniqueKeys.length), reason: 'en.jsonc must not have duplicate keys');

      final esRaw = esFile.readAsStringSync();
      final esKeysFound = keyRegex.allMatches(esRaw).map((m) => m.group(1)!).toList();
      final esUniqueKeys = esKeysFound.toSet();
      expect(esKeysFound.length, equals(esUniqueKeys.length), reason: 'es.jsonc must not have duplicate keys');
    });
  });
}
