import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/data/models/playlist_preview.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';
import 'package:vidra/ui/screens/home/home_screen.dart';
import 'package:vidra/ui/screens/home/playlist_selection_dialog.dart';

const _radioPlaylistUrl =
    'https://www.youtube.com/watch?v=WZkd2XUG2VU&list=PLo2ygdeyksELgcHDKDR15ZLKgj-WXwX0A';

final Map<String, String> _dotEnvOverrides = _loadDotEnv();

String _envValue(String key) {
  final value = _dotEnvOverrides[key] ?? Platform.environment[key];
  if (value == null) {
    throw StateError('Missing required environment variable "$key"');
  }
  final trimmed = _stripQuotes(value.trim());
  if (trimmed.isEmpty) {
    throw StateError('Environment variable "$key" cannot be empty');
  }
  return trimmed;
}

final String _backendScheme = _envValue('VIDRA_SERVER_SCHEME');
final String _backendHost = _envValue('VIDRA_SERVER_HOST');
final int _backendPort =
    int.tryParse(_envValue('VIDRA_SERVER_PORT')) ??
    (throw StateError('VIDRA_SERVER_PORT must be an integer'));
final String _backendBasePath = _envValue('VIDRA_SERVER_BASE_PATH');
final String _apiRoot = _trimSlashes(_envValue('VIDRA_SERVER_API_ROOT'));
final String _wsOverviewPath = _normalizePath(
  _envValue('VIDRA_SERVER_WS_OVERVIEW_PATH'),
);
final String _wsJobBasePath = _normalizePath(
  _envValue('VIDRA_SERVER_WS_JOB_PATH'),
);

final Uri _backendBaseUri = Uri.parse(
  '$_backendScheme://$_backendHost:$_backendPort'
  '${_normalizeBasePath(_backendBasePath)}',
);

final Uri _apiBaseUri = _backendBaseUri.resolve(
  _apiRoot.isEmpty ? '' : '$_apiRoot/',
);

final String _wsScheme = _backendScheme == 'https' ? 'wss' : 'ws';
final Uri _overviewSocketUri = Uri.parse(
  '$_wsScheme://$_backendHost:$_backendPort$_wsOverviewPath',
);
final Uri _jobSocketBaseUri = Uri.parse(
  '$_wsScheme://$_backendHost:$_backendPort$_wsJobBasePath',
);

final String _backendToken = _envValue('VIDRA_SERVER_TOKEN');

final BackendConfig _backendConfig = BackendConfig(
  name: _envValue('VIDRA_SERVER_NAME'),
  description: _envValue('VIDRA_SERVER_DESCRIPTION'),
  baseUri: _backendBaseUri,
  apiBaseUri: _apiBaseUri,
  overviewSocketUri: _overviewSocketUri,
  jobSocketBaseUri: _jobSocketBaseUri,
  metadata: _parseMetadata(_envValue('VIDRA_SERVER_METADATA')),
  timeout: Duration(
    seconds:
        int.tryParse(_envValue('VIDRA_SERVER_TIMEOUT_SECONDS')) ??
        (throw StateError('VIDRA_SERVER_TIMEOUT_SECONDS must be an integer')),
  ),
);

