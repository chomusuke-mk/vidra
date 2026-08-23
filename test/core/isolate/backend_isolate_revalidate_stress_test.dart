import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vidra/core/network/vidra_http_client.dart';

/// Test harness faithful to backend_isolate.dart revalidate & OTA logic
class BackendIsolateRevalidateHarness {
  final VidraHttpClient httpClient;
  final void Function(Map<String, dynamic> msg) onSendPortMessage;
  final Future<bool> Function() checkPermissionsFn;
  final bool Function() checkResourcesFn;
  final Future<bool> Function() startPythonBackendFn;
  final void Function()? onTerminateSeriousPython;
  final Duration retryDelay;

  String state = 'initializing';
  bool isUpdating = false;
  bool isInitializing = false;
  bool isBackendRunning = false;
  Timer? healthCheckTimer;
  int failedPings = 0;
  String? pythonAppPath;

  BackendIsolateRevalidateHarness({
    required this.httpClient,
    required this.onSendPortMessage,
    required this.checkPermissionsFn,
    required this.checkResourcesFn,
    required this.startPythonBackendFn,
    this.onTerminateSeriousPython,
    this.pythonAppPath = '/mock/python/app',
    this.retryDelay = const Duration(milliseconds: 10), // Configurable for fast tests
  });

  void notifyUiState(String newState) {
    if (state != newState) {
      state = newState;
      onSendPortMessage({'event': 'state', 'value': state});
    }
  }

  void startHealthCheck() {
    healthCheckTimer?.cancel();
    failedPings = 0;
    healthCheckTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      if (isUpdating) return;
      final isAlive = await httpClient.healthCheck();
      if (isAlive) {
        if (state != 'ready') {
          failedPings = 0;
          notifyUiState('ready');
        }
      } else {
        failedPings++;
        notifyUiState('retrying');
        if (failedPings >= 30) {
          onTerminateSeriousPython?.call();
          isBackendRunning = false;
          failedPings = 0;
          notifyUiState('startingBackend');
          if (!await startPythonBackendFn()) {
            notifyUiState('fatalError');
          } else {
            isBackendRunning = true;
          }
        }
      }
    });
  }

  Future<void> initSequence() async {
    if (isUpdating || isInitializing) return;
    isInitializing = true;
    try {
      notifyUiState('initializing');

      if (!await checkPermissionsFn()) {
        notifyUiState('missingPermissions');
        return;
      }

      if (!checkResourcesFn()) {
        notifyUiState('missingResources');
        return;
      }

      if (pythonAppPath == null) {
        notifyUiState('unpacking');
        return;
      }

      if (isBackendRunning) {
        return;
      }

      notifyUiState('startingBackend');
      if (!await startPythonBackendFn()) {
        notifyUiState('fatalError');
        return;
      }
      isBackendRunning = true;
      startHealthCheck();
    } finally {
      isInitializing = false;
    }
  }

  Future<void> handleCommand(Map<String, dynamic> message) async {
    final cmd = message['cmd'];

    switch (cmd) {
      case 'revalidate':
        isUpdating = false;
        if (isBackendRunning) {
          bool ok = false;
          for (int attempt = 1; attempt <= 15; attempt++) {
            ok = await httpClient.otaAction('load');
            if (ok) {
              break;
            }
            await Future.delayed(retryDelay);
          }

          if (ok) {
            startHealthCheck();
          } else {
            onTerminateSeriousPython?.call();
            isBackendRunning = false;
            failedPings = 0;
            notifyUiState('startingBackend');
            if (!await startPythonBackendFn()) {
              notifyUiState('fatalError');
            } else {
              isBackendRunning = true;
              startHealthCheck();
            }
          }
        } else {
          await initSequence();
        }
        break;

      case 'pause_for_update':
        isUpdating = true;
        healthCheckTimer?.cancel();
        await httpClient.otaAction('unload');
        notifyUiState('initializing');
        onSendPortMessage({'event': 'paused_ack'});
        break;
    }
  }

  void dispose() {
    healthCheckTimer?.cancel();
  }
}

