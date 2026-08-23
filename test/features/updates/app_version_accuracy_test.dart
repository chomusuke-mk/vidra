import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/core/network/github_client.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';

class FakeSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  @override
  SystemState get state => SystemState.ready;
  @override
  int? get backendPort => 5000;
  @override
  String? get backendToken => 'test_token';
  @override
  String? get serverLogsFilePath => '/path/to/logs';
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

class MockAppDownloadGithubClient implements GithubClient {
  @override
  Future<UpdateInfo?> getLatestReleaseInfo({
    required String repo,
    required List<RegExp> assetRegex,
  }) async {
    return UpdateInfo(
      version: '2.0.0',
      downloadUrl: 'https://example.com/vidra-2.0.0.apk',
      changelog: 'Changelog 2.0.0',
    );
  }

  @override
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async {
    final file = File(savePath);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    file.writeAsStringSync('mock_apk_content');
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeSystemController fakeSystem;
  late MockAppDownloadGithubClient fakeGithub;

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Vidra',
      packageName: 'com.vidra.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('app_version_accuracy_test_');
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
      return {
        'type': 0, // ResultType.done
        'message': 'done',
      };
    });

    fakeSystem = FakeSystemController();
    fakeGithub = MockAppDownloadGithubClient();
  });

  tearDown(() {
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

  group('App Version Accuracy Post-Install Attempt (R4)', () {
    test(
        'Triggering app installer does NOT prematurely mutate local app version state',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Pre-create core modules
      Directory('${tempDir.path}/core_modules/yt_dlp')
          .createSync(recursive: true);
      File('${tempDir.path}/core_modules/yt_dlp/main.py')
          .writeAsStringSync('code');
      Directory('${tempDir.path}/core_modules/yt_dlp_ejs')
          .createSync(recursive: true);
      File('${tempDir.path}/core_modules/yt_dlp_ejs/main.py')
          .writeAsStringSync('code');

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.getState(ComponentType.app).version, equals('1.0.0'));

      // Check for updates
      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.app,
      );
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.app).version, equals('1.0.0'));

      // Attempt download and install via downloadAndInstallInternal
      final info = controller.getState(ComponentType.app).pendingUpdate!;
      final success = await controller.downloadAndInstallInternal(ComponentType.app, info);

      expect(success, isTrue);

      // CRITICAL: Local version must STILL be 1.0.0 from PackageInfo, NOT 2.0.0!
      expect(controller.getState(ComponentType.app).version, equals('1.0.0'));
      expect(prefs.getString('version_app'), isNull);
    });
  });
}
