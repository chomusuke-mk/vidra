import 'package:flutter/foundation.dart';

class AppStringKey {
  final Map<String, String> _cadenasLocalizadas = <String, String>{};
  // Strings de la pantalla de downloads, prefijo d ----------------
  String get dTitle => _cadenasLocalizadas['d_title'] ?? '';
  // Strings de la pantalla de settings, prefijo s  ----------------
  String get sTitle => _cadenasLocalizadas['s_title'] ?? '';
  String get sGeneral => _cadenasLocalizadas['s_general'] ?? '';
  String get sNetwork => _cadenasLocalizadas['s_network'] ?? '';
  String get sVideo => _cadenasLocalizadas['s_video'] ?? '';
  String get sDownload => _cadenasLocalizadas['s_download'] ?? '';
  // Barra superior
  String get sSearchConfig => _cadenasLocalizadas['s_search_config'] ?? '';
  // Contenedor
  String get sNoResults => _cadenasLocalizadas['s_no_results'] ?? '';
  String get sDefault => _cadenasLocalizadas['s_default'] ?? '';
  String get sBest => _cadenasLocalizadas['s_best'] ?? '';
  String get sNone => _cadenasLocalizadas['s_none'] ?? '';
  String get sAll => _cadenasLocalizadas['s_all'] ?? '';
  String get sNotConfigured => _cadenasLocalizadas['s_not_configured'] ?? '';
  String get sSelectFile => _cadenasLocalizadas['s_select_file'] ?? '';
  String get sSearchLang => _cadenasLocalizadas['s_search_lang'] ?? '';
  String get sSearchCategory => _cadenasLocalizadas['s_search_category'] ?? '';
  String get sUnlimited => _cadenasLocalizadas['s_unlimited'] ?? '';
  // descripciones con sufijo _desc
  // General
  String get sThemeApp => _cadenasLocalizadas['s_theme_app'] ?? '';
  String get sThemeAppDesc => _cadenasLocalizadas['s_theme_app_desc'] ?? '';
  String get sAppLanguage => _cadenasLocalizadas['s_app_language'] ?? '';
  String get sAppLanguageDesc =>
      _cadenasLocalizadas['s_app_language_desc'] ?? '';
  String get sVideoResolution =>
      _cadenasLocalizadas['s_video_resolution'] ?? '';
  String get sVideoResolutionDesc =>
      _cadenasLocalizadas['s_video_resolution_desc'] ?? '';
  String get sAudioLanguage => _cadenasLocalizadas['s_audio_language'] ?? '';
  String get sAudioLanguageDesc =>
      _cadenasLocalizadas['s_audio_language_desc'] ?? '';
  String get sSubLangs => _cadenasLocalizadas['s_sub_langs'] ?? '';
  String get sSubLangsDesc => _cadenasLocalizadas['s_sub_langs_desc'] ?? '';
  String get sExtractAudio => _cadenasLocalizadas['s_extract_audio'] ?? '';
  String get sExtractAudioDesc =>
      _cadenasLocalizadas['s_extract_audio_desc'] ?? '';
  String get sPlaylist => _cadenasLocalizadas['s_playlist'] ?? '';
  String get sPlaylistDesc => _cadenasLocalizadas['s_playlist_desc'] ?? '';
  String get sSponsorblockMark =>
      _cadenasLocalizadas['s_sponsorblock_mark'] ?? '';
  String get sSponsorblockMarkDesc =>
      _cadenasLocalizadas['s_sponsorblock_mark_desc'] ?? '';
  String get sSponsorblockRemove =>
      _cadenasLocalizadas['s_sponsorblock_remove'] ?? '';
  String get sSponsorblockRemoveDesc =>
      _cadenasLocalizadas['s_sponsorblock_remove_desc'] ?? '';
  // Network
  String get sProxy => _cadenasLocalizadas['s_proxy'] ?? '';
  String get sProxyDesc => _cadenasLocalizadas['s_proxy_desc'] ?? '';
  String get sSocketTimeout => _cadenasLocalizadas['s_socket_timeout'] ?? '';
  String get sSocketTimeoutDesc =>
      _cadenasLocalizadas['s_socket_timeout_desc'] ?? '';
  String get sSourceAddress => _cadenasLocalizadas['s_source_address'] ?? '';
  String get sSourceAddressDesc =>
      _cadenasLocalizadas['s_source_address_desc'] ?? '';
  String get sImpersonate => _cadenasLocalizadas['s_impersonate'] ?? '';
  String get sImpersonateDesc =>
      _cadenasLocalizadas['s_impersonate_desc'] ?? '';
  String get sForceIpv4 => _cadenasLocalizadas['s_force_ipv4'] ?? '';
  String get sForceIpv4Desc => _cadenasLocalizadas['s_force_ipv4_desc'] ?? '';
  String get sForceIpv6 => _cadenasLocalizadas['s_force_ipv6'] ?? '';
  String get sForceIpv6Desc => _cadenasLocalizadas['s_force_ipv6_desc'] ?? '';
  String get sEnableFileUrls => _cadenasLocalizadas['s_enable_file_urls'] ?? '';
  String get sEnableFileUrlsDesc =>
      _cadenasLocalizadas['s_enable_file_urls_desc'] ?? '';
  String get sGeoVerificationProxy =>
      _cadenasLocalizadas['s_geo_verification_proxy'] ?? '';
  String get sGeoVerificationProxyDesc =>
      _cadenasLocalizadas['s_geo_verification_proxy_desc'] ?? '';
  String get sXff => _cadenasLocalizadas['s_xff'] ?? '';
  String get sXffDesc => _cadenasLocalizadas['s_xff_desc'] ?? '';
  String get sPreferInsecure => _cadenasLocalizadas['s_prefer_insecure'] ?? '';
  String get sPreferInsecureDesc =>
      _cadenasLocalizadas['s_prefer_insecure_desc'] ?? '';
  String get sAddHeaders => _cadenasLocalizadas['s_add_headers'] ?? '';
  String get sAddHeadersDesc => _cadenasLocalizadas['s_add_headers_desc'] ?? '';
  String get sCookies => _cadenasLocalizadas['s_cookies'] ?? '';
  String get sCookiesDesc => _cadenasLocalizadas['s_cookies_desc'] ?? '';
  String get sCookiesFromBrowser =>
      _cadenasLocalizadas['s_cookies_from_browser'] ?? '';
  String get sCookiesFromBrowserDesc =>
      _cadenasLocalizadas['s_cookies_from_browser_desc'] ?? '';
  String get sUsername => _cadenasLocalizadas['s_username'] ?? '';
  String get sUsernameDesc => _cadenasLocalizadas['s_username_desc'] ?? '';
  String get sPassword => _cadenasLocalizadas['s_password'] ?? '';
  String get sPasswordDesc => _cadenasLocalizadas['s_password_desc'] ?? '';
  String get sTwofactor => _cadenasLocalizadas['s_twofactor'] ?? '';
  String get sTwofactorDesc => _cadenasLocalizadas['s_twofactor_desc'] ?? '';
  String get sVideoPassword => _cadenasLocalizadas['s_video_password'] ?? '';
  String get sVideoPasswordDesc =>
      _cadenasLocalizadas['s_video_password_desc'] ?? '';
  // Video
  String get sMergeOutputFormat =>
      _cadenasLocalizadas['s_merge_output_format'] ?? '';
  String get sMergeOutputFormatDesc =>
      _cadenasLocalizadas['s_merge_output_format_desc'] ?? '';
  String get sAudioFormat => _cadenasLocalizadas['s_audio_format'] ?? '';
  String get sAudioFormatDesc =>
      _cadenasLocalizadas['s_audio_format_desc'] ?? '';
  String get sSubFormat => _cadenasLocalizadas['s_sub_format'] ?? '';
  String get sSubFormatDesc => _cadenasLocalizadas['s_sub_format_desc'] ?? '';
  String get sVideoMultistreams =>
      _cadenasLocalizadas['s_video_multistreams'] ?? '';
  String get sVideoMultistreamsDesc =>
      _cadenasLocalizadas['s_video_multistreams_desc'] ?? '';
  String get sAudioMultistreams =>
      _cadenasLocalizadas['s_audio_multistreams'] ?? '';
  String get sAudioMultistreamsDesc =>
      _cadenasLocalizadas['s_audio_multistreams_desc'] ?? '';
  String get sAudioQuality => _cadenasLocalizadas['s_audio_quality'] ?? '';
  String get sAudioQualityDesc =>
      _cadenasLocalizadas['s_audio_quality_desc'] ?? '';
  String get sRemuxVideo => _cadenasLocalizadas['s_remux_video'] ?? '';
  String get sRemuxVideoDesc => _cadenasLocalizadas['s_remux_video_desc'] ?? '';
  String get sEmbedSubs => _cadenasLocalizadas['s_embed_subs'] ?? '';
  String get sEmbedSubsDesc => _cadenasLocalizadas['s_embed_subs_desc'] ?? '';
  String get sEmbedThumbnail => _cadenasLocalizadas['s_embed_thumbnail'] ?? '';
  String get sEmbedThumbnailDesc =>
      _cadenasLocalizadas['s_embed_thumbnail_desc'] ?? '';
  String get sEmbedMetadata => _cadenasLocalizadas['s_embed_metadata'] ?? '';
  String get sEmbedMetadataDesc =>
      _cadenasLocalizadas['s_embed_metadata_desc'] ?? '';
  String get sEmbedChapters => _cadenasLocalizadas['s_embed_chapters'] ?? '';
  String get sEmbedChaptersDesc =>
      _cadenasLocalizadas['s_embed_chapters_desc'] ?? '';
  String get sEmbedInfoJson => _cadenasLocalizadas['s_embed_info_json'] ?? '';
  String get sEmbedInfoJsonDesc =>
      _cadenasLocalizadas['s_embed_info_json_desc'] ?? '';
  String get sFormat => _cadenasLocalizadas['s_format'] ?? '';
  String get sFormatDesc => _cadenasLocalizadas['s_format_desc'] ?? '';
  String get sXattrs => _cadenasLocalizadas['s_xattrs'] ?? '';
  String get sXattrsDesc => _cadenasLocalizadas['s_xattrs_desc'] ?? '';
  String get sFixup => _cadenasLocalizadas['s_fixup'] ?? '';
  String get sFixupDesc => _cadenasLocalizadas['s_fixup_desc'] ?? '';
  String get sFFmpegLocation => _cadenasLocalizadas['s_ffmpeg_location'] ?? '';
  String get sFFmpegLocationDesc =>
      _cadenasLocalizadas['s_ffmpeg_location_desc'] ?? '';
  String get sConvertThumbnails =>
      _cadenasLocalizadas['s_convert_thumbnails'] ?? '';
  String get sConvertThumbnailsDesc =>
      _cadenasLocalizadas['s_convert_thumbnails_desc'] ?? '';
  String get sWriteSubs => _cadenasLocalizadas['s_write_subs'] ?? '';
  String get sWriteSubsDesc => _cadenasLocalizadas['s_write_subs_desc'] ?? '';
  String get sWriteAutoSubs => _cadenasLocalizadas['s_write_auto_subs'] ?? '';
  String get sWriteAutoSubsDesc =>
      _cadenasLocalizadas['s_write_auto_subs_desc'] ?? '';
  // Download
  String get sOutput => _cadenasLocalizadas['s_output'] ?? '';
  String get sOutputDesc => _cadenasLocalizadas['s_output_desc'] ?? '';
  String get sPaths => _cadenasLocalizadas['s_paths'] ?? '';
  String get sPathsDesc => _cadenasLocalizadas['s_paths_desc'] ?? '';
  String get sDownloadArchive =>
      _cadenasLocalizadas['s_download_archive'] ?? '';
  String get sDownloadArchiveDesc =>
      _cadenasLocalizadas['s_download_archive_desc'] ?? '';
  String get sConcurrentFragments =>
      _cadenasLocalizadas['s_concurrent_fragments'] ?? '';
  String get sConcurrentFragmentsDesc =>
      _cadenasLocalizadas['s_concurrent_fragments_desc'] ?? '';
  String get sBreakOnExisting =>
      _cadenasLocalizadas['s_break_on_existing'] ?? '';
  String get sBreakOnExistingDesc =>
      _cadenasLocalizadas['s_break_on_existing_desc'] ?? '';
  String get sWindowsFilenames =>
      _cadenasLocalizadas['s_windows_filenames'] ?? '';
  String get sWindowsFilenamesDesc =>
      _cadenasLocalizadas['s_windows_filenames_desc'] ?? '';
  String get sAbortOnUnavailableFragments =>
      _cadenasLocalizadas['s_abort_on_unavailable_fragments'] ?? '';
  String get sAbortOnUnavailableFragmentsDesc =>
      _cadenasLocalizadas['s_abort_on_unavailable_fragments_desc'] ?? '';
  String get sKeepFragments => _cadenasLocalizadas['s_keep_fragments'] ?? '';
  String get sKeepFragmentsDesc =>
      _cadenasLocalizadas['s_keep_fragments_desc'] ?? '';
  String get sForceOverwrites =>
      _cadenasLocalizadas['s_force_overwrites'] ?? '';
  String get sForceOverwritesDesc =>
      _cadenasLocalizadas['s_force_overwrites_desc'] ?? '';
  String get sWriteThumbnail => _cadenasLocalizadas['s_write_thumbnail'] ?? '';
  String get sWriteThumbnailDesc =>
      _cadenasLocalizadas['s_write_thumbnail_desc'] ?? '';
  String get sLiveFromStart => _cadenasLocalizadas['s_live_from_start'] ?? '';
  String get sLiveFromStartDesc =>
      _cadenasLocalizadas['s_live_from_start_desc'] ?? '';
  String get sWaitForVideo => _cadenasLocalizadas['s_wait_for_video'] ?? '';
  String get sWaitForVideoDesc =>
      _cadenasLocalizadas['s_wait_for_video_desc'] ?? '';
  String get sMarkWatched => _cadenasLocalizadas['s_mark_watched'] ?? '';
  String get sMarkWatchedDesc =>
      _cadenasLocalizadas['s_mark_watched_desc'] ?? '';
  String get sJsRuntimes => _cadenasLocalizadas['s_js_runtimes'] ?? '';
  String get sJsRuntimesDesc => _cadenasLocalizadas['s_js_runtimes_desc'] ?? '';
  String get sSkipPlaylistAfterErrors =>
      _cadenasLocalizadas['s_skip_playlist_after_errors'] ?? '';
  String get sSkipPlaylistAfterErrorsDesc =>
      _cadenasLocalizadas['s_skip_playlist_after_errors_desc'] ?? '';
  String get sRetries => _cadenasLocalizadas['s_retries'] ?? '';
  String get sRetriesDesc => _cadenasLocalizadas['s_retries_desc'] ?? '';
  String get sFileAccessRetries =>
      _cadenasLocalizadas['s_file_access_retries'] ?? '';
  String get sFileAccessRetriesDesc =>
      _cadenasLocalizadas['s_file_access_retries_desc'] ?? '';
  String get sFragmentRetries =>
      _cadenasLocalizadas['s_fragment_retries'] ?? '';
  String get sFragmentRetriesDesc =>
      _cadenasLocalizadas['s_fragment_retries_desc'] ?? '';
  String get sExtractorRetries =>
      _cadenasLocalizadas['s_extractor_retries'] ?? '';
  String get sExtractorRetriesDesc =>
      _cadenasLocalizadas['s_extractor_retries_desc'] ?? '';
  String get sLimitRate => _cadenasLocalizadas['s_limit_rate'] ?? '';
  String get sLimitRateDesc => _cadenasLocalizadas['s_limit_rate_desc'] ?? '';

