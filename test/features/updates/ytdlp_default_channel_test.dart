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

class ChannelRecordingGithubClient implements GithubClient {
  final List<Map<String, dynamic>> recordedReleaseCalls = [];

  @override
  Future<UpdateInfo?> getLatestReleaseInfo({
    required ComponentType type,
    required UpdateChannel channel,
    required String targetAssetName,
    bool isPrefixMatch = false,
  }) async {
    recordedReleaseCalls.add({
      'type': type,
      'channel': channel,
      'targetAssetName': targetAssetName,
      'isPrefixMatch': isPrefixMatch,
    });
    return UpdateInfo(
      version: '2026.08.19',
      changelog: 'Mock changelog',
      downloadUrl: 'https://example.com/asset.tar.gz',
      type: type,
    );
  }

  @override
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async {
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeSystemController fakeSystemCtrl;
  late ChannelRecordingGithubClient fakeGithub;

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
    tempDir = Directory.systemTemp.createTempSync('ytdlp_channel_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationSupportDirectory' ||
            methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return tempDir.path;
      },
    );

    fakeSystemCtrl = FakeSystemController();
    fakeGithub = ChannelRecordingGithubClient();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('yt-dlp Default Channel in UpdateController', () {
    test('Default channel is nightly when channel_ytdlp is unset in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(fakeGithub, fakeSystemCtrl, prefs);

      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.ytDlp,
      );

      final ytDlpCalls = fakeGithub.recordedReleaseCalls
          .where((call) => call['type'] == ComponentType.ytDlp)
          .toList();

      expect(ytDlpCalls, isNotEmpty);
      expect(ytDlpCalls.first['channel'], equals(UpdateChannel.nightly));
    });

    test('Channel is nightly when channel_ytdlp is explicitly set to nightly', () async {
      SharedPreferences.setMockInitialValues({
        'channel_ytdlp': 'nightly',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(fakeGithub, fakeSystemCtrl, prefs);

      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.ytDlp,
      );

      final ytDlpCalls = fakeGithub.recordedReleaseCalls
          .where((call) => call['type'] == ComponentType.ytDlp)
          .toList();

      expect(ytDlpCalls, isNotEmpty);
      expect(ytDlpCalls.first['channel'], equals(UpdateChannel.nightly));
    });

    test('Channel is stable only when channel_ytdlp is explicitly set to stable', () async {
      SharedPreferences.setMockInitialValues({
        'channel_ytdlp': 'stable',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(fakeGithub, fakeSystemCtrl, prefs);

      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.ytDlp,
      );

      final ytDlpCalls = fakeGithub.recordedReleaseCalls
          .where((call) => call['type'] == ComponentType.ytDlp)
          .toList();

      expect(ytDlpCalls, isNotEmpty);
      expect(ytDlpCalls.first['channel'], equals(UpdateChannel.stable));
    });

    test('Switching channel dynamically from unset to stable updates subsequent checks', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(fakeGithub, fakeSystemCtrl, prefs);

      // Check 1: Unset -> defaults to nightly
      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.ytDlp,
      );
      var ytDlpCalls = fakeGithub.recordedReleaseCalls
          .where((c) => c['type'] == ComponentType.ytDlp)
          .toList();
      expect(ytDlpCalls.last['channel'], equals(UpdateChannel.nightly));

      // Switch to stable
      await prefs.setString('channel_ytdlp', 'stable');

      // Check 2: Explicit stable
      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.ytDlp,
      );
      ytDlpCalls = fakeGithub.recordedReleaseCalls
          .where((c) => c['type'] == ComponentType.ytDlp)
          .toList();
      expect(ytDlpCalls.last['channel'], equals(UpdateChannel.stable));

      // Switch back to nightly
      await prefs.setString('channel_ytdlp', 'nightly');

      // Check 3: Explicit nightly
      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.ytDlp,
      );
      ytDlpCalls = fakeGithub.recordedReleaseCalls
          .where((c) => c['type'] == ComponentType.ytDlp)
          .toList();
      expect(ytDlpCalls.last['channel'], equals(UpdateChannel.nightly));
    });

    test('Default fallback expression evaluates to nightly when key is absent', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final defaultChannel = prefs.getString('channel_ytdlp') ?? 'nightly';
      expect(defaultChannel, equals('nightly'));
    });
  });
}
