import 'dart:collection';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalizedText {
  final Map<String, String> texts;

  LocalizedText([Map<String, String>? texts])
    : texts = UnmodifiableMapView(texts ?? {});

  String get(String locale, {String? fallbackLocale}) {
    if (texts.containsKey(locale)) return texts[locale]!;
    if (fallbackLocale != null && texts.containsKey(fallbackLocale)) {
      return texts[fallbackLocale]!;
    }
    if (texts.containsKey('en')) return texts['en']!;
    return texts.isNotEmpty ? texts.values.first : '';
  }

  Map<String, String> toMap() => Map<String, String>.from(texts);
}

class Preference {
  Preference({
    required this.key,
    required Object defaultValue,
    required List<Type> allowedTypes,
    Map<String, String>? name,
    Map<String, String>? description,
  }) : _allowedTypes = allowedTypes,
       _defaultValueLiteral = defaultValue is Object? Function()
           ? null
           : defaultValue,
       _defaultValueBuilder = defaultValue is Object? Function()
           ? defaultValue
           : null,
       _value = defaultValue is Object? Function()
           ? _uninitialized
           : defaultValue {
    if (_defaultValueBuilder == null) {
      _assertAllowedType(_defaultValueLiteral!);
    }
    this.name = LocalizedText(name ?? <String, String>{'en': key});
    this.description = LocalizedText(description);
  }

  final String key;
  static const Object _uninitialized = Object();

  final List<Type> _allowedTypes;
  final Object? _defaultValueLiteral;
  final Object? Function()? _defaultValueBuilder;
  SharedPreferences? _storage;
  Object? _value;
  Object? _resolvedDefaultValue;
  bool _defaultResolved = false;
  late LocalizedText name;
  late LocalizedText description;

  Type get currentType {
    _ensureValueInitialized();
    return _value!.runtimeType;
  }

  Object? get(String property, [String locale = 'en', String? fallbackLocale]) {
    switch (property.toLowerCase()) {
      case 'key':
        return key;
      case 'value':
        _ensureValueInitialized();
        return _value;
      case 'name':
        return name.get(locale, fallbackLocale: fallbackLocale);
      case 'description':
        return description.get(locale, fallbackLocale: fallbackLocale);
      default:
        throw ArgumentError('Unknown property: $property');
    }
  }

  void applyLocalization({
    Map<String, String>? nameTexts,
    Map<String, String>? descriptionTexts,
  }) {
    if (nameTexts != null && nameTexts.isNotEmpty) {
      name = LocalizedText(nameTexts);
    }
    if (descriptionTexts != null && descriptionTexts.isNotEmpty) {
      description = LocalizedText(descriptionTexts);
    }
  }

  Future<void> setValue(Object newValue) async {
    if (_storage == null) {
      throw StateError(
        "Preference '$key' not initialized. Call initialize() first.",
      );
    }
    final newType = newValue.runtimeType;
    if (!isTypeAllowed(newType)) {
      throw ArgumentError(
        "For key '$key': Value type $newType is not allowed. Allowed types: $_allowedTypes",
      );
    }
    bool success = false;
    if (newValue is String) {
      success = await _storage!.setString(key, newValue);
    } else if (newValue is int) {
      success = await _storage!.setInt(key, newValue);
    } else if (newValue is double) {
      success = await _storage!.setDouble(key, newValue);
    } else if (newValue is bool) {
      success = await _storage!.setBool(key, newValue);
    } else if (newValue is List<String>) {
      success = await _storage!.setStringList(key, newValue);
    } else {
      final jsonString = jsonEncode(newValue);
      success = await _storage!.setString(key, jsonString);
    }
    if (!success) {
      throw Exception("Failed to save preference '$key' to storage.");
    }
    _value = newValue;
  }

  Future<void> initialize(SharedPreferences storage) async {
    _storage = storage;
    final loadedValue = storage.get(key);
    if (loadedValue == null) {
      _value = _resolveDefaultValue(cacheValue: true);
      return;
    }

    bool allowsMapStringValues() {
      return _allowedTypes.any((type) {
        final name = type.toString();
        return name == 'Map<String, String>' || name == 'Map<String,String>';
      });
    }

    bool allowsListStringValues() {
      return _allowedTypes.any((type) {
        final name = type.toString();
        return name == 'List<String>' || name == 'List<String>';
      });
    }

    Object normalizeComplexValue(Object value) {
      if (value is Map) {
        final normalized = value.map(
          (key, dynamic val) => MapEntry('$key', val),
        );
        if (allowsMapStringValues()) {
          return Map<String, String>.fromEntries(
            normalized.entries.map((entry) {
              final raw = entry.value;
              return MapEntry(entry.key, raw == null ? '' : raw.toString());
            }),
          );
        }
        return Map<String, dynamic>.from(normalized);
      }
      if (value is List) {
        if (allowsListStringValues()) {
          return List<String>.from(
            value.map((item) => item == null ? '' : item.toString()),
          );
        }
        return List<dynamic>.from(value);
      }
      return value;
    }

    Object savedValue;
    if (loadedValue is String) {
      final hasComplexType = _allowedTypes.any((type) {
        if (type == List || type == Map) {
          return true;
        }
        final name = type.toString();
        return name.startsWith('List<') || name.startsWith('Map<');
      });
      if (hasComplexType) {
        try {
          savedValue = jsonDecode(loadedValue);
        } catch (_) {
          savedValue = loadedValue;
        }
      } else {
        savedValue = loadedValue;
      }
    } else {
      savedValue = loadedValue;
    }

    savedValue = normalizeComplexValue(savedValue);
    final loadedType = savedValue.runtimeType;
    if (!isTypeAllowed(loadedType)) {
      storage.remove(key);
      return;
    }
    _value = savedValue;
  }

