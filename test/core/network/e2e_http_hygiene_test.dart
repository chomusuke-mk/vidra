import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/download_detail_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

/// Test Fake for SystemController in Network tests
class FakeNetworkSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  SystemState _state = SystemState.ready;

  @override
  SystemState get state => _state;

  void setState(SystemState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  int? get backendPort => 5000;
  @override
  String? get backendToken => 'test_token_hygiene';
  @override
  String? get serverLogsFilePath => null;
  @override
  Future<void> get whenPortReady => Future.value();
  @override
  Future<void> stopBackendForUpdate() async {}
  @override
  Future<void> resumeInitialization() async {}
  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

void main() {
  group('E2E HTTP Connection Hygiene & Stream Protection Suite', () {
    const baseUrl = 'http://127.0.0.1:5000';
    const token = 'secret_token_123';

    // =========================================================================
    // TIER 1: FEATURE COVERAGE — SSE Stream & HTTP Hygiene
    // =========================================================================
    group('Tier 1: SSE Stream Handling & HTTP Hygiene', () {
      test('1.1: subscribeToDeltas parses multi-event stream and ignores comments (: ping, : keep-alive)', () async {
        final sseStreamData = utf8.encode(
          ': ping\n'
          '\n'
          'data: [{"id": "dl_1", "status": {"value": "in_progress", "progress_value": 10.0}}]\n'
          '\n'
          ': keep-alive\n'
          'data: [{"id": "dl_1", "status": {"value": "in_progress", "progress_value": 50.0}}]\n'
          '\n'
          ': idle check\n'
          'data: [{"id": "dl_1", "status": {"value": "completed", "progress_value": 100.0}}]\n'
          '\n',
        );

        final mockClient = MockClient.streaming((request, bodyStream) async {
          expect(request.url.path, equals('/subscribe'));
          return http.StreamedResponse(
            Stream.value(sseStreamData),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final events = await client.subscribeToDeltas().toList();

        expect(events.length, equals(3));
        expect(events[0][0]['id'], equals('dl_1'));
        expect(events[0][0]['status']['progress_value'], equals(10.0));
        expect(events[1][0]['status']['progress_value'], equals(50.0));
        expect(events[2][0]['status']['value'], equals('completed'));
      });

      test('1.2: subscribeToDeltas parses multiple delta payloads in a single SSE data line', () async {
        final multiPayload = utf8.encode(
          'data: [{"id": "1", "sub_id": "s1"}, {"id": "1", "sub_id": "s2"}, {"id": "2", "sub_id": null}]\n\n',
        );

        final mockClient = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(multiPayload),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final events = await client.subscribeToDeltas().toList();
        expect(events.length, equals(1));
        expect(events[0].length, equals(3));
        expect(events[0][0]['sub_id'], equals('s1'));
        expect(events[0][1]['sub_id'], equals('s2'));
        expect(events[0][2]['sub_id'], isNull);
      });

      test('1.3: VidraHttpClient reuses client and respects configured headers and Bearer token', () async {
        var callCount = 0;
        final mockClient = MockClient((request) async {
          callCount++;
          expect(request.headers['Authorization'], equals('Bearer $token'));
          expect(request.headers['Content-Type'], equals('application/json'));
          expect(request.headers['X-Custom-Header'], equals('VidraE2E'));

          if (request.url.path == '/downloads') {
            return http.Response(jsonEncode([]), 200);
          } else if (request.url.path == '/logs') {
            return http.Response('Server is running', 200);
          }
          return http.Response('OK', 200);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {'X-Custom-Header': 'VidraE2E'},
          token: token,
          client: mockClient,
        );

        final downloads = await client.getDownloads();
        final logs = await client.getLogs();

        expect(downloads, isEmpty);
        expect(logs, equals('Server is running'));
        expect(callCount, equals(2));
      });

      test('1.4: DownloadDetailController connects to detailed SSE stream and routes sub-deltas', () async {
        final sseController = StreamController<List<dynamic>>.broadcast();

        final mockClient = MockClient.streaming((request, bodyStream) async {
          if (request.url.path == '/subscribe' && request.url.queryParameters['id'] == 'playlist_1') {
            final byteStream = sseController.stream.map(
              (event) => utf8.encode('data: ${jsonEncode(event)}\n\n'),
            );
            return http.StreamedResponse(byteStream, 200);
          } else if (request.url.path == '/downloads') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({'id': 'playlist_1', 'sub_descargas': []}))),
              200,
            );
          } else if (request.url.path == '/logs') {
            return http.StreamedResponse(Stream.value(utf8.encode('Ready')), 200);
          }
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        final repository = DownloadRepository(client);
        final sysCtrl = FakeNetworkSystemController();

        final download = Download(
          id: 'playlist_1',
          info: Info(title: 'Playlist 1'),
          subDownloads: [],
        );

        final detailCtrl = DownloadDetailController(repository, sysCtrl, download);
        await Future.delayed(const Duration(milliseconds: 20));

        // Emit sub-delta
        sseController.add([
          {
            'id': 'playlist_1',
            'sub_id': 'sub_001',
            'info': {'title': 'Sub Episode 1', 'duration': '22:15'},
            'status': {'value': 'in_progress', 'progress_value': 40.0},
          },
        ]);
        await Future.delayed(const Duration(milliseconds: 20));

        expect(download.subDownloads?.length, equals(1));
        expect(download.subDownloads?.first.info?.title, equals('Sub Episode 1'));
        expect(download.subDownloads?.first.state?.progressValue, equals(40.0));

        detailCtrl.dispose();
        await sseController.close();
      });

      test('1.5: DownloadDetailController fetchLogs retrieves download-specific logs with loading state', () async {
        final mockClient = MockClient((request) async {
          if (request.url.path == '/logs') {
            expect(request.url.queryParameters['id'], equals('dl_logged'));
            return http.Response('[FFmpeg] Transcoding video...\n[FFmpeg] Complete.', 200);
          } else if (request.url.path == '/downloads') {
            return http.Response('{"id": "dl_logged"}', 200);
          }
          return http.Response('{}', 200);
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        final repository = DownloadRepository(client);
        final sysCtrl = FakeNetworkSystemController();

        final download = Download(id: 'dl_logged', info: Info(title: 'Logged Download'));
        final detailCtrl = DownloadDetailController(repository, sysCtrl, download);
        await Future.delayed(const Duration(milliseconds: 20));

        expect(detailCtrl.logs, contains('[FFmpeg] Transcoding video...'));
        expect(detailCtrl.isLoadingLogs, isFalse);

        detailCtrl.dispose();
      });
    });

    // =========================================================================
    // TIER 2: BOUNDARY & CORNER CASES
    // =========================================================================
    group('Tier 2: Boundary & Corner Cases', () {
      test('2.1: Malformed Chunks: SSE stream emitting empty data: lines or comments skips them gracefully', () async {
        final streamData = utf8.encode(
          ': only comment\n'
          '\n'
          'data: \n'
          '\n'
          'data:   \n'
          '\n'
          'data: [{"id": "valid_dl", "status": {"value": "completed"}}]\n'
          '\n',
        );

        final mockClient = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(Stream.value(streamData), 200);
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        final events = await client.subscribeToDeltas().toList();

        expect(events.length, equals(1));
        expect(events[0][0]['id'], equals('valid_dl'));
      });

      test('2.2: Stream Teardown: Server disconnection (stream onDone) completes cleanly without dangling stream', () async {
        final sseController = StreamController<List<int>>();

        final mockClient = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(sseController.stream, 200);
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        final stream = client.subscribeToDeltas();

        var streamCompleted = false;
        final sub = stream.listen((_) {}, onDone: () {
          streamCompleted = true;
        });

        // Send one event then close
        sseController.add(utf8.encode('data: [{"id": "1"}]\n\n'));
        await Future.delayed(const Duration(milliseconds: 10));
        await sseController.close();
        await Future.delayed(const Duration(milliseconds: 10));

        expect(streamCompleted, isTrue);
        await sub.cancel();
      });

      test('2.3: HTTP Errors on Stream: Non-200 stream response throws descriptive exception and cleans up', () async {
        final mockClient = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode('Internal server stream error')),
            500,
          );
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);

        expect(
          () => client.subscribeToDeltas().toList(),
          throwsA(predicate((e) => e is Exception && e.toString().contains('500'))),
        );
      });

      test('2.4: Concurrency Limit: 50 concurrent REST calls execute through VidraHttpClient without socket starvation', () async {
        var activeRequests = 0;
        var peakActiveRequests = 0;

        final mockClient = MockClient((request) async {
          activeRequests++;
          if (activeRequests > peakActiveRequests) {
            peakActiveRequests = activeRequests;
          }
          await Future.delayed(const Duration(milliseconds: 5));
          activeRequests--;
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);

        final futures = List.generate(50, (i) => client.healthCheck());
        final results = await Future.wait(futures);

        expect(results.length, equals(50));
        expect(results.every((r) => r == true), isTrue);
        expect(activeRequests, equals(0));
      });

      test('2.5: Subscription Cancellation: Cancelling stream subscription stops receiving further events', () async {
        var yieldedAfterCancel = false;
        final sseController = StreamController<List<int>>.broadcast();

        final mockClient = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(sseController.stream, 200);
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        final stream = client.subscribeToDeltas();

        final sub = stream.listen((events) {
          if (events.any((e) => e['id'] == 'after_cancel')) {
            yieldedAfterCancel = true;
          }
        });

        sseController.add(utf8.encode('data: [{"id": "before_cancel"}]\n\n'));
        await Future.delayed(const Duration(milliseconds: 10));

        // Cancel subscription
        sub.cancel();

        // Push another event after cancellation
        sseController.add(utf8.encode('data: [{"id": "after_cancel"}]\n\n'));
        await Future.delayed(const Duration(milliseconds: 10));

        expect(yieldedAfterCancel, isFalse);
        sseController.close();
      });
    });

    // =========================================================================
    // TIER 3: CROSS-FEATURE COMBINATIONS
    // =========================================================================
    group('Tier 3: Cross-Feature Combinations', () {
      test('3.1: SSE stream disconnects while DownloadDetailController is actively fetching logs, recovers gracefully', () async {
        final sseController = StreamController<List<int>>();

        final mockClient = MockClient.streaming((request, bodyStream) async {
          if (request.url.path == '/subscribe') {
            return http.StreamedResponse(sseController.stream, 200);
          } else if (request.url.path == '/downloads') {
            return http.StreamedResponse(Stream.value(utf8.encode('{"id": "dl_cross"}')), 200);
          } else if (request.url.path == '/logs') {
            await Future.delayed(const Duration(milliseconds: 20));
            return http.StreamedResponse(Stream.value(utf8.encode('Log data ready')), 200);
          }
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        final repository = DownloadRepository(client);
        final sysCtrl = FakeNetworkSystemController();

        final download = Download(id: 'dl_cross', info: Info(title: 'Cross Test'));
        final detailCtrl = DownloadDetailController(repository, sysCtrl, download);

        // Disconnect SSE stream while log fetch is pending
        await sseController.close();
        await Future.delayed(const Duration(milliseconds: 40));

        expect(detailCtrl.logs, equals('Log data ready'));
        expect(detailCtrl.isLoadingLogs, isFalse);

        detailCtrl.dispose();
      });

      test('3.2: Out-of-order sub-deltas (status update before creation, deletion before creation) normalize cleanly', () async {
        final sseController = StreamController<List<dynamic>>.broadcast();

        final mockClient = MockClient.streaming((request, bodyStream) async {
          if (request.url.path == '/subscribe') {
            final byteStream = sseController.stream.map(
              (event) => utf8.encode('data: ${jsonEncode(event)}\n\n'),
            );
            return http.StreamedResponse(byteStream, 200);
          } else if (request.url.path == '/downloads') {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"id": "dl_ooo", "sub_descargas": []}')),
              200,
            );
          } else if (request.url.path == '/logs') {
            return http.StreamedResponse(Stream.value(utf8.encode('')), 200);
          }
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        final repository = DownloadRepository(client);
        final sysCtrl = FakeNetworkSystemController();

        final download = Download(id: 'dl_ooo', info: Info(title: 'OOO Test'), subDownloads: []);
        final detailCtrl = DownloadDetailController(repository, sysCtrl, download);
        await Future.delayed(const Duration(milliseconds: 20));

        // 1. Delete for non-existent subId
        sseController.add([
          {
            'id': 'dl_ooo',
            'sub_id': 'ghost_sub',
            'status': {'value': 'deleted'},
          },
        ]);
        await Future.delayed(const Duration(milliseconds: 10));

        // 2. Status update for new subId (should auto-create SubDownload)
        sseController.add([
          {
            'id': 'dl_ooo',
            'sub_id': 'new_sub',
            'info': {'title': 'New Sub Track'},
            'status': {'value': 'in_progress', 'progress_value': 50.0},
          },
        ]);
        await Future.delayed(const Duration(milliseconds: 20));

        expect(detailCtrl.download.subDownloads?.length, equals(1));
        expect(detailCtrl.download.subDownloads?.first.subId, equals('new_sub'));
        expect(detailCtrl.download.subDownloads?.first.info?.title, equals('New Sub Track'));

        detailCtrl.dispose();
        await sseController.close();
      });

      test('3.3: REST call error occurring during heavy SSE delta flow does not lock or corrupt client', () async {
        final sseData = utf8.encode(
          'data: [{"id": "1", "status": {"value": "in_progress"}}]\n\n'
          'data: [{"id": "2", "status": {"value": "in_progress"}}]\n\n',
        );

        final mockClient = MockClient.streaming((request, bodyStream) async {
          if (request.url.path == '/subscribe') {
            return http.StreamedResponse(Stream.value(sseData), 200);
          } else if (request.url.path == '/downloads' && request.method == 'POST') {
            return http.StreamedResponse(Stream.value(utf8.encode('{"error": "Failed"}')), 500);
          } else if (request.url.path == '/downloads') {
            return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200);
          }
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);

        // Stream deltas
        final eventsFuture = client.subscribeToDeltas().toList();

        // Concurrently dispatch failing POST
        expect(
          () => client.addDownload(url: 'https://bad-request.com'),
          throwsA(isA<Exception>()),
        );

        final events = await eventsFuture;
        expect(events.length, equals(2));

        // Future requests still succeed normally
        final downloads = await client.getDownloads();
        expect(downloads, isEmpty);
      });
    });

    // =========================================================================
    // TIER 4: REAL-WORLD SCENARIOS
    // =========================================================================
    group('Tier 4: Real-World Scenarios', () {
      test('4.1: Extended session with continuous SSE stream, periodic log polling, and backend restart', () async {
        var backendRunning = true;
        final sseController = StreamController<List<int>>.broadcast();

        final mockClient = MockClient.streaming((request, bodyStream) async {
          if (!backendRunning) {
            return http.StreamedResponse(Stream.value(utf8.encode('Service Unavailable')), 503);
          }
          if (request.url.path == '/subscribe') {
            return http.StreamedResponse(sseController.stream, 200);
          } else if (request.url.path == '/logs') {
            return http.StreamedResponse(Stream.value(utf8.encode('[Logs] Active')), 200);
          } else if (request.url.path == '/downloads') {
            return http.StreamedResponse(Stream.value(utf8.encode('{"id": "dl_session"}')), 200);
          }
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        final repository = DownloadRepository(client);
        final sysCtrl = FakeNetworkSystemController();

        final download = Download(id: 'dl_session', info: Info(title: 'Session Item'));
        final detailCtrl = DownloadDetailController(repository, sysCtrl, download);
        await Future.delayed(const Duration(milliseconds: 20));

        // 1. Stream deltas
        sseController.add(utf8.encode('data: [{"id": "dl_session", "sub_id": "s1", "status": {"value": "in_progress"}}]\n\n'));
        await Future.delayed(const Duration(milliseconds: 10));

        // 2. Poll logs
        await detailCtrl.fetchLogs();
        expect(detailCtrl.logs, equals('[Logs] Active'));

        // 3. Backend restart: system state moves to retrying then ready
        backendRunning = false;
        sysCtrl.setState(SystemState.retrying);
        await Future.delayed(const Duration(milliseconds: 20));

        backendRunning = true;
        sysCtrl.setState(SystemState.ready);
        await Future.delayed(const Duration(milliseconds: 20));

        expect(detailCtrl.isLoading, isFalse);

        detailCtrl.dispose();
        await sseController.close();
      });

      test('4.2: High-density download detail monitor with 20 sub-downloads, search filtering, and sorting', () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'id': 'dl_album',
              'sub_descargas': List.generate(
                20,
                (i) => {
                  'sub_id': 'track_$i',
                  'parent_id': 'dl_album',
                  'info': {'title': 'Track ${(20 - i).toString().padLeft(2, '0')}', 'duration': '03:30'},
                  'state': {'value': i % 2 == 0 ? 'completed' : 'in_progress', 'progress_value': i * 5.0},
                },
              ),
            }),
            200,
          );
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        final repository = DownloadRepository(client);
        final sysCtrl = FakeNetworkSystemController();

        final download = Download(id: 'dl_album', info: Info(title: 'Album Monitor'));
        final detailCtrl = DownloadDetailController(repository, sysCtrl, download);
        await Future.delayed(const Duration(milliseconds: 20));

        expect(detailCtrl.filteredSubDownloads.length, equals(20));

        // 1. Filter by completed state
        detailCtrl.toggleFilter(DownloadStateEnum.completed);
        expect(detailCtrl.filteredSubDownloads.length, equals(10));
        expect(detailCtrl.filteredSubDownloads.every((s) => s.state?.value == DownloadStateEnum.completed), isTrue);

        // 2. Search query within filtered results
        detailCtrl.updateSearch('Track 02');
        expect(detailCtrl.filteredSubDownloads.length, equals(1));
        expect(detailCtrl.filteredSubDownloads.first.info?.title, equals('Track 02'));

        // 3. Clear search and test alphabetical sort
        detailCtrl.updateSearch('');
        detailCtrl.toggleFilter(DownloadStateEnum.completed); // remove filter -> 20 items
        detailCtrl.setSortOption(SubDownloadSortOption.alphabetical);

        final titles = detailCtrl.filteredSubDownloads.map((s) => s.info?.title ?? '').toList();
        expect(titles.first, equals('Track 01'));
        expect(titles.last, equals('Track 20'));

        detailCtrl.dispose();
      });
    });
  });
}
