import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/core/constants/languages.dart';
import 'package:vidra/core/constants/resolutions.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/settings/domain/download_option_formatters.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

void main() {
  group('Adversarial Tests: DownloadOptionFormatters', () {
    late AppStringKey locale;

    setUp(() async {
      locale = AppStringKey();
      await locale.updateFromJson({
        's_default': 'Default (Recommended)',
        's_best': 'Best Available',
      });
    });

    test('1. Constant Option Lists Integrity', () {
      expect(DownloadOptionFormatters.videoResolutionOptions.first, equals('defaultOption'));
      expect(DownloadOptionFormatters.videoResolutionOptions[1], equals('bestvideo'));
      expect(
        DownloadOptionFormatters.videoResolutionOptions.sublist(2),
        equals(videoResolutions),
      );

      expect(DownloadOptionFormatters.audioLanguageOptions.first, equals('defaultOption'));
      expect(DownloadOptionFormatters.audioLanguageOptions[1], equals('bestaudio'));
      expect(
        DownloadOptionFormatters.audioLanguageOptions.sublist(2),
        equals(languagesCodes),
      );
    });

    test('2. formatResolution - Standard, Special, and Adversarial / Invalid Inputs', () {
      // Special tokens
      expect(
        DownloadOptionFormatters.formatResolution('defaultOption', locale),
        equals('Default (Recommended)'),
      );
      expect(
        DownloadOptionFormatters.formatResolution('bestvideo', locale),
        equals('Best Available'),
      );

      // Known valid resolutions
      expect(
        DownloadOptionFormatters.formatResolution('1080', locale),
        equals('1080p Full HD'),
      );
      expect(
        DownloadOptionFormatters.formatResolution('2160', locale),
        equals('2160p 4K UHD'),
      );
      expect(
        DownloadOptionFormatters.formatResolution('4320', locale),
        equals('4320p 8K UHD'),
      );
      expect(
        DownloadOptionFormatters.formatResolution('720', locale),
        equals('720p HD'),
      );
      expect(
        DownloadOptionFormatters.formatResolution('144', locale),
        equals('144p'),
      );

      // Adversarial & invalid inputs: should safely return raw input without throwing
      expect(
        DownloadOptionFormatters.formatResolution('9999p', locale),
        equals('9999p'),
      );
      expect(
        DownloadOptionFormatters.formatResolution('', locale),
        equals(''),
      );
      expect(
        DownloadOptionFormatters.formatResolution('invalid_resolution', locale),
        equals('invalid_resolution'),
      );
      expect(
        DownloadOptionFormatters.formatResolution('!@#\$%^&*()', locale),
        equals('!@#\$%^&*()'),
      );
    });

    test('3. formatLanguage - Standard, Special, and Adversarial / Invalid Inputs', () {
      // Special tokens
      expect(
        DownloadOptionFormatters.formatLanguage('defaultOption', locale),
        equals('Default (Recommended)'),
      );
      expect(
        DownloadOptionFormatters.formatLanguage('bestaudio', locale),
        equals('Best Available'),
      );

      // Known valid languages
      expect(
        DownloadOptionFormatters.formatLanguage('es', locale),
        equals('es - Español'),
      );
      expect(
        DownloadOptionFormatters.formatLanguage('en', locale),
        equals('en - English'),
      );
      expect(
        DownloadOptionFormatters.formatLanguage('ja', locale),
        equals('ja - 日本語'),
      );

      // Adversarial & invalid codes: should safely format with fallback '$val - $val' without throwing
      expect(
        DownloadOptionFormatters.formatLanguage('xyz999', locale),
        equals('xyz999 - xyz999'),
      );
      expect(
        DownloadOptionFormatters.formatLanguage('', locale),
        equals(' - '),
      );
      expect(
        DownloadOptionFormatters.formatLanguage('invalid_lang_code', locale),
        equals('invalid_lang_code - invalid_lang_code'),
      );
      expect(
        DownloadOptionFormatters.formatLanguage('!@#', locale),
        equals('!@# - !@#'),
      );
    });

    test('4. resolveCurrentVideoVal - All branches & Edge Cases', () {
      // Bestvideo
      final optsBest = DownloadOptions(videoResolution: VideoOption.bestvideo);
      expect(DownloadOptionFormatters.resolveCurrentVideoVal(optsBest), equals('bestvideo'));

      // DefaultOption
      final optsDefault = DownloadOptions(videoResolution: VideoOption.defaultOption);
      expect(DownloadOptionFormatters.resolveCurrentVideoVal(optsDefault), equals('defaultOption'));

      // Valid resolution
      final opts1080 = DownloadOptions(
        videoResolution: VideoOption.resolution,
        videoResolutionValue: '1080',
      );
      expect(DownloadOptionFormatters.resolveCurrentVideoVal(opts1080), equals('1080'));

      final opts4320 = DownloadOptions(
        videoResolution: VideoOption.resolution,
        videoResolutionValue: '4320',
      );
      expect(DownloadOptionFormatters.resolveCurrentVideoVal(opts4320), equals('4320'));

      // Invalid resolution not in videoResolutions list -> fallback to 'defaultOption'
      final optsInvalid = DownloadOptions(
        videoResolution: VideoOption.resolution,
        videoResolutionValue: '99999',
      );
      expect(DownloadOptionFormatters.resolveCurrentVideoVal(optsInvalid), equals('defaultOption'));

      // Null resolution value -> fallback to 'defaultOption'
      final optsNull = DownloadOptions(
        videoResolution: VideoOption.resolution,
        videoResolutionValue: null,
      );
      expect(DownloadOptionFormatters.resolveCurrentVideoVal(optsNull), equals('defaultOption'));
    });

    test('5. resolveCurrentAudioVal - All branches & Edge Cases', () {
      // Bestaudio
      final optsBest = DownloadOptions(audioLanguage: AudioOption.bestaudio);
      expect(DownloadOptionFormatters.resolveCurrentAudioVal(optsBest), equals('bestaudio'));

      // DefaultOption
      final optsDefault = DownloadOptions(audioLanguage: AudioOption.defaultOption);
      expect(DownloadOptionFormatters.resolveCurrentAudioVal(optsDefault), equals('defaultOption'));

      // Valid language code
      final optsEs = DownloadOptions(
        audioLanguage: AudioOption.language,
        audioLanguageCode: 'es',
      );
      expect(DownloadOptionFormatters.resolveCurrentAudioVal(optsEs), equals('es'));

      final optsJa = DownloadOptions(
        audioLanguage: AudioOption.language,
        audioLanguageCode: 'ja',
      );
      expect(DownloadOptionFormatters.resolveCurrentAudioVal(optsJa), equals('ja'));

      // Invalid language code not in languagesCodes list -> fallback to 'defaultOption'
      final optsInvalid = DownloadOptions(
        audioLanguage: AudioOption.language,
        audioLanguageCode: 'non_existent_code',
      );
      expect(DownloadOptionFormatters.resolveCurrentAudioVal(optsInvalid), equals('defaultOption'));

      // Null language code -> fallback to 'defaultOption'
      final optsNull = DownloadOptions(
        audioLanguage: AudioOption.language,
        audioLanguageCode: null,
      );
      expect(DownloadOptionFormatters.resolveCurrentAudioVal(optsNull), equals('defaultOption'));
    });
  });
}
