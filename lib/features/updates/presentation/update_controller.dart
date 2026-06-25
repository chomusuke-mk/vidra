import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';

import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/core/network/github_client.dart';
import 'package:vidra/core/security/pgp_verifier.dart';
import 'package:vidra/core/security/public_keys.dart';
import 'package:vidra/core/utils/archive_extractor.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

// ¡NUEVO! Añadimos el estado 'checking'
enum ComponentStatus {
  upToDate,
  checking,
  updateAvailable,
  downloading,
  verifying,
  installing,
  error,
}

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

  final Map<ComponentType, UpdateState> _states = {
    ComponentType.app: UpdateState(
      status: ComponentStatus.upToDate,
      version: 'Cargando...',
    ),
    ComponentType.ytDlp: UpdateState(
      status: ComponentStatus.upToDate,
      version: 'Desconocida',
    ),
    ComponentType.ytDlpEjs: UpdateState(
      status: ComponentStatus.upToDate,
      version: 'Desconocida',
    ),
  };

  UpdateState getState(ComponentType type) => _states[type]!;

  UpdateController(this._github, this._system, this._prefs) {
    _init();
  }

  Future<void> _init() async {
    await _loadLocalVersions();

    final lastCheck = _prefs.getInt('last_update_check') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sixHours = const Duration(hours: 6).inMilliseconds;

    if (now - lastCheck > sixHours) {
      await checkForUpdates(manualCall: false);
    } else {
      if (!(await _isComponentInstalled(ComponentType.ytDlp))) {
        await checkForUpdates(
          manualCall: false,
          specificType: ComponentType.ytDlp,
        );
      }
      if (!(await _isComponentInstalled(ComponentType.ytDlpEjs))) {
        await checkForUpdates(
          manualCall: false,
          specificType: ComponentType.ytDlpEjs,
        );
      }
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
    PackageInfo.fromPlatform().then((info) {
      _setState(
        ComponentType.app,
        ComponentStatus.upToDate,
        version: info.version,
      );
    });

    for (final type in [ComponentType.ytDlp, ComponentType.ytDlpEjs]) {
      final prefKey = type == ComponentType.ytDlp
          ? 'version_yt_dlp'
          : 'version_yt_dlp_ejs';
      final savedVersion = _prefs.getString(prefKey) ?? 'Desconocida';
      final isInstalled = await _isComponentInstalled(type);
      _setState(
        type,
        ComponentStatus.upToDate,
        version: isInstalled ? savedVersion : 'Falta módulo',
      );
    }
  }

  // ==========================================================================
  // FLUJO 1: REVISIÓN A DEMANDA O PERIÓDICA (Ahora devuelve un booleano)
  // ==========================================================================
  Future<bool> checkForUpdates({
    bool manualCall = true,
    ComponentType? specificType,
  }) async {
    if (manualCall && specificType == null) {
      _prefs.setInt('last_update_check', DateTime.now().millisecondsSinceEpoch);
    }

    final ytDlpChannel = _prefs.getString('channel_ytdlp') == 'nightly'
        ? UpdateChannel.nightly
        : UpdateChannel.stable;
    bool updateFound = false;

    if (specificType == null || specificType == ComponentType.ytDlp) {
      _setState(ComponentType.ytDlp, ComponentStatus.checking);
      final found = await _fetchAndCompare(
        ComponentType.ytDlp,
        ytDlpChannel,
        'yt-dlp.tar.gz',
      );
      updateFound = updateFound || found;
    }
    if (specificType == null || specificType == ComponentType.ytDlpEjs) {
      _setState(ComponentType.ytDlpEjs, ComponentStatus.checking);
      final found = await _fetchAndCompare(
        ComponentType.ytDlpEjs,
        UpdateChannel.stable,
        'yt_dlp_ejs',
        isPrefix: true,
      );
      updateFound = updateFound || found;
    }
    if (specificType == null || specificType == ComponentType.app) {
      _setState(ComponentType.app, ComponentStatus.checking);
      final appAsset = await _getExpectedAppAssetName();
      final found = await _fetchAndCompare(
        ComponentType.app,
        UpdateChannel.stable,
        appAsset,
      );
      updateFound = updateFound || found;
    }

    return updateFound;
  }

  Future<bool> _fetchAndCompare(
    ComponentType type,
    UpdateChannel channel,
    String assetName, {
    bool isPrefix = false,
  }) async {
    final info = await _github.getLatestReleaseInfo(
      type: type,
      channel: channel,
      targetAssetName: assetName,
      isPrefixMatch: isPrefix,
    );

    final isMissing = !(await _isComponentInstalled(type));

    if (info != null && (info.version != _states[type]!.version || isMissing)) {
      _setState(
        type,
        ComponentStatus.updateAvailable,
        pendingUpdate: info,
        version: isMissing ? 'Falta módulo' : null,
      );
      return true; // ¡Se encontró algo nuevo!
    } else if (info != null) {
      _setState(type, ComponentStatus.upToDate);
      return false; // Está al día
    } else {
      _setState(type, ComponentStatus.error);
      return false; // Error de red
    }
  }

  // ==========================================================================
  // FLUJO 2: DESCARGAR E INSTALAR OTA (Permanece casi igual)
  // ==========================================================================
  Future<void> downloadAndInstall(ComponentType type) async {
    final info = _states[type]?.pendingUpdate;
    if (info == null) return;

    _setState(type, ComponentStatus.downloading, progress: 0.0);

    final supportDir = await getApplicationSupportDirectory();
    final tempDir = Directory(p.join(supportDir.path, 'temp_updates'));
    if (!tempDir.existsSync()) tempDir.createSync(recursive: true);

    final binaryPath = p.join(tempDir.path, p.basename(info.downloadUrl));
    final sumsPath = p.join(tempDir.path, 'sums');
    final sigPath = p.join(tempDir.path, 'sig');

    final ok = await _github.downloadFile(
      url: info.downloadUrl,
      savePath: binaryPath,
      onProgress: (rec, total) =>
          _setState(type, ComponentStatus.downloading, progress: rec / total),
    );

    if (!ok) return _setState(type, ComponentStatus.error);

    if (info.requiresPgpValidation) {
      _setState(type, ComponentStatus.verifying);
      await _github.downloadFile(url: info.sumsUrl!, savePath: sumsPath);
      await _github.downloadFile(url: info.sigUrl!, savePath: sigPath);

      final isSafe = await PgpVerifier.verifyBinary(
        binaryFile: File(binaryPath),
        sumsFile: File(sumsPath),
        sigFile: File(sigPath),
        publicKey: PublicKeys.getKeyForComponent(type),
        expectedBinaryName: p.basename(info.downloadUrl),
      );

      if (!isSafe) {
        //tempDir.deleteSync(recursive: true);
        return _setState(type, ComponentStatus.error);
      }
    }

    _setState(type, ComponentStatus.installing);

    if (type == ComponentType.app) {
      final result = await OpenFilex.open(binaryPath);
      if (result.type == ResultType.done) {
        // Al lanzar el intent de instalación con éxito, el sistema operativo tomará el control.
        // Nosotros regresamos la tarjeta a su estado normal.
        _setState(
          type,
          ComponentStatus.upToDate,
          version: info.version,
          pendingUpdate: null,
        );
      } else {
        // Si el usuario no dio permisos o el archivo es inválido
        debugPrint('Error al abrir el APK: ${result.message}');
        _setState(type, ComponentStatus.error);
      }
    } else {
      await _system.stopBackendForUpdate();
      final modulesDir = Directory(p.join(supportDir.path, 'core_modules'));
      final pythonPackageName = type == ComponentType.ytDlp
          ? 'yt_dlp'
          : 'yt_dlp_ejs';
      final destDir = Directory(p.join(modulesDir.path, pythonPackageName));

      final extracted = await ArchiveExtractor.extractPythonModule(
        archiveFile: File(binaryPath),
        destinationDir: destDir,
        targetSubfolderName: pythonPackageName,
      );

      if (extracted) {
        await _prefs.setString(
          type == ComponentType.ytDlp ? 'version_yt_dlp' : 'version_yt_dlp_ejs',
          info.version,
        );
        _setState(
          type,
          ComponentStatus.upToDate,
          version: info.version,
          pendingUpdate: null,
        );
      } else {
        _setState(type, ComponentStatus.error);
      }
      await _system.resumeInitialization();
    }

    if (type != ComponentType.app && tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }

  Future<String> _getExpectedAppAssetName() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final abi = androidInfo.supportedAbis.firstOrNull ?? '';

      if (abi.contains('arm64')) return 'vidra-android-arm64-v8a.apk';
      if (abi.contains('armeabi-v7a')) return 'vidra-android-armeabi-v7a.apk';
      if (abi.contains('x86_64')) return 'vidra-android-x86_64.apk';
      if (abi.contains('x86')) return 'vidra-android-x86.apk';
      return 'vidra-android.apk';
    } else if (Platform.isLinux) {
      return 'vidra-linux.AppImage';
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
