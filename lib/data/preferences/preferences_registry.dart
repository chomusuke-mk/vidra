import 'dart:io';
import 'dart:ui' as ui;

import 'package:external_path/external_path.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vidra/constants/languages.dart';
import 'package:vidra/data/preferences/preference_options.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/models/preference.dart';

class Preferences {
  static const Object _skipBackendValue = Object();
  static final Set<String> _outputPlaceholderTokens = Set<String>.unmodifiable(
    autocompleteOptions['output']?.toSet() ?? const <String>{},
  );
  static final Set<String> _supportedSystemLanguages = Set<String>.unmodifiable(
    languageOptions.map((code) => code.toLowerCase()),
  );
  static Map<String, String>? _pathsDefaultValue;
  static Future<void>? _pathsDefaultInitialization;
  static String? _ffmpegDefaultValue;
  static Future<void>? _ffmpegDefaultInitialization;
  static const MethodChannel _nativeChannel = MethodChannel(
    'dev.chomusuke.vidra/native',
  );

  static bool _systemPrefersDarkTheme() {
    return ui.PlatformDispatcher.instance.platformBrightness ==
        ui.Brightness.dark;
  }

  static bool _isLanguageSupported(String? code) {
    if (code == null || code.isEmpty) {
      return false;
    }
    return _supportedSystemLanguages.contains(code.toLowerCase());
  }

  static String _systemLanguageCode() {
    final dispatcher = ui.PlatformDispatcher.instance;
    for (final locale in dispatcher.locales) {
      final candidate = locale.languageCode.toLowerCase();
      if (_isLanguageSupported(candidate)) {
        return candidate;
      }
    }
    final primary = dispatcher.locale.languageCode.toLowerCase();
    if (_isLanguageSupported(primary)) {
      return primary;
    }
    return 'en';
  }
  // Magic Options -----------------------------------------------------------
  final Preference audioLanguage = Preference(
    key: 'audio_language',
    defaultValue: 'best',
    allowedTypes: [String, bool],
  );
  final Preference videoResolution = Preference(
    key: 'video_resolution',
    defaultValue: 'best',
    allowedTypes: [String, bool],
  );
  final Preference videoSubtitles = Preference(
    key: 'video_subtitles',
    defaultValue: 'none',
    allowedTypes: [String, bool],
  );
  // General Options ---------------------------------------------------------
  final Preference isDarkTheme = Preference(
    key: 'theme_dark',
    defaultValue: () => Preferences._systemPrefersDarkTheme(),
    allowedTypes: [bool],
  );

  final Preference language = Preference(
    key: 'language',
    defaultValue: () => Preferences._systemLanguageCode(),
    allowedTypes: [String],
  );

  final Preference fontSize = Preference(
    key: 'font_size',
    defaultValue: 14,
    allowedTypes: [int],
  );

  final Preference ignoreErrors = Preference(
    key: 'ignore_errors',
    defaultValue: true,
    allowedTypes: [bool],
  );

