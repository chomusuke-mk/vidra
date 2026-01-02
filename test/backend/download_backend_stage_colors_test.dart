import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/ui/theme/download_visuals.dart';

import '../test_auth_token.dart';

const bool _runBackendTests = bool.fromEnvironment(
  'VIDRA_RUN_BACKEND_TESTS',
  defaultValue: false,
);
const String _backendSkipReason =
    'Set --dart-define=VIDRA_RUN_BACKEND_TESTS=true to enable backend tests.';

const _backendBase = 'http://127.0.0.1:5000';
const _testUrl = 'https://www.youtube.com/watch?v=NY__VTIUsiU';
late String _backendToken;

Future<void> main() async {
  if (!_runBackendTests) {
    test(
      'Download stage colors remain non-error while job is running',
      () async {},
      skip: _backendSkipReason,
    );
    return;
  }

  _backendToken = await loadTestAuthToken();
  final backendAvailable = await _isBackendAvailable();

  test(
    'Download stage colors remain non-error while job is running',
    () async {
      final jobId = await _scheduleDownload();
      addTearDown(() async => _deleteJob(jobId));

      final snapshots = <DownloadJobModel>[];
      final timeout = DateTime.now().add(const Duration(minutes: 2));

      while (DateTime.now().isBefore(timeout)) {
        final snapshot = await _fetchJob(jobId);
        if (snapshot == null) {
          break;
        }
        snapshots.add(snapshot);
        if (snapshot.isTerminal) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      expect(
        snapshots,
        isNotEmpty,
        reason: 'Backend did not return any job snapshots',
      );

      final runningSnapshots = snapshots
          .where((job) => !job.isTerminal && job.progress != null)
          .toList(growable: false);

      expect(
        runningSnapshots,
        isNotEmpty,
        reason: 'Expected at least one running snapshot',
      );

      for (final job in runningSnapshots) {
        final stageColor = DownloadVisualPalette.stageColor(
          job.progress?.stage,
          status: job.progress?.status,
          postprocessor: job.progress?.postprocessor,
          preprocessor: job.progress?.preprocessor,
          jobStatus: job.status,
        );
        expect(
          stageColor,
          isNot(equals(DownloadVisualPalette.stageErrorColor)),
          reason:
              'Stage color should not be the error palette while job ${job.id} is ${job.status}',
        );
        expect(
          job.error?.isEmpty ?? true,
          isTrue,
          reason:
              'Non-terminal job ${job.id} should not expose error text while active',
        );
      }
    },
    skip: backendAvailable ? false : 'Backend is not running on $_backendBase',
  );
}

void _attachAuthHeaders(HttpClientRequest request) {
  if (_backendToken.isEmpty) {
    return;
  }
  request.headers.add(HttpHeaders.authorizationHeader, 'Bearer $_backendToken');
  request.headers.add('X-API-Token', _backendToken);
}

Future<bool> _isBackendAvailable() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(_backendBase));
    _attachAuthHeaders(request);
    final response = await request.close();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
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

Future<String> _scheduleDownload() async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$_backendBase/api/jobs'));
    _attachAuthHeaders(request);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, dynamic>{'urls': _testUrl}));
    final response = await request.close();
    final payload = await _decodeResponse(response);
    if (response.statusCode != 201) {
      throw StateError(
        'Failed to schedule download: ${response.statusCode} ${payload['error'] ?? ''}',
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

Future<DownloadJobModel?> _fetchJob(String jobId) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('$_backendBase/api/jobs/$jobId'),
    );
    _attachAuthHeaders(request);
    final response = await request.close();
    if (response.statusCode == 404) {
      return null;
    }
    final payload = await _decodeResponse(response);
    return DownloadJobModel.fromJson(payload);
  } finally {
    client.close();
  }
}

Future<void> _deleteJob(String jobId) async {
  final client = HttpClient();
  try {
    final request = await client.deleteUrl(
      Uri.parse('$_backendBase/api/jobs/$jobId'),
    );
    _attachAuthHeaders(request);
    await request.close();
  } catch (_) {
    // Ignore cleanup failures; job may already be gone.
  } finally {
    client.close();
  }
}
