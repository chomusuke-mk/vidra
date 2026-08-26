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

class EmpiricalFakeSystemController extends ChangeNotifier
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

class NetworkAuditingGithubClient implements GithubClient {
  int fetchCallCount = 0;
  final List<String> requestedRepos = [];
  final List<int> callTimestamps = [];
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
    callTimestamps.add(DateTime.now().millisecondsSinceEpoch);
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
  late EmpiricalFakeSystemController fakeSystem;
  late NetworkAuditingGithubClient fakeGithub;

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
    PackageInfo.setMockInitialValues(
      appName: 'Vidra',
      packageName: 'com.vidra.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    tempDir = Directory.systemTemp.createTempSync('challenger2_empirical_');
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationSupportDirectory') {
        return tempDir.path;
      }
      return null;
    });

    fakeSystem = EmpiricalFakeSystemController();
    fakeGithub = NetworkAuditingGithubClient();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  void installMockModule(String moduleName, String version) {
    final moduleDir = Directory('${tempDir.path}/core_modules/$moduleName');
    moduleDir.createSync(recursive: true);
    File('${moduleDir.path}/main.py').writeAsStringSync('print("ok")');
  }

  group('Challenger 2 Empirical Verification: Isolation & Timing Guarantees', () {
    test(
        'E1. Strict Isolation: App version upgrade triggers EXACTLY 1 network call for App, zero calls for yt-dlp & yt-dlp-ejs (< 6h elapsed)',
        () async {
      // Platform upgraded to 2.0.0
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '2.0.0',
        buildNumber: '2',
        buildSignature: '',
      );

      installMockModule('yt_dlp', '2026.01.01');
      installMockModule('yt_dlp_ejs', '1.0.0');

      final now = DateTime.now().millisecondsSinceEpoch;
      final recentCheck = now - const Duration(hours: 1).inMilliseconds;

      final cachedApp = UpdateInfo(
        version: '2.0.0',
        downloadUrl: 'https://example.com/stale-app.apk',
        changelog: 'Stale cached',
      );
      final cachedYtDlp = UpdateInfo(
        version: '2026.02.01',
        downloadUrl: 'https://example.com/ytdlp.tar.gz',
        changelog: 'New yt-dlp cached',
      );
      final cachedEjs = UpdateInfo(
        version: '1.1.0',
        downloadUrl: 'https://example.com/ejs.whl',
        changelog: 'New EJS cached',
      );

      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0', // Stored was 1.0.0 -> trigger version change
        'last_update_check_app': recentCheck,
        'discovered_version_app': '2.0.0',
        'discovered_info_app': jsonEncode(cachedApp.toJson()),

        'version_yt_dlp': '2026.01.01',
        'last_update_check_yt_dlp': recentCheck,
        'discovered_version_yt_dlp': '2026.02.01',
        'discovered_info_yt_dlp': jsonEncode(cachedYtDlp.toJson()),

        'version_yt_dlp_ejs': '1.0.0',
        'last_update_check_yt_dlp_ejs': recentCheck,
        'discovered_version_yt_dlp_ejs': '1.1.0',
        'discovered_info_yt_dlp_ejs': jsonEncode(cachedEjs.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();

      fakeGithub.appUpdate = UpdateInfo(
        version: '2.5.0',
        downloadUrl: 'https://example.com/vidra-2.5.0.apk',
        changelog: 'Fresh 2.5.0 release',
      );

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Network verification: Exactly 1 call, only for Vidra App
      expect(fakeGithub.fetchCallCount, equals(1));
      expect(fakeGithub.requestedRepos, equals(['chomusuke-mk/vidra']));

      // Module last check timestamps MUST NOT be altered
      expect(prefs.getInt('last_update_check_yt_dlp'), equals(recentCheck));
      expect(prefs.getInt('last_update_check_yt_dlp_ejs'), equals(recentCheck));

      // App last check timestamp MUST be updated to now
      expect(prefs.getInt('last_update_check_app'), greaterThanOrEqualTo(now));

      // Preferences version_app updated to new 2.0.0
      expect(prefs.getString('version_app'), equals('2.0.0'));

      // App state is updateAvailable with new pendingUpdate 2.5.0
      expect(controller.getState(ComponentType.app).status, equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.app).pendingUpdate?.version, equals('2.5.0'));

      // yt-dlp & yt-dlp-ejs state rehydrated from cache without network
      expect(controller.getState(ComponentType.ytDlp).status, equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.ytDlp).pendingUpdate?.version, equals('2026.02.01'));
      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.ytDlpEjs).pendingUpdate?.version, equals('1.1.0'));
    });

    test(
        'E2. Absolute Zero Network Requests: App version unchanged and elapsed < 6h produces 0 network calls',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      installMockModule('yt_dlp', '2026.01.01');
      installMockModule('yt_dlp_ejs', '1.0.0');

      final now = DateTime.now().millisecondsSinceEpoch;
      // 5 hours and 55 minutes ago (< 6h)
      final fiveHoursAgo = now - const Duration(hours: 5, minutes: 55).inMilliseconds;

      final cachedApp = UpdateInfo(
        version: '1.2.0',
        downloadUrl: 'https://example.com/app-1.2.0.apk',
        changelog: 'Pending app update',
      );

      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0', // Unchanged
        'last_update_check_app': fiveHoursAgo,
        'discovered_version_app': '1.2.0',
        'discovered_info_app': jsonEncode(cachedApp.toJson()),

        'version_yt_dlp': '2026.01.01',
        'last_update_check_yt_dlp': fiveHoursAgo,

        'version_yt_dlp_ejs': '1.0.0',
        'last_update_check_yt_dlp_ejs': fiveHoursAgo,
      });
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // ABSOLUTE ZERO NETWORK CALLS
      expect(fakeGithub.fetchCallCount, equals(0));
      expect(fakeGithub.requestedRepos.isEmpty, isTrue);

      // Timestamps must remain exactly 5h 55m ago
      expect(prefs.getInt('last_update_check_app'), equals(fiveHoursAgo));
      expect(prefs.getInt('last_update_check_yt_dlp'), equals(fiveHoursAgo));
      expect(prefs.getInt('last_update_check_yt_dlp_ejs'), equals(fiveHoursAgo));

      // App rehydrated cached updateAvailable
      expect(controller.getState(ComponentType.app).status, equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.app).pendingUpdate?.version, equals('1.2.0'));
      expect(controller.getState(ComponentType.ytDlp).status, equals(ComponentStatus.upToDate));
      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.upToDate));
    });

    test(
        'E3. Selective Mixed Timestamps: Unchanged app (< 6h), Expired yt-dlp (> 6h), Unexpired yt-dlp-ejs (< 6h)',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      installMockModule('yt_dlp', '2026.01.01');
      installMockModule('yt_dlp_ejs', '1.0.0');

      final now = DateTime.now().millisecondsSinceEpoch;
      final twoHoursAgo = now - const Duration(hours: 2).inMilliseconds;
      final eightHoursAgo = now - const Duration(hours: 8).inMilliseconds;

      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0',
        'last_update_check_app': twoHoursAgo, // < 6h -> No check

        'version_yt_dlp': '2026.01.01',
        'last_update_check_yt_dlp': eightHoursAgo, // > 6h -> Check required!
        'channel_ytdlp': 'nightly',

        'version_yt_dlp_ejs': '1.0.0',
        'last_update_check_yt_dlp_ejs': twoHoursAgo, // < 6h -> No check
      });
      final prefs = await SharedPreferences.getInstance();

      fakeGithub.ytDlpUpdate = UpdateInfo(
        version: '2026.03.01',
        downloadUrl: 'https://example.com/yt-dlp.tar.gz',
        changelog: 'New nightly',
      );

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Network verification: Exactly 1 call, ONLY for yt-dlp nightly
      expect(fakeGithub.fetchCallCount, equals(1));
      expect(fakeGithub.requestedRepos, equals(['yt-dlp/yt-dlp-nightly-builds']));

      // Only yt-dlp check timestamp updated
      expect(prefs.getInt('last_update_check_app'), equals(twoHoursAgo));
      expect(prefs.getInt('last_update_check_yt_dlp_ejs'), equals(twoHoursAgo));
      expect(prefs.getInt('last_update_check_yt_dlp'), greaterThanOrEqualTo(now));

      expect(controller.getState(ComponentType.ytDlp).status, equals(ComponentStatus.updateAvailable));
      expect(controller.getState(ComponentType.app).status, equals(ComponentStatus.upToDate));
      expect(controller.getState(ComponentType.ytDlpEjs).status, equals(ComponentStatus.upToDate));
    });

    test(
        'E4. App Version Bump + Stale Downgrade Cached Release: Cleans discovery keys and marks upToDate',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '2.0.0',
        buildNumber: '2',
        buildSignature: '',
      );

      installMockModule('yt_dlp', '2026.01.01');
      installMockModule('yt_dlp_ejs', '1.0.0');

      final now = DateTime.now().millisecondsSinceEpoch;
      final recentCheck = now - const Duration(minutes: 30).inMilliseconds;

      final staleInfo = UpdateInfo(
        version: '1.9.0',
        downloadUrl: 'https://example.com/old.apk',
        changelog: 'Older version',
      );

      SharedPreferences.setMockInitialValues({
        'version_app': '1.8.0', // Previous was 1.8.0, cached had 1.9.0, now platform is 2.0.0
        'last_update_check_app': recentCheck,
        'discovered_version_app': '1.9.0',
        'discovered_info_app': jsonEncode(staleInfo.toJson()),

        'version_yt_dlp': '2026.01.01',
        'last_update_check_yt_dlp': recentCheck,

        'version_yt_dlp_ejs': '1.0.0',
        'last_update_check_yt_dlp_ejs': recentCheck,
      });
      final prefs = await SharedPreferences.getInstance();

      // Remote has 2.0.0 (same as installed)
      fakeGithub.appUpdate = UpdateInfo(
        version: '2.0.0',
        downloadUrl: 'https://example.com/vidra-2.0.0.apk',
        changelog: 'Same as installed',
      );

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fakeGithub.fetchCallCount, equals(1));
      expect(fakeGithub.requestedRepos, equals(['chomusuke-mk/vidra']));

      // Stale cache cleared
      expect(prefs.getString('discovered_version_app'), isNull);
      expect(prefs.getString('discovered_info_app'), isNull);
      expect(prefs.getString('version_app'), equals('2.0.0'));
      expect(controller.getState(ComponentType.app).status, equals(ComponentStatus.upToDate));
      expect(controller.getState(ComponentType.app).pendingUpdate, isNull);
    });

    test(
        'E5. Semver Build Metadata & Prerelease Transition: triggers version change check',
        () async {
      // Transition from 1.0.0-beta.1 to 1.0.0
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '1.0.0',
        buildNumber: '10',
        buildSignature: '',
      );

      installMockModule('yt_dlp', '2026.01.01');
      installMockModule('yt_dlp_ejs', '1.0.0');

      final now = DateTime.now().millisecondsSinceEpoch;
      final recent = now - const Duration(hours: 1).inMilliseconds;

      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0-beta.1',
        'last_update_check_app': recent,
        'version_yt_dlp': '2026.01.01',
        'last_update_check_yt_dlp': recent,
        'version_yt_dlp_ejs': '1.0.0',
        'last_update_check_yt_dlp_ejs': recent,
      });
      final prefs = await SharedPreferences.getInstance();

      fakeGithub.appUpdate = UpdateInfo(
        version: '1.0.0',
        downloadUrl: 'https://example.com/app.apk',
        changelog: 'Current',
      );

      final controller = UpdateController(fakeGithub, fakeSystem, prefs);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fakeGithub.fetchCallCount, equals(1));
      expect(fakeGithub.requestedRepos, equals(['chomusuke-mk/vidra']));
      expect(prefs.getString('version_app'), equals('1.0.0'));
      expect(controller.getState(ComponentType.app).status, equals(ComponentStatus.upToDate));
    });

    test(
        'E6. Performance Benchmark: 50 consecutive inits with cached state execute within 1000ms total and zero network calls',
        () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vidra',
        packageName: 'com.vidra.app',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      installMockModule('yt_dlp', '2026.01.01');
      installMockModule('yt_dlp_ejs', '1.0.0');

      final now = DateTime.now().millisecondsSinceEpoch;
      final oneHourAgo = now - const Duration(hours: 1).inMilliseconds;

      SharedPreferences.setMockInitialValues({
        'version_app': '1.0.0',
        'last_update_check_app': oneHourAgo,
        'version_yt_dlp': '2026.01.01',
        'last_update_check_yt_dlp': oneHourAgo,
        'version_yt_dlp_ejs': '1.0.0',
        'last_update_check_yt_dlp_ejs': oneHourAgo,
      });
      final prefs = await SharedPreferences.getInstance();

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 50; i++) {
        final ctrl = UpdateController(fakeGithub, fakeSystem, prefs);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(ctrl.getState(ComponentType.app).status, equals(ComponentStatus.upToDate));
      }
      stopwatch.stop();

      expect(fakeGithub.fetchCallCount, equals(0), reason: 'Zero network calls should occur across all 50 inits');
      expect(stopwatch.elapsedMilliseconds, lessThan(1000), reason: '50 inits should be lightning fast');
    });
  });
}
