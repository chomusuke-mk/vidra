import 'package:flutter/foundation.dart';

// ============================================================================
// ENUMS DE TIPADO
// ============================================================================

// ignore_for_file: curly_braces_in_flow_control_structures, constant_identifier_names

enum AudioOption { defaultOption, bestaudio, language }

enum VideoOption { defaultOption, bestvideo, resolution }

enum JsRuntime { deno, node, quickjs, bun }

enum Browser {
  brave,
  chrome,
  chromium,
  edge,
  firefox,
  opera,
  safari,
  vivaldi,
  whale,
}

enum MergeOutputFormat { avi, flv, mkv, mov, mp4, webm }

enum AudioFormat { best, aac, alac, flac, m4a, mp3, opus, vorbis, wav }

enum RemuxVideoFormat {
  avi,
  flv,
  gif,
  mkv,
  mov,
  mp4,
  webm,
  aac,
  aiff,
  alac,
  flac,
  m4a,
  mka,
  mp3,
  ogg,
  opus,
  vorbis,
  wav,
}

enum FixupOption { never, warn, detect_or_warn, force }

enum ThumbnailFormat { jpg, png, webp }

enum SubtitleFormat { ass, srt, vtt, json }

enum PathsKey {
  home,
  video,
  audio,
  subtitle,
  thumbnail,
  infojson,
  pl_thumbnail,
  description,
  annotation,
  chapter,
  sponsor,
}

enum SponsorblockCategory {
  sponsor,
  intro,
  outro,
  selfpromo,
  preview,
  filler,
  interaction,
  music_offtopic,
  hook,
  poi_highlight,
  chapter,
}

// Helpers para parseo seguro de Enums
T? _enumFromString<T extends Enum>(List<T> values, String? name) {
  if (name == null || name.isEmpty) return null;
  final cleanName = name.replaceAll('_', '').toLowerCase();
  for (final val in values) {
    if (val.name.toLowerCase() == name.toLowerCase() ||
        val.name.replaceAll('_', '').toLowerCase() == cleanName) {
      return val;
    }
  }
  return null;
}

// ============================================================================
// CLASE PRINCIPAL
// ============================================================================

class DownloadOptions {
  // --- General Options ---
  final VideoOption videoResolution;
  final String? videoResolutionValue;
  final AudioOption audioLanguage;
  final String? audioLanguageCode;
  final List<String> subLangs;
  final bool extractAudio;
  final bool playlist;
  final List<SponsorblockCategory> sponsorblockMark;
  final List<SponsorblockCategory> sponsorblockRemove;
  final bool cutVideo;
  final int cutVideoStart;
  final bool cutVideoUntilEnd;
  final int cutVideoEnd;

  // --- Network Options ---
  final String proxy;
  final int? socketTimeout;
  final bool infiniteSocketTimeout;
  final String sourceAddress;
  final String impersonate;
  final bool forceIpv4;
  final bool forceIpv6;
  final bool enableFileUrls;
  final String geoVerificationProxy;
  final String xff;
  final bool preferInsecure;
  final Map<String, String> addHeaders;
  final String? cookies;
  final bool disableCookies;
  final Browser? cookiesFromBrowser;
  final bool disableCookiesFromBrowser;
  final String? cookiesFromWebview;
  final bool disableCookiesFromWebview;
  final String username;
  final String password;
  final String twofactor;
  final String videoPassword;

  // --- Video Options ---
  final MergeOutputFormat mergeOutputFormat;
  final AudioFormat audioFormat;
  final SubtitleFormat subFormat;
  final bool videoMultistreams;
  final bool audioMultistreams;
  final int audioQuality;
  final RemuxVideoFormat? remuxVideo;
  final bool disableRemuxVideo;
  final bool embedSubs;
  final bool embedThumbnail;
  final bool embedMetadata;
  final bool embedChapters;
  final bool embedInfoJson;
  final String format;
  final bool xattrs;
  final FixupOption fixup;
  final bool forceKeyframesAtCuts;
  final String ffmpegLocation;
  final ThumbnailFormat convertThumbnails;
  final bool writeSubs;
  final bool writeAutoSubs;

  // --- Download Options ---
  final List<String> output;
  final Map<PathsKey, String> paths;
  final String? downloadArchive;
  final bool disableDownloadArchive;
  final int concurrentFragments;
  final bool breakOnExisting;
  final bool windowsFilenames;
  final bool abortOnUnavailableFragments;
  final bool keepFragments;
  final bool forceOverwrites;
  final bool writeThumbnail;
  final bool liveFromStart;
  final int? waitForVideo;
  final bool disableWaitForVideo;
  final bool markWatched;
  final Map<JsRuntime, String> jsRuntimes;
  final int? skipPlaylistAfterErrors;
  final bool infiniteSkipPlaylistAfterErrors;
  final int? retries;
  final bool infiniteRetries;
  final int? fileAccessRetries;
  final bool infiniteFileAccessRetries;
  final int? fragmentRetries;
  final bool infiniteFragmentRetries;
  final int? extractorRetries;
  final bool infiniteExtractorRetries;
  final String? limitRate;
  final bool disableLimitRate;

