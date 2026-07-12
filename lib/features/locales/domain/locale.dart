import 'package:flutter/foundation.dart';

class AppStringKey {
  final Map<String, String> _cadenasLocalizadas = <String, String>{};
  // Strings de la pantalla de downloads, prefijo d ----------------
  String get dTitle => _cadenasLocalizadas['d_title'] ?? '';
  String get dEverything => _cadenasLocalizadas['d_everything'] ?? '';
  String get dInProgress => _cadenasLocalizadas['d_in_progress'] ?? '';
  String get dCompleted => _cadenasLocalizadas['d_completed'] ?? '';
  String get dError => _cadenasLocalizadas['d_error'] ?? '';
  // Barra superior
  String get dVideoUrl => _cadenasLocalizadas['d_video_url'] ?? '';
  String get dSearchDownloads =>
      _cadenasLocalizadas['d_search_downloads'] ?? '';
  String get dFilterEverything =>
      _cadenasLocalizadas['d_filter_everything'] ?? '';
  String get dFilterVideoAudio =>
      _cadenasLocalizadas['d_filter_video_audio'] ?? '';
  String get dFilterPlaylist => _cadenasLocalizadas['d_filter_playlist'] ?? '';
  // Tooltips
  String get dPaste => _cadenasLocalizadas['d_paste'] ?? '';
  String get dFilters => _cadenasLocalizadas['d_filters'] ?? '';
  String get dSettings => _cadenasLocalizadas['d_settings'] ?? '';
  String get dShowTutorial => _cadenasLocalizadas['d_show_tutorial'] ?? '';
  // Buttons
  String get dDownload => _cadenasLocalizadas['d_download'] ?? '';
  // Messages
  String get dNoDownloads => _cadenasLocalizadas['d_no_downloads'] ?? '';
  String get dDownloadSent => _cadenasLocalizadas['d_download_sent'] ?? '';
  String get dDownloadSentError =>
      _cadenasLocalizadas['d_download_sent_error'] ?? '';
  // Strings de la pantalla de download details, prefijo dd  ----------------
  String get ddTitle => _cadenasLocalizadas['dd_title'] ?? '';
  String get ddSubDownloads => _cadenasLocalizadas['dd_sub_downloads'] ?? '';
  String get ddLogs => _cadenasLocalizadas['dd_logs'] ?? '';
  String get ddSettings => _cadenasLocalizadas['dd_settings'] ?? '';
  // Buttons
  String get ddReload => _cadenasLocalizadas['dd_reload'] ?? '';
  String get ddErrors => _cadenasLocalizadas['dd_errors'] ?? '';
  String get ddDownloading => _cadenasLocalizadas['dd_downloading'] ?? '';
  String get ddCompleted => _cadenasLocalizadas['dd_completed'] ?? '';
  String get ddPending => _cadenasLocalizadas['dd_pending'] ?? '';
  // Messages
  String get ddElements => _cadenasLocalizadas['dd_elements'] ?? '';
  String get ddSearchList => _cadenasLocalizadas['dd_search_list'] ?? '';
  String get ddNoElements => _cadenasLocalizadas['dd_no_elements'] ?? '';
  String get ddNoLogs => _cadenasLocalizadas['dd_no_logs'] ?? '';
  String get ddNoSettings => _cadenasLocalizadas['dd_no_settings'] ?? '';
  // Tooltips
  String get ddSearchFilter => _cadenasLocalizadas['dd_search_filter'] ?? '';
  String get ddSort => _cadenasLocalizadas['dd_sort'] ?? '';
  String get ddSortDefault => _cadenasLocalizadas['dd_sort_default'] ?? '';
  String get ddSortAlphabetical =>
      _cadenasLocalizadas['dd_sort_alphabetical'] ?? '';
  String get ddSortReverse => _cadenasLocalizadas['dd_sort_reverse'] ?? '';
  // Strings de la pantalla de selection wrapper, prefijo sw  ----------------
  // Messages
  String get swSelectionEnqueued =>
      _cadenasLocalizadas['sw_selection_enqueued'] ?? '';
  String get swListForwarded => _cadenasLocalizadas['sw_list_forwarded'] ?? '';
  String get swUnknownTitle => _cadenasLocalizadas['sw_unknown_title'] ?? '';
  String get swNoElementsMatch =>
      _cadenasLocalizadas['sw_no_elements_match'] ?? '';
  String get swSendingSelection =>
      _cadenasLocalizadas['sw_sending_selection'] ?? '';
  String get swNoElementsSelected =>
      _cadenasLocalizadas['sw_no_elements_selected'] ?? '';
  String get swSendSelectionSuccess =>
      _cadenasLocalizadas['sw_send_selection_success'] ?? '';
  String get swSendSelectionError =>
      _cadenasLocalizadas['sw_send_selection_error'] ?? '';
  // Hints
  String get swSearch => _cadenasLocalizadas['sw_search'] ?? '';
  // Filters
  String get swFilterSelected =>
      _cadenasLocalizadas['sw_filter_selected'] ?? '';
  // Buttons
  String get swButtonSelectAll =>
      _cadenasLocalizadas['sw_button_select_all'] ?? '';
  String get swButtonDeselectAll =>
      _cadenasLocalizadas['sw_button_deselect_all'] ?? '';
  String get swButtonInvertSelection =>
      _cadenasLocalizadas['sw_button_invert_selection'] ?? '';
  String get swButtonDownloadSelected =>
      _cadenasLocalizadas['sw_button_download_selected'] ?? '';
  // Strings de la pantalla de share wrapper, prefijo shw ----------------
  // Messages
  String get shwDownloadSent => _cadenasLocalizadas['shw_download_sent'] ?? '';
  String get shwDownloadSentError =>
      _cadenasLocalizadas['shw_download_sent_error'] ?? '';
  String get shwLoadingSelector =>
      _cadenasLocalizadas['shw_loading_selector'] ?? '';
  // Strings de la pantalla de permisos, prefijo p ----------------
  String get pTitle => _cadenasLocalizadas['p_title'] ?? '';
  String get pDescription => _cadenasLocalizadas['p_description'] ?? '';
  String get pStorage => _cadenasLocalizadas['p_storage'] ?? '';
  String get pStorageDesc => _cadenasLocalizadas['p_storage_desc'] ?? '';
  String get pOverlay => _cadenasLocalizadas['p_overlay'] ?? '';
  String get pOverlayDesc => _cadenasLocalizadas['p_overlay_desc'] ?? '';
  String get pBattery => _cadenasLocalizadas['p_battery'] ?? '';
  String get pBatteryDesc => _cadenasLocalizadas['p_battery_desc'] ?? '';
  String get pNotification => _cadenasLocalizadas['p_notification'] ?? '';
  String get pNotificationDesc =>
      _cadenasLocalizadas['p_notification_desc'] ?? '';
  String get pInstall => _cadenasLocalizadas['p_install'] ?? '';
  String get pInstallDesc => _cadenasLocalizadas['p_install_desc'] ?? '';
  // Buttons
  String get pButtonContinue => _cadenasLocalizadas['p_button_continue'] ?? '';
  String get pButtonGrant => _cadenasLocalizadas['p_button_grant'] ?? '';
  // Strings de la pantalla de licencias, prefijo l ----------------
  String get lTitle => _cadenasLocalizadas['l_title'] ?? '';
  String get lButtonSelect => _cadenasLocalizadas['l_button_select'] ?? '';
  String get lLoadingError => _cadenasLocalizadas['l_loading_error'] ?? '';
  String get lEmptyFile => _cadenasLocalizadas['l_empty_file'] ?? '';
  // Strings de la pantalla de system details, prefijo sd ----------------
  String get sdTitle => _cadenasLocalizadas['sd_title'] ?? '';
  String get sdModulesUpdates =>
      _cadenasLocalizadas['sd_modules_updates'] ?? '';
  String get sdPythonServer => _cadenasLocalizadas['sd_python_server'] ?? '';
  String get sdWaitingAvailable =>
      _cadenasLocalizadas['sd_waiting_available'] ?? '';
  String get sdAppLogs => _cadenasLocalizadas['sd_app_logs'] ?? '';
  String get sdPythonServerLogs =>
      _cadenasLocalizadas['sd_python_server_logs'] ?? '';
  String get sdLogFileNotFound =>
      _cadenasLocalizadas['sd_log_file_not_found'] ?? '';
  String get sdLogFileReadError =>
      _cadenasLocalizadas['sd_log_file_read_error'] ?? '';
  String get sdButtonRetry => _cadenasLocalizadas['sd_button_retry'] ?? '';
  String get sdButtonSearch => _cadenasLocalizadas['sd_button_search'] ?? '';
  String get sdButtonReCheck => _cadenasLocalizadas['sd_button_recheck'] ?? '';
  String get sdButtonInstall => _cadenasLocalizadas['sd_button_install'] ?? '';
  String get sdUpdate => _cadenasLocalizadas['sd_update'] ?? '';
  String get sdDownloading => _cadenasLocalizadas['sd_downloading'] ?? '';
  String get sdCheckingPGP => _cadenasLocalizadas['sd_checking_pgp'] ?? '';
  String get sdInstalling => _cadenasLocalizadas['sd_installing'] ?? '';
  String get sdGithubConnectionError =>
      _cadenasLocalizadas['sd_github_connection_error'] ?? '';
  String get sdUpToDate => _cadenasLocalizadas['sd_up_to_date'] ?? '';
  String get sdChannel => _cadenasLocalizadas['sd_channel'] ?? '';
  String get sdNoUpdatesAvailable =>
      _cadenasLocalizadas['sd_no_updates_available'] ?? '';
  String get sdShowTutorial => _cadenasLocalizadas['sd_show_tutorial'] ?? '';
  String get sdLicenses => _cadenasLocalizadas['sd_licenses'] ?? '';
  String get sdNoLogs => _cadenasLocalizadas['sd_no_logs'] ?? '';
  String get sdClose => _cadenasLocalizadas['sd_close'] ?? '';
  // Strings de la pantalla Overlay, prefijo ov ----------------
  String get ovQuickDownload => _cadenasLocalizadas['ov_quick_download'] ?? '';
  String get ovDownloadAddedDesc => _cadenasLocalizadas['ov_download_added_desc'] ?? '';
  // Strings del system status indicator, prefijo ssi ----------------
  String get ssiUpdateAvailable =>
      _cadenasLocalizadas['ssi_update_available'] ?? '';
  String get ssiSearchingUpdates =>
      _cadenasLocalizadas['ssi_searching_updates'] ?? '';
  String get ssiReady => _cadenasLocalizadas['ssi_ready'] ?? '';
  String get ssiAttention => _cadenasLocalizadas['ssi_attention'] ?? '';
  String get ssiInitializing => _cadenasLocalizadas['ssi_initializing'] ?? '';
  String get ssiReconnecting => _cadenasLocalizadas['ssi_reconnecting'] ?? '';
  // Strings del changelog, prefijo cl ----------------
  String get clTitle => _cadenasLocalizadas['cl_title'] ?? '';
  String get clClose => _cadenasLocalizadas['cl_close'] ?? '';
  String get clFileLoadingError =>
      _cadenasLocalizadas['cl_file_loading_error'] ?? '';
  // Strings de tutorial utils, prefijo tu -------------------
  String get tuSkip => _cadenasLocalizadas['tu_skip'] ?? '';
  String get tuNext => _cadenasLocalizadas['tu_next'] ?? '';
  String get tuUnderstood => _cadenasLocalizadas['tu_understood'] ?? '';
  // Pantalla Principal
  String get tuPPEngineState => _cadenasLocalizadas['tu_engine_state'] ?? '';
  String get tuPPEngineStateDesc =>
      _cadenasLocalizadas['tu_engine_state_desc'] ?? '';
  String get tuPPDownload => _cadenasLocalizadas['tu_download'] ?? '';
  String get tuPPDownloadDesc => _cadenasLocalizadas['tu_download_desc'] ?? '';
  String get tuPPFilters => _cadenasLocalizadas['tu_filters'] ?? '';
  String get tuPPFiltersDesc => _cadenasLocalizadas['tu_filters_desc'] ?? '';
  String get tuPPSettings => _cadenasLocalizadas['tu_settings'] ?? '';
  String get tuPPSettingsDesc => _cadenasLocalizadas['tu_settings_desc'] ?? '';
  // Pantalla Settings
  String get tuPSCategories =>
      _cadenasLocalizadas['tu_settings_categories'] ?? '';
  String get tuPSCategoriesDesc =>
      _cadenasLocalizadas['tu_settings_categories_desc'] ?? '';
  String get tuPSSearch => _cadenasLocalizadas['tu_settings_search'] ?? '';
  String get tuPSSearchDesc =>
      _cadenasLocalizadas['tu_settings_search_desc'] ?? '';
  // Pantalla System Details
  String get tuPSDPythonServer =>
      _cadenasLocalizadas['tu_system_details_python_server'] ?? '';
  String get tuPSDPythonServerDesc =>
      _cadenasLocalizadas['tu_system_details_python_server_desc'] ?? '';
  String get tuPSDModulesUpdates =>
      _cadenasLocalizadas['tu_system_details_modules_updates'] ?? '';
  String get tuPSDModulesUpdatesDesc =>
      _cadenasLocalizadas['tu_system_details_modules_updates_desc'] ?? '';
  // Strings de Download Card, prefijo dc ----------------
  String get dcUnknownError => _cadenasLocalizadas['dc_unknown_error'] ?? '';
  String get dcDownloadRemoving =>
      _cadenasLocalizadas['dc_download_removing'] ?? '';
  String get dcDownloadRemovingError =>
      _cadenasLocalizadas['dc_download_removing_error'] ?? '';
  String get dcDownloadResuming =>
      _cadenasLocalizadas['dc_download_resuming'] ?? '';
  String get dcDownloadResumingError =>
      _cadenasLocalizadas['dc_download_resuming_error'] ?? '';
  String get dcDownloadRetrying =>
      _cadenasLocalizadas['dc_download_retrying'] ?? '';
  String get dcDownloadRetryingError =>
      _cadenasLocalizadas['dc_download_retrying_error'] ?? '';
  String get dcDownloadPausing =>
      _cadenasLocalizadas['dc_download_pausing'] ?? '';
  String get dcDownloadPausingError =>
      _cadenasLocalizadas['dc_download_pausing_error'] ?? '';
  String get dcDownloadCancel =>
      _cadenasLocalizadas['dc_download_cancel'] ?? '';
  String get dcDownloadNoCancel =>
      _cadenasLocalizadas['dc_download_no_cancel'] ?? '';
  String get dcDownloadCancelTitle =>
      _cadenasLocalizadas['dc_download_cancel_title'] ?? '';
  String get dcDownloadCancelMessage =>
      _cadenasLocalizadas['dc_download_cancel_message'] ?? '';
  String get dcDownloadCancelling =>
      _cadenasLocalizadas['dc_download_cancelling'] ?? '';
  String get dcDownloadCancellingError =>
      _cadenasLocalizadas['dc_download_cancelling_error'] ?? '';
  String get dcGettingDownloadInfo =>
      _cadenasLocalizadas['dc_getting_download_info'] ?? '';
  // Strings de la pantalla de settings, prefijo s  ----------------
  String get sTitle => _cadenasLocalizadas['s_title'] ?? '';
  String get sGeneral => _cadenasLocalizadas['s_general'] ?? '';
  String get sNetwork => _cadenasLocalizadas['s_network'] ?? '';
  String get sVideo => _cadenasLocalizadas['s_video'] ?? '';
  String get sDownload => _cadenasLocalizadas['s_download'] ?? '';
  // Barra superior
  String get sSearchConfig => _cadenasLocalizadas['s_search_config'] ?? '';
  // Tooltips
  String get sSearchConfigTooltip =>
      _cadenasLocalizadas['s_search_config_tooltip'] ?? '';
  String get sTutorialTooltip =>
      _cadenasLocalizadas['s_tutorial_tooltip'] ?? '';
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
    'd_everything',
    'd_in_progress',
    'd_completed',
    'd_error',
    // Barra superior
    'd_video_url',
    'd_search_downloads',
    'd_filter_everything',
    'd_filter_video_audio',
    'd_filter_playlist',
    // Tooltips
    'd_paste',
    'd_filters',
    'd_settings',
    'd_show_tutorial',
    // Buttons
    'd_download',
    // Messages
    'd_no_downloads',
    'd_download_sent',
    'd_download_sent_error',
    // Pantalla Download Details -------------------------- dd_
    'dd_title',
    'dd_sub_downloads',
    'dd_logs',
    'dd_settings',
    // Buttons
    'dd_reload',
    'dd_errors',
    'dd_downloading',
    'dd_completed',
    'dd_pending',
    // Messages
    'dd_elements',
    'dd_search_list',
    'dd_no_elements',
    'dd_no_logs',
    'dd_no_settings',
    // Tooltips
    'dd_search_filter',
    'dd_sort',
    'dd_sort_default',
    'dd_sort_alphabetical',
    'dd_sort_reverse',
    // Pantalla Selection Wrapper -------------------------- sw_
    // Messages
    'sw_selection_enqueued',
    'sw_list_forwarded',
    'sw_unknown_title',
    'sw_no_elements_match',
    'sw_sending_selection',
    'sw_no_elements_selected',
    'sw_send_selection_success',
    'sw_send_selection_error',
    // Hints
    'sw_search',
    // Filters
    'sw_filter_selected',
    // Buttons
    'sw_button_select_all',
    'sw_button_deselect_all',
    'sw_button_invert_selection',
    'sw_button_download_selected',
    // Pantalla Share Wrapper -------------------------- shw_
    // Messages
    'shw_download_sent',
    'shw_download_sent_error',
    'shw_loading_selector',
    // Pantalla Permisos -------------------------------- p_
    'p_title',
    'p_description',
    'p_storage',
    'p_storage_desc',
    'p_overlay',
    'p_overlay_desc',
    'p_battery',
    'p_battery_desc',
    'p_notification',
    'p_notification_desc',
    'p_install',
    'p_install_desc',
    // Buttons
    'p_button_continue',
    'p_button_grant',
    // Pantalla Licencias -------------------------------- l_
    'l_title',
    'l_button_select',
    'l_loading_error',
    'l_empty_file',
    // Pantalla System Details -------------------------- sd_
    'sd_title',
    'sd_modules_updates',
    'sd_python_server',
    'sd_waiting_available',
    'sd_app_logs',
    'sd_python_server_logs',
    'sd_log_file_not_found',
    'sd_log_file_read_error',
    'sd_button_retry',
    'sd_button_search',
    'sd_button_recheck',
    'sd_button_install',
    'sd_update',
    'sd_downloading',
    'sd_checking_pgp',
    'sd_installing',
    'sd_github_connection_error',
    'sd_up_to_date',
    'sd_channel',
    'sd_no_updates_available',
    'sd_show_tutorial',
    'sd_licenses',
    'sd_no_logs',
    'sd_close',
    // Pantalla Overlay -------------------------------- ov_
    'ov_quick_download',
    'ov_download_added_desc',
    // System Status Indicator -------------------------- ssi_
    'ssi_update_available',
    'ssi_searching_updates',
    'ssi_ready',
    'ssi_attention',
    'ssi_initializing',
    'ssi_reconnecting',
    // Changelog -------------------------------- cl_
    'cl_title',
    'cl_close',
    'cl_file_loading_error',
    // Tutorial Utils -------------------------------- tu_
    'tu_skip',
    'tu_next',
    'tu_understood',
    // Pantalla Principal
    'tu_engine_state',
    'tu_engine_state_desc',
    'tu_download',
    'tu_download_desc',
    'tu_filters',
    'tu_filters_desc',
    'tu_settings',
    'tu_settings_desc',
    // Pantalla Settings
    'tu_settings_categories',
    'tu_settings_categories_desc',
    'tu_settings_search',
    'tu_settings_search_desc',
    // Pantalla System Details
    'tu_system_details_python_server',
    'tu_system_details_python_server_desc',
    'tu_system_details_modules_updates',
    'tu_system_details_modules_updates_desc',
    // Strings de Download Card, prefijo dc ----------------
    'dc_unknown_error',
    'dc_download_removing',
    'dc_download_removing_error',
    'dc_download_resuming',
    'dc_download_resuming_error',
    'dc_download_retrying',
    'dc_download_retrying_error',
    'dc_download_pausing',
    'dc_download_pausing_error',
    'dc_download_cancel',
    'dc_download_no_cancel',
    'dc_download_cancel_title',
    'dc_download_cancel_message',
    'dc_download_cancelling',
    'dc_download_cancelling_error',
    'dc_getting_download_info',
    // Pantalla Settings -------------------------------- s_
    's_title',
    's_general',
    's_network',
    's_video',
    's_download',
    // Barra superior
    's_search_config',
    // Tooltips
    's_search_config_tooltip',
    's_tutorial_tooltip',
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

  Map<String, String> toJson() => Map.from(_cadenasLocalizadas);

  Future<void> updateFromJson(
    Map<String, String> jsonData, {
    bool assertAllKeysPresent = false,
  }) async {
    if (_allAppStrings.any((key) => !jsonData.containsKey(key))) {
      final missingKeys = _allAppStrings
          .where((key) => !jsonData.containsKey(key))
          .toList();
      debugPrint('Missing localization keys: ${missingKeys.join(', ')}');
      if (assertAllKeysPresent) {
        throw Exception('Missing localization keys: ${missingKeys.join(', ')}');
      }
    }
    _cadenasLocalizadas.addAll(jsonData);
  }
}
