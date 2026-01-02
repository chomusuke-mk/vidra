import 'package:vidra/constants/backend_constants.dart';

/// Represents the lifecycle state of a download job exposed by the backend.
enum DownloadStatus {
  queued,
  running,
  starting,
  retrying,
  pausing,
  paused,
  cancelling,
  completed,
  completedWithErrors,
  failed,
  cancelled,
  unknown,
}

DownloadStatus downloadStatusFromString(String? raw) {
  if (raw == null) {
    return DownloadStatus.unknown;
  }
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) {
    return DownloadStatus.unknown;
  }
  return _statusLookup[normalized] ?? DownloadStatus.unknown;
}

const Map<String, DownloadStatus> _statusLookup = <String, DownloadStatus>{
  BackendJobStatus.queued: DownloadStatus.queued,
  BackendJobStatus.running: DownloadStatus.running,
  BackendJobStatus.starting: DownloadStatus.starting,
  BackendJobStatus.retrying: DownloadStatus.retrying,
  BackendJobStatus.pausing: DownloadStatus.pausing,
  BackendJobStatus.paused: DownloadStatus.paused,
  BackendJobStatus.cancelling: DownloadStatus.cancelling,
  BackendJobStatus.completed: DownloadStatus.completed,
  BackendJobStatus.completedWithErrors: DownloadStatus.completedWithErrors,
  BackendJobStatus.failed: DownloadStatus.failed,
  BackendJobStatus.cancelled: DownloadStatus.cancelled,
  BackendJobStatus.deleted: DownloadStatus.unknown,
};

/// Represents the normalized content kind identified by the backend.
enum DownloadKind { unknown, video, playlist }

DownloadKind downloadKindFromString(String? raw) {
  if (raw == null) {
    return DownloadKind.unknown;
  }
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) {
    return DownloadKind.unknown;
  }
  return _kindLookup[normalized] ?? DownloadKind.unknown;
}

const Map<String, DownloadKind> _kindLookup = <String, DownloadKind>{
  BackendJobKind.unknown: DownloadKind.unknown,
  BackendJobKind.video: DownloadKind.video,
  BackendJobKind.playlist: DownloadKind.playlist,
};

class DownloadProgress {
  const DownloadProgress({
    this.status,
    this.stage,
    this.stageName,
    this.downloadedBytes,
    this.totalBytes,
    this.speed,
    this.eta,
    this.elapsed,
    this.filename,
    this.tmpFilename,
    this.percent,
    this.stagePercent,
    this.postprocessor,
    this.preprocessor,
    this.currentItem,
    this.totalItems,
    this.message,
    this.playlistIndex,
    this.playlistCurrentIndex,
    this.playlistCount,
    this.playlistCompletedItems,
    this.playlistTotalItems,
    this.playlistPendingItems,
    this.playlistPercent,
    this.playlistCurrentEntryId,
    this.playlistCompletedIndices,
    this.playlistNewlyCompletedIndex,
    this.playlistFailedIndices,
    this.playlistPendingRetryIndices,
    this.playlistEntryErrors,
  });

  factory DownloadProgress.fromJson(Map<String, dynamic> json) {
    return DownloadProgress(
      status: json['status'] as String?,
      stage: json['stage'] as String?,
      stageName: json['stage_name'] as String?,
      downloadedBytes: _toInt(json['downloaded_bytes']),
      totalBytes: _toInt(json['total_bytes']),
      speed: _toDouble(json['speed']),
      eta: _toInt(json['eta']),
      elapsed: _toDouble(json['elapsed']),
      filename: json['filename'] as String?,
      tmpFilename: json['tmpfilename'] as String?,
      percent: _toDouble(json['percent']),
      stagePercent: _toDouble(json['stage_percent']),
      postprocessor: json['postprocessor'] as String?,
      preprocessor: json['preprocessor'] as String?,
      currentItem: _toInt(json['current_item']),
      totalItems: _toInt(json['total_items']),
      message: json['message'] as String?,
      playlistIndex: _toInt(json['playlist_index']),
      playlistCurrentIndex: _toInt(json['playlist_current_index']),
      playlistCount: _toInt(json['playlist_count']),
      playlistCompletedItems: _toInt(json['playlist_completed_items']),
      playlistTotalItems: _toInt(json['playlist_total_items']),
      playlistPendingItems: _toInt(json['playlist_pending_items']),
      playlistPercent: _toDouble(json['playlist_percent']),
      playlistCurrentEntryId: _normalizeString(
        json['playlist_current_entry_id'],
      ),
      playlistCompletedIndices: _toIntList(json['playlist_completed_indices']),
      playlistNewlyCompletedIndex: _toInt(
        json['playlist_newly_completed_index'],
      ),
      playlistFailedIndices: _toIntList(json['playlist_failed_indices']),
      playlistPendingRetryIndices: _toIntList(json['playlist_pending_indices']),
      playlistEntryErrors: _parsePlaylistEntryErrors(
        json['playlist_entry_errors'],
      ),
    );
  }

  final String? status;
  final String? stage;
  final String? stageName;
  final int? downloadedBytes;
  final int? totalBytes;
  final double? speed;
  final int? eta;
  final double? elapsed;
  final String? filename;
  final String? tmpFilename;
  final double? percent;
  final double? stagePercent;
  final String? postprocessor;
  final String? preprocessor;
  final int? currentItem;
  final int? totalItems;
  final String? message;
  final int? playlistIndex;
  final int? playlistCurrentIndex;
  final int? playlistCount;
  final int? playlistCompletedItems;
  final int? playlistTotalItems;
  final int? playlistPendingItems;
  final double? playlistPercent;
  final String? playlistCurrentEntryId;
  final List<int>? playlistCompletedIndices;
  final int? playlistNewlyCompletedIndex;
  final List<int>? playlistFailedIndices;
  final List<int>? playlistPendingRetryIndices;
  final List<DownloadPlaylistEntryError>? playlistEntryErrors;

  bool get hasPlaylistMetrics {
    return playlistTotalItems != null ||
        playlistCount != null ||
        playlistCompletedItems != null ||
        playlistPendingItems != null ||
        playlistPercent != null ||
        playlistIndex != null ||
        playlistCurrentIndex != null ||
        playlistCurrentEntryId != null ||
        (playlistCompletedIndices != null &&
            playlistCompletedIndices!.isNotEmpty) ||
        playlistNewlyCompletedIndex != null ||
        (playlistFailedIndices != null && playlistFailedIndices!.isNotEmpty) ||
        (playlistPendingRetryIndices != null &&
            playlistPendingRetryIndices!.isNotEmpty) ||
        (playlistEntryErrors != null && playlistEntryErrors!.isNotEmpty);
  }

