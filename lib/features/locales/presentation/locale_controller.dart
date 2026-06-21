import 'package:flutter/material.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/domain/locale.dart';

class LocaleController extends ChangeNotifier {
  final LocaleRepository _repository;
  final AppStringKey _localeStrings = AppStringKey();

  late String _currentLocaleCode;

  Map<String, String> _fallbackCache = {};
  static const String _fallbackCode = 'en';

  AppStringKey get localeStrings => _localeStrings;
  String get currentLocaleCode => _currentLocaleCode;

  LocaleController(this._repository, String initialLocale) {
    _currentLocaleCode = initialLocale;
    _init();
  }

  Future<void> _init() async {
    // 1. Cargamos el fallback ('en') a memoria una sola vez en el ciclo de vida de la app.
    _fallbackCache = await _repository.getLocaleStrings(_fallbackCode);

    // 2. Si el idioma guardado es inglés, terminamos aquí.
    if (_currentLocaleCode == _fallbackCode) {
      await _localeStrings.updateFromJson(
        _fallbackCache,
        // todo: poner en true
        assertAllKeysPresent: true,
      );
      notifyListeners();
      return;
    }

    // 3. Si es otro idioma, lo cargamos y fusionamos.
    await _loadAndMerge(_currentLocaleCode);
  }

  Future<void> _loadAndMerge(String targetLocale) async {
    final targetStrings = await _repository.getLocaleStrings(targetLocale);

    // El secreto perezoso: Clonamos el caché en inglés y le inyectamos el nuevo idioma.
    // Lo que falte en targetStrings se quedará automáticamente en inglés.
    final merged = Map<String, String>.from(_fallbackCache)
      ..addAll(targetStrings);

    // Al pasar el mapa fusionado completo, sobrescribimos todo rastro del idioma anterior.
    await _localeStrings.updateFromJson(merged);
    notifyListeners();
  }

  void setLocale(String localeCode) async {
    if (localeCode == _currentLocaleCode) return;

    _currentLocaleCode = localeCode;

    if (localeCode == _fallbackCode) {
      // Si vuelve a inglés, usamos el caché instantáneamente (Cero demoras)
      await _localeStrings.updateFromJson(_fallbackCache);
      notifyListeners();
    } else {
      // Si cambia a otro idioma, descargamos y fusionamos
      await _loadAndMerge(localeCode);
    }
  }
}
