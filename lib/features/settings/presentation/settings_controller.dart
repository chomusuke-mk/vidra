import 'dart:async';
import 'dart:io';
import 'package:external_path/external_path.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vidra/core/utils/platform_utils.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

class SettingsController extends ChangeNotifier {
  final SettingsRepository _repository;
  final Completer<void> _initCompleter = Completer<void>();

  // Variables privadas inicializadas con valores por defecto seguros
  String _appLanguage = 'defaultOption';
  ThemeMode _appTheme = ThemeMode.system;
  DownloadOptions _downloadOptions = DownloadOptions();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  Future<void> get initialized => _initCompleter.future;

  // Getters públicos para acceder a las configuraciones
  String get appLanguage => _appLanguage;
  ThemeMode get appTheme => _appTheme;
  DownloadOptions get downloadOptions => _downloadOptions;

  SettingsController(this._repository) {
    _loadSettings();
  }

  void _loadSettings() async {
    await Future.microtask(() {});
    _appLanguage = _repository.getAppLanguage();
    _appTheme = _repository.getAppTheme();
    var opts = _repository.getDownloadOptions();
    opts = await _applyDynamicDefaults(opts);
    _downloadOptions = opts;
    _isInitialized = true;
    if (!_initCompleter.isCompleted) {
      _initCompleter.complete();
    }
    notifyListeners();
  }

  Future<DownloadOptions> _applyDynamicDefaults(DownloadOptions opts) async {
    final newPaths = Map<PathsKey, String>.from(opts.paths);
    final newRuntimes = Map<JsRuntime, String>.from(opts.jsRuntimes);

    // --- REGLA 1: Directorio de Descargas (PathsKey.home) ---
    final currentHome = newPaths[PathsKey.home]?.trim();
    if (currentHome == null || currentHome.isEmpty) {
      Directory? dir;
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          dir = Directory(
            await ExternalPath.getExternalStoragePublicDirectory(
              ExternalPath.DIRECTORY_DOWNLOAD,
            ),
          );
        } catch (_) {
          // Fallback if external storage is inaccessible
        }
      } else if (Platform.isMacOS) {
        try {
          dir = await getDownloadsDirectory();
        } catch (_) {
          // Path provider getDownloadsDirectory is only available on macOS
        }
      }

      if (dir == null) {
        final homeEnv =
            Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
        if (homeEnv != null && homeEnv.isNotEmpty) {
          dir = Directory(p.join(homeEnv, 'Downloads'));
        }
      }

      if (dir != null) {
        newPaths[PathsKey.home] = dir.path;
      }
    }

    // --- REGLA 2: Sobrescribir siempre los ejecutables (FFmpeg y QuickJS) ---
    final resolvedFfmpeg = await PlatformUtils.resolveExecutable('ffmpeg');
    final resolvedQuickjs = await PlatformUtils.resolveExecutable('quickjs');

    newRuntimes[JsRuntime.quickjs] = resolvedQuickjs;

    // --- REGLA 3: Directorio de Cookies de WebView (vidra_cookies) ---
    String? resolvedCookiesFromWebview = opts.cookiesFromWebview;
    try {
      Directory? appSupportDir;
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        try {
          appSupportDir = await getApplicationSupportDirectory();
        } catch (_) {
          // Fallback if plugin fails
        }
      }
      if (appSupportDir == null) {
        final homeEnv =
            Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
        if (homeEnv != null && homeEnv.isNotEmpty) {
          appSupportDir = Directory(
            p.join(homeEnv, '.local', 'share', 'vidra'),
          );
        } else {
          appSupportDir = Directory.systemTemp;
        }
      }

      final vidraCookiesDir = Directory(
        p.join(appSupportDir.path, 'vidra_cookies'),
      );
      if (!vidraCookiesDir.existsSync()) {
        vidraCookiesDir.createSync(recursive: true);
      }
      resolvedCookiesFromWebview = vidraCookiesDir.path;
    } catch (_) {
      try {
        final fallbackDir = Directory(
          p.join(Directory.systemTemp.path, 'vidra', 'vidra_cookies'),
        );
        if (!fallbackDir.existsSync()) {
          fallbackDir.createSync(recursive: true);
        }
        resolvedCookiesFromWebview = fallbackDir.path;
      } catch (_) {
        // Silent fallback in constrained/read-only test environments
      }
    }

    return opts.copyWith(
      paths: newPaths,
      jsRuntimes: newRuntimes,
      ffmpegLocation: resolvedFfmpeg,
      cookiesFromWebview: resolvedCookiesFromWebview,
    );
  }

  // --- Setters para la App ---
  void setAppLanguage(String lang) {
    _appLanguage = lang;
    _repository.saveAppLanguage(lang);
    notifyListeners();
  }

  void setAppTheme(ThemeMode theme) {
    _appTheme = theme;
    _repository.saveAppTheme(theme);
    notifyListeners();
  }

  // --- Setters para Descargas ---
  void updateDownloadOptions(DownloadOptions newOptions) {
    _downloadOptions = newOptions;
    _repository.saveDownloadOptions(_downloadOptions);
    notifyListeners();
  }

  /// Devuelve las opciones actuales formateadas como un Map listo para enviar
  /// (Tu cliente VidraHttpClient ya hace el jsonEncode internamente)
  Map<String, dynamic> getDownloadOptionsPayload() {
    return _downloadOptions.toJson();
  }
}