  DownloadProgress merge(DownloadProgress other) {
    final mergedStage = other.stage ?? stage;
    final mergedStagePercent = other.stage != null && other.stage != stage
        ? other.stagePercent
        : other.stagePercent ?? stagePercent;
    final mergedPercent = other.percent ?? percent;
    final mergedMessage = other.stage != null && other.stage != stage
        ? other.message
        : other.message ?? message;
    final mergedStageName = other.stage != null && other.stage != stage
        ? other.stageName
        : other.stageName ?? stageName;
    final mergedPostprocessor = other.stage != null && other.stage != stage
        ? other.postprocessor
        : other.postprocessor ?? postprocessor;
    final mergedPreprocessor = other.stage != null && other.stage != stage
        ? other.preprocessor
        : other.preprocessor ?? preprocessor;
    final mergedIndices = _mergeIndices(
      playlistCompletedIndices,
      other.playlistCompletedIndices,
      other.playlistNewlyCompletedIndex,
    );
    return DownloadProgress(
      status: other.status ?? status,
      stage: mergedStage,
      stageName: mergedStageName,
      downloadedBytes: other.downloadedBytes ?? downloadedBytes,
      totalBytes: other.totalBytes ?? totalBytes,
      speed: other.speed ?? speed,
      eta: other.eta ?? eta,
      elapsed: other.elapsed ?? elapsed,
      filename: other.filename ?? filename,
      tmpFilename: other.tmpFilename ?? tmpFilename,
      percent: mergedPercent,
      stagePercent: mergedStagePercent,
      postprocessor: mergedPostprocessor,
      preprocessor: mergedPreprocessor,
      currentItem: other.currentItem ?? currentItem,
      totalItems: other.totalItems ?? totalItems,
      message: mergedMessage,
      playlistIndex: other.playlistIndex ?? playlistIndex,
      playlistCurrentIndex:
          other.playlistCurrentIndex ??
          other.playlistIndex ??
          playlistCurrentIndex ??
          playlistIndex,
      playlistCount: other.playlistCount ?? playlistCount,
      playlistCompletedItems:
          other.playlistCompletedItems ?? playlistCompletedItems,
      playlistTotalItems: other.playlistTotalItems ?? playlistTotalItems,
      playlistPendingItems: other.playlistPendingItems ?? playlistPendingItems,
      playlistPercent: other.playlistPercent ?? playlistPercent,
      playlistCurrentEntryId:
          other.playlistCurrentEntryId ?? playlistCurrentEntryId,
      playlistCompletedIndices: mergedIndices ?? playlistCompletedIndices,
      playlistNewlyCompletedIndex:
          other.playlistNewlyCompletedIndex ?? playlistNewlyCompletedIndex,
      playlistFailedIndices:
          _mergeIndices(
            playlistFailedIndices,
            other.playlistFailedIndices,
            null,
          ) ??
          playlistFailedIndices,
      playlistPendingRetryIndices:
          _mergeIndices(
            playlistPendingRetryIndices,
            other.playlistPendingRetryIndices,
            null,
          ) ??
          playlistPendingRetryIndices,
      playlistEntryErrors:
          _mergeEntryErrorLists(
            playlistEntryErrors,
            other.playlistEntryErrors,
          ) ??
          playlistEntryErrors,
    );
  }
}

class DownloadPlaylistEntryRef {
  const DownloadPlaylistEntryRef({this.index, this.id, this.status});

  factory DownloadPlaylistEntryRef.fromJson(Map<String, dynamic> json) {
    return DownloadPlaylistEntryRef(
      index: _toInt(json['index']),
      id: _normalizeString(json['id']),
      status: _normalizeString(json['status'] ?? json['state_hint']),
    );
  }

  final int? index;
  final String? id;
  final String? status;
}

class DownloadPlaylistEntryError {
  const DownloadPlaylistEntryError({
    required this.index,
    this.entryId,
    this.url,
    this.message,
    this.recordedAt,
    this.lastStatus,
    this.pendingRetry = false,
  });

  factory DownloadPlaylistEntryError.fromJson(Map<String, dynamic> json) {
    return DownloadPlaylistEntryError(
      index: _toInt(json['index']) ?? 0,
      entryId: _normalizeString(json['entry_id']),
      url: _normalizeString(json['url']),
      message: _normalizeString(json['message']),
      recordedAt: _parseUploadDate(json['recorded_at']),
      lastStatus: _normalizeString(json['last_status']),
      pendingRetry: json['pending_retry'] == true,
    );
  }

  final int index;
  final String? entryId;
  final String? url;
  final String? message;
  final DateTime? recordedAt;
  final String? lastStatus;
  final bool pendingRetry;
}

class DownloadPlaylistEntry {
  const DownloadPlaylistEntry({
    this.index,
    this.id,
    this.status,
    this.isCompleted = false,
    this.isCurrent = false,
    this.isFailed = false,
    this.isPendingRetry = false,
    this.preview,
    this.progress,
    this.progressSnapshot,
    this.mainFile,
    this.error,
  });

  factory DownloadPlaylistEntry.fromJson(Map<String, dynamic> json) {
    final previewJson = json['preview'];
    DownloadPreview? preview;
    if (previewJson is Map<String, dynamic>) {
      preview = DownloadPreview.fromJson(previewJson);
    }
    final progressJson = json['progress'];
    DownloadProgress? progress;
    if (progressJson is Map<String, dynamic>) {
      progress = DownloadProgress.fromJson(progressJson);
    }
    final snapshotJson = json['progress_snapshot'];
    DownloadProgress? progressSnapshot;
    if (snapshotJson is Map<String, dynamic>) {
      progressSnapshot = DownloadProgress.fromJson(snapshotJson);
    }

    final statusValue =
        _normalizeString(json['status']) ??
        _normalizeString(json['state_hint']);
    final normalizedStatus = statusValue?.toLowerCase();
    final completedFlag =
        json['is_completed'] == true ||
        normalizedStatus == 'completed' ||
        normalizedStatus == 'completed_with_errors' ||
        normalizedStatus == 'finished_with_errors';
    final currentFlag = json['is_current'] == true;

    return DownloadPlaylistEntry(
      index: _toInt(json['index']),
      id: _normalizeString(json['id']) ?? _normalizeString(json['entry_id']),
      status: statusValue,
      isCompleted: completedFlag,
      isCurrent: currentFlag,
      preview: preview,
      progress: progress,
      progressSnapshot: progressSnapshot,
      mainFile: _normalizeString(json['main_file']),
      isFailed: json['is_failed'] == true,
      isPendingRetry: json['pending_retry'] == true,
      error: _parsePlaylistEntryError(json['error'] ?? json['last_error']),
    );
  }

  final int? index;
  final String? id;
  final String? status;
  final bool isCompleted;
  final bool isCurrent;
  final bool isFailed;
  final bool isPendingRetry;
  final DownloadPreview? preview;
  final DownloadProgress? progress;
  final DownloadProgress? progressSnapshot;
  final String? mainFile;
  final DownloadPlaylistEntryError? error;
}

