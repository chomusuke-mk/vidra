enum ComponentType { app, ytDlp, ytDlpEjs }

enum UpdateChannel { stable, nightly }

class UpdateInfo {
  final String version; // Ej: "2024.04.09" o tag de la release
  final String downloadUrl; // El binario principal (.apk, yt-dlp o ejs)
  final String? sumsUrl; // Archivo de hashes (SHA2-256SUMS)
  final String? sigUrl; // Firma criptográfica (SHA2-256SUMS.sig)
  final String changelog;
  final ComponentType type;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.sumsUrl,
    this.sigUrl,
    required this.changelog,
    required this.type,
  });

  /// Determina si este componente requiere (y soporta) validación estricta PGP
  bool get requiresPgpValidation => sumsUrl != null && sigUrl != null;
}
