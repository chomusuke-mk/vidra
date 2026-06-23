import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/core/network/github_client.dart';
import 'package:vidra/core/security/pgp_verifier.dart';
import 'package:vidra/core/security/public_keys.dart';
import 'package:vidra/core/utils/archive_extractor.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

enum ComponentStatus {
  upToDate,
  updateAvailable,
  downloading,
  verifying,
  installing,
  error,
}

class UpdateState {
  final ComponentStatus status;
  final String version;
  final double progress; // 0.0 a 1.0
  final UpdateInfo?
  pendingUpdate; // Guarda la info si hay actualización disponible

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
      version: '1.0.0',
    ), // Ideal usar package_info_plus
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
    _loadLocalVersions();
    _checkInitialUpdates();
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

  void _loadLocalVersions() {
    _setState(
      ComponentType.ytDlp,
      ComponentStatus.upToDate,
      version: _prefs.getString('version_yt_dlp') ?? 'Desconocida',
    );
    _setState(
      ComponentType.ytDlpEjs,
      ComponentStatus.upToDate,
      version: _prefs.getString('version_yt_dlp_ejs') ?? 'Desconocida',
    );
  }

  // ==========================================================================
  // FLUJO 1: REVISIÓN PERIÓDICA (LAS 6 HORAS)
  // ==========================================================================
  Future<void> _checkInitialUpdates() async {
    final lastCheck = _prefs.getInt('last_update_check') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sixHours = const Duration(hours: 6).inMilliseconds;

    if (now - lastCheck > sixHours) {
      await checkForUpdates(manualCall: false);
    }
  }

  Future<void> checkForUpdates({bool manualCall = true}) async {
    if (manualCall) {
      _prefs.setInt('last_update_check', DateTime.now().millisecondsSinceEpoch);
    }

    // Leemos preferencias de canales (Por defecto estable)
    final ytDlpChannel = _prefs.getString('channel_ytdlp') == 'nightly'
        ? UpdateChannel.nightly
        : UpdateChannel.stable;

    // 1. Verificar yt-dlp
    await _fetchAndCompare(ComponentType.ytDlp, ytDlpChannel, 'yt-dlp.tar.gz');
    // 2. Verificar EJS (Solo estable, y el nombre del archivo empieza con yt_dlp_ejs)
    await _fetchAndCompare(
      ComponentType.ytDlpEjs,
      UpdateChannel.stable,
      'yt_dlp_ejs',
      isPrefix: true,
    );
    // 3. Verificar App
    final appAsset = await _getExpectedAppAssetName();
    await _fetchAndCompare(ComponentType.app, UpdateChannel.stable, appAsset);
  }

  Future<void> _fetchAndCompare(
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

    if (info != null && info.version != _states[type]!.version) {
      _setState(type, ComponentStatus.updateAvailable, pendingUpdate: info);
    } else if (info != null) {
      _setState(type, ComponentStatus.upToDate);
    }
  }

  // ==========================================================================
  // FLUJO 2: DESCARGAR E INSTALAR OTA
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

    // 1. Descarga del binario con progreso visual
    final ok = await _github.downloadFile(
      url: info.downloadUrl,
      savePath: binaryPath,
      onProgress: (rec, total) =>
          _setState(type, ComponentStatus.downloading, progress: rec / total),
    );

    if (!ok) {
      return _setState(type, ComponentStatus.error);
    }

    // 2. Validación PGP Paranoica (Para App y yt-dlp)
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
        tempDir.deleteSync(recursive: true);
        return _setState(type, ComponentStatus.error); // Bloqueo de seguridad
      }
    }

    // 3. Instalación
    _setState(type, ComponentStatus.installing);

    if (type == ComponentType.app) {
      // TODO: Usar open_filex para pedir a Android que instale el APK
    } else {
      // 🛑 Petición al Cerebro para APAGAR PYTHON
      await _system.stopBackendForUpdate();

      final modulesDir = Directory(p.join(supportDir.path, 'core_modules'));
      // La carpeta de destino donde el PYTHONPATH de Python buscará.
      // Recuerda: Python importa con guión bajo (yt_dlp y yt_dlp_ejs)
      final pythonPackageName = type == ComponentType.ytDlp
          ? 'yt_dlp'
          : 'yt_dlp_ejs';
      final destDir = Directory(p.join(modulesDir.path, pythonPackageName));

      // Extraemos quirúrgicamente
      final extracted = await ArchiveExtractor.extractPythonModule(
        archiveFile: File(binaryPath),
        destinationDir: destDir,
        targetSubfolderName: pythonPackageName,
      );

      if (extracted) {
        // Guardamos la nueva versión y el estado
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

      // 🟢 Petición al Cerebro para REVIVIR PYTHON
      await _system.resumeInitialization();
    }

    // 4. Limpieza del directorio temporal
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }

  // ==========================================================================
  // MÉTODOS DE APOYO
  // ==========================================================================
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