DownloadPlaylistEntryError? _parsePlaylistEntryError(Object? raw) {
  if (raw is Map<String, dynamic>) {
    return DownloadPlaylistEntryError.fromJson(raw);
  }
  if (raw is Map) {
    try {
      return DownloadPlaylistEntryError.fromJson(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
  return null;
}

class DownloadPlaylistSummary {
  const DownloadPlaylistSummary({
    this.id,
    this.title,
    this.uploader,
    this.channel,
    this.thumbnailUrl,
    this.description,
    this.descriptionShort,
    this.webpageUrl,
    this.entryCount,
    this.totalItems,
    this.completedItems,
    this.pendingItems,
    this.percent,
    this.currentIndex,
    this.currentEntryId,
    this.entriesEndpoint,
    this.entryRefs = const <DownloadPlaylistEntryRef>[],
    this.entries = const <DownloadPlaylistEntry>[],
    this.thumbnails = const <DownloadPreviewThumbnail>[],
    this.completedIndices,
    this.isPlaylist,
    this.entriesVersion,
    this.entriesExternal = false,
    this.failedIndices,
    this.pendingRetryIndices,
    this.entryErrors = const <DownloadPlaylistEntryError>[],
    this.isCollectingEntries,
    this.collectionComplete,
    this.hasIndefiniteLength,
  });

  factory DownloadPlaylistSummary.fromJson(Map<String, dynamic> json) {
    final entryRefMaps = _coerceMapList(json['entry_refs']);
    final entryRefs = entryRefMaps.isEmpty
        ? const <DownloadPlaylistEntryRef>[]
        : entryRefMaps
              .map(DownloadPlaylistEntryRef.fromJson)
              .toList(growable: false);

    final entryMaps = _coerceMapList(json['entries']);
    final entries = entryMaps.isEmpty
        ? const <DownloadPlaylistEntry>[]
        : entryMaps.map(DownloadPlaylistEntry.fromJson).toList(growable: false);

    final thumbnailMaps = _coerceMapList(json['thumbnails']);
    final thumbnails = thumbnailMaps.isEmpty
        ? const <DownloadPreviewThumbnail>[]
        : thumbnailMaps
              .map(DownloadPreviewThumbnail.fromJson)
              .toList(growable: false);

    final completedIndices = _toIntList(json['completed_indices']);
    final failedIndices = _toIntList(json['failed_indices']);
    final pendingRetryIndices = _toIntList(json['pending_retry_indices']);
    final entryErrors =
        _parsePlaylistEntryErrors(json['entry_errors']) ??
        const <DownloadPlaylistEntryError>[];

    int? entryCount = _toInt(json['entry_count']);
    int? totalItems = _toInt(json['total_items']);
    final completedItems = _toInt(json['completed_items']);
    final pendingItems = _toInt(json['pending_items']);
    final percent = _toDouble(json['percent']);
    final currentIndex = _toInt(json['current_index']);
    final currentEntryId = _normalizeString(json['current_entry_id']);
    final entriesEndpoint = _normalizeString(json['entries_endpoint']);
    final playlistFlag = _toBool(json['is_playlist']);
    final entriesVersion = _toInt(json['entries_version']);
    final entriesExternalFlag = _toBool(json['entries_external']);
    final entriesExternal =
        entriesExternalFlag == true || entriesVersion != null;
    final isCollectingEntries = _toBool(json['is_collecting_entries']);
    final collectionComplete = _toBool(json['collection_complete']);
    final hasIndefiniteLength = _toBool(json['has_indefinite_length']);

    entryCount ??= entries.length;
    totalItems ??= entryCount;

    return DownloadPlaylistSummary(
      id: _normalizeString(json['id']),
      title: _normalizeString(json['title']),
      uploader: _normalizeString(json['uploader']),
      channel: _normalizeString(json['channel']),
      thumbnailUrl: _normalizeString(json['thumbnail_url']),
      description: _normalizeString(json['description']),
      descriptionShort: _normalizeString(json['description_short']),
      webpageUrl: _normalizeString(json['webpage_url']),
      entryCount: entryCount,
      totalItems: totalItems,
      completedItems: completedItems,
      pendingItems: pendingItems,
      percent: percent,
      currentIndex: currentIndex,
      currentEntryId: currentEntryId,
      entriesEndpoint: entriesEndpoint,
      entryRefs: entryRefs,
      entries: entries,
      thumbnails: thumbnails,
      completedIndices: completedIndices,
      isPlaylist: playlistFlag,
      entriesVersion: entriesVersion,
      entriesExternal: entriesExternal,
      failedIndices: failedIndices,
      pendingRetryIndices: pendingRetryIndices,
      entryErrors: entryErrors,
      isCollectingEntries: isCollectingEntries,
      collectionComplete: collectionComplete,
      hasIndefiniteLength: hasIndefiniteLength,
    )._withDerivedMetrics();
  }

  static DownloadPlaylistSummary? fromProgress(DownloadProgress progress) {
    if (!progress.hasPlaylistMetrics) {
      return null;
    }
    final combinedIndices = _mergeIndices(
      progress.playlistCompletedIndices,
      null,
      progress.playlistNewlyCompletedIndex,
    );
    final totalItemsHint =
        progress.playlistTotalItems ?? progress.playlistCount;
    final pendingItems = progress.playlistPendingItems;
    final bool? isCollectingEntries = pendingItems != null
        ? pendingItems > 0
        : null;
    bool? collectionComplete;
    if (pendingItems != null) {
      collectionComplete = pendingItems <= 0;
    } else if (totalItemsHint != null && totalItemsHint > 0) {
      final completed = progress.playlistCompletedItems;
      if (completed != null) {
        collectionComplete = completed >= totalItemsHint;
      }
    }
    bool? hasIndefiniteLength;
    if (totalItemsHint != null && totalItemsHint > 0) {
      hasIndefiniteLength = false;
    }
    return DownloadPlaylistSummary(
      totalItems: totalItemsHint,
      entryCount: progress.playlistCount ?? progress.playlistTotalItems,
      completedItems: progress.playlistCompletedItems,
      pendingItems: progress.playlistPendingItems,
      percent: progress.playlistPercent,
      currentIndex: progress.playlistCurrentIndex ?? progress.playlistIndex,
      currentEntryId: progress.playlistCurrentEntryId,
      completedIndices: combinedIndices ?? progress.playlistCompletedIndices,
      isPlaylist: true,
      failedIndices: progress.playlistFailedIndices,
      pendingRetryIndices: progress.playlistPendingRetryIndices,
      entryErrors:
          progress.playlistEntryErrors ?? const <DownloadPlaylistEntryError>[],
      isCollectingEntries: isCollectingEntries,
      collectionComplete: collectionComplete,
      hasIndefiniteLength: hasIndefiniteLength,
    )._withDerivedMetrics();
  }

  static DownloadPlaylistSummary? fromProgressEvent(Map<String, dynamic> json) {
    final totalItems =
        _toInt(json['playlist_total_items']) ?? _toInt(json['playlist_count']);
    final entryCount = _toInt(json['playlist_count']) ?? totalItems;
    final completedItems = _toInt(json['playlist_completed_items']);
    final pendingItems = _toInt(json['playlist_pending_items']);
    final percent = _toDouble(json['playlist_percent']);
    final currentIndex = _toInt(json['playlist_current_index']);
    final currentEntryId = _normalizeString(json['playlist_current_entry_id']);
    final completedIndices = _toIntList(json['playlist_completed_indices']);
    final newlyCompleted = _toInt(json['playlist_newly_completed_index']);
    final failedIndices = _toIntList(json['playlist_failed_indices']);
    final pendingRetryIndices = _toIntList(json['playlist_pending_indices']);
    final entryErrors =
        _parsePlaylistEntryErrors(json['playlist_entry_errors']) ??
        const <DownloadPlaylistEntryError>[];

    if (totalItems == null &&
        entryCount == null &&
        completedItems == null &&
        pendingItems == null &&
        percent == null &&
        currentIndex == null &&
        currentEntryId == null &&
        (completedIndices == null || completedIndices.isEmpty) &&
        newlyCompleted == null) {
      return null;
    }

    final mergedIndices = _mergeIndices(completedIndices, null, newlyCompleted);

    final bool? isCollectingEntries = pendingItems != null
        ? pendingItems > 0
        : null;
    bool? collectionComplete;
    if (pendingItems != null) {
      collectionComplete = pendingItems <= 0;
    } else if (totalItems != null && totalItems > 0) {
      if (completedItems != null) {
        collectionComplete = completedItems >= totalItems;
      }
    }
    bool? hasIndefiniteLength;
    if (totalItems != null && totalItems > 0) {
      hasIndefiniteLength = false;
    }

    return DownloadPlaylistSummary(
      totalItems: totalItems,
      entryCount: entryCount,
      completedItems: completedItems,
      pendingItems: pendingItems,
      percent: percent,
      currentIndex: currentIndex,
      currentEntryId: currentEntryId,
      completedIndices: mergedIndices ?? completedIndices,
      isPlaylist: true,
      failedIndices: failedIndices,
      pendingRetryIndices: pendingRetryIndices,
      entryErrors: entryErrors,
      isCollectingEntries: isCollectingEntries,
      collectionComplete: collectionComplete,
      hasIndefiniteLength: hasIndefiniteLength,
    )._withDerivedMetrics();
  }

  DownloadPlaylistSummary merge(DownloadPlaylistSummary other) {
    final mergedEntryRefs = other.entryRefs.isNotEmpty
        ? other.entryRefs
        : entryRefs;
    final mergedEntries = other.entries.isNotEmpty ? other.entries : entries;
    final mergedThumbnails = other.thumbnails.isNotEmpty
        ? other.thumbnails
        : thumbnails;
    final mergedIndices = _mergeIndices(
      completedIndices,
      other.completedIndices,
      null,
    );
    final mergedFailed = _mergeIndices(
      failedIndices,
      other.failedIndices,
      null,
    );
    final mergedPendingRetry = _mergeIndices(
      pendingRetryIndices,
      other.pendingRetryIndices,
      null,
    );
    final mergedEntryErrors = _mergeEntryErrorLists(
      entryErrors,
      other.entryErrors,
    );

    final clearsCurrent =
        other.currentIndex != null && other.currentIndex! <= 0;
    final mergedCurrentIndex = clearsCurrent
        ? null
        : other.currentIndex ?? currentIndex;
    final mergedCurrentEntryId = clearsCurrent
        ? null
        : other.currentEntryId ?? currentEntryId;
    final mergedEntriesVersion = other.entriesVersion ?? entriesVersion;
    final mergedEntriesExternal =
        other.entriesExternal ||
        entriesExternal ||
        mergedEntriesVersion != null;

    return DownloadPlaylistSummary(
      id: other.id ?? id,
      title: other.title ?? title,
      uploader: other.uploader ?? uploader,
      channel: other.channel ?? channel,
      thumbnailUrl: other.thumbnailUrl ?? thumbnailUrl,
      description: other.description ?? description,
      descriptionShort: other.descriptionShort ?? descriptionShort,
      webpageUrl: other.webpageUrl ?? webpageUrl,
      entryCount: other.entryCount ?? entryCount,
      totalItems:
          other.totalItems ?? totalItems ?? other.entryCount ?? entryCount,
      completedItems: other.completedItems ?? completedItems,
      pendingItems: other.pendingItems ?? pendingItems,
      percent: other.percent ?? percent,
      currentIndex: mergedCurrentIndex,
      currentEntryId: mergedCurrentEntryId,
      entriesEndpoint: other.entriesEndpoint ?? entriesEndpoint,
      entryRefs: mergedEntryRefs,
      entries: mergedEntries,
      thumbnails: mergedThumbnails,
      completedIndices: mergedIndices ?? completedIndices,
      isPlaylist: other.isPlaylist ?? isPlaylist,
      entriesVersion: mergedEntriesVersion,
      entriesExternal: mergedEntriesExternal,
      failedIndices: mergedFailed ?? failedIndices,
      pendingRetryIndices: mergedPendingRetry ?? pendingRetryIndices,
      entryErrors: mergedEntryErrors ?? entryErrors,
      isCollectingEntries: other.isCollectingEntries ?? isCollectingEntries,
      collectionComplete: other.collectionComplete ?? collectionComplete,
      hasIndefiniteLength: other.hasIndefiniteLength ?? hasIndefiniteLength,
    )._withDerivedMetrics();
  }

  DownloadPlaylistSummary applyProgress(DownloadProgress progress) {
    final summary = DownloadPlaylistSummary.fromProgress(progress);
    if (summary == null) {
      return this;
    }
    return merge(summary);
  }

  bool get hasEntries => entries.isNotEmpty;

  DownloadPlaylistSummary _withDerivedMetrics() {
    final resolvedTotal = totalItems ?? entryCount;
    int? derivedCompleted = completedItems;
    int? derivedPending = pendingItems;
    double? derivedPercent = percent;

    if (resolvedTotal != null) {
      if (derivedCompleted == null && derivedPending != null) {
        final computed = resolvedTotal - derivedPending;
        derivedCompleted = computed < 0 ? 0 : computed;
      } else if (derivedPending == null && derivedCompleted != null) {
        final computed = resolvedTotal - derivedCompleted;
        derivedPending = computed < 0 ? 0 : computed;
      }
      if (derivedCompleted != null &&
          derivedPercent == null &&
          resolvedTotal > 0) {
        derivedPercent = (derivedCompleted / resolvedTotal) * 100;
      }
    }

    final clampedPercent = derivedPercent?.clamp(0.0, 100.0).toDouble();
    final normalizedEntries = _syncEntryStates(
      entries,
      completedIndices,
      currentIndex,
      failedIndices,
      pendingRetryIndices,
      entryErrors,
    );
    final normalizedEntryErrors = entryErrors.isEmpty
        ? const <DownloadPlaylistEntryError>[]
        : List<DownloadPlaylistEntryError>.unmodifiable(entryErrors);

    bool? resolvedCollectionComplete = collectionComplete;
    if (resolvedCollectionComplete == null) {
      if (isCollectingEntries == true) {
        resolvedCollectionComplete = false;
      } else if (resolvedTotal != null && resolvedTotal > 0) {
        if (derivedPending != null) {
          resolvedCollectionComplete = derivedPending <= 0;
        } else if (derivedCompleted != null) {
          resolvedCollectionComplete = derivedCompleted >= resolvedTotal;
        }
      }
    }
    bool? normalizedCollecting = isCollectingEntries;
    if (normalizedCollecting == null) {
      if (resolvedCollectionComplete == true) {
        normalizedCollecting = false;
      } else if (resolvedCollectionComplete == false) {
        normalizedCollecting = true;
      }
    }
    bool? resolvedHasIndefiniteLength = hasIndefiniteLength;
    resolvedHasIndefiniteLength ??= resolvedTotal == null;

    return DownloadPlaylistSummary(
      id: id,
      title: title,
      uploader: uploader,
      channel: channel,
      thumbnailUrl: thumbnailUrl,
      description: description,
      descriptionShort: descriptionShort,
      webpageUrl: webpageUrl,
      entryCount: entryCount ?? resolvedTotal,
      totalItems: resolvedTotal,
      completedItems: derivedCompleted,
      pendingItems: derivedPending,
      percent: clampedPercent,
      currentIndex: currentIndex,
      currentEntryId: currentEntryId,
      entriesEndpoint: entriesEndpoint,
      entryRefs: entryRefs,
      entries: normalizedEntries,
      thumbnails: thumbnails,
      completedIndices: completedIndices,
      isPlaylist: isPlaylist,
      entriesVersion: entriesVersion,
      entriesExternal: entriesExternal,
      failedIndices: failedIndices,
      pendingRetryIndices: pendingRetryIndices,
      entryErrors: normalizedEntryErrors,
      isCollectingEntries: normalizedCollecting,
      collectionComplete: resolvedCollectionComplete,
      hasIndefiniteLength: resolvedHasIndefiniteLength,
    );
  }

  List<DownloadPlaylistEntry> _syncEntryStates(
    List<DownloadPlaylistEntry> entries,
    List<int>? completedIndices,
    int? currentIndex,
    List<int>? failedIndices,
    List<int>? pendingRetryIndices,
    List<DownloadPlaylistEntryError> entryErrors,
  ) {
    if (entries.isEmpty) {
      return entries;
    }
    final completedSet = <int>{};
    if (completedIndices != null && completedIndices.isNotEmpty) {
      completedSet.addAll(completedIndices);
    }
    final failedSet = <int>{};
    if (failedIndices != null && failedIndices.isNotEmpty) {
      failedSet.addAll(failedIndices);
    }
    final pendingRetrySet = <int>{};
    if (pendingRetryIndices != null && pendingRetryIndices.isNotEmpty) {
      pendingRetrySet.addAll(pendingRetryIndices);
    }
    final errorLookup = <int, DownloadPlaylistEntryError>{};
    for (final record in entryErrors) {
      if (record.index > 0) {
        errorLookup[record.index] = record;
      }
    }
    final updated = <DownloadPlaylistEntry>[];
    var changed = false;
    for (final entry in entries) {
      final index = entry.index;
      final hasFailure = index != null && failedSet.contains(index);
      final isCompleted = index != null && completedSet.contains(index);
      final isCurrent =
          index != null && currentIndex != null && index == currentIndex;
      final isFailed = hasFailure;
      final isPendingRetry = index != null && pendingRetrySet.contains(index);
      final associatedError = index != null ? errorLookup[index] : null;
      final normalizedStatus = _normalizeEntryStatus(
        entry.status,
        isCurrent: isCurrent,
        isCompleted: isCompleted,
        isFailed: isFailed,
        isPendingRetry: isPendingRetry,
      );
      final normalizedProgress = isCompleted ? null : entry.progress;
      if (entry.isCompleted != isCompleted ||
          entry.isCurrent != isCurrent ||
          normalizedStatus != entry.status ||
          normalizedProgress != entry.progress ||
          entry.isFailed != isFailed ||
          entry.isPendingRetry != isPendingRetry ||
          entry.error != associatedError) {
        changed = true;
        updated.add(
          DownloadPlaylistEntry(
            index: entry.index,
            id: entry.id,
            status: normalizedStatus,
            isCompleted: isCompleted,
            isCurrent: isCurrent,
            isFailed: isFailed,
            isPendingRetry: isPendingRetry,
            preview: entry.preview,
            progress: normalizedProgress,
            progressSnapshot: entry.progressSnapshot,
            mainFile: entry.mainFile,
            error: associatedError,
          ),
        );
      } else {
        updated.add(entry);
      }
    }
    if (!changed) {
      return entries;
    }
    return List<DownloadPlaylistEntry>.unmodifiable(updated);
  }

  String? _normalizeEntryStatus(
    String? status, {
    required bool isCurrent,
    required bool isCompleted,
    required bool isFailed,
    required bool isPendingRetry,
  }) {
    final normalized = status?.toLowerCase();
    if (isCurrent) {
      if (normalized == null ||
          normalized == 'pending' ||
          normalized == 'completed' ||
          normalized == 'finished') {
        return 'active';
      }
      return status;
    }
    if (isCompleted) {
      if (normalized == null ||
          normalized == 'active' ||
          normalized == 'pending' ||
          normalized == 'finished') {
        return 'completed';
      }
      return status;
    }
    if (isFailed) {
      return 'failed';
    }
    if (isPendingRetry) {
      return 'pending_retry';
    }
    if (normalized == 'active' || normalized == 'completed') {
      return 'pending';
    }
    return status;
  }

  final String? id;
  final String? title;
  final String? uploader;
  final String? channel;
  final String? thumbnailUrl;
  final String? description;
  final String? descriptionShort;
  final String? webpageUrl;
  final int? entryCount;
  final int? totalItems;
  final int? completedItems;
  final int? pendingItems;
  final double? percent;
  final int? currentIndex;
  final String? currentEntryId;
  final String? entriesEndpoint;
  final List<DownloadPlaylistEntryRef> entryRefs;
  final List<DownloadPlaylistEntry> entries;
  final List<DownloadPreviewThumbnail> thumbnails;
  final List<int>? completedIndices;
  final bool? isPlaylist;
  final int? entriesVersion;
  final bool entriesExternal;
  final List<int>? failedIndices;
  final List<int>? pendingRetryIndices;
  final List<DownloadPlaylistEntryError> entryErrors;
  final bool? isCollectingEntries;
  final bool? collectionComplete;
  final bool? hasIndefiniteLength;
}

class DownloadPlaylistSnapshot {
  const DownloadPlaylistSnapshot({
    required this.jobId,
    required this.summary,
    this.status,
  });

  factory DownloadPlaylistSnapshot.fromJson(Map<String, dynamic> json) {
    final jobId = _normalizeString(json['job_id']) ?? '';
    final playlistJson = json['playlist'];
    if (playlistJson is! Map<String, dynamic>) {
      throw const FormatException('Playlist payload missing');
    }
    final summary = DownloadPlaylistSummary.fromJson(
      playlistJson.cast<String, dynamic>(),
    );
    final statusRaw = json['status'] as String?;
    DownloadStatus? status;
    if (statusRaw != null && statusRaw.isNotEmpty) {
      status = downloadStatusFromString(statusRaw);
    }
    return DownloadPlaylistSnapshot(
      jobId: jobId,
      summary: summary,
      status: status,
    );
  }

  final String jobId;
  final DownloadPlaylistSummary summary;
  final DownloadStatus? status;
}

class DownloadPlaylistDeltaSnapshot {
  const DownloadPlaylistDeltaSnapshot({
    required this.jobId,
    required this.summary,
    this.status,
    this.version,
    this.delta,
  });

  factory DownloadPlaylistDeltaSnapshot.fromJson(Map<String, dynamic> json) {
    final snapshot = DownloadPlaylistSnapshot.fromJson(json);
    final rawDelta = json['delta'];
    DownloadJobDeltaSnapshot? delta;
    if (rawDelta is Map<String, dynamic>) {
      delta = DownloadJobDeltaSnapshot.fromJson(rawDelta);
    } else if (rawDelta is Map) {
      delta = DownloadJobDeltaSnapshot.fromJson(
        rawDelta.cast<String, dynamic>(),
      );
    }
    final version = _toInt(json['version']);
    return DownloadPlaylistDeltaSnapshot(
      jobId: snapshot.jobId,
      summary: snapshot.summary,
      status: snapshot.status,
      version: version,
      delta: delta,
    );
  }

  final String jobId;
  final DownloadPlaylistSummary summary;
  final DownloadStatus? status;
  final int? version;
  final DownloadJobDeltaSnapshot? delta;

  bool get hasEntries => summary.entries.isNotEmpty;
}

class DownloadLogEntry {
  const DownloadLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  factory DownloadLogEntry.fromJson(Map<String, dynamic> json) {
    return DownloadLogEntry(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? ''),
      level: json['level'] as String? ?? 'info',
      message: json['message'] as String? ?? '',
    );
  }

  final DateTime? timestamp;
  final String level;
  final String message;
}

class DownloadPreview {
  const DownloadPreview({
    this.title,
    this.description,
    this.thumbnailUrl,
    this.durationSeconds,
    this.durationText,
    this.uploader,
    this.channel,
    this.webpageUrl,
    this.originalUrl,
    this.extractor,
    this.extractorId,
    this.uploadDate,
    this.viewCount,
    this.likeCount,
    this.tags = const <String>[],
    this.thumbnails = const <DownloadPreviewThumbnail>[],
  });

  factory DownloadPreview.fromJson(Map<String, dynamic> json) {
    final thumbnails =
        (json['thumbnails'] as List?)
            ?.whereType<Map>()
            .map(
              (entry) => DownloadPreviewThumbnail.fromJson(
                entry.cast<String, dynamic>(),
              ),
            )
            .toList(growable: false) ??
        const <DownloadPreviewThumbnail>[];
    final tags =
        (json['tags'] as List?)
            ?.whereType<String>()
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];

    String? resolveString(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return DownloadPreview(
      title: resolveString('title'),
      description: resolveString('description'),
      thumbnailUrl:
          resolveString('thumbnail_url') ?? resolveString('thumbnail'),
      durationSeconds: _toInt(json['duration_seconds']),
      durationText:
          resolveString('duration_text') ?? resolveString('duration_string'),
      uploader: resolveString('uploader'),
      channel: resolveString('channel'),
      webpageUrl:
          resolveString('webpage_url') ?? resolveString('canonical_url'),
      originalUrl: resolveString('original_url'),
      extractor: resolveString('extractor'),
      extractorId:
          resolveString('extractor_id') ?? resolveString('extractor_key'),
      uploadDate: _parseUploadDate(
        json['upload_date_iso'] ?? json['upload_date'],
      ),
      viewCount: _toInt(json['view_count']),
      likeCount: _toInt(json['like_count']),
      tags: tags,
      thumbnails: thumbnails,
    );
  }

  static DownloadPreview? fromMetadata(Map<String, dynamic> metadata) {
    final preview = metadata['preview'];
    if (preview is Map<String, dynamic>) {
      return DownloadPreview.fromJson(preview);
    }
    String? resolveMetadataString(String key) {
      final value = metadata[key];
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      return null;
    }

    final fallbackTitle = metadata['title'];
    final fallbackDescription = metadata['description'];
    final fallbackThumbnail = metadata['thumbnail_url'];
    if (fallbackTitle is! String &&
        fallbackDescription is! String &&
        fallbackThumbnail is! String) {
      return null;
    }
    return DownloadPreview(
      title: fallbackTitle is String ? fallbackTitle : null,
      description: fallbackDescription is String ? fallbackDescription : null,
      thumbnailUrl: fallbackThumbnail is String ? fallbackThumbnail : null,
      extractor: resolveMetadataString('extractor'),
      extractorId:
          resolveMetadataString('extractor_id') ??
          resolveMetadataString('extractor_key'),
    );
  }

  final String? title;
  final String? description;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final String? durationText;
  final String? uploader;
  final String? channel;
  final String? webpageUrl;
  final String? originalUrl;
  final String? extractor;
  final String? extractorId;
  final DateTime? uploadDate;
  final int? viewCount;
  final int? likeCount;
  final List<String> tags;
  final List<DownloadPreviewThumbnail> thumbnails;

  Duration? get duration {
    final seconds = durationSeconds;
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return Duration(seconds: seconds);
  }

  String? shortDescription([int maxLength = 240]) {
    final text = description?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text.length <= maxLength) {
      return text;
    }
    final truncated = text.substring(0, maxLength - 3).trimRight();
    return '$truncated...';
  }

  String? get bestThumbnailUrl {
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return thumbnailUrl;
    }
    if (thumbnails.isEmpty) {
      return null;
    }
    final sortedThumbnails =
        thumbnails
            .where((thumb) => thumb.url.isNotEmpty)
            .toList(growable: false)
          ..sort((a, b) {
            final widthComparison = (b.width ?? 0).compareTo(a.width ?? 0);
            if (widthComparison != 0) {
              return widthComparison;
            }
            return (b.height ?? 0).compareTo(a.height ?? 0);
          });
    if (sortedThumbnails.isEmpty) {
      return null;
    }
    return sortedThumbnails.first.url;
  }
}