const _backendTestGateVar = 'VIDRA_RUN_BACKEND_TESTS';
const bool _backendTestsEnabled = bool.fromEnvironment(
  _backendTestGateVar,
  defaultValue: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (!_backendTestsEnabled) {
    debugPrint(
      'Skipping backend integration tests. Provide --dart-define=$_backendTestGateVar=true to run.',
    );
    testWidgets(
      'radio playlist download surfaces playlist modal while collecting entries',
      (WidgetTester tester) async {},
      skip: true,
    );
    return;
  }

  bool backendAvailable = false;

  setUpAll(() async {
    backendAvailable = await _withRealHttp(_isBackendAvailable);
  });

  testWidgets(
    'radio playlist download surfaces playlist modal while collecting entries',
    (WidgetTester tester) async {
      if (!backendAvailable) {
        final message =
            'Backend is not running on ${_backendBaseUri.toString()}.';
        debugPrint('$message Test skipped.');
        return;
      }

      SharedPreferences.setMockInitialValues({});
      final preferencesModel = PreferencesModel();
      await preferencesModel.initializePreferences();
      addTearDown(preferencesModel.dispose);

      final jobId = await _withRealHttp(_scheduleDownload);
      addTearDown(() => _withRealHttp(() => _cancelJob(jobId)));

      final snapshot = await _withRealHttp(
        () => _waitForPlaylistSnapshot(jobId),
      );
      expect(
        snapshot,
        isNotNull,
        reason: 'Backend never exposed playlist metadata for job $jobId',
      );

      final job = DownloadJobModel.fromJson(snapshot!);
      final controller = _HarnessDownloadController(
        backendConfig: _backendConfig,
        jobs: [job],
        collectingJobIds: {job.id},
        pendingSelectionJobId: job.id,
      );
      addTearDown(controller.dispose);

      final invokedJobs = <String>[];
      final capturedPlaylists = <PlaylistPreview?>[];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<BackendConfig>.value(value: _backendConfig),
            ChangeNotifierProvider<PreferencesModel>.value(
              value: preferencesModel,
            ),
            ChangeNotifierProvider<DownloadController>.value(value: controller),
          ],
          child: MaterialApp(
            home: HomeScreen(
              playlistDialogLauncher:
                  (context, boundController, observedJobId, previewData) async {
                    invokedJobs.add(observedJobId);
                    capturedPlaylists.add(previewData.playlist);
                    return const PlaylistSelectionResult(selectedIndices: null);
                  },
              autoInitializeController: false,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(invokedJobs, equals([job.id]));
      expect(capturedPlaylists, isNotEmpty);
      final playlist = capturedPlaylists.single;
      expect(playlist, isNotNull);
      expect(playlist!.isCollectingEntries, isTrue);
      expect(playlist.entries, isEmpty);
    },
  );
}

// Intentionally no runtime/env opt-in to avoid accidental slow runs when
// developers export variables from .env. Explicit --dart-define keeps this
// suite opt-in only.

Future<bool> _isBackendAvailable() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(_backendBaseUri);
    _attachAuthHeaders(request);
    final response = await request.close();
    return response.statusCode < 500;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

Future<String> _scheduleDownload() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final targetUri = _apiUri('jobs');
    debugPrint('Scheduling radio playlist via $targetUri');
    final request = await client.postUrl(targetUri);
    _attachAuthHeaders(request);
    request.headers.contentType = ContentType.json;
    final payloadBytes = utf8.encode(
      jsonEncode(<String, dynamic>{
        'urls': _radioPlaylistUrl,
        'options': {'playlist': true},
      }),
    );
    request.contentLength = payloadBytes.length;
    request.add(payloadBytes);
    final response = await request.close();
    final payload = await _decodeResponse(response);
    if (response.statusCode != 201) {
      final headerDump = <String, List<String>>{};
      response.headers.forEach((name, values) {
        headerDump[name] = values;
      });
      debugPrint(
        'Job scheduling failed ${response.statusCode}: '
        '${payload.isEmpty ? '<empty>' : payload} '
        'headers=$headerDump',
      );
      throw StateError(
        'Failed to schedule radio playlist: ${response.statusCode} ${payload['error'] ?? payload['detail'] ?? payload}',
      );
    }
    final jobId = payload['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw StateError('Download creation response missing job_id');
    }
    return jobId;
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>?> _waitForPlaylistSnapshot(String jobId) async {
  final timeout = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(timeout)) {
    final snapshot = await _fetchJobSnapshot(jobId);
    if (snapshot == null) {
      break;
    }
    if (_hasPlaylistMetadata(snapshot)) {
      return snapshot;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  return null;
}

Future<Map<String, dynamic>?> _fetchJobSnapshot(String jobId) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(_apiUri('jobs/$jobId'));
    _attachAuthHeaders(request);
    final response = await request.close();
    if (response.statusCode == 404) {
      return null;
    }
    return _decodeResponse(response);
  } finally {
    client.close();
  }
}

