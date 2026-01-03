import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/data/models/playlist_preview.dart';
import 'package:vidra/data/preferences/preferences_registry.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/share/share_intent_coordinator.dart';
import 'package:vidra/share/share_intent_payload.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/initial_permissions_controller.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';
import 'package:vidra/ui/screens/initial_setup/initial_permissions_sheet.dart';
import 'package:vidra/ui/widgets/backend_status_indicator.dart';
import 'package:vidra/ui/widgets/jobs/download_job_card.dart';
import 'package:vidra/ui/models/preference_ui_models.dart';
import 'package:vidra/ui/widgets/preferences/preference_control_builder.dart';
import 'package:vidra/ui/widgets/preferences/preference_dropdown_control.dart';
import 'package:vidra/ui/widgets/settings/preference_tile.dart';
import 'package:vidra/ui/widgets/magic_options_sheet.dart';
import 'backend_status_screen.dart';
import 'job_detail_screen.dart';
import 'playlist_detail_screen.dart';
import 'playlist_selection_dialog.dart';

typedef PlaylistDialogLauncher =
    Future<PlaylistSelectionResult?> Function(
      BuildContext context,
      DownloadController controller,
      String jobId,
      PlaylistPreviewData previewData,
    );

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.playlistDialogLauncher,
    this.autoInitializeController = true,
  });

  final PlaylistDialogLauncher? playlistDialogLauncher;
  final bool autoInitializeController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _urlController;
  late final FocusNode _urlFocusNode;
  late final TabController _tabController;
  static const List<int> _pageSizeOptions = [6, 12, 24, 50];
  late List<int> _pageIndices;
  int _pageSize = _pageSizeOptions.first;
  static const double _advancedControlsBreakpoint = 760;
  static const double _compactControlMinWidth = 220;
  static final List<DataFormat> _urlDropFormats = <DataFormat>[
    Formats.uri,
    Formats.plainText,
    Formats.htmlText,
  ];
  static const Map<ShortcutActivator, Intent> _urlFieldPasteShortcuts = {
    SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
        PasteTextIntent(SelectionChangedCause.keyboard),
    SingleActivator(LogicalKeyboardKey.keyV, control: true, alt: true):
        PasteTextIntent(SelectionChangedCause.keyboard),
    SingleActivator(LogicalKeyboardKey.keyV, control: true, meta: true):
        PasteTextIntent(SelectionChangedCause.keyboard),
    SingleActivator(
      LogicalKeyboardKey.keyV,
      control: true,
      alt: true,
      shift: true,
    ): PasteTextIntent(
      SelectionChangedCause.keyboard,
    ),
    SingleActivator(
      LogicalKeyboardKey.keyV,
      control: true,
      meta: true,
      shift: true,
    ): PasteTextIntent(
      SelectionChangedCause.keyboard,
    ),
    SingleActivator(
      LogicalKeyboardKey.keyV,
      control: true,
      alt: true,
      meta: true,
    ): PasteTextIntent(
      SelectionChangedCause.keyboard,
    ),
    SingleActivator(
      LogicalKeyboardKey.keyV,
      control: true,
      alt: true,
      meta: true,
      shift: true,
    ): PasteTextIntent(
      SelectionChangedCause.keyboard,
    ),
  };
  DownloadController? _boundDownloadController;
  StreamSubscription<ShareIntentPayload>? _shareManualSubscription;
  bool _isHandlingPlaylistDialog = false;
  bool _showMagicFab = false;
  final Map<String, int> _playlistDialogDismissedEntryCounts = <String, int>{};
  final Set<String> _playlistDialogDeferNotified = <String>{};
  final Set<String> _manualPlaylistDialogRequests = <String>{};
  final Set<String> _autoOpenedPlaylistDialogs = <String>{};
  bool _isUrlDropHovered = false;

  PlaylistDialogLauncher get _effectivePlaylistDialogLauncher =>
      widget.playlistDialogLauncher ?? showPlaylistSelectionDialog;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _urlFocusNode = FocusNode();
    _tabController = TabController(length: 4, vsync: this);
    _pageIndices = List<int>.filled(4, 0, growable: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shareManualSubscription ??= context
        .read<ShareIntentCoordinator>()
        .manualFlowStream
        .listen(_handleManualSharePayload);
    final controller = context.read<DownloadController>();
    if (!identical(controller, _boundDownloadController)) {
      _boundDownloadController?.removeListener(_handleDownloadControllerTick);
      _boundDownloadController = controller;
      controller.addListener(_handleDownloadControllerTick);
      if (widget.autoInitializeController) {
        unawaited(controller.initialize());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handleDownloadControllerTick();
        }
      });
    }
  }

  @override
  void dispose() {
    _boundDownloadController?.removeListener(_handleDownloadControllerTick);
    _tabController.dispose();
    _urlController.dispose();
    _urlFocusNode.dispose();
    _shareManualSubscription?.cancel();
    super.dispose();
  }

  Future<void> _clearThumbnailCache() async {
    final localizations = VidraLocalizations.of(context);
    try {
      await DefaultCacheManager().emptyCache();
      painting.imageCache.clear();
      painting.imageCache.clearLiveImages();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizations.ui(AppStringKey.homeThumbnailCacheCleared),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${localizations.ui(AppStringKey.homeThumbnailCacheClearError)}: $error',
          ),
        ),
      );
    }
  }

  void _handleDownloadControllerTick() {
    if (!mounted || _isHandlingPlaylistDialog) {
      return;
    }
    final controller = _boundDownloadController;
    if (controller == null) {
      return;
    }
    final jobId = controller.takeNextPlaylistSelectionRequest();
    if (jobId == null) {
      return;
    }
    _isHandlingPlaylistDialog = true;
    unawaited(_presentPlaylistSelection(jobId));
  }

  void _handleManualPlaylistSelectionRequest(String jobId) {
    _manualPlaylistDialogRequests.add(jobId);
    _playlistDialogDismissedEntryCounts.remove(jobId);
    _playlistDialogDeferNotified.remove(jobId);
  }

  Future<void> _presentPlaylistSelection(String jobId) async {
    final controller = _boundDownloadController;
    if (controller == null) {
      _isHandlingPlaylistDialog = false;
      return;
    }
    var rescheduleDelay = Duration.zero;
    try {
      final localizations = VidraLocalizations.of(context);
      DownloadJobModel? job = controller.jobById(jobId);
      if (job == null) {
        _manualPlaylistDialogRequests.remove(jobId);
        _autoOpenedPlaylistDialogs.remove(jobId);
        controller.completePlaylistSelectionRequest(jobId);
        return;
      }
      final requiresEntries =
          job.playlist == null ||
          job.playlist!.entriesExternal ||
          job.playlist!.entries.isEmpty;
      if (requiresEntries) {
        try {
          await controller.loadPlaylist(jobId, includeEntries: true);
          job = controller.jobById(jobId) ?? job;
        } catch (_) {
          // Fallback to existing job snapshot if fetch fails
        }
      }
      if (job == null) {
        controller.completePlaylistSelectionRequest(jobId, keepQueued: true);
        return;
      }
      final DownloadJobModel effectiveJob = job;
      final bool manualRequest = _manualPlaylistDialogRequests.remove(jobId);
      final rawPreviewData = _buildPlaylistPreview(effectiveJob);
      PlaylistPreviewData? previewData =
          rawPreviewData ?? _buildPlaceholderPreviewData(effectiveJob);
      previewData ??= _buildEmergencyPreviewData(effectiveJob, localizations);
      if (!mounted) {
        rescheduleDelay = const Duration(seconds: 1);
        controller.requeuePlaylistSelection(jobId);
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      final preparingMessage = localizations.ui(
        AppStringKey.homePlaylistPreparing,
      );

      void showQueueSnack(String message) {
        if (messenger == null) {
          return;
        }
        if (!_playlistDialogDeferNotified.add(jobId)) {
          return;
        }
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 2),
            ),
          );
      }

      if (previewData == null) {
        controller.completePlaylistSelectionRequest(jobId, keepQueued: true);
        _autoOpenedPlaylistDialogs.remove(jobId);
        showQueueSnack(preparingMessage);
        return;
      }
      var playlist = previewData.playlist;

      if (playlist == null) {
        final fallbackPlaylist = _buildFallbackPlaylist(
          effectiveJob,
          previewData,
        );
        if (fallbackPlaylist == null) {
          controller.completePlaylistSelectionRequest(jobId, keepQueued: true);
          _autoOpenedPlaylistDialogs.remove(jobId);
          showQueueSnack(preparingMessage);
          return;
        }
        final mergedRaw = Map<String, dynamic>.from(previewData.raw);
        mergedRaw['playlist'] = fallbackPlaylist;
        previewData = PlaylistPreviewData.fromJson(mergedRaw);
        playlist = previewData.playlist;
      }
      _playlistDialogDeferNotified.remove(jobId);

      final entrySnapshot = _resolvePlaylistEntrySnapshot(
        effectiveJob,
        previewData,
      );
      final stillCollecting = controller.jobIsCollectingPlaylistEntries(jobId);
      final dismissedEntries = _playlistDialogDismissedEntryCounts[jobId];
      if (manualRequest) {
        _playlistDialogDismissedEntryCounts.remove(jobId);
      }
      if (stillCollecting) {
        _autoOpenedPlaylistDialogs.remove(jobId);
        final shouldDeferAutoDialog =
            !manualRequest &&
            dismissedEntries != null &&
            entrySnapshot.received <= dismissedEntries;
        if (shouldDeferAutoDialog) {
          _playlistDialogDismissedEntryCounts[jobId] = entrySnapshot.received;
          controller.completePlaylistSelectionRequest(jobId, keepQueued: true);
          return;
        }
      } else {
        _playlistDialogDismissedEntryCounts.remove(jobId);
      }

      if (!manualRequest) {
        final alreadyAutoOpened = !_autoOpenedPlaylistDialogs.add(jobId);
        if (alreadyAutoOpened) {
          controller.completePlaylistSelectionRequest(jobId, keepQueued: true);
          return;
        }
      }

      if (!mounted) {
        rescheduleDelay = const Duration(seconds: 1);
        controller.requeuePlaylistSelection(jobId);
        return;
      }
      final result = await _effectivePlaylistDialogLauncher(
        context,
        controller,
        jobId,
        previewData,
      );
      if (!mounted) {
        rescheduleDelay = const Duration(seconds: 1);
        controller.requeuePlaylistSelection(jobId);
        return;
      }
      if (result == null) {
        if (stillCollecting) {
          _playlistDialogDismissedEntryCounts[jobId] = entrySnapshot.received;
        }
        controller.completePlaylistSelectionRequest(jobId, keepQueued: true);
        return;
      }
      final indices = result.downloadAll ? null : result.selectedIndices;
      final success = await controller.submitPlaylistSelection(
        jobId,
        indices: indices,
      );
      if (success) {
        _playlistDialogDismissedEntryCounts.remove(jobId);
        _playlistDialogDeferNotified.remove(jobId);
        _autoOpenedPlaylistDialogs.remove(jobId);
      }
      if (!success) {
        rescheduleDelay = const Duration(seconds: 1);
      }
    } finally {
      _isHandlingPlaylistDialog = false;
      if (mounted) {
        if (rescheduleDelay <= Duration.zero) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _handleDownloadControllerTick();
            }
          });
        } else {
          Future<void>.delayed(rescheduleDelay, () {
            if (mounted) {
              _handleDownloadControllerTick();
            }
          });
        }
      }
    }
  }

  PlaylistPreviewData? _buildPlaylistPreview(DownloadJobModel job) {
    final previewJson = _buildPreviewMetadata(job);
    final playlistJson = _buildPlaylistMetadata(job);
    if (previewJson == null && playlistJson == null) {
      return null;
    }
    final payload = Map<String, dynamic>.from(
      previewJson ?? <String, dynamic>{},
    );
    if (playlistJson != null) {
      payload['playlist'] = playlistJson;
    }
    return PlaylistPreviewData.fromJson(payload);
  }

  Map<String, dynamic>? _buildPreviewMetadata(DownloadJobModel job) {
    final previewRaw = job.metadata['preview'];
    if (previewRaw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(previewRaw);
    }
    if (previewRaw is Map) {
      return previewRaw.cast<String, dynamic>();
    }
    final preview = job.preview;
    if (preview == null) {
      return null;
    }
    final thumbnails = preview.thumbnails
        .map(
          (thumb) => <String, dynamic>{
            'url': thumb.url,
            if (thumb.width != null) 'width': thumb.width,
            if (thumb.height != null) 'height': thumb.height,
            if (thumb.id != null) 'id': thumb.id,
          },
        )
        .where((thumb) => (thumb['url'] as String?)?.isNotEmpty ?? false)
        .toList(growable: false);
    final payload = <String, dynamic>{
      if (preview.title != null) 'title': preview.title,
      if (preview.description != null) 'description': preview.description,
      if (preview.thumbnailUrl != null) 'thumbnail_url': preview.thumbnailUrl,
      if (preview.bestThumbnailUrl != null)
        'thumbnail': preview.bestThumbnailUrl,
      if (preview.durationSeconds != null)
        'duration_seconds': preview.durationSeconds,
      if (preview.durationText != null) 'duration_text': preview.durationText,
      if (preview.uploader != null) 'uploader': preview.uploader,
      if (preview.channel != null) 'channel': preview.channel,
      if (preview.webpageUrl != null) 'webpage_url': preview.webpageUrl,
      if (preview.originalUrl != null) 'original_url': preview.originalUrl,
      if (preview.extractor != null) 'extractor': preview.extractor,
      if (preview.extractorId != null) 'extractor_id': preview.extractorId,
      if (preview.viewCount != null) 'view_count': preview.viewCount,
      if (preview.likeCount != null) 'like_count': preview.likeCount,
      if (preview.tags.isNotEmpty) 'tags': List<String>.from(preview.tags),
      if (thumbnails.isNotEmpty) 'thumbnails': thumbnails,
    };
    return payload.isEmpty ? null : payload;
  }

  Map<String, dynamic>? _buildPlaylistMetadata(DownloadJobModel job) {
    final playlistRaw = job.metadata['playlist'];
    if (playlistRaw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(playlistRaw);
    }
    if (playlistRaw is Map) {
      return playlistRaw.cast<String, dynamic>();
    }
    final summary = job.playlist;
    final preview = job.preview;
    if (summary == null && preview == null) {
      return null;
    }
    final summaryEntries = _summaryEntriesToMetadata(summary);
    final fallback = <String, dynamic>{
      'is_collecting_entries': true,
      'entries': summaryEntries ?? const <Map<String, dynamic>>[],
      if (summary?.id != null) 'id': summary!.id,
      if (summary?.title != null)
        'title': summary!.title
      else if (preview?.title != null)
        'title': preview!.title,
      if (summary?.uploader != null)
        'uploader': summary!.uploader
      else if (preview?.uploader != null)
        'uploader': preview!.uploader,
      if (summary?.channel != null)
        'channel': summary!.channel
      else if (preview?.channel != null)
        'channel': preview!.channel,
      if (summary?.thumbnailUrl != null)
        'thumbnail_url': summary!.thumbnailUrl
      else if (preview?.bestThumbnailUrl != null)
        'thumbnail_url': preview!.bestThumbnailUrl,
      if (summary?.description != null)
        'description': summary!.description
      else if (preview?.description != null)
        'description': preview!.description,
      if (summary?.descriptionShort != null)
        'description_short': summary!.descriptionShort
      else if (preview?.shortDescription() != null)
        'description_short': preview!.shortDescription(),
      if (summary?.webpageUrl != null)
        'webpage_url': summary!.webpageUrl
      else if (preview?.webpageUrl != null)
        'webpage_url': preview!.webpageUrl,
    };
    final inferredEntryCount =
        summary?.totalItems ??
        summary?.entryCount ??
        job.progress?.playlistTotalItems ??
        job.progress?.playlistCount;
    if (inferredEntryCount != null && inferredEntryCount > 0) {
      fallback['entry_count'] = inferredEntryCount;
      fallback['total_items'] = inferredEntryCount;
    }
    final received =
        summary?.completedItems ??
        job.progress?.playlistCompletedItems ??
        (summaryEntries?.length ?? summary?.entries.length ?? 0);
    fallback['received_count'] = received;
    return fallback.isEmpty ? null : fallback;
  }

  List<Map<String, dynamic>>? _summaryEntriesToMetadata(
    DownloadPlaylistSummary? summary,
  ) {
    if (summary == null || summary.entries.isEmpty) {
      return null;
    }
    final converted = summary.entries
        .map(_playlistEntryToMetadata)
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    return converted.isEmpty ? null : converted;
  }

  Map<String, dynamic> _playlistEntryToMetadata(DownloadPlaylistEntry entry) {
    final preview = entry.preview;
    final payload = <String, dynamic>{
      if (entry.index != null) 'index': entry.index,
      if (entry.id != null) 'id': entry.id,
      if (preview?.title != null) 'title': preview!.title,
      if (preview?.uploader != null) 'uploader': preview!.uploader,
      if (preview?.channel != null) 'channel': preview!.channel,
      if (preview?.webpageUrl != null) 'webpage_url': preview!.webpageUrl,
      if (preview?.durationSeconds != null)
        'duration_seconds': preview!.durationSeconds,
      if (preview?.durationText != null) 'duration_text': preview!.durationText,
      if (preview?.thumbnailUrl != null) 'thumbnail_url': preview!.thumbnailUrl,
      'is_live': false,
      if (entry.isCompleted) 'is_completed': true,
      if (entry.isCurrent) 'is_current': true,
    };
    return payload;
  }

  Map<String, dynamic>? _buildFallbackPlaylist(
    DownloadJobModel job,
    PlaylistPreviewData previewData,
  ) {
    final preview = previewData.preview;
    final estimatedTotal =
        job.progress?.playlistTotalItems ??
        job.progress?.playlistCount ??
        job.playlist?.totalItems ??
        job.playlist?.entryCount;
    final payload = <String, dynamic>{
      'title': preview.title,
      'uploader': preview.uploader,
      'channel': preview.channel,
      'thumbnail_url': preview.thumbnailUrl,
      'description': preview.description,
      'description_short': preview.shortDescription(),
      'webpage_url': preview.webpageUrl ?? preview.originalUrl,
      'is_collecting_entries': true,
      'entries': const <Map<String, dynamic>>[],
      'received_count': 0,
      if (estimatedTotal != null && estimatedTotal > 0)
        'entry_count': estimatedTotal,
      if (estimatedTotal != null && estimatedTotal > 0)
        'total_items': estimatedTotal,
    };
    payload.removeWhere((key, value) => value == null);
    if (!payload.containsKey('entry_count')) {
      payload['entry_count'] = 0;
      payload['total_items'] = 0;
    }
    return payload;
  }

  PlaylistPreviewData? _buildPlaceholderPreviewData(DownloadJobModel job) {
    final preview = job.preview;
    final playlist = job.playlist;
    final metadataTitle = _coerceMetadataString(job.metadata['title']);
    final firstUrl = job.urls.isNotEmpty ? job.urls.first : null;
    final fallbackTitle = _firstNonEmpty([
      preview?.title,
      playlist?.title,
      metadataTitle,
      firstUrl,
      job.id,
    ]);
    if (fallbackTitle == null || fallbackTitle.isEmpty) {
      return null;
    }
    final previewPayload = <String, dynamic>{
      'title': fallbackTitle,
      if (preview?.description != null)
        'description': preview!.description
      else if (playlist?.description != null)
        'description': playlist!.description,
      if (preview?.thumbnailUrl != null)
        'thumbnail_url': preview!.thumbnailUrl
      else if (preview?.bestThumbnailUrl != null)
        'thumbnail_url': preview!.bestThumbnailUrl
      else if (playlist?.thumbnailUrl != null)
        'thumbnail_url': playlist!.thumbnailUrl,
      if (preview?.uploader != null)
        'uploader': preview!.uploader
      else if (playlist?.uploader != null)
        'uploader': playlist!.uploader,
      if (preview?.channel != null)
        'channel': preview!.channel
      else if (playlist?.channel != null)
        'channel': playlist!.channel,
      if (preview?.webpageUrl != null)
        'webpage_url': preview!.webpageUrl
      else if (preview?.originalUrl != null)
        'webpage_url': preview!.originalUrl
      else if (playlist?.webpageUrl != null)
        'webpage_url': playlist!.webpageUrl
      else if (firstUrl != null)
        'webpage_url': firstUrl,
      if (preview?.shortDescription() != null)
        'description_short': preview!.shortDescription()
      else if (playlist?.descriptionShort != null)
        'description_short': playlist!.descriptionShort,
    };
    previewPayload.removeWhere((key, value) => value == null);
    return PlaylistPreviewData.fromJson(previewPayload);
  }

  PlaylistPreviewData? _buildEmergencyPreviewData(
    DownloadJobModel job,
    VidraLocalizations localizations,
  ) {
    final fallbackTitle = _firstNonEmpty([
      job.preview?.title,
      job.playlist?.title,
      job.urls.isNotEmpty ? job.urls.first : null,
      job.id,
    ]);
    if (fallbackTitle == null || fallbackTitle.isEmpty) {
      return null;
    }
    final estimatedTotal =
        job.progress?.playlistTotalItems ??
        job.progress?.playlistCount ??
        job.playlist?.totalItems ??
        job.playlist?.entryCount;
    final received = job.progress?.playlistCompletedItems ?? 0;
    final previewPayload = <String, dynamic>{
      'title': fallbackTitle,
      'description':
          job.preview?.description ??
          localizations.ui(AppStringKey.homePlaylistCollectingDescription),
      'playlist': <String, dynamic>{
        'title': fallbackTitle,
        'entries': const <Map<String, dynamic>>[],
        'is_collecting_entries': true,
        'received_count': math.max(received, 0),
        if (estimatedTotal != null && estimatedTotal > 0)
          'entry_count': estimatedTotal,
        if (estimatedTotal != null && estimatedTotal > 0)
          'total_items': estimatedTotal,
      },
    };
    return PlaylistPreviewData.fromJson(previewPayload);
  }

  _PlaylistEntrySnapshot _resolvePlaylistEntrySnapshot(
    DownloadJobModel job,
    PlaylistPreviewData previewData,
  ) {
    final playlist = previewData.playlist;
    final jobPlaylist = job.playlist;
    final progress = job.progress;
    final playlistIndex = progress?.playlistCurrentIndex;
    final candidates = <int?>[
      playlist?.receivedCount,
      playlist?.entries.length,
      jobPlaylist?.completedItems,
      jobPlaylist?.entries.length,
      progress?.playlistCompletedItems,
      playlistIndex != null ? playlistIndex + 1 : null,
    ];
    var received = 0;
    for (final candidate in candidates) {
      if (candidate == null) {
        continue;
      }
      if (candidate < 0) {
        continue;
      }
      received = candidate;
      break;
    }
    return _PlaylistEntrySnapshot(received: received);
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      if (value == null) {
        continue;
      }
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  String? _coerceMetadataString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final preferencesModel = context.watch<PreferencesModel>();
    final downloadController = context.read<DownloadController>();
    final backendState = context.select<DownloadController, BackendState>(
      (controller) => controller.backendState,
    );
    final initialPermissionsController = context
        .watch<InitialPermissionsController>();
    final showInitialPermissionsSheet =
        initialPermissionsController.shouldPrompt;
    final pendingPermissionsCount = initialPermissionsController.permissions
        .where((state) => state.needsAttention)
        .length;
    final backendReady = backendState == BackendState.running;
    final jobs = context.select<DownloadController, List<DownloadJobModel>>(
      (controller) => controller.jobs,
    );
    final isSubmitting = context.select<DownloadController, bool>(
      (controller) => controller.isSubmitting,
    );
    final lastError = context.select<DownloadController, String?>(
      (controller) => controller.lastError,
    );
    final preferences = preferencesModel.preferences;
    final languageValue = preferencesModel.effectiveLanguage;
    final localizations = VidraLocalizations.of(context);
    final isExtractAudio = preferences.extractAudio.getValue<bool>();
    final isDarkTheme = preferences.isDarkTheme.getValue<bool>();
    final isPlaylistMode = preferences.playlist.getValue<bool>();
    final inProgressJobs = <DownloadJobModel>[];
    final completedJobs = <DownloadJobModel>[];
    final errorJobs = <DownloadJobModel>[];
    for (final job in jobs) {
      if (_isInProgress(job)) {
        inProgressJobs.add(job);
        continue;
      }
      if (job.status == DownloadStatus.completed) {
        completedJobs.add(job);
        continue;
      }
      if (job.status == DownloadStatus.failed) {
        errorJobs.add(job);
      }
    }
    final inProgressJobsView = List<DownloadJobModel>.unmodifiable(
      inProgressJobs,
    );
    final completedJobsView = List<DownloadJobModel>.unmodifiable(
      completedJobs,
    );
    final errorJobsView = List<DownloadJobModel>.unmodifiable(errorJobs);
    final theme = Theme.of(context);

    final tabDescriptors = [
      _HomeTabDescriptor(
        label: localizations.ui(AppStringKey.homeTabAll),
        icon: Icons.dashboard_outlined,
        count: jobs.length,
      ),
      _HomeTabDescriptor(
        label: localizations.ui(AppStringKey.homeTabInProgress),
        icon: Icons.downloading_outlined,
        count: inProgressJobsView.length,
      ),
      _HomeTabDescriptor(
        label: localizations.ui(AppStringKey.homeTabCompleted),
        icon: Icons.check_circle_outline,
        count: completedJobsView.length,
      ),
      _HomeTabDescriptor(
        label: localizations.ui(AppStringKey.homeTabError),
        icon: Icons.error_outline,
        count: errorJobsView.length,
      ),
    ];

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(localizations.ui(AppStringKey.homeTitle)),
        actions: [
          if (pendingPermissionsCount > 0)
            _PermissionsAppBarButton(
              pendingCount: pendingPermissionsCount,
              tooltip: localizations.ui(AppStringKey.initialPermissionsTitle),
              onPressed: _openPermissionsSheet,
            ),
          BackendStatusIndicator(onTap: _openBackendStatus),
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: localizations.ui(AppStringKey.homeThumbnailCacheTooltip),
            onPressed: _clearThumbnailCache,
          ),
          IconButton(
            tooltip: localizations.ui(AppStringKey.homeThemeToggleTooltip),
            icon: Icon(isDarkTheme ? Icons.dark_mode : Icons.light_mode),
            onPressed: () async {
              await preferencesModel.setPreferenceValue(
                preferences.isDarkTheme,
                !isDarkTheme,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: localizations.ui(AppStringKey.homeSettingsTooltip),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: DropRegion(
        formats: _urlDropFormats,
        onDropEnter: _handleUrlDropEnter,
        onDropLeave: (_) => _setUrlDropHovered(false),
        onDropOver: _handleUrlDropOver,
        onPerformDrop: _handleUrlDropPerform,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 5, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.symmetric(
                        horizontal: _isUrlDropHovered ? 8 : 0,
                        vertical: _isUrlDropHovered ? 6 : 0,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isUrlDropHovered
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                        ),
                        color: _isUrlDropHovered
                            ? theme.colorScheme.primary.withValues(alpha: 0.05)
                            : Colors.transparent,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Shortcuts(
                              shortcuts: _urlFieldPasteShortcuts,
                              child: TextField(
                                key: const ValueKey('home_url_input'),
                                controller: _urlController,
                                focusNode: _urlFocusNode,
                                decoration: InputDecoration(
                                  labelText: localizations.ui(
                                    AppStringKey.enterUrl,
                                  ),
                                  border: const OutlineInputBorder(),
                                  prefixIconConstraints: const BoxConstraints(
                                    minHeight: 30,
                                    maxHeight: 30,
                                    minWidth: 40,
                                  ),
                                  prefixIcon: Tooltip(
                                    message: localizations.ui(
                                      AppStringKey.homePasteButtonTooltip,
                                    ),
                                    waitDuration: const Duration(
                                      milliseconds: 250,
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.paste_rounded),
                                      onPressed: _pasteFromClipboard,
                                      style: IconButton.styleFrom(
                                        padding: const EdgeInsets.only(left: 5),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ),
                                  suffixIconConstraints: const BoxConstraints(
                                    minHeight: 30,
                                    maxHeight: 30,
                                  ),
                                  suffixIcon: Tooltip(
                                    message:
                                        preferences.playlist.get(
                                              'name',
                                              languageValue,
                                            )
                                            as String,
                                    waitDuration: const Duration(
                                      milliseconds: 250,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: IconButton(
                                        key: const ValueKey(
                                          'home_playlist_mode_toggle',
                                        ),
                                        isSelected: isPlaylistMode,
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () async {
                                          await preferencesModel
                                              .setPreferenceValue(
                                                preferences.playlist,
                                                !isPlaylistMode,
                                              );
                                        },
                                        icon: const Icon(
                                          Icons.play_circle_outline,
                                          size: 22,
                                        ),
                                        selectedIcon: const Icon(
                                          Icons.queue_music,
                                          size: 22,
                                        ),
                                        style: IconButton.styleFrom(
                                          padding: const EdgeInsets.all(0),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          backgroundColor: isPlaylistMode
                                              ? theme
                                                    .colorScheme
                                                    .primaryContainer
                                              : theme
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                          foregroundColor: isPlaylistMode
                                              ? theme
                                                    .colorScheme
                                                    .onPrimaryContainer
                                              : theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                          hoverColor: theme
                                              .colorScheme
                                              .primaryContainer
                                              .withValues(alpha: 0.2),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.go,
                                onSubmitted: backendReady
                                    ? (_) => _handleDownload(context)
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _urlController,
                            builder: (context, value, _) {
                              final hasText = value.text.trim().isNotEmpty;
                              return SizedBox(
                                height: 48,
                                width: 48,
                                child: ElevatedButton(
                                  onPressed:
                                      !backendReady || isSubmitting || !hasText
                                      ? null
                                      : () => _handleDownload(context),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(48, 48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 2,
                                  ),
                                  child: isSubmitting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.download),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final controlsGroup = _buildPreferenceControls(
                          preferences,
                          languageValue,
                          isExtractAudio: isExtractAudio,
                        );
                        final primaryControl = controlsGroup.buildPrimary(
                          context,
                        );
                        final collapseAdvanced =
                            constraints.maxWidth <
                                _advancedControlsBreakpoint &&
                            controlsGroup.hasAdvanced;
                        final shouldShowMagicFab = collapseAdvanced;
                        if (_showMagicFab != shouldShowMagicFab) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                _showMagicFab = shouldShowMagicFab;
                              });
                            }
                          });
                        }

                        final extractSwitch = Tooltip(
                          message:
                              preferences.extractAudio.get(
                                    'name',
                                    languageValue,
                                  )
                                  as String,
                          waitDuration: const Duration(milliseconds: 250),
                          child: Switch(
                            key: const ValueKey('home_extract_audio_switch'),
                            value: isExtractAudio,
                            onChanged: (value) async {
                              await preferencesModel.setPreferenceValue(
                                preferences.extractAudio,
                                value,
                              );
                            },
                            thumbIcon: WidgetStateProperty<Icon>.fromMap({
                              WidgetState.selected: Icon(
                                Icons.audiotrack,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              WidgetState.any: Icon(
                                Icons.videocam,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            }),
                            thumbColor: WidgetStateProperty.all<Color>(
                              Theme.of(context).colorScheme.onPrimary,
                            ),
                            trackColor: WidgetStateProperty.all<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                            trackOutlineColor: WidgetStateProperty.all<Color>(
                              Colors.transparent,
                            ),
                          ),
                        );

                        final children = <Widget>[
                          extractSwitch,
                          primaryControl,
                        ];
                        final hasAdvanced = controlsGroup.hasAdvanced;

                        if (!collapseAdvanced && hasAdvanced) {
                          children.addAll(controlsGroup.buildAdvanced(context));
                        }

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.start,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: children,
                        );
                      },
                    ),
                    SizedBox(height: 5),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final useIconTabs = constraints.maxWidth < 800;
                        return TabBar(
                          controller: _tabController,
                          splashBorderRadius: BorderRadius.circular(10),
                          tabs: [
                            for (final descriptor in tabDescriptors)
                              _buildTab(descriptor, theme, useIconTabs),
                          ],
                        );
                      },
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildJobsTab(
                            context,
                            downloadController,
                            jobs,
                            emptyMessage: localizations.ui(
                              AppStringKey.homeEmptyAll,
                            ),
                            tabIndex: 0,
                            backendState: backendState,
                          ),
                          _buildJobsTab(
                            context,
                            downloadController,
                            inProgressJobsView,
                            emptyMessage: localizations.ui(
                              AppStringKey.homeEmptyInProgress,
                            ),
                            tabIndex: 1,
                            backendState: backendState,
                          ),
                          _buildJobsTab(
                            context,
                            downloadController,
                            completedJobsView,
                            emptyMessage: localizations.ui(
                              AppStringKey.homeEmptyCompleted,
                            ),
                            tabIndex: 2,
                            backendState: backendState,
                          ),
                          _buildJobsTab(
                            context,
                            downloadController,
                            errorJobsView,
                            emptyMessage: localizations.ui(
                              AppStringKey.homeEmptyError,
                            ),
                            tabIndex: 3,
                            backendState: backendState,
                          ),
                        ],
                      ),
                    ),
                    if (lastError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          lastError,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_isUrlDropHovered)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.9),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.shadow.withValues(
                                alpha: 0.2,
                              ),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.download_for_offline,
                              size: 48,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              localizations.ui(
                                AppStringKey.homeDropOverlayHint,
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_showMagicFab) ...[
            Tooltip(
              message: localizations.ui(AppStringKey.homeFormatFabTooltip),
              child: FloatingActionButton.small(
                key: const ValueKey('home_magic_fab'),
                heroTag: const ValueKey('home_magic_fab_hero'),
                onPressed: () => _magicBottomSheet(context),
                child: const Icon(Icons.auto_fix_high),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Tooltip(
            message: localizations.ui(AppStringKey.homeFolderFabTooltip),
            child: FloatingActionButton.small(
              key: const ValueKey('home_folder_fab'),
              heroTag: const ValueKey('home_folder_fab_hero'),
              onPressed: () => _folderBottomSheet(context),
              child: const Icon(Icons.folder),
            ),
          ),
        ],
      ),
    );

    if (!showInitialPermissionsSheet) {
      return scaffold;
    }

    return Stack(
      children: [
        scaffold,
        const Positioned.fill(child: InitialPermissionsSheet()),
      ],
    );
  }

  void _openBackendStatus() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BackendStatusScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openPermissionsSheet() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => InitialPermissionsSheet(
          onCloseRequested: () => Navigator.of(routeContext).maybePop(),
        ),
        fullscreenDialog: true,
      ),
    );
  }

  void _magicBottomSheet(BuildContext context) {
    MagicOptionsSheet.show(context);
  }

  void _setUrlDropHovered(bool hovered) {
    if (_isUrlDropHovered == hovered) {
      return;
    }
    setState(() {
      _isUrlDropHovered = hovered;
    });
  }

  void _handleUrlDropEnter(DropEvent event) {
    if (_dropSessionHasSupportedData(event.session)) {
      _setUrlDropHovered(true);
    }
  }

  DropOperation _handleUrlDropOver(DropOverEvent event) {
    final hasSupportedData = _dropSessionHasSupportedData(event.session);
    final canCopy = event.session.allowedOperations.contains(
      DropOperation.copy,
    );
    if (hasSupportedData && canCopy) {
      _setUrlDropHovered(true);
      return DropOperation.copy;
    }
    _setUrlDropHovered(false);
    return DropOperation.none;
  }

  Future<void> _handleUrlDropPerform(PerformDropEvent event) async {
    _setUrlDropHovered(false);
    var handled = false;
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null) {
        continue;
      }
      _requestUrlFromReader(reader, (value) {
        if (handled) {
          return;
        }
        handled = _applyDroppedUrl(value);
      });
    }
  }

  void _requestUrlFromReader(
    DataReader reader,
    void Function(String value) onValue,
  ) {
    if (reader.canProvide(Formats.uri)) {
      reader.getValue<NamedUri>(Formats.uri, (namedUri) {
        final uri = namedUri?.uri;
        if (uri != null) {
          onValue(uri.toString());
        }
      });
    }
    if (reader.canProvide(Formats.plainText)) {
      reader.getValue<String>(Formats.plainText, (value) {
        if (value != null) {
          onValue(value);
        }
      });
    }
    if (reader.canProvide(Formats.htmlText)) {
      reader.getValue<String>(Formats.htmlText, (value) {
        final extracted = _extractUrlFromHtml(value);
        if (extracted != null) {
          onValue(extracted);
        }
      });
    }
  }

  String? _extractUrlFromHtml(String? html) {
    if (html == null || html.isEmpty) {
      return null;
    }
    final linkMatch = RegExp(
      r'''href=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (linkMatch != null) {
      return linkMatch.group(1);
    }
    final fallbackMatch = RegExp(
      r'''(https?:\/\/[^\s"'<]+)''',
      caseSensitive: false,
    ).firstMatch(html);
    return fallbackMatch?.group(1);
  }

  bool _dropSessionHasSupportedData(DropSession session) {
    for (final item in session.items) {
      if (_dropItemHasSupportedData(item)) {
        return true;
      }
    }
    return false;
  }

  bool _dropItemHasSupportedData(DropItem item) {
    return item.canProvide(Formats.uri) ||
        item.canProvide(Formats.plainText) ||
        item.canProvide(Formats.htmlText);
  }

  bool _applyDroppedUrl(String? rawValue) {
    final trimmed = rawValue?.trim();
    if (trimmed == null || trimmed.isEmpty || !_looksLikeUrl(trimmed)) {
      return false;
    }
    _urlController.text = trimmed;
    if (mounted) {
      unawaited(_handleDownload(context));
    }
    return true;
  }

  bool _looksLikeUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return true;
    }
    final fallback = Uri.tryParse('https://$value');
    return fallback != null && fallback.host.isNotEmpty;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final value = data?.text;
    if (value == null) {
      return;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _urlController
      ..text = trimmed
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: trimmed.length),
      );
  }

  Future<void> _handleManualSharePayload(ShareIntentPayload payload) async {
    if (!mounted) {
      return;
    }
    final urlsValue = payload.joinedUrls('\n');
    _urlController
      ..text = urlsValue
      ..selection = TextSelection.collapsed(offset: urlsValue.length);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) {
      return;
    }
    if (!_urlFocusNode.hasFocus) {
      _urlFocusNode.requestFocus();
    }
    _magicBottomSheet(context);
  }

  void _folderBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // permite que se adapte al contenido
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final preferencesModel = context.watch<PreferencesModel>();
        final preferences = preferencesModel.preferences;
        final languageValue = preferencesModel.effectiveLanguage;
        final localizations = VidraLocalizations.of(context);
        const PreferenceControlBuilder controlBuilder =
            PreferenceControlBuilder();
        final controlPaths = controlBuilder.build(
          context: context,
          preference: preferences.paths,
          languageOverride: languageValue,
        );
        final controlOutput = controlBuilder.build(
          context: context,
          preference: preferences.output,
          languageOverride: languageValue,
        );
        return SafeArea(
          child: _FolderOptionsSheet(
            localizations: localizations,
            preferences: preferences,
            languageValue: languageValue,
            controlPaths: controlPaths,
            controlOutput: controlOutput,
          ),
        );
      },
    );
  }

  Tab _buildTab(
    _HomeTabDescriptor descriptor,
    ThemeData theme,
    bool useIconTabs,
  ) {
    Widget buildBadge({required bool dense}) {
      final horizontal = dense ? 5.0 : 6.0;
      final vertical = dense ? 1.5 : 2.0;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          descriptor.count.toString(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: dense ? 10 : null,
          ),
        ),
      );
    }

    if (useIconTabs) {
      return Tab(
        child: Tooltip(
          message: descriptor.label,
          child: SizedBox(
            width: 48,
            height: 40,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Icon(descriptor.icon),
                  ),
                  Positioned(
                    top: -8,
                    right: -12,
                    child: buildBadge(dense: true),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(descriptor.icon, size: 18),
          const SizedBox(width: 6),
          Text(descriptor.label),
          const SizedBox(width: 6),
          buildBadge(dense: false),
        ],
      ),
    );
  }

  Widget _buildJobsTab(
    BuildContext context,
    DownloadController downloadController,
    List<DownloadJobModel> jobs, {
    required String emptyMessage,
    required int tabIndex,
    required BackendState backendState,
  }) {
    final localizations = VidraLocalizations.of(context);
    final theme = Theme.of(context);
    final totalPages = (jobs.length / _pageSize).ceil();
    final rawIndex = _pageIndices[tabIndex];
    final pageIndex = totalPages == 0 ? 0 : rawIndex.clamp(0, totalPages - 1);
    if (pageIndex != rawIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _pageIndices[tabIndex] = pageIndex;
        });
      });
    }

    final hasJobs = jobs.isNotEmpty;
    final start = hasJobs ? pageIndex * _pageSize : 0;
    final visibleJobs = hasJobs
        ? jobs.skip(start).take(_pageSize).toList(growable: false)
        : const <DownloadJobModel>[];
    final end = hasJobs ? math.min(start + visibleJobs.length, jobs.length) : 0;
    final rangeLabel = hasJobs
        ? _formatTemplate(
            localizations.ui(AppStringKey.homePaginationRangeLabel),
            {'start': '${start + 1}', 'end': '$end', 'total': '${jobs.length}'},
          )
        : localizations.ui(AppStringKey.homePaginationNoItems);

    final backendReady = backendState == BackendState.running;
    final backendLoadingHeader = backendReady
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator.adaptive(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    backendStatusText(localizations, backendState),
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );

    Widget buildList() {
      if (!hasJobs) {
        if (!backendReady) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [backendLoadingHeader],
          );
        }
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 96),
            Center(child: Text(emptyMessage)),
          ],
        );
      }
      final includeHeader = !backendReady;
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visibleJobs.length + (includeHeader ? 1 : 0),
        itemBuilder: (context, index) {
          if (includeHeader && index == 0) {
            return backendLoadingHeader;
          }
          final job = visibleJobs[index - (includeHeader ? 1 : 0)];
          final Route<void> Function(String) routeBuilder = job.isPlaylist
              ? PlaylistDetailScreen.route
              : JobDetailScreen.route;
          return DownloadJobCard(
            job: job,
            onTap: () => Navigator.of(context).push(routeBuilder(job.id)),
            onShowDetails: () =>
                Navigator.of(context).push(JobDetailScreen.route(job.id)),
            onPlaylistSelectionRequested: _handleManualPlaylistSelectionRequest,
            enableOpenDestinationAction:
                job.kind != DownloadKind.playlist && !job.isPlaylist,
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPaginationToolbar(context, localizations, rangeLabel),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => downloadController.refreshJobs(),
            child: buildList(),
          ),
        ),
        _buildPaginationControls(
          context,
          localizations,
          tabIndex,
          totalPages,
          pageIndex,
        ),
      ],
    );
  }

  Widget _buildPaginationToolbar(
    BuildContext context,
    VidraLocalizations localizations,
    String rangeLabel,
  ) {
    final theme = Theme.of(context);
    final selector = Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          localizations.ui(AppStringKey.homePaginationShow),
          style: theme.textTheme.bodySmall,
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _pageSize,
            isDense: true,
            style: theme.textTheme.bodySmall,
            items: _pageSizeOptions
                .map(
                  (size) => DropdownMenuItem<int>(
                    value: size,
                    child: Text(size.toString()),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null && value != _pageSize) {
                _changePageSize(value);
              }
            },
          ),
        ),
        Text(
          localizations.ui(AppStringKey.homePaginationPerPage),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            selector,
            Text(rangeLabel, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationControls(
    BuildContext context,
    VidraLocalizations localizations,
    int tabIndex,
    int totalPages,
    int pageIndex,
  ) {
    if (totalPages <= 1) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    Widget buildButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 32),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          buildButton(
            icon: Icons.first_page,
            tooltip: localizations.ui(AppStringKey.homePaginationFirst),
            onPressed: pageIndex > 0 ? () => _goToPage(tabIndex, 0) : null,
          ),
          buildButton(
            icon: Icons.chevron_left,
            tooltip: localizations.ui(AppStringKey.homePaginationPrevious),
            onPressed: pageIndex > 0
                ? () => _goToPage(tabIndex, pageIndex - 1)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _formatTemplate(
                localizations.ui(AppStringKey.homePaginationPageStatus),
                {'current': '${pageIndex + 1}', 'total': '$totalPages'},
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
          buildButton(
            icon: Icons.chevron_right,
            tooltip: localizations.ui(AppStringKey.homePaginationNext),
            onPressed: pageIndex < totalPages - 1
                ? () => _goToPage(tabIndex, pageIndex + 1)
                : null,
          ),
          buildButton(
            icon: Icons.last_page,
            tooltip: localizations.ui(AppStringKey.homePaginationLast),
            onPressed: pageIndex < totalPages - 1
                ? () => _goToPage(tabIndex, totalPages - 1)
                : null,
          ),
        ],
      ),
    );
  }

  String _formatTemplate(String template, Map<String, String> values) {
    return values.entries.fold<String>(
      template,
      (result, entry) => result.replaceAll('{${entry.key}}', entry.value),
    );
  }

  void _changePageSize(int newSize) {
    setState(() {
      _pageSize = newSize;
      _resetPageIndices();
    });
  }

  void _goToPage(int tabIndex, int newPage) {
    setState(() {
      _pageIndices[tabIndex] = newPage;
    });
  }

  void _resetPageIndices() {
    for (var i = 0; i < _pageIndices.length; i++) {
      _pageIndices[i] = 0;
    }
  }

  bool _isInProgress(DownloadJobModel job) {
    return _inProgressStatuses.contains(job.status);
  }

  static const Set<DownloadStatus> _inProgressStatuses = {
    DownloadStatus.queued,
    DownloadStatus.running,
    DownloadStatus.starting,
    DownloadStatus.retrying,
    DownloadStatus.pausing,
    DownloadStatus.paused,
    DownloadStatus.cancelling,
  };

  _PreferenceControlsGroup _buildPreferenceControls(
    Preferences preferences,
    String languageValue, {
    required bool isExtractAudio,
  }) {
    if (isExtractAudio) {
      return _PreferenceControlsGroup(
        primaryBuilder: (_) => PreferenceDropdownControl(
          preference: preferences.audioFormat,
          leadingIcon: const Icon(Icons.audiotrack_outlined),
          label: Text(
            preferences.audioFormat.get('name', languageValue) as String,
          ),
          isCompact: true,
          minCompactWidth: _compactControlMinWidth,
        ),
        advancedBuilders: const <WidgetBuilder>[],
      );
    }

    return _PreferenceControlsGroup(
      primaryBuilder: (_) => PreferenceDropdownControl(
        preference: preferences.videoResolution,
        leadingIcon: const Icon(Icons.video_settings_rounded),
        label: Text(
          preferences.videoResolution.get('name', languageValue) as String,
        ),
        isCompact: true,
        minCompactWidth: _compactControlMinWidth,
      ),
      advancedBuilders: <WidgetBuilder>[
        (_) => PreferenceDropdownControl(
          preference: preferences.mergeOutputFormat,
          leadingIcon: const Icon(Icons.videocam_outlined),
          label: Text(
            preferences.mergeOutputFormat.get('name', languageValue) as String,
          ),
          isCompact: true,
          minCompactWidth: _compactControlMinWidth,
        ),
        (_) => PreferenceDropdownControl(
          preference: preferences.audioLanguage,
          leadingIcon: const Icon(Icons.language_outlined),
          label: Text(
            preferences.audioLanguage.get('name', languageValue) as String,
          ),
          writeable: true,
          isCompact: true,
          minCompactWidth: _compactControlMinWidth,
        ),
        (_) => PreferenceDropdownControl(
          preference: preferences.videoSubtitles,
          leadingIcon: const Icon(Icons.subtitles_outlined),
          label: Text(
            preferences.videoSubtitles.get('name', languageValue) as String,
          ),
          writeable: true,
          isCompact: true,
          minCompactWidth: _compactControlMinWidth,
        ),
      ],
    );
  }

  String _backendActionDisabledMessage(
    VidraLocalizations localizations,
    BackendState state,
  ) {
    switch (state) {
      case BackendState.unpacking:
        return localizations.ui(
          AppStringKey.homeBackendActionDisabledUnpacking,
        );
      case BackendState.starting:
        return localizations.ui(AppStringKey.homeBackendActionDisabledStarting);
      case BackendState.unknown:
        return localizations.ui(AppStringKey.homeBackendActionDisabledUnknown);
      case BackendState.stopped:
        return localizations.ui(AppStringKey.homeBackendActionDisabledStopped);
      case BackendState.running:
        return '';
    }
  }

  Future<void> _handleDownload(BuildContext context) async {
    final downloadController = context.read<DownloadController>();
    final backendState = downloadController.backendState;
    final localizations = VidraLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (backendState != BackendState.running) {
      final message = _backendActionDisabledMessage(
        localizations,
        backendState,
      );
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final preferencesModel = context.read<PreferencesModel>();
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

    if (!hadValidPathsHome && ensuredHomePath != null && messenger != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              localizations
                  .ui(AppStringKey.homePathsEnsureDownloads)
                  .replaceAll('{path}', ensuredHomePath),
            ),
          ),
        );
    }

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

    final success = await downloadController.startDownload(
      _urlController.text,
      options,
    );
    if (!context.mounted) {
      return;
    }
    if (success) {
      _urlController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.ui(AppStringKey.homeDownloadStarted)),
        ),
      );
    } else {
      final error =
          downloadController.lastError ??
          localizations.ui(AppStringKey.homeDownloadFailed);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  bool _hasValidPathsHome(Object? pathsValue) {
    if (pathsValue is Map) {
      final homeValue = pathsValue['home'];
      return homeValue is String && homeValue.trim().isNotEmpty;
    }
    return false;
  }
}

