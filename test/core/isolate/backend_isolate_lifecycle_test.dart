import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vidra/core/network/vidra_http_client.dart';

/// Test harness implementing the exact state machine and command handlers of backend_isolate.dart
class BackendIsolateLifecycleHarness {
  final VidraHttpClient httpClient;
  final void Function(Map<String, dynamic> msg) onSendPortMessage;
  final Future<bool> Function() checkPermissionsFn;
  final bool Function() checkResourcesFn;
  final Future<bool> Function() startPythonBackendFn;

  String state = 'initializing';
  bool isUpdating = false;
  bool isInitializing = false;
  bool isBackendRunning = false;
  Timer? healthCheckTimer;
  StreamSubscription? sseSubscription;
  String? pythonAppPath;

  BackendIsolateLifecycleHarness({
    required this.httpClient,
    required this.onSendPortMessage,
    required this.checkPermissionsFn,
    required this.checkResourcesFn,
    required this.startPythonBackendFn,
    this.pythonAppPath = '/path/to/python/app',
  });

  void notifyUiState(String newState) {
    if (state != newState) {
      state = newState;
      onSendPortMessage({'event': 'state', 'value': state});
    }
  }

  void startHealthCheck() {
    healthCheckTimer?.cancel();
    healthCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {});
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
      notifyUiState('ready');
    } finally {
      isInitializing = false;
    }
  }

  Future<void> handleCommand(Map<String, dynamic> message) async {
    final cmd = message['cmd'];

    switch (cmd) {
      case 'revalidate':
        if (isBackendRunning) {
          final ok = await httpClient.otaAction('load');
          isUpdating = false;
          if (ok) {
            startHealthCheck();
          } else {
            notifyUiState('fatalError');
          }
        } else {
          isUpdating = false;
          await initSequence();
        }
        break;

      case 'pause_for_update':
        isUpdating = true;
        healthCheckTimer?.cancel();
        sseSubscription?.cancel();
        await httpClient.otaAction('unload');
        notifyUiState('initializing');
        onSendPortMessage({'event': 'paused_ack'});
        break;
    }
  }

  void dispose() {
    healthCheckTimer?.cancel();
    sseSubscription?.cancel();
  }
}