void main() {
  group('BackendIsolate Revalidate Polling & Resurrection Stress Tests', () {
    late List<Map<String, dynamic>> sentMessages;
    late List<String> otaActionsCalled;

    setUp(() {
      sentMessages = [];
      otaActionsCalled = [];
    });

    test('1. Revalidate with 0 delay (succeeds on attempt 1)', () async {
      int attempts = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/ota') {
          attempts++;
          otaActionsCalled.add(request.url.queryParameters['action'] ?? '');
          return http.Response(jsonEncode({'message': 'ok'}), 200);
        }
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = VidraHttpClient(
        baseUrl: 'http://127.0.0.1:5000',
        defaultHeaders: {},
        token: 'test_token',
        client: mockClient,
      );

      final harness = BackendIsolateRevalidateHarness(
        httpClient: httpClient,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () async => true,
        checkResourcesFn: () => true,
        startPythonBackendFn: () async => true,
      );

      harness.isBackendRunning = true;
      harness.state = 'initializing';

      await harness.handleCommand({'cmd': 'revalidate'});

      expect(attempts, equals(1));
      expect(otaActionsCalled, equals(['load']));
      expect(harness.isBackendRunning, isTrue);
      expect(harness.state, isNot('fatalError'));
      expect(harness.healthCheckTimer?.isActive, isTrue);

      harness.dispose();
    });

    test('2. Revalidate with medium delay (fails 4 times, succeeds on attempt 5)', () async {
      int attempts = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/ota') {
          attempts++;
          otaActionsCalled.add(request.url.queryParameters['action'] ?? '');
          if (attempts < 5) {
            return http.Response(jsonEncode({'error': 'server warming up'}), 503);
          }
          return http.Response(jsonEncode({'message': 'ok'}), 200);
        }
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = VidraHttpClient(
        baseUrl: 'http://127.0.0.1:5000',
        defaultHeaders: {},
        token: 'test_token',
        client: mockClient,
      );

      final harness = BackendIsolateRevalidateHarness(
        httpClient: httpClient,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () async => true,
        checkResourcesFn: () => true,
        startPythonBackendFn: () async => true,
      );

      harness.isBackendRunning = true;
      harness.state = 'initializing';

      await harness.handleCommand({'cmd': 'revalidate'});

      expect(attempts, equals(5));
      expect(otaActionsCalled.length, equals(5));
      expect(harness.isBackendRunning, isTrue);
      expect(harness.state, isNot('fatalError'));
      expect(harness.healthCheckTimer?.isActive, isTrue);

      harness.dispose();
    });

    test('3. Revalidate near threshold (fails 14 times, succeeds on attempt 15)', () async {
      int attempts = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/ota') {
          attempts++;
          otaActionsCalled.add(request.url.queryParameters['action'] ?? '');
          if (attempts < 15) {
            return http.Response(jsonEncode({'error': 'busy'}), 500);
          }
          return http.Response(jsonEncode({'message': 'ok'}), 200);
        }
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = VidraHttpClient(
        baseUrl: 'http://127.0.0.1:5000',
        defaultHeaders: {},
        token: 'test_token',
        client: mockClient,
      );

      final harness = BackendIsolateRevalidateHarness(
        httpClient: httpClient,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () async => true,
        checkResourcesFn: () => true,
        startPythonBackendFn: () async => true,
      );

      harness.isBackendRunning = true;
      harness.state = 'initializing';

      await harness.handleCommand({'cmd': 'revalidate'});

      expect(attempts, equals(15));
      expect(harness.isBackendRunning, isTrue);
      expect(harness.state, isNot('fatalError'));
      expect(harness.healthCheckTimer?.isActive, isTrue);

      harness.dispose();
    });

    test('4. Revalidate failure triggers resurrection fallback successfully', () async {
      int attempts = 0;
      bool terminated = false;
      bool resurrected = false;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/ota') {
          attempts++;
          otaActionsCalled.add(request.url.queryParameters['action'] ?? '');
          // All 15 attempts fail
          return http.Response(jsonEncode({'error': 'dead'}), 500);
        }
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = VidraHttpClient(
        baseUrl: 'http://127.0.0.1:5000',
        defaultHeaders: {},
        token: 'test_token',
        client: mockClient,
      );

      final harness = BackendIsolateRevalidateHarness(
        httpClient: httpClient,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () async => true,
        checkResourcesFn: () => true,
        onTerminateSeriousPython: () {
          terminated = true;
        },
        startPythonBackendFn: () async {
          resurrected = true;
          return true;
        },
      );

      harness.isBackendRunning = true;
      harness.state = 'initializing';

      await harness.handleCommand({'cmd': 'revalidate'});

      expect(attempts, equals(15));
      expect(terminated, isTrue);
      expect(resurrected, isTrue);
      expect(harness.isBackendRunning, isTrue);
      expect(harness.state, isNot('fatalError'));
      expect(
        sentMessages.any((m) => m['event'] == 'state' && m['value'] == 'startingBackend'),
        isTrue,
      );

      harness.dispose();
    });

    test('5. Revalidate failure with failed resurrection triggers fatalError', () async {
      int attempts = 0;
      bool terminated = false;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/ota') {
          attempts++;
          otaActionsCalled.add(request.url.queryParameters['action'] ?? '');
          return http.Response(jsonEncode({'error': 'dead'}), 500);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = VidraHttpClient(
        baseUrl: 'http://127.0.0.1:5000',
        defaultHeaders: {},
        token: 'test_token',
        client: mockClient,
      );

      final harness = BackendIsolateRevalidateHarness(
        httpClient: httpClient,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () async => true,
        checkResourcesFn: () => true,
        onTerminateSeriousPython: () {
          terminated = true;
        },
        startPythonBackendFn: () async {
          return false; // Resurrection fails
        },
      );

      harness.isBackendRunning = true;
      harness.state = 'initializing';

      await harness.handleCommand({'cmd': 'revalidate'});

      expect(attempts, equals(15));
      expect(terminated, isTrue);
      expect(harness.isBackendRunning, isFalse);
      expect(harness.state, equals('fatalError'));
      expect(
        sentMessages.any((m) => m['event'] == 'state' && m['value'] == 'fatalError'),
        isTrue,
      );

      harness.dispose();
    });
  });
}
