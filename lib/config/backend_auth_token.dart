import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BackendAuthToken {
  BackendAuthToken._(this.value);

  final String value;

  static BackendAuthToken resolve(DotEnv env) {
    if (kReleaseMode) {
      return BackendAuthToken._(_generateRandom());
    }
    final raw = env.maybeGet(_tokenKey)?.trim();
    if (raw == null || raw.isEmpty) {
      throw StateError(
        'Environment variable "$_tokenKey" is required in debug builds.',
      );
    }
    return BackendAuthToken._(raw);
  }

  static String _generateRandom([int length = 48]) {
    final random = _secureRandom();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

const String _tokenKey = 'VIDRA_SERVER_TOKEN';

Random _secureRandom() {
  try {
    return Random.secure();
  } catch (_) {
    return Random();
  }
}
