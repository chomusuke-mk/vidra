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
import 'package:vidra/features/system/presentation/system_status_indicator.dart';
import 'package:vidra/features/system/presentation/widgets/system_status_update_bubble.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/utils/tutorial_utils.dart';

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

class MockSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  SystemState _state = SystemState.ready;
  @override
  SystemState get state => _state;

  void setState(SystemState s) {
    _state = s;
    notifyListeners();
  }

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

class MockGithubClient implements GithubClient {
  @override
  Future<UpdateInfo?> getLatestReleaseInfo({
    required ComponentType type,
    required UpdateChannel channel,
    required String targetAssetName,
    bool isPrefixMatch = false,
  }) async => null;

  @override
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async => true;
}

class FakeUpdateController extends ChangeNotifier implements UpdateController {
  bool _hasAvailableUpdates = false;
  bool _hasShownSessionUpdateBubble = false;
  final bool _isAutoDownloadingMissing = false;
  final double _missingModulesProgress = 0.0;

  @override
  bool get hasAvailableUpdates => _hasAvailableUpdates;

  @override
  bool get hasShownSessionUpdateBubble => _hasShownSessionUpdateBubble;

  @override
  bool get isAutoDownloadingMissing => _isAutoDownloadingMissing;

  @override
  double get missingModulesProgress => _missingModulesProgress;

  @override
  bool get isCheckingUpdates => false;

  @override
  bool get hasPendingChecks => false;

  void setHasAvailableUpdates(bool val) {
    _hasAvailableUpdates = val;
    notifyListeners();
  }

  @override
  void markSessionUpdateBubbleShown() {
    _hasShownSessionUpdateBubble = true;
    notifyListeners();
  }

  @override
  UpdateState getState(ComponentType type) {
    return UpdateState(
      status: ComponentStatus.upToDate,
      version: '1.0.0',
    );
  }

  @override
  Future<bool> checkForUpdates({bool manualCall = true, ComponentType? specificType}) async {
    return false;
  }

  @override
  Future<void> downloadAndInstall(ComponentType type) async {}

  @override
  Future<bool> downloadAndInstallInternal(ComponentType type, UpdateInfo info, {Function(double progress)? onDownloadProgress}) async => true;

  @override
  LinuxPackageType getLinuxPackageType() => LinuxPackageType.deb;

  @override
  Future<void> retryMissingModulesDownload() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeCtrl;
  late MockSystemController mockSystemCtrl;
  late FakeUpdateController fakeUpdateCtrl;
  late SharedPreferences prefs;
  late Directory tempDir;

