import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/data/services/download_service.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';

import '../test_auth_token.dart';

late String _testToken;

class _AlwaysRunningBackendState implements ValueListenable<BackendState> {
  const _AlwaysRunningBackendState();

  @override
  BackendState get value => BackendState.running;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class StubDownloadService extends DownloadService {
  StubDownloadService(super.config)
    : super(authToken: _testToken, httpClient: http.Client());

  Future<DownloadJobModel> Function(
    String,
    Map<String, dynamic>,
    Map<String, dynamic>?,
    String?,
  )?
  onCreateJob;

  Future<List<DownloadJobModel>> Function()? onListJobs;

  Future<Map<String, dynamic>> Function(String jobId)? onCancelJob;

  Future<Map<String, dynamic>> Function(String jobId)? onPauseJob;

  Future<Map<String, dynamic>> Function(String jobId)? onResumeJob;

  Future<Map<String, dynamic>> Function(String jobId)? onDeleteJob;

  Future<DownloadPlaylistSnapshot?> Function(
    String jobId, {
    bool includeEntries,
    int? limit,
    int? offset,
  })?
  onFetchPlaylistSnapshot;

  Future<DownloadPlaylistDeltaSnapshot?> Function(
    String jobId, {
    int? sinceVersion,
  })?
  onFetchPlaylistDelta;

  @override
  Future<DownloadJobModel> createJob(
    String url,
    Map<String, dynamic> options, {
    Map<String, dynamic>? metadata,
    String? owner,
  }) {
    return onCreateJob?.call(url, options, metadata, owner) ??
        Future<DownloadJobModel>.error(StateError('onCreateJob not provided'));
  }

  @override
  Future<List<DownloadJobModel>> listJobs() {
    return onListJobs?.call() ?? Future.value(const <DownloadJobModel>[]);
  }

  @override
  Future<DownloadJobModel?> getJob(String jobId) => Future.value(null);

  @override
  Future<Map<String, dynamic>> cancelJob(String jobId) {
    return onCancelJob?.call(jobId) ??
        Future.value({'job_id': jobId, 'status': 'cancelling'});
  }

  @override
  Future<Map<String, dynamic>> pauseJob(String jobId) {
    return onPauseJob?.call(jobId) ??
        Future.value({'job_id': jobId, 'status': 'pausing'});
  }

  @override
  Future<Map<String, dynamic>> resumeJob(String jobId) {
    return onResumeJob?.call(jobId) ??
        Future.value({'job_id': jobId, 'status': 'running'});
  }

  @override
  Future<Map<String, dynamic>> deleteJob(String jobId) {
    return onDeleteJob?.call(jobId) ??
        Future.value({
          'job_id': jobId,
          'status': 'deleted',
          'reason': 'deleted',
        });
  }

  @override
  Future<DownloadPlaylistSnapshot?> fetchPlaylistSnapshot(
    String jobId, {
    bool includeEntries = false,
    int? limit,
    int? offset,
  }) {
    return onFetchPlaylistSnapshot?.call(
          jobId,
          includeEntries: includeEntries,
          limit: limit,
          offset: offset,
        ) ??
        Future.value(null);
  }

  @override
  Future<DownloadPlaylistDeltaSnapshot?> fetchPlaylistDelta(
    String jobId, {
    int? sinceVersion,
  }) {
    return onFetchPlaylistDelta?.call(jobId, sinceVersion: sinceVersion) ??
        Future.value(null);
  }

  @override
  void dispose() {}
}

void main() {
  setUpAll(() async {
    _testToken = await loadTestAuthToken();
  });
  group('DownloadController', () {
    late BackendConfig config;
    late StubDownloadService service;

    setUp(() {
      config = BackendConfig(
        name: 'Vidra Download Service',
        description: 'Local server backend for Vidra',
        baseUri: Uri.parse('http://127.0.0.1:5000/'),
        apiBaseUri: Uri.parse('http://127.0.0.1:5000/api/'),
        overviewSocketUri: Uri.parse('ws://127.0.0.1:5000/ws/overview'),
        jobSocketBaseUri: Uri.parse('ws://127.0.0.1:5000/ws/jobs/'),
        metadata: const {'environment': 'test'},
        timeout: const Duration(seconds: 30),
      );
      service = StubDownloadService(config);
    });

    test('startDownload merges metadata and stores job', () async {
      late Map<String, dynamic>? capturedMetadata;

      final job = DownloadJobModel(
        id: 'job-123',
        status: DownloadStatus.queued,
        createdAt: DateTime.now(),
      );

      service.onCreateJob = (url, options, metadata, owner) async {
        capturedMetadata = metadata;
        expect(url, 'https://example.com');
        expect(options['extract_audio'], isTrue);
        expect(metadata, isNotNull);
        expect(metadata!['client'], config.name);
        expect(metadata['description'], config.description);
        expect(metadata['base_uri'], config.baseUri.toString());
        expect(metadata['api_base_uri'], config.apiBaseUri.toString());
        expect(
          metadata['ws_overview_uri'],
          config.overviewSocketUri.toString(),
        );
        expect(metadata['ws_job_base_uri'], config.jobSocketBaseUri.toString());
        expect(metadata['timeout_seconds'], config.timeout.inSeconds);
        expect(metadata['environment'], 'test');
        return job;
      };

      final controller = DownloadController(
        backendConfig: config,
        authToken: _testToken,
        backendStateListenable: const _AlwaysRunningBackendState(),
        service: service,
        logUnhandledJobEvents: false,
      );

      final success = await controller.startDownload('https://example.com', {
        'extract_audio': true,
      });

      expect(success, isTrue);
      expect(controller.jobs.length, 1);
      expect(controller.jobs.first.id, 'job-123');
      expect(capturedMetadata, isNotNull);
    });

    test(
      'loadPlaylist uses playlist delta when entries are external',
      () async {
        final job = _jobWithPlaylist(
          'job-delta',
          _buildPlaylistJson(
            entriesVersion: 1,
            entriesExternal: true,
            entryCount: 2,
          ),
        );

        service.onListJobs = () async => [job];

        var hydrationCompleted = false;
        int? capturedSince;

        service.onFetchPlaylistSnapshot =
            (_, {bool includeEntries = false, int? limit, int? offset}) async {
              fail('Snapshot endpoint should not be used when delta succeeds');
            };

        service.onFetchPlaylistDelta = (jobId, {int? sinceVersion}) async {
          if (!hydrationCompleted) {
            hydrationCompleted = true;
            return DownloadPlaylistDeltaSnapshot.fromJson({
              'job_id': jobId,
              'status': 'running',
              'version': 2,
              'delta': {'type': 'full', 'version': 2},
              'playlist': _buildPlaylistJson(
                entriesVersion: 2,
                entriesExternal: true,
                entryCount: 2,
                entries: const [
                  {'index': 1, 'id': 'video-1'},
                ],
              ),
            });
          }
          capturedSince = sinceVersion;
          return DownloadPlaylistDeltaSnapshot.fromJson({
            'job_id': jobId,
            'status': 'running',
            'version': 3,
            'delta': {
              'type': 'incremental',
              'version': 3,
              'since': sinceVersion,
            },
            'playlist': _buildPlaylistJson(
              entriesVersion: 3,
              entriesExternal: true,
              entryCount: 2,
              entries: const [
                {'index': 1, 'id': 'video-1'},
                {'index': 2, 'id': 'video-2'},
              ],
            ),
          });
        };

        final controller = DownloadController(
          backendConfig: config,
          authToken: _testToken,
          backendStateListenable: const _AlwaysRunningBackendState(),
          service: service,
          logUnhandledJobEvents: false,
        );

        await controller.refreshJobs();
        await _drainMicrotasks();

        final hydratedPlaylist = controller.jobById(job.id)?.playlist;
        expect(hydratedPlaylist, isNotNull);
        expect(hydratedPlaylist!.entries.length, 1);

        final summary = await controller.loadPlaylist(
          job.id,
          includeEntries: true,
        );

        expect(summary, isNotNull);
        expect(summary!.entries.length, 2);
        expect(capturedSince, 2);
        final cached = controller.jobById(job.id)?.playlist;
        expect(cached?.entries.length, 2);
        expect(cached?.entriesVersion, 3);
      },
    );

    test(
      'loadPlaylist falls back to snapshot when entries are inline',
      () async {
        final job = _jobWithPlaylist(
          'job-inline',
          _buildPlaylistJson(
            entriesExternal: false,
            entryCount: 1,
            entries: const [
              {'index': 1, 'id': 'inline-1'},
            ],
          ),
        );

        service.onListJobs = () async => [job];

        var deltaInvoked = false;
        var snapshotCalls = 0;

        service.onFetchPlaylistDelta = (_, {int? sinceVersion}) async {
          deltaInvoked = true;
          return null;
        };

        service.onFetchPlaylistSnapshot =
            (
              jobId, {
              bool includeEntries = false,
              int? limit,
              int? offset,
            }) async {
              snapshotCalls++;
              expect(includeEntries, isTrue);
              return DownloadPlaylistSnapshot.fromJson({
                'job_id': jobId,
                'status': 'running',
                'playlist': _buildPlaylistJson(
                  entriesExternal: false,
                  entryCount: 1,
                  entries: const [
                    {'index': 1, 'id': 'inline-1'},
                  ],
                ),
              });
            };

        final controller = DownloadController(
          backendConfig: config,
          authToken: _testToken,
          backendStateListenable: const _AlwaysRunningBackendState(),
          service: service,
          logUnhandledJobEvents: false,
        );

        await controller.refreshJobs();

        final summary = await controller.loadPlaylist(
          job.id,
          includeEntries: true,
        );

        expect(summary, isNotNull);
        expect(snapshotCalls, 1);
        expect(deltaInvoked, isFalse);
        expect(controller.jobById(job.id)?.playlist?.entries.length, 1);
      },
    );

    test(
      'loadPlaylist falls back to snapshot when delta unavailable',
      () async {
        final job = _jobWithPlaylist(
          'job-fallback',
          _buildPlaylistJson(
            entriesVersion: 4,
            entriesExternal: true,
            entryCount: 1,
          ),
        );

        service.onListJobs = () async => [job];

        var deltaCalls = 0;
        var snapshotCalls = 0;

        service.onFetchPlaylistDelta = (_, {int? sinceVersion}) async {
          deltaCalls++;
          return null;
        };

        service.onFetchPlaylistSnapshot =
            (
              jobId, {
              bool includeEntries = false,
              int? limit,
              int? offset,
            }) async {
              snapshotCalls++;
              return DownloadPlaylistSnapshot.fromJson({
                'job_id': jobId,
                'status': 'running',
                'playlist': _buildPlaylistJson(
                  entriesExternal: true,
                  entriesVersion: 5,
                  entryCount: 1,
                  entries: const [
                    {'index': 1, 'id': 'video-1'},
                  ],
                ),
              });
            };

        final controller = DownloadController(
          backendConfig: config,
          authToken: _testToken,
          backendStateListenable: const _AlwaysRunningBackendState(),
          service: service,
          logUnhandledJobEvents: false,
        );

        await controller.refreshJobs();
        await _drainMicrotasks();

        final cachedBefore = controller.jobById(job.id)?.playlist;
        expect(cachedBefore, isNotNull);
        expect(cachedBefore!.entriesExternal, isTrue);

        final summary = await controller.loadPlaylist(
          job.id,
          includeEntries: true,
        );

        expect(summary, isNotNull);
        expect(deltaCalls, greaterThanOrEqualTo(1));
        expect(snapshotCalls, 1);
        expect(controller.jobById(job.id)?.playlist?.entries.length, 1);
      },
    );
  });
}

Future<void> _drainMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
}

DownloadJobModel _jobWithPlaylist(
  String jobId,
  Map<String, dynamic> playlistJson,
) {
  return DownloadJobModel(
    id: jobId,
    status: DownloadStatus.running,
    createdAt: DateTime.now(),
    playlist: DownloadPlaylistSummary.fromJson(playlistJson),
  );
}

Map<String, dynamic> _buildPlaylistJson({
  required bool entriesExternal,
  int? entriesVersion,
  int entryCount = 0,
  List<Map<String, dynamic>> entries = const <Map<String, dynamic>>[],
}) {
  final map = <String, dynamic>{
    'id': 'playlist-test',
    'title': 'Test playlist',
    'entry_count': entryCount,
    'total_items': entryCount,
    'entries_external': entriesExternal,
    'entries': entries,
  };
  if (entriesVersion != null) {
    map['entries_version'] = entriesVersion;
  }
  return map;
}