  final Preference abortOnError = Preference(
    key: 'abort_on_error',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference useExtractors = Preference(
    key: 'use_extractors',
    defaultValue: 'all',
    allowedTypes: [String, bool],
  );

  final Preference liveFromStart = Preference(
    key: 'live_from_start',
    defaultValue: true,
    allowedTypes: [bool],
  );

  final Preference waitForVideo = Preference(
    key: 'wait_for_video',
    defaultValue: false,
    allowedTypes: [bool, int],
  );

  // Network Options ---------------------------------------------------------
  final Preference proxy = Preference(
    key: 'proxy',
    defaultValue: '',
    allowedTypes: [String],
  );

  final Preference socketTimeout = Preference(
    key: 'socket_timeout',
    defaultValue: 15,
    allowedTypes: [int],
  );

  final Preference sourceAddress = Preference(
    key: 'source_address',
    defaultValue: '',
    allowedTypes: [String],
  );

  final Preference impersonate = Preference(
    key: 'impersonate',
    defaultValue: false,
    allowedTypes: [String, bool],
  );

  final Preference foceIPv4 = Preference(
    key: 'force_ipv4',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference forceIPv6 = Preference(
    key: 'force_ipv6',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference enableFileUrls = Preference(
    key: 'enable_file_urls',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference geoVerificationProxy = Preference(
    key: 'geo_verification_proxy',
    defaultValue: '',
    allowedTypes: [String],
  );

  final Preference xff = Preference(
    key: 'xff',
    defaultValue: '',
    allowedTypes: [String],
  );

  final Preference preferInsecure = Preference(
    key: 'prefer_insecure',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference addHeaders = Preference(
    key: 'add_headers',
    defaultValue: const <String, String>{},
    allowedTypes: [Map<String, String>, String],
  );

  final Preference cookies = Preference(
    key: 'cookies',
    defaultValue: false,
    allowedTypes: [String, bool],
  );

  final Preference cookiesFromBrowser = Preference(
    key: 'cookies_from_browser',
    defaultValue: false,
    allowedTypes: [bool, String],
  );

  final Preference username = Preference(
    key: 'username',
    defaultValue: '',
    allowedTypes: [String],
  );

  final Preference password = Preference(
    key: 'password',
    defaultValue: '',
    allowedTypes: [String],
  );

  final Preference twoFactor = Preference(
    key: 'twofactor',
    defaultValue: '',
    allowedTypes: [String],
  );

  final Preference videoPassword = Preference(
    key: 'video_password',
    defaultValue: '',
    allowedTypes: [String],
  );

  // Video Selection ---------------------------------------------------------
  final Preference videoMultistreams = Preference(
    key: 'video_multistreams',
    defaultValue: true,
    allowedTypes: [bool],
  );

  final Preference audioMultistreams = Preference(
    key: 'audio_multistreams',
    defaultValue: true,
    allowedTypes: [bool],
  );

  final Preference mergeOutputFormat = Preference(
    key: 'merge_output_format',
    defaultValue: 'mkv',
    allowedTypes: [String],
  );

  final Preference audioFormat = Preference(
    key: 'audio_format',
    defaultValue: 'best',
    allowedTypes: [String],
  );

  final Preference extractAudio = Preference(
    key: 'extract_audio',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference audioQuality = Preference(
    key: 'audio_quality',
    defaultValue: 0,
    allowedTypes: [int],
  );

  final Preference remuxVideo = Preference(
    key: 'remux_video',
    defaultValue: false,
    allowedTypes: [String, bool],
  );

  final Preference embedSubs = Preference(
    key: 'embed_subs',
    defaultValue: true,
    allowedTypes: [bool],
  );

  final Preference embedThumbnail = Preference(
    key: 'embed_thumbnail',
    defaultValue: true,
    allowedTypes: [bool],
  );

  final Preference embedMetadata = Preference(
    key: 'embed_metadata',
    defaultValue: true,
    allowedTypes: [bool],
  );

  final Preference embedChapters = Preference(
    key: 'embed_chapters',
    defaultValue: true,
    allowedTypes: [bool],
  );

  final Preference embedInfoJson = Preference(
    key: 'embed_info_json',
    defaultValue: true,
    allowedTypes: [bool],
  );

  final Preference format = Preference(
    key: 'format',
    defaultValue: const <String>['bestvideo+bestaudio', 'best'],
    allowedTypes: [List<String>, String],
  );

  final Preference xattrs = Preference(
    key: 'xattrs',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference fixup = Preference(
    key: 'fixup',
    defaultValue: 'force',
    allowedTypes: [String],
  );

  final Preference ffmpegLocation = Preference(
    key: 'ffmpeg_location',
    defaultValue: () => Preferences._ffmpegDefaultSnapshot(),
    allowedTypes: [String],
  );

  final Preference convertThumbnails = Preference(
    key: 'convert_thumbnails',
    defaultValue: 'webp',
    allowedTypes: [String],
  );

  final Preference writeSubs = Preference(
    key: 'write_subs',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference writeAutoSubs = Preference(
    key: 'write_auto_subs',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference subFormat = Preference(
    key: 'sub_format',
    defaultValue: 'srt',
    allowedTypes: [String],
  );

  final Preference subLangs = Preference(
    key: 'sub_langs',
    defaultValue: const <String>[],
    allowedTypes: [List<String>],
  );

  // Download Options --------------------------------------------------------
  final Preference output = Preference(
    key: 'output',
    defaultValue: ['title', '-', 'artist', '[', 'id', ']', '.', 'ext'],
    allowedTypes: [List<String>],
  );

  final Preference paths = Preference(
    key: 'paths',
    defaultValue: () => Preferences._pathsDefaultSnapshot(),
    allowedTypes: [Map<String, String>],
  );

  final Preference downloadArchive = Preference(
    key: 'download_archive',
    defaultValue: false,
    allowedTypes: [String, bool],
  );

  final Preference playlist = Preference(
    key: 'playlist',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference concurrentFragments = Preference(
    key: 'concurrent_fragments',
    defaultValue: 1,
    allowedTypes: [int],
  );

  final Preference breakOnExisting = Preference(
    key: 'break_on_existing',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference skipPlaylistAfterErrors = Preference(
    key: 'skip_playlist_after_errors',
    defaultValue: false,
    allowedTypes: [int, bool],
  );

  final Preference retries = Preference(
    key: 'retries',
    defaultValue: 10,
    allowedTypes: [int, String],
  );

  final Preference fileAccessRetries = Preference(
    key: 'file_access_retries',
    defaultValue: 5,
    allowedTypes: [int, String],
  );

  final Preference fragmentRetries = Preference(
    key: 'fragment_retries',
    defaultValue: 10,
    allowedTypes: [int, String],
  );

  final Preference extractorRetries = Preference(
    key: 'extractor_retries',
    defaultValue: 3,
    allowedTypes: [int, String],
  );

  final Preference abortOnUnavailableFragments = Preference(
    key: 'abort_on_unavailable_fragments',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference keepFragments = Preference(
    key: 'keep_fragments',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference batchFile = Preference(
    key: 'batch_file',
    defaultValue: false,
    allowedTypes: [String, bool],
  );

  final Preference forceOverwrites = Preference(
    key: 'force_overwrites',
    defaultValue: true,
    allowedTypes: [bool],
  );

  final Preference writeThumbnail = Preference(
    key: 'write_thumbnail',
    defaultValue: false,
    allowedTypes: [bool],
  );

  final Preference sponsorblockMark = Preference(
    key: 'sponsorblock_mark',
    defaultValue: const <String>[
      'sponsor',
      'intro',
      'outro',
      'selfpromo',
      'preview',
      'filler',
      'interaction',
      'music_offtopic',
      'hook',
      'poi_highlight',
      'chapter',
    ],
    allowedTypes: [List<String>, String],
  );

  final Preference sponsorblockRemove = Preference(
    key: 'sponsorblock_remove',
    defaultValue: const <String>[],
    allowedTypes: [List<String>, String],
  );

  final Preference limitRate = Preference(
    key: 'limit_rate',
    defaultValue: '',
    allowedTypes: [String],
  );

  Iterable<Preference> get allPreferences => [
    // Magic
    audioLanguage,
    videoResolution,
    videoSubtitles,
    // General
    isDarkTheme,
    language,
    fontSize,
    ignoreErrors,
    abortOnError,
    useExtractors,
    liveFromStart,
    waitForVideo,
    // Network
    proxy,
    socketTimeout,
    sourceAddress,
    impersonate,
    foceIPv4,
    forceIPv6,
    enableFileUrls,
    geoVerificationProxy,
    xff,
    preferInsecure,
    addHeaders,
    cookies,
    cookiesFromBrowser,
    username,
    password,
    twoFactor,
    videoPassword,
    // Video
    videoMultistreams,
    audioMultistreams,
    mergeOutputFormat,
    audioFormat,
    extractAudio,
    audioQuality,
    remuxVideo,
    embedSubs,
    embedThumbnail,
    embedMetadata,
    embedChapters,
    embedInfoJson,
    format,
    xattrs,
    fixup,
    ffmpegLocation,
    convertThumbnails,
    writeSubs,
    writeAutoSubs,
    subFormat,
    subLangs,
    // Download
    output,
    paths,
    downloadArchive,
    playlist,
    concurrentFragments,
    breakOnExisting,
    skipPlaylistAfterErrors,
    retries,
    fileAccessRetries,
    fragmentRetries,
    extractorRetries,
    abortOnUnavailableFragments,
    keepFragments,
    batchFile,
    forceOverwrites,
    writeThumbnail,
    sponsorblockMark,
    sponsorblockRemove,
    limitRate,
  ];

  Map<String, dynamic> toBackendOptions({Set<String> excludeKeys = const {}}) {
    final payload = <String, dynamic>{};
    for (final preference in allPreferences) {
      if (excludeKeys.contains(preference.key)) {
        continue;
      }
      final normalized = _normalizePreferenceValue(
        preference.key,
        preference.get('value'),
      );
      if (identical(normalized, _skipBackendValue)) {
        continue;
      }
      payload[preference.key] = normalized;
    }
    return payload;
  }

  Object? _normalizePreferenceValue(String key, Object? value) {
    switch (key) {
      case 'download_archive':
        return _normalizeDownloadArchive(value);
      case 'format':
        return _normalizeFormatPreference(value);
      case 'output':
        return _normalizeOutputTemplate(value);
      default:
        return _cloneValue(value);
    }
  }

  Object? _normalizeDownloadArchive(Object? value) {
    if (value == null) {
      return _skipBackendValue;
    }
    if (value is bool) {
      return _skipBackendValue;
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return _skipBackendValue;
    }
    return text;
  }

  Object? _normalizeFormatPreference(Object? value) {
    if (value == null) {
      return _skipBackendValue;
    }
    if (value is List) {
      final parts = value
          .map((entry) => entry?.toString().trim())
          .whereType<String>()
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
      if (parts.isEmpty) {
        return _skipBackendValue;
      }
      return parts.join('/');
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return _skipBackendValue;
    }
    return text;
  }

  Object? _normalizeOutputTemplate(Object? value) {
    if (value == null) {
      return _skipBackendValue;
    }
    if (value is List) {
      final encoded = _encodeOutputTemplate(value);
      return encoded ?? _skipBackendValue;
    }
    final text = value.toString();
    if (text.trim().isEmpty) {
      return _skipBackendValue;
    }
    return text;
  }

  String? _encodeOutputTemplate(List<Object?> segments) {
    if (segments.isEmpty) {
      return null;
    }
    final buffer = StringBuffer();
    for (final entry in segments) {
      if (entry == null) {
        continue;
      }
      final text = entry.toString();
      if (text.isEmpty) {
        continue;
      }
      if (_outputPlaceholderTokens.contains(text)) {
        buffer
          ..write('%(')
          ..write(text)
          ..write(')s');
      } else {
        buffer.write(text);
      }
    }
    final template = buffer.toString();
    return template.isEmpty ? null : template;
  }

  Object? _cloneValue(Object? value) {
    if (value is Map) {
      return value.map((key, dynamic v) => MapEntry('$key', _cloneValue(v)));
    }
    if (value is List) {
      return value.map(_cloneValue).toList();
    }
    return value;
  }

  Future<void> initializeAll(
    SharedPreferences storage, {
    Map<String, PreferenceLocalization>? localizedPreferences,
  }) async {
    if (localizedPreferences != null && localizedPreferences.isNotEmpty) {
      _applyLocalizedPreferences(localizedPreferences);
    }
    await _ensurePathsDefaultResolved();
    await _ensureFfmpegDefaultResolved();
    await Future.wait(allPreferences.map((pref) => pref.initialize(storage)));
    await _initializeBundledFfmpegPreference();
  }

  void _applyLocalizedPreferences(
    Map<String, PreferenceLocalization> localizedPreferences,
  ) {
    for (final preference in allPreferences) {
      final localization = localizedPreferences[preference.key];
      if (localization == null) {
        continue;
      }
      preference.applyLocalization(
        nameTexts: localization.names,
        descriptionTexts: localization.descriptions,
      );
    }
  }

  Future<String?> ensurePathsHomeEntry() async {
    final rawValue = paths.get('value');
    Map<String, String> currentValues;
    if (rawValue is Map<String, String>) {
      currentValues = Map<String, String>.from(rawValue);
    } else if (rawValue is Map) {
      currentValues = rawValue.map((key, value) {
        final normalizedKey = key?.toString() ?? '';
        final normalizedValue = value == null ? '' : value.toString();
        return MapEntry(normalizedKey, normalizedValue);
      }).cast<String, String>();
    } else {
      currentValues = <String, String>{};
    }
    final existingHome = currentValues['home'];
    if (_isValidPath(existingHome)) {
      return existingHome!.trim();
    }

    await _ensurePathsDefaultResolved();
    final cachedDefault = _pathsDefaultValue?['home'];
    final resolvedPath = cachedDefault ?? await _resolveDownloadsDirectory();
    final normalized = _sanitizePath(resolvedPath);
    if (normalized == null) {
      return null;
    }

    currentValues['home'] = normalized;
    await paths.setValue(currentValues);
    _pathsDefaultValue = <String, String>{
      if (_pathsDefaultValue != null) ..._pathsDefaultValue!,
      'home': normalized,
    };
    return normalized;
  }

  Future<bool> ensureOutputTemplateSegments() async {
    final currentSegments = _extractOutputSegments(output.get('value'));
    if (currentSegments.isNotEmpty) {
      return false;
    }
    final fallbackSegments = List<String>.from(
      output.getDefaultValue<List<String>>(),
    );
    await output.setValue(fallbackSegments);
    return true;
  }

  Future<void> _initializeBundledFfmpegPreference() async {
    if (!Platform.isAndroid && !Platform.isWindows && !Platform.isLinux) {
      return;
    }

    final currentValue = ffmpegLocation.get('value');
    final normalizedCurrent = currentValue is String ? currentValue.trim() : '';
    if (normalizedCurrent.isNotEmpty) {
      return;
    }

    final cached = _ffmpegDefaultValue;
    final defaultValue = cached != null && cached.trim().isNotEmpty
        ? cached
        : await _resolveFfmpegDefaultPath();
    if (defaultValue.trim().isEmpty) {
      return;
    }
    await ffmpegLocation.setValue(defaultValue);
    if (kDebugMode) {
      debugPrint('ffmpeg_location preference seteado (init): $defaultValue');
    }
  }

  Future<String?> ensureBundledFfmpegLocation() async {
    final currentValue = ffmpegLocation.get('value');
    final normalizedCurrent = currentValue is String ? currentValue.trim() : '';
    if (!Platform.isAndroid && !Platform.isWindows && !Platform.isLinux) {
      return normalizedCurrent.isEmpty ? null : normalizedCurrent;
    }

    await _ensureFfmpegDefaultResolved();
    final resolved = await _resolveFfmpegDefaultPath();
    if (resolved.trim().isNotEmpty) {
      if (resolved.trim() != normalizedCurrent) {
        await ffmpegLocation.setValue(resolved);
      }
      if (kDebugMode) {
        debugPrint('ffmpeg_location preference seteado (ensure): $resolved');
      }
      return resolved;
    }

    final cached = _ffmpegDefaultValue;
    if (cached != null && cached.trim().isNotEmpty) {
      if (cached.trim() != normalizedCurrent) {
        await ffmpegLocation.setValue(cached);
      }
      if (kDebugMode) {
        debugPrint(
          'ffmpeg_location preference seteado (ensure-cache): $cached',
        );
      }
      return cached;
    }

    return normalizedCurrent.isEmpty ? null : normalizedCurrent;
  }

  Future<String?> ensureAndroidFfmpegLocation() async {
    return ensureBundledFfmpegLocation();
  }

  static Map<String, String> _pathsDefaultSnapshot() {
    final cached = _pathsDefaultValue;
    if (cached == null || cached.isEmpty) {
      return const <String, String>{};
    }
    return Map<String, String>.from(cached);
  }

  static String _ffmpegDefaultSnapshot() {
    final cached = _ffmpegDefaultValue;
    if (cached == null || cached.isEmpty) {
      return '';
    }
    return cached;
  }

  static Future<void> _ensurePathsDefaultResolved() {
    final ongoing = _pathsDefaultInitialization;
    if (ongoing != null) {
      return ongoing;
    }
    final future = _computePathsDefault();
    _pathsDefaultInitialization = future;
    return future;
  }

  static Future<void> _ensureFfmpegDefaultResolved() {
    final ongoing = _ffmpegDefaultInitialization;
    if (ongoing != null) {
      return ongoing;
    }
    final future = _computeFfmpegDefault();
    _ffmpegDefaultInitialization = future;
    return future;
  }

  static Future<void> _computeFfmpegDefault() async {
    _ffmpegDefaultValue = await _resolveFfmpegDefaultPath();
  }

  static Future<void> _computePathsDefault() async {
    _pathsDefaultValue = await _buildPathsDefaultMap();
  }

  static Future<Map<String, String>> _buildPathsDefaultMap() async {
    final downloadsPath = await _resolveDownloadsDirectory();
    if (downloadsPath == null) {
      return const <String, String>{};
    }
    return <String, String>{'home': downloadsPath};
  }

  static Future<String?> _resolveDownloadsDirectory() async {
    final platformPath = await _resolvePlatformDownloadsDirectory();
    if (platformPath != null) {
      final sanitized = _sanitizePath(platformPath);
      if (sanitized != null) {
        return sanitized;
      }
    }
    final fallback = _fallbackDownloadsPath();
    return _sanitizePath(fallback);
  }

  static Future<String> _resolveFfmpegDefaultPath() async {
    if (Platform.isAndroid) {
      final androidPath = await _resolveAndroidFfmpegPath();
      if (androidPath != null) {
        return androidPath;
      }
    }
    if (Platform.isWindows) {
      final windowsPath = await _resolveWindowsFfmpegPath();
      if (windowsPath != null) {
        return windowsPath;
      }
    }
    if (Platform.isLinux) {
      final linuxPath = await _resolveLinuxFfmpegPath();
      if (linuxPath != null) {
        return linuxPath;
      }
    }
    return '';
  }

  static Future<String?> _resolveAndroidFfmpegPath() async {
    try {
      final dir = await _nativeChannel.invokeMethod<String>('getNativeLibDir');
      if (dir == null || dir.trim().isEmpty) {
        return null;
      }
      return p.join(dir, 'libffmpeg.so');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _resolveWindowsFfmpegPath() async {
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidate = p.join(exeDir, 'ffmpeg.exe');
      final exists = await File(candidate).exists();
      if (!exists && kDebugMode) {
        debugPrint('ffmpeg no encontrado en "$candidate"; omitiendo');
      }
      return exists ? candidate : null;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error resolviendo ffmpeg en Windows; omitiendo: $error');
      }
      return null;
    }
  }

  static Future<String?> _resolveLinuxFfmpegPath() async {
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidate = p.join(exeDir, 'ffmpeg');
      final exists = await File(candidate).exists();
      if (!exists && kDebugMode) {
        debugPrint('ffmpeg no encontrado en "$candidate"; omitiendo');
      }
      return exists ? candidate : null;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error resolviendo ffmpeg en Linux; omitiendo: $error');
      }
      return null;
    }
  }

  static Future<String?> _resolvePlatformDownloadsDirectory() async {
    try {
      if (Platform.isAndroid) {
        return await ExternalPath.getExternalStoragePublicDirectory(
          ExternalPath.DIRECTORY_DOWNLOAD,
        );
      }
      if (Platform.isIOS) {
        final directory = await getApplicationDocumentsDirectory();
        return directory.path;
      }
      final downloadsDirectory = await getDownloadsDirectory();
      return downloadsDirectory?.path;
    } catch (_) {
      return null;
    }
  }

  static String? _fallbackDownloadsPath() {
    try {
      final home = Platform.isWindows
          ? Platform.environment['USERPROFILE']
          : Platform.environment['HOME'];
      if (home == null || home.isEmpty) {
        return null;
      }
      return p.join(home, 'Downloads');
    } catch (_) {
      return null;
    }
  }

  static String? _sanitizePath(String? rawPath) {
    if (rawPath == null) {
      return null;
    }
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return p.normalize(trimmed);
  }

  static bool _isValidPath(Object? value) {
    return value is String && value.trim().isNotEmpty;
  }

  static List<String> _extractOutputSegments(Object? rawValue) {
    if (rawValue is List) {
      return rawValue
          .where((segment) => segment != null)
          .map((segment) => segment.toString())
          .where((segment) => segment.trim().isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }
}
