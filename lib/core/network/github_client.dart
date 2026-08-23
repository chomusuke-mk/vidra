import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vidra/features/updates/domain/update_info.dart';

class GithubClient {
  final Dio _dio;

  GithubClient() : _dio = Dio() {
    _dio.options.headers = {'Accept': 'application/vnd.github.v3+json'};
  }

  /// Obtiene la metadata mapeada dependiendo del repositorio y el canal
  Future<UpdateInfo?> getLatestReleaseInfo({
    required String repo,
    required List<RegExp> assetRegex,
  }) async {
    try {
      final response = await _dio.get(
        'https://api.github.com/repos/$repo/releases/latest',
      );
      final data = response.data;

      final String version = data['tag_name'] ?? '';
      final String changelog = data['body'] ?? 'No changelog available.';
      final List assets = data['assets'] ?? [];

      String? downloadUrl;
      String? sumsUrl;
      String? sigUrl;

      // 2. Extracción de Assets específicos
      for (var asset in assets) {
        final name = asset['name'] as String;
        final url = asset['browser_download_url'] as String;

        if (name == 'SHA2-512SUMS' || name == 'SHA512SUMS') {
          sumsUrl = url;
        } else if (name == 'SHA2-512SUMS.sig' || name == 'SHA512SUMS.sig') {
          sigUrl = url;
        }

        if (downloadUrl != null) {
          continue; // Ya encontramos un binario, no necesitamos seguir buscando
        }

        for (var pattern in assetRegex) {
          if (pattern.hasMatch(name)) {
            downloadUrl = url;
            break;
          }
        }
      }

      if (downloadUrl == null && assetRegex.isNotEmpty) {
        debugPrint('No se encontró ningún asset válido $assetRegex en $repo');
        return null;
      }

      return UpdateInfo(
        version: version,
        downloadUrl: downloadUrl ?? '',
        sumsUrl: sumsUrl,
        sigUrl: sigUrl,
        changelog: changelog,
      );
    } catch (e) {
      debugPrint('Error al obtener la información de la última versión en $repo: $e');
      return null;
    }
  }

  /// Descarga un archivo a una ruta específica reportando progreso nativo
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async {
    try {
      final file = File(savePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }

      await _dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true, // Crucial porque Github S3 siempre redirige
        ),
      );

      if (!file.existsSync() || file.lengthSync() == 0) {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Error al descargar el archivo desde $url: $e');
      return false;
    }
  }
}
