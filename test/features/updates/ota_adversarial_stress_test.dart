import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vidra/core/network/github_client.dart';
import 'package:vidra/core/security/pgp_verifier.dart';
import 'package:vidra/core/utils/archive_extractor.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';

/// Fake SystemController that records isolate pause/resume lifecycle calls
class FakeSystemController extends ChangeNotifier with WidgetsBindingObserver implements SystemController {
  int stopBackendCallCount = 0;
  int resumeInitializationCallCount = 0;
  bool isBackendPaused = false;
  final List<String> callLog = [];
  final SystemState _state = SystemState.ready;

  @override
  SystemState get state => _state;

  @override
  int? get backendPort => 5000;

  @override
  String? get backendToken => 'test_token';

  @override
  String? get serverLogsFilePath => '/path/to/logs';

  @override
  Future<void> get whenPortReady => Future.value();

  @override
  Future<void> stopBackendForUpdate() async {
    stopBackendCallCount++;
    isBackendPaused = true;
    callLog.add('stopBackendForUpdate');
  }

  @override
  Future<void> resumeInitialization() async {
    resumeInitializationCallCount++;
    isBackendPaused = false;
    callLog.add('resumeInitialization');
  }

  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

/// Fake GithubClient supporting custom simulated download responses per URL
class FakeGithubClient implements GithubClient {
  final Map<String, Future<bool> Function(String savePath, Function(int, int)? onProgress)> downloadHandlers = {};
  final Map<ComponentType, UpdateInfo> releaseInfoMap = {};

  @override
  Future<UpdateInfo?> getLatestReleaseInfo({
    required ComponentType type,
    required UpdateChannel channel,
    required String targetAssetName,
    bool isPrefixMatch = false,
  }) async {
    return releaseInfoMap[type];
  }

  @override
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async {
    final handler = downloadHandlers[url];
    if (handler != null) {
      return handler(savePath, onProgress);
    }

    // Default mock download behavior
    final file = File(savePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsStringSync('default_mock_content');
    onProgress?.call(100, 100);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testRoot;
  late FakeSystemController fakeSystem;
  late FakeGithubClient fakeGithub;
  late SharedPreferences prefs;

  setUp(() async {
    testRoot = Directory.systemTemp.createTempSync('ota_adversarial_test_');

    // Mock path_provider channel
    const MethodChannel pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (MethodCall methodCall) async {
        return testRoot.path;
      },
    );

    // Mock package_info
    PackageInfo.setMockInitialValues(
      appName: 'Vidra',
      packageName: 'com.vidra.app',
      version: '3.0.0',
      buildNumber: '50',
      buildSignature: '',
    );

    SharedPreferences.setMockInitialValues({
      'last_update_check_app': DateTime.now().millisecondsSinceEpoch,
      'last_update_check_yt_dlp': DateTime.now().millisecondsSinceEpoch,
      'last_update_check_yt_dlp_ejs': DateTime.now().millisecondsSinceEpoch,
      'version_yt_dlp': '2024.01.01',
      'version_yt_dlp_ejs': '0.1.0',
    });
    prefs = await SharedPreferences.getInstance();

    fakeSystem = FakeSystemController();
    fakeGithub = FakeGithubClient();
  });

  tearDown(() {
    const MethodChannel pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      null,
    );

    if (testRoot.existsSync()) {
      testRoot.deleteSync(recursive: true);
    }
  });

  /// Helper to create a valid tar.gz or zip containing target Python module
  List<int> createValidArchiveBytes({
    required String targetFolder,
    required String innerFileName,
    required String innerContent,
    bool asZip = true,
  }) {
    final archive = Archive();
    final fileBytes = utf8.encode(innerContent);
    archive.addFile(
      ArchiveFile(
        '$targetFolder/$innerFileName',
        fileBytes.length,
        fileBytes,
      ),
    );

    if (asZip) {
      return ZipEncoder().encode(archive);
    } else {
      final tarData = TarEncoder().encode(archive);
      return GZipEncoder().encode(tarData);
    }
  }