  setUpAll(() {
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
    tempDir = Directory.systemTemp.createTempSync('bubble_adversarial_');
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (MethodCall methodCall) async {
      return tempDir.path;
    });

    SharedPreferences.setMockInitialValues({
      'has_seen_system_tutorial': true,
      'has_seen_main_tutorial': true,
    });
    prefs = await SharedPreferences.getInstance();

    localeCtrl = LocaleController(LocaleRepository(), 'en');
    await localeCtrl.whenReady;
    mockSystemCtrl = MockSystemController();
    fakeUpdateCtrl = FakeUpdateController();
  });

  tearDown(() {
    SystemStatusUpdateBubble.hide();
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget buildApp(Widget child) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: prefs),
        ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
        ChangeNotifierProvider<SystemController>.value(value: mockSystemCtrl),
        ChangeNotifierProvider<UpdateController>.value(value: fakeUpdateCtrl),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('Adversarial Stress Test: SystemStatusUpdateBubble Lifecycle & Overlay Race Conditions', () {
    testWidgets('1. Rapid 10x show() calls do NOT create duplicate entries or crash', (tester) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        buildApp(
          Center(
            child: SizedBox(
              key: key,
              width: 50,
              height: 50,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = key.currentContext!;
      for (int i = 0; i < 10; i++) {
        SystemStatusUpdateBubble.show(context, key);
      }
      await tester.pumpAndSettle();

      expect(SystemStatusUpdateBubble.isShowing, isTrue);
      // Only 1 bubble title widget rendered in overlay
      expect(
        find.text(localeCtrl.localeStrings.ssiBubbleTitle),
        findsOneWidget,
      );

      // Clean hide
      SystemStatusUpdateBubble.hide();
      await tester.pumpAndSettle();
      expect(SystemStatusUpdateBubble.isShowing, isFalse);
    });

    testWidgets('2. Repeated hide() calls when already hidden are idempotent and safe', (tester) async {
      expect(SystemStatusUpdateBubble.isShowing, isFalse);
      expect(() {
        SystemStatusUpdateBubble.hide();
        SystemStatusUpdateBubble.hide();
        SystemStatusUpdateBubble.hide();
      }, returnsNormally);
      expect(SystemStatusUpdateBubble.isShowing, isFalse);
    });

    testWidgets('3. Rapid show-hide-show alternation settles in the correct state', (tester) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        buildApp(
          Center(
            child: SizedBox(
              key: key,
              width: 50,
              height: 50,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = key.currentContext!;
      SystemStatusUpdateBubble.show(context, key);
      expect(SystemStatusUpdateBubble.isShowing, isTrue);
      SystemStatusUpdateBubble.hide();
      expect(SystemStatusUpdateBubble.isShowing, isFalse);
      SystemStatusUpdateBubble.show(context, key);
      expect(SystemStatusUpdateBubble.isShowing, isTrue);

      await tester.pumpAndSettle();
      expect(find.text(localeCtrl.localeStrings.ssiBubbleTitle), findsOneWidget);

      SystemStatusUpdateBubble.hide();
      await tester.pumpAndSettle();
      expect(SystemStatusUpdateBubble.isShowing, isFalse);
      expect(find.text(localeCtrl.localeStrings.ssiBubbleTitle), findsNothing);
    });

    testWidgets('4. Tapping outside the bubble (backdrop gesture detector) dismisses the bubble cleanly', (tester) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        buildApp(
          Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              key: key,
              width: 40,
              height: 40,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      SystemStatusUpdateBubble.show(key.currentContext!, key);
      await tester.pumpAndSettle();

      expect(SystemStatusUpdateBubble.isShowing, isTrue);
      expect(find.text(localeCtrl.localeStrings.ssiBubbleTitle), findsOneWidget);

      // Tap bottom-left of the screen (outside bubble)
      await tester.tapAt(const Offset(20, 500));
      await tester.pumpAndSettle();

      expect(SystemStatusUpdateBubble.isShowing, isFalse);
      expect(find.text(localeCtrl.localeStrings.ssiBubbleTitle), findsNothing);
    });

    testWidgets('5. Tapping Show button dismisses bubble and opens SystemDetailsScreen', (tester) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        buildApp(
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: key,
              width: 40,
              height: 40,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      SystemStatusUpdateBubble.show(key.currentContext!, key);
      await tester.pumpAndSettle();

      expect(SystemStatusUpdateBubble.isShowing, isTrue);
      final showBtn = find.text(localeCtrl.localeStrings.ssiBubbleButtonShow);
      expect(showBtn, findsOneWidget);

      await tester.tap(showBtn);
      await tester.pumpAndSettle();

      // Bubble should be dismissed
      expect(SystemStatusUpdateBubble.isShowing, isFalse);
      // SystemDetailsScreen should be displayed in modal bottom sheet
      expect(find.byType(SystemDetailsScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('6. SystemStatusIndicator session scoping under multi-rebuild pressure', (tester) async {
      fakeUpdateCtrl.setHasAvailableUpdates(true);

      await tester.pumpWidget(
        buildApp(
          AppBar(
            leading: SystemStatusIndicator(key: AppTutorialKeys.mainSystemStatus),
          ),
        ),
      );
      await tester.pump();

      // Wait 500ms delay for bubble to show
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(SystemStatusUpdateBubble.isShowing, isTrue);
      expect(fakeUpdateCtrl.hasShownSessionUpdateBubble, isTrue);

      // Dismiss bubble
      SystemStatusUpdateBubble.hide();
      await tester.pumpAndSettle();
      expect(SystemStatusUpdateBubble.isShowing, isFalse);

      // Trigger 10 rapid rebuilds of the tree while hasAvailableUpdates remains true
      for (int i = 0; i < 10; i++) {
        fakeUpdateCtrl.notifyListeners();
        mockSystemCtrl.setState(i.isEven ? SystemState.ready : SystemState.retrying);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      // Bubble MUST NOT reappear because hasShownSessionUpdateBubble is true
      expect(SystemStatusUpdateBubble.isShowing, isFalse);
    });

    testWidgets('7. Anchor edge clamping: Extreme screen coordinates (left, right, offscreen)', (tester) async {
      // Test left edge (x = 0)
      final leftKey = GlobalKey();
      await tester.pumpWidget(
        buildApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: leftKey,
              width: 30,
              height: 30,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      SystemStatusUpdateBubble.show(leftKey.currentContext!, leftKey);
      await tester.pumpAndSettle();
      expect(SystemStatusUpdateBubble.isShowing, isTrue);
      SystemStatusUpdateBubble.hide();
      await tester.pumpAndSettle();

      // Test right edge (x = 800)
      final rightKey = GlobalKey();
      await tester.pumpWidget(
        buildApp(
          Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              key: rightKey,
              width: 30,
              height: 30,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      SystemStatusUpdateBubble.show(rightKey.currentContext!, rightKey);
      await tester.pumpAndSettle();
      expect(SystemStatusUpdateBubble.isShowing, isTrue);
      SystemStatusUpdateBubble.hide();
      await tester.pumpAndSettle();
    });
  });
}
