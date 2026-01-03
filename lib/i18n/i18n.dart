import 'dart:async';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:jsonc/jsonc.dart' show jsoncDecode;

export 'delegates/vidra_localizations.dart';

class AppStringKey {
  AppStringKey._();

  static const homeTitle = 'homeTitle';
  static const settingsTitle = 'settingsTitle';
  static const quickSettings = 'quickSettings';
  static const enterUrl = 'enterUrl';
  static const download = 'download';
  static const general = 'general';
  static const network = 'network';
  static const video = 'video';
  static const downloadSection = 'downloadSection';
  static const mapKeyLabel = 'mapKeyLabel';
  static const mapValueLabel = 'mapValueLabel';
  static const addEntry = 'addEntry';
  static const addItem = 'addItem';
  static const textMode = 'textMode';
  static const listMode = 'listMode';
  static const mapMode = 'mapMode';
  static const suggestions = 'suggestions';
  static const customValue = 'customValue';
  static const preferencePickerSelectFolderTitle =
      'preferencePickerSelectFolderTitle';
  static const preferencePickerUseFolderAction =
      'preferencePickerUseFolderAction';
  static const preferencePickerSelectFileTitle =
      'preferencePickerSelectFileTitle';
  static const preferencePickerUseFileAction = 'preferencePickerUseFileAction';
  static const preferencePickerGrantStoragePermission =
      'preferencePickerGrantStoragePermission';
  static const preferencePickerNoStorageLocations =
      'preferencePickerNoStorageLocations';
  static const preferencePickerPermissionDenied =
      'preferencePickerPermissionDenied';
  static const preferencePickerFilesystemUnavailable =
      'preferencePickerFilesystemUnavailable';
  static const preferencePickerFilePickerUnavailable =
      'preferencePickerFilePickerUnavailable';
  static const preferencePickerSystemPickerUnavailable =
      'preferencePickerSystemPickerUnavailable';
  static const preferencePickerGoUp = 'preferencePickerGoUp';
  static const preferencePickerUserFolder = 'preferencePickerUserFolder';
  static const preferencePickerSystemLabel = 'preferencePickerSystemLabel';
  static const preferencePickerDriveLabel = 'preferencePickerDriveLabel';
  static const preferencePickerInternalStorage =
      'preferencePickerInternalStorage';
  static const preferencePickerSdCardLabel = 'preferencePickerSdCardLabel';
  static const preferencePickerMainDisk = 'preferencePickerMainDisk';
  static const preferencePickerTooltipFolder = 'preferencePickerTooltipFolder';
  static const preferenceControlNotImplemented =
      'preferenceControlNotImplemented';
  static const offLabel = 'offLabel';
  static const removeItem = 'removeItem';
  static const removeEntry = 'removeEntry';
  static const editEntry = 'editEntry';
  static const invalidMapFormat = 'invalidMapFormat';
  static const invalidMapKey = 'invalidMapKey';
  static const all = 'all';
  static const best = 'best';
  static const none = 'none';
  static const noOverride = 'noOverride';
  static const homeTabAll = 'homeTabAll';
  static const homeTabInProgress = 'homeTabInProgress';
  static const homeTabCompleted = 'homeTabCompleted';
  static const homeTabError = 'homeTabError';
  static const homeEmptyAll = 'homeEmptyAll';
  static const homeEmptyInProgress = 'homeEmptyInProgress';
  static const homeEmptyCompleted = 'homeEmptyCompleted';
  static const homeEmptyError = 'homeEmptyError';
  static const homeThumbnailCacheCleared = 'homeThumbnailCacheCleared';
  static const homeThumbnailCacheClearError = 'homeThumbnailCacheClearError';
  static const homeThumbnailCacheTooltip = 'homeThumbnailCacheTooltip';
  static const homePlaylistPreparing = 'homePlaylistPreparing';
  static const homePlaylistCollectingDescription =
      'homePlaylistCollectingDescription';
  static const homeOptionsTitle = 'homeOptionsTitle';
  static const homeFolderOptionsTitle = 'homeFolderOptionsTitle';
  static const homeLanguageButtonTooltip = 'homeLanguageButtonTooltip';
  static const homeThemeToggleTooltip = 'homeThemeToggleTooltip';
  static const homeSettingsTooltip = 'homeSettingsTooltip';
  static const homeFormatFabTooltip = 'homeFormatFabTooltip';
  static const homeFolderFabTooltip = 'homeFolderFabTooltip';
  static const homePasteButtonTooltip = 'homePasteButtonTooltip';
  static const homeDropOverlayHint = 'homeDropOverlayHint';
  static const homeCloseAction = 'homeCloseAction';
  static const homeLanguagePickerTitle = 'homeLanguagePickerTitle';
  static const homePaginationShow = 'homePaginationShow';
  static const homePaginationPerPage = 'homePaginationPerPage';
  static const homePaginationRangeLabel = 'homePaginationRangeLabel';
  static const homePaginationNoItems = 'homePaginationNoItems';
  static const homePaginationFirst = 'homePaginationFirst';
  static const homePaginationPrevious = 'homePaginationPrevious';
  static const homePaginationNext = 'homePaginationNext';
  static const homePaginationLast = 'homePaginationLast';
  static const homePaginationPageStatus = 'homePaginationPageStatus';
  static const homeDownloadStarted = 'homeDownloadStarted';
  static const homeDownloadFailed = 'homeDownloadFailed';
  static const homeBackendStatusUnknown = 'homeBackendStatusUnknown';
  static const homeBackendStatusUnpacking = 'homeBackendStatusUnpacking';
  static const homeBackendStatusStarting = 'homeBackendStatusStarting';
  static const homeBackendStatusStartingShort =
      'homeBackendStatusStartingShort';
  static const homeBackendStatusStopped = 'homeBackendStatusStopped';
  static const homeBackendStatusInstallReady = 'homeBackendStatusInstallReady';
  static const homeBackendStatusDownloadingUpdate =
      'homeBackendStatusDownloadingUpdate';
  static const homeBackendStatusUpdateAvailable =
      'homeBackendStatusUpdateAvailable';
  static const homeBackendStatusCheckingUpdates =
      'homeBackendStatusCheckingUpdates';
  static const homeBackendStatusRunning = 'homeBackendStatusRunning';
  static const homeBackendActionDisabledUnknown =
      'homeBackendActionDisabledUnknown';
  static const homeBackendActionDisabledUnpacking =
      'homeBackendActionDisabledUnpacking';
  static const homeBackendActionDisabledStarting =
      'homeBackendActionDisabledStarting';
  static const homeBackendActionDisabledStopped =
      'homeBackendActionDisabledStopped';
  static const backendStatusTitle = 'backendStatusTitle';
  static const backendStatusUnknownVersion = 'backendStatusUnknownVersion';
  static const backendStatusUnknownPlatform = 'backendStatusUnknownPlatform';
  static const backendStatusPrimaryDownloading =
      'backendStatusPrimaryDownloading';
  static const backendStatusPrimaryInstall = 'backendStatusPrimaryInstall';
  static const backendStatusPrimarySearching = 'backendStatusPrimarySearching';
  static const backendStatusPrimaryDownload = 'backendStatusPrimaryDownload';
  static const backendStatusPrimaryUpToDate = 'backendStatusPrimaryUpToDate';
  static const backendStatusSnackPreparing = 'backendStatusSnackPreparing';
  static const backendStatusSnackReady = 'backendStatusSnackReady';
  static const backendStatusSnackInstalling = 'backendStatusSnackInstalling';
  static const backendStatusOpenLinkInvalid = 'backendStatusOpenLinkInvalid';
  static const backendStatusOpenLinkFailed = 'backendStatusOpenLinkFailed';
  static const backendStatusHeaderLabel = 'backendStatusHeaderLabel';
  static const backendStatusBadgeActive = 'backendStatusBadgeActive';
  static const backendStatusBadgeBusy = 'backendStatusBadgeBusy';
  static const backendStatusBadgeStopped = 'backendStatusBadgeStopped';
  static const backendStatusBadgeUnknown = 'backendStatusBadgeUnknown';
  static const backendStatusDescription = 'backendStatusDescription';
  static const backendStatusUpdateCardTitle = 'backendStatusUpdateCardTitle';
  static const backendStatusAppInfoTitle = 'backendStatusAppInfoTitle';
  static const backendStatusServiceNameLabel = 'backendStatusServiceNameLabel';
  static const backendStatusDescriptionLabel = 'backendStatusDescriptionLabel';
  static const backendStatusEnvironmentLabel = 'backendStatusEnvironmentLabel';
  static const backendStatusVersionLabel = 'backendStatusVersionLabel';
  static const backendStatusHostPortLabel = 'backendStatusHostPortLabel';
  static const backendStatusBackendBaseLabel = 'backendStatusBackendBaseLabel';
  static const backendStatusApiBaseLabel = 'backendStatusApiBaseLabel';
  static const backendStatusOverviewSocketLabel =
      'backendStatusOverviewSocketLabel';
  static const backendStatusJobSocketLabel = 'backendStatusJobSocketLabel';
  static const backendStatusTimeoutLabel = 'backendStatusTimeoutLabel';
  static const backendStatusViewCodeAction = 'backendStatusViewCodeAction';
  static const backendStatusViewLicensesAction =
      'backendStatusViewLicensesAction';
  static const backendLicensesTitle = 'backendLicensesTitle';
  static const backendLicensesEmpty = 'backendLicensesEmpty';
  static const backendLicensesLoadError = 'backendLicensesLoadError';
  static const backendStatusDonatePatreonAction =
      'backendStatusDonatePatreonAction';
  static const backendStatusDonateBuyMeACoffeeAction =
      'backendStatusDonateBuyMeACoffeeAction';
  static const backendStatusDeveloperLabel = 'backendStatusDeveloperLabel';
  static const backendStatusVersionPlatform = 'backendStatusVersionPlatform';
  static const backendStatusTooltipRefresh = 'backendStatusTooltipRefresh';
  static const backendStatusTooltipDownload = 'backendStatusTooltipDownload';
  static const backendStatusTooltipDownloading =
      'backendStatusTooltipDownloading';
  static const backendStatusTooltipInstall = 'backendStatusTooltipInstall';
  static const backendOverlayShowAnimationTooltip =
      'backendOverlayShowAnimationTooltip';
  static const backendOverlayHideAnimationTooltip =
      'backendOverlayHideAnimationTooltip';
  static const backendOverlayCycleAnimationTooltip =
      'backendOverlayCycleAnimationTooltip';
  static const backendOverlayReloadAnimationTooltip =
      'backendOverlayReloadAnimationTooltip';
  static const homePathsEnsureDownloads = 'homePathsEnsureDownloads';
  static const initialPermissionsTitle = 'initialPermissionsTitle';
  static const initialPermissionsSubtitle = 'initialPermissionsSubtitle';
  static const initialPermissionsLanguageLabel =
      'initialPermissionsLanguageLabel';
  static const initialPermissionsContinueButton =
      'initialPermissionsContinueButton';
  static const initialPermissionsRefreshButton =
      'initialPermissionsRefreshButton';
  static const initialPermissionsNotificationsTitle =
      'initialPermissionsNotificationsTitle';
  static const initialPermissionsNotificationsDescription =
      'initialPermissionsNotificationsDescription';
  static const initialPermissionsManageStorageTitle =
      'initialPermissionsManageStorageTitle';
  static const initialPermissionsManageStorageDescription =
      'initialPermissionsManageStorageDescription';
  static const initialPermissionsLegacyStorageTitle =
      'initialPermissionsLegacyStorageTitle';
  static const initialPermissionsLegacyStorageDescription =
      'initialPermissionsLegacyStorageDescription';
  static const initialPermissionsOverlayTitle =
      'initialPermissionsOverlayTitle';
  static const initialPermissionsOverlayDescription =
      'initialPermissionsOverlayDescription';
  static const initialPermissionsStatusGranted =
      'initialPermissionsStatusGranted';
  static const initialPermissionsStatusDenied =
      'initialPermissionsStatusDenied';
  static const initialPermissionsStatusPermanentlyDenied =
      'initialPermissionsStatusPermanentlyDenied';
  static const initialPermissionsStatusNotRequired =
      'initialPermissionsStatusNotRequired';
  static const initialPermissionsStatusUnknown =
      'initialPermissionsStatusUnknown';
  static const initialPermissionsStatusUnsupported =
      'initialPermissionsStatusUnsupported';
  static const initialPermissionsRecommendedLabel =
      'initialPermissionsRecommendedLabel';
  static const initialPermissionsOptionalLabel =
      'initialPermissionsOptionalLabel';
  static const initialPermissionsActionGrant = 'initialPermissionsActionGrant';
  static const initialPermissionsActionSettings =
      'initialPermissionsActionSettings';
  static const backendWaitActionSuffix = 'backendWaitActionSuffix';
  static const backendWaitUnpacking = 'backendWaitUnpacking';
  static const backendWaitStarting = 'backendWaitStarting';
  static const backendWaitStopped = 'backendWaitStopped';
  static const backendWaitUnknown = 'backendWaitUnknown';
  static const backendWaitConnectionFailed = 'backendWaitConnectionFailed';
  static const backendActionSyncDownloads = 'backendActionSyncDownloads';
  static const backendActionRefreshDownloads = 'backendActionRefreshDownloads';
  static const backendActionFetchPreview = 'backendActionFetchPreview';
  static const backendActionLoadPlaylist = 'backendActionLoadPlaylist';
  static const backendActionLoadJobOptions = 'backendActionLoadJobOptions';
  static const backendActionLoadEntryOptions = 'backendActionLoadEntryOptions';
  static const backendActionLoadJobLogs = 'backendActionLoadJobLogs';
  static const backendActionLoadEntryLogs = 'backendActionLoadEntryLogs';
  static const backendActionStartDownload = 'backendActionStartDownload';
  static const backendActionPauseJob = 'backendActionPauseJob';
  static const backendActionResumeJob = 'backendActionResumeJob';
  static const backendActionCancelJob = 'backendActionCancelJob';
  static const backendActionRetryJob = 'backendActionRetryJob';
  static const backendActionRetryEntries = 'backendActionRetryEntries';
  static const backendActionDeleteJob = 'backendActionDeleteJob';
  static const backendActionSendPlaylistSelection =
      'backendActionSendPlaylistSelection';
  static const preferenceDropdownDialogCloseTooltip =
      'preferenceDropdownDialogCloseTooltip';
  static const preferenceDropdownDialogValueLabel =
      'preferenceDropdownDialogValueLabel';
  static const preferenceDropdownDialogSearchLabel =
      'preferenceDropdownDialogSearchLabel';
  static const preferenceDropdownDialogNoResults =
      'preferenceDropdownDialogNoResults';
  static const jobLinkUnavailable = 'jobLinkUnavailable';
  static const jobLinkInvalid = 'jobLinkInvalid';
  static const jobLinkOpenFailed = 'jobLinkOpenFailed';
  static const jobKindPlaylist = 'jobKindPlaylist';
  static const jobKindVideo = 'jobKindVideo';
  static const jobPlaylistItemCount = 'jobPlaylistItemCount';
  static const jobProgressPercent = 'jobProgressPercent';
  static const jobPlaylistSummaryCounts = 'jobPlaylistSummaryCounts';
  static const jobPlaylistSummaryPercent = 'jobPlaylistSummaryPercent';
  static const jobPlaylistOpeningSelection = 'jobPlaylistOpeningSelection';
  static const jobPlaylistSelectItemsPrompt = 'jobPlaylistSelectItemsPrompt';
  static const jobDetailsAction = 'jobDetailsAction';
  static const jobSelectItemsAction = 'jobSelectItemsAction';
  static const jobPauseAction = 'jobPauseAction';
  static const jobPauseRequested = 'jobPauseRequested';
  static const jobPauseFailed = 'jobPauseFailed';
  static const jobResumeAction = 'jobResumeAction';
  static const jobResumeSuccess = 'jobResumeSuccess';
  static const jobResumeFailed = 'jobResumeFailed';
  static const jobContinueDownloadAction = 'jobContinueDownloadAction';
  static const jobContinueRequested = 'jobContinueRequested';
  static const jobContinueFailed = 'jobContinueFailed';
  static const jobRetryAction = 'jobRetryAction';
  static const jobRetryRequested = 'jobRetryRequested';
  static const jobRetryFailed = 'jobRetryFailed';
  static const jobRetryEntriesAction = 'jobRetryEntriesAction';
  static const jobRetryEntriesRequested = 'jobRetryEntriesRequested';
  static const jobRetryEntriesFailed = 'jobRetryEntriesFailed';
  static const jobCancelAction = 'jobCancelAction';
  static const jobCancelRequested = 'jobCancelRequested';
  static const jobCancelFailed = 'jobCancelFailed';
  static const jobDeleteAction = 'jobDeleteAction';
  static const jobDeleteSuccess = 'jobDeleteSuccess';
  static const jobDeleteFailed = 'jobDeleteFailed';
  static const jobOpenLinkAction = 'jobOpenLinkAction';
  static const jobOpenFileAction = 'jobOpenFileAction';
  static const jobOpenFileSuccess = 'jobOpenFileSuccess';
  static const jobOpenFileFailed = 'jobOpenFileFailed';
  static const jobActionsMenuTooltip = 'jobActionsMenuTooltip';
  static const jobPlaylistBannerCollectingSemantics =
      'jobPlaylistBannerCollectingSemantics';
  static const jobPlaylistBannerSelectionSemantics =
      'jobPlaylistBannerSelectionSemantics';
  static const jobPlaylistBannerCollectingDescription =
      'jobPlaylistBannerCollectingDescription';
  static const jobPlaylistBannerSelectionDescription =
      'jobPlaylistBannerSelectionDescription';
  static const jobPlaylistBannerSelectButton = 'jobPlaylistBannerSelectButton';
  static const jobCardOpenDetailsHint = 'jobCardOpenDetailsHint';
  static const jobCardSemanticsStatus = 'jobCardSemanticsStatus';
  static const jobCardSemanticsProgress = 'jobCardSemanticsProgress';
  static const jobCardSemanticsRequireSelection =
      'jobCardSemanticsRequireSelection';
  static const jobCardSemanticsError = 'jobCardSemanticsError';
  static const jobPlaylistFailureSingleFailed =
      'jobPlaylistFailureSingleFailed';
  static const jobPlaylistFailureMultipleFailed =
      'jobPlaylistFailureMultipleFailed';
  static const jobPlaylistFailureSinglePending =
      'jobPlaylistFailureSinglePending';
  static const jobPlaylistFailureMultiplePending =
      'jobPlaylistFailureMultiplePending';
  static const jobPlaylistFailurePendingSummary =
      'jobPlaylistFailurePendingSummary';
  static const jobPlaylistFailureInQueueHint = 'jobPlaylistFailureInQueueHint';
  static const jobPlaylistFailureWaitForCompletion =
      'jobPlaylistFailureWaitForCompletion';
  static const jobPlaylistFailureRetryMultiple =
      'jobPlaylistFailureRetryMultiple';
  static const jobPlaylistFailureRetrySingle = 'jobPlaylistFailureRetrySingle';
  static const jobPlaylistFailureViewDetails = 'jobPlaylistFailureViewDetails';
  static const jobPlaylistFailureEntryLabel = 'jobPlaylistFailureEntryLabel';
  static const jobPlaylistFailureLastError = 'jobPlaylistFailureLastError';
  static const playlistTitleFallback = 'playlistTitleFallback';
  static const playlistBackToDownloads = 'playlistBackToDownloads';
  static const playlistViewJobDetailsTooltip = 'playlistViewJobDetailsTooltip';
  static const playlistLoadFailed = 'playlistLoadFailed';
  static const playlistMissingJob = 'playlistMissingJob';
  static const playlistBackAction = 'playlistBackAction';
  static const playlistEntriesTitle = 'playlistEntriesTitle';
  static const playlistEntriesPending = 'playlistEntriesPending';
  static const playlistEntriesUnavailable = 'playlistEntriesUnavailable';
  static const playlistEntryRetryAction = 'playlistEntryRetryAction';
  static const playlistDialogFilterLabel = 'playlistDialogFilterLabel';
  static const playlistDialogSortOriginal = 'playlistDialogSortOriginal';
  static const playlistDialogSortTitle = 'playlistDialogSortTitle';
  static const playlistDialogSortDuration = 'playlistDialogSortDuration';
  static const playlistDialogSortChannel = 'playlistDialogSortChannel';
  static const playlistDialogSortAscending = 'playlistDialogSortAscending';
  static const playlistDialogSortDescending = 'playlistDialogSortDescending';
  static const playlistDialogDownloadAll = 'playlistDialogDownloadAll';
  static const playlistDialogDownloadSelection =
      'playlistDialogDownloadSelection';
  static const playlistDialogAwaitingEntries = 'playlistDialogAwaitingEntries';
  static const playlistDialogItemsReceivedOfTotal =
      'playlistDialogItemsReceivedOfTotal';
  static const playlistDialogItemsTotal = 'playlistDialogItemsTotal';
  static const playlistDialogItemsReceived = 'playlistDialogItemsReceived';
  static const playlistDialogColumnDuration = 'playlistDialogColumnDuration';
  static const playlistDialogColumnChannel = 'playlistDialogColumnChannel';
  static const playlistDialogColumnTitle = 'playlistDialogColumnTitle';
  static const playlistDialogEntryFallbackTitle =
      'playlistDialogEntryFallbackTitle';
  static const jobDetailTitleFallback = 'jobDetailTitleFallback';
  static const jobDetailViewParentAction = 'jobDetailViewParentAction';
  static const jobDetailRefreshAction = 'jobDetailRefreshAction';
  static const jobDetailPlaylistDetailsAction =
      'jobDetailPlaylistDetailsAction';
  static const jobDetailMissingJobMessage = 'jobDetailMissingJobMessage';
  static const jobDetailOptionsTab = 'jobDetailOptionsTab';
  static const jobDetailLogsTab = 'jobDetailLogsTab';
  static const jobDetailNoOptions = 'jobDetailNoOptions';
  static const jobDetailOptionsTitle = 'jobDetailOptionsTitle';
  static const jobDetailOptionsSubtitle = 'jobDetailOptionsSubtitle';
  static const jobDetailNoLogs = 'jobDetailNoLogs';
  static const jobDetailLogsTitle = 'jobDetailLogsTitle';
  static const jobDetailLogsSubtitle = 'jobDetailLogsSubtitle';
  static const jobDetailCopyLogs = 'jobDetailCopyLogs';
  static const jobDetailReloadSection = 'jobDetailReloadSection';
  static const jobDetailReloadAction = 'jobDetailReloadAction';
  static const jobDetailLogsCopied = 'jobDetailLogsCopied';
  static const jobDetailLogLineSemantics = 'jobDetailLogLineSemantics';
  static const jobStatusDownloading = 'jobStatusDownloading';
  static const jobStatusFinished = 'jobStatusFinished';
  static const jobStatusFinishedWithErrors = 'jobStatusFinishedWithErrors';
  static const jobStatusError = 'jobStatusError';
  static const jobStatusProcessing = 'jobStatusProcessing';
  static const jobStatusPaused = 'jobStatusPaused';
  static const jobStatusPausing = 'jobStatusPausing';
  static const jobStatusCancelling = 'jobStatusCancelling';
  static const jobStatusQueued = 'jobStatusQueued';
  static const jobStatusCancelled = 'jobStatusCancelled';
  static const jobStatusUnknown = 'jobStatusUnknown';
  static const jobStageDownloadingFragments = 'jobStageDownloadingFragments';
  static const jobStageMerging = 'jobStageMerging';
  static const jobStageExtractingInfo = 'jobStageExtractingInfo';
  static const jobStageWaitingForItems = 'jobStageWaitingForItems';
  static const jobStageWaitingForSelection = 'jobStageWaitingForSelection';
  static const jobStageProcessingThumbnails = 'jobStageProcessingThumbnails';
  static const jobStageEmbeddingSubtitles = 'jobStageEmbeddingSubtitles';
  static const jobStageEmbeddingMetadata = 'jobStageEmbeddingMetadata';
  static const jobStageEmbeddingThumbnail = 'jobStageEmbeddingThumbnail';
  static const jobStageWritingMetadata = 'jobStageWritingMetadata';
  static const jobStageDownloadFinished = 'jobStageDownloadFinished';
  static const jobStageQueued = 'jobStageQueued';
  static const jobStagePreparing = 'jobStagePreparing';
  static const jobStageProcessingNamed = 'jobStageProcessingNamed';
  static const jobStagePreparingNamed = 'jobStagePreparingNamed';
  static const jobStagePostprocessingComplete =
      'jobStagePostprocessingComplete';
  static const jobStageExtractingAudio = 'jobStageExtractingAudio';
  static const jobStageProcessingWithFfmpeg = 'jobStageProcessingWithFfmpeg';
  static const jobStageProcessingVideo = 'jobStageProcessingVideo';
  static const jobStagePreparingThumbnails = 'jobStagePreparingThumbnails';
  static const jobStagePreparingVideoResources =
      'jobStagePreparingVideoResources';
  static const jobStagePreparingMetadata = 'jobStagePreparingMetadata';
  static const notificationProgressChannelName =
      'notificationProgressChannelName';
  static const notificationProgressChannelDescription =
      'notificationProgressChannelDescription';
  static const notificationTerminalChannelName =
      'notificationTerminalChannelName';
  static const notificationTerminalChannelDescription =
      'notificationTerminalChannelDescription';
  static const notificationPlaylistAttentionChannelName =
      'notificationPlaylistAttentionChannelName';
  static const notificationPlaylistAttentionChannelDescription =
      'notificationPlaylistAttentionChannelDescription';
  static const notificationLinuxDefaultAction =
      'notificationLinuxDefaultAction';
  static const notificationTerminalPlaylistSummary =
      'notificationTerminalPlaylistSummary';
  static const notificationTerminalSavedTo = 'notificationTerminalSavedTo';
  static const notificationTerminalSuccess = 'notificationTerminalSuccess';
  static const notificationTerminalFailure = 'notificationTerminalFailure';
  static const notificationTerminalCancelled = 'notificationTerminalCancelled';
  static const notificationTitleFallback = 'notificationTitleFallback';
  static const notificationMetricEta = 'notificationMetricEta';
  static const notificationMetricSpeed = 'notificationMetricSpeed';
  static const notificationActionOpen = 'notificationActionOpen';
  static const notificationActionRetry = 'notificationActionRetry';
  static const notificationActionDismiss = 'notificationActionDismiss';
  static const downloadServiceJobResponseMissingId =
      'downloadServiceJobResponseMissingId';
  static const downloadServicePreviewUrlRequired =
      'downloadServicePreviewUrlRequired';
  static const downloadServiceJobIdRequired = 'downloadServiceJobIdRequired';
  static const downloadServiceTooManyRedirects =
      'downloadServiceTooManyRedirects';
  static const downloadServiceInvalidJson = 'downloadServiceInvalidJson';
  static const downloadServiceTimeoutSeconds = 'downloadServiceTimeoutSeconds';
  static const downloadServiceTimeoutExpectedDuration =
      'downloadServiceTimeoutExpectedDuration';
  static const downloadServiceTimeout = 'downloadServiceTimeout';
  static const downloadServiceSocketError = 'downloadServiceSocketError';
  static const downloadServiceIoError = 'downloadServiceIoError';
  static const downloadServiceNetworkError = 'downloadServiceNetworkError';

