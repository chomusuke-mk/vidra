import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

class SettingsRepository {
  final SharedPreferences _prefs;

  SettingsRepository(this._prefs);

  // Claves para guardar en la memoria del teléfono
  static const _keyLanguage = 'app_language';
  static const _keyTheme = 'app_theme';
  static const _keyDownloadOptions = 'app_download_options';

  // --- 1. Opciones Locales de la App ---

  String getAppLanguage() => _prefs.getString(_keyLanguage) ?? 'en';

  Future<void> saveAppLanguage(String lang) =>
      _prefs.setString(_keyLanguage, lang);

  ThemeMode getAppTheme() {
    // Guardamos el índice del enum para que sea fácil de recuperar
    final themeIndex = _prefs.getInt(_keyTheme);
    if (themeIndex == null) return ThemeMode.system;
    return ThemeMode.values[themeIndex];
  }

  Future<void> saveAppTheme(ThemeMode theme) =>
      _prefs.setInt(_keyTheme, theme.index);

  // --- 2. Opciones de Descarga (Payload) ---
  DownloadOptions getDownloadOptions() {
    final jsonString = _prefs.getString(_keyDownloadOptions);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
        return DownloadOptions.fromJson(jsonMap);
      } catch (e) {
        debugPrint('Error al leer las opciones de descarga: $e');
      }
    }
    return DownloadOptions();
  }

  Future<void> saveDownloadOptions(DownloadOptions options) async {
    final String jsonString = jsonEncode(options.toJson());
    await _prefs.setString(_keyDownloadOptions, jsonString);
  }
}