Future<void> _cancelJob(String jobId) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.postUrl(_apiUri('jobs/$jobId/cancel'));
    _attachAuthHeaders(request);
    await request.close();
  } catch (_) {
    // Ignore cancel failures.
  } finally {
    client.close();
  }
}

Uri _apiUri(String path) {
  final normalized = _buildApiPath(path);
  if (normalized.isEmpty) {
    return _backendBaseUri;
  }
  return _backendBaseUri.resolve(normalized);
}

String _buildApiPath(String path) {
  final normalizedTail = _trimLeadingSlash(path);
  if (_apiRoot.isEmpty) {
    return normalizedTail;
  }
  if (normalizedTail.isEmpty) {
    return _apiRoot;
  }
  return '$_apiRoot/$normalizedTail';
}

String _trimLeadingSlash(String raw) {
  var value = raw.trim();
  while (value.startsWith('/')) {
    value = value.substring(1);
  }
  return value;
}

String _normalizeBasePath(String raw) {
  if (raw.isEmpty) {
    return '/';
  }
  var value = raw.trim();
  if (!value.startsWith('/')) {
    value = '/$value';
  }
  if (!value.endsWith('/')) {
    value = '$value/';
  }
  if (value == '//') {
    return '/';
  }
  return value;
}

String _normalizePath(String raw) {
  if (raw.isEmpty) {
    return '/';
  }
  var value = raw.trim();
  if (!value.startsWith('/')) {
    value = '/$value';
  }
  return value;
}

String _trimSlashes(String raw) {
  var value = raw.trim();
  while (value.startsWith('/')) {
    value = value.substring(1);
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

Map<String, String> _loadDotEnv() {
  final file = File('.env');
  if (!file.existsSync()) {
    return const <String, String>{};
  }
  final entries = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final separatorIndex = trimmed.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }
    final key = trimmed.substring(0, separatorIndex).trim();
    final value = _stripQuotes(trimmed.substring(separatorIndex + 1).trim());
    if (key.isEmpty) {
      continue;
    }
    entries[key] = value;
  }
  return entries;
}

