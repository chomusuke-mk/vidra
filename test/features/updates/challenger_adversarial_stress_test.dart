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

//SUPERFIX - HERE APK IS OPENED
class MockSystemController extends ChangeNotifier
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

class MockGithubClient implements GithubClient {
  int fetchCallCount = 0;
  final List<String> requestedRepos = [];
  final List<String> requestedAssetNames = [];
  UpdateInfo? appUpdate;
  UpdateInfo? ytDlpUpdate;
  UpdateInfo? ytDlpEjsUpdate;

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

  bool shouldFailDownload = false;

  @override
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async {
    if (shouldFailDownload) return false;
    final file = File(savePath);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    file.writeAsStringSync('binary_data');
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MockSystemController mockSystem;
  late MockGithubClient mockGithub;

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
    tempDir = Directory.systemTemp.createTempSync('challenger_stress_test_');
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (MethodCall methodCall) async {
      return tempDir.path;
    });

    const MethodChannel openFileChannel = MethodChannel('open_filex');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(openFileChannel, (MethodCall methodCall) async {
      return {'type': 0, 'message': 'done'};
    });

    mockSystem = MockSystemController();
    mockGithub = MockGithubClient();
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

  void createFakeModules() {
    Directory('${tempDir.path}/core_modules/yt_dlp').createSync(recursive: true);
    File('${tempDir.path}/core_modules/yt_dlp/main.py').writeAsStringSync('code');
    Directory('${tempDir.path}/core_modules/yt_dlp_ejs').createSync(recursive: true);
    File('${tempDir.path}/core_modules/yt_dlp_ejs/main.py').writeAsStringSync('code');
  }

  group('Adversarial Stress Suite: Update Intervals (5h59m vs 6h00m vs 6h01m)', () {
    test('1.1 Boundary: 5h 59m elapsed (cache hit, 0 network requests, state restored)', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      // Exactly 5h 59m ago = 5*3600*1000 + 59*60*1000 = 21,540,000 ms
      const elapsed5h59m = (5 * 3600 + 59 * 60) * 1000;
      final checkTime = now - elapsed5h59m;

      final cachedApp = UpdateInfo(
        version: '1.5.0',
        downloadUrl: 'https://example.com/app.apk',
        changelog: 'Discovered earlier',
      );

      final cachedYtDlp = UpdateInfo(
        version: '2026.09.01',
        downloadUrl: 'https://example.com/ytdlp.tar.gz',
        changelog: 'yt-dlp update',
      );

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': checkTime,
        'last_update_check_yt_dlp': checkTime,
        'last_update_check_yt_dlp_ejs': checkTime,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
        'discovered_version_app': '1.5.0',
        'discovered_info_app': cachedApp.toJsonString(),
        'discovered_version_yt_dlp': '2026.09.01',
        'discovered_info_yt_dlp': cachedYtDlp.toJsonString(),
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockGithub.fetchCallCount, equals(0),
          reason: 'At 5h59m elapsed, no network requests should be triggered.');
      expect(controller.hasPendingChecks, isFalse);
      expect(controller.hasAvailableUpdates, isTrue);

      // Verify app state rehydrated from cache
      final appState = controller.getState(ComponentType.app);
      expect(appState.status, equals(ComponentStatus.updateAvailable));
      expect(appState.pendingUpdate?.version, equals('1.5.0'));
      expect(appState.version, equals('1.0.0'));

      // Verify ytDlp state rehydrated from cache
      final ytDlpState = controller.getState(ComponentType.ytDlp);
      expect(ytDlpState.status, equals(ComponentStatus.updateAvailable));
      expect(ytDlpState.pendingUpdate?.version, equals('2026.09.01'));

      // Verify ytDlpEjs has no pending update -> upToDate
      final ejsState = controller.getState(ComponentType.ytDlpEjs);
      expect(ejsState.status, equals(ComponentStatus.upToDate));
    });

