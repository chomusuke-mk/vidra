import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/ui/widgets/jobs/download_job_card.dart';
import 'job_detail_screen.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.jobId});

  final String jobId;

  static Route<void> route(String jobId) {
    return MaterialPageRoute<void>(
      builder: (_) => PlaylistDetailScreen(jobId: jobId),
    );
  }

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late final DownloadController _controller;
  bool _isLoading = false;
  String? _loadError;
  static const List<int> _pageSizeOptions = [25, 50, 100, 200];
  int _pageSize = _pageSizeOptions.first;
  int _pageIndex = 0;
  final Map<String, DownloadJobModel> _entryModelCache =
      <String, DownloadJobModel>{};

  @override
  void initState() {
    super.initState();
    _controller = context.read<DownloadController>();
    _controller.subscribeToPlaylistUpdates(widget.jobId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPlaylist(showSpinner: true);
    });
  }

  @override
  void didUpdateWidget(covariant PlaylistDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId) {
      _controller.unsubscribeFromPlaylistUpdates(oldWidget.jobId);
      _controller.subscribeToPlaylistUpdates(widget.jobId);
      _entryModelCache.clear();
      setState(() {
        _pageIndex = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _refreshPlaylist(showSpinner: true);
      });
    }
  }

  @override
  void dispose() {
    _controller.unsubscribeFromPlaylistUpdates(widget.jobId);
    super.dispose();
  }

  Future<void> _refreshPlaylist({bool showSpinner = false}) async {
    final controller = _controller;
    final localizations = VidraLocalizations.of(context);
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final summary = await controller.loadPlaylist(
        widget.jobId,
        includeEntries: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = summary == null
            ? localizations.ui(AppStringKey.playlistLoadFailed)
            : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.toString();
      });
    } finally {
      if (showSpinner && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DownloadController>();
    final job = controller.jobById(widget.jobId);
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final VoidCallback? openJobDetails = job == null
        ? null
        : () => Navigator.of(context).push(JobDetailScreen.route(job.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          job?.playlist?.title ??
              job?.preview?.title ??
              job?.metadata['playlist_title'] as String? ??
              localizations.ui(AppStringKey.playlistTitleFallback),
        ),
        leading: IconButton(
          tooltip: localizations.ui(AppStringKey.playlistBackToDownloads),
          icon: const Icon(Icons.arrow_back),
          onPressed: _navigateBackToHome,
        ),
        actions: [
          if (openJobDetails != null)
            IconButton(
              tooltip: localizations.ui(
                AppStringKey.playlistViewJobDetailsTooltip,
              ),
              icon: const Icon(Icons.info_outline),
              onPressed: openJobDetails,
            ),
        ],
      ),
      body: job == null
          ? _buildMissingJob(theme, localizations)
          : RefreshIndicator(
              onRefresh: () => _refreshPlaylist(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                children: [
                  if (_isLoading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
                  if (_loadError != null) ...[
                    _buildErrorBanner(theme, _loadError!),
                    const SizedBox(height: 12),
                  ],
                  _buildPlaylistSummary(
                    theme,
                    job,
                    onShowDetails: openJobDetails,
                  ),
                  const SizedBox(height: 24),
                  _buildEntriesSection(theme, job),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildMissingJob(ThemeData theme, VidraLocalizations localizations) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_remove_outlined,
              size: 48,
              color: theme.hintColor,
            ),
            const SizedBox(height: 12),
            Text(
              localizations.ui(AppStringKey.playlistMissingJob),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _navigateBackToHome,
              icon: const Icon(Icons.arrow_back),
              label: Text(localizations.ui(AppStringKey.playlistBackAction)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme, String message) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistSummary(
    ThemeData theme,
    DownloadJobModel job, {
    VoidCallback? onShowDetails,
  }) {
    return DownloadJobCard(job: job, onShowDetails: onShowDetails);
  }

  Widget _buildEntriesSection(ThemeData theme, DownloadJobModel job) {
    final summary = job.playlist;
    final entries = summary?.entries ?? const <DownloadPlaylistEntry>[];
    final localizations = VidraLocalizations.of(context);
    final entriesTitle = localizations.ui(AppStringKey.playlistEntriesTitle);

    if (summary == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entriesTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                localizations.ui(AppStringKey.playlistEntriesPending),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      );
    }

    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entriesTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                localizations.ui(AppStringKey.playlistEntriesUnavailable),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      );
    }

    final failureState = _resolvePlaylistFailureState(job, summary);
    final totalEntries = entries.length;
    final totalPages = (totalEntries / _pageSize).ceil();
    final rawIndex = _pageIndex;
    final pageIndex = totalPages == 0 ? 0 : rawIndex.clamp(0, totalPages - 1);
    if (pageIndex != rawIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _pageIndex = pageIndex;
        });
      });
    }

    final start = totalEntries == 0 ? 0 : pageIndex * _pageSize;
    final visibleEntries = entries
        .skip(start)
        .take(_pageSize)
        .toList(growable: false);
    String rangeLabel;
    if (totalEntries == 0) {
      rangeLabel = localizations.ui(AppStringKey.homePaginationNoItems);
    } else if (visibleEntries.isEmpty) {
      rangeLabel = _formatTemplate(
        localizations.ui(AppStringKey.playlistDialogItemsTotal),
        {'count': '$totalEntries'},
      );
    } else {
      rangeLabel = _formatTemplate(
        localizations.ui(AppStringKey.homePaginationRangeLabel),
        {
          'start': '${start + 1}',
          'end': '${start + visibleEntries.length}',
          'total': '$totalEntries',
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entriesTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildEntriesPaginationControls(
          theme,
          localizations,
          rangeLabel,
          totalPages,
          pageIndex,
        ),
        const SizedBox(height: 12),
        if (failureState.hasAlerts)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlaylistFailureBanner(
              failedCount: failureState.failedCount,
              pendingRetryCount: failureState.pendingRetryCount,
              retryableCount: failureState.retryableIndices.length,
              latestError: failureState.latestError,
              isJobTerminal: job.isTerminal,
              onRetry:
                  job.isTerminal && failureState.retryableIndices.isNotEmpty
                  ? () => _retryPlaylistEntries(
                      job,
                      indices: failureState.retryableIndices,
                    )
                  : null,
              onViewDetails: () =>
                  Navigator.of(context).push(JobDetailScreen.route(job.id)),
              localizations: localizations,
            ),
          ),
        for (final entry in visibleEntries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _buildEntryCard(job, summary, entry, localizations),
          ),
        if (totalPages > 1) ...[
          const SizedBox(height: 16),
          _buildEntriesPaginationControls(
            theme,
            localizations,
            rangeLabel,
            totalPages,
            pageIndex,
          ),
        ],
      ],
    );
  }

  Widget _buildEntryCard(
    DownloadJobModel parentJob,
    DownloadPlaylistSummary summary,
    DownloadPlaylistEntry entry,
    VidraLocalizations localizations,
  ) {
    final entryJob = _buildEntryJobModel(parentJob, summary, entry);
    final entryLink = _resolveEntryLaunchUrl(entry, entryJob);
    final canRetrySingle = parentJob.isTerminal && entry.isFailed;
    return DownloadJobCard(
      job: entryJob,
      enableActions: true,
      showDefaultActions: false,
      leadingIndex: entry.index,
      hidePlatformAndKindMetadata: true,
      extraActions: [
        if (entryLink != null)
          DownloadJobCardAction(
            label: localizations.ui(AppStringKey.jobOpenLinkAction),
            icon: Icons.open_in_new,
            onSelected: () => _openEntryLink(entryLink),
          ),
        if (canRetrySingle)
          DownloadJobCardAction(
            label: localizations.ui(AppStringKey.playlistEntryRetryAction),
            icon: Icons.restart_alt_rounded,
            onSelected: () => _retryPlaylistEntries(
              parentJob,
              indices: entry.index != null && entry.index! > 0
                  ? <int>[entry.index!]
                  : null,
              entryIds: entry.id?.isNotEmpty == true
                  ? <String>[entry.id!]
                  : null,
            ),
          ),
        DownloadJobCardAction(
          label: localizations.ui(AppStringKey.jobDetailsAction),
          icon: Icons.info_outline,
          onSelected: () => _openEntryDetails(entryJob),
        ),
      ],
    );
  }

  Future<void> _retryPlaylistEntries(
    DownloadJobModel job, {
    Iterable<int>? indices,
    Iterable<String>? entryIds,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final localizations = VidraLocalizations.of(context);
    final success = await _controller.retryPlaylistEntries(
      job.id,
      indices: indices,
      entryIds: entryIds,
    );
    if (!mounted) {
      return;
    }
    final message = success
        ? localizations.ui(AppStringKey.jobRetryEntriesRequested)
        : (_controller.lastError ??
              localizations.ui(AppStringKey.jobRetryEntriesFailed));
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  _PlaylistFailureState _resolvePlaylistFailureState(
    DownloadJobModel job,
    DownloadPlaylistSummary summary,
  ) {
    final failed = _normalizeFailureIndices(
      summary.failedIndices ?? job.progress?.playlistFailedIndices,
    );
    final pending = _normalizeFailureIndices(
      summary.pendingRetryIndices ?? job.progress?.playlistPendingRetryIndices,
    );
    for (final error in summary.entryErrors) {
      if (error.index > 0) {
        failed.add(error.index);
      }
    }
    final retryable = failed.difference(pending).toList()..sort();
    DownloadPlaylistEntryError? latestError;
    if (summary.entryErrors.isNotEmpty) {
      latestError = summary.entryErrors.last;
    } else {
      final progressErrors = job.progress?.playlistEntryErrors;
      if (progressErrors != null && progressErrors.isNotEmpty) {
        latestError = progressErrors.last;
      }
    }
    return _PlaylistFailureState(
      failedIndices: failed,
      pendingRetryIndices: pending,
      retryableIndices: List<int>.unmodifiable(retryable),
      latestError: latestError,
    );
  }

  Set<int> _normalizeFailureIndices(List<int>? values) {
    if (values == null || values.isEmpty) {
      return <int>{};
    }
    final set = <int>{};
    for (final value in values) {
      if (value > 0) {
        set.add(value);
      }
    }
    return set;
  }

  Widget _buildEntriesPaginationControls(
    ThemeData theme,
    VidraLocalizations localizations,
    String rangeLabel,
    int totalPages,
    int pageIndex,
  ) {
    final textStyle = theme.textTheme.bodySmall;
    final hasMultiplePages = totalPages > 1;
    final pageStatus = _formatTemplate(
      localizations.ui(AppStringKey.homePaginationPageStatus),
      {'current': '${pageIndex + 1}', 'total': '$totalPages'},
    );
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              localizations.ui(AppStringKey.homePaginationShow),
              style: textStyle,
            ),
            const SizedBox(width: 8),
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _pageSize,
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
                    _changeEntriesPageSize(value);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              localizations.ui(AppStringKey.homePaginationPerPage),
              style: textStyle,
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(rangeLabel, style: textStyle),
            if (hasMultiplePages) ...[
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.first_page),
                tooltip: localizations.ui(AppStringKey.homePaginationFirst),
                onPressed: pageIndex > 0 ? () => _goToEntriesPage(0) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: localizations.ui(AppStringKey.homePaginationPrevious),
                onPressed: pageIndex > 0
                    ? () => _goToEntriesPage(pageIndex - 1)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(pageStatus, style: textStyle),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: localizations.ui(AppStringKey.homePaginationNext),
                onPressed: pageIndex < totalPages - 1
                    ? () => _goToEntriesPage(pageIndex + 1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                tooltip: localizations.ui(AppStringKey.homePaginationLast),
                onPressed: pageIndex < totalPages - 1
                    ? () => _goToEntriesPage(totalPages - 1)
                    : null,
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _formatTemplate(String template, Map<String, String> values) {
    return values.entries.fold<String>(
      template,
      (result, entry) => result.replaceAll('{${entry.key}}', entry.value),
    );
  }

  void _changeEntriesPageSize(int newSize) {
    setState(() {
      _pageSize = newSize;
      _pageIndex = 0;
    });
  }

  void _goToEntriesPage(int newPage) {
    setState(() {
      _pageIndex = newPage;
    });
  }

  Future<void> _openEntryDetails(DownloadJobModel entryJob) async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      JobDetailScreen.entryRoute(entryJob: entryJob, parentJobId: widget.jobId),
    );
  }

  DownloadJobModel _buildEntryJobModel(
    DownloadJobModel parentJob,
    DownloadPlaylistSummary summary,
    DownloadPlaylistEntry entry,
  ) {
    final status = _mapEntryStatus(entry);
    final progress = _buildEntryProgress(parentJob, entry, status);
    final metadata = _buildEntryMetadata(entry, parentJob);
    final urls = _buildEntryUrls(entry);
    final sanitizedEntryError = _sanitize(entry.error?.message);
    final fallbackErrorMessage =
        _sanitize(entry.progress?.message) ??
        _sanitize(entry.progressSnapshot?.message);
    final errorMessage =
        sanitizedEntryError ??
        ((status == DownloadStatus.failed ||
                status == DownloadStatus.completedWithErrors)
            ? fallbackErrorMessage
            : null);
    final generatedFiles = _deriveEntryGeneratedFiles(entry, progress, status);
    final entryMainFile = _sanitize(entry.mainFile);
    final fallbackFilename =
        _sanitize(entry.progress?.filename) ??
        _sanitize(entry.progressSnapshot?.filename);
    final mainFile =
        entryMainFile ??
        (generatedFiles.isNotEmpty ? generatedFiles.first : fallbackFilename);

    final entryId = entry.id?.isNotEmpty == true
        ? entry.id!
        : entry.index != null
        ? 'entry-${entry.index}'
        : 'entry-${summary.id ?? parentJob.id}-${metadata.hashCode}';

    final model = DownloadJobModel(
      id: '${parentJob.id}::$entryId',
      status: status,
      kind: DownloadKind.video,
      createdAt: parentJob.createdAt,
      startedAt: parentJob.startedAt,
      finishedAt:
          (status == DownloadStatus.completed ||
              status == DownloadStatus.completedWithErrors)
          ? parentJob.finishedAt
          : null,
      progress: progress,
      error: errorMessage,
      creator: parentJob.creator,
      urls: urls,
      options: const {},
      metadata: metadata,
      logs: const [],
      playlist: null,
      generatedFiles: generatedFiles,
      mainFile: mainFile,
    );

    final existing = _entryModelCache[model.id];
    final merged = existing != null ? existing.merge(model) : model;
    _entryModelCache[model.id] = merged;
    return merged;
  }

  Map<String, dynamic> _buildEntryMetadata(
    DownloadPlaylistEntry entry,
    DownloadJobModel parentJob,
  ) {
    final metadata = <String, dynamic>{
      'is_playlist': false,
      'parent_job_id': parentJob.id,
    };
    final preview = entry.preview;
    if (preview != null) {
      final previewMap = <String, dynamic>{};

      void writeValue(String key, Object? value) {
        if (value == null) {
          return;
        }
        if (value is String) {
          final trimmed = value.trim();
          if (trimmed.isEmpty) {
            return;
          }
          previewMap[key] = trimmed;
        } else {
          previewMap[key] = value;
        }
      }

      writeValue('title', preview.title);
      writeValue('description', preview.description);
      writeValue('thumbnail_url', preview.thumbnailUrl);
      writeValue('duration_text', preview.durationText);
      writeValue('uploader', preview.uploader);
      writeValue('channel', preview.channel);
      writeValue('webpage_url', preview.webpageUrl);
      writeValue('original_url', preview.originalUrl);
      if (preview.durationSeconds != null) {
        previewMap['duration_seconds'] = preview.durationSeconds;
      }
      if (preview.uploadDate != null) {
        previewMap['upload_date_iso'] = preview.uploadDate!.toIso8601String();
      }
      if (preview.viewCount != null) {
        previewMap['view_count'] = preview.viewCount;
      }
      if (preview.likeCount != null) {
        previewMap['like_count'] = preview.likeCount;
      }
      if (preview.thumbnails.isNotEmpty) {
        previewMap['thumbnails'] = preview.thumbnails
            .map(
              (thumb) => {
                'url': thumb.url,
                if (thumb.width != null) 'width': thumb.width,
                if (thumb.height != null) 'height': thumb.height,
                if (thumb.id != null) 'id': thumb.id,
              },
            )
            .toList(growable: false);
      }

      metadata['preview'] = previewMap;
      if (preview.title != null && preview.title!.isNotEmpty) {
        metadata['title'] = preview.title;
      }
      if (preview.description != null && preview.description!.isNotEmpty) {
        metadata['description'] = preview.description;
      }
      if (preview.thumbnailUrl != null && preview.thumbnailUrl!.isNotEmpty) {
        metadata['thumbnail_url'] = preview.thumbnailUrl;
      }
      if (preview.webpageUrl != null && preview.webpageUrl!.isNotEmpty) {
        metadata['webpage_url'] = preview.webpageUrl;
      }
      if (preview.originalUrl != null && preview.originalUrl!.isNotEmpty) {
        metadata['original_url'] = preview.originalUrl;
      }
    }

    if (entry.id != null && entry.id!.isNotEmpty) {
      metadata['entry_id'] = entry.id;
    }
    if (entry.index != null && entry.index! > 0) {
      metadata['playlist_index'] = entry.index;
    }

    if (!metadata.containsKey('title') && parentJob.preview?.title != null) {
      metadata['parent_title'] = parentJob.preview!.title;
    }

    return Map<String, dynamic>.unmodifiable(metadata);
  }

  List<String> _buildEntryUrls(DownloadPlaylistEntry entry) {
    final urls = <String>{};
    void add(String? value) {
      if (value == null) {
        return;
      }
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      urls.add(trimmed);
    }

    final preview = entry.preview;
    add(preview?.webpageUrl);
    add(preview?.originalUrl);
    if (entry.id != null && entry.id!.startsWith('http')) {
      add(entry.id);
    }
    return urls.toList(growable: false);
  }

  DownloadProgress _buildEntryProgress(
    DownloadJobModel parentJob,
    DownloadPlaylistEntry entry,
    DownloadStatus status,
  ) {
    final base = entry.isCurrent && parentJob.progress != null
        ? parentJob.progress
        : entry.progress ?? entry.progressSnapshot;
    final snapshot = entry.progressSnapshot;

    final percent =
        base?.percent ??
        base?.stagePercent ??
        snapshot?.percent ??
        snapshot?.stagePercent ??
        ((status == DownloadStatus.completed ||
                status == DownloadStatus.completedWithErrors)
            ? 100.0
            : null);
    final stagePercent =
        base?.stagePercent ?? snapshot?.stagePercent ?? percent;
    final statusText =
        base?.status ??
        snapshot?.status ??
        entry.status ??
        _statusStringFromEnum(status);
    final stageText =
        base?.stage ??
        snapshot?.stage ??
        entry.status ??
        _defaultStageForStatus(status);
    final message = entry.isCurrent
        ? (_sanitize(base?.message) ?? _sanitize(parentJob.progress?.message))
        : _sanitize(base?.message ?? snapshot?.message);

    return DownloadProgress(
      status: statusText,
      stage: stageText,
      downloadedBytes: base?.downloadedBytes ?? snapshot?.downloadedBytes,
      totalBytes: base?.totalBytes ?? snapshot?.totalBytes,
      speed: base?.speed ?? snapshot?.speed,
      eta: base?.eta ?? snapshot?.eta,
      elapsed: base?.elapsed ?? snapshot?.elapsed,
      filename: base?.filename,
      tmpFilename: base?.tmpFilename,
      percent: percent,
      stagePercent: stagePercent,
      postprocessor: base?.postprocessor,
      currentItem: base?.currentItem,
      totalItems: base?.totalItems,
      message: message,
    );
  }

  List<String> _deriveEntryGeneratedFiles(
    DownloadPlaylistEntry entry,
    DownloadProgress progress,
    DownloadStatus status,
  ) {
    if (status != DownloadStatus.completed &&
        status != DownloadStatus.completedWithErrors) {
      return const <String>[];
    }
    final candidates = <String>[];
    void add(String? value) {
      if (value == null) {
        return;
      }
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (!candidates.contains(trimmed)) {
        candidates.add(trimmed);
      }
    }

    add(entry.mainFile);
    add(progress.filename);
    add(entry.progress?.filename);
    add(entry.progressSnapshot?.filename);

    if (candidates.isEmpty) {
      return const <String>[];
    }
    return List<String>.unmodifiable(candidates);
  }

  DownloadStatus _mapEntryStatus(DownloadPlaylistEntry entry) {
    final raw = entry.status?.toLowerCase().trim();
    if (raw == 'completed_with_errors' || raw == 'finished_with_errors') {
      return DownloadStatus.completedWithErrors;
    }
    if (entry.isCompleted) {
      return DownloadStatus.completed;
    }
    if (entry.isCurrent) {
      if (raw == 'paused') {
        return DownloadStatus.paused;
      }
      if (raw == 'pausing') {
        return DownloadStatus.pausing;
      }
      return DownloadStatus.running;
    }
    switch (raw) {
      case 'completed':
      case 'finished':
        return DownloadStatus.completed;
      case 'running':
      case 'active':
      case 'downloading':
      case 'processing':
      case 'postprocessing':
        return DownloadStatus.running;
      case 'starting':
      case 'initializing':
        return DownloadStatus.starting;
      case 'retrying':
      case 'restarting':
        return DownloadStatus.retrying;
      case 'paused':
        return DownloadStatus.paused;
      case 'pausing':
        return DownloadStatus.pausing;
      case 'queued':
      case 'pending':
      case 'waiting':
      case 'queued_for_processing':
        return DownloadStatus.queued;
      case 'cancelling':
        return DownloadStatus.cancelling;
      case 'cancelled':
      case 'canceled':
        return DownloadStatus.cancelled;
      case 'failed':
      case 'error':
        return DownloadStatus.failed;
      case 'completed_with_errors':
      case 'completed_with_error':
      case 'finished_with_errors':
      case 'finished_with_error':
        return DownloadStatus.completedWithErrors;
      case 'skipped':
        return DownloadStatus.completed;
      default:
        return DownloadStatus.unknown;
    }
  }

  String _statusStringFromEnum(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.queued:
        return 'queued';
      case DownloadStatus.running:
        return 'downloading';
      case DownloadStatus.pausing:
        return 'pausing';
      case DownloadStatus.paused:
        return 'paused';
      case DownloadStatus.cancelling:
        return 'cancelling';
      case DownloadStatus.starting:
        return 'starting';
      case DownloadStatus.retrying:
        return 'retrying';
      case DownloadStatus.completed:
        return 'finished';
      case DownloadStatus.completedWithErrors:
        return 'finished_with_errors';
      case DownloadStatus.failed:
        return 'error';
      case DownloadStatus.cancelled:
        return 'cancelled';
      case DownloadStatus.unknown:
        return 'unknown';
    }
  }

  String _defaultStageForStatus(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.queued:
        return 'queued';
      case DownloadStatus.running:
        return 'downloading';
      case DownloadStatus.pausing:
        return 'pausing';
      case DownloadStatus.paused:
        return 'paused';
      case DownloadStatus.cancelling:
        return 'cancelling';
      case DownloadStatus.starting:
        return 'starting';
      case DownloadStatus.retrying:
        return 'retrying';
      case DownloadStatus.completed:
        return 'completed';
      case DownloadStatus.completedWithErrors:
        return 'completed_with_errors';
      case DownloadStatus.failed:
        return 'error';
      case DownloadStatus.cancelled:
        return 'cancelled';
      case DownloadStatus.unknown:
        return 'unknown';
    }
  }

  String? _sanitize(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _navigateBackToHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _openEntryLink(String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final localizations = VidraLocalizations.of(context);
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(localizations.ui(AppStringKey.jobLinkUnavailable)),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty) {
      messenger?.showSnackBar(
        SnackBar(content: Text(localizations.ui(AppStringKey.jobLinkInvalid))),
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) {
      return;
    }
    if (!launched) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(localizations.ui(AppStringKey.jobLinkOpenFailed)),
        ),
      );
    }
  }

  String? _resolveEntryLaunchUrl(
    DownloadPlaylistEntry entry,
    DownloadJobModel entryJob,
  ) {
    String? sanitize(String? value) {
      if (value == null) {
        return null;
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final preview = entry.preview;
    final metadataUrl = entryJob.metadata['webpage_url'];
    final candidate =
        sanitize(preview?.webpageUrl) ??
        sanitize(preview?.originalUrl) ??
        (entryJob.urls.isNotEmpty ? sanitize(entryJob.urls.first) : null) ??
        (metadataUrl is String ? sanitize(metadataUrl) : null);
    if (candidate == null) {
      return null;
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.scheme.isEmpty) {
      return null;
    }
    return candidate;
  }
}

class _PlaylistFailureState {
  const _PlaylistFailureState({
    required this.failedIndices,
    required this.pendingRetryIndices,
    required this.retryableIndices,
    this.latestError,
  });

  bool get hasAlerts =>
      failedIndices.isNotEmpty || pendingRetryIndices.isNotEmpty;
  int get failedCount => failedIndices.length;
  int get pendingRetryCount => pendingRetryIndices.length;

  final Set<int> failedIndices;
  final Set<int> pendingRetryIndices;
  final List<int> retryableIndices;
  final DownloadPlaylistEntryError? latestError;
}
