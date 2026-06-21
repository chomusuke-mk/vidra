import 'dart:io';
import 'package:external_path/external_path.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

class SettingsController extends ChangeNotifier {
  final SettingsRepository _repository;

  // Variables privadas (sin valores por defecto, se cargan del repo)
  late String _appLanguage;
  late ThemeMode _appTheme;
  late DownloadOptions _downloadOptions;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  static const _platform = MethodChannel('vidra_channel');

  // Getters públicos para acceder a las configuraciones
  String get appLanguage => _appLanguage;
  ThemeMode get appTheme => _appTheme;
  DownloadOptions get downloadOptions => _downloadOptions;

  SettingsController(this._repository) {
    _loadSettings();
  }

  void _loadSettings() async {
    // Recuperamos todo desde el almacenamiento local
    _appLanguage = _repository.getAppLanguage();
    _appTheme = _repository.getAppTheme();
    var opts = _repository.getDownloadOptions();
    opts = await _applyDynamicDefaults(opts);
    _downloadOptions = opts;
    _isInitialized = true;
    notifyListeners();
  }

  Future<DownloadOptions> _applyDynamicDefaults(DownloadOptions opts) async {
    final newPaths = Map<PathsKey, String>.from(opts.paths);
    final newRuntimes = Map<JsRuntime, String>.from(opts.jsRuntimes);

    // --- REGLA 1: Directorio de Descargas (PathsKey.home) ---
    final currentHome = newPaths[PathsKey.home]?.trim();
    if (currentHome == null || currentHome.isEmpty) {
      try {
        Directory? dir;
        if (Platform.isAndroid || Platform.isIOS) {
          dir = Directory(
            await ExternalPath.getExternalStoragePublicDirectory(
              ExternalPath.DIRECTORY_DOWNLOAD,
            ),
          );
        } else {
          dir = await getDownloadsDirectory();
        }

        if (dir != null) {
          newPaths[PathsKey.home] = dir.path;
        }
      } catch (e) {
        debugPrint('Error asignando directorio de descargas por defecto: $e');
      }
    }

    // --- REGLA 2: Sobrescribir siempre los ejecutables (FFmpeg y QuickJS) ---
    final resolvedFfmpeg = await _resolveExecutable('ffmpeg');
    final resolvedQuickjs = await _resolveExecutable('quickjs');

    newRuntimes[JsRuntime.quickjs] = resolvedQuickjs;

    return opts.copyWith(
      paths: newPaths,
      jsRuntimes: newRuntimes,
      ffmpegLocation: resolvedFfmpeg,
    );
  }

  Future<String> _resolveExecutable(String baseName) async {
    if (Platform.isAndroid) {
      try {
        // Pedimos al OS el directorio real de librerías nativas extraídas
        final nativeLibDir = await _platform.invokeMethod<String>(
          'getNativeLibDir',
        );
        return p.join(nativeLibDir ?? '', 'lib$baseName.so');
      } catch (e) {
        debugPrint('Fallo al obtener NativeLibDir para $baseName: $e');
        return 'lib$baseName.so'; // Fallback a puro nombre por si el PATH del sistema lo atrapa
      }
    } else {
      // Magia de Escritorio (Windows, Linux, macOS)
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final ext = Platform.isWindows ? '.exe' : '';
      return p.join(exeDir, '$baseName$ext');
    }
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

  Future<void> clearCache() async {
    debugPrint('Limpiando caché local de la app...');
    await Future.delayed(const Duration(seconds: 1)); // Simulación
    // Lógica para borrar archivos temporales locales
    debugPrint('Caché limpiada.');
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