class DownloadPreviewThumbnail {
  const DownloadPreviewThumbnail({
    required this.url,
    this.width,
    this.height,
    this.id,
  });

  factory DownloadPreviewThumbnail.fromJson(Map<String, dynamic> json) {
    final url = json['url'];
    return DownloadPreviewThumbnail(
      url: url is String ? url : '',
      width: _toInt(json['width']),
      height: _toInt(json['height']),
      id: json['id'] as String?,
    );
  }

  final String url;
  final int? width;
  final int? height;
  final String? id;
}

class DownloadJobModel {
  const DownloadJobModel({
    required this.id,
    required this.status,
    this.kind = DownloadKind.unknown,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.progress,
    this.error,
    this.creator,
    this.urls = const [],
    this.options = const {},
    this.optionsVersion,
    this.optionsExternal = false,
    this.metadata = const {},
    this.logs = const [],
    this.logsVersion,
    this.logsExternal = false,
    this.playlist,
    this.generatedFiles = const [],
    this.partialFiles = const [],
    this.mainFile,
  });

  factory DownloadJobModel.fromJson(Map<String, dynamic> json) {
    final status = downloadStatusFromString(json['status'] as String?);
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    final startedAt = DateTime.tryParse(json['started_at'] as String? ?? '');
    final finishedAt = DateTime.tryParse(json['finished_at'] as String? ?? '');

    final urls =
        (json['urls'] as List?)?.whereType<String>().toList(growable: false) ??
        const <String>[];

    final options =
        (json['options'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final metadataRaw =
        (json['metadata'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final mutableMetadata = Map<String, dynamic>.from(metadataRaw);
    final previewJson = json['preview'];
    if (previewJson is Map<String, dynamic>) {
      mutableMetadata['preview'] = previewJson;
      void maybeAssign(String key) {
        if (!mutableMetadata.containsKey(key) && previewJson[key] is String) {
          final value = (previewJson[key] as String).trim();
          if (value.isNotEmpty) {
            mutableMetadata[key] = value;
          }
        }
      }

      maybeAssign('title');
      maybeAssign('description');
      maybeAssign('thumbnail_url');
      maybeAssign('webpage_url');
      maybeAssign('original_url');
      maybeAssign('extractor');
      maybeAssign('extractor_id');
      maybeAssign('extractor_key');
    }
    final metadata = Map<String, dynamic>.unmodifiable(mutableMetadata);

    DownloadPlaylistSummary? playlist;
    final playlistJson = json['playlist'];
    if (playlistJson is Map<String, dynamic>) {
      playlist = DownloadPlaylistSummary.fromJson(
        playlistJson.cast<String, dynamic>(),
      );
    }

    final progressJson = json['progress'];
    DownloadProgress? progress;
    if (progressJson is Map<String, dynamic>) {
      progress = DownloadProgress.fromJson(progressJson);
    }

    final logs =
        (json['logs'] as List?)
            ?.whereType<Map>()
            .map(
              (entry) =>
                  DownloadLogEntry.fromJson(entry.cast<String, dynamic>()),
            )
            .toList(growable: false) ??
        const <DownloadLogEntry>[];

    final generatedFiles = _coerceStringList(json['generated_files']);
    final partialFiles = _coerceStringList(json['partial_files']);
    final mainFile = _coerceString(json['main_file']);

    final optionsVersion = _toInt(json['options_version']);
    final logsVersion = _toInt(json['logs_version']);
    final optionsExternalFlag = _toBool(json['options_external']);
    final logsExternalFlag = _toBool(json['logs_external']);
    final optionsExternal =
        optionsExternalFlag == true || optionsVersion != null;
    final logsExternal = logsExternalFlag == true || logsVersion != null;

    final explicitKind = downloadKindFromString(json['kind'] as String?);
    final resolvedKind = _resolveKind(
      incoming: explicitKind,
      current: DownloadKind.unknown,
      playlist: playlist,
    );

    return DownloadJobModel(
      id: json['job_id'] as String? ?? '',
      status: status,
      kind: resolvedKind,
      createdAt: createdAt ?? DateTime.now(),
      startedAt: startedAt,
      finishedAt: finishedAt,
      progress: progress,
      error: json['error'] as String?,
      creator: json['creator'] as String?,
      urls: urls,
      options: options,
      optionsVersion: optionsVersion,
      optionsExternal: optionsExternal,
      metadata: metadata,
      logs: logs,
      logsVersion: logsVersion,
      logsExternal: logsExternal,
      playlist: playlist,
      generatedFiles: generatedFiles,
      partialFiles: partialFiles,
      mainFile: mainFile,
    );
  }

  final String id;
  final DownloadStatus status;
  final DownloadKind kind;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DownloadProgress? progress;
  final String? error;
  final String? creator;
  final List<String> urls;
  final Map<String, dynamic> options;
  final int? optionsVersion;
  final bool optionsExternal;
  final Map<String, dynamic> metadata;
  final List<DownloadLogEntry> logs;
  final int? logsVersion;
  final bool logsExternal;
  final DownloadPlaylistSummary? playlist;
  final List<String> generatedFiles;
  final List<String> partialFiles;
  final String? mainFile;

  bool get isTerminal =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.completedWithErrors ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  bool get isRunning =>
      status == DownloadStatus.running ||
      status == DownloadStatus.starting ||
      status == DownloadStatus.retrying ||
      status == DownloadStatus.cancelling ||
      status == DownloadStatus.pausing;

  bool get isQueued =>
      status == DownloadStatus.queued || status == DownloadStatus.starting;

  bool get isPlaylist {
    if (kind == DownloadKind.playlist) {
      return true;
    }
    if (kind == DownloadKind.video) {
      return false;
    }
    final flag = metadata['is_playlist'];
    if (flag is bool) {
      return flag;
    }
    if (flag is String) {
      final normalized = flag.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return playlist != null;
  }

  bool get isVideo => kind == DownloadKind.video;

  bool get hasIdentifiedKind => kind != DownloadKind.unknown;

  double? get progressPercent => progress?.percent ?? progress?.stagePercent;

  DownloadPreview? get preview => DownloadPreview.fromMetadata(metadata);

  DownloadJobModel merge(DownloadJobModel other) {
    String? resolvedError;
    if (other.error != null && other.error!.isNotEmpty) {
      resolvedError = other.error;
    } else if (other.status != DownloadStatus.failed &&
        other.status != DownloadStatus.cancelled) {
      resolvedError = null;
    } else {
      resolvedError = error;
    }

    final mergedMetadata = other.metadata.isNotEmpty
        ? _mergeMetadataMaps(metadata, other.metadata)
        : metadata;
    final mergedPlaylist = other.playlist != null && playlist != null
        ? playlist!.merge(other.playlist!)
        : other.playlist ?? playlist;

    final incomingOptionsVersion = other.optionsVersion;
    final incomingLogsVersion = other.logsVersion;
    final optionsVersionChanged =
        incomingOptionsVersion != null &&
        incomingOptionsVersion != optionsVersion;
    final logsVersionChanged =
        incomingLogsVersion != null && incomingLogsVersion != logsVersion;

    Map<String, dynamic> mergedOptions;
    if (optionsVersionChanged && other.options.isEmpty) {
      mergedOptions = const <String, dynamic>{};
    } else {
      mergedOptions = other.options.isNotEmpty ? other.options : options;
    }

    List<DownloadLogEntry> mergedLogs;
    if (logsVersionChanged && other.logs.isEmpty) {
      mergedLogs = const <DownloadLogEntry>[];
    } else {
      mergedLogs = other.logs.isNotEmpty ? other.logs : logs;
    }

    final mergedGeneratedFiles = other.generatedFiles.isEmpty
        ? generatedFiles
        : _mergeOutputFiles(generatedFiles, other.generatedFiles);
    final mergedPartialFiles = other.partialFiles.isEmpty
        ? partialFiles
        : _mergeOutputFiles(partialFiles, other.partialFiles);
    final mergedMainFile = _coerceString(other.mainFile) ?? mainFile;

    final mergedOptionsVersion = incomingOptionsVersion ?? optionsVersion;
    final mergedLogsVersion = incomingLogsVersion ?? logsVersion;
    final mergedOptionsExternal =
        other.optionsExternal ||
        optionsExternal ||
        mergedOptionsVersion != null;
    final mergedLogsExternal =
        other.logsExternal || logsExternal || mergedLogsVersion != null;
    final resolvedKind = _resolveKind(
      incoming: other.kind,
      current: kind,
      playlist: mergedPlaylist,
    );

    return DownloadJobModel(
      id: id,
      status: other.status != DownloadStatus.unknown ? other.status : status,
      kind: resolvedKind,
      createdAt: other.createdAt,
      startedAt: other.startedAt ?? startedAt,
      finishedAt: other.finishedAt ?? finishedAt,
      progress: other.progress != null
          ? (progress?.merge(other.progress!) ?? other.progress)
          : progress,
      error: resolvedError,
      creator: other.creator ?? creator,
      urls: other.urls.isNotEmpty ? other.urls : urls,
      options: mergedOptions,
      optionsVersion: mergedOptionsVersion,
      optionsExternal: mergedOptionsExternal,
      metadata: mergedMetadata,
      logs: mergedLogs,
      logsVersion: mergedLogsVersion,
      logsExternal: mergedLogsExternal,
      playlist: mergedPlaylist,
      generatedFiles: mergedGeneratedFiles,
      partialFiles: mergedPartialFiles,
      mainFile: mergedMainFile,
    );
  }

  DownloadJobModel applyProgress(DownloadProgress update) {
    final mergedProgress = progress?.merge(update) ?? update;
    DownloadPlaylistSummary? updatedPlaylist = playlist;
    final progressSummary = DownloadPlaylistSummary.fromProgress(
      mergedProgress,
    );
    if (progressSummary != null) {
      updatedPlaylist = updatedPlaylist == null
          ? progressSummary
          : updatedPlaylist.merge(progressSummary);
    }
    final resolvedKind = _resolveKind(
      incoming: null,
      current: kind,
      playlist: updatedPlaylist,
    );
    return DownloadJobModel(
      id: id,
      status: status,
      kind: resolvedKind,
      createdAt: createdAt,
      startedAt: startedAt,
      finishedAt: finishedAt,
      progress: mergedProgress,
      creator: creator,
      urls: urls,
      options: options,
      optionsVersion: optionsVersion,
      optionsExternal: optionsExternal,
      metadata: metadata,
      logs: logs,
      logsVersion: logsVersion,
      logsExternal: logsExternal,
      playlist: updatedPlaylist,
      generatedFiles: generatedFiles,
      partialFiles: partialFiles,
      mainFile: mainFile,
    );
  }

  DownloadJobModel applyPlaylistSummary(DownloadPlaylistSummary summary) {
    final mergedPlaylist = playlist == null
        ? summary
        : playlist!.merge(summary);
    return copyWith(playlist: mergedPlaylist);
  }

  DownloadJobModel copyWith({
    DownloadStatus? status,
    DownloadKind? kind,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    DownloadProgress? progress,
    String? error,
    List<String>? urls,
    Map<String, dynamic>? options,
    Map<String, dynamic>? metadata,
    List<DownloadLogEntry>? logs,
    DownloadPlaylistSummary? playlist,
    int? optionsVersion,
    bool? optionsExternal,
    int? logsVersion,
    bool? logsExternal,
    List<String>? generatedFiles,
    List<String>? partialFiles,
    String? mainFile,
  }) {
    final resolvedMetadata = metadata ?? this.metadata;
    final resolvedPlaylist = playlist ?? this.playlist;
    final resolvedKind = _resolveKind(
      incoming: kind,
      current: this.kind,
      playlist: resolvedPlaylist,
    );
    return DownloadJobModel(
      id: id,
      status: status ?? this.status,
      kind: resolvedKind,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      creator: creator,
      urls: urls ?? this.urls,
      options: options ?? this.options,
      optionsVersion: optionsVersion ?? this.optionsVersion,
      optionsExternal: optionsExternal ?? this.optionsExternal,
      metadata: resolvedMetadata,
      logs: logs ?? this.logs,
      logsVersion: logsVersion ?? this.logsVersion,
      logsExternal: logsExternal ?? this.logsExternal,
      playlist: resolvedPlaylist,
      generatedFiles: generatedFiles ?? this.generatedFiles,
      partialFiles: partialFiles ?? this.partialFiles,
      mainFile: mainFile ?? this.mainFile,
    );
  }
}

class DownloadJobDeltaSnapshot {
  const DownloadJobDeltaSnapshot({
    required this.type,
    this.version,
    this.since,
  });

  factory DownloadJobDeltaSnapshot.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DownloadJobDeltaSnapshot(type: 'full');
    }
    return DownloadJobDeltaSnapshot(
      type: _normalizeString(json['type']) ?? 'full',
      version: _toInt(json['version']),
      since: _toInt(json['since']),
    );
  }

  final String type;
  final int? version;
  final int? since;

  bool get isNoop => type.toLowerCase() == 'noop';
}

class DownloadJobOptionsSnapshot {
  const DownloadJobOptionsSnapshot({
    required this.jobId,
    this.version,
    this.external = false,
    this.delta,
    this.options = const <String, dynamic>{},
  });

  factory DownloadJobOptionsSnapshot.fromJson(Map<String, dynamic> json) {
    final rawDelta = json['delta'];
    DownloadJobDeltaSnapshot? delta;
    if (rawDelta is Map<String, dynamic>) {
      delta = DownloadJobDeltaSnapshot.fromJson(rawDelta);
    } else if (rawDelta is Map) {
      delta = DownloadJobDeltaSnapshot.fromJson(
        rawDelta.cast<String, dynamic>(),
      );
    }
    final options =
        (json['options'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final version = _toInt(json['version']);
    final externalFlag = _toBool(json['external']);
    final resolvedExternal = externalFlag == true || version != null;
    final jobId = json['job_id'] as String? ?? '';
    return DownloadJobOptionsSnapshot(
      jobId: jobId,
      version: version,
      external: resolvedExternal,
      delta: delta,
      options: options,
    );
  }

  final String jobId;
  final int? version;
  final bool external;
  final DownloadJobDeltaSnapshot? delta;
  final Map<String, dynamic> options;

  bool get hasOptions => options.isNotEmpty;
}

class DownloadJobLogsSnapshot {
  const DownloadJobLogsSnapshot({
    required this.jobId,
    this.version,
    this.external = false,
    this.delta,
    this.logs = const <DownloadLogEntry>[],
    this.count = 0,
  });

  factory DownloadJobLogsSnapshot.fromJson(Map<String, dynamic> json) {
    final rawDelta = json['delta'];
    DownloadJobDeltaSnapshot? delta;
    if (rawDelta is Map<String, dynamic>) {
      delta = DownloadJobDeltaSnapshot.fromJson(rawDelta);
    } else if (rawDelta is Map) {
      delta = DownloadJobDeltaSnapshot.fromJson(
        rawDelta.cast<String, dynamic>(),
      );
    }
    final logs =
        (json['logs'] as List?)
            ?.whereType<Map>()
            .map(
              (entry) =>
                  DownloadLogEntry.fromJson(entry.cast<String, dynamic>()),
            )
            .toList(growable: false) ??
        const <DownloadLogEntry>[];
    final version = _toInt(json['version']);
    final externalFlag = _toBool(json['external']);
    final resolvedExternal = externalFlag == true || version != null;
    final jobId = json['job_id'] as String? ?? '';
    final count = _toInt(json['count']) ?? logs.length;
    return DownloadJobLogsSnapshot(
      jobId: jobId,
      version: version,
      external: resolvedExternal,
      delta: delta,
      logs: logs,
      count: count,
    );
  }

  final String jobId;
  final int? version;
  final bool external;
  final DownloadJobDeltaSnapshot? delta;
  final List<DownloadLogEntry> logs;
  final int count;

  bool get hasLogs => logs.isNotEmpty;
}

DownloadKind _resolveKind({
  DownloadKind? incoming,
  required DownloadKind current,
  DownloadPlaylistSummary? playlist,
}) {
  final DownloadKind explicit = incoming ?? DownloadKind.unknown;
  if (explicit != DownloadKind.unknown) {
    return explicit;
  }

  if (current != DownloadKind.unknown) {
    return current;
  }

  final DownloadKind? playlistHint = _inferKindFromPlaylistSummary(playlist);
  if (playlistHint != null && playlistHint != DownloadKind.unknown) {
    return playlistHint;
  }

  return DownloadKind.unknown;
}

DownloadKind? _inferKindFromPlaylistSummary(DownloadPlaylistSummary? playlist) {
  if (playlist == null) {
    return null;
  }
  if (playlist.isPlaylist == true) {
    return DownloadKind.playlist;
  }
  if (playlist.isPlaylist == false) {
    return DownloadKind.video;
  }
  final int? totalItems = playlist.totalItems ?? playlist.entryCount;
  if (totalItems != null && totalItems > 1) {
    return DownloadKind.playlist;
  }
  if (playlist.entries.isNotEmpty || playlist.entryRefs.isNotEmpty) {
    return DownloadKind.playlist;
  }
  return null;
}

Map<String, dynamic> _mergeMetadataMaps(
  Map<String, dynamic> base,
  Map<String, dynamic> updates,
) {
  if (updates.isEmpty) {
    return base;
  }
  final merged = Map<String, dynamic>.from(base);
  updates.forEach((key, value) {
    if (value == null) {
      merged.remove(key);
    } else {
      merged[key] = value;
    }
  });
  return merged;
}

List<String> _mergeOutputFiles(List<String> current, List<String> updates) {
  if (updates.isEmpty) {
    return current;
  }
  if (current.isEmpty) {
    return List<String>.unmodifiable(updates);
  }
  final merged = <String>[];
  final seen = <String>{};

  void addAll(List<String> source) {
    for (final entry in source) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (seen.add(trimmed)) {
        merged.add(trimmed);
      }
    }
  }

  addAll(current);
  addAll(updates);

  if (merged.isEmpty) {
    return const <String>[];
  }
  return List<String>.unmodifiable(merged);
}

List<DownloadPlaylistEntryError>? _mergeEntryErrorLists(
  List<DownloadPlaylistEntryError>? base,
  List<DownloadPlaylistEntryError>? addition,
) {
  final baseHasEntries = base != null && base.isNotEmpty;
  final additionHasEntries = addition != null && addition.isNotEmpty;
  if (!baseHasEntries && !additionHasEntries) {
    return baseHasEntries ? base : addition;
  }
  final merged = <int, DownloadPlaylistEntryError>{};
  if (base != null) {
    for (final record in base) {
      if (record.index > 0) {
        merged[record.index] = record;
      }
    }
  }
  if (addition != null) {
    for (final record in addition) {
      if (record.index > 0) {
        merged[record.index] = record;
      }
    }
  }
  if (merged.isEmpty) {
    return const <DownloadPlaylistEntryError>[];
  }
  final ordered = merged.values.toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  return List<DownloadPlaylistEntryError>.unmodifiable(ordered);
}

List<DownloadPlaylistEntryError>? _parsePlaylistEntryErrors(Object? value) {
  final maps = _coerceMapList(value);
  if (maps.isEmpty) {
    return null;
  }
  final parsed = maps
      .map(DownloadPlaylistEntryError.fromJson)
      .where((record) => record.index > 0)
      .toList(growable: false);
  if (parsed.isEmpty) {
    return const <DownloadPlaylistEntryError>[];
  }
  return List<DownloadPlaylistEntryError>.unmodifiable(parsed);
}

int compareJobs(DownloadJobModel a, DownloadJobModel b) {
  const priority = {
    DownloadStatus.running: 0,
    DownloadStatus.starting: 1,
    DownloadStatus.retrying: 2,
    DownloadStatus.pausing: 3,
    DownloadStatus.cancelling: 4,
    DownloadStatus.queued: 5,
    DownloadStatus.failed: 6,
    DownloadStatus.cancelled: 7,
    DownloadStatus.completed: 8,
    DownloadStatus.paused: 9,
    DownloadStatus.unknown: 10,
  };

  final statusRankA = priority[a.status] ?? 999;
  final statusRankB = priority[b.status] ?? 999;
  final statusComparison = statusRankA.compareTo(statusRankB);
  if (statusComparison != 0) {
    return statusComparison;
  }
  return b.createdAt.compareTo(a.createdAt);
}

String? _normalizeString(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
  return null;
}

bool? _toBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'y') {
      return true;
    }
    if (normalized == 'false' ||
        normalized == '0' ||
        normalized == 'no' ||
        normalized == 'n') {
      return false;
    }
  }
  if (value is num) {
    if (value == 1) {
      return true;
    }
    if (value == 0) {
      return false;
    }
  }
  return null;
}

List<Map<String, dynamic>> _coerceMapList(Object? source) {
  if (source is Iterable) {
    return source
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList(growable: false);
  }
  if (source is Map) {
    return source.values
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

String? _coerceString(Object? source) {
  if (source is String) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
  return null;
}

List<String> _coerceStringList(Object? source) {
  if (source is Iterable) {
    final items = <String>[];
    for (final entry in source) {
      if (entry is! String) {
        continue;
      }
      final trimmed = entry.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      items.add(trimmed);
    }
    if (items.isEmpty) {
      return const <String>[];
    }
    return List<String>.unmodifiable(items);
  }
  return const <String>[];
}

List<int>? _toIntList(Object? value) {
  if (value is List) {
    if (value.isEmpty) {
      return const <int>[];
    }
    final items = value.map(_toInt).whereType<int>().toList(growable: false);
    if (items.isEmpty) {
      return const <int>[];
    }
    items.sort();
    return List<int>.unmodifiable(items);
  }
  return null;
}

List<int>? _mergeIndices(List<int>? base, List<int>? addition, int? single) {
  final baseList = base;
  final additionList = addition;
  final hasBase = baseList != null && baseList.isNotEmpty;
  final hasAddition = additionList != null && additionList.isNotEmpty;
  final hasSingle = single != null;

  if (!hasBase && !hasAddition && !hasSingle) {
    if (baseList != null && baseList.isEmpty) {
      return baseList;
    }
    if (additionList != null && additionList.isEmpty) {
      return additionList;
    }
    return baseList ?? additionList;
  }

  final result = <int>{};
  if (baseList != null && baseList.isNotEmpty) {
    result.addAll(baseList);
  }
  if (additionList != null && additionList.isNotEmpty) {
    result.addAll(additionList);
  }
  if (single != null) {
    result.add(single);
  }

  if (result.isEmpty) {
    if (baseList != null && baseList.isEmpty) {
      return baseList;
    }
    if (additionList != null && additionList.isEmpty) {
      return additionList;
    }
    return null;
  }

  final sorted = result.toList()..sort();
  return List<int>.unmodifiable(sorted);
}

int? _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double? _toDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

DateTime? _parseUploadDate(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length == 8 && int.tryParse(trimmed) != null) {
      final formatted =
          '${trimmed.substring(0, 4)}-${trimmed.substring(4, 6)}-${trimmed.substring(6, 8)}';
      return DateTime.tryParse(formatted);
    }
    return DateTime.tryParse(trimmed);
  }
  return null;
}
