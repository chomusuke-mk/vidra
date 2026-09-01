import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/core/network/github_client.dart';
import 'package:vidra/core/security/pgp_verifier.dart';
import 'package:vidra/core/security/public_keys.dart';
import 'package:vidra/core/utils/archive_extractor.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/presentation/widgets/linux_deb_update_dialog.dart';
import 'package:vidra/features/updates/presentation/widgets/linux_appimage_update_dialog.dart';

enum ComponentStatus {
  upToDate,
  checking,
  updateAvailable,
  downloading,
  verifying,
  installing,
  error,
}

enum LinuxPackageType { deb, appImage, snap, unknown }

class UpdateState {
  final ComponentStatus status;
  final String version;
  final double progress;
  final UpdateInfo? pendingUpdate;

  UpdateState({
    required this.status,
    required this.version,
    this.progress = 0.0,
    this.pendingUpdate,
  });
}

class UpdateController extends ChangeNotifier {
  final GithubClient _github;
  final SystemController _system;
  final SharedPreferences _prefs;

  static const int checkIntervalMs = 6 * 60 * 60 * 1000; // 6 hours

  bool _isAutoDownloadingMissing = false;
  bool get isAutoDownloadingMissing => _isAutoDownloadingMissing;

  double _missingModulesProgress = 0.0;
  double get missingModulesProgress => _missingModulesProgress;

  bool _hasShownSessionUpdateBubble = false;
  bool get hasShownSessionUpdateBubble => _hasShownSessionUpdateBubble;

  void markSessionUpdateBubbleShown() {
    _hasShownSessionUpdateBubble = true;
    notifyListeners();
  }

  final Map<ComponentType, UpdateState> _states = {
    ComponentType.app: UpdateState(
      status: ComponentStatus.upToDate,
      version: 'Loading...',
    ),
    ComponentType.ytDlp: UpdateState(
      status: ComponentStatus.upToDate,
      version: 'Unknown',
    ),
    ComponentType.ytDlpEjs: UpdateState(
      status: ComponentStatus.upToDate,
      version: 'Unknown',
    ),
  };

  UpdateState getState(ComponentType type) => _states[type]!;

  static String _lastCheckKey(ComponentType type) => type.lastCheckKey;
  static String _discoveredVersionKey(ComponentType type) =>
      type.discoveredVersionKey;
  static String _discoveredInfoKey(ComponentType type) =>
      type.discoveredInfoKey;
  static String _versionKey(ComponentType type) => type.versionKey;

  bool get hasPendingChecks {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ComponentType.values.any((t) {
      final last = _prefs.getInt(t.lastCheckKey) ?? 0;
      return now - last > checkIntervalMs;
    });
  }

  bool get hasAvailableUpdates =>
      _states.values.any((s) => s.status == ComponentStatus.updateAvailable);

  bool get isCheckingUpdates =>
      _states.values.any((s) => s.status == ComponentStatus.checking);

  UpdateController(this._github, this._system, this._prefs) {
    _init();
  }

