import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vidra/core/network/github_client.dart';
import 'package:vidra/core/security/public_keys.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';

class MockSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  SystemState _state = SystemState.initializing;
  int stopBackendCount = 0;
  int resumeInitCount = 0;
  final List<SystemState> stateHistory = [];

  @override
  SystemState get state => _state;

  void setState(SystemState newState) {
    _state = newState;
    stateHistory.add(newState);
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
  Future<void> stopBackendForUpdate() async {
    stopBackendCount++;
  }

  @override
  Future<void> resumeInitialization() async {
    resumeInitCount++;
    setState(SystemState.ready);
  }

  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class MockGithubClient implements GithubClient {
  final Map<String, UpdateInfo> releaseMap = {};
  final Map<String, List<int>> downloadBytesMap = {};
  bool failNextDownload = false;
  int downloadCalls = 0;

  @override
  Future<UpdateInfo?> getLatestReleaseInfo({
    required String repo,
    required List<RegExp> assetRegex,
  }) async {
    if (repo.contains('ejs')) return releaseMap['yt-dlp/ejs'];
    if (repo.contains('yt-dlp')) {
      return releaseMap['yt-dlp/yt-dlp-nightly-builds'] ?? releaseMap['yt-dlp/yt-dlp'];
    }
    if (repo.contains('vidra')) return releaseMap['chomusuke-mk/vidra'];
    return null;
  }

  @override
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async {
    downloadCalls++;
    if (failNextDownload) return false;

    final bytes = downloadBytesMap[url] ?? utf8.encode('default_bytes');
    final file = File(savePath);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    onProgress?.call(bytes.length, bytes.length);
    return true;
  }
}

List<int> _buildModuleArchive({
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
  late MockSystemController mockSystem;
  late MockGithubClient mockGithub;
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
    tempDir = Directory.systemTemp.createTempSync('cold_start_test_');

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

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    mockSystem = MockSystemController();
    mockGithub = MockGithubClient();
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

  group('Adversarial Cold-Start Auto-Download Suite (Task 1)', () {
    test('1. Clean launch with missing yt-dlp and yt-dlp-ejs completes without false fatal errors', () async {
      // Prepare archives for both modules
      final ytdlpBytes = _buildModuleArchive(
        folderName: 'yt_dlp',
        filename: '__init__.py',
        content: '__version__ = "2026.08.20"',
        asZip: false,
      );
      final ejsBytes = _buildModuleArchive(
        folderName: 'yt_dlp_ejs',
        filename: '__init__.py',
        content: '__version__ = "0.5.0"',
        asZip: true,
      );

      final ytdlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.20/yt-dlp.tar.gz';
      final ejsUrl = 'https://github.com/yt-dlp/ejs/releases/download/0.5.0/yt_dlp_ejs-0.5.0-py3-none-any.whl';

      mockGithub.releaseMap['yt-dlp/yt-dlp-nightly-builds'] = UpdateInfo(
        version: '2026.08.20',
        downloadUrl: ytdlpUrl,
        sumsUrl: null,
        sigUrl: null,
        changelog: 'yt-dlp release',
      );

      mockGithub.releaseMap['yt-dlp/ejs'] = UpdateInfo(
        version: '0.5.0',
        downloadUrl: ejsUrl,
        sumsUrl: null,
        sigUrl: null,
        changelog: 'ejs release',
      );

      mockGithub.downloadBytesMap[ytdlpUrl] = ytdlpBytes;
      mockGithub.downloadBytesMap[ejsUrl] = ejsBytes;

      // Verify PublicKeys contract
      expect(PublicKeys.getKeyForComponent(ComponentType.ytDlpEjs), isNull);
      expect(PublicKeys.hasKeyForComponent(ComponentType.ytDlpEjs), isFalse);
      expect(PublicKeys.hasKeyForComponent(ComponentType.ytDlp), isTrue);

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      // Wait for auto-download init sequence
      await Future.delayed(const Duration(milliseconds: 100));

      // 1. Check directories were created and extracted properly
      final ytdlpDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp'));
      final ejsDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs'));
      expect(ytdlpDir.existsSync(), isTrue);
      expect(ejsDir.existsSync(), isTrue);
      expect(File(p.join(ytdlpDir.path, '__init__.py')).existsSync(), isTrue);
      expect(File(p.join(ejsDir.path, '__init__.py')).existsSync(), isTrue);

      // 2. Verify lifecycle calls: stopBackend was NOT called prematurely during cold start
      expect(mockSystem.stopBackendCount, equals(0));
      // 3. resumeInitialization called exactly once at the end of the batch
      expect(mockSystem.resumeInitCount, equals(1));

      // 4. Verify system state never transitioned to fatalError
      expect(mockSystem.stateHistory.contains(SystemState.fatalError), isFalse);
      expect(mockSystem.state, equals(SystemState.ready));

      // 5. Verify states of components
      expect(controller.getState(ComponentType.ytDlp).status, equals(ComponentStatus.upToDate));
      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.upToDate));
      expect(controller.isAutoDownloadingMissing, isFalse);
    });

    test('2. Missing module download failure degrades gracefully without fatalError and allows retry', () async {
      mockGithub.failNextDownload = true; // Simulate network drop

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future.delayed(const Duration(milliseconds: 50));

      // Auto downloading finishes and attempts resume
      expect(controller.isAutoDownloadingMissing, isFalse);
      expect(mockSystem.stateHistory.contains(SystemState.fatalError), isFalse);

      // Retry when network recovers
      mockGithub.failNextDownload = false;
      final ejsBytes = _buildModuleArchive(
        folderName: 'yt_dlp_ejs',
        filename: '__init__.py',
        content: '__version__ = "0.5.0"',
        asZip: true,
      );
      final ejsUrl = 'https://github.com/yt-dlp/ejs/releases/download/0.5.0/yt_dlp_ejs.whl';
      mockGithub.releaseMap['yt-dlp/ejs'] = UpdateInfo(
        version: '0.5.0',
        downloadUrl: ejsUrl,
        changelog: 'ejs',
      );
      mockGithub.downloadBytesMap[ejsUrl] = ejsBytes;

      await controller.retryMissingModulesDownload();
      expect(mockSystem.stateHistory.contains(SystemState.fatalError), isFalse);
    });

    test('3. Partial missing: only yt_dlp_ejs missing downloads only EJS and resumes cleanly', () async {
      // Pre-create yt_dlp
      final ytdlpDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp'))..createSync(recursive: true);
      File(p.join(ytdlpDir.path, '__init__.py')).writeAsStringSync('__version__ = "2026.01.01"');

      final ejsBytes = _buildModuleArchive(
        folderName: 'yt_dlp_ejs',
        filename: '__init__.py',
        content: '__version__ = "0.5.0"',
        asZip: true,
      );
      final ejsUrl = 'https://github.com/yt-dlp/ejs/releases/download/0.5.0/yt_dlp_ejs.whl';
      mockGithub.releaseMap['yt-dlp/ejs'] = UpdateInfo(
        version: '0.5.0',
        downloadUrl: ejsUrl,
        changelog: 'ejs',
      );
      mockGithub.downloadBytesMap[ejsUrl] = ejsBytes;

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future.delayed(const Duration(milliseconds: 80));

      final ejsDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs'));
      expect(ejsDir.existsSync(), isTrue);
      expect(File(p.join(ejsDir.path, '__init__.py')).existsSync(), isTrue);
      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.upToDate));
      expect(mockSystem.stopBackendCount, equals(0));
      expect(mockSystem.resumeInitCount, equals(1));
      expect(mockSystem.stateHistory.contains(SystemState.fatalError), isFalse);
    });

    test('4. Partial missing: only yt_dlp missing downloads only yt_dlp and resumes cleanly', () async {
      // Pre-create yt_dlp_ejs
      final ejsDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs'))..createSync(recursive: true);
      File(p.join(ejsDir.path, '__init__.py')).writeAsStringSync('__version__ = "0.5.0"');

      final ytdlpBytes = _buildModuleArchive(
        folderName: 'yt_dlp',
        filename: '__init__.py',
        content: '__version__ = "2026.08.20"',
        asZip: false,
      );
      final ytdlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.20/yt-dlp.tar.gz';
      mockGithub.releaseMap['yt-dlp/yt-dlp-nightly-builds'] = UpdateInfo(
        version: '2026.08.20',
        downloadUrl: ytdlpUrl,
        changelog: 'yt-dlp',
      );
      mockGithub.downloadBytesMap[ytdlpUrl] = ytdlpBytes;

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future.delayed(const Duration(milliseconds: 80));

      final ytdlpDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp'));
      expect(ytdlpDir.existsSync(), isTrue);
      expect(File(p.join(ytdlpDir.path, '__init__.py')).existsSync(), isTrue);
      expect(controller.getState(ComponentType.ytDlp).status, equals(ComponentStatus.upToDate));
      expect(mockSystem.stopBackendCount, equals(0));
      expect(mockSystem.resumeInitCount, equals(1));
      expect(mockSystem.stateHistory.contains(SystemState.fatalError), isFalse);
    });
  });
}
