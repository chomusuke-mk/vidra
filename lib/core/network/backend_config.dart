import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BackendConfig {
  BackendConfig({
    required this.name,
    required this.description,
    required this.baseUri,
    required this.apiBaseUri,
    required this.overviewSocketUri,
    required this.jobSocketBaseUri,
    required this.metadata,
    required this.timeout,
  });

  final String name;
  final String description;
  final Uri baseUri;
  final Uri apiBaseUri;
  final Uri overviewSocketUri;
  final Uri jobSocketBaseUri;
  final Map<String, dynamic> metadata;
  final Duration timeout;

  factory BackendConfig.fromEnv() {
    final env = dotenv;

    String require(String key) => _requireEnvValue(env, key);
    int requireInt(String key) => _parseInt(require(key), key);

    final scheme = require(_EnvKeys.scheme);
    final host = require(_EnvKeys.host);
    final port = requireInt(_EnvKeys.port);

    final basePath = require(_EnvKeys.basePath);
    final apiRoot = require(_EnvKeys.apiRoot);
    final wsOverviewPath = require(_EnvKeys.wsOverviewPath);
    final wsJobPath = require(_EnvKeys.wsJobPath);

    final metadataRaw = require(_EnvKeys.metadata);
    Map<String, dynamic> metadata = _parseMetadata(
      metadataRaw,
      _EnvKeys.metadata,
    );

    final description = require(_EnvKeys.description);
    if (!metadata.containsKey('description')) {
      metadata = {...metadata, 'description': description};
    }

    final timeoutSeconds = requireInt(_EnvKeys.timeoutSeconds);

    final baseSegments = _extractSegments(basePath);
    final baseUri = _buildUri(scheme, host, port, baseSegments);
    final apiBaseUri = _buildUri(scheme, host, port, [
      ...baseSegments,
      ..._extractSegments(apiRoot),
    ]);
    final wsScheme = scheme == 'https' ? 'wss' : 'ws';
    final overviewSocketUri = _buildUri(wsScheme, host, port, [
      ...baseSegments,
      ..._extractSegments(wsOverviewPath),
    ]);
    final jobSocketBaseUri = _ensureTrailingSlash(
      _buildUri(wsScheme, host, port, [
        ...baseSegments,
        ..._extractSegments(wsJobPath),
      ]),
    );

    final clampedTimeout = timeoutSeconds.clamp(1, 300);
    final timeoutSecondsInt = (clampedTimeout as num).toInt();

    return BackendConfig(
      name: require(_EnvKeys.name),
      description: description,
      baseUri: baseUri,
      apiBaseUri: _ensureTrailingSlash(apiBaseUri),
      overviewSocketUri: overviewSocketUri,
      jobSocketBaseUri: jobSocketBaseUri,
      metadata: metadata,
      timeout: Duration(seconds: timeoutSecondsInt),
    );
  }

  Uri apiEndpoint(String path, {Map<String, dynamic>? queryParameters}) {
    final sanitizedSegments = _extractSegments(path);
    final reference = sanitizedSegments.join('/');
    final resolved = reference.isEmpty
        ? apiBaseUri
        : apiBaseUri.resolve(reference);
    final query = _stringifyQuery(queryParameters);
    return query == null ? resolved : resolved.replace(queryParameters: query);
  }

  Uri overviewSocketEndpoint() => overviewSocketUri;

  Uri jobSocketEndpoint(String jobId) {
    final segments = _extractSegments(jobId);
    if (segments.isEmpty) {
      return jobSocketBaseUri;
    }
    final reference = segments.join('/');
    return jobSocketBaseUri.resolve(reference);
  }

  static List<String> _extractSegments(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return const [];
    }
    return trimmed
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
  }

  static Uri _buildUri(
    String scheme,
    String host,
    int port,
    List<String> pathSegments,
  ) {
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
      pathSegments: pathSegments,
    );
  }

  static Map<String, String>? _stringifyQuery(Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) {
      return null;
    }
    return query.map(
      (key, value) => MapEntry(key, value == null ? '' : value.toString()),
    );
  }

  static Uri _ensureTrailingSlash(Uri uri) {
    if (uri.path.isEmpty || uri.path.endsWith('/')) {
      return uri;
    }
    return uri.replace(path: '${uri.path}/');
  }

  static String _requireEnvValue(DotEnv env, String key) {
    final value = env.maybeGet(key);
    if (value == null) {
      throw StateError('Missing required environment variable "$key"');
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw StateError('Environment variable "$key" cannot be empty');
    }
    return trimmed;
  }

  static int _parseInt(String raw, String key) {
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw StateError('Environment variable "$key" must be an integer');
    }
    return parsed;
  }

  static Map<String, dynamic> _parseMetadata(String raw, String key) {
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw const FormatException('Metadata is not a JSON object');
    } on FormatException catch (error, stackTrace) {
      debugPrint('Failed to parse $key: $error');
      debugPrint(stackTrace.toString());
      throw StateError('Environment variable "$key" must be valid JSON');
    }
  }
}

class _EnvKeys {
  static const name = 'VIDRA_SERVER_NAME';
  static const description = 'VIDRA_SERVER_DESCRIPTION';
  static const scheme = 'VIDRA_SERVER_SCHEME';
  static const host = 'VIDRA_SERVER_HOST';
  static const port = 'VIDRA_SERVER_PORT';
  static const basePath = 'VIDRA_SERVER_BASE_PATH';
  static const apiRoot = 'VIDRA_SERVER_API_ROOT';
  static const wsOverviewPath = 'VIDRA_SERVER_WS_OVERVIEW_PATH';
  static const wsJobPath = 'VIDRA_SERVER_WS_JOB_PATH';
  static const metadata = 'VIDRA_SERVER_METADATA';
  static const timeoutSeconds = 'VIDRA_SERVER_TIMEOUT_SECONDS';
}
