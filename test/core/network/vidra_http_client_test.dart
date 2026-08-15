import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vidra/core/network/vidra_http_client.dart';

void main() {
  group('VidraHttpClient', () {
    const baseUrl = 'http://127.0.0.1:5000';
    const token = 'test_token_123';

    group('Base functionality', () {
      test('healthCheck returns true when server responds status ok', () async {
        final mockClient = MockClient((request) async {
          expect(request.method, equals('GET'));
          expect(request.url, equals(Uri.parse('$baseUrl/')));
          expect(request.headers['Authorization'], equals('Bearer $token'));
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final result = await client.healthCheck();
        expect(result, isTrue);
      });

      test('healthCheck returns false when status is unload or not ok', () async {
        final mockClient = MockClient((request) async {
          return http.Response(jsonEncode({'status': 'unload'}), 200);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final result = await client.healthCheck();
        expect(result, isFalse);
      });

      test('healthCheck returns false on network error', () async {
        final mockClient = MockClient((request) async {
          throw http.ClientException('Connection refused');
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final result = await client.healthCheck();
        expect(result, isFalse);
      });

      test('otaAction(load) sends PATCH /ota?action=load with Bearer token', () async {
        var requestReceived = false;
        final mockClient = MockClient((request) async {
          expect(request.method, equals('PATCH'));
          expect(request.url.path, equals('/ota'));
          expect(request.url.queryParameters['action'], equals('load'));
          expect(request.headers['Authorization'], equals('Bearer $token'));
          expect(request.headers['Content-Type'], equals('application/json'));
          requestReceived = true;
          return http.Response(jsonEncode({'message': 'OTA control applied.'}), 200);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final result = await client.otaAction('load');
        expect(result, isTrue);
        expect(requestReceived, isTrue);
      });

      test('otaAction(unload) sends PATCH /ota?action=unload with Bearer token', () async {
        var requestReceived = false;
        final mockClient = MockClient((request) async {
          expect(request.method, equals('PATCH'));
          expect(request.url.path, equals('/ota'));
          expect(request.url.queryParameters['action'], equals('unload'));
          expect(request.headers['Authorization'], equals('Bearer $token'));
          requestReceived = true;
          return http.Response(jsonEncode({'message': 'OTA control applied.'}), 200);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final result = await client.otaAction('unload');
        expect(result, isTrue);
        expect(requestReceived, isTrue);
      });

      test('otaLoad and otaUnload helper methods work properly', () async {
        final actions = <String>[];
        final mockClient = MockClient((request) async {
          actions.add(request.url.queryParameters['action'] ?? '');
          return http.Response(jsonEncode({'message': 'OK'}), 200);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final loadResult = await client.otaLoad();
        final unloadResult = await client.otaUnload();

        expect(loadResult, isTrue);
        expect(unloadResult, isTrue);
        expect(actions, equals(['load', 'unload']));
      });

      test('otaAction returns false on HTTP error status code', () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'error': "Invalid action, must be 'load' or 'unload'"}),
            400,
          );
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final result = await client.otaAction('invalid_action');
        expect(result, isFalse);
      });

      test('otaAction returns false on network exception', () async {
        final mockClient = MockClient((request) async {
          throw http.ClientException('Socket error');
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final result = await client.otaAction('load');
        expect(result, isFalse);
      });

      test('getLogs sends GET /logs and returns raw body', () async {
        final mockClient = MockClient((request) async {
          expect(request.method, equals('GET'));
          expect(request.url.path, equals('/logs'));
          expect(request.url.queryParameters['id'], equals('123'));
          return http.Response('log contents here', 200);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final logs = await client.getLogs(id: '123');
        expect(logs, equals('log contents here'));
      });

      test('getDownloads sends GET /downloads and returns parsed JSON', () async {
        final mockClient = MockClient((request) async {
          expect(request.method, equals('GET'));
          expect(request.url.path, equals('/downloads'));
          return http.Response(jsonEncode([{'id': '1', 'url': 'https://example.com'}]), 200);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final downloads = await client.getDownloads();
        expect(downloads, isA<List>());
        expect((downloads as List).first['id'], equals('1'));
      });

      test('addDownload sends POST /downloads and returns created id', () async {
        final mockClient = MockClient((request) async {
          expect(request.method, equals('POST'));
          expect(request.url.path, equals('/downloads'));
          final body = jsonDecode(request.body);
          expect(body['url'], equals('https://youtube.com/watch?v=abc'));
          return http.Response(jsonEncode({'id': 'item-456'}), 201);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final id = await client.addDownload(url: 'https://youtube.com/watch?v=abc');
        expect(id, equals('item-456'));
      });

      test('updateDownload sends PATCH /downloads with id and action', () async {
        final mockClient = MockClient((request) async {
          expect(request.method, equals('PATCH'));
          expect(request.url.path, equals('/downloads'));
          expect(request.url.queryParameters['id'], equals('123'));
          expect(request.url.queryParameters['action'], equals('pause'));
          return http.Response(jsonEncode({'message': 'paused'}), 200);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        await expectLater(
          client.updateDownload(id: '123', action: 'pause'),
          completes,
        );
      });

      test('getEntriesToSelect and selectEntries work correctly', () async {
        final mockClient = MockClient((request) async {
          if (request.method == 'GET') {
            expect(request.url.path, equals('/select-entries'));
            expect(request.url.queryParameters['id'], equals('dl-1'));
            return http.Response(jsonEncode({'entries': ['1', '2']}), 200);
          } else if (request.method == 'POST') {
            expect(request.url.path, equals('/select-entries'));
            expect(request.url.queryParameters['id'], equals('dl-1'));
            final body = jsonDecode(request.body);
            expect(body['entries'], equals(['1']));
            return http.Response(jsonEncode({'message': 'selected'}), 200);
          }
          return http.Response('Not Found', 404);
        });

        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );

        final entries = await client.getEntriesToSelect(id: 'dl-1');
        expect(entries, equals(['1', '2']));

        await expectLater(
          client.selectEntries(id: 'dl-1', entries: ['1']),
          completes,
        );
      });
    });

    group('Scenario 1: Network Timeouts', () {
      test('otaAction(load) returns false when request times out (>15s)', () async {
        final mockClient = MockClient((request) async {
          throw TimeoutException('Request timed out after 15s');
        });
        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );
        final result = await client.otaAction('load');
        expect(result, isFalse);
      });

      test('otaAction(unload) returns false when request times out (>15s)', () async {
        final mockClient = MockClient((request) async {
          throw TimeoutException('Request timed out after 15s');
        });
        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );
        final result = await client.otaAction('unload');
        expect(result, isFalse);
      });

      test('healthCheck returns false when request times out (>2s)', () async {
        final mockClient = MockClient((request) async {
          throw TimeoutException('Health check timed out after 2s');
        });
        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          client: mockClient,
        );
        final result = await client.healthCheck();
        expect(result, isFalse);
      });

      test('data endpoints throw TimeoutException when client timeout duration is exceeded', () async {
        final mockClient = MockClient((request) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return http.Response('{}', 200);
        });
        final client = VidraHttpClient(
          baseUrl: baseUrl,
          defaultHeaders: {},
          token: token,
          timeout: const Duration(milliseconds: 10),
          client: mockClient,
        );

        expect(() => client.getLogs(), throwsA(isA<TimeoutException>()));
        expect(() => client.getDownloads(), throwsA(isA<TimeoutException>()));
        expect(() => client.addDownload(url: 'https://test.com'), throwsA(isA<TimeoutException>()));
        expect(() => client.updateDownload(id: '1', action: 'pause'), throwsA(isA<TimeoutException>()));
        expect(() => client.getEntriesToSelect(id: '1'), throwsA(isA<TimeoutException>()));
        expect(() => client.selectEntries(id: '1', entries: []), throwsA(isA<TimeoutException>()));
      });
    });

    group('Scenario 2: HTTP Status Codes (400, 401, 403, 404, 500, 502, 503, 504)', () {
      final statusCodes = [400, 401, 403, 404, 500, 502, 503, 504];

      for (final code in statusCodes) {
        test('otaAction returns false on HTTP $code', () async {
          final mockClient = MockClient((request) async {
            return http.Response(jsonEncode({'error': 'HTTP $code occurred'}), code);
          });
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
          final loadResult = await client.otaAction('load');
          final unloadResult = await client.otaAction('unload');
          expect(loadResult, isFalse);
          expect(unloadResult, isFalse);
        });

        test('healthCheck returns false on HTTP $code', () async {
          final mockClient = MockClient((request) async {
            return http.Response(jsonEncode({'error': 'Server error'}), code);
          });
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
          final result = await client.healthCheck();
          expect(result, isFalse);
        });
      }

      test('getLogs throws detailed Exception on 400, 401, 500', () async {
        for (final code in [400, 401, 500]) {
          final mockClient = MockClient((request) async => http.Response('Error body $code', code));
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
          expect(
            () => client.getLogs(),
            throwsA(predicate((e) => e is Exception && e.toString().contains('$code') && e.toString().contains('Error body $code'))),
          );
        }
      });

      test('getDownloads throws detailed Exception on 400, 401, 500', () async {
        for (final code in [400, 401, 500]) {
          final mockClient = MockClient((request) async => http.Response('{"error": "fail"}', code));
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
          expect(
            () => client.getDownloads(),
            throwsA(predicate((e) => e is Exception && e.toString().contains('$code'))),
          );
        }
      });

      test('addDownload throws detailed Exception when response is not 201 (e.g. 200, 400, 500)', () async {
        for (final code in [200, 400, 401, 500]) {
          final mockClient = MockClient((request) async => http.Response('{"error": "invalid"}', code));
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
          expect(
            () => client.addDownload(url: 'https://test.com'),
            throwsA(predicate((e) => e is Exception && e.toString().contains('$code'))),
          );
        }
      });

      test('updateDownload throws detailed Exception on non-200 status', () async {
        for (final code in [400, 404, 500]) {
          final mockClient = MockClient((request) async => http.Response('Cannot resume', code));
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
          expect(
            () => client.updateDownload(id: '123', action: 'resume'),
            throwsA(predicate((e) => e is Exception && e.toString().contains('$code') && e.toString().contains('resume'))),
          );
        }
      });

      test('getEntriesToSelect throws detailed Exception on non-200 status', () async {
        for (final code in [404, 500]) {
          final mockClient = MockClient((request) async => http.Response('Not found', code));
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
          expect(
            () => client.getEntriesToSelect(id: 'dl-1'),
            throwsA(predicate((e) => e is Exception && e.toString().contains('$code'))),
          );
        }
      });

      test('selectEntries throws detailed Exception on non-200 status', () async {
        for (final code in [400, 500]) {
          final mockClient = MockClient((request) async => http.Response('Invalid selection', code));
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
          expect(
            () => client.selectEntries(id: 'dl-1', entries: ['1']),
            throwsA(predicate((e) => e is Exception && e.toString().contains('$code'))),
          );
        }
      });

      test('subscribeToDeltas throws detailed Exception on non-200 status stream', () async {
        final mockClient = MockClient((request) async => http.Response('Unauthorized stream', 401));
        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
        expect(
          client.subscribeToDeltas().toList(),
          throwsA(predicate((e) => e is Exception && e.toString().contains('401') && e.toString().contains('Unauthorized stream'))),
        );
      });
    });

    group('Scenario 3: Socket Exceptions & Network Down Scenarios', () {
      test('otaAction returns false on SocketException', () async {
        final mockClient = MockClient((request) async => throw const SocketException('Connection refused'));
        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        expect(await client.otaAction('load'), isFalse);
        expect(await client.otaAction('unload'), isFalse);
      });

      test('otaAction returns false on ClientException (connection closed prematurely)', () async {
        final mockClient = MockClient((request) async => throw http.ClientException('Connection closed before headers'));
        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        expect(await client.otaAction('load'), isFalse);
      });

      test('otaAction returns false on HttpException and HandshakeException', () async {
        final mockClient1 = MockClient((request) async => throw const HttpException('Connection reset by peer'));
        final client1 = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient1);
        expect(await client1.otaAction('load'), isFalse);

        final mockClient2 = MockClient((request) async => throw const HandshakeException('TLS handshake failed'));
        final client2 = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient2);
        expect(await client2.otaAction('load'), isFalse);
      });

      test('healthCheck returns false on SocketException and HttpException', () async {
        final mockClient = MockClient((request) async => throw const SocketException('Network unreachable'));
        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
        expect(await client.healthCheck(), isFalse);
      });
    });

    group('Scenario 4: Malformed Responses, Null/Dynamic Tokens & Query Encoding', () {
      test('healthCheck returns false on non-JSON response (HTML or plain text)', () async {
        final mockClient = MockClient((request) async => http.Response('<html>502 Bad Gateway</html>', 200));
        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
        expect(await client.healthCheck(), isFalse);
      });

      test('healthCheck returns false when response JSON is not a Map (e.g. array, integer, bool, null)', () async {
        for (final body in ['[1, 2, 3]', '123', 'true', 'null', '""']) {
          final mockClient = MockClient((request) async => http.Response(body, 200));
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
          expect(await client.healthCheck(), isFalse);
        }
      });

      test('healthCheck returns false when map has missing or invalid status value', () async {
        for (final body in ['{}', '{"status": null}', '{"status": 123}', '{"status": "error"}', '{"status": "unhealthy"}']) {
          final mockClient = MockClient((request) async => http.Response(body, 200));
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
          expect(await client.healthCheck(), isFalse);
        }
      });

      test('otaAction correctly encodes special characters, unicode, spaces and query parameter injection', () async {
        final capturedUris = <Uri>[];
        final mockClient = MockClient((request) async {
          capturedUris.add(request.url);
          return http.Response(jsonEncode({'message': 'OK'}), 200);
        });
        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);

        await client.otaAction('load & hot-reload');
        await client.otaAction('acción');
        await client.otaAction('load?admin=true&action=override');
        await client.otaAction('unload#fragment');

        expect(capturedUris[0].queryParameters['action'], equals('load & hot-reload'));
        expect(capturedUris[1].queryParameters['action'], equals('acción'));
        expect(capturedUris[2].queryParameters['action'], equals('load?admin=true&action=override'));
        expect(capturedUris[3].queryParameters['action'], equals('unload#fragment'));
      });

      test('VidraHttpClient handles token: null by omitting Authorization header', () async {
        final mockClient = MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        });
        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {'X-Custom': 'Val'}, token: null, client: mockClient);
        expect(await client.healthCheck(), isTrue);
      });

      test('VidraHttpClient supports dynamically mutating token and preserves custom headers', () async {
        final capturedHeaders = <Map<String, String>>[];
        final mockClient = MockClient((request) async {
          capturedHeaders.add(Map.from(request.headers));
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        });
        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {'X-App-Id': 'VidraApp'}, token: null, client: mockClient);

        await client.healthCheck();
        expect(capturedHeaders[0].containsKey('Authorization'), isFalse);
        expect(capturedHeaders[0]['X-App-Id'], equals('VidraApp'));
        expect(capturedHeaders[0]['Content-Type'], equals('application/json'));

        client.token = 'dynamic_token_abc';
        await client.healthCheck();
        expect(capturedHeaders[1]['Authorization'], equals('Bearer dynamic_token_abc'));
        expect(capturedHeaders[1]['X-App-Id'], equals('VidraApp'));
      });

      test('getEntriesToSelect returns empty list when entries key is missing, null, or body is not a map', () async {
        for (final body in ['{}', '{"entries": null}', '{"other": "data"}', '[1, 2, 3]']) {
          final mockClient = MockClient((request) async => http.Response(body, 200));
          final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, client: mockClient);
          final result = await client.getEntriesToSelect(id: 'dl-1');
          expect(result, isEmpty);
        }
      });
    });

    group('Scenario 5: Multiple Rapid Concurrent Calls & SSE Stream', () {
      test('100 rapid concurrent calls to otaAction complete independently without race conditions', () async {
        var callCount = 0;
        final mockClient = MockClient((request) async {
          callCount++;
          final action = request.url.queryParameters['action'];
          return http.Response(jsonEncode({'action': action}), 200);
        });
        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);

        final futures = List.generate(100, (i) => client.otaAction(i.isEven ? 'load' : 'unload'));
        final results = await Future.wait(futures);

        expect(results.length, equals(100));
        expect(results.every((r) => r == true), isTrue);
        expect(callCount, equals(100));
      });

      test('100 rapid concurrent calls with mixed responses (success, error, timeout, socket exception) isolate failures', () async {
        final mockClient = MockClient((request) async {
          final action = request.url.queryParameters['action'];
          final index = int.tryParse(action ?? '') ?? 0;
          if (index % 4 == 0) {
            return http.Response('{"status": "ok"}', 200);
          } else if (index % 4 == 1) {
            return http.Response('{"error": "Server error"}', 500);
          } else if (index % 4 == 2) {
            throw const SocketException('Connection reset');
          } else {
            throw TimeoutException('Timed out');
          }
        });
        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);

        final futures = List.generate(100, (i) => client.otaAction(i.toString()));
        final results = await Future.wait(futures);

        expect(results.length, equals(100));
        for (var i = 0; i < 100; i++) {
          if (i % 4 == 0) {
            expect(results[i], isTrue, reason: 'Index $i should succeed');
          } else {
            expect(results[i], isFalse, reason: 'Index $i should return false');
          }
        }
      });

      test('subscribeToDeltas properly parses SSE event stream with comments, bursts, and empty lines', () async {
        final sseData = utf8.encode(
          ': ping comment\n'
          '\n'
          'data: [{"id": "1", "progress": 10.0}]\n'
          '\n'
          ': keep-alive\n'
          'data: [{"id": "1", "progress": 50.0}, {"id": "2", "progress": 0.0}]\n'
          '\n'
          'data: [{"id": "1", "progress": 100.0}]\n'
          '\n',
        );

        final mockClient = MockClient.streaming((request, bodyStream) async {
          expect(request.url.path, equals('/subscribe'));
          return http.StreamedResponse(
            Stream.value(sseData),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });

        final client = VidraHttpClient(baseUrl: baseUrl, defaultHeaders: {}, token: token, client: mockClient);
        final events = await client.subscribeToDeltas().toList();

        expect(events.length, equals(3));
        expect(events[0], equals([{'id': '1', 'progress': 10.0}]));
        expect(events[1].length, equals(2));
        expect(events[2], equals([{'id': '1', 'progress': 100.0}]));
      });
    });
  });
}