  static const List<String> values = <String>[
    homeTitle,
    settingsTitle,
    quickSettings,
    enterUrl,
    download,
    general,
    network,
    video,
    downloadSection,
    mapKeyLabel,
    mapValueLabel,
    addEntry,
    addItem,
    textMode,
    listMode,
    mapMode,
    suggestions,
    customValue,
    preferencePickerSelectFolderTitle,
    preferencePickerUseFolderAction,
    preferencePickerSelectFileTitle,
    preferencePickerUseFileAction,
    preferencePickerGrantStoragePermission,
    preferencePickerNoStorageLocations,
    preferencePickerPermissionDenied,
    preferencePickerFilesystemUnavailable,
    preferencePickerFilePickerUnavailable,
    preferencePickerSystemPickerUnavailable,
    preferencePickerGoUp,
    preferencePickerUserFolder,
    preferencePickerSystemLabel,
    preferencePickerDriveLabel,
    preferencePickerInternalStorage,
    preferencePickerSdCardLabel,
    preferencePickerMainDisk,
    preferencePickerTooltipFolder,
    preferenceControlNotImplemented,
    offLabel,
    removeItem,
    removeEntry,
    editEntry,
    invalidMapFormat,
    invalidMapKey,
    all,
    best,
    none,
    noOverride,
    homeTabAll,
    homeTabInProgress,
    homeTabCompleted,
    homeTabError,
    homeEmptyAll,
    homeEmptyInProgress,
    homeEmptyCompleted,
    homeEmptyError,
    homeThumbnailCacheCleared,
    homeThumbnailCacheClearError,
    homeThumbnailCacheTooltip,
    homePlaylistPreparing,
    homePlaylistCollectingDescription,
    homeOptionsTitle,
    homeFolderOptionsTitle,
    homeLanguageButtonTooltip,
    homeThemeToggleTooltip,
    homeSettingsTooltip,
    homeFormatFabTooltip,
    homeFolderFabTooltip,
    homePasteButtonTooltip,
    homeCloseAction,
    homeLanguagePickerTitle,
    homePaginationShow,
    homePaginationPerPage,
    homePaginationRangeLabel,
    homePaginationNoItems,
    homePaginationFirst,
    homePaginationPrevious,
    homePaginationNext,
    homePaginationLast,
    homePaginationPageStatus,
    homeDownloadStarted,
    homeDownloadFailed,
    homeBackendStatusUnknown,
    homeBackendStatusUnpacking,
    homeBackendStatusStarting,
    homeBackendStatusStopped,
    homeBackendStatusInstallReady,
    homeBackendStatusDownloadingUpdate,
    homeBackendStatusUpdateAvailable,
    homeBackendStatusCheckingUpdates,
    homeBackendStatusRunning,
    homeBackendActionDisabledUnknown,
    homeBackendActionDisabledUnpacking,
    homeBackendActionDisabledStarting,
    homeBackendActionDisabledStopped,
    backendStatusTitle,
    backendStatusUnknownVersion,
    backendStatusUnknownPlatform,
    backendStatusPrimaryDownloading,
    backendStatusPrimaryInstall,
    backendStatusPrimarySearching,
    backendStatusPrimaryDownload,
    backendStatusPrimaryUpToDate,
    backendStatusSnackPreparing,
    backendStatusSnackReady,
    backendStatusSnackInstalling,
    backendStatusOpenLinkInvalid,
    backendStatusOpenLinkFailed,
    backendStatusHeaderLabel,
    backendStatusBadgeActive,
    backendStatusBadgeBusy,
    backendStatusBadgeStopped,
    backendStatusBadgeUnknown,
    backendStatusDescription,
    backendStatusUpdateCardTitle,
    backendStatusAppInfoTitle,
    backendStatusServiceNameLabel,
    backendStatusDescriptionLabel,
    backendStatusEnvironmentLabel,
    backendStatusVersionLabel,
    backendStatusHostPortLabel,
    backendStatusBackendBaseLabel,
    backendStatusApiBaseLabel,
    backendStatusOverviewSocketLabel,
    backendStatusJobSocketLabel,
    backendStatusTimeoutLabel,
    backendStatusViewCodeAction,
    backendStatusDonatePatreonAction,
    backendStatusDonateBuyMeACoffeeAction,
    backendStatusDeveloperLabel,
    backendStatusVersionPlatform,
    backendStatusTooltipRefresh,
    backendStatusTooltipDownload,
    backendStatusTooltipDownloading,
    backendStatusTooltipInstall,
    backendOverlayShowAnimationTooltip,
    backendOverlayHideAnimationTooltip,
    backendOverlayCycleAnimationTooltip,
    backendOverlayReloadAnimationTooltip,
    homePathsEnsureDownloads,
    initialPermissionsTitle,
    initialPermissionsSubtitle,
    initialPermissionsLanguageLabel,
    initialPermissionsContinueButton,
    initialPermissionsRefreshButton,
    initialPermissionsNotificationsTitle,
    initialPermissionsNotificationsDescription,
    initialPermissionsManageStorageTitle,
    initialPermissionsManageStorageDescription,
    initialPermissionsLegacyStorageTitle,
    initialPermissionsLegacyStorageDescription,
    initialPermissionsOverlayTitle,
    initialPermissionsOverlayDescription,
    initialPermissionsStatusGranted,
    initialPermissionsStatusDenied,
    initialPermissionsStatusPermanentlyDenied,
    initialPermissionsStatusNotRequired,
    initialPermissionsStatusUnknown,
    initialPermissionsStatusUnsupported,
    initialPermissionsRecommendedLabel,
    initialPermissionsOptionalLabel,
    initialPermissionsActionGrant,
    initialPermissionsActionSettings,
    backendWaitActionSuffix,
    backendWaitUnpacking,
    backendWaitStarting,
    backendWaitStopped,
    backendWaitUnknown,
    backendWaitConnectionFailed,
    backendActionSyncDownloads,
    backendActionRefreshDownloads,
    backendActionFetchPreview,
    backendActionLoadPlaylist,
    backendActionLoadJobOptions,
    backendActionLoadEntryOptions,
    backendActionLoadJobLogs,
    backendActionLoadEntryLogs,
    backendActionStartDownload,
    backendActionPauseJob,
    backendActionResumeJob,
    backendActionCancelJob,
    backendActionRetryJob,
    backendActionRetryEntries,
    backendActionDeleteJob,
    backendActionSendPlaylistSelection,
    preferenceDropdownDialogCloseTooltip,
    preferenceDropdownDialogValueLabel,
    preferenceDropdownDialogSearchLabel,
    preferenceDropdownDialogNoResults,
    jobLinkUnavailable,
    jobLinkInvalid,
    jobLinkOpenFailed,
    jobKindPlaylist,
    jobKindVideo,
    jobPlaylistItemCount,
    jobProgressPercent,
    jobPlaylistSummaryCounts,
    jobPlaylistSummaryPercent,
    jobPlaylistOpeningSelection,
    jobPlaylistSelectItemsPrompt,
    jobDetailsAction,
    jobSelectItemsAction,
    jobPauseAction,
    jobPauseRequested,
    jobPauseFailed,
    jobResumeAction,
    jobResumeSuccess,
    jobResumeFailed,
    jobContinueDownloadAction,
    jobContinueRequested,
    jobContinueFailed,
    jobRetryAction,
    jobRetryRequested,
    jobRetryFailed,
    jobRetryEntriesAction,
    jobRetryEntriesRequested,
    jobRetryEntriesFailed,
    jobCancelAction,
    jobCancelRequested,
    jobCancelFailed,
    jobDeleteAction,
    jobDeleteSuccess,
    jobDeleteFailed,
    jobOpenLinkAction,
    jobOpenFileAction,
    jobOpenFileSuccess,
    jobOpenFileFailed,
    jobActionsMenuTooltip,
    jobPlaylistBannerCollectingSemantics,
    jobPlaylistBannerSelectionSemantics,
    jobPlaylistBannerCollectingDescription,
    jobPlaylistBannerSelectionDescription,
    jobPlaylistBannerSelectButton,
    jobCardOpenDetailsHint,
    jobCardSemanticsStatus,
    jobCardSemanticsProgress,
    jobCardSemanticsRequireSelection,
    jobCardSemanticsError,
    jobPlaylistFailureSingleFailed,
    jobPlaylistFailureMultipleFailed,
    jobPlaylistFailureSinglePending,
    jobPlaylistFailureMultiplePending,
    jobPlaylistFailurePendingSummary,
    jobPlaylistFailureInQueueHint,
    jobPlaylistFailureWaitForCompletion,
    jobPlaylistFailureRetryMultiple,
    jobPlaylistFailureRetrySingle,
    jobPlaylistFailureViewDetails,
    jobPlaylistFailureEntryLabel,
    jobPlaylistFailureLastError,
    playlistTitleFallback,
    playlistBackToDownloads,
    playlistViewJobDetailsTooltip,
    playlistLoadFailed,
    playlistMissingJob,
    playlistBackAction,
    playlistEntriesTitle,
    playlistEntriesPending,
    playlistEntriesUnavailable,
    playlistEntryRetryAction,
    playlistDialogFilterLabel,
    playlistDialogSortOriginal,
    playlistDialogSortTitle,
    playlistDialogSortDuration,
    playlistDialogSortChannel,
    playlistDialogSortAscending,
    playlistDialogSortDescending,
    playlistDialogDownloadAll,
    playlistDialogDownloadSelection,
    playlistDialogAwaitingEntries,
    playlistDialogItemsReceivedOfTotal,
    playlistDialogItemsTotal,
    playlistDialogItemsReceived,
    playlistDialogColumnDuration,
    playlistDialogColumnChannel,
    playlistDialogColumnTitle,
    playlistDialogEntryFallbackTitle,
    jobDetailTitleFallback,
    jobDetailViewParentAction,
    jobDetailRefreshAction,
    jobDetailPlaylistDetailsAction,
    jobDetailMissingJobMessage,
    jobDetailOptionsTab,
    jobDetailLogsTab,
    jobDetailNoOptions,
    jobDetailOptionsTitle,
    jobDetailOptionsSubtitle,
    jobDetailNoLogs,
    jobDetailLogsTitle,
    jobDetailLogsSubtitle,
    jobDetailCopyLogs,
    jobDetailReloadSection,
    jobDetailReloadAction,
    jobDetailLogsCopied,
    jobDetailLogLineSemantics,
    jobStatusDownloading,
    jobStatusFinished,
    jobStatusFinishedWithErrors,
    jobStatusError,
    jobStatusProcessing,
    jobStatusPaused,
    jobStatusPausing,
    jobStatusCancelling,
    jobStatusQueued,
    jobStatusCancelled,
    jobStatusUnknown,
    jobStageDownloadingFragments,
    jobStageMerging,
    jobStageExtractingInfo,
    jobStageWaitingForItems,
    jobStageWaitingForSelection,
    jobStageProcessingThumbnails,
    jobStageEmbeddingSubtitles,
    jobStageEmbeddingMetadata,
    jobStageEmbeddingThumbnail,
    jobStageWritingMetadata,
    jobStageDownloadFinished,
    jobStageQueued,
    jobStagePreparing,
    jobStageProcessingNamed,
    jobStagePreparingNamed,
    jobStagePostprocessingComplete,
    jobStageExtractingAudio,
    jobStageProcessingWithFfmpeg,
    jobStageProcessingVideo,
    jobStagePreparingThumbnails,
    jobStagePreparingVideoResources,
    jobStagePreparingMetadata,
    notificationProgressChannelName,
    notificationProgressChannelDescription,
    notificationTerminalChannelName,
    notificationTerminalChannelDescription,
    notificationPlaylistAttentionChannelName,
    notificationPlaylistAttentionChannelDescription,
    notificationLinuxDefaultAction,
    notificationTerminalPlaylistSummary,
    notificationTerminalSavedTo,
    notificationTerminalSuccess,
    notificationTerminalFailure,
    notificationTerminalCancelled,
    notificationTitleFallback,
    notificationMetricEta,
    notificationMetricSpeed,
    notificationActionOpen,
    notificationActionRetry,
    notificationActionDismiss,
    downloadServiceJobResponseMissingId,
    downloadServicePreviewUrlRequired,
    downloadServiceJobIdRequired,
    downloadServiceTooManyRedirects,
    downloadServiceInvalidJson,
    downloadServiceTimeoutSeconds,
    downloadServiceTimeoutExpectedDuration,
    downloadServiceTimeout,
    downloadServiceSocketError,
    downloadServiceIoError,
    downloadServiceNetworkError,
  ];
}

