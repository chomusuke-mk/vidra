import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/share/share_intent_payload.dart';

class BackendOptionBuildResult {
  BackendOptionBuildResult({required this.options, this.ensuredHomePathNotice});

  final Map<String, dynamic> options;
  final String? ensuredHomePathNotice;
}

Future<BackendOptionBuildResult> buildBackendOptions(
  PreferencesModel preferencesModel,
) async {
  final preferences = preferencesModel.preferences;
  await preferences.ensureOutputTemplateSegments();
  final ensuredFfmpegPath = await preferences.ensureBundledFfmpegLocation();
  final options = Map<String, dynamic>.from(
    preferences.toBackendOptions(
      excludeKeys: const {'theme_dark', 'language', 'font_size'},
    ),
  );
  final rawPathsValue = preferences.paths.get('value');
  final hadValidPathsHome = _hasValidPathsHome(rawPathsValue);
  String? ensuredHomePath;
  if (!hadValidPathsHome) {
    ensuredHomePath = await preferences.ensurePathsHomeEntry();
  }
  final refreshedPathsValue = preferences.paths.get('value');
  if (refreshedPathsValue is Map<String, String>) {
    options['paths'] = Map<String, String>.from(refreshedPathsValue);
  }
  options.remove('playlist_items');

  if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
    final currentFfmpegValue = options['ffmpeg_location'];
    final before = currentFfmpegValue is String
        ? currentFfmpegValue.trim()
        : '';

    final resolved = ensuredFfmpegPath?.trim().isNotEmpty == true
        ? ensuredFfmpegPath!
        : await preferences.ensureBundledFfmpegLocation();

    if (resolved != null && resolved.trim().isNotEmpty) {
      options['ffmpeg_location'] = resolved;
      if (kDebugMode) {
        debugPrint('ffmpeg_location seteado: $resolved (antes: $before)');
      }
    }
  }

  final notice = !hadValidPathsHome && ensuredHomePath != null
      ? ensuredHomePath.trim().isEmpty
            ? null
            : ensuredHomePath.trim()
      : null;

  return BackendOptionBuildResult(
    options: options,
    ensuredHomePathNotice: notice,
  );
}

Map<String, dynamic> buildShareMetadata(
  ShareIntentPayload payload,
  String presetId, {
  bool autoLaunch = false,
}) {
  final metadata = <String, dynamic>{
    'share_intent': <String, dynamic>{
      'preset': presetId,
      'direct_share': payload.directShare,
      'auto_launch': autoLaunch,
      'display_name': payload.displayName,
      'source_package': payload.sourcePackage,
      'subject': payload.subject,
      'timestamp': payload.timestamp.toIso8601String(),
    },
  };
  metadata.removeWhere((key, value) => value == null);
  final shareIntentData = metadata['share_intent'] as Map<String, dynamic>;
  shareIntentData.removeWhere((key, value) => value == null);
  return metadata;
}

String joinSharedUrls(List<String> urls) {
  return urls.where((url) => url.trim().isNotEmpty).join('\n');
}

bool _hasValidPathsHome(Object? pathsValue) {
  if (pathsValue is Map) {
    final homeValue = pathsValue['home'];
    return homeValue is String && homeValue.trim().isNotEmpty;
  }
  return false;
}
