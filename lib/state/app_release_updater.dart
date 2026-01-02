import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:openpgp/openpgp.dart';

class ReleaseUpdateInfo {
  const ReleaseUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tag,
    required this.assetName,
    required this.assetUrl,
    required this.sha256,
    required this.publishedAt,
  });

  final String currentVersion;
  final String latestVersion;
  final String tag;
  final String assetName;
  final Uri assetUrl;
  final String sha256;
  final DateTime? publishedAt;

  bool get isUpdateAvailable =>
      _compareSemVer(latestVersion, currentVersion) > 0;
}

class GitHubReleaseUpdater {
  GitHubReleaseUpdater({
    http.Client? httpClient,
    DateTime Function()? clock,
    required this.owner,
    required this.repo,
  }) : _http = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final http.Client _http;
  final DateTime Function() _clock;
  final String owner;
  final String repo;

  static const Duration throttleWindow = Duration(hours: 8);

  /// Caller is expected to persist throttling timestamps.
  DateTime now() => _clock();

  Future<ReleaseUpdateInfo> fetchLatest({
    required String currentVersion,
    required TargetPlatform platform,
  }) async {
    final latest = await _fetchLatestRelease();
    final assets = _parseAssets(latest);

    final updateAsset = assets.firstWhere(
      (a) => a.name == '_update',
      orElse: () => throw StateError('Latest release missing _update asset'),
    );

    final updateText = await _downloadText(updateAsset.browserDownloadUrl);
    final updateMap = _parseUpdateFile(updateText);

    final tag = (updateMap['tag'] ?? latest['tag_name'] ?? '')
        .toString()
        .trim();
    if (tag.isEmpty) {
      throw StateError('Could not determine release tag from _update/tag_name');
    }

    final latestVersion = (updateMap['version'] ?? '').toString().trim();
    if (latestVersion.isEmpty) {
      throw StateError('Latest release _update missing version');
    }

    final resolvedAssetName = await _resolveAssetName(
      updateMap: updateMap,
      tag: tag,
      platform: platform,
    );

    final targetAsset = assets.firstWhere(
      (a) => a.name == resolvedAssetName,
      orElse: () => throw StateError(
        'Latest release missing expected asset "$resolvedAssetName"',
      ),
    );

    final sha256SumsName = (updateMap['sha256sums'] ?? 'SHA2-256SUMS').trim();
    final sha256SigName = (updateMap['sha256sums_sig'] ?? 'SHA2-256SUMS.sig')
        .trim();

    final sumsAsset = assets.firstWhere(
      (a) => a.name == sha256SumsName,
      orElse: () => throw StateError('Latest release missing $sha256SumsName'),
    );

    final sumsSigAsset = _findOptionalAsset(assets, <String>[
      sha256SigName,
      'SHA2-256SUMS.sig',
      'SHA2-256SUMS.asc',
    ]);
    if (sumsSigAsset == null) {
      throw StateError('Latest release missing signature for $sha256SumsName');
    }

    final sumsBytes = await _downloadBytes(sumsAsset.browserDownloadUrl);
    final signature = await _downloadText(sumsSigAsset.browserDownloadUrl);
    final publicKey = await _loadPublicKey();
    final ok = await OpenPGP.verifyBytes(signature, sumsBytes, publicKey);
    if (!ok) {
      throw StateError('Firma PGP inválida para $sha256SumsName');
    }

    final sumsText = utf8.decode(sumsBytes);
    final sha256 = _sha256ForFile(sumsText, resolvedAssetName);

    final publishedAtRaw = latest['published_at'];
    DateTime? publishedAt;
    if (publishedAtRaw is String) {
      publishedAt = DateTime.tryParse(publishedAtRaw);
    }

    return ReleaseUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      tag: tag,
      assetName: resolvedAssetName,
      assetUrl: targetAsset.browserDownloadUrl,
      sha256: sha256,
      publishedAt: publishedAt,
    );
  }

  _GitHubAsset? _findOptionalAsset(
    List<_GitHubAsset> assets,
    List<String> names,
  ) {
    for (final name in names) {
      for (final asset in assets) {
        if (asset.name == name) {
          return asset;
        }
      }
    }
    return null;
  }

  Future<String> _loadPublicKey() async {
    final text = await rootBundle.loadString('public.key');
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw StateError('public.key está vacío');
    }
    return trimmed;
  }

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/releases/latest',
    );
    final resp = await _http.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'vidra-app',
      },
    );
    if (resp.statusCode != 200) {
      throw HttpException(
        'GitHub latest release request failed (${resp.statusCode})',
        uri: uri,
      );
    }
    final decoded = json.decode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('GitHub API response is not an object');
    }
    return decoded;
  }

  List<_GitHubAsset> _parseAssets(Map<String, dynamic> release) {
    final raw = release['assets'];
    if (raw is! List) {
      return const <_GitHubAsset>[];
    }
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .map(_GitHubAsset.fromJson)
        .toList(growable: false);
  }

  Future<String> _downloadText(Uri url) async {
    final resp = await _http.get(
      url,
      headers: <String, String>{
        'Accept': 'application/octet-stream',
        'User-Agent': 'vidra-app',
      },
    );
    if (resp.statusCode != 200) {
      throw HttpException('Download failed (${resp.statusCode})', uri: url);
    }
    return utf8.decode(resp.bodyBytes);
  }

  Future<Uint8List> _downloadBytes(Uri url) async {
    final resp = await _http.get(
      url,
      headers: <String, String>{
        'Accept': 'application/octet-stream',
        'User-Agent': 'vidra-app',
      },
    );
    if (resp.statusCode != 200) {
      throw HttpException('Download failed (${resp.statusCode})', uri: url);
    }
    return resp.bodyBytes;
  }

  static Map<String, String> _parseUpdateFile(String contents) {
    final map = <String, String>{};
    for (final rawLine in const LineSplitter().convert(contents)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final idx = line.indexOf('=');
      if (idx <= 0) {
        continue;
      }
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.isEmpty) {
        continue;
      }
      map[key] = value;
    }
    return map;
  }

  Future<String> _resolveAssetName({
    required Map<String, String> updateMap,
    required String tag,
    required TargetPlatform platform,
  }) async {
    // New scheme (preferred):
    // - detect local system id (windows_x64, android_x86_64, android, ...)
    // - map via upgrade.<from>=<to>
    // - resolve filename via file.<to>=<asset_filename>
    final systemId = await _detectSystemId(platform);
    final toId = (updateMap['upgrade.$systemId'] ?? systemId).trim();
    final direct = updateMap['file.$toId']?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    // Fallback for when system id isn't known or not present in mapping.
    final platformFallbackId = _fallbackIdForPlatform(platform);
    final toFallback =
        (updateMap['upgrade.$platformFallbackId'] ?? platformFallbackId).trim();
    final fromFallback = updateMap['file.$toFallback']?.trim();
    if (fromFallback != null && fromFallback.isNotEmpty) {
      return fromFallback;
    }

    // Legacy scheme: asset-* keys (kept for compatibility with older releases).
    final legacy = _legacyAssetName(
      updateMap: updateMap,
      tag: tag,
      platform: platform,
    );
    if (legacy != null) {
      return legacy;
    }

    // Final fallback: historical naming.
    switch (platform) {
      case TargetPlatform.windows:
        return 'vidra-$tag-windows.exe';
      case TargetPlatform.linux:
        return 'vidra-$tag-linux.AppImage';
      case TargetPlatform.android:
        return 'vidra-$tag-android.apk';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        throw UnsupportedError('Platform not supported for self-update');
    }
  }

  static String _fallbackIdForPlatform(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.windows:
        return 'windows_x64';
      case TargetPlatform.linux:
        return 'linux_x64';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        throw UnsupportedError('Platform not supported for self-update');
    }
  }

  static String? _legacyAssetName({
    required Map<String, String> updateMap,
    required String tag,
    required TargetPlatform platform,
  }) {
    String? fromUpdate;
    switch (platform) {
      case TargetPlatform.windows:
        fromUpdate = updateMap['asset-windows'];
        break;
      case TargetPlatform.linux:
        fromUpdate = updateMap['asset-linux-appimage'];
        break;
      case TargetPlatform.android:
        fromUpdate = updateMap['asset-android-universal'];
        break;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        fromUpdate = null;
        break;
    }
    final trimmed = fromUpdate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return null;
  }

  Future<String> _detectSystemId(TargetPlatform platform) async {
    try {
      switch (platform) {
        case TargetPlatform.windows:
          final arch = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '')
              .toLowerCase();
          if (arch.contains('arm64')) {
            return 'windows_arm64';
          }
          if (arch.contains('86') && !arch.contains('64')) {
            return 'windows_x86';
          }
          return 'windows_x64';
        case TargetPlatform.android:
          final info = await DeviceInfoPlugin().androidInfo;
          final abis = <String>[];
          // supportedAbis is the most useful; keep some fallbacks.
          abis.addAll(info.supportedAbis);
          abis.addAll(info.supported64BitAbis);
          abis.addAll(info.supported32BitAbis);
          final normalized = abis.map((e) => e.toLowerCase()).toList();

          bool has(String v) => normalized.contains(v.toLowerCase());
          if (has('arm64-v8a')) {
            return 'android_arm64_v8a';
          }
          if (has('x86_64')) {
            return 'android_x86_64';
          }
          if (has('armeabi-v7a')) {
            return 'android_armeabi_v7a';
          }
          if (has('x86')) {
            return 'android_x86';
          }
          return 'android';
        case TargetPlatform.linux:
          // Keep it simple: if you later publish per-arch Linux assets, add mapping here.
          return 'linux_x64';
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
        case TargetPlatform.fuchsia:
          throw UnsupportedError('Platform not supported for self-update');
      }
    } catch (_) {
      // If detection fails, fall back to platform-general id.
      return _fallbackIdForPlatform(platform);
    }
  }

  static String _sha256ForFile(String sha256sums, String fileName) {
    // Format: <hex> <space><space>*?<filename>
    for (final rawLine in const LineSplitter().convert(sha256sums)) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        continue;
      }
      // sha256sum uses two spaces between hash and file.
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }
      final hash = parts.first.trim();
      final name = parts.last.replaceFirst('*', '').trim();
      if (name == fileName) {
        if (!_looksLikeHex(hash, 64)) {
          throw FormatException('Invalid sha256 for $fileName');
        }
        return hash.toLowerCase();
      }
    }
    throw StateError('SHA2-256SUMS does not contain entry for $fileName');
  }

  static bool _looksLikeHex(String input, int expectedLength) {
    if (input.length != expectedLength) {
      return false;
    }
    final re = RegExp(r'^[0-9a-fA-F]+$');
    return re.hasMatch(input);
  }
}

class _GitHubAsset {
  const _GitHubAsset({required this.name, required this.browserDownloadUrl});

  final String name;
  final Uri browserDownloadUrl;

  factory _GitHubAsset.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString();
    final urlRaw = (json['browser_download_url'] ?? '').toString();
    final url = Uri.tryParse(urlRaw);
    if (name.trim().isEmpty || url == null) {
      throw const FormatException('Invalid GitHub asset JSON');
    }
    return _GitHubAsset(name: name, browserDownloadUrl: url);
  }
}

int _compareSemVer(String a, String b) {
  final va = _SemVer.tryParse(a);
  final vb = _SemVer.tryParse(b);
  if (va == null || vb == null) {
    // Fallback: treat as equal if unparseable.
    return 0;
  }
  return va.compareTo(vb);
}

class _SemVer implements Comparable<_SemVer> {
  const _SemVer(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static _SemVer? tryParse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    // Ignore build metadata / prerelease for now.
    s = s.split('+').first;
    s = s.split('-').first;
    final parts = s.split('.');
    if (parts.length < 3) {
      return null;
    }
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) {
      return null;
    }
    return _SemVer(major, minor, patch);
  }

  @override
  int compareTo(_SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }
}