void main() {
  group('BackendIsolate Lifecycle & State Transitions', () {
    late List<Map<String, dynamic>> sentMessages;
    late List<String> otaActionsCalled;

    setUp(() {
      sentMessages = [];
      otaActionsCalled = [];
    });

    VidraHttpClient createMockClient({
      bool otaSuccess = true,
      int otaStatusCode = 200,
    }) {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/ota') {
          final action = request.url.queryParameters['action'] ?? '';
          otaActionsCalled.add(action);
          if (otaSuccess) {
            return http.Response(jsonEncode({'message': 'OTA ok'}), otaStatusCode);
          } else {
            return http.Response(jsonEncode({'error': 'OTA failed'}), otaStatusCode);
          }
        }
        return http.Response('Not Found', 404);
      });

      return VidraHttpClient(
        baseUrl: 'http://127.0.0.1:5000',
        defaultHeaders: {},
        token: 'test_token',
        client: mockClient,
      );
    }

    test('Scenario 1 (Part A): revalidate when isBackendRunning == true calls otaAction(load)', () async {
      final client = createMockClient(otaSuccess: true);
      final harness = BackendIsolateLifecycleHarness(
        httpClient: client,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () async => true,
        checkResourcesFn: () => true,
        startPythonBackendFn: () async => true,
      );

      // Set initial running state
      harness.isBackendRunning = true;
      harness.isUpdating = true;
      harness.state = 'initializing';

      await harness.handleCommand({'cmd': 'revalidate'});

      expect(otaActionsCalled, equals(['load']));
      expect(harness.isUpdating, isFalse);
      expect(harness.isBackendRunning, isTrue);
      expect(harness.healthCheckTimer?.isActive, isTrue);
      expect(harness.state, isNot('fatalError'));

      harness.dispose();
    });

    test('Scenario 1 (Part A.2): revalidate when isBackendRunning == true and otaAction fails transitions to fatalError', () async {
      final client = createMockClient(otaSuccess: false, otaStatusCode: 500);
      final harness = BackendIsolateLifecycleHarness(
        httpClient: client,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () async => true,
        checkResourcesFn: () => true,
        startPythonBackendFn: () async => true,
      );

      harness.isBackendRunning = true;
      harness.isUpdating = true;
      harness.state = 'initializing';

      await harness.handleCommand({'cmd': 'revalidate'});

      expect(otaActionsCalled, equals(['load']));
      expect(harness.isUpdating, isFalse);
      expect(harness.state, equals('fatalError'));
      expect(
        sentMessages.any(
          (m) => m['event'] == 'state' && m['value'] == 'fatalError',
        ),
        isTrue,
      );

      harness.dispose();
    });

    test('Scenario 1 (Part B): revalidate when isBackendRunning == false invokes initSequence and starts backend', () async {
      final client = createMockClient(otaSuccess: true);
      bool pythonStarted = false;

      final harness = BackendIsolateLifecycleHarness(
        httpClient: client,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () async => true,
        checkResourcesFn: () => true,
        startPythonBackendFn: () async {
          pythonStarted = true;
          return true;
        },
      );

      // Backend is NOT running (e.g. after permissions were resolved)
      harness.isBackendRunning = false;
      harness.isUpdating = true;
      harness.state = 'missingPermissions';

      await harness.handleCommand({'cmd': 'revalidate'});

      // otaAction should NOT have been called because backend wasn't running
      expect(otaActionsCalled, isEmpty);
      expect(harness.isUpdating, isFalse);
      expect(pythonStarted, isTrue);
      expect(harness.isBackendRunning, isTrue);
      expect(harness.state, equals('ready'));

      harness.dispose();
    });

    test('Scenario 2: pause_for_update leaves isBackendRunning == true, cancels timer/SSE, and calls otaAction(unload)', () async {
      final client = createMockClient(otaSuccess: true);
      final harness = BackendIsolateLifecycleHarness(
        httpClient: client,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () async => true,
        checkResourcesFn: () => true,
        startPythonBackendFn: () async => true,
      );

      // Put harness into active running state
      harness.isBackendRunning = true;
      harness.state = 'ready';
      harness.startHealthCheck();

      // Create a dummy active SSE stream subscription
      final streamController = StreamController<List<dynamic>>();
      bool sseCancelled = false;
      streamController.onCancel = () {
        sseCancelled = true;
      };
      harness.sseSubscription = streamController.stream.listen((_) {});

      expect(harness.healthCheckTimer?.isActive, isTrue);
      expect(harness.isBackendRunning, isTrue);

      // Send pause_for_update command
      await harness.handleCommand({'cmd': 'pause_for_update'});

      // 1. isUpdating is set to true
      expect(harness.isUpdating, isTrue);

      // 2. Health check timer is cancelled
      expect(harness.healthCheckTimer?.isActive, isFalse);

      // 3. SSE subscription is cancelled
      expect(sseCancelled, isTrue);

      // 4. HTTP client called otaAction('unload')
      expect(otaActionsCalled, equals(['unload']));

      // 5. isBackendRunning remains TRUE (critical: process is still alive, only modules unloaded)
      expect(harness.isBackendRunning, isTrue);

      // 6. UI notified of state 'initializing' and 'paused_ack' event sent
      expect(harness.state, equals('initializing'));
      expect(
        sentMessages.any(
          (m) => m['event'] == 'state' && m['value'] == 'initializing',
        ),
        isTrue,
      );
      expect(
        sentMessages.any((m) => m['event'] == 'paused_ack'),
        isTrue,
      );

      streamController.close();
      harness.dispose();
    });

    test('OTA Full Lifecycle Sequence: Ready -> Pause -> Update -> Revalidate -> Ready', () async {
      final client = createMockClient(otaSuccess: true);
      final harness = BackendIsolateLifecycleHarness(
        httpClient: client,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () async => true,
        checkResourcesFn: () => true,
        startPythonBackendFn: () async => true,
      );

      // 1. Start up to ready
      await harness.initSequence();
      expect(harness.state, equals('ready'));
      expect(harness.isBackendRunning, isTrue);

      // 2. Pause for update
      await harness.handleCommand({'cmd': 'pause_for_update'});
      expect(harness.isUpdating, isTrue);
      expect(harness.isBackendRunning, isTrue);
      expect(harness.state, equals('initializing'));
      expect(otaActionsCalled, equals(['unload']));

      // 3. Revalidate after OTA update completes
      await harness.handleCommand({'cmd': 'revalidate'});
      expect(harness.isUpdating, isFalse);
      expect(harness.isBackendRunning, isTrue);
      expect(otaActionsCalled, equals(['unload', 'load']));
      expect(harness.healthCheckTimer?.isActive, isTrue);

      harness.dispose();
    });
  });
}