    test('1.2 Boundary: 6h 00m exact elapsed (cache expired, network check triggered)', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      // Exactly 6 hours = 6 * 3600 * 1000 = 21,600,000 ms
      const elapsed6h = 6 * 3600 * 1000;
      final checkTime = now - elapsed6h;

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': checkTime,
        'last_update_check_yt_dlp': checkTime,
        'last_update_check_yt_dlp_ejs': checkTime,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      mockGithub.appUpdate = UpdateInfo(
        version: '1.6.0',
        downloadUrl: 'https://example.com/app.apk',
        changelog: '6h update',
      );

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockGithub.fetchCallCount, greaterThan(0),
          reason: 'At exactly 6h00m elapsed, network check must be performed.');
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.app).pendingUpdate?.version,
          equals('1.6.0'));
    });

    test('1.3 Boundary: 6h 01m elapsed (cache expired, network check triggered)', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      // 6h 01m = (6*3600 + 60) * 1000 = 21,660,000 ms
      const elapsed6h01m = (6 * 3600 + 60) * 1000;
      final checkTime = now - elapsed6h01m;

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': checkTime,
        'last_update_check_yt_dlp': checkTime,
        'last_update_check_yt_dlp_ejs': checkTime,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      mockGithub.ytDlpUpdate = UpdateInfo(
        version: '2026.10.01',
        downloadUrl: 'https://example.com/yt-dlp.tar.gz',
        changelog: 'Nightly fix',
      );

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockGithub.fetchCallCount, greaterThan(0));
      expect(controller.getState(ComponentType.ytDlp).status,
          equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.ytDlp).pendingUpdate?.version,
          equals('2026.10.01'));
      // Prefs should now have the newly discovered version
      expect(prefs.getString('discovered_version_yt_dlp'), equals('2026.10.01'));
    });

    test('1.4 Future Timestamp / Negative Elapsed (Clock roll-back resiliency)', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      // System clock was rolled back: last check recorded is 2 hours in the future
      final futureTime = now + (2 * 3600 * 1000);

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': futureTime,
        'last_update_check_yt_dlp': futureTime,
        'last_update_check_yt_dlp_ejs': futureTime,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Elapsed is negative (< checkIntervalMs), so no crash and no network calls
      expect(mockGithub.fetchCallCount, equals(0));
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
    });
  });

  group('Adversarial Stress Suite: Cache Rehydration & Malformed Payload Handling', () {
    test('2.1 Stale cache eviction: Discovered version matching current version is pruned', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      final recentTime = now - (1 * 3600 * 1000);

      // Discovered version is '1.0.0', which is identical to current PackageInfo version ('1.0.0')
      final staleInfo = UpdateInfo(
        version: '1.0.0',
        downloadUrl: 'https://example.com/app-1.0.0.apk',
        changelog: 'Already installed',
      );

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': recentTime,
        'last_update_check_yt_dlp': recentTime,
        'last_update_check_yt_dlp_ejs': recentTime,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
        'discovered_version_app': '1.0.0',
        'discovered_info_app': staleInfo.toJsonString(),
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Status should be upToDate, not updateAvailable
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
      expect(controller.hasAvailableUpdates, isFalse);

      // Stale cache keys must be removed from SharedPreferences
      expect(prefs.getString('discovered_version_app'), isNull);
      expect(prefs.getString('discovered_info_app'), isNull);
    });

    test('2.2 Corrupted JSON string payload does not crash and defaults to upToDate', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      final recentTime = now - (1 * 3600 * 1000);

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': recentTime,
        'discovered_version_app': '9.9.9',
        'discovered_info_app': '<<< INVALID_NOT_JSON_DATA >>>',
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
      expect(controller.hasAvailableUpdates, isFalse);
    });

    test('2.3 Missing fields in JSON payload handled safely', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      final recentTime = now - (1 * 3600 * 1000);

      // JSON missing version or type
      SharedPreferences.setMockInitialValues({
        'last_update_check_app': recentTime,
        'discovered_version_app': '9.9.9',
        'discovered_info_app': jsonEncode({'downloadUrl': 'https://example.com/app.apk'}),
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
    });

    test('2.4 Empty string in discovered_info_* ignored safely', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      final recentTime = now - (1 * 3600 * 1000);

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': recentTime,
        'discovered_version_app': '',
        'discovered_info_app': '',
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
    });
  });

  group('Adversarial Stress Suite: Independent Manual Check Timers', () {
    test('3.1 Manual check on ytDlp strictly updates ONLY ytDlp timestamp', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      final tApp = now - (4 * 3600 * 1000);
      final tYtDlp = now - (4 * 3600 * 1000);
      final tEjs = now - (4 * 3600 * 1000);

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': tApp,
        'last_update_check_yt_dlp': tYtDlp,
        'last_update_check_yt_dlp_ejs': tEjs,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      mockGithub.requestedRepos.clear();

      // Trigger manual check ONLY for ytDlp
      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.ytDlp,
      );

      final finalApp = prefs.getInt('last_update_check_app');
      final finalYtDlp = prefs.getInt('last_update_check_yt_dlp');
      final finalEjs = prefs.getInt('last_update_check_yt_dlp_ejs');

      expect(finalApp, equals(tApp), reason: 'App timestamp must be untouched');
      expect(finalEjs, equals(tEjs), reason: 'ytDlpEjs timestamp must be untouched');
      expect(finalYtDlp, greaterThanOrEqualTo(now), reason: 'ytDlp timestamp must be updated');
      expect(mockGithub.requestedRepos.any((r) => r.contains('yt-dlp') && !r.contains('ejs')), isTrue);
    });

    test('3.2 Manual check on ytDlpEjs strictly updates ONLY ytDlpEjs timestamp', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      final tApp = now - (4 * 3600 * 1000);
      final tYtDlp = now - (4 * 3600 * 1000);
      final tEjs = now - (4 * 3600 * 1000);

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': tApp,
        'last_update_check_yt_dlp': tYtDlp,
        'last_update_check_yt_dlp_ejs': tEjs,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      mockGithub.requestedRepos.clear();

      // Trigger manual check ONLY for ytDlpEjs
      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.ytDlpEjs,
      );

      final finalApp = prefs.getInt('last_update_check_app');
      final finalYtDlp = prefs.getInt('last_update_check_yt_dlp');
      final finalEjs = prefs.getInt('last_update_check_yt_dlp_ejs');

      expect(finalApp, equals(tApp), reason: 'App timestamp must be untouched');
      expect(finalYtDlp, equals(tYtDlp), reason: 'ytDlp timestamp must be untouched');
      expect(finalEjs, greaterThanOrEqualTo(now), reason: 'ytDlpEjs timestamp must be updated');
      expect(mockGithub.requestedRepos.any((r) => r.contains('ejs')), isTrue);
    });

    test('3.3 Manual check on app strictly updates ONLY app timestamp', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      final tApp = now - (4 * 3600 * 1000);
      final tYtDlp = now - (4 * 3600 * 1000);
      final tEjs = now - (4 * 3600 * 1000);

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': tApp,
        'last_update_check_yt_dlp': tYtDlp,
        'last_update_check_yt_dlp_ejs': tEjs,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      mockGithub.requestedRepos.clear();

      // Trigger manual check ONLY for app
      await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.app,
      );

      final finalApp = prefs.getInt('last_update_check_app');
      final finalYtDlp = prefs.getInt('last_update_check_yt_dlp');
      final finalEjs = prefs.getInt('last_update_check_yt_dlp_ejs');

      expect(finalApp, greaterThanOrEqualTo(now), reason: 'App timestamp must be updated');
      expect(finalYtDlp, equals(tYtDlp), reason: 'ytDlp timestamp must be untouched');
      expect(finalEjs, equals(tEjs), reason: 'ytDlpEjs timestamp must be untouched');
      expect(mockGithub.requestedRepos, equals(['chomusuke-mk/vidra']));
    });

    test('3.4 General check (specificType == null) updates ALL timestamps', () async {
      createFakeModules();
      final now = DateTime.now().millisecondsSinceEpoch;
      final tOld = now - (7 * 3600 * 1000);

      SharedPreferences.setMockInitialValues({
        'last_update_check_app': tOld,
        'last_update_check_yt_dlp': tOld,
        'last_update_check_yt_dlp_ejs': tOld,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      mockGithub.requestedRepos.clear();

      await controller.checkForUpdates(manualCall: true, specificType: null);

      expect(prefs.getInt('last_update_check_app'), greaterThanOrEqualTo(now));
      expect(prefs.getInt('last_update_check_yt_dlp'), greaterThanOrEqualTo(now));
      expect(prefs.getInt('last_update_check_yt_dlp_ejs'), greaterThanOrEqualTo(now));
      expect(mockGithub.requestedRepos.any((r) => r.contains('vidra')), isTrue);
      expect(mockGithub.requestedRepos.any((r) => r.contains('yt-dlp')), isTrue);
      expect(mockGithub.requestedRepos.any((r) => r.contains('ejs')), isTrue);
    });
  });

  group('Adversarial Stress Suite: Platform Resolvers & Packaging', () {
    test('4.1 Linux packaging resolver identifies DEB, AppImage, Snap', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = UpdateController(
        mockGithub,
        mockSystem,
        prefs,
      );

      final detected = controller.getLinuxPackageType();
      // On this host, SNAP_NAME is 'antigravity', not 'vidra', so it resolves to deb
      expect(detected, equals(LinuxPackageType.deb));
    });

    test('4.2 Linux app update checks version without requiring asset download', () async {
      createFakeModules();
      final prefs = await SharedPreferences.getInstance();
      mockGithub.appUpdate = UpdateInfo(
        version: '4.0.0',
        downloadUrl: '',
        changelog: 'New version for Linux',
      );
      final controller = UpdateController(mockGithub, mockSystem, prefs);

      mockGithub.requestedAssetNames.clear();
      final hasUpdate = await controller.checkForUpdates(
        manualCall: true,
        specificType: ComponentType.app,
      );

      expect(hasUpdate, isTrue);
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.updateAvailable));
      expect(mockGithub.requestedAssetNames, isEmpty,
          reason: 'Linux app updates validate version without searching for specific binary assets');
    });
  });

  group('Adversarial Stress Suite: App Version Accuracy & Installer Invocations', () {
    test('5.1 App version strictly reflects PackageInfo and does NOT mutate to pendingUpdate version', () async {
      createFakeModules();
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.getState(ComponentType.app).version, equals('1.0.0'));

      final pendingInfo = UpdateInfo(
        version: '3.0.0',
        downloadUrl: 'https://example.com/vidra-3.0.0.apk',
        changelog: 'Version 3.0.0',
      );

      await controller.downloadAndInstallInternal(
        ComponentType.app,
        pendingInfo,
      );

      // Regardless of OpenFilex execution, local state version MUST STILL be '1.0.0', NEVER '3.0.0'
      expect(controller.getState(ComponentType.app).version, equals('1.0.0'));
      expect(prefs.getString('version_app'), equals('1.0.0'));
    });

    test('5.2 Download failure sets ComponentStatus.error and maintains version 1.0.0', () async {
      createFakeModules();
      final prefs = await SharedPreferences.getInstance();

      mockGithub.shouldFailDownload = true;
      final failingController = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final pendingInfo = UpdateInfo(
        version: '4.0.0',
        downloadUrl: 'https://example.com/broken-download.apk',
        changelog: 'Download failure',
      );

      final result = await failingController.downloadAndInstallInternal(
        ComponentType.app,
        pendingInfo,
      );

      expect(result, isFalse);
      expect(failingController.getState(ComponentType.app).status, equals(ComponentStatus.error));
      expect(failingController.getState(ComponentType.app).version, equals('1.0.0'));
      mockGithub.shouldFailDownload = false;
    });
  });
}