  final List<String> _allAppStrings = [
    // Pantalla Downloads -------------------------------- d_
    'd_title',
    // Pantalla Settings -------------------------------- s_
    's_title',
    's_general',
    's_network',
    's_video',
    's_download',
    // Barra superior
    's_search_config',
    // Contenedor
    's_no_results',
    's_default',
    's_best',
    's_none',
    's_all',
    's_not_configured',
    's_select_file',
    's_search_category',
    's_search_lang',
    's_unlimited',
    // General
    's_theme_app',
    's_theme_app_desc',
    's_app_language',
    's_app_language_desc',
    's_video_resolution',
    's_video_resolution_desc',
    's_audio_language',
    's_audio_language_desc',
    's_sub_langs',
    's_sub_langs_desc',
    's_extract_audio',
    's_extract_audio_desc',
    's_playlist',
    's_playlist_desc',
    's_sponsorblock_mark',
    's_sponsorblock_mark_desc',
    's_sponsorblock_remove',
    's_sponsorblock_remove_desc',
    // Network
    's_proxy',
    's_proxy_desc',
    's_socket_timeout',
    's_socket_timeout_desc',
    's_source_address',
    's_source_address_desc',
    's_impersonate',
    's_impersonate_desc',
    's_force_ipv4',
    's_force_ipv4_desc',
    's_force_ipv6',
    's_force_ipv6_desc',
    's_enable_file_urls',
    's_enable_file_urls_desc',
    's_geo_verification_proxy',
    's_geo_verification_proxy_desc',
    's_xff',
    's_xff_desc',
    's_prefer_insecure',
    's_prefer_insecure_desc',
    's_add_headers',
    's_add_headers_desc',
    's_cookies',
    's_cookies_desc',
    's_cookies_from_browser',
    's_cookies_from_browser_desc',
    's_username',
    's_username_desc',
    's_password',
    's_password_desc',
    's_twofactor',
    's_twofactor_desc',
    's_video_password',
    's_video_password_desc',
    // Video
    's_merge_output_format',
    's_merge_output_format_desc',
    's_audio_format',
    's_audio_format_desc',
    's_sub_format',
    's_sub_format_desc',
    's_video_multistreams',
    's_video_multistreams_desc',
    's_audio_multistreams',
    's_audio_multistreams_desc',
    's_audio_quality',
    's_audio_quality_desc',
    's_remux_video',
    's_remux_video_desc',
    's_embed_subs',
    's_embed_subs_desc',
    's_embed_thumbnail',
    's_embed_thumbnail_desc',
    's_embed_metadata',
    's_embed_metadata_desc',
    's_embed_chapters',
    's_embed_chapters_desc',
    's_embed_info_json',
    's_embed_info_json_desc',
    's_format',
    's_format_desc',
    's_xattrs',
    's_xattrs_desc',
    's_fixup',
    's_fixup_desc',
    's_ffmpeg_location',
    's_ffmpeg_location_desc',
    's_convert_thumbnails',
    's_convert_thumbnails_desc',
    's_write_subs',
    's_write_subs_desc',
    's_write_auto_subs',
    's_write_auto_subs_desc',
    // Download
    's_output',
    's_output_desc',
    's_paths',
    's_paths_desc',
    's_download_archive',
    's_download_archive_desc',
    's_concurrent_fragments',
    's_concurrent_fragments_desc',
    's_break_on_existing',
    's_break_on_existing_desc',
    's_windows_filenames',
    's_windows_filenames_desc',
    's_abort_on_unavailable_fragments',
    's_abort_on_unavailable_fragments_desc',
    's_keep_fragments',
    's_keep_fragments_desc',
    's_force_overwrites',
    's_force_overwrites_desc',
    's_write_thumbnail',
    's_write_thumbnail_desc',
    's_live_from_start',
    's_live_from_start_desc',
    's_wait_for_video',
    's_wait_for_video_desc',
    's_mark_watched',
    's_mark_watched_desc',
    's_js_runtimes',
    's_js_runtimes_desc',
    's_skip_playlist_after_errors',
    's_skip_playlist_after_errors_desc',
    's_retries',
    's_retries_desc',
    's_file_access_retries',
    's_file_access_retries_desc',
    's_fragment_retries',
    's_fragment_retries_desc',
    's_extractor_retries',
    's_extractor_retries_desc',
    's_limit_rate',
    's_limit_rate_desc',
  ];

  Future<void> updateFromJson(
    Map<String, String> jsonData, {
    bool assertAllKeysPresent = false,
  }) async {
    if (_allAppStrings.any((key) => !jsonData.containsKey(key))) {
      final missingKeys = _allAppStrings
          .where((key) => !jsonData.containsKey(key))
          .toList();
      if (assertAllKeysPresent) {
        throw Exception('Missing localization keys: ${missingKeys.join(', ')}');
      } else {
        debugPrint('Missing localization keys: ${missingKeys.join(', ')}');
      }
    }
    _cadenasLocalizadas.addAll(jsonData);
  }
}
