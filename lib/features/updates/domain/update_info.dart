import 'dart:convert';

enum ComponentType { app, ytDlp, ytDlpEjs }

enum UpdateChannel { stable, nightly }

class UpdateInfo {
  final String version; // Ej: "2024.04.09" o tag de la release
  final String downloadUrl; // El binario principal (.apk, yt-dlp o ejs)
  final String? sumsUrl; // Archivo de hashes (SHA2-512SUMS)
  final String? sigUrl; // Firma criptográfica (SHA2-512SUMS.sig)
  final String changelog;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.sumsUrl,
    this.sigUrl,
    required this.changelog,
  });

  /// Determina si este componente requiere (y soporta) validación estricta PGP
  bool get requiresPgpValidation => sumsUrl != null && sigUrl != null;

  Map<String, dynamic> toJson() => {
    'version': version,
    'downloadUrl': downloadUrl,
    'sumsUrl': sumsUrl,
    'sigUrl': sigUrl,
    'changelog': changelog,
  };

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sumsUrl: json['sumsUrl'] as String?,
      sigUrl: json['sigUrl'] as String?,
      changelog: json['changelog'] as String? ?? '',
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory UpdateInfo.fromJsonString(String raw) =>
      UpdateInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
