import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'dart:io';
import 'package:jsonc/jsonc.dart';

class MockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  MockLocaleRepository() {
    // Load real en.jsonc and es.jsonc and fr.jsonc from filesystem
    for (final code in ['en', 'es', 'fr', 'de', 'ja']) {
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

  void setCustomLocale(String code, Map<String, String> data) {
    _storage[code] = data;
  }

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    return _storage[localeCode] ?? {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocaleController Fallback Behavior', () {
    late MockLocaleRepository mockRepo;

    setUp(() {
      mockRepo = MockLocaleRepository();
    });

    test('initialization with non-English language lacking qs_* keys falls back to en values seamlessly', () async {
      mockRepo.setCustomLocale('fr_partial', {
        'd_download': 'Télécharger',
        'd_title': 'Accueil',
      });

      final frMap = await mockRepo.getLocaleStrings('fr_partial');
      expect(frMap.containsKey('qs_title'), isFalse);
      expect(frMap.containsKey('d_quick_settings'), isFalse);

      final controller = LocaleController(mockRepo, 'fr_partial');
      await controller.whenReady;

      final strings = controller.localeStrings;

      // Fallback keys should yield English values
      expect(strings.qsTitle, equals('Quick Settings'));
      expect(strings.dQuickSettings, equals('Quick Settings'));
      expect(strings.qsClose, equals('Close'));
      expect(strings.qsAudio, equals('Audio'));
      expect(strings.tuPPQuickSettings, equals('Quick Settings'));
      expect(
        strings.tuPPQuickSettingsDesc,
        equals(
          'Open this menu to quickly adjust download options on the fly without leaving the main screen.',
        ),
      );

      // Keys present in French should yield French values
      expect(strings.dDownload, equals(frMap['d_download']));
      expect(strings.dDownload, isNotEmpty);
      expect(strings.dDownload, isNot(equals('Download')));
    });

    test('switching between languages preserves fallback for missing keys and updates present keys', () async {
      mockRepo.setCustomLocale('de_partial', {
        'd_download': 'Herunterladen',
      });

      final controller = LocaleController(mockRepo, 'en');
      await controller.whenReady;

      expect(controller.localeStrings.qsTitle, equals('Quick Settings'));
      expect(controller.localeStrings.dQuickSettings, equals('Quick Settings'));
      expect(controller.localeStrings.tuPPQuickSettings, equals('Quick Settings'));

      // Switch to Spanish (which has all keys localized)
      controller.setLocale('es');
      // Wait a microtask / tick for async merge
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.localeStrings.qsTitle, equals('Configuración Rápida'));
      expect(controller.localeStrings.dQuickSettings, equals('Configuración rápida'));
      expect(controller.localeStrings.qsClose, equals('Cerrar'));
      expect(controller.localeStrings.qsAudio, equals('Audio'));
      expect(controller.localeStrings.tuPPQuickSettings, equals('Configuración rápida'));
      expect(
        controller.localeStrings.tuPPQuickSettingsDesc,
        equals(
          'Abra este menú para ajustar rápidamente las opciones de descarga sobre la marcha sin salir de la pantalla principal.',
        ),
      );

      // Switch to de_partial (which lacks qs_* keys)
      controller.setLocale('de_partial');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // qs_* and tu_* falls back to English
      expect(controller.localeStrings.qsTitle, equals('Quick Settings'));
      expect(controller.localeStrings.dQuickSettings, equals('Quick Settings'));
      expect(controller.localeStrings.qsClose, equals('Close'));
      expect(controller.localeStrings.qsAudio, equals('Audio'));
      expect(controller.localeStrings.tuPPQuickSettings, equals('Quick Settings'));
      expect(
        controller.localeStrings.tuPPQuickSettingsDesc,
        equals(
          'Open this menu to quickly adjust download options on the fly without leaving the main screen.',
        ),
      );

      // de keys are used where available
      final deMap = await mockRepo.getLocaleStrings('de_partial');
      expect(controller.localeStrings.dDownload, equals(deMap['d_download']));
    });

    test('completely empty or missing language gracefully retains all English fallback strings without throwing', () async {
      mockRepo.setCustomLocale('xx_missing', {});

      final controller = LocaleController(mockRepo, 'xx_missing');
      await expectLater(controller.whenReady, completes);

      expect(controller.localeStrings.qsTitle, equals('Quick Settings'));
      expect(controller.localeStrings.dQuickSettings, equals('Quick Settings'));
      expect(controller.localeStrings.dTitle, equals('Home'));
    });
  });
}