class ErrorStringKey {
  ErrorStringKey._();

  static const tokenMissingOrInvalid = 'token_missing_or_invalid';
  static const urlsRequired = 'urls_required';
  static const jobNotFound = 'job_not_found';
  static const jobDeleteConflictActive = 'job_delete_conflict_active';
  static const jobStatusConflict = 'job_status_conflict';
  static const sinceMustBeInteger = 'since_must_be_integer';
  static const entryIndexInvalid = 'entry_index_invalid';
  static const limitMustBeInteger = 'limit_must_be_integer';
  static const limitGreaterThanZero = 'limit_greater_than_zero';
  static const offsetMustBeInteger = 'offset_must_be_integer';
  static const offsetMustBeNonNegative = 'offset_must_be_non_negative';
  static const playlistEntriesUnavailable = 'playlist_entries_unavailable';
  static const playlistMetadataUnavailable = 'playlist_metadata_unavailable';
  static const dryRunFailed = 'dry_run_failed';
  static const previewFailed = 'preview_failed';
  static const profilesNotImplemented = 'profiles_not_implemented';
  static const downloadError = 'download_error';
  static const invalidJsonPayload = 'invalid_json_payload';
  static const optionsNotObject = 'options_not_object';
  static const payloadNotObject = 'payload_not_object';
  static const actionRequired = 'action_required';
  static const unknownAction = 'unknown_action';
  static const playlistSelectionReceived = 'playlist_selection_received';
  static const identifyingContent = 'identifying_content';
  static const downloadsFailed = 'downloads_failed';

