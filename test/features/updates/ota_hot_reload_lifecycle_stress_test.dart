import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vidra/core/network/github_client.dart';
import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';

/// Simulated Isolate & System Bridge to test end-to-end IPC and lifecycle
class EndToEndLifecycleHarness {
  final List<String> eventLog = [];
  SystemState systemState = SystemState.ready;
  bool isBackendRunning = true;
  bool isUpdating = false;
  Timer? healthCheckTimer;
  Completer<void>? pauseCompleter;

  late final VidraHttpClient httpClient;
  late final MockClient mockHttpTransport;
  int otaLoadCalls = 0;
  int otaUnloadCalls = 0;

  EndToEndLifecycleHarness() {
    mockHttpTransport = MockClient((request) async {
      if (request.url.path == '/ota') {
        final action = request.url.queryParameters['action'] ?? '';
        if (action == 'unload') {
          otaUnloadCalls++;
          eventLog.add('python_ota_unload');
          return http.Response(jsonEncode({'message': 'unloaded'}), 200);
        } else if (action == 'load') {
          otaLoadCalls++;
          eventLog.add('python_ota_load');
          return http.Response(jsonEncode({'message': 'loaded'}), 200);
        }
      }
      if (request.url.path == '/health') {
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }
      return http.Response('Not Found', 404);
    });

    httpClient = VidraHttpClient(
      baseUrl: 'http://127.0.0.1:5000',
      defaultHeaders: {},
      token: 'token',
      client: mockHttpTransport,
    );
  }

  Future<void> dispatchIsolateCommand(Map<String, dynamic> msg) async {
    final cmd = msg['cmd'];
    eventLog.add('isolate_cmd_$cmd');

    switch (cmd) {
      case 'pause_for_update':
        isUpdating = true;
        healthCheckTimer?.cancel();
        await httpClient.otaAction('unload');
        systemState = SystemState.initializing;
        eventLog.add('isolate_paused_ack');
        pauseCompleter?.complete();
        break;

      case 'revalidate':
        isUpdating = false;
        if (isBackendRunning) {
          bool ok = false;
          for (int attempt = 1; attempt <= 15; attempt++) {
            ok = await httpClient.otaAction('load');
            if (ok) break;
            await Future.delayed(const Duration(milliseconds: 10));
          }
          if (ok) {
            systemState = SystemState.ready;
            eventLog.add('isolate_revalidated_ready');
          } else {
            systemState = SystemState.fatalError;
          }
        }
        break;
    }
  }

  Future<void> stopBackendForUpdate() async {
    eventLog.add('ui_stopBackendForUpdate_start');
    pauseCompleter = Completer<void>();
    await dispatchIsolateCommand({'cmd': 'pause_for_update'});
    await pauseCompleter!.future;
    eventLog.add('ui_stopBackendForUpdate_done');
  }

  Future<void> resumeInitialization() async {
    eventLog.add('ui_resumeInitialization_start');
    systemState = SystemState.initializing;
    await dispatchIsolateCommand({'cmd': 'revalidate'});
    eventLog.add('ui_resumeInitialization_done');
  }
}

class SystemBridgeController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  final EndToEndLifecycleHarness harness;

  SystemBridgeController(this.harness);

  @override
  SystemState get state => harness.systemState;
  @override
  int? get backendPort => 5000;
  @override
  String? get backendToken => 'token';
  @override
  String? get serverLogsFilePath => '/path/logs';
  @override
  Future<void> get whenPortReady => Future.value();

  @override
  Future<void> stopBackendForUpdate() => harness.stopBackendForUpdate();

  @override
  Future<void> resumeInitialization() => harness.resumeInitialization();

  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class LifecycleGithubClient implements GithubClient {
  final Map<String, List<int>> downloadBytesMap = {};
  int downloadCalls = 0;
  bool shouldFail = false;

  @override
  Future<UpdateInfo?> getLatestReleaseInfo({
    required String repo,
    required List<RegExp> assetRegex,
  }) async => null;

  @override
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async {
    downloadCalls++;
    if (shouldFail) return false;
    final bytes = downloadBytesMap[url] ?? utf8.encode('dummy');
    final file = File(savePath);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    onProgress?.call(bytes.length, bytes.length);
    return true;
  }
}

