import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

class ArchiveExtractor {
  /// Extrae un .tar.gz buscando una subcarpeta específica y volcándola en el destino.
  static Future<bool> extractPythonModule({
    required File archiveFile,
    required Directory destinationDir,
    required String targetSubfolderName, // Ej: "yt-dlp" o "yt_dlp_ejs"
  }) async {
    try {
      if (!destinationDir.existsSync()) {
        destinationDir.createSync(recursive: true);
      }
      destinationDir.createSync(recursive: true);

      // 1. Decodificación en cascada GZip -> Tar
      final bytes = await archiveFile.readAsBytes();
      final tarBytes = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(tarBytes);

      bool foundAtLeastOneFile = false;

      // 2. Búsqueda y extracción quirúrgica
      for (final file in archive) {
        // file.name suele ser: "yt-dlp-master/yt_dlp/extractor/youtube.py"
        final pathSegments = p.split(file.name);

        final targetIndex = pathSegments.indexOf(targetSubfolderName);

        if (targetIndex != -1) {
          // Extraemos todo lo que esté DENTRO de la carpeta objetivo.
          // Si pathSegments = ["yt_dlp_ejs-0.8.0", "yt_dlp_ejs", "__init__.py"]
          // Y targetIndex = 1
          // sublist(2) nos da ["__init__.py"]
          final relativeSubPathList = pathSegments.sublist(targetIndex + 1);

          if (relativeSubPathList.isEmpty) {
            continue; // Es la propia carpeta raíz, la ignoramos
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