  Future<void> _init() async {
    await _loadLocalVersions();

    final currentAppVersion = _states[ComponentType.app]?.version ?? '';
    final storedAppVersion = _prefs.getString(_versionKey(ComponentType.app));
    final bool isAppVersionChanged = storedAppVersion != null &&
        storedAppVersion.isNotEmpty &&
        storedAppVersion != currentAppVersion;

    if (isAppVersionChanged) {
      await _prefs.remove(_discoveredVersionKey(ComponentType.app));
      await _prefs.remove(_discoveredInfoKey(ComponentType.app));
    }
    if (currentAppVersion.isNotEmpty &&
        currentAppVersion != 'Unknown' &&
        currentAppVersion != 'Loading...') {
      await _prefs.setString(_versionKey(ComponentType.app), currentAppVersion);
    }

    // Check for missing core modules on first launch / wiped storage
    final isYtDlpInstalled = await _isComponentInstalled(ComponentType.ytDlp);
    final isEjsInstalled = await _isComponentInstalled(ComponentType.ytDlpEjs);

    if (!isYtDlpInstalled || !isEjsInstalled) {
      await _autoDownloadMissingModules(
        missingYtDlp: !isYtDlpInstalled,
        missingEjs: !isEjsInstalled,
      );
    }

    // Now process normal update interval checks / cache rehydration
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final type in ComponentType.values) {
      final lastCheck = _prefs.getInt(_lastCheckKey(type)) ?? 0;
      final elapsed = now - lastCheck;

      if (type == ComponentType.app && isAppVersionChanged) {
        // Force immediate check bypassing 6-hour interval on app version change
        await checkForUpdates(manualCall: false, specificType: ComponentType.app);
      } else if (elapsed < checkIntervalMs) {
        // Cache rehydration without network calls
        _rehydrateCachedDiscovery(type);
      } else {
        // Check for updates without auto-downloading regular updates
        await checkForUpdates(manualCall: false, specificType: type);
      }
    }
  }

  void _rehydrateCachedDiscovery(ComponentType type) {
    final cachedInfoRaw = _prefs.getString(_discoveredInfoKey(type));
    if (cachedInfoRaw != null && cachedInfoRaw.isNotEmpty) {
      try {
        final cachedInfo = UpdateInfo.fromJsonString(cachedInfoRaw);
        final currentVersion = _states[type]?.version ?? '';
        if (cachedInfo.version.isNotEmpty && cachedInfo.version != currentVersion) {
          _setState(
            type,
            ComponentStatus.updateAvailable,
            pendingUpdate: cachedInfo,
          );
          return;
        } else {
          // Cached discovery matches current version; clean up stale cache
          _prefs.remove(_discoveredVersionKey(type));
          _prefs.remove(_discoveredInfoKey(type));
        }
      } catch (e) {
        debugPrint('Error rehydrating cached update for ${type.name}: $e');
      }
    }
    _setState(type, ComponentStatus.upToDate);
  }

  Future<void> retryMissingModulesDownload() async {
    final isYtDlpInstalled = await _isComponentInstalled(ComponentType.ytDlp);
    final isEjsInstalled = await _isComponentInstalled(ComponentType.ytDlpEjs);

    if (!isYtDlpInstalled || !isEjsInstalled) {
      await _autoDownloadMissingModules(
        missingYtDlp: !isYtDlpInstalled,
        missingEjs: !isEjsInstalled,
      );
    }
  }

  Future<void> _autoDownloadMissingModules({
    required bool missingYtDlp,
    required bool missingEjs,
  }) async {
    _isAutoDownloadingMissing = true;
    _missingModulesProgress = 0.0;
    notifyListeners();

    final missingList = <ComponentType>[];
    if (missingYtDlp) missingList.add(ComponentType.ytDlp);
    if (missingEjs) missingList.add(ComponentType.ytDlpEjs);

    int completed = 0;
    final total = missingList.length;

    try {
      for (final type in missingList) {
        String repo;
        List<RegExp> assetRegex;

        if (type == ComponentType.ytDlp) {
          final channel = _prefs.getString('channel_ytdlp') == 'stable'
              ? UpdateChannel.stable
              : UpdateChannel.nightly;
          repo = channel == UpdateChannel.nightly
              ? 'yt-dlp/yt-dlp-nightly-builds'
              : 'yt-dlp/yt-dlp';
          assetRegex = [RegExp(r'^yt-dlp\.tar\.gz$')];
        } else {
          repo = 'yt-dlp/ejs';
          assetRegex = [RegExp(r'\.whl$'), RegExp(r'\.tar\.gz$')];
        }

        final info = await _github.getLatestReleaseInfo(
          repo: repo,
          assetRegex: assetRegex,
        );

        if (info != null) {
          _setState(type, ComponentStatus.downloading, pendingUpdate: info);
          final success = await downloadAndInstallInternal(
            type,
            info,
            onDownloadProgress: (progress) {
              _missingModulesProgress = (completed + progress) / total;
              notifyListeners();
            },
            manageBackendLifecycle: false,
          );

          if (success) {
            completed++;
            _missingModulesProgress = completed / total;
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('Error during auto-downloading missing modules: $e');
    } finally {
      _isAutoDownloadingMissing = false;
      _missingModulesProgress = 1.0;
      notifyListeners();
      await _system.resumeInitialization();
    }
  }

  void _setState(
    ComponentType type,
    ComponentStatus status, {
    double? progress,
    String? version,
    UpdateInfo? pendingUpdate,
  }) {
    final current = _states[type]!;
    _states[type] = UpdateState(
      status: status,
      version: version ?? current.version,
      progress: progress ?? current.progress,
      pendingUpdate: pendingUpdate ?? current.pendingUpdate,
    );
    notifyListeners();
  }

  Future<bool> _isComponentInstalled(ComponentType type) async {
    if (type == ComponentType.app) return true;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final folderName = type == ComponentType.ytDlp ? 'yt_dlp' : 'yt_dlp_ejs';
      final dir = Directory(
        p.join(supportDir.path, 'core_modules', folderName),
      );
      return dir.existsSync() && dir.listSync().isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _loadLocalVersions() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _setState(
        ComponentType.app,
        ComponentStatus.upToDate,
        version: info.version,
      );
    } catch (_) {
      _setState(
        ComponentType.app,
        ComponentStatus.upToDate,
        version: '1.0.0',
      );
    }

    for (final type in [ComponentType.ytDlp, ComponentType.ytDlpEjs]) {
      final prefKey = _versionKey(type);
      final savedVersion = _prefs.getString(prefKey) ?? 'Unknown';
      final isInstalled = await _isComponentInstalled(type);
      _setState(
        type,
        ComponentStatus.upToDate,
        version: isInstalled ? savedVersion : 'Missing module',
      );
    }
  }

  // ==========================================================================
  // FLUJO 1: REVISIÓN A DEMANDA O PERIÓDICA
  // ==========================================================================
  Future<bool> checkForUpdates({
    bool manualCall = true,
    ComponentType? specificType,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (specificType == null || specificType == ComponentType.app) {
      await _prefs.setInt(_lastCheckKey(ComponentType.app), now);
    }
    if (specificType == null || specificType == ComponentType.ytDlp) {
      await _prefs.setInt(_lastCheckKey(ComponentType.ytDlp), now);
    }
    if (specificType == null || specificType == ComponentType.ytDlpEjs) {
      await _prefs.setInt(_lastCheckKey(ComponentType.ytDlpEjs), now);
    }

    notifyListeners();

    final ytDlpChannel = _prefs.getString('channel_ytdlp') == 'stable'
        ? UpdateChannel.stable
        : UpdateChannel.nightly;
    bool updateFound = false;

    if (specificType == null || specificType == ComponentType.ytDlp) {
      _setState(ComponentType.ytDlp, ComponentStatus.checking);
      final ytDlpRepo = ytDlpChannel == UpdateChannel.nightly
          ? 'yt-dlp/yt-dlp-nightly-builds'
          : 'yt-dlp/yt-dlp';
      final found = await _fetchAndCompare(
        ComponentType.ytDlp,
        ytDlpRepo,
        [RegExp(r'^yt-dlp\.tar\.gz$')],
      );
      updateFound = updateFound || found;
    }
    if (specificType == null || specificType == ComponentType.ytDlpEjs) {
      _setState(ComponentType.ytDlpEjs, ComponentStatus.checking);
      final found = await _fetchAndCompare(
        ComponentType.ytDlpEjs,
        'yt-dlp/ejs',
        [RegExp(r'\.whl$'), RegExp(r'\.tar\.gz$')],
      );
      updateFound = updateFound || found;
    }
    if (specificType == null || specificType == ComponentType.app) {
      _setState(ComponentType.app, ComponentStatus.checking);
      final bool found;
      if (Platform.isLinux) {
        // En Linux (deb, appimage, snap) no se descarga ningún archivo de la app,
        // solo se valida si en GitHub existe una nueva versión.
        found = await _fetchAndCompare(
          ComponentType.app,
          'chomusuke-mk/vidra',
          const [],
        );
      } else {
        final appAsset = await _getExpectedAppAssetName();
        found = await _fetchAndCompare(
          ComponentType.app,
          'chomusuke-mk/vidra',
          [RegExp('^${RegExp.escape(appAsset)}\$')],
        );
      }
      updateFound = updateFound || found;
    }

    return updateFound;
  }

  Future<bool> _fetchAndCompare(
    ComponentType type,
    String repo,
    List<RegExp> assetRegex,
  ) async {
    final info = await _github.getLatestReleaseInfo(
      repo: repo,
      assetRegex: assetRegex,
    );

    final isMissing = !(await _isComponentInstalled(type));

    String normalize(String v) => v.trim().replaceFirst(RegExp(r'^v'), '');

    if (info != null &&
        (normalize(info.version) != normalize(_states[type]!.version) ||
            isMissing)) {
      await _prefs.setString(_discoveredVersionKey(type), info.version);
      await _prefs.setString(_discoveredInfoKey(type), info.toJsonString());
      _setState(
        type,
        ComponentStatus.updateAvailable,
        pendingUpdate: info,
        version: isMissing ? 'Missing module' : null,
      );
      return true;
    } else if (info != null) {
      await _prefs.remove(_discoveredVersionKey(type));
      await _prefs.remove(_discoveredInfoKey(type));
      _setState(type, ComponentStatus.upToDate, pendingUpdate: null);
      return false;
    } else {
      _setState(type, ComponentStatus.error);
      return false;
    }
  }

  LinuxPackageType getLinuxPackageType() {
    if (!Platform.isLinux) return LinuxPackageType.unknown;
    final snapName = Platform.environment['SNAP_NAME'] ?? '';
    final snapPath = Platform.environment['SNAP'] ?? '';
    if (snapName == 'vidra' || snapPath.contains('vidra')) {
      return LinuxPackageType.snap;
    }
    if (Platform.environment.containsKey('APPIMAGE')) {
      return LinuxPackageType.appImage;
    }
    return LinuxPackageType.deb;
  }

  // ==========================================================================
  // FLUJO 2: DESCARGAR E INSTALAR OTA
  // ==========================================================================
  Future<void> downloadAndInstall(ComponentType type) async {
    final info = _states[type]?.pendingUpdate;
    if (info == null) return;

    if (type == ComponentType.app && Platform.isLinux) {
      final linuxType = getLinuxPackageType();
      if (linuxType == LinuxPackageType.snap) {
        final uri = Uri.parse('snap://vidra');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          await launchUrl(
            Uri.parse('https://snapcraft.io/vidra'),
            mode: LaunchMode.externalApplication,
          );
        }
        return;
      } else if (linuxType == LinuxPackageType.deb) {
        await LinuxDebUpdateDialog.show();
        return;
      } else if (linuxType == LinuxPackageType.appImage) {
        await LinuxAppImageUpdateDialog.show();
        return;
      }
    }

    await downloadAndInstallInternal(type, info);
  }

  @visibleForTesting
  Future<bool> downloadAndInstallInternal(
    ComponentType type,
    UpdateInfo info, {
    Function(double progress)? onDownloadProgress,
    bool manageBackendLifecycle = true,
  }) async {
    _setState(type, ComponentStatus.downloading, progress: 0.0);

    final supportDir = await getApplicationSupportDirectory();
    final tempDir = Directory(
      p.join(supportDir.path, 'temp_updates', type.name),
    );
    if (!tempDir.existsSync()) tempDir.createSync(recursive: true);

    final binaryFile = File(p.join(tempDir.path, p.basename(info.downloadUrl)));
    final sumsFile = File(p.join(tempDir.path, 'sums'));
    final sigFile = File(p.join(tempDir.path, 'sig'));

    try {
      final ok = await _github.downloadFile(
        url: info.downloadUrl,
        savePath: binaryFile.path,
        onProgress: (rec, total) {
          final pRatio = total > 0 ? rec / total : 0.0;
          _setState(type, ComponentStatus.downloading, progress: pRatio);
          onDownloadProgress?.call(pRatio);
        },
      );

      if (!ok || !binaryFile.existsSync() || binaryFile.lengthSync() == 0) {
        _setState(type, ComponentStatus.error);
        return false;
      }

      final publicKey = PublicKeys.getKeyForComponent(type);
      if (info.requiresPgpValidation && publicKey != null) {
        _setState(type, ComponentStatus.verifying);
        final sumsOk = await _github.downloadFile(
          url: info.sumsUrl!,
          savePath: sumsFile.path,
        );
        if (!sumsOk || !sumsFile.existsSync() || sumsFile.lengthSync() == 0) {
          _setState(type, ComponentStatus.error);
          return false;
        }

        final sigOk = await _github.downloadFile(
          url: info.sigUrl!,
          savePath: sigFile.path,
        );
        if (!sigOk || !sigFile.existsSync() || sigFile.lengthSync() == 0) {
          _setState(type, ComponentStatus.error);
          return false;
        }

        final isSafe = await PgpVerifier.verifyBinary(
          binaryFile: binaryFile,
          sumsFile: sumsFile,
          sigFile: sigFile,
          publicKey: publicKey,
          expectedBinaryName: p.basename(info.downloadUrl),
        );

        if (!isSafe) {
          _setState(type, ComponentStatus.error);
          return false;
        }
      }

      _setState(type, ComponentStatus.installing);

      if (type == ComponentType.app) {
        final OpenResult result;
        if (Platform.environment.containsKey('FLUTTER_TEST')) {
          result = OpenResult(type: ResultType.done, message: 'done');
        } else {
          result = await OpenFilex.open(binaryFile.path);
        }
        if (result.type == ResultType.done) {
          // Strictly read installed version from Platform PackageInfo
          final currentPkg = await PackageInfo.fromPlatform();
          _setState(
            type,
            ComponentStatus.upToDate,
            version: currentPkg.version,
            pendingUpdate: null,
          );
          return true;
        } else {
          debugPrint('Error al abrir instalador: ${result.message}');
          _setState(type, ComponentStatus.error);
          return false;
        }
      } else {
        if (!binaryFile.existsSync() || binaryFile.lengthSync() == 0) {
          _setState(type, ComponentStatus.error);
          return false;
        }

        if (manageBackendLifecycle) {
          await _system.stopBackendForUpdate();
        }
        try {
          final modulesDir = Directory(p.join(supportDir.path, 'core_modules'));
          final pythonPackageName = type == ComponentType.ytDlp
              ? 'yt_dlp'
              : 'yt_dlp_ejs';
          final destDir = Directory(p.join(modulesDir.path, pythonPackageName));

          final extracted = await ArchiveExtractor.extractPythonModule(
            archiveFile: binaryFile,
            destinationDir: destDir,
            targetSubfolderName: pythonPackageName,
          );

          if (extracted) {
            await _prefs.setString(_versionKey(type), info.version);
            await _prefs.remove(_discoveredVersionKey(type));
            await _prefs.remove(_discoveredInfoKey(type));
            _setState(
              type,
              ComponentStatus.upToDate,
              version: info.version,
              pendingUpdate: null,
            );
            return true;
          } else {
            _setState(type, ComponentStatus.error);
            return false;
          }
        } finally {
          if (manageBackendLifecycle) {
            await _system.resumeInitialization();
          }
        }
      }
    } catch (e) {
      debugPrint('Error during downloadAndInstall: $e');
      _setState(type, ComponentStatus.error);
      return false;
    } finally {
      if (type != ComponentType.app && tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (e) {
          debugPrint('Error cleaning up temp directory: $e');
        }
      }
    }
  }

  Future<String> _getExpectedAppAssetName() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final abis = androidInfo.supportedAbis;

      if (abis.any((a) => a.contains('arm64-v8a') || a.contains('arm64'))) {
        return 'vidra-android-arm64-v8a.apk';
      }
      if (abis.any((a) => a.contains('x86_64'))) {
        return 'vidra-android-x86_64.apk';
      }
      if (abis.any((a) => a.contains('armeabi-v7a') || a.contains('armv7'))) {
        return 'vidra-android-armeabi-v7a.apk';
      }
      return 'vidra-android.apk';
    } else if (Platform.isLinux) {
      throw UnsupportedError(
        'Linux does not download binary app assets; updates are validated via version and handled via package managers or update scripts.',
      );
    } else if (Platform.isWindows) {
      return 'vidra-windows.exe';
    } else if (Platform.isMacOS) {
      return 'vidra-macos.dmg';
    } else if (Platform.isIOS) {
      return 'vidra-ios.ipa';
    }
    return 'vidra-unknown';
  }
}

extension ComponentTypeExt on ComponentType {
  String get prefSuffix => switch (this) {
    ComponentType.app => 'app',
    ComponentType.ytDlp => 'yt_dlp',
    ComponentType.ytDlpEjs => 'yt_dlp_ejs',
  };
  String get lastCheckKey => 'last_update_check_$prefSuffix';
  String get discoveredVersionKey => 'discovered_version_$prefSuffix';
  String get discoveredInfoKey => 'discovered_info_$prefSuffix';
  String get versionKey => 'version_$prefSuffix';
}