  static const List<String> values = <String>[
    tokenMissingOrInvalid,
    urlsRequired,
    jobNotFound,
    jobDeleteConflictActive,
    jobStatusConflict,
    sinceMustBeInteger,
    entryIndexInvalid,
    limitMustBeInteger,
    limitGreaterThanZero,
    offsetMustBeInteger,
    offsetMustBeNonNegative,
    playlistEntriesUnavailable,
    playlistMetadataUnavailable,
    dryRunFailed,
    previewFailed,
    profilesNotImplemented,
    downloadError,
    invalidJsonPayload,
    optionsNotObject,
    payloadNotObject,
    actionRequired,
    unknownAction,
    playlistSelectionReceived,
    identifyingContent,
    downloadsFailed,
  ];
}

class I18n {
  I18n._();

  static const String _defaultFallbackLocale = 'en';
  static String _fallbackLocale = _defaultFallbackLocale;

  static String get fallbackLocale => _fallbackLocale;

  static const List<String> supportedLanguageCodes = <String>[
    'aa',
    'ab',
    'ae',
    'af',
    'ak',
    'am',
    'an',
    'ar',
    'as',
    'av',
    'ay',
    'az',
    'ba',
    'be',
    'bg',
    'bi',
    'bm',
    'bn',
    'bo',
    'br',
    'bs',
    'ca',
    'ce',
    'ch',
    'co',
    'cr',
    'cs',
    'cu',
    'cv',
    'cy',
    'da',
    'de',
    'dv',
    'dz',
    'ee',
    'el',
    'en',
    'eo',
    'es',
    'et',
    'eu',
    'fa',
    'ff',
    'fi',
    'fj',
    'fo',
    'fr',
    'fy',
    'ga',
    'gd',
    'gl',
    'gn',
    'gu',
    'gv',
    'ha',
    'he',
    'hi',
    'ho',
    'hr',
    'ht',
    'hu',
    'hy',
    'hz',
    'ia',
    'id',
    'ie',
    'ig',
    'ii',
    'ik',
    'io',
    'is',
    'it',
    'iu',
    'ja',
    'jv',
    'ka',
    'kg',
    'ki',
    'kj',
    'kk',
    'kl',
    'km',
    'kn',
    'ko',
    'kr',
    'ks',
    'ku',
    'kv',
    'kw',
    'ky',
    'la',
    'lb',
    'lg',
    'li',
    'ln',
    'lo',
    'lt',
    'lu',
    'lv',
    'mg',
    'mh',
    'mi',
    'mk',
    'ml',
    'mn',
    'mr',
    'ms',
    'mt',
    'my',
    'na',
    'nb',
    'nd',
    'ne',
    'ng',
    'nl',
    'nn',
    'no',
    'nr',
    'nv',
    'ny',
    'oc',
    'oj',
    'om',
    'or',
    'os',
    'pa',
    'pi',
    'pl',
    'ps',
    'pt',
    'qu',
    'rm',
    'rn',
    'ro',
    'ru',
    'rw',
    'sa',
    'sc',
    'sd',
    'se',
    'sg',
    'si',
    'sk',
    'sl',
    'sm',
    'sn',
    'so',
    'sq',
    'sr',
    'ss',
    'st',
    'su',
    'sv',
    'sw',
    'ta',
    'te',
    'tg',
    'th',
    'ti',
    'tk',
    'tl',
    'tn',
    'to',
    'tr',
    'ts',
    'tt',
    'tw',
    'ty',
    'ug',
    'uk',
    'ur',
    'uz',
    've',
    'vi',
    'vo',
    'wa',
    'wo',
    'xh',
    'yi',
    'yo',
    'za',
    'zh',
    'zu',
  ];
  static const List<String> _bundleFileNames = <String>['ui', 'errors'];
  static const String _preferencesFileName = 'preferences';

