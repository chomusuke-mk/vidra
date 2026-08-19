import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/presentation/share_wrapper.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

class MockLocaleRepository extends LocaleRepository {
  final Map<String, Map<String, String>> _storage = {};

  MockLocaleRepository() {
    for (final code in ['en', 'es']) {
      final f = File('i18n/$code.jsonc');
      if (f.existsSync()) {
        final raw = f.readAsStringSync();
        final map = (jsonc.decode(raw) as Map).cast<String, dynamic>().map(
              (k, v) => MapEntry(k, v.toString().trim()),
            );
        map.removeWhere((k, v) => v.trim().isEmpty);
        _storage[code] = map;
      }
    }
  }

  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    return _storage[localeCode] ?? {};
  }
}

class FakeSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  @override
  SystemState get state => SystemState.ready;

  @override
  int? get backendPort => 5000;

  @override
  String? get backendToken => 'mock_token';

  @override
  String? get serverLogsFilePath => '/tmp/mock.log';

  @override
  Future<void> get whenPortReady => Future.value();

  final List<Map<String, dynamic>> enqueuedDownloads = [];

  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {
    enqueuedDownloads.add({'url': url, 'options': options});
  }

  @override
  Future<void> resumeInitialization() async {}

  @override
  Future<void> stopBackendForUpdate() async {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class FakeDownloadRepository extends DownloadRepository {
  FakeDownloadRepository()
      : super(VidraHttpClient(baseUrl: 'http://127.0.0.1:5000', defaultHeaders: {}));

  @override
  Future<List<Download>> getAllDownloads() async => [];

  @override
  Stream<List<Delta>> watchGlobalProgress() => const Stream.empty();
}

class FailingDownloadsController extends DownloadsController {
  FailingDownloadsController(super.repository, super.systemController);

  @override
  Future<bool> addDownload(String url, Map<String, dynamic> options) async {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSystemController fakeSystemCtrl;
  late FakeDownloadRepository fakeDownloadRepo;
  late DownloadsController downloadsCtrl;
  late SettingsController settingsCtrl;
  late LocaleController localeCtrl;
  late SharedPreferences prefs;

  late List<MethodCall> overlayChannelCalls;
  late List<dynamic> overlaySharedData;
  late List<MethodCall> vidraChannelCalls;

  int checkPermissionCallCount = 0;
  bool firstCheckResult = false;
  bool secondCheckResult = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'last_seen_changelog_version': '1.0.0',
    });
    prefs = await SharedPreferences.getInstance();

    fakeSystemCtrl = FakeSystemController();
    fakeDownloadRepo = FakeDownloadRepository();
    downloadsCtrl = DownloadsController(fakeDownloadRepo, fakeSystemCtrl);
    final settingsRepo = SettingsRepository(prefs);
    settingsCtrl = SettingsController(settingsRepo);
    settingsCtrl.updateDownloadOptions(DownloadOptions());

    final localeRepo = MockLocaleRepository();
    localeCtrl = LocaleController(localeRepo, 'en');
    await localeCtrl.whenReady;

    overlayChannelCalls = [];
    overlaySharedData = [];
    vidraChannelCalls = [];

    checkPermissionCallCount = 0;
    firstCheckResult = false;
    secondCheckResult = false;

    // Mock ReceiveSharingIntent Channels
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('receive_sharing_intent/messages'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getInitialMedia') {
          return null;
        }
        return null;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('receive_sharing_intent/events-media'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {},
      ),
    );

    // Mock Overlay MethodChannel (x-slayer/overlay_channel)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('x-slayer/overlay_channel'),
      (MethodCall methodCall) async {
        overlayChannelCalls.add(methodCall);
        if (methodCall.method == 'checkPermission') {
          checkPermissionCallCount++;
          if (checkPermissionCallCount == 1) {
            return firstCheckResult;
          }
          return secondCheckResult;
        }
        if (methodCall.method == 'requestPermission') {
          return true;
        }
        if (methodCall.method == 'showOverlay') {
          return true;
        }
        return true;
      },
    );

    // Mock Overlay Messenger BasicMessageChannel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
      const BasicMessageChannel<dynamic>('x-slayer/overlay_messenger', JSONMessageCodec()),
      (dynamic message) async {
        overlaySharedData.add(message);
        return true;
      },
    );

    // Mock Vidra Channel (moveToBackground)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('vidra_channel'),
      (MethodCall methodCall) async {
        vidraChannelCalls.add(methodCall);
        return null;
      },
    );
  });

  tearDown(() {
    ShareIntentWrapperState.debugOverrideIsAndroid = null;
    ToastUtils.dismissAll();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('receive_sharing_intent/messages'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('receive_sharing_intent/events-media'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('x-slayer/overlay_channel'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'x-slayer/overlay_messenger',
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('vidra_channel'),
      null,
    );
  });

  Widget createTestWidget({
    DownloadsController? customDownloadsCtrl,
    LocaleController? customLocaleCtrl,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(
          value: customLocaleCtrl ?? localeCtrl,
        ),
        ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
        ChangeNotifierProvider<DownloadsController>.value(
          value: customDownloadsCtrl ?? downloadsCtrl,
        ),
        ChangeNotifierProvider<SettingsController>.value(value: settingsCtrl),
      ],
      child: MaterialApp(
        navigatorKey: ToastUtils.navigatorKey,
        home: const ShareIntentWrapper(
          child: Scaffold(body: Text('Child Content')),
        ),
      ),
    );
  }

  group('ShareWrapper - Android Overlay Permission & Fallback Direct Download', () {
    testWidgets('Case A: Overlay permission already granted -> shows overlay and does not add direct download', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(() => state.processIntentForTesting('https://www.youtube.com/watch?v=granted123'));
      await tester.pump();

      // Overlay should be shown and data shared
      expect(
        overlayChannelCalls.any((call) => call.method == 'showOverlay'),
        isTrue,
      );
      expect(overlaySharedData.length, equals(1));
      expect(overlaySharedData.first['url'], equals('https://www.youtube.com/watch?v=granted123'));
      expect(
        vidraChannelCalls.any((call) => call.method == 'moveToBackground'),
        isTrue,
      );

      // DownloadsController should NOT be called directly
      expect(fakeSystemCtrl.enqueuedDownloads, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Case B: Overlay permission not granted initially, but granted upon request and lifecycle resume -> shows overlay', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(() async {
        final future = state.processIntentForTesting('https://www.youtube.com/watch?v=promptGranted123');
        await Future.delayed(const Duration(milliseconds: 10));

        // Intermediate non-resumed states do not prematurely resolve
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future.delayed(const Duration(milliseconds: 10));

        // User returns to app
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await future;
      });
      await tester.pump();

      // Permission requested and overlay shown
      expect(
        overlayChannelCalls.any((call) => call.method == 'requestPermission'),
        isTrue,
      );
      expect(
        overlayChannelCalls.any((call) => call.method == 'showOverlay'),
        isTrue,
      );
      expect(overlaySharedData.length, equals(1));
      expect(overlaySharedData.first['url'], equals('https://www.youtube.com/watch?v=promptGranted123'));
      expect(fakeSystemCtrl.enqueuedDownloads, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Case C: Overlay permission denied upon request and lifecycle resume -> enqueues direct download and shows localized toast (EN)', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = false;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(() async {
        final future = state.processIntentForTesting('https://www.youtube.com/watch?v=denied123');
        await Future.delayed(const Duration(milliseconds: 10));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future.delayed(const Duration(milliseconds: 10));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await future;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Overlay should NOT be shown
      expect(
        overlayChannelCalls.any((call) => call.method == 'showOverlay'),
        isFalse,
      );
      expect(overlaySharedData, isEmpty);

      // Download directly enqueued
      expect(fakeSystemCtrl.enqueuedDownloads.length, equals(1));
      expect(fakeSystemCtrl.enqueuedDownloads.first['url'], equals('https://www.youtube.com/watch?v=denied123'));

      // Localized Toast message displayed: "Overlay permission denied, downloading directly"
      expect(find.text('Overlay permission denied, downloading directly'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Case C (Spanish): Overlay permission denied upon request and lifecycle resume -> shows Spanish localized toast', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = false;

      final esLocaleRepo = MockLocaleRepository();
      final esLocaleCtrl = LocaleController(esLocaleRepo, 'es');
      await esLocaleCtrl.whenReady;

      await tester.pumpWidget(createTestWidget(customLocaleCtrl: esLocaleCtrl));
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(() async {
        final future = state.processIntentForTesting('https://www.youtube.com/watch?v=denied_es');
        await Future.delayed(const Duration(milliseconds: 10));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await future;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Spanish toast displayed
      expect(
        find.text('Permiso de superposición denegado, descargando directamente'),
        findsOneWidget,
      );
      expect(fakeSystemCtrl.enqueuedDownloads.length, equals(1));
      expect(fakeSystemCtrl.enqueuedDownloads.first['url'], equals('https://www.youtube.com/watch?v=denied_es'));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Case D: Overlay permission denied and addDownload fails -> shows localized error toast', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = false;
      final failingCtrl = FailingDownloadsController(fakeDownloadRepo, fakeSystemCtrl);

      await tester.pumpWidget(createTestWidget(customDownloadsCtrl: failingCtrl));
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(() async {
        final future = state.processIntentForTesting('https://www.youtube.com/watch?v=failure');
        await Future.delayed(const Duration(milliseconds: 10));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await future;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Localized error toast displayed: "Error sending download."
      expect(find.text('Error sending download.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Timeout case: User stays in Settings until timeout -> re-checks permission and falls back to direct download', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = false;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );
      state.resumeTimeout = const Duration(milliseconds: 50);

      await tester.runAsync(() async {
        await state.processIntentForTesting('https://www.youtube.com/watch?v=timeout_fallback');
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Overlay should NOT be shown
      expect(
        overlayChannelCalls.any((call) => call.method == 'showOverlay'),
        isFalse,
      );
      expect(fakeSystemCtrl.enqueuedDownloads.length, equals(1));
      expect(fakeSystemCtrl.enqueuedDownloads.first['url'], equals('https://www.youtube.com/watch?v=timeout_fallback'));
      expect(find.text('Overlay permission denied, downloading directly'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Timeout case: User enabled permission in Settings but resume signal missed/timed out -> re-checks permission to true and opens overlay', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );
      state.resumeTimeout = const Duration(milliseconds: 50);

      await tester.runAsync(() async {
        await state.processIntentForTesting('https://www.youtube.com/watch?v=timeout_granted');
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        overlayChannelCalls.any((call) => call.method == 'showOverlay'),
        isTrue,
      );
      expect(overlaySharedData.length, equals(1));
      expect(overlaySharedData.first['url'], equals('https://www.youtube.com/watch?v=timeout_granted'));
      expect(fakeSystemCtrl.enqueuedDownloads, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Non-Android platform -> direct download and standard localized toast', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = false;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(() => state.processIntentForTesting('https://www.youtube.com/watch?v=desktop123'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Direct download enqueued
      expect(fakeSystemCtrl.enqueuedDownloads.length, equals(1));
      expect(fakeSystemCtrl.enqueuedDownloads.first['url'], equals('https://www.youtube.com/watch?v=desktop123'));

      // Standard toast: "Download sent"
      expect(find.text('Download sent'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Empty or whitespace URL is safely ignored', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(() => state.processIntentForTesting('   '));
      await tester.pump();

      expect(overlayChannelCalls, isEmpty);
      expect(fakeSystemCtrl.enqueuedDownloads, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Case E: Overlay permission check/request throws PlatformException -> falls back to direct download', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;

      // Mock x-slayer/overlay_channel to throw PlatformException on checkPermission
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('x-slayer/overlay_channel'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'checkPermission' || methodCall.method == 'requestPermission') {
            throw PlatformException(code: 'PERMISSION_ERROR', message: 'Channel failed');
          }
          return true;
        },
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );
      state.resumeTimeout = const Duration(milliseconds: 50);

      await tester.runAsync(
        () => state.processIntentForTesting('https://www.youtube.com/watch?v=channel_exception'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Direct download enqueued
      expect(fakeSystemCtrl.enqueuedDownloads.length, equals(1));
      expect(
        fakeSystemCtrl.enqueuedDownloads.first['url'],
        equals('https://www.youtube.com/watch?v=channel_exception'),
      );

      // Toast displayed: "Overlay permission denied, downloading directly"
      expect(find.text('Overlay permission denied, downloading directly'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Case F: showOverlay throws PlatformException -> falls back to direct download safely', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('x-slayer/overlay_channel'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'checkPermission') {
            return true; // granted
          }
          if (methodCall.method == 'showOverlay') {
            throw PlatformException(code: 'SHOW_FAILED', message: 'Overlay window rejected');
          }
          return true;
        },
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(
        () => state.processIntentForTesting('https://www.youtube.com/watch?v=show_overlay_fail'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Direct download enqueued as fallback
      expect(fakeSystemCtrl.enqueuedDownloads.length, equals(1));
      expect(
        fakeSystemCtrl.enqueuedDownloads.first['url'],
        equals('https://www.youtube.com/watch?v=show_overlay_fail'),
      );
      expect(find.text('Overlay permission denied, downloading directly'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Case G: Unmounted widget when processing intent returns gracefully without error', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      // Unmount the widget by pumping another widget
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Unmounted'))));
      await tester.pump();

      // Calling processIntentForTesting on unmounted state should return without throw
      await tester.runAsync(() => state.processIntentForTesting('https://www.youtube.com/watch?v=unmounted'));
      await tester.pump();

      expect(find.text('Unmounted'), findsOneWidget);
    });

    testWidgets('Unmounted safety: Widget disposed while awaiting resume completes gracefully without error', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      Future<void>? processFuture;
      await tester.runAsync(() async {
        processFuture = state.processIntentForTesting('https://www.youtube.com/watch?v=dispose_while_waiting');
        await Future.delayed(const Duration(milliseconds: 10));
      });

      // Unmount the widget while waiting in _waitForResume
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Unmounted While Waiting'))));
      await tester.pump();

      await tester.runAsync(() async {
        await processFuture;
      });
      await tester.pump();

      expect(find.text('Unmounted While Waiting'), findsOneWidget);
    });

    testWidgets('Adversarial Concurrency: Multiple incoming share intents arriving concurrently while awaiting resume -> all unblock simultaneously on resume', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      Future<void>? future1;
      Future<void>? future2;
      await tester.runAsync(() async {
        future1 = state.processIntentForTesting('https://www.youtube.com/watch?v=concurrent_1');
        await Future.delayed(const Duration(milliseconds: 5));
        future2 = state.processIntentForTesting('https://www.youtube.com/watch?v=concurrent_2');
        await Future.delayed(const Duration(milliseconds: 10));

        // Both should be waiting for resume; trigger resume once
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future.wait([future1!, future2!]);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Both should have proceeded to overlay
      expect(
        overlayChannelCalls.where((call) => call.method == 'showOverlay').length,
        greaterThanOrEqualTo(1),
      );
      expect(
        overlaySharedData.map((d) => d['url']).toSet(),
        containsAll(['https://www.youtube.com/watch?v=concurrent_1', 'https://www.youtube.com/watch?v=concurrent_2']),
      );
      expect(fakeSystemCtrl.enqueuedDownloads, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Adversarial Concurrency (Denied): Multiple concurrent intents when permission denied -> all enqueue direct downloads and dismiss spinner', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = false;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(() async {
        final future1 = state.processIntentForTesting('https://www.youtube.com/watch?v=concurrent_denied_1');
        final future2 = state.processIntentForTesting('https://www.youtube.com/watch?v=concurrent_denied_2');
        await Future.delayed(const Duration(milliseconds: 10));

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future.wait([future1, future2]);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Both downloads should be enqueued directly
      expect(fakeSystemCtrl.enqueuedDownloads.length, equals(2));
      final enqueuedUrls = fakeSystemCtrl.enqueuedDownloads.map((d) => d['url']).toList();
      expect(enqueuedUrls, contains('https://www.youtube.com/watch?v=concurrent_denied_1'));
      expect(enqueuedUrls, contains('https://www.youtube.com/watch?v=concurrent_denied_2'));
      expect(find.text('Overlay permission denied, downloading directly'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Adversarial Lifecycle Jitter: Rapid successive lifecycle events (inactive -> paused -> hidden -> resumed -> paused -> resumed) resolve cleanly', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(() async {
        final future = state.processIntentForTesting('https://www.youtube.com/watch?v=jitter_test');
        await Future.delayed(const Duration(milliseconds: 5));

        // Rapid state changes
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

        await future;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        overlayChannelCalls.any((call) => call.method == 'showOverlay'),
        isTrue,
      );
      expect(overlaySharedData.first['url'], equals('https://www.youtube.com/watch?v=jitter_test'));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Consecutive Intents: Sequential intents across distinct lifecycle cycles work independently', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      // First intent
      await tester.runAsync(() async {
        final future1 = state.processIntentForTesting('https://www.youtube.com/watch?v=seq_1');
        await Future.delayed(const Duration(milliseconds: 10));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await future1;
      });
      await tester.pump();

      expect(overlaySharedData.any((d) => d['url'] == 'https://www.youtube.com/watch?v=seq_1'), isTrue);

      // Reset mock checks for second intent
      firstCheckResult = false;
      secondCheckResult = false;

      // Second intent
      await tester.runAsync(() async {
        final future2 = state.processIntentForTesting('https://www.youtube.com/watch?v=seq_2');
        await Future.delayed(const Duration(milliseconds: 10));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await future2;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeSystemCtrl.enqueuedDownloads.any((d) => d['url'] == 'https://www.youtube.com/watch?v=seq_2'), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Case H: FlutterScreenOverlay.shareData throws PlatformException -> falls back to direct download safely and dismisses spinner', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = true;

      // Mock x-slayer/overlay_messenger to throw PlatformException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
        const BasicMessageChannel<dynamic>('x-slayer/overlay_messenger', JSONMessageCodec()),
        (dynamic message) async {
          throw PlatformException(code: 'SHARE_DATA_ERROR', message: 'IPC failure');
        },
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(
        () => state.processIntentForTesting('https://www.youtube.com/watch?v=share_data_fail'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Direct download enqueued as fallback
      expect(fakeSystemCtrl.enqueuedDownloads.length, equals(1));
      expect(
        fakeSystemCtrl.enqueuedDownloads.first['url'],
        equals('https://www.youtube.com/watch?v=share_data_fail'),
      );
      expect(find.text('Overlay permission denied, downloading directly'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Case I: moveToBackground throws PlatformException -> overlay setup completes without failure and dismisses spinner', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = true;

      // Mock vidra_channel to throw PlatformException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('vidra_channel'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'moveToBackground') {
            throw PlatformException(code: 'BG_ERROR', message: 'Cannot move to background');
          }
          return null;
        },
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      await tester.runAsync(
        () => state.processIntentForTesting('https://www.youtube.com/watch?v=bg_error_test'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Overlay should be shown and data shared without fallback download
      expect(
        overlayChannelCalls.any((call) => call.method == 'showOverlay'),
        isTrue,
      );
      expect(overlaySharedData.length, equals(1));
      expect(overlaySharedData.first['url'], equals('https://www.youtube.com/watch?v=bg_error_test'));
      expect(fakeSystemCtrl.enqueuedDownloads, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Case J: High-concurrency stress test with 10 parallel incoming intents -> all unblock cleanly on resume', (
      tester,
    ) async {
      ShareIntentWrapperState.debugOverrideIsAndroid = true;
      firstCheckResult = false;
      secondCheckResult = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<ShareIntentWrapperState>(
        find.byType(ShareIntentWrapper),
      );

      final List<Future<void>> futures = [];
      await tester.runAsync(() async {
        for (int i = 0; i < 10; i++) {
          futures.add(state.processIntentForTesting('https://www.youtube.com/watch?v=stress_$i'));
          await Future.delayed(const Duration(milliseconds: 2));
        }

        // Resume lifecycle
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future.wait(futures);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(overlaySharedData.length, equals(10));
      expect(fakeSystemCtrl.enqueuedDownloads, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