  bool isTypeAllowed(dynamic typeOrInstance) {
    String typeName;
    Type? typeObj;

    if (typeOrInstance is Type) {
      typeName = typeOrInstance.toString();
      typeObj = typeOrInstance;
    } else if (typeOrInstance is String) {
      typeName = typeOrInstance;
      typeObj = null;
    } else {
      typeName = typeOrInstance.runtimeType.toString();
      typeObj = typeOrInstance.runtimeType;
    }

    String normalizeTypeName(String name) {
      var clean = name;
      if (clean.startsWith('_')) {
        clean = clean.substring(1);
      }

      final genericIndex = clean.indexOf('<');
      final base = genericIndex == -1
          ? clean
          : clean.substring(0, genericIndex);
      final suffix = genericIndex == -1 ? '' : clean.substring(genericIndex);

      if (base.contains('List')) {
        return 'List$suffix';
      }
      if (base.contains('Map')) {
        return 'Map$suffix';
      }

      return clean;
    }

    String? extractGenerics(String name) {
      final start = name.indexOf('<');
      if (start == -1) {
        return null;
      }
      final end = name.lastIndexOf('>');
      if (end <= start) {
        return null;
      }
      return name.substring(start + 1, end).replaceAll(' ', '');
    }

    bool isDynamicGenerics(String? generics) {
      if (generics == null || generics.isEmpty) {
        return true;
      }
      final parts = generics.split(',');
      return parts.every((part) {
        final trimmed = part.trim();
        return trimmed.isEmpty || trimmed == 'dynamic';
      });
    }

    bool hasMatchingCollectionSignature(
      String normalized,
      String allowed,
      String keyword,
    ) {
      if (!normalized.startsWith(keyword) || !allowed.startsWith(keyword)) {
        return false;
      }
      final normalizedGenerics = extractGenerics(normalized);
      final allowedGenerics = extractGenerics(allowed);
      if (allowedGenerics == null || allowedGenerics.isEmpty) {
        return true;
      }
      if (isDynamicGenerics(normalizedGenerics)) {
        return true;
      }
      return normalizedGenerics == allowedGenerics;
    }

    final normalizedTypeName = normalizeTypeName(typeName);

    for (final allowed in _allowedTypes) {
      final allowedName = normalizeTypeName(allowed.toString());
      if (typeObj != null && allowed == typeObj) {
        return true;
      }
      if (allowedName == normalizedTypeName) {
        return true;
      }
      if (hasMatchingCollectionSignature(
        normalizedTypeName,
        allowedName,
        'List',
      )) {
        return true;
      }
      if (hasMatchingCollectionSignature(
        normalizedTypeName,
        allowedName,
        'Map',
      )) {
        return true;
      }
    }

    if (typeObj == null) {
      return false;
    }

    return false;
  }

  T getValue<T>() {
    _ensureValueInitialized();
    switch (_value) {
      case T value:
        return value;
      default:
        throw TypeError();
    }
  }

  T getDefaultValue<T>() {
    final resolved = _resolveDefaultValue();
    switch (resolved) {
      case T value:
        return value;
      default:
        throw TypeError();
    }
  }

  void _ensureValueInitialized() {
    if (!identical(_value, _uninitialized)) {
      return;
    }
    _value = _resolveDefaultValue(cacheValue: true);
  }

  Object _resolveDefaultValue({bool cacheValue = false}) {
    if (_defaultResolved) {
      final resolved = _resolvedDefaultValue!;
      if (cacheValue) {
        _value = resolved;
      }
      return resolved;
    }

    Object? candidate;
    if (_defaultValueBuilder != null) {
      candidate = _defaultValueBuilder.call();
    } else if (_defaultValueLiteral != null) {
      candidate = _defaultValueLiteral;
    }
    if (candidate == null) {
      throw StateError(
        "Default value builder for '$key' returned null, which is not allowed.",
      );
    }
    final resolved = candidate;
    _assertAllowedType(resolved);
    _resolvedDefaultValue = resolved;
    _defaultResolved = true;
    if (cacheValue) {
      _value = resolved;
    }
    return resolved;
  }

  void _assertAllowedType(Object value) {
    final defaultType = value.runtimeType;
    if (!isTypeAllowed(defaultType)) {
      throw ArgumentError(
        "Default value type $defaultType is not in $_allowedTypes",
      );
    }
  }
}
