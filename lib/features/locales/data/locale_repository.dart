import 'package:jsonc/jsonc.dart' show jsoncDecode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';

class LocaleRepository {
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final assetPath = 'i18n/$localeCode.jsonc';
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      Map<String, dynamic> jsonData = jsoncDecode(jsonString);
      Map<String, String> stringMap = jsonData.map(
        (key, value) => MapEntry(key, value.toString().trim()),
      );
      stringMap.removeWhere((key, value) => value.trim().isEmpty);

      return stringMap;
    } catch (e) {
      debugPrint('Error loading localization for "$localeCode": $e');
      return {};
    }
  }
}