  static final Map<String, Map<String, String>> _cache =
      <String, Map<String, String>>{};
  static final Map<String, Map<String, String>> _mergedBundles =
      <String, Map<String, String>>{};
  static final Map<String, Future<Map<String, String>>> _pendingLoads =
      <String, Future<Map<String, String>>>{};
  static final Map<String, Map<String, _PreferenceEntry>> _preferenceCache =
      <String, Map<String, _PreferenceEntry>>{};
  static final Map<String, Future<Map<String, _PreferenceEntry>>>
  _pendingPreferenceLoads = <String, Future<Map<String, _PreferenceEntry>>>{};
  static final Set<String> _supportedLanguageSet = Set<String>.unmodifiable(
    supportedLanguageCodes,
  );
  static Map<String, PreferenceLocalization>? _preferenceLocalizationView;

  static void configure({String? fallbackLocale}) {
    if (fallbackLocale != null) {
      _setFallbackLocale(fallbackLocale);
    }
  }

  static void _setFallbackLocale(String localeCode) {
    final normalized = _normalizeForFallback(localeCode);
    if (_fallbackLocale == normalized) {
      return;
    }
    _fallbackLocale = normalized;
    _cache.clear();
    _mergedBundles.clear();
    _pendingLoads.clear();
    _preferenceCache.clear();
    _pendingPreferenceLoads.clear();
    _preferenceLocalizationView = null;
  }

