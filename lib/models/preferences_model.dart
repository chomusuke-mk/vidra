import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/constants/languages.dart';
import 'package:vidra/data/preferences/preferences_registry.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/models/preference.dart';

class PreferencesModel extends ChangeNotifier {
  final Preferences preferences = Preferences();
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> initializePreferences({
    Map<String, PreferenceLocalization>? localizedPreferences,
  }) async {
    if (_initialized) return;
    final storage = await SharedPreferences.getInstance();
    await preferences.initializeAll(
      storage,
      localizedPreferences: localizedPreferences,
    );
    _initialized = true;
    notifyListeners();
  }

  Future<void> setPreferenceValue(Preference preference, Object value) async {
    await preference.setValue(value);
    notifyListeners();
  }

  bool get isDarkModeEnabled => preferences.isDarkTheme.getValue<bool>();

  String get effectiveLanguage {
    final stored = preferences.language.getValue<String>();
    if (_isSupportedLanguage(stored)) {
      return stored;
    }

    final defaultLanguage = preferences.language.getDefaultValue<String>();
    if (_isSupportedLanguage(defaultLanguage)) {
      return defaultLanguage;
    }

    return 'en';
  }

  bool _isSupportedLanguage(String? code) {
    if (code == null || code.isEmpty) {
      return false;
    }
    return languageOptions.contains(code);
  }
}
