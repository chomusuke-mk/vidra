import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/state/app_release_updater.dart';
import 'package:vidra/state/backend_update_indicator.dart';
import 'package:vidra/state/release_update_cache.dart';

class AppUpdateBootstrapper {
  AppUpdateBootstrapper({GitHubReleaseUpdater? updater})
    : _updater =
          updater ?? GitHubReleaseUpdater(owner: 'chomusuke-mk', repo: 'vidra');

  final GitHubReleaseUpdater _updater;

  Future<void> run() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final current = packageInfo.version.trim();
      if (current.isEmpty) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final now = _updater.now();
      final last = ReleaseUpdateCache.readLastCheck(prefs);

      if (last != null &&
          now.difference(last) < GitHubReleaseUpdater.throttleWindow) {
        _applyIndicator(
          cached: ReleaseUpdateCache.read(prefs, currentVersion: current),
        );
        return;
      }

      await ReleaseUpdateCache.writeLastCheck(prefs, now);

      final latest = await _updater.fetchLatest(
        currentVersion: current,
        platform: defaultTargetPlatform,
      );

      await ReleaseUpdateCache.write(prefs, latest);
      _applyIndicator(cached: latest);
    } catch (error) {
      debugPrint('Startup update check failed: $error');
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        final current = packageInfo.version.trim();
        if (current.isEmpty) {
          return;
        }
        final prefs = await SharedPreferences.getInstance();
        _applyIndicator(
          cached: ReleaseUpdateCache.read(prefs, currentVersion: current),
        );
      } catch (_) {
        // Ignore any fallback errors.
      }
    }
  }

  void _applyIndicator({required ReleaseUpdateInfo? cached}) {
    final indicator = BackendUpdateIndicator.instance;

    // Don't override more urgent states.
    if (indicator.current == BackendUpdateStatus.downloadingUpdate ||
        indicator.current == BackendUpdateStatus.installReady) {
      return;
    }

    if (cached != null && cached.isUpdateAvailable) {
      indicator.setState(BackendUpdateStatus.updateAvailable);
    } else {
      indicator.setState(BackendUpdateStatus.idle);
    }
  }
}
