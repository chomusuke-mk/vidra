import 'package:dio/dio.dart';
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

      // 2. Extracción de Assets específicos
      for (var asset in assets) {
        final name = asset['name'] as String;
        final url = asset['browser_download_url'] as String;
        // Si esPrefijo, validamos que inicie con eso (ej: yt_dlp_ejs-)
        if ((isPrefixMatch &&
                name.startsWith(targetAssetName) &&
                name.endsWith('.tar.gz')) ||
            (!isPrefixMatch && name == targetAssetName)) {
          downloadUrl = url;
        } else if (name == targetAssetName) {
          downloadUrl = url;
        } else if (name == 'SHA2-256SUMS' || name == 'SHA256SUMS') {
          sumsUrl = url;
        } else if (name == 'SHA2-256SUMS.sig' || name == 'SHA256SUMS.sig') {
          sigUrl = url;
        }
      }

      if (downloadUrl == null) return null; // Fallo crítico si no hay binario

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