  // Constructor con defaults
  DownloadOptions({
    // General
    this.videoResolution = VideoOption.resolution,
    this.videoResolutionValue = '1080',
    this.audioLanguage = AudioOption.bestaudio,
    this.audioLanguageCode,
    this.subLangs = const [],
    this.extractAudio = false,
    this.playlist = false,
    this.sponsorblockMark = const [],
    this.sponsorblockRemove = const [],
    this.cutVideo = false,
    this.cutVideoStart = 0,
    this.cutVideoUntilEnd = true,
    this.cutVideoEnd = 0,

    // Network
    this.proxy = '',
    this.socketTimeout,
    this.infiniteSocketTimeout = true, // Python: "infinite"
    this.sourceAddress = '',
    this.impersonate = '',
    this.forceIpv4 = false,
    this.forceIpv6 = false,
    this.enableFileUrls = false,
    this.geoVerificationProxy = '',
    this.xff = '',
    this.preferInsecure = false,
    this.addHeaders = const {},
    this.cookies,
    this.disableCookies = true, // Python: false
    this.cookiesFromBrowser,
    this.disableCookiesFromBrowser = true, // Python: false
    this.cookiesFromWebview,
    this.disableCookiesFromWebview = false, // Python: true
    this.username = '',
    this.password = '',
    this.twofactor = '',
    this.videoPassword = '',

    // Video
    this.mergeOutputFormat = MergeOutputFormat.mkv,
    this.audioFormat = AudioFormat.best,
    this.subFormat = SubtitleFormat.srt,
    this.videoMultistreams = true,
    this.audioMultistreams = true,
    this.audioQuality = 0,
    this.remuxVideo,
    this.disableRemuxVideo = true, // Python: false
    this.embedSubs = true,
    this.embedThumbnail = true,
    this.embedMetadata = true,
    this.embedChapters = true,
    this.embedInfoJson = true,
    this.format = '',
    this.xattrs = false,
    this.fixup = FixupOption.force,
    this.forceKeyframesAtCuts = true,
    this.ffmpegLocation = '',
    this.convertThumbnails = ThumbnailFormat.webp,
    this.writeSubs = false,
    this.writeAutoSubs = false,

    // Download
    this.output = const ["title", ".", "ext"],
    this.paths = const {},
    this.downloadArchive,
    this.disableDownloadArchive = true, // Python: false
    this.concurrentFragments = 1,
    this.breakOnExisting = false,
    this.windowsFilenames = true,
    this.abortOnUnavailableFragments = false,
    this.keepFragments = false,
    this.forceOverwrites = false,
    this.writeThumbnail = false,
    this.liveFromStart = true,
    this.waitForVideo,
    this.disableWaitForVideo = true, // Python: false = disabled wait
    this.markWatched = false,
    this.jsRuntimes = const {},
    this.skipPlaylistAfterErrors,
    this.infiniteSkipPlaylistAfterErrors = true, // Python: "infinite"
    this.retries = 10,
    this.infiniteRetries = false,
    this.fileAccessRetries = 3,
    this.infiniteFileAccessRetries = false,
    this.fragmentRetries = 10,
    this.infiniteFragmentRetries = false,
    this.extractorRetries = 3,
    this.infiniteExtractorRetries = false,
    this.limitRate,
    this.disableLimitRate = true, // Python: false
  });