class _PermissionsAppBarButton extends StatelessWidget {
  const _PermissionsAppBarButton({
    required this.pendingCount,
    required this.tooltip,
    required this.onPressed,
  });

  final int pendingCount;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeLabel = pendingCount > 9 ? '9+' : '$pendingCount';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.verified_user_outlined),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
        Positioned(
          right: 6,
          top: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onError,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FolderOptionsSheet extends StatefulWidget {
  const _FolderOptionsSheet({
    required this.localizations,
    required this.preferences,
    required this.languageValue,
    required this.controlPaths,
    required this.controlOutput,
  });

  final VidraLocalizations localizations;
  final Preferences preferences;
  final String languageValue;
  final PreferenceControl controlPaths;
  final PreferenceControl controlOutput;

  @override
  State<_FolderOptionsSheet> createState() => _FolderOptionsSheetState();
}

class _FolderOptionsSheetState extends State<_FolderOptionsSheet> {
  static const double _extraBottomSpace = 110.0;
  static const double _initialContentEstimate = 360.0;

  final GlobalKey _contentKey = GlobalKey();
  double? _contentHeight;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final measuredContentHeight = _contentHeight ?? _initialContentEstimate;
        final desiredHeight = math.min(
          maxHeight,
          measuredContentHeight + _extraBottomSpace,
        );

        final measuredSection = KeyedSubtree(
          key: _contentKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const Divider(height: 1),
              const SizedBox(height: 8),
              PreferenceTile(
                preference: widget.preferences.paths,
                languageValue: widget.languageValue,
                control: widget.controlPaths,
              ),
              const SizedBox(height: 8),
              PreferenceTile(
                preference: widget.preferences.output,
                languageValue: widget.languageValue,
                control: widget.controlOutput,
              ),
            ],
          ),
        );

        final sheetBody = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            measuredSection,
            const SizedBox(height: _extraBottomSpace),
          ],
        );

        final scrollable = SingleChildScrollView(
          key: const ValueKey('home_folder_bottom_sheet'),
          padding: EdgeInsets.only(bottom: viewInsets),
          physics: const ClampingScrollPhysics(),
          child: sheetBody,
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateMeasuredHeight();
        });

        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: SizedBox(height: desiredHeight, child: scrollable),
        );
      },
    );
  }

  void _updateMeasuredHeight() {
    if (!mounted) {
      return;
    }
    final context = _contentKey.currentContext;
    if (context == null) {
      return;
    }
    final size = context.size;
    if (size == null) {
      return;
    }
    final nextHeight = size.height;
    if (nextHeight <= 0) {
      return;
    }
    if (_contentHeight != null && (nextHeight - _contentHeight!).abs() < 0.5) {
      return;
    }
    setState(() {
      _contentHeight = nextHeight;
    });
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.localizations.ui(AppStringKey.homeFolderOptionsTitle),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: widget.localizations.ui(AppStringKey.homeCloseAction),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _HomeTabDescriptor {
  const _HomeTabDescriptor({
    required this.label,
    required this.icon,
    required this.count,
  });

  final String label;
  final IconData icon;
  final int count;
}

class _PreferenceControlsGroup {
  const _PreferenceControlsGroup({
    required this.primaryBuilder,
    required this.advancedBuilders,
  });

  final WidgetBuilder primaryBuilder;
  final List<WidgetBuilder> advancedBuilders;

  bool get hasAdvanced => advancedBuilders.isNotEmpty;

  Widget buildPrimary(BuildContext context) => primaryBuilder(context);

  List<Widget> buildAdvanced(BuildContext context) {
    if (advancedBuilders.isEmpty) {
      return const <Widget>[];
    }
    return advancedBuilders
        .map((builder) => builder(context))
        .toList(growable: false);
  }
}

class _PlaylistEntrySnapshot {
  const _PlaylistEntrySnapshot({required this.received});

  final int received;
}
