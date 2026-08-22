import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart' as download_model;
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/presentation/downloads_screen.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
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

class MockSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  SystemState _state = SystemState.missingResources;
  @override
  SystemState get state => _state;

  void setState(SystemState s) {
    _state = s;
    notifyListeners();
  }

  @override
  int? get backendPort => null;
  @override
  String? get backendToken => null;
  @override
  String? get serverLogsFilePath => null;
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

class MockUpdateController extends ChangeNotifier implements UpdateController {
  bool _isAutoDownloadingMissing = false;
  double _missingModulesProgress = 0.0;
  ComponentStatus _ytDlpStatus = ComponentStatus.upToDate;
  ComponentStatus _ytDlpEjsStatus = ComponentStatus.upToDate;
  bool retryCalled = false;

  @override
  bool get isAutoDownloadingMissing => _isAutoDownloadingMissing;
  @override
  double get missingModulesProgress => _missingModulesProgress;
  @override
  bool get hasShownSessionUpdateBubble => false;
  @override
  bool get hasAvailableUpdates => false;
  @override
  bool get isCheckingUpdates => false;
  @override
  bool get hasPendingChecks => false;

  void setAutoDownloading(bool val, {double progress = 0.0}) {
    _isAutoDownloadingMissing = val;
    _missingModulesProgress = progress;
    notifyListeners();
  }

  void setComponentStatuses({
    ComponentStatus ytDlp = ComponentStatus.upToDate,
    ComponentStatus ytDlpEjs = ComponentStatus.upToDate,
  }) {
    _ytDlpStatus = ytDlp;
    _ytDlpEjsStatus = ytDlpEjs;
    notifyListeners();
  }

  @override
  UpdateState getState(ComponentType type) {
    if (type == ComponentType.ytDlp) {
      return UpdateState(status: _ytDlpStatus, version: 'Unknown');
    }
    if (type == ComponentType.ytDlpEjs) {
      return UpdateState(status: _ytDlpEjsStatus, version: 'Unknown');
    }
    return UpdateState(status: ComponentStatus.upToDate, version: '1.0.0');
  }

  @override
  Future<void> retryMissingModulesDownload() async {
    retryCalled = true;
    notifyListeners();
  }

  @override
  void markSessionUpdateBubbleShown() {}
  @override
  Future<bool> checkForUpdates({bool manualCall = true, ComponentType? specificType}) async => false;
  @override
  Future<void> downloadAndInstall(ComponentType type) async {}
  @override
  Future<bool> downloadAndInstallInternal(ComponentType type, UpdateInfo info, {Function(double progress)? onDownloadProgress}) async => true;
  @override
  LinuxPackageType getLinuxPackageType() => LinuxPackageType.deb;
}

class MockDownloadRepository implements DownloadRepository {
  @override
  Future<List<download_model.Download>> getAllDownloads() async => [];
  @override
  Future<download_model.Download?> getDownloadById(String id) async => null;
  @override
  Future<String> addDownload(String url, {Map<String, dynamic>? options}) async => 'id_1';
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<List<download_model.SubDownload>> getEntries(String id) async => [];
  @override
  Future<void> submitSelectedEntries(String id, List<String> entries) async {}
  @override
  Future<void> pauseDownload(String id) async {}
  @override
  Future<void> resumeDownload(String id) async {}
  @override
  Future<void> cancelDownload(String id) async {}
  @override
  Future<void> retryDownload(String id) async {}
  @override
  Future<void> deleteDownload(String id) async {}
  @override
  Future<String> fetchLogs(String? id) async => '';
  @override
  Stream<List<download_model.Delta>> watchGlobalProgress() => const Stream.empty();
  @override
  Stream<List<download_model.Delta>> watchDetailedProgress(String id) => const Stream.empty();
}