  static Future<void> preloadAll() async {
    await Future.wait(<Future<void>>[
      _ensureLocaleLoaded(fallbackLocale).then((_) => null),
      _ensurePreferenceLocaleLoaded(fallbackLocale).then((_) => null),
    ]);
    final others = supportedLanguageCodes.where(
      (code) => code != fallbackLocale,
    );
    await Future.wait(
      others.map((code) async {
        await _ensureLocaleLoaded(code);
        await _ensurePreferenceLocaleLoaded(code);
      }),
    );
  }

  static Future<Map<String, String>> ensureLocale(String localeCode) {
    return _ensureLocaleLoaded(localeCode);
  }

  static Future<Map<String, String>> _ensureLocaleLoaded(String localeCode) {
    final normalized = normalizeLocaleCode(localeCode);
    final existing = _cache[normalized];
    if (existing != null) {
      return Future<Map<String, String>>.value(existing);
    }
    final pending = _pendingLoads[normalized];
    if (pending != null) {
      return pending;
    }
    final future = _loadLocale(normalized);
    _pendingLoads[normalized] = future;
    future.whenComplete(() => _pendingLoads.remove(normalized));
    return future;
  }

  static Future<Map<String, String>> _loadLocale(String localeCode) async {
    final entries = <String, String>{};
    for (final bundle in _bundleFileNames) {
      final assetPath = 'i18n/locales/$localeCode/$bundle.jsonc';
      try {
        final raw = await rootBundle.loadString(assetPath);
        final parsed = jsoncDecode(raw);
        if (parsed is Map) {
          parsed.forEach((key, value) {
            if (key == null || value == null) {
              return;
            }
            entries[key.toString()] = value.toString();
          });
        } else {
          throw FormatException('The asset $assetPath must contain an object.');
        }
      } on FlutterError {
        final isFallbackUi =
            localeCode == fallbackLocale && bundle == _bundleFileNames.first;
        if (isFallbackUi) {
          rethrow;
        }
        continue;
      }
    }
    final map = Map<String, String>.unmodifiable(entries);
    _cache[localeCode] = map;
    _mergedBundles.remove(localeCode);
    return map;
  }

