import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/state/app_release_updater.dart';

class ReleaseUpdateCache {
  static const String kUpdateLastCheckKey = 'vidra.app_update.last_check_ms';
  static const String kUpdateCacheLatestVersion =
      'vidra.app_update.cache.latest_version';
  static const String kUpdateCacheTag = 'vidra.app_update.cache.tag';
  static const String kUpdateCacheAssetName =
      'vidra.app_update.cache.asset_name';
  static const String kUpdateCacheAssetUrl = 'vidra.app_update.cache.asset_url';
  static const String kUpdateCacheSha256 = 'vidra.app_update.cache.sha256';

  static DateTime? readLastCheck(SharedPreferences prefs) {
    final lastMs = prefs.getInt(kUpdateLastCheckKey);
    if (lastMs == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(lastMs, isUtc: true).toLocal();
  }

  static Future<void> writeLastCheck(
    SharedPreferences prefs,
    DateTime now,
  ) async {
    await prefs.setInt(kUpdateLastCheckKey, now.toUtc().millisecondsSinceEpoch);
  }

  static ReleaseUpdateInfo? read(
    SharedPreferences prefs, {
    required String currentVersion,
  }) {
    final latestVersion = prefs.getString(kUpdateCacheLatestVersion);
    final tag = prefs.getString(kUpdateCacheTag);
    final assetName = prefs.getString(kUpdateCacheAssetName);
    final assetUrlRaw = prefs.getString(kUpdateCacheAssetUrl);
    final sha256 = prefs.getString(kUpdateCacheSha256);
    if (latestVersion == null ||
        tag == null ||
        assetName == null ||
        assetUrlRaw == null ||
        sha256 == null) {
      return null;
    }
    final assetUrl = Uri.tryParse(assetUrlRaw);
    if (assetUrl == null) {
      return null;
    }
    return ReleaseUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      tag: tag,
      assetName: assetName,
      assetUrl: assetUrl,
      sha256: sha256,
      publishedAt: null,
    );
  }

  static Future<void> write(
    SharedPreferences prefs,
    ReleaseUpdateInfo info,
  ) async {
    await prefs.setString(kUpdateCacheLatestVersion, info.latestVersion);
    await prefs.setString(kUpdateCacheTag, info.tag);
    await prefs.setString(kUpdateCacheAssetName, info.assetName);
    await prefs.setString(kUpdateCacheAssetUrl, info.assetUrl.toString());
    await prefs.setString(kUpdateCacheSha256, info.sha256);
  }
}
