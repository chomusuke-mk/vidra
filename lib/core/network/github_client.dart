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
    required ComponentType type,
    required UpdateChannel channel,
    required String
    targetAssetName, // El archivo exacto que queremos (ej. "yt-dlp", "vidra.apk")
    bool isPrefixMatch = false,
  }) async {
    // 1. Enrutamiento inteligente de repositorios
    String repo;
    if (type == ComponentType.ytDlp) {
      repo = channel == UpdateChannel.nightly
          ? 'yt-dlp/yt-dlp-nightly-builds'
          : 'yt-dlp/yt-dlp';
    } else if (type == ComponentType.ytDlpEjs) {
      repo = 'yt-dlp/ejs'; // EJS solo tiene estable
    } else {
      repo = 'chomusuke-mk/vidra';
    }

    try {
      // Como bien apuntaste, todos soportan /releases/latest.
      final response = await _dio.get(
        'https://api.github.com/repos/$repo/releases/latest',
      );
      final data = response.data;

      final String version = data['tag_name'];
      final String changelog = data['body'] ?? 'No changelog available.';
      final List assets = data['assets'] ?? [];

      String? downloadUrl;
      String? sumsUrl;
      String? sigUrl;

      // Variables para cazar múltiples formatos si usamos búsqueda por prefijo
      String? foundWhl;
      String? foundTarGz;

      // 2. Extracción de Assets específicos
      for (var asset in assets) {
        final name = asset['name'] as String;
        final url = asset['browser_download_url'] as String;

        if (isPrefixMatch && name.startsWith(targetAssetName)) {
          // Si es por prefijo (EJS), atrapamos los dos posibles formatos
          if (name.endsWith('.whl')) {
            foundWhl = url;
          } else if (name.endsWith('.tar.gz')) {
            foundTarGz = url;
          }
        } else if (!isPrefixMatch && name == targetAssetName) {
          // Si es búsqueda exacta (App o yt-dlp)
          downloadUrl = url;
        } else if (name == 'SHA2-512SUMS' || name == 'SHA512SUMS') {
          sumsUrl = url;
        } else if (name == 'SHA2-512SUMS.sig' || name == 'SHA512SUMS.sig') {
          sigUrl = url;
        }
      }

      // 3. Resolución de Prioridad (Wheel > Tarball)
      if (isPrefixMatch) {
        downloadUrl = foundWhl ?? foundTarGz;
      }

      if (downloadUrl == null) {
        debugPrint('No se encontró el binario para $targetAssetName en $repo');
        return null; // Fallo crítico si no hay binario
      }

      return UpdateInfo(
        version: version,
        downloadUrl: downloadUrl,
        sumsUrl: sumsUrl,
        sigUrl: sigUrl,
        changelog: changelog,
        type: type,
      );
    } catch (e) {
      // Manejo silencioso de pérdida de red
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
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true, // Crucial porque Github S3 siempre redirige
        ),
      );
      return true;
    } catch (e) {
      return false;
    }
  }
}
