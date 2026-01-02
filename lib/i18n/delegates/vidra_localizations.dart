import 'package:flutter/widgets.dart';

import '../i18n.dart';

/// Central localization bridge for translating backend keys into
/// user-facing strings on the Flutter side.
class VidraLocalizations {
  VidraLocalizations._(this._localeCode) : locale = Locale(_localeCode);

  final Locale locale;
  final String _localeCode;

  static VidraLocalizations of(BuildContext context) {
    final localizations = Localizations.of<VidraLocalizations>(
      context,
      VidraLocalizations,
    );
    assert(
      localizations != null,
      'VidraLocalizations not found in widget tree. Add VidraLocalizations.delegate.',
    );
    return localizations!;
  }

  static List<Locale> get supportedLocales => I18n.supportedLanguageCodes
      .map((code) => Locale(code))
      .toList(growable: false);

  static final LocalizationsDelegate<VidraLocalizations> delegate =
      const _VidraLocalizationsDelegate();

  String error(String key) {
    return I18n.translate(key, localeCode: _localeCode);
  }

  String ui(String key) {
    return I18n.translate(key, localeCode: _localeCode);
  }

  Map<String, String> errorBundle() {
    return _bundleForKeys(ErrorStringKey.values);
  }

  Map<String, String> uiBundle() {
    return _bundleForKeys(AppStringKey.values);
  }

  Map<String, String> _bundleForKeys(List<String> keys) {
    final merged = I18n.bundle(_localeCode);
    return Map<String, String>.fromEntries(
      keys.map(
        (key) => MapEntry(
          key,
          merged[key] ?? I18n.translate(key, localeCode: _localeCode),
        ),
      ),
    );
  }
}

class _VidraLocalizationsDelegate
    extends LocalizationsDelegate<VidraLocalizations> {
  const _VidraLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    final tag = _localeTag(locale);
    final normalized = I18n.normalizeLocaleCode(tag);
    return I18n.supportedLanguageCodes.contains(normalized);
  }

  @override
  Future<VidraLocalizations> load(Locale locale) async {
    final normalized = I18n.normalizeLocaleCode(_localeTag(locale));
    await I18n.ensureLocale(normalized);
    return VidraLocalizations._(normalized);
  }

  @override
  bool shouldReload(LocalizationsDelegate<VidraLocalizations> old) => false;
}

String _localeTag(Locale locale) {
  final buffer = StringBuffer(locale.languageCode.toLowerCase());
  final scriptCode = locale.scriptCode;
  if (scriptCode != null && scriptCode.isNotEmpty) {
    buffer.write('-${scriptCode.toLowerCase()}');
  }
  final countryCode = locale.countryCode;
  if (countryCode != null && countryCode.isNotEmpty) {
    buffer.write('-${countryCode.toLowerCase()}');
  }
  return buffer.toString();
}
