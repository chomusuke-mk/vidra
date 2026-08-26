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

class MockSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  @override
  SystemState get state => SystemState.ready;
  @override
  int? get backendPort => 5000;
  @override
  String? get backendToken => 'mock_token';
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
  UpdateInfo? appUpdate;
  UpdateInfo? ytDlpUpdate;
  UpdateInfo? ytDlpEjsUpdate;

  bool shouldSimulateNetworkError = false;

  @override
  Future<UpdateInfo?> getLatestReleaseInfo({
    required String repo,
    required List<RegExp> assetRegex,
  }) async {
    fetchCallCount++;
    requestedRepos.add(repo);
    if (shouldSimulateNetworkError) {
      // GithubClient contract returns null on any network error (SocketException, 404, etc.)
      return null;
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
  }) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MockSystemController mockSystem;
  late MockGithubClient mockGithub;

  void mockInstalledModules(Directory baseDir) {
    Directory('${baseDir.path}/core_modules/yt_dlp')
        .createSync(recursive: true);
    File('${baseDir.path}/core_modules/yt_dlp/main.py')
        .writeAsStringSync('# module yt_dlp');
    Directory('${baseDir.path}/core_modules/yt_dlp_ejs')
        .createSync(recursive: true);
    File('${baseDir.path}/core_modules/yt_dlp_ejs/main.py')
        .writeAsStringSync('# module yt_dlp_ejs');
  }

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Vidra',
      packageName: 'com.vidra.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    tempDir = Directory.systemTemp.createTempSync('challenger_upgrade_stress_');
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (MethodCall methodCall) async {
      return tempDir.path;
    });

    mockSystem = MockSystemController();
    mockGithub = MockGithubClient();
    mockInstalledModules(tempDir);
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

  group('Adversarial Suite 1: Multi-Hop Version Upgrade & Downgrade Transitions', () {
    test(
        '1.1 Successive multi-step upgrades (1.0.0 -> 1.1.0 -> 1.1.0 -> 1.2.0) preserve cache discipline and bypass appropriately',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final recent = now - const Duration(minutes: 30).inMilliseconds;

      // STEP 1: App starts at 1.0.0 (Fresh)
      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0',
        'last_update_check_app': recent,
        'last_update_check_yt_dlp': recent,
        'last_update_check_yt_dlp_ejs': recent,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      var prefs = await SharedPreferences.getInstance();

      var controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(mockGithub.fetchCallCount, equals(0),
          reason: 'No network check because 1.0.0 version is unchanged and elapsed < 6h');
      expect(controller.getState(ComponentType.app).version, equals('1.0.0'));
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));

      // STEP 2: Upgrade to 1.1.0 (First upgrade)
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '1.1.0',
        buildNumber: '2',
        buildSignature: '',
      );
      // Simulate that 1.0.0 discovered 1.1.0 earlier
      await prefs.setString('discovered_version_app', '1.1.0');
      await prefs.setString(
        'discovered_info_app',
        jsonEncode(UpdateInfo(
          version: '1.1.0',
          downloadUrl: 'https://example.com/v1.1.0.apk',
          changelog: 'v1.1.0 notes',
        ).toJson()),
      );

      mockGithub.appUpdate = UpdateInfo(
        version: '1.1.0',
        downloadUrl: 'https://example.com/v1.1.0.apk',
        changelog: 'v1.1.0 notes',
      );

      mockGithub.fetchCallCount = 0;
      mockGithub.requestedRepos.clear();

      controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(mockGithub.fetchCallCount, equals(1),
          reason: 'Immediate app check triggered due to version upgrade');
      expect(prefs.getString('version_app'), equals('1.1.0'));
      // Since remote is 1.1.0 and current is 1.1.0, status is upToDate
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
      expect(prefs.getString('discovered_version_app'), isNull);
      expect(prefs.getString('discovered_info_app'), isNull);

      // STEP 3: Second launch at 1.1.0 within 10 minutes (Unchanged version)
      mockGithub.fetchCallCount = 0;
      mockGithub.requestedRepos.clear();

      controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(mockGithub.fetchCallCount, equals(0),
          reason: 'Version 1.1.0 unchanged and < 6h, no network query');
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));

      // STEP 4: Upgrade to 1.2.0 (Second upgrade)
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '1.2.0',
        buildNumber: '3',
        buildSignature: '',
      );

      mockGithub.appUpdate = UpdateInfo(
        version: '1.3.0',
        downloadUrl: 'https://example.com/v1.3.0.apk',
        changelog: 'v1.3.0 notes',
      );

      mockGithub.fetchCallCount = 0;
      mockGithub.requestedRepos.clear();

      controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(mockGithub.fetchCallCount, equals(1));
      expect(prefs.getString('version_app'), equals('1.2.0'));
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.app).pendingUpdate?.version,
          equals('1.3.0'));
    });

    test(
        '1.2 Downgrade scenario (2.0.0 -> 1.9.0): Detects version shift, clears stale discovery, and queries remote immediately',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final recent = now - const Duration(hours: 1).inMilliseconds;

      // App was at 2.0.0, user sideloads/downgrades to 1.9.0
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '1.9.0',
        buildNumber: '9',
        buildSignature: '',
      );

      final staleCacheFrom200 = UpdateInfo(
        version: '2.1.0',
        downloadUrl: 'https://example.com/2.1.0.apk',
        changelog: 'Notes 2.1.0',
      );

      SharedPreferences.setMockInitialValues({
        'version_app': '2.0.0', // Stored previous version was higher
        'last_update_check_app': recent,
        'discovered_version_app': '2.1.0',
        'discovered_info_app': jsonEncode(staleCacheFrom200.toJson()),
        'last_update_check_yt_dlp': recent,
        'last_update_check_yt_dlp_ejs': recent,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      // Remote release is 2.0.0
      mockGithub.appUpdate = UpdateInfo(
        version: '2.0.0',
        downloadUrl: 'https://example.com/2.0.0.apk',
        changelog: 'Notes 2.0.0',
      );

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(mockGithub.fetchCallCount, equals(1));
      expect(prefs.getString('version_app'), equals('1.9.0'));
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.app).pendingUpdate?.version,
          equals('2.0.0'));
    });
  });

  group('Adversarial Suite 2: Clock Skews and Timestamp Drift', () {
    test(
        '2.1 Backward clock skew / negative elapsed time (< 0): Rehydrates cache safely without crashing when version unchanged',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Clock in prefs is in the future (user rolled clock back)
      final futureTimestamp = now + const Duration(days: 30).inMilliseconds;

      final cachedUpdate = UpdateInfo(
        version: '1.5.0',
        downloadUrl: 'https://example.com/1.5.0.apk',
        changelog: 'Update',
      );

      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0',
        'last_update_check_app': futureTimestamp,
        'discovered_version_app': '1.5.0',
        'discovered_info_app': jsonEncode(cachedUpdate.toJson()),
        'last_update_check_yt_dlp': futureTimestamp,
        'last_update_check_yt_dlp_ejs': futureTimestamp,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Negative elapsed < checkIntervalMs -> should rehydrate without crash
      expect(mockGithub.fetchCallCount, equals(0));
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.app).pendingUpdate?.version,
          equals('1.5.0'));
    });

    test(
        '2.2 Backward clock skew with version upgrade: Bypasses negative elapsed and forces immediate check, resetting last_check',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '1.1.0',
        buildNumber: '2',
        buildSignature: '',
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final futureTimestamp = now + const Duration(days: 365).inMilliseconds;

      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0', // Version changed from 1.0.0 to 1.1.0
        'last_update_check_app': futureTimestamp, // Future timestamp!
        'last_update_check_yt_dlp': futureTimestamp,
        'last_update_check_yt_dlp_ejs': futureTimestamp,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      mockGithub.appUpdate = UpdateInfo(
        version: '1.1.0',
        downloadUrl: 'https://example.com/1.1.0.apk',
        changelog: '1.1.0',
      );

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Network check MUST be triggered regardless of the future timestamp
      expect(mockGithub.fetchCallCount, equals(1));
      expect(prefs.getString('version_app'), equals('1.1.0'));
      expect(controller.getState(ComponentType.app).status, equals(ComponentStatus.upToDate));
      // last_update_check_app should now be reset to current timestamp (not future)
      final newLastCheck = prefs.getInt('last_update_check_app')!;
      expect(newLastCheck, greaterThanOrEqualTo(now));
      expect(newLastCheck, lessThan(futureTimestamp));
    });

    test(
        '2.3 Extreme timestamp values (0, negative, very large int): Handled without integer overflow or exceptions',
        () async {
      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0',
        'last_update_check_app': -999999999,
        'last_update_check_yt_dlp': 0,
        'last_update_check_yt_dlp_ejs': 9007199254740991, // 2^53 - 1
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        () => UpdateController(mockGithub, mockSystem, prefs),
        returnsNormally,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
  });

  group('Adversarial Suite 3: Null, Empty, and Corrupted SharedPreferences Keys', () {
    test(
        '3.1 Empty string version_app (""): Does NOT trigger false positive upgrade loop and saves baseline',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'version_app': '', // Empty string
        'last_update_check_app': now,
        'last_update_check_yt_dlp': now,
        'last_update_check_yt_dlp_ejs': now,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Empty storedAppVersion should NOT be treated as a version change (isAppVersionChanged requires isNotEmpty)
      expect(mockGithub.fetchCallCount, equals(0));
      // Stored version should be properly populated with '1.0.0'
      expect(prefs.getString('version_app'), equals('1.0.0'));
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
    });

    test(
        '3.2 Corrupted JSON in discovered_info_app during version upgrade is safely purged and does not throw',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '1.2.0',
        buildNumber: '2',
        buildSignature: '',
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0',
        'last_update_check_app': now,
        'last_update_check_yt_dlp': now,
        'last_update_check_yt_dlp_ejs': now,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
        'discovered_version_app': 'MALFORMED',
        'discovered_info_app': '{"corrupt_garbage_without_closing_brace": [1, 2, ',
      });
      final prefs = await SharedPreferences.getInstance();

      mockGithub.appUpdate = UpdateInfo(
        version: '1.2.0',
        downloadUrl: 'https://example.com/1.2.0.apk',
        changelog: 'Clean',
      );

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(mockGithub.fetchCallCount, equals(1));
      expect(prefs.getString('discovered_info_app'), isNull);
      expect(prefs.getString('discovered_version_app'), isNull);
      expect(prefs.getString('version_app'), equals('1.2.0'));
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
    });

    test(
        '3.3 Corrupted JSON in discovered_info_app during cache rehydration falls back to upToDate gracefully',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0',
        'last_update_check_app': now,
        'last_update_check_yt_dlp': now,
        'last_update_check_yt_dlp_ejs': now,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
        'discovered_version_app': '1.5.0',
        'discovered_info_app': '### NOT A JSON OBJECT ###',
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(mockGithub.fetchCallCount, equals(0));
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
    });

    test(
        '3.4 All SharedPreferences keys missing (cold boot): Sets version baseline and initializes cleanly',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(prefs.getString('version_app'), equals('1.0.0'));
      expect(controller.getState(ComponentType.app).version, equals('1.0.0'));
    });
  });

  group('Adversarial Suite 4: Network Failures during Forced Immediate Check', () {
    test(
        '4.1 Network failure (null/timeout/offline) during immediate check upon upgrade: Records version_app, evicts stale cache, sets error status cleanly',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '2.0.0',
        buildNumber: '2',
        buildSignature: '',
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final staleCache = UpdateInfo(
        version: '1.9.0',
        downloadUrl: 'https://example.com/old.apk',
        changelog: 'Old',
      );

      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0',
        'last_update_check_app': now,
        'discovered_version_app': '1.9.0',
        'discovered_info_app': jsonEncode(staleCache.toJson()),
        'last_update_check_yt_dlp': now,
        'last_update_check_yt_dlp_ejs': now,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      // Simulate network error (getLatestReleaseInfo returns null on error)
      mockGithub.shouldSimulateNetworkError = true;

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Network check was attempted
      expect(mockGithub.fetchCallCount, equals(1));

      // Stale cache must be evicted BEFORE the network call
      expect(prefs.getString('discovered_version_app'), isNull);
      expect(prefs.getString('discovered_info_app'), isNull);

      // Baseline version_app must be updated to 2.0.0 BEFORE the network call
      expect(prefs.getString('version_app'), equals('2.0.0'));

      // App state transitioned to error, avoiding false positive update badge
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.error));
      expect(controller.getState(ComponentType.app).pendingUpdate, isNull);

      // RECOVERY: When network is restored and manual check runs
      mockGithub.shouldSimulateNetworkError = false;
      mockGithub.appUpdate = UpdateInfo(
        version: '2.0.0',
        downloadUrl: 'https://example.com/2.0.0.apk',
        changelog: 'Up to date',
      );

      await controller.checkForUpdates(manualCall: true, specificType: ComponentType.app);
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
    });

    test(
        '4.2 GitHub API returns null (404/500/rate limit) during immediate upgrade check: Handled gracefully without crash',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '2.0.0',
        buildNumber: '2',
        buildSignature: '',
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0',
        'last_update_check_app': now,
        'last_update_check_yt_dlp': now,
        'last_update_check_yt_dlp_ejs': now,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
        'discovered_version_app': '1.5.0',
        'discovered_info_app': jsonEncode(UpdateInfo(
          version: '1.5.0',
          downloadUrl: 'https://example.com/1.5.0.apk',
          changelog: '1.5.0',
        ).toJson()),
      });
      final prefs = await SharedPreferences.getInstance();

      // Return null from GitHub client
      mockGithub.appUpdate = null;

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(mockGithub.fetchCallCount, equals(1));
      // Stale cache cleared
      expect(prefs.getString('discovered_version_app'), isNull);
      expect(prefs.getString('discovered_info_app'), isNull);
      expect(prefs.getString('version_app'), equals('2.0.0'));
      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.error));
    });
  });

  group('Adversarial Suite 5: Component Isolation and Selective Bypassing', () {
    test(
        '5.1 App version upgrade triggers network check ONLY for App; Core modules with elapsed < 6h stay cached',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '3.0.0',
        buildNumber: '3',
        buildSignature: '',
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final recent = now - const Duration(hours: 2).inMilliseconds;

      final cachedYtDlp = UpdateInfo(
        version: '2026.09.01',
        downloadUrl: 'https://example.com/ytdlp.tar.gz',
        changelog: 'yt-dlp new',
      );

      SharedPreferences.setMockInitialValues({
        'version_app': '2.0.0',
        'last_update_check_app': recent,
        'last_update_check_yt_dlp': recent,
        'last_update_check_yt_dlp_ejs': recent,
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
        'discovered_version_yt_dlp': '2026.09.01',
        'discovered_info_yt_dlp': jsonEncode(cachedYtDlp.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();

      mockGithub.appUpdate = UpdateInfo(
        version: '3.0.0',
        downloadUrl: 'https://example.com/3.0.0.apk',
        changelog: '3.0.0',
      );
      mockGithub.ytDlpUpdate = UpdateInfo(
        version: '2026.10.01',
        downloadUrl: 'https://example.com/ytdlp_10.tar.gz',
        changelog: 'yt-dlp newer',
      );

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Network check strictly only 1 call for app repo
      expect(mockGithub.fetchCallCount, equals(1));
      expect(mockGithub.requestedRepos.length, equals(1));
      expect(mockGithub.requestedRepos.first, contains('vidra'));

      // yt-dlp discovery cache preserved and rehydrated
      expect(controller.getState(ComponentType.ytDlp).status,
          equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.ytDlp).pendingUpdate?.version,
          equals('2026.09.01'));
      expect(prefs.getString('discovered_version_yt_dlp'), equals('2026.09.01'));
    });

    test(
        '5.2 App version upgrade with expired yt-dlp check (>= 6h) checks both components properly without interference',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '3.0.0',
        buildNumber: '3',
        buildSignature: '',
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final recent = now - const Duration(hours: 1).inMilliseconds;
      final expired = now - const Duration(hours: 8).inMilliseconds;

      SharedPreferences.setMockInitialValues({
        'version_app': '2.0.0',
        'last_update_check_app': recent,
        'last_update_check_yt_dlp': expired, // Expired (>6h)
        'last_update_check_yt_dlp_ejs': recent, // Fresh (<6h)
        'version_yt_dlp': '2026.01.01',
        'version_yt_dlp_ejs': '1.0.0',
      });
      final prefs = await SharedPreferences.getInstance();

      mockGithub.appUpdate = UpdateInfo(
        version: '3.0.0',
        downloadUrl: 'https://example.com/3.0.0.apk',
        changelog: '3.0.0',
      );
      mockGithub.ytDlpUpdate = UpdateInfo(
        version: '2026.08.26',
        downloadUrl: 'https://example.com/ytdlp.tar.gz',
        changelog: 'ytdlp',
      );

      final controller = UpdateController(mockGithub, mockSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Network checks for app (due to version change) AND ytDlp (due to >6h elapsed)
      expect(mockGithub.fetchCallCount, equals(2));
      expect(mockGithub.requestedRepos.any((r) => r.contains('vidra')), isTrue);
      expect(mockGithub.requestedRepos.any((r) => r.contains('yt-dlp')), isTrue);
      expect(mockGithub.requestedRepos.any((r) => r.contains('ejs')), isFalse);

      expect(controller.getState(ComponentType.app).status,
          equals(ComponentStatus.upToDate));
      expect(controller.getState(ComponentType.ytDlp).status,
          equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.ytDlpEjs).status,
          equals(ComponentStatus.upToDate));
    });
  });
}