  // ===========================================================================
  // CATEGORY 1: CONCURRENT DOWNLOADS & NAMESPACING COLLISION RESISTANCE
  // ===========================================================================
  group('1. Concurrent Downloads Across Components (ytDlp & ytDlpEjs)', () {
    test('Temp directory namespacing prevents file collision and race conditions during simultaneous downloads', () async {
      // ytDlp archive (tar.gz) and ytDlpEjs archive (.whl/zip)
      final ytDlpArchiveBytes = createValidArchiveBytes(
        targetFolder: 'yt_dlp',
        innerFileName: '__init__.py',
        innerContent: '__version__ = "2026.08.15"',
        asZip: false,
      );
      final ytDlpEjsArchiveBytes = createValidArchiveBytes(
        targetFolder: 'yt_dlp_ejs',
        innerFileName: '__init__.py',
        innerContent: '__version__ = "0.8.0"',
        asZip: true,
      );

      final ytdlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.15/yt-dlp.tar.gz';
      final ytdlpSumsUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.15/SHA2-512SUMS';
      final ytdlpSigUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.15/SHA2-512SUMS.sig';

      final ejsUrl = 'https://github.com/yt-dlp/ejs/releases/download/0.8.0/yt_dlp_ejs-0.8.0-py3-none-any.whl';

      // Set up pending updates for both
      fakeGithub.releaseInfoMap[ComponentType.ytDlp] = UpdateInfo(
        version: '2026.08.15',
        downloadUrl: ytdlpUrl,
        sumsUrl: ytdlpSumsUrl,
        sigUrl: ytdlpSigUrl,
        changelog: 'yt-dlp update',
        type: ComponentType.ytDlp,
      );

      fakeGithub.releaseInfoMap[ComponentType.ytDlpEjs] = UpdateInfo(
        version: '0.8.0',
        downloadUrl: ejsUrl,
        sumsUrl: null, // EJS does not require PGP validation
        sigUrl: null,
        changelog: 'ejs update',
        type: ComponentType.ytDlpEjs,
      );

      // Handlers simulating concurrent async network download latency
      fakeGithub.downloadHandlers[ytdlpUrl] = (savePath, onProgress) async {
        await Future.delayed(const Duration(milliseconds: 30));
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(ytDlpArchiveBytes);
        onProgress?.call(ytDlpArchiveBytes.length, ytDlpArchiveBytes.length);
        return true;
      };

      final ytdlpHash = sha512.convert(ytDlpArchiveBytes).toString();
      fakeGithub.downloadHandlers[ytdlpSumsUrl] = (savePath, onProgress) async {
        await Future.delayed(const Duration(milliseconds: 20));
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsStringSync('$ytdlpHash  yt-dlp.tar.gz\n');
        return true;
      };
      fakeGithub.downloadHandlers[ytdlpSigUrl] = (savePath, onProgress) async {
        await Future.delayed(const Duration(milliseconds: 20));
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsStringSync('-----BEGIN PGP SIGNATURE-----\nfake\n-----END PGP SIGNATURE-----');
        return true;
      };

      fakeGithub.downloadHandlers[ejsUrl] = (savePath, onProgress) async {
        await Future.delayed(const Duration(milliseconds: 25));
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(ytDlpEjsArchiveBytes);
        onProgress?.call(ytDlpEjsArchiveBytes.length, ytDlpEjsArchiveBytes.length);
        return true;
      };

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await controller.checkForUpdates();

      // Ensure both pending updates are registered
      expect(controller.getState(ComponentType.ytDlp).status, equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.updateAvailable));

      // Trigger parallel downloads of both components concurrently
      await Future.wait([
        controller.downloadAndInstall(ComponentType.ytDlp),
        controller.downloadAndInstall(ComponentType.ytDlpEjs),
      ]);

      // EJS should succeed cleanly to upToDate
      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.upToDate));
      expect(prefs.getString('version_yt_dlp_ejs'), equals('0.8.0'));

      // Check destinations
      final ejsDest = Directory(p.join(testRoot.path, 'core_modules', 'yt_dlp_ejs'));
      expect(ejsDest.existsSync(), isTrue);
      expect(File(p.join(ejsDest.path, '__init__.py')).existsSync(), isTrue);
      expect(File(p.join(ejsDest.path, '__init__.py')).readAsStringSync(), equals('__version__ = "0.8.0"'));

      // Verify temp folders are clean and independent
      final tempYtDlp = Directory(p.join(testRoot.path, 'temp_updates', 'ytDlp'));
      final tempYtDlpEjs = Directory(p.join(testRoot.path, 'temp_updates', 'ytDlpEjs'));
      expect(tempYtDlp.existsSync(), isFalse);
      expect(tempYtDlpEjs.existsSync(), isFalse);
    });