String _stripQuotes(String value) {
  if (value.length >= 2) {
    final startsWithDouble = value.startsWith('"') && value.endsWith('"');
    final startsWithSingle = value.startsWith("'") && value.endsWith("'");
    if (startsWithDouble || startsWithSingle) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}

Map<String, dynamic> _parseMetadata(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {
    // Ignore parse errors and fall back to an empty metadata map.
  }
  return const <String, dynamic>{};
}

Future<Map<String, dynamic>> _decodeResponse(
  HttpClientResponse response,
) async {
  final body = await response.transform(utf8.decoder).join();
  if (body.isEmpty) {
    return const <String, dynamic>{};
  }
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  throw StateError('Unexpected response payload: $decoded');
}

bool _hasPlaylistMetadata(Map<String, dynamic> snapshot) {
  final playlist = snapshot['playlist'];
  final metadata = snapshot['metadata'];
  final metadataPlaylist = metadata is Map<String, dynamic>
      ? metadata['playlist']
      : null;
  final playlistSnapshot = snapshot['playlist_snapshot'];
  final progress = snapshot['progress'];

  bool collectingFlag = false;
  if (playlist is Map<String, dynamic>) {
    collectingFlag = playlist['is_collecting_entries'] == true;
  }
  if (metadataPlaylist is Map<String, dynamic>) {
    collectingFlag =
        collectingFlag || metadataPlaylist['is_collecting_entries'] == true;
  }

  final requiresSelection =
      metadata is Map<String, dynamic> &&
      metadata['requires_playlist_selection'] == true;
  final playlistEntryCountReady =
      metadata is Map<String, dynamic> &&
      (metadata['playlist_entry_count'] is num) &&
      (metadata['playlist_entry_count'] as num) > 0;
  final progressHasPlaylistTotals =
      progress is Map<String, dynamic> &&
      (progress['playlist_total_items'] is num) &&
      (progress['playlist_total_items'] as num) > 0;
  final waitingForUserConfirmation =
      snapshot['status_hint'] == 'waiting_user_confirmation';

  bool hasSnapshotEntries = false;
  if (playlistSnapshot is Map<String, dynamic>) {
    final snapshotEntries = playlistSnapshot['entries'];
    hasSnapshotEntries = snapshotEntries is List && snapshotEntries.isNotEmpty;
  }

  return (playlist is Map && playlist.isNotEmpty) ||
      (metadataPlaylist is Map && metadataPlaylist.isNotEmpty) ||
      collectingFlag ||
      requiresSelection ||
      playlistEntryCountReady ||
      progressHasPlaylistTotals ||
      waitingForUserConfirmation ||
      hasSnapshotEntries;
}

Future<T> _withRealHttp<T>(Future<T> Function() operation) {
  final overrides = _PassthroughHttpOverrides();
  return HttpOverrides.runZoned<Future<T>>(
    operation,
    createHttpClient: overrides.createHttpClient,
  );
}

void _attachAuthHeaders(HttpClientRequest request) {
  if (_backendToken.isEmpty) {
    return;
  }
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_backendToken');
  request.headers.set('X-API-Token', _backendToken);
}

class _PassthroughHttpOverrides extends HttpOverrides {}

class _HarnessDownloadController extends DownloadController {
  _HarnessDownloadController({
    required super.backendConfig,
    List<DownloadJobModel> jobs = const <DownloadJobModel>[],
    Set<String> collectingJobIds = const <String>{},
    String? pendingSelectionJobId,
  }) : _jobsById = {for (final job in jobs) job.id: job},
       _collectingJobIds = Set<String>.from(collectingJobIds),
       _pendingRequests = Queue<String>(),
       super(
         authToken: _backendToken,
         backendStateListenable: const _AlwaysRunningBackendState(),
       ) {
    if (pendingSelectionJobId != null) {
      _pendingRequests.add(pendingSelectionJobId);
    }
  }

  final Map<String, DownloadJobModel> _jobsById;
  final Set<String> _collectingJobIds;
  final Queue<String> _pendingRequests;

  @override
  List<DownloadJobModel> get jobs => _jobsById.values.toList(growable: false);

  @override
  DownloadJobModel? jobById(String jobId) => _jobsById[jobId];

  @override
  bool jobIsCollectingPlaylistEntries(String jobId) {
    return _collectingJobIds.contains(jobId);
  }

  @override
  String? takeNextPlaylistSelectionRequest() {
    if (_pendingRequests.isEmpty) {
      return null;
    }
    return _pendingRequests.removeFirst();
  }

  @override
  void completePlaylistSelectionRequest(
    String jobId, {
    bool keepQueued = false,
  }) {
    if (keepQueued) {
      _pendingRequests
        ..removeWhere((id) => id == jobId)
        ..add(jobId);
    } else {
      _pendingRequests.removeWhere((id) => id == jobId);
    }
    notifyListeners();
  }

  @override
  void requeuePlaylistSelection(String jobId) {
    _pendingRequests.add(jobId);
    notifyListeners();
  }

  @override
  Future<bool> submitPlaylistSelection(
    String jobId, {
    Set<int>? indices,
  }) async {
    return true;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshJobs() async {}

  @override
  Future<bool> startDownload(
    String url,
    Map<String, dynamic> options, {
    Map<String, dynamic>? metadata,
    String? owner,
  }) async {
    return true;
  }

  @override
  bool get isSubmitting => false;

  @override
  String? get lastError => null;
}

class _AlwaysRunningBackendState implements ValueListenable<BackendState> {
  const _AlwaysRunningBackendState();

  @override
  BackendState get value => BackendState.running;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
