import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/core/network/github_client.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/system/presentation/system_details_screen.dart';
import 'package:vidra/features/system/presentation/widgets/system_status_update_bubble.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  bool autoUncompress = true;
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => 0;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final transparentPng = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    return Stream<List<int>>.value(transparentPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _MockSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  final SystemState _state = SystemState.ready;
  @override
  SystemState get state => _state;
  @override
  int? get backendPort => 5000;
  @override
  String? get backendToken => 'token';
  @override
  String? get serverLogsFilePath => '/path/logs';
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

class _MockGithubClient implements GithubClient {
  int fetchCallCount = 0;
  final List<String> requestedRepos = [];
  final List<String> requestedAssetNames = [];
  UpdateInfo? appUpdate;
  UpdateInfo? ytDlpUpdate;
  UpdateInfo? ytDlpEjsUpdate;
  bool shouldFailDownload = false;

  @override
  Future<UpdateInfo?> getLatestReleaseInfo({
    required String repo,
    required List<RegExp> assetRegex,
  }) async {
    fetchCallCount++;
    requestedRepos.add(repo);
    if (assetRegex.isNotEmpty) {
      requestedAssetNames.add(assetRegex.first.pattern);
    }
    if (repo.contains('vidra')) return appUpdate;
    if (repo.contains('ejs')) return ytDlpEjsUpdate;
    if (repo.contains('yt-dlp')) return ytDlpUpdate;
    return null;
  }

  @override
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async {
    if (shouldFailDownload) return false;
    final file = File(savePath);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    file.writeAsStringSync('dummy_payload');
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _MockSystemController mockSystem;
  late _MockGithubClient mockGithub;
  late LocaleController localeCtrl;

  setUpAll(() async {
    HttpOverrides.global = _MockHttpOverrides();
    PackageInfo.setMockInitialValues(
      appName: 'Vidra',
      packageName: 'com.vidra.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('challenger3_adversarial_');
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (MethodCall methodCall) async {
      return tempDir.path;
    });

    const MethodChannel openFileChannel = MethodChannel('open_filex');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(openFileChannel,
            (MethodCall methodCall) async {
      return {'type': 0, 'message': 'done'};
    });

    SharedPreferences.setMockInitialValues({
      'has_seen_system_tutorial': true,
      'has_seen_main_tutorial': true,
    });

    mockSystem = _MockSystemController();
    mockGithub = _MockGithubClient();
    localeCtrl = LocaleController(LocaleRepository(), 'en');
    await localeCtrl.whenReady;
  });

  tearDown(() {
    SystemStatusUpdateBubble.hide();
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    const MethodChannel openFileChannel = MethodChannel('open_filex');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(openFileChannel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  void createFakeModules() {
    final modulesDir = Directory('${tempDir.path}/core_modules');
    final ytdlp = Directory('${modulesDir.path}/yt_dlp');
    final ejs = Directory('${modulesDir.path}/yt_dlp_ejs');
    if (!ytdlp.existsSync()) ytdlp.createSync(recursive: true);
    if (!ejs.existsSync()) ejs.createSync(recursive: true);
  }

  Widget buildAppWithProviders(Widget child, SharedPreferences prefs, UpdateController updateCtrl) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: prefs),
        ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
        ChangeNotifierProvider<SystemController>.value(value: mockSystem),
        ChangeNotifierProvider<UpdateController>.value(value: updateCtrl),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('Adversarial Re-verification 1: Linux Package Resolver & Asset Resolution Alignment', () {
    test('1.1 Resolver alignment: Linux validates version without requesting binary assets', () async {
      createFakeModules();
      SharedPreferences.setMockInitialValues({
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();
      mockGithub.appUpdate = UpdateInfo(
        version: '5.0.0',
        downloadUrl: '',
        changelog: 'Linux release',
      );
      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGithub.requestedAssetNames.clear();
      final hasUpdate = await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.app,
      );

      final pkgType = controller.getLinuxPackageType();
      expect(pkgType, isA<LinuxPackageType>());
      expect(hasUpdate, isTrue);
      expect(mockGithub.requestedAssetNames, isEmpty,
          reason: 'Linux app updates validate version without searching for specific binary assets');
    });

    test('1.2 Resolver consistency: getLinuxPackageType returns strictly non-null enum', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = UpdateController(mockGithub, mockSystem, prefs);

      final type = controller.getLinuxPackageType();
      expect(type, isA<LinuxPackageType>());
      expect([LinuxPackageType.deb, LinuxPackageType.appImage, LinuxPackageType.snap, LinuxPackageType.unknown].contains(type), isTrue);
    });
  });

  group('Adversarial Re-verification 2: SystemStatusUpdateBubble Context & Modal Sheet Execution', () {
    testWidgets('2.1 _handleShow successfully unmounts bubble and opens SystemDetailsScreen', (tester) async {
      createFakeModules();
      final prefs = await SharedPreferences.getInstance();
      final updateCtrl = UpdateController(mockGithub, mockSystem, prefs);

      final anchorKey = GlobalKey();

      await tester.pumpWidget(
        buildAppWithProviders(
          Center(
            child: SizedBox(
              key: anchorKey,
              width: 50,
              height: 50,
            ),
          ),
          prefs,
          updateCtrl,
        ),
      );
      await tester.pumpAndSettle();

      // Show bubble
      SystemStatusUpdateBubble.show(anchorKey.currentContext!, anchorKey);
      await tester.pumpAndSettle();

      expect(SystemStatusUpdateBubble.isShowing, isTrue);
      expect(find.text(localeCtrl.localeStrings.ssiBubbleTitle), findsOneWidget);

      final showButton = find.text(localeCtrl.localeStrings.ssiBubbleButtonShow);
      expect(showButton, findsOneWidget);

      // Tap Show
      await tester.tap(showButton);
      await tester.pumpAndSettle();

      // Bubble is removed
      expect(SystemStatusUpdateBubble.isShowing, isFalse);
      // SystemDetailsScreen is mounted in bottom sheet
      expect(find.byType(SystemDetailsScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('2.2 _handleShow respects custom onShow callback without throwing or opening default sheet', (tester) async {
      createFakeModules();
      final prefs = await SharedPreferences.getInstance();
      final updateCtrl = UpdateController(mockGithub, mockSystem, prefs);

      final anchorKey = GlobalKey();
      bool customShowCalled = false;

      await tester.pumpWidget(
        buildAppWithProviders(
          Stack(
            children: [
              Center(
                child: SizedBox(
                  key: anchorKey,
                  width: 50,
                  height: 50,
                ),
              ),
              SystemStatusUpdateBubble(
                anchorKey: anchorKey,
                onShow: () {
                  customShowCalled = true;
                },
              ),
            ],
          ),
          prefs,
          updateCtrl,
        ),
      );
      await tester.pumpAndSettle();

      final showButton = find.text(localeCtrl.localeStrings.ssiBubbleButtonShow);
      expect(showButton, findsOneWidget);

      await tester.tap(showButton);
      await tester.pumpAndSettle();

      expect(customShowCalled, isTrue);
      // Default bottom sheet should NOT have opened because onShow intercepted
      expect(find.byType(SystemDetailsScreen), findsNothing);
    });

    testWidgets('2.3 _handleDismiss respects custom onDismiss callback', (tester) async {
      createFakeModules();
      final prefs = await SharedPreferences.getInstance();
      final updateCtrl = UpdateController(mockGithub, mockSystem, prefs);

      final anchorKey = GlobalKey();
      bool customDismissCalled = false;

      await tester.pumpWidget(
        buildAppWithProviders(
          Stack(
            children: [
              Center(
                child: SizedBox(
                  key: anchorKey,
                  width: 50,
                  height: 50,
                ),
              ),
              SystemStatusUpdateBubble(
                anchorKey: anchorKey,
                onDismiss: () {
                  customDismissCalled = true;
                },
              ),
            ],
          ),
          prefs,
          updateCtrl,
        ),
      );
      await tester.pumpAndSettle();

      final dismissButton = find.text(localeCtrl.localeStrings.ssiBubbleButtonDismiss);
      expect(dismissButton, findsOneWidget);

      await tester.tap(dismissButton);
      await tester.pumpAndSettle();

      expect(customDismissCalled, isTrue);
    });
  });

  group('Adversarial Stress Suite 3: 6-Hour Interval & Cache Integrity (R2 & R4)', () {
    test('3.1 Extreme timestamp drift (10 years into future) does not spam network requests', () async {
      createFakeModules();
      final tenYearsInFuture = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'last_update_check_app': tenYearsInFuture,
        'last_update_check_yt_dlp': tenYearsInFuture,
        'last_update_check_yt_dlp_ejs': tenYearsInFuture,
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = UpdateController(mockGithub, mockSystem, prefs);

      expect(controller.hasPendingChecks, isFalse);
      expect(mockGithub.fetchCallCount, equals(0));
    });

    test('3.2 Partial cache corruption: discovered_version exists but info is malformed', () async {
      createFakeModules();
      SharedPreferences.setMockInitialValues({
        'last_update_check_app': DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        'discovered_version_app': '2.0.0',
        'discovered_info_app': '{"corrupted": "bad_json_shape}',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Controller should gracefully rehydrate without crashing
      final appState = controller.getState(ComponentType.app);
      expect(appState.status, equals(ComponentStatus.upToDate));
      expect(appState.version, equals('1.0.0'));
    });

    test('3.3 PackageInfo immutability: Failed download does not corrupt version string', () async {
      createFakeModules();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = UpdateController(mockGithub, mockSystem, prefs);

      mockGithub.shouldFailDownload = true;

      final brokenInfo = UpdateInfo(
        version: '99.0.0',
        downloadUrl: 'https://invalid-url-that-does-not-exist.org/file.apk',
        changelog: 'Test',
      );

      final success = await controller.downloadAndInstallInternal(ComponentType.app, brokenInfo);
      expect(success, isFalse);
      expect(controller.getState(ComponentType.app).status, equals(ComponentStatus.error));
      expect(controller.getState(ComponentType.app).version, equals('1.0.0'));
    });
  });
}
