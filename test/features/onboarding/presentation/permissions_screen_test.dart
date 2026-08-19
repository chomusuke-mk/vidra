import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/onboarding/presentation/permissions_screen.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

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
  SystemState _state = SystemState.initializing;
  @override
  SystemState get state => _state;

  bool resumeInitializationCalled = false;

  @override
  int? get backendPort => 5000;

  @override
  String? get backendToken => 'mock_token';

  @override
  String? get serverLogsFilePath => '/tmp/mock.log';

  @override
  Future<void> get whenPortReady => Future.value();

  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {}

  @override
  Future<void> resumeInitialization() async {
    resumeInitializationCalled = true;
    _state = SystemState.ready;
    notifyListeners();
  }

  @override
  Future<void> stopBackendForUpdate() async {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSystemController fakeSystemCtrl;
  late LocaleController localeCtrl;
  late List<MethodCall> overlayChannelCalls;
  late List<MethodCall> permissionChannelCalls;

  bool mockStorageGranted = true;
  bool mockOverlayGranted = false;
  bool mockNotificationGranted = true;
  bool mockBatteryGranted = true;
  bool mockInstallGranted = false;

  setUp(() async {
    fakeSystemCtrl = FakeSystemController();
    final repo = MockLocaleRepository();
    localeCtrl = LocaleController(repo, 'en');
    await localeCtrl.whenReady;

    overlayChannelCalls = [];
    permissionChannelCalls = [];

    mockStorageGranted = true;
    mockOverlayGranted = false;
    mockNotificationGranted = true;
    mockBatteryGranted = true;
    mockInstallGranted = false;

    // Mock Device Info
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAndroidDeviceInfo') {
          return {
            'version': {'sdkInt': 33, 'release': '13'},
            'board': 'mock',
            'bootloader': 'mock',
            'brand': 'mock',
            'device': 'mock',
            'display': 'mock',
            'fingerprint': 'mock',
            'hardware': 'mock',
            'host': 'mock',
            'id': 'mock',
            'manufacturer': 'mock',
            'model': 'mock',
            'product': 'mock',
            'supported32BitAbis': [],
            'supported64BitAbis': [],
            'supportedAbis': [],
            'tags': 'mock',
            'type': 'mock',
            'isPhysicalDevice': true,
            'systemFeatures': [],
          };
        }
        return null;
      },
    );

    // Mock FlutterScreenOverlay Channel (x-slayer/overlay_channel)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('x-slayer/overlay_channel'),
      (MethodCall methodCall) async {
        overlayChannelCalls.add(methodCall);
        if (methodCall.method == 'checkPermission') {
          return mockOverlayGranted;
        }
        if (methodCall.method == 'requestPermission') {
          return true;
        }
        return null;
      },
    );

    // Mock Permission Handler Channel
    // 15: storage, 16: ignoreBatteryOptimizations, 17: notification, 22: manageExternalStorage, 24: requestInstallPackages
    // Status: 0: denied, 1: granted
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        permissionChannelCalls.add(methodCall);
        if (methodCall.method == 'checkPermissionStatus') {
          final int perm = methodCall.arguments as int;
          if (perm == 15 || perm == 22) {
            return mockStorageGranted ? 1 : 0;
          }
          if (perm == 17) {
            return mockNotificationGranted ? 1 : 0;
          }
          if (perm == 16) {
            return mockBatteryGranted ? 1 : 0;
          }
          if (perm == 24) {
            return mockInstallGranted ? 1 : 0;
          }
          return 0;
        }
        if (methodCall.method == 'requestPermissions') {
          final List<dynamic> perms = methodCall.arguments as List<dynamic>;
          final Map<int, int> result = {};
          for (final p in perms) {
            final int perm = p as int;
            if (perm == 15 || perm == 22) {
              result[perm] = mockStorageGranted ? 1 : 0;
            } else if (perm == 17) {
              result[perm] = mockNotificationGranted ? 1 : 0;
            } else if (perm == 16) {
              result[perm] = mockBatteryGranted ? 1 : 0;
            } else if (perm == 24) {
              result[perm] = mockInstallGranted ? 1 : 0;
            } else {
              result[perm] = 0;
            }
          }
          return result;
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('x-slayer/overlay_channel'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      null,
    );
  });

  Widget createTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
        ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
      ],
      child: const MaterialApp(
        home: PermissionsScreen(),
      ),
    );
  }

  group('PermissionsScreen - Optional Overlay Permission & Flow', () {
    testWidgets('Displays optional badges for overlay and install permissions in English and Spanish', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Check title and optional badges in English
      expect(find.text('Permissions'), findsOneWidget);
      expect(find.text('Optional'), findsNWidgets(2)); // Overlay and Install both optional
      expect(find.text('Overlay'), findsOneWidget);

      // Switch to Spanish
      localeCtrl.setLocale('es');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Permisos'), findsOneWidget);
      expect(find.text('Opcional'), findsNWidgets(2));
      expect(find.text('Cubrir'), findsOneWidget);
    });

    testWidgets('Continue button is ENABLED when mandatory permissions are granted even if overlay is DENIED', (
      tester,
    ) async {
      mockStorageGranted = true;
      mockNotificationGranted = true;
      mockBatteryGranted = true;
      mockOverlayGranted = false;
      mockInstallGranted = false;

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The Continue button should be enabled
      final continueButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(continueButton.onPressed, isNotNull);

      // Tap Continue button
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(fakeSystemCtrl.resumeInitializationCalled, isTrue);
    });

    testWidgets('Continue button is DISABLED when any mandatory permission is missing', (
      tester,
    ) async {
      // 1. Missing storage
      mockStorageGranted = false;
      mockNotificationGranted = true;
      mockBatteryGranted = true;
      mockOverlayGranted = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      FilledButton continueButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(continueButton.onPressed, isNull);

      // 2. Missing notifications (on SDK 33)
      mockStorageGranted = true;
      mockNotificationGranted = false;
      mockBatteryGranted = true;
      mockOverlayGranted = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      continueButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(continueButton.onPressed, isNull);

      // 3. Missing battery optimization
      mockStorageGranted = true;
      mockNotificationGranted = true;
      mockBatteryGranted = false;
      mockOverlayGranted = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      continueButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(continueButton.onPressed, isNull);
    });

    testWidgets('Requesting overlay permission invokes FlutterScreenOverlay.requestPermission', (
      tester,
    ) async {
      mockStorageGranted = true;
      mockNotificationGranted = true;
      mockBatteryGranted = true;
      mockOverlayGranted = false;

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Find the grant button next to Overlay tile
      final grantButtons = find.widgetWithText(OutlinedButton, 'Grant Permission');
      expect(grantButtons, findsWidgets);

      // Tap the grant button
      await tester.tap(grantButtons.first);
      await tester.pump();

      expect(
        overlayChannelCalls.any((call) => call.method == 'requestPermission'),
        isTrue,
      );
    });

    testWidgets('Overlay channel check/request throwing PlatformException does not crash and allows Continue', (
      tester,
    ) async {
      mockStorageGranted = true;
      mockNotificationGranted = true;
      mockBatteryGranted = true;

      // Mock FlutterScreenOverlay to throw PlatformException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('x-slayer/overlay_channel'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'CHANNEL_FAIL', message: 'Overlay unavailable');
        },
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Check title rendered
      expect(find.text('Permissions'), findsOneWidget);

      // Continue button should still be enabled because mandatory permissions are granted
      final continueButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(continueButton.onPressed, isNotNull);

      // Tapping grant button next to overlay does not crash
      final grantButtons = find.widgetWithText(OutlinedButton, 'Grant Permission');
      if (grantButtons.evaluate().isNotEmpty) {
        await tester.tap(grantButtons.first);
        await tester.pump();
      }

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(fakeSystemCtrl.resumeInitializationCalled, isTrue);
    });
  });
}
