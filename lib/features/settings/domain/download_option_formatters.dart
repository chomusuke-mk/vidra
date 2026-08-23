import 'package:vidra/core/constants/languages.dart';
import 'package:vidra/core/constants/resolutions.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

class DownloadOptionFormatters {
  static const List<String> videoResolutionOptions = [
    'defaultOption',
    'bestvideo',
    ...videoResolutions,
  ];

  static const List<String> audioLanguageOptions = [
    'defaultOption',
    'bestaudio',
    ...languagesCodes,
  ];

  static String formatResolution(String val, AppStringKey locale) {
    if (val == 'defaultOption') return locale.sDefault;
    if (val == 'bestvideo') return locale.sBest;
    return resolutionLabels[val] ?? val;
  }

  static String formatLanguage(String val, AppStringKey locale) {
    if (val == 'defaultOption') return locale.sDefault;
    if (val == 'bestaudio') return locale.sBest;
    final name = languagesEndonyms[val] ?? val;
    return '$val - $name';
  }

  static String resolveCurrentVideoVal(DownloadOptions opts) {
    if (opts.videoResolution == VideoOption.bestvideo) return 'bestvideo';
    if (opts.videoResolution == VideoOption.resolution &&
        opts.videoResolutionValue != null &&
        videoResolutions.contains(opts.videoResolutionValue)) {
      return opts.videoResolutionValue!;
    }
    return 'defaultOption';
  }

  static String resolveCurrentAudioVal(DownloadOptions opts) {
    if (opts.audioLanguage == AudioOption.bestaudio) return 'bestaudio';
    if (opts.audioLanguage == AudioOption.language &&
        opts.audioLanguageCode != null &&
        languagesCodes.contains(opts.audioLanguageCode)) {
      return opts.audioLanguageCode!;
    }
    return 'defaultOption';
  }
}
