import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:vidra/features/locales/domain/locale.dart';

void main() {
  group('Locale keys and strings', () {
    test('en.jsonc and es.jsonc contain all keys required by AppStringKey', () async {
      final enFile = File('i18n/en.jsonc');
      expect(enFile.existsSync(), isTrue);

      final enRaw = enFile.readAsStringSync();
      final enMap = (jsonc.decode(enRaw) as Map).cast<String, dynamic>().map(
            (k, v) => MapEntry(k, v.toString()),
          );

      final appStrings = AppStringKey();
      // Should not throw when asserting all keys present in en.jsonc
      await expectLater(
        appStrings.updateFromJson(enMap, assertAllKeysPresent: true),
        completes,
      );

      // Verify fatal error getters return non-empty strings
      expect(appStrings.feTitle, equals('Fatal System Error'));
      expect(
        appStrings.feMessage,
        equals(
          'The download engine failed to load after an update. Please restart the application.',
        ),
      );
      expect(appStrings.feRestartButton, equals('Restart Application'));
      expect(appStrings.feViewLogsButton, equals('View Logs'));

      // Verify es.jsonc
      final esFile = File('i18n/es.jsonc');
      expect(esFile.existsSync(), isTrue);
      final esRaw = esFile.readAsStringSync();
      final esMap = (jsonc.decode(esRaw) as Map).cast<String, dynamic>().map(
            (k, v) => MapEntry(k, v.toString()),
          );

      final esStrings = AppStringKey();
      await esStrings.updateFromJson(enMap);
      await esStrings.updateFromJson(esMap);

      expect(esStrings.feTitle, equals('Error fatal del sistema'));
      expect(
        esStrings.feMessage,
        equals(
          'El motor de descargas no pudo cargarse tras la actualización. Por favor, reinicia la aplicación.',
        ),
      );
      expect(esStrings.feRestartButton, equals('Reiniciar aplicación'));
      expect(esStrings.feViewLogsButton, equals('Ver registros'));
    });
  });
}
