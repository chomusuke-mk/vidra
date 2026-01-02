import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

String? _cachedToken;

Future<String> loadTestAuthToken() async {
  final cached = _cachedToken;
  if (cached != null && cached.isNotEmpty) {
    return cached;
  }
  final envToken = _sanitize(Platform.environment['VIDRA_SERVER_TOKEN']);
  if (envToken != null && envToken.isNotEmpty) {
    _cachedToken = envToken;
    return envToken;
  }
  if (!dotenv.isInitialized) {
    await dotenv.load(fileName: '.env');
  }
  final fileToken = _sanitize(dotenv.maybeGet('VIDRA_SERVER_TOKEN'));
  if (fileToken == null || fileToken.isEmpty) {
    throw StateError(
      'VIDRA_SERVER_TOKEN is required for tests. Set the environment variable or add it to .env.',
    );
  }
  _cachedToken = fileToken;
  return fileToken;
}

String? _sanitize(String? raw) {
  if (raw == null) {
    return null;
  }
  var trimmed = raw.trim();
  if (trimmed.length >= 2) {
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }
  }
  return trimmed;
}