  // ==========================================================================
  // COPY WITH (Para actualizar campos inmutables)
  // ==========================================================================
  DownloadOptions copyWith({
    VideoOption? videoResolution,
    String? videoResolutionValue,
    AudioOption? audioLanguage,
    String? audioLanguageCode,
    List<String>? subLangs,
    bool? extractAudio,
    bool? playlist,
    List<SponsorblockCategory>? sponsorblockMark,
    List<SponsorblockCategory>? sponsorblockRemove,
    bool? cutVideo,
    int? cutVideoStart,
    bool? cutVideoUntilEnd,
    int? cutVideoEnd,
    String? proxy,
    int? socketTimeout,
    bool? infiniteSocketTimeout,
    String? sourceAddress,
    String? impersonate,
    bool? forceIpv4,
    bool? forceIpv6,
    bool? enableFileUrls,
    String? geoVerificationProxy,
    String? xff,
    bool? preferInsecure,
    Map<String, String>? addHeaders,
    String? cookies,
    bool? disableCookies,
    Browser? cookiesFromBrowser,
    bool? disableCookiesFromBrowser,
    String? cookiesFromWebview,
    bool? disableCookiesFromWebview,
    String? username,
    String? password,
    String? twofactor,
    String? videoPassword,
    MergeOutputFormat? mergeOutputFormat,
    AudioFormat? audioFormat,
    SubtitleFormat? subFormat,
    bool? videoMultistreams,
    bool? audioMultistreams,
    int? audioQuality,
    RemuxVideoFormat? remuxVideo,
    bool? disableRemuxVideo,
    bool? embedSubs,
    bool? embedThumbnail,
    bool? embedMetadata,
    bool? embedChapters,
    bool? embedInfoJson,
    String? format,
    bool? xattrs,
    FixupOption? fixup,
    bool? forceKeyframesAtCuts,
    String? ffmpegLocation,
    ThumbnailFormat? convertThumbnails,
    bool? writeSubs,
    bool? writeAutoSubs,
    List<String>? output,
    Map<PathsKey, String>? paths,
    String? downloadArchive,
    bool? disableDownloadArchive,
    int? concurrentFragments,
    bool? breakOnExisting,
    bool? windowsFilenames,
    bool? abortOnUnavailableFragments,
    bool? keepFragments,
    bool? forceOverwrites,
    bool? writeThumbnail,
    bool? liveFromStart,
    int? waitForVideo,
    bool? disableWaitForVideo,
    bool? markWatched,
    Map<JsRuntime, String>? jsRuntimes,
    int? skipPlaylistAfterErrors,
    bool? infiniteSkipPlaylistAfterErrors,
    int? retries,
    bool? infiniteRetries,
    int? fileAccessRetries,
    bool? infiniteFileAccessRetries,
    int? fragmentRetries,
    bool? infiniteFragmentRetries,
    int? extractorRetries,
    bool? infiniteExtractorRetries,
    String? limitRate,
    bool? disableLimitRate,
  }) {
    return DownloadOptions(
      videoResolution: videoResolution ?? this.videoResolution,
      videoResolutionValue: videoResolutionValue ?? this.videoResolutionValue,
      audioLanguage: audioLanguage ?? this.audioLanguage,
      audioLanguageCode: audioLanguageCode ?? this.audioLanguageCode,
      subLangs: subLangs ?? this.subLangs,
      extractAudio: extractAudio ?? this.extractAudio,
      playlist: playlist ?? this.playlist,
      sponsorblockMark: sponsorblockMark ?? this.sponsorblockMark,
      sponsorblockRemove: sponsorblockRemove ?? this.sponsorblockRemove,
      cutVideo: cutVideo ?? this.cutVideo,
      cutVideoStart: cutVideoStart ?? this.cutVideoStart,
      cutVideoUntilEnd: cutVideoUntilEnd ?? this.cutVideoUntilEnd,
      cutVideoEnd: cutVideoEnd ?? this.cutVideoEnd,
      proxy: proxy ?? this.proxy,
      socketTimeout: socketTimeout ?? this.socketTimeout,
      infiniteSocketTimeout:
          infiniteSocketTimeout ?? this.infiniteSocketTimeout,
      sourceAddress: sourceAddress ?? this.sourceAddress,
      impersonate: impersonate ?? this.impersonate,
      forceIpv4: forceIpv4 ?? this.forceIpv4,
      forceIpv6: forceIpv6 ?? this.forceIpv6,
      enableFileUrls: enableFileUrls ?? this.enableFileUrls,
      geoVerificationProxy: geoVerificationProxy ?? this.geoVerificationProxy,
      xff: xff ?? this.xff,
      preferInsecure: preferInsecure ?? this.preferInsecure,
      addHeaders: addHeaders ?? this.addHeaders,
      cookies: cookies ?? this.cookies,
      disableCookies: disableCookies ?? this.disableCookies,
      cookiesFromBrowser: cookiesFromBrowser ?? this.cookiesFromBrowser,
      disableCookiesFromBrowser:
          disableCookiesFromBrowser ?? this.disableCookiesFromBrowser,
      cookiesFromWebview: cookiesFromWebview ?? this.cookiesFromWebview,
      disableCookiesFromWebview:
          disableCookiesFromWebview ?? this.disableCookiesFromWebview,
      username: username ?? this.username,
      password: password ?? this.password,
      twofactor: twofactor ?? this.twofactor,
      videoPassword: videoPassword ?? this.videoPassword,
      mergeOutputFormat: mergeOutputFormat ?? this.mergeOutputFormat,
      audioFormat: audioFormat ?? this.audioFormat,
      subFormat: subFormat ?? this.subFormat,
      videoMultistreams: videoMultistreams ?? this.videoMultistreams,
      audioMultistreams: audioMultistreams ?? this.audioMultistreams,
      audioQuality: audioQuality ?? this.audioQuality,
      remuxVideo: remuxVideo ?? this.remuxVideo,
      disableRemuxVideo: disableRemuxVideo ?? this.disableRemuxVideo,
      embedSubs: embedSubs ?? this.embedSubs,
      embedThumbnail: embedThumbnail ?? this.embedThumbnail,
      embedMetadata: embedMetadata ?? this.embedMetadata,
      embedChapters: embedChapters ?? this.embedChapters,
      embedInfoJson: embedInfoJson ?? this.embedInfoJson,
      format: format ?? this.format,
      xattrs: xattrs ?? this.xattrs,
      fixup: fixup ?? this.fixup,
      forceKeyframesAtCuts: forceKeyframesAtCuts ?? this.forceKeyframesAtCuts,
      ffmpegLocation: ffmpegLocation ?? this.ffmpegLocation,
      convertThumbnails: convertThumbnails ?? this.convertThumbnails,
      writeSubs: writeSubs ?? this.writeSubs,
      writeAutoSubs: writeAutoSubs ?? this.writeAutoSubs,
      output: output ?? this.output,
      paths: paths ?? this.paths,
      downloadArchive: downloadArchive ?? this.downloadArchive,
      disableDownloadArchive:
          disableDownloadArchive ?? this.disableDownloadArchive,
      concurrentFragments: concurrentFragments ?? this.concurrentFragments,
      breakOnExisting: breakOnExisting ?? this.breakOnExisting,
      windowsFilenames: windowsFilenames ?? this.windowsFilenames,
      abortOnUnavailableFragments:
          abortOnUnavailableFragments ?? this.abortOnUnavailableFragments,
      keepFragments: keepFragments ?? this.keepFragments,
      forceOverwrites: forceOverwrites ?? this.forceOverwrites,
      writeThumbnail: writeThumbnail ?? this.writeThumbnail,
      liveFromStart: liveFromStart ?? this.liveFromStart,
      waitForVideo: waitForVideo ?? this.waitForVideo,
      disableWaitForVideo: disableWaitForVideo ?? this.disableWaitForVideo,
      markWatched: markWatched ?? this.markWatched,
      jsRuntimes: jsRuntimes ?? this.jsRuntimes,
      skipPlaylistAfterErrors:
          skipPlaylistAfterErrors ?? this.skipPlaylistAfterErrors,
      infiniteSkipPlaylistAfterErrors:
          infiniteSkipPlaylistAfterErrors ??
          this.infiniteSkipPlaylistAfterErrors,
      retries: retries ?? this.retries,
      infiniteRetries: infiniteRetries ?? this.infiniteRetries,
      fileAccessRetries: fileAccessRetries ?? this.fileAccessRetries,
      infiniteFileAccessRetries:
          infiniteFileAccessRetries ?? this.infiniteFileAccessRetries,
      fragmentRetries: fragmentRetries ?? this.fragmentRetries,
      infiniteFragmentRetries:
          infiniteFragmentRetries ?? this.infiniteFragmentRetries,
      extractorRetries: extractorRetries ?? this.extractorRetries,
      infiniteExtractorRetries:
          infiniteExtractorRetries ?? this.infiniteExtractorRetries,
      limitRate: limitRate ?? this.limitRate,
      disableLimitRate: disableLimitRate ?? this.disableLimitRate,
    );
  }