  static String translate(String key, {String? localeCode}) {
    final normalized = normalizeLocaleCode(localeCode);
    final localeMap = _cache[normalized];
    if (localeMap != null) {
      final candidate = localeMap[key];
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }
    final fallbackMap = _cache[fallbackLocale];
    if (fallbackMap != null) {
      final candidate = fallbackMap[key];
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    } else {
      throw StateError(
        'I18n fallback locale not loaded. Call I18n.preloadAll() during startup.',
      );
    }
    return key;
  }

  static Map<String, String> bundle(String localeCode) {
    final normalized = normalizeLocaleCode(localeCode);
    final existingBundle = _mergedBundles[normalized];
    if (existingBundle != null) {
      return existingBundle;
    }
    final fallbackMap = _cache[fallbackLocale];
    if (fallbackMap == null) {
      throw StateError(
        'I18n fallback locale not loaded. Call I18n.preloadAll() during startup.',
      );
    }
    final localeMap = _cache[normalized];
    if (localeMap == null || normalized == fallbackLocale) {
      _mergedBundles[normalized] = fallbackMap;
      return fallbackMap;
    }
    final merged = Map<String, String>.from(fallbackMap)..addAll(localeMap);
    final immutable = Map<String, String>.unmodifiable(merged);
    _mergedBundles[normalized] = immutable;
    return immutable;
  }