List<int> _createModuleArchive({
  required String folderName,
  required String filename,
  required String content,
  bool asZip = false,
}) {
  final archive = Archive();
  final data = utf8.encode(content);
  archive.addFile(ArchiveFile('$folderName/$filename', data.length, data));
  if (asZip) {
    return ZipEncoder().encode(archive);
  } else {
    final tarBytes = TarEncoder().encode(archive);
    return GZipEncoder().encode(tarBytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late EndToEndLifecycleHarness harness;
  late SystemBridgeController systemBridge;
  late LifecycleGithubClient mockGithub;
  late SharedPreferences prefs;

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Vidra',
      packageName: 'com.vidra.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ota_lifecycle_test_');

    const MethodChannel pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (MethodCall methodCall) async => tempDir.path,
    );

    const MethodChannel openFileChannel = MethodChannel('open_filex');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      openFileChannel,
      (MethodCall methodCall) async => {'type': 0, 'message': 'done'},
    );

    SharedPreferences.setMockInitialValues({
      'version_yt_dlp': '2026.01.01',
      'version_yt_dlp_ejs': '0.1.0',
    });
    prefs = await SharedPreferences.getInstance();

    // Pre-create modules so init doesn't auto-download
    Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp')).createSync(recursive: true);
    File(p.join(tempDir.path, 'core_modules', 'yt_dlp', '__init__.py')).writeAsStringSync('v=1');
    Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs')).createSync(recursive: true);
    File(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs', '__init__.py')).writeAsStringSync('v=1');

    harness = EndToEndLifecycleHarness();
    systemBridge = SystemBridgeController(harness);
    mockGithub = LifecycleGithubClient();
  });

  tearDown(() {
    const MethodChannel pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      null,
    );

    const MethodChannel openFileChannel = MethodChannel('open_filex');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      openFileChannel,
      null,
    );

    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('OTA Hot-Reload Lifecycle Transitions Stress Tests (Task 2)', () {
    test('1. Full Hot-Reload Transition Flow (pause_for_update -> paused_ack -> extract -> revalidate -> load)', () async {
      final ytdlpArchive = _createModuleArchive(
        folderName: 'yt_dlp',
        filename: '__init__.py',
        content: '__version__ = "2026.09.01"',
        asZip: false,
      );
      final updateUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.09.01/yt-dlp.tar.gz';
      mockGithub.downloadBytesMap[updateUrl] = ytdlpArchive;

      final updateInfo = UpdateInfo(
        version: '2026.09.01',
        downloadUrl: updateUrl,
        changelog: 'hot reload update',
      );

      final controller = UpdateController(mockGithub, systemBridge, prefs);

      final success = await controller.downloadAndInstallInternal(
        ComponentType.ytDlp,
        updateInfo,
      );

      expect(success, isTrue);
      expect(controller.getState(ComponentType.ytDlp).status, equals(ComponentStatus.upToDate));
      expect(controller.getState(ComponentType.ytDlp).version, equals('2026.09.01'));

      // Check event sequence
      expect(harness.eventLog, containsAllInOrder([
        'ui_stopBackendForUpdate_start',
        'isolate_cmd_pause_for_update',
        'python_ota_unload',
        'isolate_paused_ack',
        'ui_stopBackendForUpdate_done',
        'ui_resumeInitialization_start',
        'isolate_cmd_revalidate',
        'python_ota_load',
        'isolate_revalidated_ready',
        'ui_resumeInitialization_done',
      ]));

      expect(harness.otaUnloadCalls, equals(1));
      expect(harness.otaLoadCalls, equals(1));
      expect(harness.systemState, equals(SystemState.ready));
    });

    test('2. Multiple Consecutive OTA Updates (5 back-to-back hot-reloads)', () async {
      final controller = UpdateController(mockGithub, systemBridge, prefs);

      for (int i = 1; i <= 5; i++) {
        final version = '2026.09.0$i';
        final archive = _createModuleArchive(
          folderName: 'yt_dlp',
          filename: '__init__.py',
          content: '__version__ = "$version"',
          asZip: false,
        );
        final url = 'https://github.com/yt-dlp/yt-dlp/releases/download/$version/yt-dlp.tar.gz';
        mockGithub.downloadBytesMap[url] = archive;

        final info = UpdateInfo(
          version: version,
          downloadUrl: url,
          changelog: 'v$i',
        );

        final ok = await controller.downloadAndInstallInternal(ComponentType.ytDlp, info);
        expect(ok, isTrue);
        expect(controller.getState(ComponentType.ytDlp).version, equals(version));
        expect(harness.systemState, equals(SystemState.ready));
      }

      expect(harness.otaUnloadCalls, equals(5));
      expect(harness.otaLoadCalls, equals(5));
    });

    test('3. Failed Extraction still guarantees unpausing and resumeInitialization', () async {
      final brokenArchiveBytes = utf8.encode('corrupted_not_a_valid_tar_or_zip');
      final brokenUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/broken/yt-dlp.tar.gz';
      mockGithub.downloadBytesMap[brokenUrl] = brokenArchiveBytes;

      final brokenInfo = UpdateInfo(
        version: 'broken_version',
        downloadUrl: brokenUrl,
        changelog: 'broken',
      );

      final controller = UpdateController(mockGithub, systemBridge, prefs);

      final ok = await controller.downloadAndInstallInternal(ComponentType.ytDlp, brokenInfo);
      expect(ok, isFalse);
      expect(controller.getState(ComponentType.ytDlp).status, equals(ComponentStatus.error));

      // Despite error, finally block must unpause backend isolate
      expect(harness.eventLog, contains('ui_resumeInitialization_start'));
      expect(harness.eventLog, contains('isolate_cmd_revalidate'));
      expect(harness.systemState, equals(SystemState.ready));
    });
  });
}
