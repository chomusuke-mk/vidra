import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:vidra/features/downloads/domain/download.dart';

class PlatformUtils {
  static const _platform = MethodChannel('vidra_channel');

  static Future<String> resolveExecutable(String baseName) async {
    if (Platform.isAndroid) {
      try {
        final nativeLibDir = await _platform.invokeMethod<String>(
          'getNativeLibDir',
        );
        return p.join(nativeLibDir ?? '', 'lib$baseName.so');
      } catch (e) {
        debugPrint('Fallo al obtener NativeLibDir para $baseName: $e');
        return 'lib$baseName.so';
      }
    } else {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final ext = Platform.isWindows ? '.exe' : '';
      return p.join(exeDir, '$baseName$ext');
    }
  }

  /// Escanea un archivo en MediaStore de Android para que aparezca en galerías y reproductores.
  static Future<String?> scanMediaFile(String filePath) async {
    if (!Platform.isAndroid || filePath.trim().isEmpty) return null;

    final file = File(filePath);
    if (!file.existsSync()) return null;

    try {
      final mimeType = lookupMimeType(filePath);
      final uri = await _platform
          .invokeMethod<String>('scanFile', {
            'path': filePath,
            'mimeType': mimeType,
          })
          .timeout(const Duration(seconds: 10), onTimeout: () => null);
      debugPrint(
        '📸 [MediaStore] Escaneado completado para: $filePath ($mimeType) -> URI: $uri',
      );
      return uri;
    } catch (e) {
      debugPrint('⚠️ [MediaStore] Error escaneando archivo en MediaStore: $e');
      return null;
    }
  }

  /// Escanea los archivos de una descarga en MediaStore de Android.
  /// - Valida si la plataforma es Android.
  /// - Si es tipo video, escanea el archivo individual.
  /// - Si es tipo lista, solicita la información completa al backend,
  ///   itera sobre cada sub-descarga validando que esté completada y tenga file,
  ///   y finalmente espera la resolución de todos mediante Future.wait.
  static Future<void> scanFiles(
    Download download, {
    Future<dynamic> Function(String id)? fetchDownloadDetails,
    Future<String?> Function(String filePath)? scanMediaFileFn,
    bool? isAndroid,
  }) async {
    final isAndroidPlatform = isAndroid ?? Platform.isAndroid;
    if (!isAndroidPlatform) return;

    final scanner = scanMediaFileFn ?? scanMediaFile;

    if (download.info?.type == DownloadType.video) {
      var filePath = download.info?.file;
      if ((filePath == null || filePath.isEmpty) &&
          download.id != null &&
          fetchDownloadDetails != null) {
        try {
          final data = await fetchDownloadDetails(download.id!);
          if (data is Map<String, dynamic>) {
            filePath = data['info']?['file']?.toString();
          }
        } catch (_) {}
      }
      if (filePath != null && filePath.isNotEmpty) {
        await scanner(filePath);
      }
    } else if (download.info?.type == DownloadType.list) {
      final id = download.id;
      if (id == null || fetchDownloadDetails == null) return;

      try {
        final data = await fetchDownloadDetails(id);
        if (data is Map<String, dynamic>) {
          final fullDownload = Download.fromJson(data);
          final futures = <Future<String?>>[];

          for (final sub in fullDownload.subDownloads ?? <SubDownload>[]) {
            final isCompleted =
                sub.state?.value == DownloadStateEnum.completed;
            final filePath = sub.info?.file;

            if (isCompleted && filePath != null && filePath.isNotEmpty) {
              futures.add(scanner(filePath));
            }
          }

          if (futures.isNotEmpty) {
            await Future.wait(futures);
          }
        }
      } catch (e) {
        debugPrint(
          '⚠️ [MediaStore] Error al obtener detalles de la lista para escanear: $e',
        );
      }
    }
  }
}