    test('Simultaneous ArchiveExtractor extraction on ytDlp and ytDlpEjs handles independent staging without collision', () async {
      final destDir1 = Directory(p.join(testRoot.path, 'core_modules', 'yt_dlp'));
      final destDir2 = Directory(p.join(testRoot.path, 'core_modules', 'yt_dlp_ejs'));

      final archive1Bytes = createValidArchiveBytes(
        targetFolder: 'yt_dlp',
        innerFileName: 'core.py',
        innerContent: 'def ytdlp(): pass',
        asZip: true,
      );
      final archive2Bytes = createValidArchiveBytes(
        targetFolder: 'yt_dlp_ejs',
        innerFileName: 'engine.py',
        innerContent: 'def ejs(): pass',
        asZip: true,
      );

      final file1 = File(p.join(testRoot.path, 'temp1.zip'))..writeAsBytesSync(archive1Bytes);
      final file2 = File(p.join(testRoot.path, 'temp2.zip'))..writeAsBytesSync(archive2Bytes);

      // Run 50 concurrent extractions in parallel to hammer staging dir creation
      final futures = <Future<bool>>[];
      for (int i = 0; i < 25; i++) {
        futures.add(ArchiveExtractor.extractPythonModule(
          archiveFile: file1,
          destinationDir: destDir1,
          targetSubfolderName: 'yt_dlp',
        ));
        futures.add(ArchiveExtractor.extractPythonModule(
          archiveFile: file2,
          destinationDir: destDir2,
          targetSubfolderName: 'yt_dlp_ejs',
        ));
      }

      final results = await Future.wait(futures);
      expect(results.every((r) => r == true), isTrue);

      // Verify final destinations are valid
      expect(File(p.join(destDir1.path, 'core.py')).readAsStringSync(), equals('def ytdlp(): pass'));
      expect(File(p.join(destDir2.path, 'engine.py')).readAsStringSync(), equals('def ejs(): pass'));

      // Verify no orphan staging directories
      final parentDir = destDir1.parent;
      final stagingDirs = parentDir.listSync().where((e) => e.path.contains('_staging_')).toList();
      expect(stagingDirs, isEmpty);
    });
  });

  // ===========================================================================
  // CATEGORY 2: CORRUPTED DOWNLOADS, 0-BYTE FILES & MISSING SIGNATURE/SUMS
  // ===========================================================================
  group('2. Corrupted Downloads, 0-Byte Files, & Missing Signature/Sums', () {
    test('0-byte binary file causes immediate error state and never invokes backend pause', () async {
      final ejsUrl = 'https://github.com/yt-dlp/ejs/releases/download/0.8.0/yt_dlp_ejs.whl';

      fakeGithub.releaseInfoMap[ComponentType.ytDlpEjs] = UpdateInfo(
        version: '0.8.0',
        downloadUrl: ejsUrl,
        changelog: 'empty binary test',
        type: ComponentType.ytDlpEjs,
      );

      // Handler produces 0-byte file
      fakeGithub.downloadHandlers[ejsUrl] = (savePath, onProgress) async {
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync([]); // 0 bytes
        return true;
      };

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await controller.checkForUpdates();

      await controller.downloadAndInstall(ComponentType.ytDlpEjs);

      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.error));
      // Backend pause should NOT have been called because download validation failed early
      expect(fakeSystem.stopBackendCallCount, equals(0));
    });

    test('Failed binary download (network error) results in error state without throwing', () async {
      final ejsUrl = 'https://github.com/yt-dlp/ejs/releases/download/0.8.0/yt_dlp_ejs.whl';

      fakeGithub.releaseInfoMap[ComponentType.ytDlpEjs] = UpdateInfo(
        version: '0.8.0',
        downloadUrl: ejsUrl,
        changelog: 'network error test',
        type: ComponentType.ytDlpEjs,
      );

      fakeGithub.downloadHandlers[ejsUrl] = (savePath, onProgress) async {
        return false; // Download failed
      };

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await controller.checkForUpdates();

      await controller.downloadAndInstall(ComponentType.ytDlpEjs);

      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.error));
      expect(fakeSystem.stopBackendCallCount, equals(0));
    });

    test('Missing / 0-byte sums file on PGP-validated component halts at verifying stage with error state', () async {
      final ytdlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.15/yt-dlp.tar.gz';
      final sumsUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.15/SHA2-512SUMS';
      final sigUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.15/SHA2-512SUMS.sig';

      fakeGithub.releaseInfoMap[ComponentType.ytDlp] = UpdateInfo(
        version: '2026.08.15',
        downloadUrl: ytdlpUrl,
        sumsUrl: sumsUrl,
        sigUrl: sigUrl,
        changelog: 'sums fail test',
        type: ComponentType.ytDlp,
      );

      fakeGithub.downloadHandlers[ytdlpUrl] = (savePath, onProgress) async {
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(utf8.encode('valid_binary_bytes'));
        return true;
      };

      // Sums download returns false or empty file
      fakeGithub.downloadHandlers[sumsUrl] = (savePath, onProgress) async {
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync([]); // 0-byte sums
        return false;
      };

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await controller.checkForUpdates();

      await controller.downloadAndInstall(ComponentType.ytDlp);

      expect(controller.getState(ComponentType.ytDlp).status, equals(ComponentStatus.error));
      expect(fakeSystem.stopBackendCallCount, equals(0));
    });

    test('Missing / 0-byte sig file on PGP-validated component halts at verifying stage with error state', () async {
      final ytdlpUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.15/yt-dlp.tar.gz';
      final sumsUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.15/SHA2-512SUMS';
      final sigUrl = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.15/SHA2-512SUMS.sig';

      fakeGithub.releaseInfoMap[ComponentType.ytDlp] = UpdateInfo(
        version: '2026.08.15',
        downloadUrl: ytdlpUrl,
        sumsUrl: sumsUrl,
        sigUrl: sigUrl,
        changelog: 'sig fail test',
        type: ComponentType.ytDlp,
      );

      fakeGithub.downloadHandlers[ytdlpUrl] = (savePath, onProgress) async {
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(utf8.encode('valid_binary_bytes'));
        return true;
      };

      fakeGithub.downloadHandlers[sumsUrl] = (savePath, onProgress) async {
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsStringSync('dummy_hash  yt-dlp.tar.gz');
        return true;
      };

      // Sig download fails
      fakeGithub.downloadHandlers[sigUrl] = (savePath, onProgress) async {
        return false;
      };

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await controller.checkForUpdates();

      await controller.downloadAndInstall(ComponentType.ytDlp);

      expect(controller.getState(ComponentType.ytDlp).status, equals(ComponentStatus.error));
      expect(fakeSystem.stopBackendCallCount, equals(0));
    });

    test('Corrupted binary checksum mismatch causes PgpVerifier to reject payload without exception', () async {
      final binaryFile = File(p.join(testRoot.path, 'yt-dlp.tar.gz'))..writeAsStringSync('corrupted_binary_data');
      final sumsFile = File(p.join(testRoot.path, 'sums'))..writeAsStringSync('different_hash_12345  yt-dlp.tar.gz\n');
      final sigFile = File(p.join(testRoot.path, 'sig'))..writeAsStringSync('-----BEGIN PGP SIGNATURE-----\nfake\n-----END PGP SIGNATURE-----');

      final result = await PgpVerifier.verifyBinary(
        binaryFile: binaryFile,
        sumsFile: sumsFile,
        sigFile: sigFile,
        publicKey: 'dummy_public_key',
        expectedBinaryName: 'yt-dlp.tar.gz',
      );

      expect(result, isFalse);
    });

    test('PgpVerifier safely handles missing target filename in sums file', () async {
      final binaryFile = File(p.join(testRoot.path, 'yt-dlp.tar.gz'))..writeAsStringSync('some_bytes');
      final sumsFile = File(p.join(testRoot.path, 'sums'))..writeAsStringSync('some_hash  unrelated_file.zip\nanother_hash  something_else.tar.gz\n');
      final sigFile = File(p.join(testRoot.path, 'sig'))..writeAsStringSync('-----BEGIN PGP SIGNATURE-----\nfake\n-----END PGP SIGNATURE-----');

      final result = await PgpVerifier.verifyBinary(
        binaryFile: binaryFile,
        sumsFile: sumsFile,
        sigFile: sigFile,
        publicKey: 'dummy_public_key',
        expectedBinaryName: 'yt-dlp.tar.gz',
      );

      expect(result, isFalse);
    });
  });

  // ===========================================================================
  // CATEGORY 3: EXTRACTION FAILURES, DESTINATION SAFETY & ISOLATE RESUME
  // ===========================================================================
  group('3. Extraction Failures, Module Preservation & Isolate Resume Lifecycle', () {
    test('Non-archive corrupted garbage payload fails extraction and leaves existing destination 100% intact', () async {
      final destDir = Directory(p.join(testRoot.path, 'core_modules', 'yt_dlp_ejs'))..createSync(recursive: true);
      final originalFile = File(p.join(destDir.path, '__init__.py'))..writeAsStringSync('# ORIGINAL WORKING MODULE');
      final originalCode = File(p.join(destDir.path, 'worker.py'))..writeAsStringSync('def work(): return 42');

      final corruptedArchive = File(p.join(testRoot.path, 'corrupt.whl'))..writeAsBytesSync([0x00, 0xFF, 0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34]);

      final result = await ArchiveExtractor.extractPythonModule(
        archiveFile: corruptedArchive,
        destinationDir: destDir,
        targetSubfolderName: 'yt_dlp_ejs',
      );

      expect(result, isFalse);
      expect(destDir.existsSync(), isTrue);
      expect(originalFile.existsSync(), isTrue);
      expect(originalFile.readAsStringSync(), equals('# ORIGINAL WORKING MODULE'));
      expect(originalCode.existsSync(), isTrue);
      expect(originalCode.readAsStringSync(), equals('def work(): return 42'));
    });

    test('Valid archive lacking target subfolder fails extraction and leaves existing destination intact', () async {
      final destDir = Directory(p.join(testRoot.path, 'core_modules', 'yt_dlp'))..createSync(recursive: true);
      final originalFile = File(p.join(destDir.path, 'main.py'))..writeAsStringSync('# PRODUCTION YTDLP');

      // Archive has files under "wrong_package/" instead of "yt_dlp/"
      final archiveBytes = createValidArchiveBytes(
        targetFolder: 'wrong_package',
        innerFileName: 'main.py',
        innerContent: '# WRONG CONTENT',
        asZip: true,
      );
      final archiveFile = File(p.join(testRoot.path, 'wrong.zip'))..writeAsBytesSync(archiveBytes);

      final result = await ArchiveExtractor.extractPythonModule(
        archiveFile: archiveFile,
        destinationDir: destDir,
        targetSubfolderName: 'yt_dlp',
      );

      expect(result, isFalse);
      expect(destDir.existsSync(), isTrue);
      expect(originalFile.existsSync(), isTrue);
      expect(originalFile.readAsStringSync(), equals('# PRODUCTION YTDLP'));
    });

    test('Extraction failure during downloadAndInstall GUARANTEES isolate resume via try/finally', () async {
      final destDir = Directory(p.join(testRoot.path, 'core_modules', 'yt_dlp_ejs'))..createSync(recursive: true);
      final existingFile = File(p.join(destDir.path, '__init__.py'))..writeAsStringSync('# ACTIVE PRODUCTION MODULE');

      final ejsUrl = 'https://github.com/yt-dlp/ejs/releases/download/0.8.0/yt_dlp_ejs.whl';

      fakeGithub.releaseInfoMap[ComponentType.ytDlpEjs] = UpdateInfo(
        version: '0.8.0',
        downloadUrl: ejsUrl,
        changelog: 'corrupt payload test',
        type: ComponentType.ytDlpEjs,
      );

      // Download succeeds with corrupted non-zip content
      fakeGithub.downloadHandlers[ejsUrl] = (savePath, onProgress) async {
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(utf8.encode('NON_ZIP_CORRUPTED_BYTES'));
        return true;
      };

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await controller.checkForUpdates();

      expect(fakeSystem.stopBackendCallCount, equals(0));
      expect(fakeSystem.resumeInitializationCallCount, equals(0));

      await controller.downloadAndInstall(ComponentType.ytDlpEjs);

      // State transitions to error
      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.error));

      // CRITICAL GUARANTEE: stopBackend was called, and resumeInitialization was ALWAYS called in finally
      expect(fakeSystem.stopBackendCallCount, equals(1));
      expect(fakeSystem.resumeInitializationCallCount, equals(1));
      expect(fakeSystem.isBackendPaused, isFalse);
      expect(fakeSystem.callLog, equals(['stopBackendForUpdate', 'resumeInitialization']));

      // Destination module was NOT destroyed
      expect(destDir.existsSync(), isTrue);
      expect(existingFile.existsSync(), isTrue);
      expect(existingFile.readAsStringSync(), equals('# ACTIVE PRODUCTION MODULE'));
    });

    test('Catastrophic filesystem exception during extraction still guarantees isolate resume and error status', () async {
      final ejsUrl = 'https://github.com/yt-dlp/ejs/releases/download/0.8.0/yt_dlp_ejs.whl';

      fakeGithub.releaseInfoMap[ComponentType.ytDlpEjs] = UpdateInfo(
        version: '0.8.0',
        downloadUrl: ejsUrl,
        changelog: 'filesystem error test',
        type: ComponentType.ytDlpEjs,
      );

      final validArchiveBytes = createValidArchiveBytes(
        targetFolder: 'yt_dlp_ejs',
        innerFileName: '__init__.py',
        innerContent: '__version__ = "0.8.0"',
        asZip: true,
      );

      fakeGithub.downloadHandlers[ejsUrl] = (savePath, onProgress) async {
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(validArchiveBytes);
        return true;
      };

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await controller.checkForUpdates();

      // Create a conflicting regular file where core_modules directory is expected to cause extraction failure
      final coreModulesAsFile = File(p.join(testRoot.path, 'core_modules'));
      coreModulesAsFile.writeAsStringSync('BLOCKING_FILE');

      await controller.downloadAndInstall(ComponentType.ytDlpEjs);

      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.error));
      // Even with catastrophic FS conflict, isolate was resumed
      expect(fakeSystem.stopBackendCallCount, equals(1));
      expect(fakeSystem.resumeInitializationCallCount, equals(1));
      expect(fakeSystem.isBackendPaused, isFalse);
    });
  });
}