class FakeSettingsController extends ChangeNotifier implements SettingsController {
  @override
  Map<String, dynamic> getDownloadOptionsPayload() => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeCtrl;
  late MockSystemController mockSystemCtrl;
  late MockUpdateController mockUpdateCtrl;
  late MockDownloadRepository mockRepo;
  late DownloadsController downloadsCtrl;
  late FakeSettingsController fakeSettingsCtrl;
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
    tempDir = Directory.systemTemp.createTempSync('startup_progress_test_');
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (MethodCall methodCall) async {
      return tempDir.path;
    });

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    localeCtrl = LocaleController(LocaleRepository(), 'en');
    await localeCtrl.whenReady;
    mockSystemCtrl = MockSystemController();
    mockUpdateCtrl = MockUpdateController();
    mockRepo = MockDownloadRepository();
    downloadsCtrl = DownloadsController(mockRepo, mockSystemCtrl);
    fakeSettingsCtrl = FakeSettingsController();
  });

  tearDown(() {
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget createTestWidget() {
    return MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: prefs),
        ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
        ChangeNotifierProvider<SystemController>.value(value: mockSystemCtrl),
        ChangeNotifierProvider<UpdateController>.value(value: mockUpdateCtrl),
        ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
        ChangeNotifierProvider<SettingsController>.value(value: fakeSettingsCtrl),
      ],
      child: const MaterialApp(
        home: DownloadsScreen(),
      ),
    );
  }

  group('Adversarial Stress Test: Startup Engine Resource Acquisition & Progress UI (R1)', () {
    testWidgets('1. Initial missing resources: displays downloading engine indicator with 0% description', (tester) async {
      mockSystemCtrl.setState(SystemState.missingResources);
      mockUpdateCtrl.setAutoDownloading(true, progress: 0.0);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text(localeCtrl.localeStrings.dEngineDownloading), findsOneWidget);
      expect(find.text(localeCtrl.localeStrings.dEngineDownloadingDesc), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.downloading), findsOneWidget);
    });

    testWidgets('2. Linear progress updates dynamically from 0.0 to 1.0', (tester) async {
      mockSystemCtrl.setState(SystemState.missingResources);
      mockUpdateCtrl.setAutoDownloading(true, progress: 0.0);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text(localeCtrl.localeStrings.dEngineDownloadingDesc), findsOneWidget);

      // Simulate 50% download progress
      mockUpdateCtrl.setAutoDownloading(true, progress: 0.50);
      await tester.pump();

      expect(find.text('50%'), findsOneWidget);

      // Simulate 88% download progress
      mockUpdateCtrl.setAutoDownloading(true, progress: 0.88);
      await tester.pump();

      expect(find.text('88%'), findsOneWidget);

      final progressIndicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progressIndicator.value, equals(0.88));
    });

    testWidgets('3. Error during missing module download renders error UI and Retry button', (tester) async {
      mockSystemCtrl.setState(SystemState.missingResources);
      mockUpdateCtrl.setAutoDownloading(true, progress: 0.2);
      mockUpdateCtrl.setComponentStatuses(ytDlp: ComponentStatus.error);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text(localeCtrl.localeStrings.dDownloadingEngineError), findsOneWidget);
      expect(find.text(localeCtrl.localeStrings.sdGithubConnectionError), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text(localeCtrl.localeStrings.sdButtonRetry), findsOneWidget);

      // Tap Retry button
      await tester.tap(find.text(localeCtrl.localeStrings.sdButtonRetry));
      await tester.pump();

      expect(mockUpdateCtrl.retryCalled, isTrue);
    });

    testWidgets('4. Transitioning to ready state restores normal downloads UI', (tester) async {
      mockSystemCtrl.setState(SystemState.missingResources);
      mockUpdateCtrl.setAutoDownloading(true, progress: 0.5);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text(localeCtrl.localeStrings.dEngineDownloading), findsOneWidget);

      // Engine downloaded & installed, system becomes ready
      mockUpdateCtrl.setAutoDownloading(false, progress: 1.0);
      mockSystemCtrl.setState(SystemState.ready);
      await tester.pump();

      expect(find.text(localeCtrl.localeStrings.dEngineDownloading), findsNothing);
      expect(find.text(localeCtrl.localeStrings.dNoDownloads), findsOneWidget);
    });
  });
}