  static String normalizeLocaleCode(String? localeCode) {
    if (localeCode == null || localeCode.trim().isEmpty) {
      return fallbackLocale;
    }
    final canonical = localeCode.replaceAll('_', '-').toLowerCase();
    if (_supportedLanguageSet.contains(canonical)) {
      return canonical;
    }
    final base = canonical.split('-').first;
    if (_supportedLanguageSet.contains(base)) {
      return base;
    }
    return fallbackLocale;
  }

  static Map<String, PreferenceLocalization> preferenceLocalizations() {
    final cached = _preferenceLocalizationView;
    if (cached != null) {
      return cached;
    }
    final fallbackPrefs = _preferenceCache[fallbackLocale];
    if (fallbackPrefs == null) {
      throw StateError(
        'Preference localizations not loaded. Call I18n.preloadAll() during startup.',
      );
    }
    final builders = <String, _PreferenceLocalizationBuilder>{};

    void mergeLocale(String locale, Map<String, _PreferenceEntry>? entries) {
      if (entries == null || entries.isEmpty) {
        return;
      }
      entries.forEach((key, entry) {
        final builder = builders.putIfAbsent(
          key,
          () => _PreferenceLocalizationBuilder(),
        );
        final name = entry.name;
        if (_hasContent(name)) {
          builder.names[locale] = name!.trim();
        }
        final description = entry.description;
        if (_hasContent(description)) {
          builder.descriptions[locale] = description!.trim();
        }
      });
    }

    mergeLocale(fallbackLocale, fallbackPrefs);
    for (final locale in supportedLanguageCodes) {
      if (locale == fallbackLocale) {
        continue;
      }
      mergeLocale(locale, _preferenceCache[locale]);
    }

    final view = Map<String, PreferenceLocalization>.unmodifiable(
      builders.map(
        (key, builder) => MapEntry(
          key,
          PreferenceLocalization(
            names: builder.names,
            descriptions: builder.descriptions,
          ),
        ),
      ),
    );
    _preferenceLocalizationView = view;
    return view;
  }

  static Future<Map<String, _PreferenceEntry>> _ensurePreferenceLocaleLoaded(
    String localeCode,
  ) {
    final normalized = normalizeLocaleCode(localeCode);
    final existing = _preferenceCache[normalized];
    if (existing != null) {
      return Future<Map<String, _PreferenceEntry>>.value(existing);
    }
    final pending = _pendingPreferenceLoads[normalized];
    if (pending != null) {
      return pending;
    }
    final future = _loadPreferenceLocale(normalized);
    _pendingPreferenceLoads[normalized] = future;
    future.whenComplete(() => _pendingPreferenceLoads.remove(normalized));
    return future;
  }

  static Future<Map<String, _PreferenceEntry>> _loadPreferenceLocale(
    String localeCode,
  ) async {
    final assetPath = 'i18n/locales/$localeCode/$_preferencesFileName.jsonc';
    try {
      final raw = await rootBundle.loadString(assetPath);
      final parsed = jsoncDecode(raw);
      if (parsed is! Map) {
        throw FormatException('The asset $assetPath must contain an object.');
      }
      final entries = <String, _PreferenceEntry>{};
      parsed.forEach((key, value) {
        if (key == null || value is! Map) {
          return;
        }
        final name = value['name']?.toString();
        final description = value['description']?.toString();
        if (!_hasContent(name) && !_hasContent(description)) {
          return;
        }
        entries[key.toString()] = _PreferenceEntry(name, description);
      });
      final map = Map<String, _PreferenceEntry>.unmodifiable(entries);
      _preferenceCache[localeCode] = map;
      _preferenceLocalizationView = null;
      return map;
    } on FlutterError {
      if (localeCode == fallbackLocale) {
        rethrow;
      }
      const empty = <String, _PreferenceEntry>{};
      _preferenceCache[localeCode] = empty;
      _preferenceLocalizationView = null;
      return empty;
    }
  }

  static bool _hasContent(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  static String _normalizeForFallback(String? localeCode) {
    if (localeCode == null || localeCode.trim().isEmpty) {
      return _defaultFallbackLocale;
    }
    final canonical = localeCode.replaceAll('_', '-').toLowerCase();
    if (_supportedLanguageSet.contains(canonical)) {
      return canonical;
    }
    final base = canonical.split('-').first;
    if (_supportedLanguageSet.contains(base)) {
      return base;
    }
    return _defaultFallbackLocale;
  }
}

class PreferenceLocalization {
  PreferenceLocalization({
    required Map<String, String> names,
    required Map<String, String> descriptions,
  }) : names = Map<String, String>.unmodifiable(names),
       descriptions = Map<String, String>.unmodifiable(descriptions);

  final Map<String, String> names;
  final Map<String, String> descriptions;
}

class _PreferenceEntry {
  const _PreferenceEntry(this.name, this.description);

  final String? name;
  final String? description;
}

class _PreferenceLocalizationBuilder {
  _PreferenceLocalizationBuilder();

  final Map<String, String> names = <String, String>{};
  final Map<String, String> descriptions = <String, String>{};
}

String resolveAppString(String key, String languageCode) {
  return I18n.translate(key, localeCode: languageCode);
}
