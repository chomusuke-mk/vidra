import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/constants/backend_constants.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/i18n/i18n.dart' show I18n;

/// Thin HTTP client that speaks to the Python backend download endpoints.
class DownloadService {
  DownloadService(
    this.config, {
    String? authToken,
    http.Client? httpClient,
    String Function()? languageResolver,
  }) : _authToken = authToken?.trim(),
       _client = httpClient ?? http.Client(),
       _languageResolver = languageResolver ?? _defaultLanguageResolver;

  final BackendConfig config;
  String? _authToken;
  final http.Client _client;
  final String Function() _languageResolver;

  void updateAuthToken(String? authToken) {
    _authToken = authToken?.trim();
  }

  static const Set<int> _redirectStatusCodes = <int>{301, 302, 303, 307, 308};
  static const int _defaultMaxRedirects = 5;

  Future<DownloadJobModel> createJob(
    String url,
    Map<String, dynamic> options, {
    Map<String, dynamic>? metadata,
    String? owner,
  }) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw DownloadServiceException(
        400,
        'The download URL must not be empty.',
      );
    }
    final normalizedOwner = owner?.trim();
    final normalizedOptions = Map<String, dynamic>.from(options);
    final metadataPayload = metadata == null
        ? null
        : Map<String, dynamic>.from(metadata);
    final endpoint = config.apiEndpoint('jobs');
    final body = {
      'urls': trimmedUrl,
      'options': normalizedOptions,
      if (metadataPayload != null && metadataPayload.isNotEmpty)
        'metadata': metadataPayload,
      if (normalizedOwner != null && normalizedOwner.isNotEmpty)
        'owner': normalizedOwner,
    };
    final response = await _postWithRedirects(endpoint, jsonEncode(body));
    _throwIfNotSuccessful(response);
    final decoded = _decodeJsonBody(response);
    if (_looksLikeJobResponse(decoded)) {
      return DownloadJobModel.fromJson(decoded);
    }
    final jobId = decoded['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw DownloadServiceException(
        response.statusCode,
        _localize(AppStringKey.downloadServiceJobResponseMissingId),
      );
    }
    final createdAtRaw = decoded['created_at'] as String?;
    final statusRaw = decoded['status'] as String? ?? 'queued';
    final normalizedMetadata = <String, dynamic>{
      if (metadataPayload != null) ...metadataPayload,
      if (normalizedOwner != null && normalizedOwner.isNotEmpty)
        'owner': normalizedOwner,
    };
    final progressPayload = decoded['progress'];
    final placeholderJson = <String, dynamic>{
      'job_id': jobId,
      'status': statusRaw,
      'created_at': createdAtRaw ?? DateTime.now().toUtc().toIso8601String(),
      'urls': [trimmedUrl],
      'options': normalizedOptions,
      'metadata': normalizedMetadata,
      'creator': normalizedOwner,
      'progress': progressPayload is Map
          ? progressPayload.cast<String, dynamic>()
          : <String, dynamic>{
              'status': BackendJobStatus.starting,
              'stage': 'identifying',
            },
      'logs': const <Map<String, dynamic>>[],
    };
    return DownloadJobModel.fromJson(placeholderJson);
  }

  Future<Map<String, dynamic>?> previewUrl(
    String url,
    Map<String, dynamic> options,
  ) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw DownloadServiceException(
        400,
        _localize(AppStringKey.downloadServicePreviewUrlRequired),
      );
    }
    final endpoint = config.apiEndpoint('preview');
    final body = {
      'urls': trimmedUrl,
      'options': Map<String, dynamic>.from(options),
    };
    final response = await _postWithRedirects(endpoint, jsonEncode(body));
    _throwIfNotSuccessful(response);
    final decoded = _decodeJsonBody(response);
    final preview = decoded['preview'];
    if (preview is Map) {
      return preview.cast<String, dynamic>();
    }
    return null;
  }

  Future<List<DownloadJobModel>> listJobs() async {
    final endpoint = config.apiEndpoint('jobs');
    final response = await _getWithRedirects(endpoint);
    _throwIfNotSuccessful(response);
    final decoded = _decodeJsonBody(response);
    final rawJobs = decoded['jobs'] ?? decoded['value'];
    final Iterable<dynamic> jobList = rawJobs is List
        ? rawJobs
        : const <dynamic>[];
    return jobList
        .whereType<Map>()
        .map(
          (entry) => DownloadJobModel.fromJson(entry.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<DownloadJobModel?> getJob(String jobId) async {
    final endpoint = config.apiEndpoint('jobs/$jobId');
    final response = await _getWithRedirects(endpoint);
    if (response.statusCode == 404) {
      return null;
    }
    _throwIfNotSuccessful(response);
    final decoded = _decodeJsonBody(response);
    return DownloadJobModel.fromJson(decoded);
  }

  Future<Map<String, dynamic>> cancelJob(String jobId) async {
    final endpoint = config.apiEndpoint('jobs/$jobId/cancel');
    final response = await _postWithRedirects(
      endpoint,
      '',
      allowEmptyBody: true,
    );
    _throwIfNotSuccessful(response);
    return _decodeJsonBody(response);
  }

  Future<Map<String, dynamic>> pauseJob(String jobId) async {
    final endpoint = config.apiEndpoint('jobs/$jobId/pause');
    final response = await _postWithRedirects(
      endpoint,
      '',
      allowEmptyBody: true,
    );
    _throwIfNotSuccessful(response);
    return _decodeJsonBody(response);
  }

  Future<Map<String, dynamic>> resumeJob(String jobId) async {
    final endpoint = config.apiEndpoint('jobs/$jobId/resume');
    final response = await _postWithRedirects(
      endpoint,
      '',
      allowEmptyBody: true,
    );
    _throwIfNotSuccessful(response);
    return _decodeJsonBody(response);
  }

  Future<Map<String, dynamic>> retryJob(String jobId) async {
    final endpoint = config.apiEndpoint('jobs/$jobId/retry');
    final response = await _postWithRedirects(
      endpoint,
      '',
      allowEmptyBody: true,
    );
    _throwIfNotSuccessful(response);
    return _decodeJsonBody(response);
  }

  Future<Map<String, dynamic>> retryPlaylistEntries(
    String jobId, {
    Iterable<int>? indices,
    Iterable<String>? entryIds,
  }) async {
    final sanitizedId = jobId.trim();
    if (sanitizedId.isEmpty) {
      throw DownloadServiceException(
        400,
        _localize(AppStringKey.downloadServiceJobIdRequired),
      );
    }
    final payload = <String, dynamic>{};
    if (indices != null) {
      final normalized = indices
          .where((value) => value > 0)
          .toList(growable: false);
      if (normalized.isNotEmpty) {
        payload['indices'] = normalized;
      }
    }
    if (entryIds != null) {
      final normalized = entryIds
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (normalized.isNotEmpty) {
        payload['entry_ids'] = normalized;
      }
    }
    final endpoint = config.apiEndpoint('jobs/$sanitizedId/playlist/retry');
    final response = await _postWithRedirects(
      endpoint,
      jsonEncode(payload),
      allowEmptyBody: payload.isEmpty,
    );
    _throwIfNotSuccessful(response);
    return _decodeJsonBody(response);
  }

  Future<Map<String, dynamic>> deleteJob(String jobId) async {
    final endpoint = config.apiEndpoint('jobs/$jobId');
    final response = await _deleteWithRedirects(endpoint);
    _throwIfNotSuccessful(response);
    return _decodeJsonBody(response);
  }

  Future<Map<String, dynamic>> submitPlaylistSelection(
    String jobId, {
    Iterable<int>? indices,
  }) async {
    final endpoint = config.apiEndpoint('jobs/$jobId/playlist/selection');
    final payload = <String, dynamic>{};
    if (indices != null) {
      payload['indices'] = indices.toList();
    }
    final response = await _postWithRedirects(endpoint, jsonEncode(payload));
    _throwIfNotSuccessful(response);
    return _decodeJsonBody(response);
  }

  Future<DownloadPlaylistSnapshot?> fetchPlaylistSnapshot(
    String jobId, {
    bool includeEntries = false,
    int? offset,
    int? limit,
  }) async {
    final sanitizedId = jobId.trim();
    if (sanitizedId.isEmpty) {
      return null;
    }
    final query = <String, dynamic>{};
    if (offset != null && offset > 0) {
      query['offset'] = offset;
    }
    if (limit != null && limit > 0) {
      query['limit'] = limit;
    }
    Uri endpoint;
    if (includeEntries) {
      endpoint = config.apiEndpoint(
        'jobs/$sanitizedId/playlist/items',
        queryParameters: query.isEmpty ? null : query,
      );
    } else {
      endpoint = config.apiEndpoint(
        'jobs/$sanitizedId/playlist',
        queryParameters: query.isEmpty ? null : query,
      );
    }
    final response = await _getWithRedirects(endpoint);
    if (response.statusCode == 404) {
      return null;
    }
    _throwIfNotSuccessful(response);
    final decoded = _decodeJsonBody(response);
    final playlist = decoded['playlist'];
    if (playlist is! Map<String, dynamic>) {
      return null;
    }
    return DownloadPlaylistSnapshot.fromJson(decoded);
  }

  Future<DownloadPlaylistDeltaSnapshot?> fetchPlaylistDelta(
    String jobId, {
    int? sinceVersion,
  }) async {
    final sanitizedId = jobId.trim();
    if (sanitizedId.isEmpty) {
      return null;
    }
    final query = <String, dynamic>{};
    if (sinceVersion != null) {
      query['since'] = sinceVersion;
    }
    final endpoint = config.apiEndpoint(
      'jobs/$sanitizedId/playlist/items/delta',
      queryParameters: query.isEmpty ? null : query,
    );
    final response = await _getWithRedirects(endpoint);
    if (response.statusCode == 404) {
      return null;
    }
    _throwIfNotSuccessful(response);
    final decoded = _decodeJsonBody(response);
    final playlist = decoded['playlist'];
    if (playlist is! Map<String, dynamic>) {
      return null;
    }
    return DownloadPlaylistDeltaSnapshot.fromJson(decoded);
  }

  Future<DownloadJobOptionsSnapshot?> fetchJobOptions(
    String jobId, {
    int? sinceVersion,
    bool includeOptions = true,
    String? entryId,
    int? entryIndex,
  }) async {
    final sanitizedId = jobId.trim();
    if (sanitizedId.isEmpty) {
      return null;
    }
    final query = <String, dynamic>{};
    if (sinceVersion != null) {
      query['since'] = sinceVersion;
    }
    if (includeOptions) {
      query['detail'] = 'true';
    }
    if (entryId != null && entryId.trim().isNotEmpty) {
      query['entry_id'] = entryId.trim();
    }
    if (entryIndex != null && entryIndex > 0) {
      query['entry_index'] = entryIndex;
    }
    final endpoint = config.apiEndpoint(
      'jobs/$sanitizedId/options',
      queryParameters: query.isEmpty ? null : query,
    );
    final response = await _getWithRedirects(endpoint);
    if (response.statusCode == 404) {
      return null;
    }
    _throwIfNotSuccessful(response);
    final decoded = _decodeJsonBody(response);
    return DownloadJobOptionsSnapshot.fromJson(decoded);
  }

  Future<DownloadJobLogsSnapshot?> fetchJobLogs(
    String jobId, {
    int? sinceVersion,
    bool includeLogs = true,
    int? limit,
    String? entryId,
    int? entryIndex,
  }) async {
    final sanitizedId = jobId.trim();
    if (sanitizedId.isEmpty) {
      return null;
    }
    final query = <String, dynamic>{};
    if (sinceVersion != null) {
      query['since'] = sinceVersion;
    }
    if (includeLogs) {
      query['detail'] = 'true';
    }
    if (limit != null && limit > 0) {
      query['limit'] = limit;
    }
    if (entryId != null && entryId.trim().isNotEmpty) {
      query['entry_id'] = entryId.trim();
    }
    if (entryIndex != null && entryIndex > 0) {
      query['entry_index'] = entryIndex;
    }
    final endpoint = config.apiEndpoint(
      'jobs/$sanitizedId/logs',
      queryParameters: query.isEmpty ? null : query,
    );
    final response = await _getWithRedirects(endpoint);
    if (response.statusCode == 404) {
      return null;
    }
    _throwIfNotSuccessful(response);
    final decoded = _decodeJsonBody(response);
    return DownloadJobLogsSnapshot.fromJson(decoded);
  }

  Map<String, String> _buildHeaders({required bool includeBody}) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (includeBody) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    final token = _authToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      headers['X-API-Token'] = token;
    }
    return headers;
  }

  void _throwIfNotSuccessful(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DownloadServiceException(
        response.statusCode,
        response.body.isNotEmpty ? response.body : response.reasonPhrase,
      );
    }
  }

  Future<http.Response> _postWithRedirects(
    Uri url,
    String body, {
    bool allowEmptyBody = false,
    int maxRedirects = _defaultMaxRedirects,
  }) async {
    Uri current = url;
    String payload = body;
    final headers = _buildHeaders(
      includeBody: !allowEmptyBody || payload.isNotEmpty,
    );
    for (var attempt = 0; attempt <= maxRedirects; attempt++) {
      final response = await _runRequest(
        () => _client
            .post(
              current,
              headers: headers,
              body: allowEmptyBody ? null : payload,
            )
            .timeout(config.timeout),
        endpoint: current,
      );
      if (!_isRedirect(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      if (location == null) {
        return response;
      }
      current = current.resolve(location);
      if (response.statusCode == 303) {
        return _getWithRedirects(
          current,
          maxRedirects: maxRedirects - attempt - 1,
        );
      }
      // For 307/308 reuse same payload; for empty body ensure null remains null.
      continue;
    }
    return _tooManyRedirectsResponse();
  }

  Future<http.Response> _getWithRedirects(
    Uri url, {
    int maxRedirects = _defaultMaxRedirects,
  }) async {
    Uri current = url;
    final headers = _buildHeaders(includeBody: false);
    for (var attempt = 0; attempt <= maxRedirects; attempt++) {
      final response = await _runRequest(
        () => _client.get(current, headers: headers).timeout(config.timeout),
        endpoint: current,
      );
      if (!_isRedirect(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      if (location == null) {
        return response;
      }
      current = current.resolve(location);
    }
    return _tooManyRedirectsResponse();
  }

  bool _isRedirect(int statusCode) {
    return _redirectStatusCodes.contains(statusCode);
  }

  Future<http.Response> _deleteWithRedirects(
    Uri url, {
    int maxRedirects = _defaultMaxRedirects,
  }) async {
    Uri current = url;
    final headers = _buildHeaders(includeBody: false);
    for (var attempt = 0; attempt <= maxRedirects; attempt++) {
      final response = await _runRequest(
        () => _client.delete(current, headers: headers).timeout(config.timeout),
        endpoint: current,
      );
      if (!_isRedirect(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      if (location == null) {
        return response;
      }
      current = current.resolve(location);
    }
    return _tooManyRedirectsResponse();
  }

  Map<String, dynamic> _decodeJsonBody(http.Response response) {
    if (response.body.isEmpty) {
      return const <String, dynamic>{};
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw DownloadServiceException(
        response.statusCode,
        _localize(AppStringKey.downloadServiceInvalidJson, {
          'error': error.toString(),
        }),
      );
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return {'value': decoded};
  }

  bool _looksLikeJobResponse(Map<String, dynamic> decoded) {
    if (!decoded.containsKey('job_id')) {
      return false;
    }
    if (decoded['urls'] is List) {
      return true;
    }
    if (decoded['metadata'] is Map) {
      return true;
    }
    if (decoded['progress'] is Map) {
      return true;
    }
    return false;
  }

  void dispose() {
    _client.close();
  }

  static String _defaultLanguageResolver() => I18n.fallbackLocale;

  String _effectiveLanguageCode() {
    final resolved = _languageResolver().trim();
    if (resolved.isEmpty) {
      return I18n.fallbackLocale;
    }
    return resolved;
  }

  String _localize(String key, [Map<String, String>? values]) {
    final template = _resolveTemplate(key);
    if (values == null || values.isEmpty) {
      return template;
    }
    return values.entries.fold<String>(
      template,
      (result, entry) => result.replaceAll('{${entry.key}}', entry.value),
    );
  }

  String _resolveTemplate(String key) {
    try {
      return resolveAppString(key, _effectiveLanguageCode());
    } on StateError {
      return _fallbackStrings[key] ?? key;
    }
  }

  String _timeoutDurationLabel(Duration timeout) {
    if (timeout.inSeconds > 0) {
      return _localize(AppStringKey.downloadServiceTimeoutSeconds, {
        'seconds': timeout.inSeconds.toString(),
      });
    }
    return _localize(AppStringKey.downloadServiceTimeoutExpectedDuration);
  }

  String _endpointLabel(Uri? endpoint) {
    return (endpoint ?? config.apiBaseUri).toString();
  }

  http.Response _tooManyRedirectsResponse() {
    return http.Response(
      _localize(AppStringKey.downloadServiceTooManyRedirects),
      310,
    );
  }

  static const Map<String, String> _fallbackStrings = <String, String>{
    // English fallback copy when localization assets are unavailable.
    AppStringKey.downloadServiceJobResponseMissingId:
        'Job creation response missing job_id.',
    AppStringKey.downloadServicePreviewUrlRequired:
        'The preview URL must not be empty.',
    AppStringKey.downloadServiceJobIdRequired: 'job_id is required.',
    AppStringKey.downloadServiceTooManyRedirects: 'Too many redirects',
    AppStringKey.downloadServiceInvalidJson:
        'Invalid JSON response: {error}',
    AppStringKey.downloadServiceTimeoutSeconds: '{seconds} s',
    AppStringKey.downloadServiceTimeoutExpectedDuration:
        'the expected time',
    AppStringKey.downloadServiceTimeout:
        'The backend did not respond after {duration} ({target}).',
    AppStringKey.downloadServiceSocketError:
        'Could not connect to {target}: {detail}',
    AppStringKey.downloadServiceIoError: 'I/O error with {target}: {error}',
    AppStringKey.downloadServiceNetworkError:
        'Network error with {target}: {error}',
  };

  Future<http.Response> _runRequest(
    Future<http.Response> Function() request, {
    Uri? endpoint,
  }) async {
    try {
      return await request();
    } on TimeoutException catch (_) {
      final target = _endpointLabel(endpoint);
      final durationLabel = _timeoutDurationLabel(config.timeout);
      final message = _localize(AppStringKey.downloadServiceTimeout, {
        'duration': durationLabel,
        'target': target,
      },
      );
      throw DownloadServiceConnectionException(message, details: target);
    } on SocketException catch (error) {
      final target = _endpointLabel(endpoint);
      final detail = error.osError?.message ?? error.message;
      final message = _localize(AppStringKey.downloadServiceSocketError, {
        'target': target,
        'detail': detail,
      },
      );
      throw DownloadServiceConnectionException(message, details: detail);
    } on IOException catch (error) {
      final target = _endpointLabel(endpoint);
      final message = _localize(AppStringKey.downloadServiceIoError, {
        'target': target,
        'error': error.toString(),
      },
      );
      throw DownloadServiceConnectionException(
        message,
        details: error.toString(),
      );
    } on http.ClientException catch (error) {
      final target = _endpointLabel(endpoint);
      final message = _localize(AppStringKey.downloadServiceNetworkError, {
        'target': target,
        'error': error.message,
      },
      );
      throw DownloadServiceConnectionException(message, details: error.message);
    }
  }
}

class DownloadServiceException implements Exception {
  DownloadServiceException(this.statusCode, this.message);

  final int statusCode;
  final Object? message;

  @override
  String toString() => 'DownloadServiceException($statusCode, $message)';
}

class DownloadServiceConnectionException extends DownloadServiceException {
  DownloadServiceConnectionException(String message, {String? details})
    : _details = details?.trim() ?? '',
      super(-1, message);

  final String _details;

  String get details => _details;

  @override
  String toString() {
    final base = message?.toString() ?? 'DownloadServiceConnectionException';
    if (_details.isEmpty) {
      return base;
    }
    return '$base ($_details)';
  }
}
