import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vidra/core/network/vidra_http_client.dart';
import 'backend_isolate_lifecycle_test.dart';

void main() {
  group('BackendIsolate Permission Verification', () {
    late List<Map<String, dynamic>> sentMessages;

    setUp(() {
      sentMessages = [];
    });

    VidraHttpClient createMockClient() {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
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

    /// Replicates the exact checkPermissions logic in backend_isolate.dart:
    /// Storage (manageExternalStorage on SDK>=30 or storage on SDK<30),
    /// Notification (on SDK>=33),
    /// Battery Optimization (ignoreBatteryOptimizations).
    /// Overlay permission is NOT checked.
    Future<bool> checkPermissionsLogic({
      required bool isAndroid,
      required int sdkInt,
      required bool storageGranted,
      required bool notificationGranted,
      required bool batteryGranted,
      required bool overlayGranted, // Overlay is explicitly tracked to prove it does not affect the result
    }) async {
      if (!isAndroid) return true;
      try {
        bool effectiveStorage = storageGranted;
        bool effectiveNotif = sdkInt >= 33 ? notificationGranted : true;
        bool effectiveBattery = batteryGranted;
        return effectiveStorage && effectiveNotif && effectiveBattery;
      } catch (e) {
        return false;
      }
    }

    test('Backend starts up to ready when mandatory permissions are granted even if overlay permission is DENIED', (
    ) async {
      final client = createMockClient();
      bool backendStarted = false;

      final harness = BackendIsolateLifecycleHarness(
        httpClient: client,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () => checkPermissionsLogic(
          isAndroid: true,
          sdkInt: 33,
          storageGranted: true,
          notificationGranted: true,
          batteryGranted: true,
          overlayGranted: false, // Overlay denied
        ),
        checkResourcesFn: () => true,
        startPythonBackendFn: () async {
          backendStarted = true;
          return true;
        },
      );

      await harness.initSequence();

      expect(backendStarted, isTrue);
      expect(harness.isBackendRunning, isTrue);
      expect(harness.state, equals('ready'));
      expect(
        sentMessages.any((m) => m['event'] == 'state' && m['value'] == 'missingPermissions'),
        isFalse,
      );

      harness.dispose();
    });

    test('Backend transitions to missingPermissions when storage is missing', () async {
      final client = createMockClient();
      bool backendStarted = false;

      final harness = BackendIsolateLifecycleHarness(
        httpClient: client,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () => checkPermissionsLogic(
          isAndroid: true,
          sdkInt: 33,
          storageGranted: false, // Missing storage
          notificationGranted: true,
          batteryGranted: true,
          overlayGranted: true,
        ),
        checkResourcesFn: () => true,
        startPythonBackendFn: () async {
          backendStarted = true;
          return true;
        },
      );

      await harness.initSequence();

      expect(backendStarted, isFalse);
      expect(harness.isBackendRunning, isFalse);
      expect(harness.state, equals('missingPermissions'));
      expect(
        sentMessages.any((m) => m['event'] == 'state' && m['value'] == 'missingPermissions'),
        isTrue,
      );

      harness.dispose();
    });

    test('Backend transitions to missingPermissions when battery optimization is missing', () async {
      final client = createMockClient();
      bool backendStarted = false;

      final harness = BackendIsolateLifecycleHarness(
        httpClient: client,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () => checkPermissionsLogic(
          isAndroid: true,
          sdkInt: 33,
          storageGranted: true,
          notificationGranted: true,
          batteryGranted: false, // Missing battery
          overlayGranted: true,
        ),
        checkResourcesFn: () => true,
        startPythonBackendFn: () async {
          backendStarted = true;
          return true;
        },
      );

      await harness.initSequence();

      expect(backendStarted, isFalse);
      expect(harness.isBackendRunning, isFalse);
      expect(harness.state, equals('missingPermissions'));

      harness.dispose();
    });

    test('Backend transitions to missingPermissions when notification is missing on SDK 33', () async {
      final client = createMockClient();
      bool backendStarted = false;

      final harness = BackendIsolateLifecycleHarness(
        httpClient: client,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () => checkPermissionsLogic(
          isAndroid: true,
          sdkInt: 33,
          storageGranted: true,
          notificationGranted: false, // Missing notification on SDK 33
          batteryGranted: true,
          overlayGranted: true,
        ),
        checkResourcesFn: () => true,
        startPythonBackendFn: () async {
          backendStarted = true;
          return true;
        },
      );

      await harness.initSequence();

      expect(backendStarted, isFalse);
      expect(harness.isBackendRunning, isFalse);
      expect(harness.state, equals('missingPermissions'));

      harness.dispose();
    });

    test('Backend automatically bypasses permission checks on non-Android platform', () async {
      final client = createMockClient();
      bool backendStarted = false;

      final harness = BackendIsolateLifecycleHarness(
        httpClient: client,
        onSendPortMessage: (msg) => sentMessages.add(msg),
        checkPermissionsFn: () => checkPermissionsLogic(
          isAndroid: false,
          sdkInt: 0,
          storageGranted: false,
          notificationGranted: false,
          batteryGranted: false,
          overlayGranted: false,
        ),
        checkResourcesFn: () => true,
        startPythonBackendFn: () async {
          backendStarted = true;
          return true;
        },
      );

      await harness.initSequence();

      expect(backendStarted, isTrue);
      expect(harness.isBackendRunning, isTrue);
      expect(harness.state, equals('ready'));

      harness.dispose();
    });
  });
}
