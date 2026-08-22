import 'dart:convert';
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

class FakeGithubClient implements GithubClient {
  int fetchCallCount = 0;
  final List<ComponentType> requestedTypes = [];
  UpdateInfo? appUpdate;
  UpdateInfo? ytDlpUpdate;
  UpdateInfo? ytDlpEjsUpdate;

  @override
  Future<UpdateInfo?> getLatestReleaseInfo({
    required ComponentType type,
    required UpdateChannel channel,
    required String targetAssetName,
    bool isPrefixMatch = false,
  }) async {
    fetchCallCount++;
    requestedTypes.add(type);
    if (type == ComponentType.app) return appUpdate;
    if (type == ComponentType.ytDlp) return ytDlpUpdate;
    if (type == ComponentType.ytDlpEjs) return ytDlpEjsUpdate;
    return null;
  }

  @override
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeSystemController fakeSystem;
  late FakeGithubClient fakeGithub;

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
    tempDir = Directory.systemTemp.createTempSync('update_interval_test_');
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (MethodCall methodCall) async {
      return tempDir.path;
    });

    fakeSystem = FakeSystemController();
    fakeGithub = FakeGithubClient();
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

  group('Update Interval and Discovered State Caching (R2)', () {
    test(
        '1. Six-hour interval: Checks do NOT query network if < 6 hours have elapsed',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fiveHoursAgo = now - const Duration(hours: 5).inMilliseconds;

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': fiveHoursAgo,
        'last_update_check_yt_dlp': fiveHoursAgo,
        'last_update_check_yt_dlp_ejs': fiveHoursAgo,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      // Create core module dirs to avoid missing module auto-fetch
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

      expect(controller.hasPendingChecks, isFalse);
      expect(fakeGithub.fetchCallCount, equals(0));
    });

    test(
        '2. Cache rehydration: Cached discovered version restores updateAvailable state without network',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final twoHoursAgo = now - const Duration(hours: 2).inMilliseconds;

      final cachedAppUpdate = UpdateInfo(
        version: '1.2.0',
        downloadUrl: 'https://example.com/app.apk',
        changelog: 'New features',
        type: ComponentType.app,
      );

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': twoHoursAgo,
        'last_update_check_yt_dlp': twoHoursAgo,
        'last_update_check_yt_dlp_ejs': twoHoursAgo,
        'discovered_version_app': '1.2.0',
        'discovered_info_app': jsonEncode(cachedAppUpdate.toJson()),
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

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

      expect(controller.hasAvailableUpdates, isTrue);
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.app).pendingUpdate?.version,
          equals('1.2.0'));
      expect(fakeGithub.fetchCallCount, equals(0));
    });

    test('3. Six-hour expiration: Check queries network when >= 6 hours elapsed',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sevenHoursAgo = now - const Duration(hours: 7).inMilliseconds;

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': sevenHoursAgo,
        'last_update_check_yt_dlp': sevenHoursAgo,
        'last_update_check_yt_dlp_ejs': sevenHoursAgo,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      Directory('${tempDir.path}/core_modules/yt_dlp')
          .createSync(recursive: true);
      File('${tempDir.path}/core_modules/yt_dlp/main.py')
          .writeAsStringSync('code');
      Directory('${tempDir.path}/core_modules/yt_dlp_ejs')
          .createSync(recursive: true);
      File('${tempDir.path}/core_modules/yt_dlp_ejs/main.py')
          .writeAsStringSync('code');

      fakeGithub.appUpdate = UpdateInfo(
        version: '1.5.0',
        downloadUrl: 'https://example.com/app.apk',
        changelog: 'Major update',
        type: ComponentType.app,
      );

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fakeGithub.fetchCallCount, greaterThan(0));
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.updateAvailable));
    });

    test(
        '4. Independent manual check: Manual check updates only targeted component timestamp',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final initialTime = now - const Duration(hours: 3).inMilliseconds;

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': initialTime,
        'last_update_check_yt_dlp': initialTime,
        'last_update_check_yt_dlp_ejs': initialTime,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      Directory('${tempDir.path}/core_modules/yt_dlp')
          .createSync(recursive: true);
      File('${tempDir.path}/core_modules/yt_dlp/main.py')
          .writeAsStringSync('code');
      Directory('${tempDir.path}/core_modules/yt_dlp_ejs')
          .createSync(recursive: true);
      File('${tempDir.path}/core_modules/yt_dlp_ejs/main.py')
          .writeAsStringSync('code');

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);

      // Perform manual check ONLY for ytDlp
      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.ytDlp,
      );

      final appCheck = prefs.getInt('last_update_check_app');
      final ytDlpCheck = prefs.getInt('last_update_check_yt_dlp');
      final ejsCheck = prefs.getInt('last_update_check_yt_dlp_ejs');

      expect(appCheck, equals(initialTime));
      expect(ejsCheck, equals(initialTime));
      expect(ytDlpCheck, greaterThanOrEqualTo(now));
    });

    test('5. Corrupted cache JSON recovers gracefully without throwing',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final twoHoursAgo = now - const Duration(hours: 2).inMilliseconds;

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': twoHoursAgo,
        'discovered_version_app': '1.2.0',
        'discovered_info_app': '{ corrupt json ...',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        () => UpdateController(fakeGithub, fakeSystem, prefs),
        returnsNormally,
      );
    });

    test('6. UpdateInfo JSON serialization round-trip preservation', () {
      final original = UpdateInfo(
        version: '2026.08.22',
        downloadUrl: 'https://example.com/asset.tar.gz',
        sumsUrl: 'https://example.com/sums',
        sigUrl: 'https://example.com/sums.sig',
        changelog: 'Changelog details',
        type: ComponentType.ytDlp,
      );

      final jsonMap = original.toJson();
      final restored = UpdateInfo.fromJson(jsonMap);

      expect(restored.version, equals(original.version));
      expect(restored.downloadUrl, equals(original.downloadUrl));
      expect(restored.sumsUrl, equals(original.sumsUrl));
      expect(restored.sigUrl, equals(original.sigUrl));
      expect(restored.changelog, equals(original.changelog));
      expect(restored.type, equals(original.type));
      expect(restored.requiresPgpValidation, isTrue);

      final jsonString = original.toJsonString();
      final fromStr = UpdateInfo.fromJsonString(jsonString);
      expect(fromStr.version, equals(original.version));
      expect(fromStr.type, equals(ComponentType.ytDlp));
    });
  });
}