  // ==========================================================================
  // TO JSON (Para enviar a Python o guardar localmente)
  // ==========================================================================
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};

    // --- General Options ---
    if (videoResolution == VideoOption.defaultOption)
      map['video_resolution'] = 'default';
    else if (videoResolution == VideoOption.bestvideo)
      map['video_resolution'] = 'bestvideo';
    else if (videoResolutionValue != null)
      map['video_resolution'] = videoResolutionValue;

    if (audioLanguage == AudioOption.defaultOption)
      map['audio_language'] = 'default';
    else if (audioLanguage == AudioOption.bestaudio)
      map['audio_language'] = 'bestaudio';
    else if (audioLanguageCode != null)
      map['audio_language'] = audioLanguageCode;

    if (subLangs.isNotEmpty) map['sub_langs'] = subLangs;

    map['extract_audio'] = extractAudio;
    map['playlist'] = playlist;

    if (sponsorblockMark.isNotEmpty)
      map['sponsorblock_mark'] = sponsorblockMark.map((e) => e.name).toList();
    if (sponsorblockRemove.isNotEmpty)
      map['sponsorblock_remove'] = sponsorblockRemove
          .map((e) => e.name)
          .toList();

    if (cutVideo) {
      if (cutVideoUntilEnd) {
        map['cut_video'] = [cutVideoStart, 'inf'];
      } else {
        map['cut_video'] = [cutVideoStart, cutVideoEnd];
      }
    } else {
      map['cut_video'] = false;
    }

    // --- Network Options ---
    if (proxy.isNotEmpty) map['proxy'] = proxy;

    if (infiniteSocketTimeout)
      map['socket_timeout'] = 'infinite';
    else if (socketTimeout != null)
      map['socket_timeout'] = socketTimeout;

    if (sourceAddress.isNotEmpty) map['source_address'] = sourceAddress;
    if (impersonate.isNotEmpty) map['impersonate'] = impersonate;
    map['force_ipv4'] = forceIpv4;
    map['force_ipv6'] = forceIpv6;
    map['enable_file_urls'] = enableFileUrls;
    if (geoVerificationProxy.isNotEmpty)
      map['geo_verification_proxy'] = geoVerificationProxy;
    if (xff.isNotEmpty) map['xff'] = xff;
    map['prefer_insecure'] = preferInsecure;

    if (addHeaders.isNotEmpty) map['add_headers'] = addHeaders;

    if (disableCookies)
      map['cookies'] = false;
    else if (cookies != null && cookies!.isNotEmpty)
      map['cookies'] = cookies;

    if (disableCookiesFromBrowser)
      map['cookies_from_browser'] = false;
    else if (cookiesFromBrowser != null)
      map['cookies_from_browser'] = cookiesFromBrowser!.name;

    if (disableCookiesFromWebview)
      map['cookies_from_webview'] = false;
    else if (cookiesFromWebview != null && cookiesFromWebview!.isNotEmpty)
      map['cookies_from_webview'] = cookiesFromWebview;

    if (username.isNotEmpty) map['username'] = username;
    if (password.isNotEmpty) map['password'] = password;
    if (twofactor.isNotEmpty) map['twofactor'] = twofactor;
    if (videoPassword.isNotEmpty) map['video_password'] = videoPassword;

    // --- Video Options ---
    map['merge_output_format'] = mergeOutputFormat.name;
    map['audio_format'] = audioFormat.name;
    map['sub_format'] = subFormat.name;
    map['video_multistreams'] = videoMultistreams;
    map['audio_multistreams'] = audioMultistreams;
    map['audio_quality'] = audioQuality;

    if (disableRemuxVideo)
      map['remux_video'] = false;
    else if (remuxVideo != null)
      map['remux_video'] = remuxVideo!.name;

    map['embed_subs'] = embedSubs;
    map['embed_thumbnail'] = embedThumbnail;
    map['embed_metadata'] = embedMetadata;
    map['embed_chapters'] = embedChapters;
    map['embed_info_json'] = embedInfoJson;
    if (format.isNotEmpty) map['format'] = format;
    map['xattrs'] = xattrs;
    map['fixup'] = fixup.name;
    map['force_keyframes_at_cuts'] = forceKeyframesAtCuts;
    if (ffmpegLocation.isNotEmpty) map['ffmpeg_location'] = ffmpegLocation;
    map['convert_thumbnails'] = convertThumbnails.name;
    map['write_subs'] = writeSubs;
    map['write_auto_subs'] = writeAutoSubs;

    // --- Download Options ---
    map['output'] = output;

    if (paths.isNotEmpty) {
      map['paths'] = paths.map((k, v) => MapEntry(k.name, v));
    }

    if (disableDownloadArchive)
      map['download_archive'] = false;
    else if (downloadArchive != null && downloadArchive!.isNotEmpty)
      map['download_archive'] = downloadArchive;

    map['concurrent_fragments'] = concurrentFragments;
    map['break_on_existing'] = breakOnExisting;


    map['windows_filenames'] = windowsFilenames;
    map['abort_on_unavailable_fragments'] = abortOnUnavailableFragments;
    map['keep_fragments'] = keepFragments;

    map['force_overwrites'] = forceOverwrites;
    map['write_thumbnail'] = writeThumbnail;
    map['live_from_start'] = liveFromStart;

    if (disableWaitForVideo)
      map['wait_for_video'] = false;
    else if (waitForVideo != null)
      map['wait_for_video'] = waitForVideo;

    map['mark_watched'] = markWatched;

    if (jsRuntimes.isNotEmpty) {
      map['js_runtimes'] = jsRuntimes.map((k, v) => MapEntry(k.name, v));
    }
    _setUnionInfiniteInt(
      map,
      'skip_playlist_after_errors',
      skipPlaylistAfterErrors,
      infiniteSkipPlaylistAfterErrors,
    );
    _setUnionInfiniteInt(map, 'retries', retries, infiniteRetries);
    _setUnionInfiniteInt(
      map,
      'file_access_retries',
      fileAccessRetries,
      infiniteFileAccessRetries,
    );
    _setUnionInfiniteInt(
      map,
      'fragment_retries',
      fragmentRetries,
      infiniteFragmentRetries,
    );
    _setUnionInfiniteInt(
      map,
      'extractor_retries',
      extractorRetries,
      infiniteExtractorRetries,
    );



    if (disableLimitRate)
      map['limit_rate'] = false;
    else if (limitRate != null && limitRate!.isNotEmpty)
      map['limit_rate'] = limitRate;

    return map;
  }

  void _setUnionInfiniteInt(
    Map<String, dynamic> map,
    String key,
    int? value,
    bool isInfinite,
  ) {
    if (isInfinite)
      map[key] = 'infinite';
    else if (value != null)
      map[key] = value;
  }

  // ==========================================================================
  // FROM JSON (Para leer desde SharedPreferences o la red)
  // ==========================================================================
  factory DownloadOptions.fromJson(Map<String, dynamic> json) {
    // Parsers auxiliares para las uniones de String/Enum
    AudioOption pAudioOption = AudioOption.bestaudio;
    String? pAudioCode;
    if (json['audio_language'] == 'default') {
      pAudioOption = AudioOption.defaultOption;
    } else if (json['audio_language'] == 'bestaudio') {
      pAudioOption = AudioOption.bestaudio;
    } else if (json['audio_language'] != null &&
        json['audio_language'] != 'default') {
      pAudioOption = AudioOption.language;
      pAudioCode = json['audio_language'];
    }

    VideoOption pVideoOption = VideoOption.resolution;
    String? pVideoRes = '1080';
    if (json['video_resolution'] == 'default') {
      pVideoOption = VideoOption.defaultOption;
      pVideoRes = null;
    } else if (json['video_resolution'] == 'bestvideo') {
      pVideoOption = VideoOption.bestvideo;
      pVideoRes = null;
    } else if (json['video_resolution'] != null &&
        json['video_resolution'] != 'default') {
      pVideoOption = VideoOption.resolution;
      pVideoRes = json['video_resolution'];
    }
    List<SponsorblockCategory> pSponsorMark = [];
    if (json['sponsorblock_mark'] != null) {
      for (var s in json['sponsorblock_mark']) {
        final cat = _enumFromString(SponsorblockCategory.values, s);
        if (cat != null) pSponsorMark.add(cat);
      }
    }

    List<SponsorblockCategory> pSponsorRemove = [];
    if (json['sponsorblock_remove'] != null) {
      for (var s in json['sponsorblock_remove']) {
        final cat = _enumFromString(SponsorblockCategory.values, s);
        if (cat != null) pSponsorRemove.add(cat);
      }
    }

    bool pCutVideo = false;
    int pCutVideoStart = 0;
    bool pCutVideoUntilEnd = true;
    int pCutVideoEnd = 0;

    final rawCutVideo = json['cut_video'];
    if (rawCutVideo is List && rawCutVideo.length >= 2) {
      pCutVideo = true;
      final startVal = rawCutVideo[0];
      if (startVal is int) {
        pCutVideoStart = startVal;
      } else if (startVal != null) {
        pCutVideoStart = int.tryParse(startVal.toString()) ?? 0;
      }
      final endVal = rawCutVideo[1];
      if (endVal == 'inf' || endVal == 'infinite') {
        pCutVideoUntilEnd = true;
        pCutVideoEnd = 0;
      } else if (endVal is int) {
        pCutVideoUntilEnd = false;
        pCutVideoEnd = endVal;
      } else if (endVal != null) {
        final parsedEnd = int.tryParse(endVal.toString());
        if (parsedEnd != null) {
          pCutVideoUntilEnd = false;
          pCutVideoEnd = parsedEnd;
        } else {
          pCutVideoUntilEnd = true;
          pCutVideoEnd = 0;
        }
      }
    }

    Map<JsRuntime, String> pJsRuntimes = {};
    if (json['js_runtimes'] != null) {
      (json['js_runtimes'] as Map<String, dynamic>).forEach((k, v) {
        final key = _enumFromString(JsRuntime.values, k);
        if (key != null) pJsRuntimes[key] = v.toString();
      });
    }

    Map<PathsKey, String> pPaths = {};
    if (json['paths'] != null) {
      (json['paths'] as Map<String, dynamic>).forEach((k, v) {
        final key = _enumFromString(PathsKey.values, k);
        if (key != null) pPaths[key] = v.toString();
      });
    }


    return DownloadOptions(
      // General
      videoResolution: pVideoOption,
      videoResolutionValue: pVideoRes,
      audioLanguage: pAudioOption,
      audioLanguageCode: pAudioCode,
      subLangs: json['sub_langs'] != null
          ? List<String>.from(json['sub_langs'])
          : [],
      extractAudio: json['extract_audio'] == true,
      playlist: json['playlist'] == true,
      sponsorblockMark: pSponsorMark,
      sponsorblockRemove: pSponsorRemove,
      cutVideo: pCutVideo,
      cutVideoStart: pCutVideoStart,
      cutVideoUntilEnd: pCutVideoUntilEnd,
      cutVideoEnd: pCutVideoEnd,

      // Network
      proxy: json['proxy']?.toString() ?? '',
      socketTimeout: json['socket_timeout'] is int
          ? json['socket_timeout']
          : null,
      infiniteSocketTimeout: json['socket_timeout'] == 'infinite',
      sourceAddress: json['source_address']?.toString() ?? '',
      impersonate: json['impersonate']?.toString() ?? '',
      forceIpv4: json['force_ipv4'] == true,
      forceIpv6: json['force_ipv6'] == true,
      enableFileUrls: json['enable_file_urls'] == true,
      geoVerificationProxy: json['geo_verification_proxy']?.toString() ?? '',
      xff: json['xff']?.toString() ?? '',
      preferInsecure: json['prefer_insecure'] == true,
      addHeaders: json['add_headers'] != null
          ? Map<String, String>.from(json['add_headers'])
          : {},
      cookies: json['cookies'] is String ? json['cookies'] : null,
      disableCookies: json['cookies'] == false,
      cookiesFromBrowser: _enumFromString(
        Browser.values,
        json['cookies_from_browser'] is String
            ? json['cookies_from_browser']
            : null,
      ),
      disableCookiesFromBrowser: json['cookies_from_browser'] == false,
      cookiesFromWebview:
          json['cookies_from_webview'] is String
              ? json['cookies_from_webview']
              : null,
      disableCookiesFromWebview: json['cookies_from_webview'] == false,
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      twofactor: json['twofactor']?.toString() ?? '',
      videoPassword: json['video_password']?.toString() ?? '',

      // Video
      mergeOutputFormat:
          _enumFromString(
            MergeOutputFormat.values,
            json['merge_output_format'],
          ) ??
          MergeOutputFormat.mkv,
      audioFormat:
          _enumFromString(AudioFormat.values, json['audio_format']) ??
          AudioFormat.best,
      subFormat:
          _enumFromString(SubtitleFormat.values, json['sub_format']) ??
          SubtitleFormat.srt,
      videoMultistreams: json['video_multistreams'] ?? true,
      audioMultistreams: json['audio_multistreams'] ?? true,
      audioQuality: json['audio_quality'] is int ? json['audio_quality'] : 0,
      remuxVideo: _enumFromString(
        RemuxVideoFormat.values,
        json['remux_video'] is String ? json['remux_video'] : null,
      ),
      disableRemuxVideo: json['remux_video'] == false,
      embedSubs: json['embed_subs'] ?? true,
      embedThumbnail: json['embed_thumbnail'] ?? true,
      embedMetadata: json['embed_metadata'] ?? true,
      embedChapters: json['embed_chapters'] ?? true,
      embedInfoJson: json['embed_info_json'] ?? true,
      format: json['format']?.toString() ?? '',
      xattrs: json['xattrs'] == true,
      fixup:
          _enumFromString(FixupOption.values, json['fixup']) ??
          FixupOption.force,
      forceKeyframesAtCuts: json['force_keyframes_at_cuts'] ?? true,
      ffmpegLocation: json['ffmpeg_location']?.toString() ?? '',
      convertThumbnails:
          _enumFromString(ThumbnailFormat.values, json['convert_thumbnails']) ??
          ThumbnailFormat.webp,
      writeSubs: json['write_subs'] == true,
      writeAutoSubs: json['write_auto_subs'] == true,

      // Download
      output: json['output'] != null
          ? List<String>.from(json['output'])
          : ["title", ".", "ext"],
      paths: pPaths,
      downloadArchive: json['download_archive'] is String
          ? json['download_archive']
          : null,
      disableDownloadArchive: json['download_archive'] == false,
      concurrentFragments: json['concurrent_fragments'] is int
          ? json['concurrent_fragments']
          : 1,
      breakOnExisting: json['break_on_existing'] == true,
      windowsFilenames: json['windows_filenames'] ?? true,
      abortOnUnavailableFragments:
          json['abort_on_unavailable_fragments'] == true,
      keepFragments: json['keep_fragments'] == true,
      forceOverwrites: json['force_overwrites'] ?? false,
      writeThumbnail: json['write_thumbnail'] == true,
      liveFromStart: json['live_from_start'] ?? true,
      waitForVideo: json['wait_for_video'] is int
          ? json['wait_for_video']
          : null,
      disableWaitForVideo: json['wait_for_video'] == false,
      markWatched: json['mark_watched'] == true,
      jsRuntimes: pJsRuntimes,
      skipPlaylistAfterErrors: json['skip_playlist_after_errors'] is int
          ? json['skip_playlist_after_errors']
          : null,
      infiniteSkipPlaylistAfterErrors:
          json['skip_playlist_after_errors'] == 'infinite',
      retries: json['retries'] is int ? json['retries'] : null,
      infiniteRetries: json['retries'] == 'infinite',
      fileAccessRetries: json['file_access_retries'] is int
          ? json['file_access_retries']
          : null,
      infiniteFileAccessRetries: json['file_access_retries'] == 'infinite',
      fragmentRetries: json['fragment_retries'] is int
          ? json['fragment_retries']
          : null,
      infiniteFragmentRetries: json['fragment_retries'] == 'infinite',
      extractorRetries: json['extractor_retries'] is int
          ? json['extractor_retries']
          : null,
      infiniteExtractorRetries: json['extractor_retries'] == 'infinite',
      limitRate: json['limit_rate'] is String ? json['limit_rate'] : null,
      disableLimitRate: json['limit_rate'] == false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadOptions &&
        other.videoResolution == videoResolution &&
        other.videoResolutionValue == videoResolutionValue &&
        other.audioLanguage == audioLanguage &&
        other.audioLanguageCode == audioLanguageCode &&
        listEquals(other.subLangs, subLangs) &&
        other.extractAudio == extractAudio &&
        other.playlist == playlist &&
        listEquals(other.sponsorblockMark, sponsorblockMark) &&
        listEquals(other.sponsorblockRemove, sponsorblockRemove) &&
        other.cutVideo == cutVideo &&
        other.cutVideoStart == cutVideoStart &&
        other.cutVideoUntilEnd == cutVideoUntilEnd &&
        other.cutVideoEnd == cutVideoEnd &&
        other.proxy == proxy &&
        other.socketTimeout == socketTimeout &&
        other.infiniteSocketTimeout == infiniteSocketTimeout &&
        other.sourceAddress == sourceAddress &&
        other.impersonate == impersonate &&
        other.forceIpv4 == forceIpv4 &&
        other.forceIpv6 == forceIpv6 &&
        other.enableFileUrls == enableFileUrls &&
        other.geoVerificationProxy == geoVerificationProxy &&
        other.xff == xff &&
        other.preferInsecure == preferInsecure &&
        mapEquals(other.addHeaders, addHeaders) &&
        other.cookies == cookies &&
        other.disableCookies == disableCookies &&
        other.cookiesFromBrowser == cookiesFromBrowser &&
        other.disableCookiesFromBrowser == disableCookiesFromBrowser &&
        other.cookiesFromWebview == cookiesFromWebview &&
        other.disableCookiesFromWebview == disableCookiesFromWebview &&
        other.username == username &&
        other.password == password &&
        other.twofactor == twofactor &&
        other.videoPassword == videoPassword &&
        other.mergeOutputFormat == mergeOutputFormat &&
        other.audioFormat == audioFormat &&
        other.subFormat == subFormat &&
        other.videoMultistreams == videoMultistreams &&
        other.audioMultistreams == audioMultistreams &&
        other.audioQuality == audioQuality &&
        other.remuxVideo == remuxVideo &&
        other.disableRemuxVideo == disableRemuxVideo &&
        other.embedSubs == embedSubs &&
        other.embedThumbnail == embedThumbnail &&
        other.embedMetadata == embedMetadata &&
        other.embedChapters == embedChapters &&
        other.embedInfoJson == embedInfoJson &&
        other.format == format &&
        other.xattrs == xattrs &&
        other.fixup == fixup &&
        other.forceKeyframesAtCuts == forceKeyframesAtCuts &&
        other.ffmpegLocation == ffmpegLocation &&
        other.convertThumbnails == convertThumbnails &&
        other.writeSubs == writeSubs &&
        other.writeAutoSubs == writeAutoSubs &&
        listEquals(other.output, output) &&
        mapEquals(other.paths, paths) &&
        other.downloadArchive == downloadArchive &&
        other.disableDownloadArchive == disableDownloadArchive &&
        other.concurrentFragments == concurrentFragments &&
        other.breakOnExisting == breakOnExisting &&
        other.windowsFilenames == windowsFilenames &&
        other.abortOnUnavailableFragments == abortOnUnavailableFragments &&
        other.keepFragments == keepFragments &&
        other.forceOverwrites == forceOverwrites &&
        other.writeThumbnail == writeThumbnail &&
        other.liveFromStart == liveFromStart &&
        other.waitForVideo == waitForVideo &&
        other.disableWaitForVideo == disableWaitForVideo &&
        other.markWatched == markWatched &&
        mapEquals(other.jsRuntimes, jsRuntimes) &&
        other.skipPlaylistAfterErrors == skipPlaylistAfterErrors &&
        other.infiniteSkipPlaylistAfterErrors ==
            infiniteSkipPlaylistAfterErrors &&
        other.retries == retries &&
        other.infiniteRetries == infiniteRetries &&
        other.fileAccessRetries == fileAccessRetries &&
        other.infiniteFileAccessRetries == infiniteFileAccessRetries &&
        other.fragmentRetries == fragmentRetries &&
        other.infiniteFragmentRetries == infiniteFragmentRetries &&
        other.extractorRetries == extractorRetries &&
        other.infiniteExtractorRetries == infiniteExtractorRetries &&
        other.limitRate == limitRate &&
        other.disableLimitRate == disableLimitRate;
  }

  @override
  int get hashCode => Object.hashAll([
        videoResolution,
        videoResolutionValue,
        audioLanguage,
        audioLanguageCode,
        Object.hashAll(subLangs),
        extractAudio,
        playlist,
        Object.hashAll(sponsorblockMark),
        Object.hashAll(sponsorblockRemove),
        cutVideo,
        cutVideoStart,
        cutVideoUntilEnd,
        cutVideoEnd,
        proxy,
        socketTimeout,
        infiniteSocketTimeout,
        sourceAddress,
        impersonate,
        forceIpv4,
        forceIpv6,
        cookies,
        disableCookies,
        cookiesFromBrowser,
        disableCookiesFromBrowser,
        cookiesFromWebview,
        disableCookiesFromWebview,
      ]);
}
