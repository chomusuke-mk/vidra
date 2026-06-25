import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

class ArchiveExtractor {
  /// Extrae un archivo comprimido buscando una subcarpeta específica y volcándola
  /// directamente en el directorio destino, ignorando el resto del archivo.
  static Future<bool> extractPythonModule({
    required File archiveFile,
    required Directory destinationDir, // Ej: /.../core_modules/yt_dlp
    required String targetSubfolderName, // Ej: "yt_dlp" o "yt_dlp_ejs"
  }) async {
    try {
      if (destinationDir.existsSync()) {
        destinationDir.deleteSync(recursive: true);
      }
      destinationDir.createSync(recursive: true);

      final bytes = await archiveFile.readAsBytes();
      Archive archive;

      // 1. MAGIA: Detectar si es un Wheel (.whl / .zip) o un Tarball (.tar.gz)
      if (archiveFile.path.toLowerCase().endsWith('.whl') ||
          archiveFile.path.toLowerCase().endsWith('.zip')) {
        archive = ZipDecoder().decodeBytes(bytes);
      } else {
        final tarBytes = GZipDecoder().decodeBytes(bytes);
        archive = TarDecoder().decodeBytes(tarBytes);
      }

      bool foundAtLeastOneFile = false;

      // 2. Búsqueda y extracción quirúrgica
      for (final file in archive) {
        // Unificamos separadores por si el .whl fue compilado en un Windows
        final normalizedName = file.name.replaceAll('\\', '/');
        final pathSegments = p.split(normalizedName);

        final targetIndex = pathSegments.indexOf(targetSubfolderName);

        if (targetIndex != -1) {
          // Extraemos todo lo que esté DENTRO de la carpeta objetivo (yt_dlp_ejs)
          // Y esto ignorará automáticamente la carpeta "yt_dlp_ejs-0.8.0.dist-info"
          // porque su nombre no coincide exactamente con "yt_dlp_ejs".
          final relativeSubPathList = pathSegments.sublist(targetIndex + 1);

          if (relativeSubPathList.isEmpty) {
            continue; // Es la propia carpeta raíz
          }

          final relativePath = p.joinAll(relativeSubPathList);
          final finalPath = p.join(destinationDir.path, relativePath);

          if (file.isFile) {
            final outFile = File(finalPath);
            outFile.parent.createSync(recursive: true);
            outFile.writeAsBytesSync(file.content as List<int>);
            foundAtLeastOneFile = true;
          } else {
            Directory(finalPath).createSync(recursive: true);
          }
        }
      }

      if (!foundAtLeastOneFile) {
        debugPrint(
          '❌ No se encontró la carpeta $targetSubfolderName dentro del archivo.',
        );
        return false;
      }

      debugPrint('✅ Extracción quirúrgica completada: $targetSubfolderName');
      return true;
    } catch (e) {
      debugPrint('❌ Error en extracción: $e');
      return false;
    }
  }
}
