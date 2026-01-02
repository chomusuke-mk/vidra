import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/data/services/download_service.dart';

const String _testToken = 'test-token';

void main() {
  group('DownloadService', () {
    late BackendConfig config;

    setUp(() {
      config = BackendConfig(
        name: 'Test Backend',
        description: 'Test Description',
        baseUri: Uri.parse('http://127.0.0.1:5000/'),
        apiBaseUri: Uri.parse('http://127.0.0.1:5000/api/'),
        overviewSocketUri: Uri.parse('ws://127.0.0.1:5000/ws/overview'),
        jobSocketBaseUri: Uri.parse('ws://127.0.0.1:5000/ws/jobs/'),
        metadata: const {},
        timeout: const Duration(seconds: 30),
      );
    });

    test('createJob sends POST with expected payload', () async {
      late http.Request capturedRequest;
      var getCalls = 0;
      final client = MockClient((request) async {
        capturedRequest = request;
        if (request.method == 'POST') {
          final responseBody = jsonEncode({
            'job_id': 'job-1',
            'status': 'queued',
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'urls': ['https://example.com'],
            'options': {'extract_audio': true},
            'metadata': {
              'preview': {
                'title': 'Example Video',
                'thumbnail_url': 'https://example.com/thumb.jpg',
                'description': 'Sample description',
              },
            },
            'progress': {},
            'logs': [],
          });
          return http.Response(
            responseBody,
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET') {
          getCalls += 1;
          final detailBody = jsonEncode({
            'job_id': 'job-1',
            'status': 'queued',
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'urls': ['https://example.com'],
            'options': {'extract_audio': true},
            'metadata': {},
            'progress': {},
            'logs': [],
          });
          return http.Response(
            detailBody,
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Unsupported', 400);
      });

      final service = DownloadService(
        config,
        authToken: _testToken,
        httpClient: client,
      );
      final job = await service.createJob('https://example.com', {
        'extract_audio': true,
      });

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.url.toString(), 'http://127.0.0.1:5000/api/jobs');
      expect(
        capturedRequest.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(capturedRequest.headers['authorization'], 'Bearer $_testToken');
      expect(capturedRequest.headers['x-api-token'], _testToken);

      final payload = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(payload['urls'], 'https://example.com');
      expect(payload['options'], containsPair('extract_audio', true));

      expect(job.id, 'job-1');
      expect(job.status.name, 'queued');
      expect(getCalls, 0);
      expect(job.urls, contains('https://example.com'));
      expect(job.preview?.title, 'Example Video');
      expect(job.preview?.bestThumbnailUrl, 'https://example.com/thumb.jpg');
    });

    test('createJob follows 308 redirect automatically', () async {
      final postResponses = <http.Response>[
        http.Response('', 308, headers: {'location': '/api/jobs'}),
        http.Response(
          jsonEncode({
            'job_id': 'job-redirect',
            'status': 'queued',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }),
          201,
          headers: {'content-type': 'application/json'},
        ),
      ];

      final bodies = <String?>[];
      var getCalls = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          bodies.add(request.body);
          return postResponses.removeAt(0);
        }
        if (request.method == 'GET') {
          getCalls += 1;
          final detailBody = jsonEncode({
            'job_id': 'job-redirect',
            'status': 'queued',
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'urls': ['https://redirected'],
            'options': {},
            'metadata': {},
            'progress': {},
            'logs': [],
          });
          return http.Response(
            detailBody,
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Unsupported', 400);
      });

      final service = DownloadService(
        config,
        authToken: _testToken,
        httpClient: client,
      );
      final job = await service.createJob('https://redirected', {});

      expect(bodies.length, 2);
      expect(bodies[0], equals(bodies[1]));
      expect(job.id, 'job-redirect');
      expect(getCalls, 0);
    });
  });
}
