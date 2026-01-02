import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImage;
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/ui/theme/download_visuals.dart';
import 'package:vidra/utils/download_formatters.dart';

class DownloadJobCardAction {
  const DownloadJobCardAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final FutureOr<void> Function() onSelected;
  final bool destructive;
}

class DownloadJobCard extends StatelessWidget {
  const DownloadJobCard({
    super.key,
    required this.job,
    this.onTap,
    this.onShowDetails,
    this.enableActions = true,
    this.showDefaultActions = true,
    this.enableOpenDestinationAction = true,
    this.leadingIndex,
    this.hidePlatformAndKindMetadata = false,
    this.onPlaylistSelectionRequested,
    this.extraActions = const <DownloadJobCardAction>[],
  });

  final DownloadJobModel job;
  final VoidCallback? onTap;
  final VoidCallback? onShowDetails;
  final bool enableActions;
  final bool showDefaultActions;
  final bool enableOpenDestinationAction;
  final int? leadingIndex;
  final bool hidePlatformAndKindMetadata;
  final ValueChanged<String>? onPlaylistSelectionRequested;
  final List<DownloadJobCardAction> extraActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final controller = context.read<DownloadController>();
    final status = _resolveStatusAppearance(job.status, theme, localizations);
    final preview = job.preview;
    final primaryUrl =
        preview?.webpageUrl ??
        preview?.originalUrl ??
        (job.urls.isNotEmpty ? job.urls.first : job.id);
    final title = (preview?.title?.trim().isNotEmpty ?? false)
        ? preview!.title!.trim()
        : primaryUrl;
    final subtitleParts = <String>[];
    final uploadDate = preview?.uploadDate;

    final durationLabel = _durationLabel(preview);

    final progress = job.progress;
    final playlist = job.playlist;
    final hasPartialProgress =
        progress != null &&
        (((progress.downloadedBytes ?? 0) > 0) ||
            ((progress.percent ?? progress.stagePercent ?? 0) > 0));
    final playlistTotalItems =
        playlist?.totalItems ??
        playlist?.entryCount ??
        progress?.playlistTotalItems ??
        progress?.playlistCount;
    final playlistCompletedItems =
        playlist?.completedItems ?? progress?.playlistCompletedItems;
    final playlistPendingItems =
        playlist?.pendingItems ?? progress?.playlistPendingItems;
    final rawPlaylistCurrentIndex =
        playlist?.currentIndex ??
        progress?.playlistCurrentIndex ??
        progress?.playlistIndex;
    final playlistCurrentIndex =
        rawPlaylistCurrentIndex != null && rawPlaylistCurrentIndex > 0
        ? rawPlaylistCurrentIndex
        : null;
    double? playlistPercentValue =
        playlist?.percent ?? progress?.playlistPercent;
    if (playlistPercentValue == null &&
        playlistTotalItems != null &&
        playlistCompletedItems != null &&
        playlistTotalItems > 0) {
      playlistPercentValue =
          (playlistCompletedItems / playlistTotalItems) * 100;
    }

    final hasPlaylistProgress =
        job.isPlaylist &&
        (playlistTotalItems != null ||
            playlistCompletedItems != null ||
            playlistPendingItems != null ||
            playlistPercentValue != null ||
            playlistCurrentIndex != null);

    Map<String, dynamic>? playlistMetadata;
    final playlistMetadataRaw = job.metadata['playlist'];
    if (playlistMetadataRaw is Map<String, dynamic>) {
      playlistMetadata = playlistMetadataRaw;
    } else if (playlistMetadataRaw is Map) {
      try {
        playlistMetadata = playlistMetadataRaw.cast<String, dynamic>();
      } catch (_) {
        playlistMetadata = null;
      }
    }

    final requiresPlaylistSelection = _jobRequiresPlaylistSelection(
      job,
      playlistMetadata,
    );

    final String? playlistCollectionError = _resolvePlaylistCollectionError(
      playlistMetadata,
      job,
    );
    final bool isCollectingPlaylistEntries = _isPlaylistCollecting(
      metadata: playlistMetadata,
      summary: playlist,
      progress: progress,
      collectionError: playlistCollectionError,
    );
    final bool hasPlaylistCollectionError = playlistCollectionError != null;
    final bool isAwaitingSelection =
        !hasPlaylistCollectionError &&
        (requiresPlaylistSelection || isCollectingPlaylistEntries);
    final bool canTapCard = job.isPlaylist && !isAwaitingSelection;
    final VoidCallback? effectiveOnTap = canTapCard ? onTap : null;
    final VoidCallback? failureDetailsAction = onShowDetails ?? effectiveOnTap;
    final bool showPlaylistSelectionBanner =
        job.isPlaylist &&
        (hasPlaylistCollectionError || requiresPlaylistSelection);

    final messenger = ScaffoldMessenger.maybeOf(context);
    final normalizedMainFile = job.mainFile?.trim();
    final primaryOutputPath =
        (normalizedMainFile != null && normalizedMainFile.isNotEmpty)
        ? normalizedMainFile
        : null;
    const IconData openActionIcon = Icons.play_circle_outline;

    String localized(String key, [Map<String, String>? values]) {
      final template = localizations.ui(key);
      if (values == null || values.isEmpty) {
        return template;
      }
      return values.entries.fold<String>(
        template,
        (result, entry) => result.replaceAll('{${entry.key}}', entry.value),
      );
    }

    void showSnack(String message) {
      if (messenger == null) {
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

    Future<void> handleOpenLink() async {
      if (primaryUrl.isEmpty) {
        showSnack(localized(AppStringKey.jobLinkUnavailable));
        return;
      }
      final uri = Uri.tryParse(primaryUrl);
      if (uri == null) {
        showSnack(localized(AppStringKey.jobLinkInvalid));
        return;
      }
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        showSnack(localized(AppStringKey.jobLinkOpenFailed));
      }
    }

    String? sanitizeText(String? value) {
      if (value == null) {
        return null;
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    String? metadataValue(String key) {
      final value = job.metadata[key];
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      return null;
    }

    Set<int> normalizeIndices(List<int>? values) {
      if (values == null || values.isEmpty) {
        return <int>{};
      }
      final normalized = <int>{};
      for (final value in values) {
        if (value > 0) {
          normalized.add(value);
        }
      }
      return normalized;
    }

    List<DownloadPlaylistEntryError> resolveEntryErrors() {
      if (playlist != null && playlist.entryErrors.isNotEmpty) {
        return playlist.entryErrors;
      }
      return job.progress?.playlistEntryErrors ??
          const <DownloadPlaylistEntryError>[];
    }

    String? formatPlatformLabel(String? value) {
      final sanitized = sanitizeText(value);
      if (sanitized == null) {
        return null;
      }
      final primary = sanitized.split(':').first.trim();
      if (primary.isEmpty) {
        return null;
      }
      final normalized = primary.replaceAll(RegExp(r'[_\-]+'), ' ');
      final words = normalized
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .map((word) {
            final lowerWord = word.toLowerCase();
            if (lowerWord.length == 1) {
              return lowerWord.toUpperCase();
            }
            return '${lowerWord[0].toUpperCase()}${lowerWord.substring(1)}';
          })
          .toList();
      if (words.isEmpty) {
        return null;
      }
      return words.join(' ');
    }

    final authorLabel =
        sanitizeText(preview?.channel) ??
        sanitizeText(preview?.uploader) ??
        sanitizeText(playlist?.channel) ??
        sanitizeText(playlist?.uploader);

    final platformLabel =
        formatPlatformLabel(preview?.extractor) ??
        formatPlatformLabel(preview?.extractorId) ??
        formatPlatformLabel(metadataValue('extractor')) ??
        formatPlatformLabel(metadataValue('extractor_id')) ??
        formatPlatformLabel(metadataValue('extractor_key'));

    DateTime resolvedDate = job.createdAt;
    if (uploadDate != null) {
      resolvedDate = uploadDate;
    } else if (job.startedAt != null) {
      resolvedDate = job.startedAt!;
    } else if (job.finishedAt != null) {
      resolvedDate = job.finishedAt!;
    }
    final String dateLabel = MaterialLocalizations.of(
      context,
    ).formatMediumDate(resolvedDate.toLocal());

    String? kindLabel;
    if (job.kind == DownloadKind.playlist) {
      kindLabel = localized(AppStringKey.jobKindPlaylist);
    } else if (job.kind == DownloadKind.video) {
      kindLabel = localized(AppStringKey.jobKindVideo);
    }

    final metadataLabels = <String>[
      if (!hidePlatformAndKindMetadata && platformLabel != null) platformLabel,
      if (!hidePlatformAndKindMetadata && kindLabel != null) kindLabel,
      if (authorLabel != null) authorLabel,
      dateLabel,
      if (durationLabel != null) durationLabel,
      if (job.isPlaylist && playlistTotalItems != null)
        localized(AppStringKey.jobPlaylistItemCount, {
          'count': '$playlistTotalItems',
        }),
    ];
    final metadataLine = metadataLabels
        .where((label) => label.isNotEmpty)
        .join(' • ');
    final hasMetadataLine = metadataLine.isNotEmpty;

    final entryErrors = resolveEntryErrors();
    final failedIndexSet = normalizeIndices(
      playlist?.failedIndices ?? job.progress?.playlistFailedIndices,
    );
    for (final error in entryErrors) {
      if (error.index > 0) {
        failedIndexSet.add(error.index);
      }
    }
    final pendingRetrySet = normalizeIndices(
      playlist?.pendingRetryIndices ??
          job.progress?.playlistPendingRetryIndices,
    );
    final retryableIndices = failedIndexSet.difference(pendingRetrySet);
    final bool hasPlaylistAlerts =
        failedIndexSet.isNotEmpty || pendingRetrySet.isNotEmpty;
    final latestEntryError = entryErrors.isNotEmpty ? entryErrors.last : null;
    final bool canRetryPlaylistEntries =
        enableActions && job.isTerminal && retryableIndices.isNotEmpty;
    final bool showPlaylistFailureBanner = job.isPlaylist && hasPlaylistAlerts;

    String? progressSummaryLabel;
    final double? directPercent = progress?.percent ?? progress?.stagePercent;
    final double? resolvedPercent = directPercent ?? playlistPercentValue;
    if (resolvedPercent != null) {
      final normalized = resolvedPercent.clamp(0, 100);
      final isInt = normalized.truncateToDouble() == normalized;
      final percentText = isInt
          ? normalized.toInt().toString()
          : normalized.toStringAsFixed(1);
      progressSummaryLabel = localized(AppStringKey.jobProgressPercent, {
        'percent': percentText,
      });
    }
    String? playlistSummaryLabel;
    if (job.isPlaylist) {
      final totalItems = playlistTotalItems ?? playlist?.entryCount;
      final completedItems = playlistCompletedItems;
      if (totalItems != null && completedItems != null) {
        playlistSummaryLabel =
            localized(
          AppStringKey.jobPlaylistSummaryCounts,
          {'completed': '$completedItems', 'total': '$totalItems'},
        );
      } else if (playlistPercentValue != null) {
        playlistSummaryLabel =
            localized(
          AppStringKey.jobPlaylistSummaryPercent,
          {'percent': playlistPercentValue.toStringAsFixed(0)},
        );
      }
    }
    final errorLabel = (job.error?.trim().isNotEmpty ?? false)
        ? job.error!.trim()
        : null;
    final semanticsLabel = _buildJobCardSemanticsLabel(
      localizations: localizations,
      title: title,
      statusLabel: status.label,
      progressLabel: progressSummaryLabel,
      playlistLabel: playlistSummaryLabel,
      requiresSelection:
          !hasPlaylistCollectionError && requiresPlaylistSelection,
      errorMessage: errorLabel,
    );

    String? formatErrorMessage(Object? error) {
      if (error == null) {
        return null;
      }
      final text = error.toString().trim();
      if (text.isEmpty) {
        return null;
      }
      String candidate = text;
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start != -1 && end > start) {
        candidate = text.substring(start, end + 1);
      }
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          final message = decoded['error'] ?? decoded['detail'];
          if (message is String && message.trim().isNotEmpty) {
            return message.trim();
          }
        }
      } catch (_) {
        // fall back to raw text
      }
      return text;
    }

    Future<void> performAction({
      required Future<bool> Function() action,
      required String successMessage,
      required String failureMessage,
    }) async {
      final result = await action();
      final message = result
          ? successMessage
          : (formatErrorMessage(controller.lastError) ?? failureMessage);
      showSnack(message);
    }

    Future<bool> openDestination() async {
      final target = primaryOutputPath;
      if (target == null || target.isEmpty) {
        return false;
      }
      final result = await OpenFile.open(target);
      return result.type == ResultType.done;
    }

    Future<void> promptPlaylistSelection() async {
      if (playlistCollectionError != null) {
        showSnack(playlistCollectionError);
        return;
      }
      onPlaylistSelectionRequested?.call(job.id);
      controller.requeuePlaylistSelection(job.id);
      if (isCollectingPlaylistEntries) {
        showSnack(
          localized(AppStringKey.jobPlaylistOpeningSelection),
        );
        return;
      }
      showSnack(localized(AppStringKey.jobPlaylistSelectItemsPrompt));
    }

    final isRunning = job.status == DownloadStatus.running;
    final isPausing = job.status == DownloadStatus.pausing;
    final isPaused = job.status == DownloadStatus.paused;
    final isQueued = job.status == DownloadStatus.queued;
    final isStarting = job.status == DownloadStatus.starting;
    final isCancelling = job.status == DownloadStatus.cancelling;
    final isFailed = job.status == DownloadStatus.failed;
    final isCompletedWithErrors =
        job.status == DownloadStatus.completedWithErrors;
    final isCompleted =
        job.status == DownloadStatus.completed || isCompletedWithErrors;
    final isCancelled = job.status == DownloadStatus.cancelled;
    final hasErrors = isFailed || isCompletedWithErrors;
    final jobActions = <_JobAction>[];
    if (enableActions && showDefaultActions) {
      if (onShowDetails != null) {
        jobActions.add(
          _JobAction(
            label: localized(AppStringKey.jobDetailsAction),
            icon: Icons.info_outline,
            onSelected: () async {
              onShowDetails?.call();
            },
          ),
        );
      }
      if (requiresPlaylistSelection && !hasPlaylistCollectionError) {
        jobActions.add(
          _JobAction(
            label: localized(AppStringKey.jobSelectItemsAction),
            icon: Icons.playlist_add_check_circle,
            onSelected: () async {
              await promptPlaylistSelection();
            },
          ),
        );
      }
      if ((isRunning || isPausing) && !isPausing) {
        jobActions.add(
          _JobAction(
            label: localized(AppStringKey.jobPauseAction),
            icon: Icons.pause_circle_outline,
            onSelected: () => performAction(
              action: () => controller.pauseJob(job.id),
              successMessage: localized(AppStringKey.jobPauseRequested),
              failureMessage: localized(AppStringKey.jobPauseFailed),
            ),
          ),
        );
      }

      if (isPaused) {
        jobActions.add(
          _JobAction(
            label: localized(AppStringKey.jobResumeAction),
            icon: Icons.play_arrow_rounded,
            onSelected: () => performAction(
              action: () => controller.resumeJob(job.id),
              successMessage: localized(AppStringKey.jobResumeSuccess),
              failureMessage: localized(AppStringKey.jobResumeFailed),
            ),
          ),
        );
      }

      if (isFailed && hasPartialProgress) {
        jobActions.add(
          _JobAction(
            label: localized(AppStringKey.jobContinueDownloadAction),
            icon: Icons.play_circle_outline,
            onSelected: () => performAction(
              action: () => controller.resumeJob(job.id),
              successMessage: localized(AppStringKey.jobContinueRequested),
              failureMessage: localized(AppStringKey.jobContinueFailed),
            ),
          ),
        );
      }

      if (isFailed || isCancelled || isCompletedWithErrors) {
        jobActions.add(
          _JobAction(
            label: localized(AppStringKey.jobRetryAction),
            icon: Icons.restart_alt_rounded,
            onSelected: () => performAction(
              action: () => controller.retryJob(job.id),
              successMessage: localized(AppStringKey.jobRetryRequested),
              failureMessage: localized(AppStringKey.jobRetryFailed),
            ),
          ),
        );
      }

      if (job.isPlaylist && canRetryPlaylistEntries) {
        jobActions.add(
          _JobAction(
            label: localized(AppStringKey.jobRetryEntriesAction),
            icon: Icons.restart_alt_outlined,
            onSelected: () => performAction(
              action: () => controller.retryAllFailedPlaylistEntries(job.id),
              successMessage: localized(AppStringKey.jobRetryEntriesRequested),
              failureMessage: localized(AppStringKey.jobRetryEntriesFailed),
            ),
          ),
        );
      }

      final canCancel =
          isRunning ||
          isQueued ||
          isStarting ||
          isPausing ||
          isPaused ||
          isCancelling;
      if (canCancel && !isCancelling) {
        jobActions.add(
          _JobAction(
            label: localized(AppStringKey.jobCancelAction),
            icon: Icons.stop_circle_outlined,
            onSelected: () => performAction(
              action: () => controller.cancelJob(job.id),
              successMessage: localized(AppStringKey.jobCancelRequested),
              failureMessage: localized(AppStringKey.jobCancelFailed),
            ),
            destructive: true,
          ),
        );
      }

      final canDelete = isCompleted || isCancelled || isFailed;
      if (canDelete) {
        jobActions.add(
          _JobAction(
            label: localized(AppStringKey.jobDeleteAction),
            icon: Icons.delete_forever_outlined,
            onSelected: () => performAction(
              action: () => controller.deleteJob(job.id),
              successMessage: localized(AppStringKey.jobDeleteSuccess),
              failureMessage: localized(AppStringKey.jobDeleteFailed),
            ),
            destructive: true,
          ),
        );
      }

      if (primaryUrl.isNotEmpty) {
        jobActions.add(
          _JobAction(
            label: localized(AppStringKey.jobOpenLinkAction),
            icon: Icons.open_in_new,
            onSelected: () => handleOpenLink(),
          ),
        );
      }
    }

    if (enableActions && extraActions.isNotEmpty) {
      for (final action in extraActions) {
        jobActions.add(
          _JobAction(
            label: action.label,
            icon: action.icon,
            destructive: action.destructive,
            onSelected: () async {
              final FutureOr<void> result = action.onSelected();
              if (result is Future<void>) {
                await result;
              }
            },
          ),
        );
      }
    }

    if (enableActions &&
        enableOpenDestinationAction &&
        isCompleted &&
        primaryOutputPath != null) {
      jobActions.add(
        _JobAction(
          label: localized(AppStringKey.jobOpenFileAction),
          icon: openActionIcon,
          onSelected: () => performAction(
            action: () => openDestination(),
            successMessage: localized(AppStringKey.jobOpenFileSuccess),
            failureMessage: localized(AppStringKey.jobOpenFileFailed),
          ),
        ),
      );
    }

    final showProgress =
        (progress != null &&
            (((progress.downloadedBytes ?? 0) > 0) ||
                ((progress.totalBytes ?? 0) > 0) ||
                ((progress.percent ?? progress.stagePercent ?? 0) > 0))) ||
        isRunning ||
        isPausing ||
        isPaused ||
        isCancelling ||
        isQueued ||
        isFailed;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 560;
        final hasPreview =
            preview != null &&
            ((preview.title?.trim().isNotEmpty ?? false) ||
                (preview.description?.trim().isNotEmpty ?? false) ||
                (preview.bestThumbnailUrl?.isNotEmpty ?? false));
        final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
        );
        final skeletonColor = theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.6);

        Widget buildStatusIconWidget() {
          final Color iconColor = status.iconColor;
          final Color backgroundColor = status.iconBackgroundColor;
          return Tooltip(
            message: status.label,
            child: Semantics(
              label: status.label,
              container: true,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(status.icon, size: 18, color: iconColor),
              ),
            ),
          );
        }

        Widget buildTrailingControls() {
          final statusIcon = buildStatusIconWidget();
          if (jobActions.isEmpty) {
            return statusIcon;
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PopupMenuButton<_JobAction>(
                tooltip: localized(AppStringKey.jobActionsMenuTooltip),
                icon: const Icon(Icons.more_vert),
                onSelected: (action) => unawaited(action.onSelected()),
                itemBuilder: (context) {
                  final destructiveColor = theme.colorScheme.error;
                  final baseColor = theme.colorScheme.onSurfaceVariant;
                  return [
                    for (final action in jobActions)
                      PopupMenuItem<_JobAction>(
                        value: action,
                        child: Row(
                          children: [
                            Icon(
                              action.icon,
                              size: 18,
                              color: action.destructive
                                  ? destructiveColor
                                  : baseColor,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              action.label,
                              style: action.destructive
                                  ? TextStyle(color: destructiveColor)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                  ];
                },
              ),
              const SizedBox(width: 6),
              statusIcon,
            ],
          );
        }

        Widget buildLoadedHeader() {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        style: subtitleStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (hasMetadataLine)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          metadataLine,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.72),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: isCompact ? 6 : 10),
              buildTrailingControls(),
            ],
          );
        }

        Widget buildSkeletonHeader() {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonLine(
                      color: skeletonColor,
                      height: 22,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(height: 6),
                    _SkeletonLine(
                      color: skeletonColor,
                      widthFactor: 0.55,
                      height: 14,
                    ),
                    const SizedBox(height: 8),
                    _SkeletonLine(color: skeletonColor, height: 14),
                    if (hasMetadataLine)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          metadataLine,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.72),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: isCompact ? 6 : 10),
              buildTrailingControls(),
            ],
          );
        }

        Widget header;
        if (hasPreview) {
          header = buildLoadedHeader();
        } else {
          header = buildSkeletonHeader();
        }

        Widget buildImageSlot() {
          Widget base;
          if (!hasPreview) {
            base = _SkeletonImage(color: skeletonColor, isCompact: isCompact);
          } else {
            final imageUrl = preview.bestThumbnailUrl;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              base = _PreviewImage(imageUrl: imageUrl, isCompact: isCompact);
            } else {
              base = _ImagePlaceholderIcon(isCompact: isCompact);
            }
          }
          final indexValue = leadingIndex;
          if (indexValue != null && indexValue > 0) {
            base = Stack(
              clipBehavior: Clip.none,
              children: [
                base,
                Positioned(
                  top: isCompact ? -10 : -12,
                  left: isCompact ? -10 : -14,
                  child: _IndexBadge(index: indexValue, compact: isCompact),
                ),
              ],
            );
          }
          return base;
        }

        final bool showImage = !isCompact;
        final Widget? imageSlot = showImage ? buildImageSlot() : null;

        final Widget topContent;
        if (imageSlot != null) {
          topContent = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              imageSlot,
              const SizedBox(width: 12),
              Expanded(child: header),
            ],
          );
        } else {
          topContent = header;
        }

        final hasProgressData = progress != null;
        final displayPrimaryProgress =
            hasProgressData && (!job.isPlaylist || !hasPlaylistProgress);
        final displayPendingProgress =
            !hasProgressData &&
            showProgress &&
            (!job.isPlaylist || !hasPlaylistProgress);

        final bool shouldShowError =
            (hasErrors || isCancelled) &&
            (job.error != null && job.error!.isNotEmpty);

        final bodyChildren = <Widget>[
          topContent,
          if (showPlaylistSelectionBanner)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _PlaylistSelectionBanner(
                isCollecting:
                    !hasPlaylistCollectionError && isCollectingPlaylistEntries,
                collectionError: playlistCollectionError,
                onPressed: (!hasPlaylistCollectionError && enableActions)
                    ? () => unawaited(promptPlaylistSelection())
                    : null,
              ),
            ),
          if (displayPrimaryProgress) ...[
            _ProgressIndicator(
              progress: job.progress!,
              jobStatus: job.status,
              stateAppearance: status,
            ),
          ] else if (displayPendingProgress) ...[
            _PendingProgressIndicator(statusAppearance: status),
          ],
          if (hasPlaylistProgress) ...[
            _PlaylistSummary(
              job: job,
              progress: job.progress,
              playlist: playlist,
              stateAppearance: status,
              totalItems: playlistTotalItems,
              completedItems: playlistCompletedItems,
              pendingItems: playlistPendingItems,
              percent: playlistPercentValue,
              currentIndex: playlistCurrentIndex,
            ),
          ],
          if (showPlaylistFailureBanner)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: PlaylistFailureBanner(
                failedCount: failedIndexSet.length,
                pendingRetryCount: pendingRetrySet.length,
                retryableCount: retryableIndices.length,
                latestError: latestEntryError,
                isJobTerminal: job.isTerminal,
                onRetry: canRetryPlaylistEntries
                    ? () => performAction(
                        action: () =>
                            controller.retryAllFailedPlaylistEntries(job.id),
                        successMessage: localized(
                          AppStringKey.jobRetryEntriesRequested,
                        ),
                        failureMessage: localized(
                          AppStringKey.jobRetryEntriesFailed,
                        ),
                      )
                    : null,
                onViewDetails: failureDetailsAction,
                localizations: localizations,
              ),
            ),
          if (shouldShowError) ...[
            const SizedBox(height: 10),
            Text(
              job.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ];

        final card = Card(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          color: status.cardColor,
          surfaceTintColor: Colors.transparent,
          child: InkWell(
            onTap: effectiveOnTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 12 : 16,
                vertical: isCompact ? 10 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: bodyChildren,
              ),
            ),
          ),
        );

        return MergeSemantics(
          child: Semantics(
            key: ValueKey('job-card-semantics-${job.id}'),
            container: true,
            button: effectiveOnTap != null,
            enabled: effectiveOnTap != null,
            label: semanticsLabel.isEmpty ? title : semanticsLabel,
            onTapHint: effectiveOnTap != null
                ? localized(AppStringKey.jobCardOpenDetailsHint)
                : null,
            child: card,
          ),
        );
      },
    );
  }

  _StatusAppearance _resolveStatusAppearance(
    DownloadStatus status,
    ThemeData theme,
    VidraLocalizations localizations,
  ) {
    final visuals = DownloadVisualPalette.resolveState(status, theme);
    return _StatusAppearance(
      label: localizations.ui(visuals.labelKey),
      icon: visuals.icon,
      progressColor: visuals.progressColor,
      cardColor: visuals.cardColor,
      iconColor: visuals.iconColor,
      iconBackgroundColor: visuals.iconBackgroundColor,
    );
  }
}

String _buildJobCardSemanticsLabel({
  required VidraLocalizations localizations,
  required String title,
  required String statusLabel,
  String? progressLabel,
  String? playlistLabel,
  bool requiresSelection = false,
  String? errorMessage,
}) {
  String localized(String key, [Map<String, String>? values]) {
    final template = localizations.ui(key);
    if (values == null || values.isEmpty) {
      return template;
    }
    return values.entries.fold<String>(
      template,
      (result, entry) => result.replaceAll('{${entry.key}}', entry.value),
    );
  }

  final parts = <String>[
    title,
    localized(AppStringKey.jobCardSemanticsStatus, {'status': statusLabel}),
  ];
  if (progressLabel != null && progressLabel.isNotEmpty) {
    parts.add(
      localized(AppStringKey.jobCardSemanticsProgress, {
        'progress': progressLabel,
      }),
    );
  }
  if (playlistLabel != null && playlistLabel.isNotEmpty) {
    parts.add(playlistLabel);
  }
  if (requiresSelection) {
    parts.add(localized(AppStringKey.jobCardSemanticsRequireSelection));
  }
  if (errorMessage != null && errorMessage.isNotEmpty) {
    parts.add(
      localized(AppStringKey.jobCardSemanticsError, {'message': errorMessage}),
    );
  }
  return parts.join('. ').trim();
}

class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({
    required this.progress,
    required this.jobStatus,
    required this.stateAppearance,
  });

  final DownloadProgress progress;
  final DownloadStatus jobStatus;
  final _StatusAppearance stateAppearance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final isError =
        jobStatus == DownloadStatus.failed ||
        jobStatus == DownloadStatus.completedWithErrors;
    final isCompleted = jobStatus == DownloadStatus.completed && !isError;
    final accentBase = stateAppearance.progressColor;
    final accent = isError ? theme.colorScheme.error : accentBase;
    final indicatorValue = _computeIndicatorValue();
    final metricsPalette = DownloadVisualPalette.metricColors;
    final metrics = _buildMetrics(metricsPalette);
    final metricsStyle = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final stageTitleCandidate = formatStageName(progress.stageName);
    final stageLabel =
        stageTitleCandidate ??
        describeStage(
          progress.stage,
          progress.postprocessor,
          progress.preprocessor,
          lookup: localizations.ui,
        ) ??
        describeStatus(progress.status, localizations.ui);
    final message = sanitizeMessage(progress.message);
    final stageLine = (!isCompleted || isError)
        ? composeStageLine(stageLabel, message)
        : null;
    final stageColorCandidate = DownloadVisualPalette.stageColor(
      progress.stage,
      status: progress.status,
      postprocessor: progress.postprocessor,
      preprocessor: progress.preprocessor,
      jobStatus: jobStatus,
    );
    final defaultStageColor = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: 0.9,
    );
    final bool isFailedState =
        jobStatus == DownloadStatus.failed ||
        jobStatus == DownloadStatus.completedWithErrors;
    final Color stageColor = _brightenForDarkTheme(
      (!isFailedState &&
              stageColorCandidate == DownloadVisualPalette.stageErrorColor)
          ? defaultStageColor
          : (stageColorCandidate ?? defaultStageColor),
      theme,
    );

    final baseMetricStyle = metricsStyle ?? const TextStyle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: indicatorValue,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
                backgroundColor: accent.withValues(alpha: 0.15),
              ),
            ),
            for (final metric in metrics) ...[
              const SizedBox(width: 8),
              Text(
                metric.label,
                style: baseMetricStyle.copyWith(
                  color: _brightenForDarkTheme(metric.color, theme),
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
            ],
          ],
        ),
        if (stageLine != null) ...[
          const SizedBox(height: 4),
          Text(
            stageLine,
            style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
              color: stageColor,
            ),
          ),
        ],
      ],
    );
  }

  double? _computeIndicatorValue() {
    final percent = progress.percent;
    if (percent != null) {
      return (percent / 100).clamp(0.0, 1.0);
    }
    final stagePercent = progress.stagePercent;
    if (stagePercent != null) {
      return (stagePercent / 100).clamp(0.0, 1.0);
    }
    if (jobStatus == DownloadStatus.completed ||
        jobStatus == DownloadStatus.completedWithErrors) {
      return 1.0;
    }
    if (jobStatus == DownloadStatus.failed ||
        jobStatus == DownloadStatus.cancelled) {
      return 0.0;
    }
    return null;
  }

  List<_MetricEntry> _buildMetrics(DownloadMetricColors palette) {
    final metrics = <_MetricEntry>[];
    final downloaded = progress.downloadedBytes;
    final total = progress.totalBytes;
    if (downloaded != null && total != null && total > 0) {
      metrics.add(
        _MetricEntry(
          '${formatBytesCompact(downloaded)}/${formatBytesCompact(total)}',
          palette.portion,
        ),
      );
    } else if (downloaded != null) {
      metrics.add(
        _MetricEntry(formatBytesCompact(downloaded), palette.portion),
      );
    } else if (total != null && total > 0) {
      metrics.add(_MetricEntry(formatBytesCompact(total), palette.portion));
    }

    final speed = progress.speed;
    if (speed != null && speed > 0) {
      metrics.add(
        _MetricEntry('${formatBytesCompact(speed)}/s', palette.speed),
      );
    }

    final eta = progress.eta;
    if (eta != null && eta > 0) {
      metrics.add(_MetricEntry(formatEta(eta), palette.eta));
    }

    return metrics;
  }
}

class _PendingProgressIndicator extends StatelessWidget {
  const _PendingProgressIndicator({required this.statusAppearance});

  final _StatusAppearance statusAppearance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusAppearance.progressColor;
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: null,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(width: 12),
        Text(statusAppearance.label, style: textStyle),
      ],
    );
  }
}

class _PlaylistSummary extends StatelessWidget {
  const _PlaylistSummary({
    required this.job,
    required this.progress,
    required this.playlist,
    required this.stateAppearance,
    this.totalItems,
    this.completedItems,
    this.pendingItems,
    this.percent,
    this.currentIndex,
  });

  final DownloadJobModel job;
  final DownloadProgress? progress;
  final DownloadPlaylistSummary? playlist;
  final _StatusAppearance stateAppearance;
  final int? totalItems;
  final int? completedItems;
  final int? pendingItems;
  final double? percent;
  final int? currentIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final isError =
        job.status == DownloadStatus.failed ||
        job.status == DownloadStatus.completedWithErrors;
    final isCompleted = job.status == DownloadStatus.completed && !isError;
    final accentBase = stateAppearance.progressColor;
    final accent = isError ? theme.colorScheme.error : accentBase;

    final counts = _resolveCounts();
    final indicatorValue = counts.percentProgress;
    final metricsPalette = DownloadVisualPalette.metricColors;
    final metrics = _buildMetrics(counts, metricsPalette);
    final metricsStyle = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final stageLabel = (!isCompleted || isError)
        ? (describeStage(
                progress?.stage,
                progress?.postprocessor,
                progress?.preprocessor,
                lookup: localizations.ui,
              ) ??
              describeStatus(progress?.status, localizations.ui) ??
              sanitizeMessage(progress?.message))
        : null;
    final descriptorLine = (!isCompleted || isError)
        ? _buildDescriptorLine(stageLabel)
        : null;
    final stageColorCandidate = DownloadVisualPalette.stageColor(
      progress?.stage,
      status: progress?.status,
      postprocessor: progress?.postprocessor,
      preprocessor: progress?.preprocessor,
      jobStatus: job.status,
    );
    final defaultStageColor = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: 0.9,
    );
    final bool isFailedState =
        job.status == DownloadStatus.failed ||
        job.status == DownloadStatus.completedWithErrors;
    final Color secondaryColor = _brightenForDarkTheme(
      (!isFailedState &&
              stageColorCandidate == DownloadVisualPalette.stageErrorColor)
          ? defaultStageColor
          : (stageColorCandidate ?? defaultStageColor),
      theme,
    );

    final baseMetricStyle = metricsStyle ?? const TextStyle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: indicatorValue,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
                backgroundColor: accent.withValues(alpha: 0.15),
              ),
            ),
            for (final metric in metrics) ...[
              const SizedBox(width: 12),
              Text(
                metric.label,
                style: baseMetricStyle.copyWith(
                  color: _brightenForDarkTheme(metric.color, theme),
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
            ],
          ],
        ),
        if (descriptorLine != null) ...[
          const SizedBox(height: 6),
          Text(
            descriptorLine,
            style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
              color: secondaryColor,
            ),
          ),
        ],
      ],
    );
  }

  _PlaylistProgressCounts _resolveCounts() {
    final resolvedTotal =
        totalItems ??
        playlist?.totalItems ??
        playlist?.entryCount ??
        progress?.playlistTotalItems ??
        progress?.playlistCount;
    int? resolvedCompleted =
        completedItems ??
        progress?.playlistCompletedItems ??
        playlist?.completedItems;
    int? resolvedPending =
        pendingItems ??
        progress?.playlistPendingItems ??
        playlist?.pendingItems;

    if (resolvedTotal != null) {
      if (resolvedCompleted == null && resolvedPending != null) {
        resolvedCompleted = math.max(resolvedTotal - resolvedPending, 0);
      } else if (resolvedPending == null && resolvedCompleted != null) {
        resolvedPending = math.max(resolvedTotal - resolvedCompleted, 0);
      }
    }

    final percentValue = percent ?? progress?.playlistPercent;
    double? indicatorValue;
    if (percentValue != null) {
      indicatorValue = (percentValue / 100).clamp(0.0, 1.0);
    } else if (resolvedCompleted != null &&
        resolvedTotal != null &&
        resolvedTotal > 0) {
      indicatorValue = (resolvedCompleted / resolvedTotal).clamp(0.0, 1.0);
    }

    final remaining = (resolvedTotal != null && resolvedCompleted != null)
        ? math.max(resolvedTotal - resolvedCompleted, 0)
        : null;

    return _PlaylistProgressCounts(
      total: resolvedTotal,
      completed: resolvedCompleted,
      pending: resolvedPending,
      percentProgress: indicatorValue,
      remaining: remaining,
    );
  }

  List<_MetricEntry> _buildMetrics(
    _PlaylistProgressCounts counts,
    DownloadMetricColors palette,
  ) {
    final metrics = <_MetricEntry>[];
    final completed = counts.completed ?? 0;
    final total = counts.total;
    if (total != null && total > 0) {
      metrics.add(_MetricEntry('$completed/$total', palette.portion));
    } else {
      metrics.add(_MetricEntry(completed.toString(), palette.portion));
    }

    final elapsed = progress?.elapsed;
    final effectiveElapsed = elapsed != null && elapsed > 0 ? elapsed : null;
    double? entryRate;
    if (effectiveElapsed != null && completed > 0) {
      entryRate = completed / effectiveElapsed;
    }
    if (entryRate != null && entryRate > 0) {
      metrics.add(
        _MetricEntry('${formatEntriesRate(entryRate)}e/s', palette.speed),
      );
    }

    int? etaSeconds = progress?.eta;
    if ((etaSeconds == null || etaSeconds <= 0) &&
        entryRate != null &&
        entryRate > 0 &&
        counts.remaining != null) {
      etaSeconds = (counts.remaining! / entryRate).ceil();
    }
    if (etaSeconds != null && etaSeconds > 0) {
      metrics.add(_MetricEntry(formatEta(etaSeconds), palette.eta));
    }

    return metrics;
  }

  String? _buildDescriptorLine(String? stageLabel) {
    final entry = _resolveCurrentEntry();
    final title =
        sanitizeText(entry?.preview?.title) ??
        sanitizeText(entry?.id) ??
        sanitizeText(job.preview?.title);
    final author =
        sanitizeText(entry?.preview?.uploader) ??
        sanitizeText(entry?.preview?.channel);
    final labelParts = <String>[];
    if (title != null && title.isNotEmpty) {
      labelParts.add(title);
    }
    if (author != null && author.isNotEmpty) {
      labelParts.add(author);
    }
    final baseLabel = labelParts.join(' - ');
    final stage = stageLabel?.replaceAll('\n', ' ').trim();

    if (baseLabel.isEmpty && (stage == null || stage.isEmpty)) {
      return null;
    }

    if (baseLabel.isEmpty) {
      return stage;
    }
    if (stage == null || stage.isEmpty) {
      return baseLabel;
    }
    return '$baseLabel:$stage';
  }

  DownloadPlaylistEntry? _resolveCurrentEntry() {
    final summary = playlist;
    final index = currentIndex;
    DownloadPlaylistEntry? candidate;
    if (summary != null) {
      if (index != null && index > 0) {
        for (final entry in summary.entries) {
          if (entry.index == index) {
            candidate = entry;
            break;
          }
        }
      }
      if (candidate == null && progress?.playlistCurrentEntryId != null) {
        final entryId = progress!.playlistCurrentEntryId;
        for (final entry in summary.entries) {
          if (entry.id == entryId) {
            candidate = entry;
            break;
          }
        }
      }
    }
    return candidate;
  }
}

class PlaylistFailureBanner extends StatelessWidget {
  const PlaylistFailureBanner({
    super.key,
    required this.failedCount,
    required this.pendingRetryCount,
    required this.retryableCount,
    required this.latestError,
    required this.isJobTerminal,
    this.onRetry,
    this.onViewDetails,
    required this.localizations,
  });

  final int failedCount;
  final int pendingRetryCount;
  final int retryableCount;
  final DownloadPlaylistEntryError? latestError;
  final bool isJobTerminal;
  final VoidCallback? onRetry;
  final VoidCallback? onViewDetails;
  final VidraLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.errorContainer;
    final foreground = theme.colorScheme.onErrorContainer;
    String localized(String key, [Map<String, String>? values]) {
      final template = localizations.ui(key);
      if (values == null || values.isEmpty) {
        return template;
      }
      return values.entries.fold<String>(
        template,
        (result, entry) => result.replaceAll('{${entry.key}}', entry.value),
      );
    }

    final summaryParts = <String>[];
    if (failedCount > 0) {
      summaryParts.add(
        failedCount == 1
            ? localized(AppStringKey.jobPlaylistFailureSingleFailed)
            : localized(AppStringKey.jobPlaylistFailureMultipleFailed, {
                'count': '$failedCount',
              }),
      );
    }
    if (pendingRetryCount > 0) {
      summaryParts.add(
        pendingRetryCount == 1
            ? localized(AppStringKey.jobPlaylistFailureSinglePending)
            : localized(AppStringKey.jobPlaylistFailureMultiplePending, {
                'count': '$pendingRetryCount',
              }),
      );
    }
    if (summaryParts.isEmpty) {
      summaryParts.add(
        localized(AppStringKey.jobPlaylistFailurePendingSummary),
      );
    }

    final latestErrorLabel = _formatLatestError(latestError);
    final bool showPendingHint = pendingRetryCount > 0 && retryableCount == 0;
    final bool showTerminalHint =
        !isJobTerminal && retryableCount > 0 && onRetry == null;

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summaryParts.join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (latestErrorLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              latestErrorLabel,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ],
          if (showPendingHint) ...[
            const SizedBox(height: 6),
            Text(
              localized(AppStringKey.jobPlaylistFailureInQueueHint),
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ],
          if (showTerminalHint) ...[
            const SizedBox(height: 6),
            Text(
              localized(AppStringKey.jobPlaylistFailureWaitForCompletion),
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ],
          if (onRetry != null || onViewDetails != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onRetry != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(
                      retryableCount > 1
                          ? localized(
                              AppStringKey.jobPlaylistFailureRetryMultiple,
                              {'count': '$retryableCount'},
                            )
                          : localized(
                              AppStringKey.jobPlaylistFailureRetrySingle,
                            ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: foreground,
                      foregroundColor: background,
                    ),
                    onPressed: onRetry,
                  ),
                if (onViewDetails != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.list_alt_outlined),
                    label: Text(
                      localized(AppStringKey.jobPlaylistFailureViewDetails),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: foreground,
                      side: BorderSide(
                        color: foreground.withValues(alpha: 0.6),
                      ),
                    ),
                    onPressed: onViewDetails,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String? _formatLatestError(DownloadPlaylistEntryError? error) {
    if (error == null) {
      return null;
    }
    final parts = <String>[];
    if (error.index > 0) {
      parts.add(
        localizations
            .ui(AppStringKey.jobPlaylistFailureEntryLabel)
            .replaceAll('{index}', '${error.index}'),
      );
    } else if (error.entryId?.trim().isNotEmpty ?? false) {
      parts.add(error.entryId!.trim());
    }
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      parts.add(message);
    } else if (error.lastStatus?.trim().isNotEmpty ?? false) {
      parts.add(error.lastStatus!.trim());
    }
    if (parts.isEmpty) {
      return null;
    }
    return localizations
        .ui(AppStringKey.jobPlaylistFailureLastError)
        .replaceAll('{error}', parts.join(' · '));
  }
}

class _MetricEntry {
  const _MetricEntry(this.label, this.color);

  final String label;
  final Color color;
}

class _PlaylistProgressCounts {
  const _PlaylistProgressCounts({
    this.total,
    this.completed,
    this.pending,
    this.percentProgress,
    this.remaining,
  });

  final int? total;
  final int? completed;
  final int? pending;
  final double? percentProgress;
  final int? remaining;
}

Color _brightenForDarkTheme(Color color, ThemeData theme) {
  if (theme.brightness != Brightness.dark) {
    return color;
  }
  return Color.lerp(color, Colors.white, 0.28) ?? color;
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.imageUrl, required this.isCompact});

  final String imageUrl;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(10);
    final background = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.5,
    );
    final iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
    final placeholder = Container(
      color: background,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: iconColor, size: 28),
    );
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
    final content = ClipRRect(
      borderRadius: borderRadius,
      child: AspectRatio(aspectRatio: 16 / 9, child: image),
    );
    if (isCompact) {
      return content;
    }
    return SizedBox(height: 50, child: content);
  }
}

class _IndexBadge extends StatelessWidget {
  const _IndexBadge({required this.index, required this.compact});

  final int index;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = compact ? 28.0 : 32.0;
    final textStyle =
        theme.textTheme.labelSmall ??
        theme.textTheme.bodySmall ??
        const TextStyle(fontSize: 12);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: theme.colorScheme.surface, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        index.toString(),
        style: textStyle.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
          fontSize: textStyle.fontSize != null
              ? textStyle.fontSize! * (compact ? 0.9 : 1.0)
              : (compact ? 11 : 12),
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatefulWidget {
  const _SkeletonLine({
    required this.color,
    this.widthFactor = 1,
    this.height = 12,
    this.borderRadius,
  });

  final Color color;
  final double widthFactor;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<_SkeletonLine> createState() => _SkeletonLineState();
}

class _SkeletonLineState extends State<_SkeletonLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widget.widthFactor,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final phase = math.sin(_controller.value * 2 * math.pi);
          final t = (phase + 1) / 2;
          final base = widget.color;
          final lowlight = Color.lerp(base, Colors.black, 0.08)!;
          final highlight = Color.lerp(base, Colors.white, 0.18)!;
          final color = Color.lerp(lowlight, highlight, t)!;
          return Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: widget.borderRadius ?? BorderRadius.circular(6),
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonImage extends StatefulWidget {
  const _SkeletonImage({required this.color, required this.isCompact});

  final Color color;
  final bool isCompact;

  @override
  State<_SkeletonImage> createState() => _SkeletonImageState();
}

class _SkeletonImageState extends State<_SkeletonImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = math.sin(_controller.value * 2 * math.pi);
        final t = (phase + 1) / 2;
        final base = widget.color;
        final lowlight = Color.lerp(base, Colors.black, 0.1)!;
        final highlight = Color.lerp(base, Colors.white, 0.2)!;
        final color = Color.lerp(lowlight, highlight, t)!;
        final content = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(color: color),
          ),
        );
        if (widget.isCompact) {
          return content;
        }
        return SizedBox(width: 160, child: content);
      },
    );
  }
}

class _ImagePlaceholderIcon extends StatelessWidget {
  const _ImagePlaceholderIcon({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.5,
    );
    final iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: background,
          alignment: Alignment.center,
          child: Icon(Icons.image_outlined, size: 34, color: iconColor),
        ),
      ),
    );
    if (isCompact) {
      return content;
    }
    return SizedBox(width: 160, child: content);
  }
}

class _StatusAppearance {
  const _StatusAppearance({
    required this.label,
    required this.icon,
    required this.progressColor,
    required this.cardColor,
    required this.iconColor,
    required this.iconBackgroundColor,
  });

  final String label;
  final IconData icon;
  final Color progressColor;
  final Color cardColor;
  final Color iconColor;
  final Color iconBackgroundColor;
}

class _JobAction {
  const _JobAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onSelected;
  final bool destructive;
}

class _PlaylistSelectionBanner extends StatelessWidget {
  const _PlaylistSelectionBanner({
    this.onPressed,
    this.isCollecting = false,
    this.collectionError,
  });

  final VoidCallback? onPressed;
  final bool isCollecting;
  final String? collectionError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final String? trimmedError = collectionError?.trim();
    final String? bannerError =
        (trimmedError != null && trimmedError.isNotEmpty) ? trimmedError : null;
    final bool hasError = bannerError != null;
    late final String semanticsLabel;
    late final String description;
    if (bannerError != null) {
      final String errorMessage = bannerError;
      semanticsLabel = errorMessage;
      description = errorMessage;
    } else {
      semanticsLabel = localizations.ui(
        isCollecting
            ? AppStringKey.jobPlaylistBannerCollectingSemantics
            : AppStringKey.jobPlaylistBannerSelectionSemantics,
      );
      description = localizations.ui(
        isCollecting
            ? AppStringKey.jobPlaylistBannerCollectingDescription
            : AppStringKey.jobPlaylistBannerSelectionDescription,
      );
    }
    final IconData icon = hasError
        ? Icons.error_outline
        : (isCollecting
              ? Icons.hourglass_bottom
              : Icons.playlist_add_check_circle);
    final Color iconColor = hasError
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final TextStyle? messageStyle = hasError
        ? theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.w600,
          )
        : theme.textTheme.bodyMedium;
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                description,
                style: messageStyle,
              ),
            ),
            if (!hasError && onPressed != null) ...[
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: onPressed,
                child: Text(
                  localizations.ui(AppStringKey.jobPlaylistBannerSelectButton),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool _isPlaylistCollecting({
  required Map<String, dynamic>? metadata,
  required DownloadPlaylistSummary? summary,
  required DownloadProgress? progress,
  String? collectionError,
}) {
  final String? resolvedCollectionError =
      collectionError ?? _parseNonEmptyString(metadata?['collection_error']);
  if (resolvedCollectionError != null) {
    return false;
  }
  final bool metadataCompleteFlag =
      metadata != null && metadata.containsKey('collection_complete')
          ? _parseFlexibleBool(metadata['collection_complete'])
          : false;
  if (metadataCompleteFlag) {
    return false;
  }
  if (summary?.collectionComplete == true) {
    return false;
  }

  final metadataEntriesRaw = metadata?['entries'];
  final int metadataEntriesCount = metadataEntriesRaw is List
      ? metadataEntriesRaw.length
      : 0;
  final int summaryEntriesCount = summary?.entries.length ?? 0;
  final int summaryRefsCount = summary?.entryRefs.length ?? 0;
  final bool hasAnyEntries =
      metadataEntriesCount > 0 ||
      summaryEntriesCount > 0 ||
      summaryRefsCount > 0;
  final bool metadataIndefiniteFlag =
      metadata != null && metadata.containsKey('has_indefinite_length')
      ? _parseFlexibleBool(metadata['has_indefinite_length'])
      : false;
  final bool hasIndefiniteLength =
      metadataIndefiniteFlag || summary?.hasIndefiniteLength == true;
  final bool indefiniteAwaiting = hasIndefiniteLength && !metadataCompleteFlag;

  final bool? metadataCollecting = metadata != null &&
          metadata.containsKey('is_collecting_entries')
      ? _parseFlexibleBool(metadata['is_collecting_entries'])
      : null;
  if (metadataCollecting != null) {
    return metadataCollecting;
  }
  if (summary?.isCollectingEntries != null) {
    return summary!.isCollectingEntries!;
  }

  int? totalItems = _parseFlexibleInt(
    metadata?['total_items'] ?? metadata?['entry_count'],
  );
  totalItems ??= summary?.totalItems ?? summary?.entryCount;
  totalItems ??= progress?.playlistTotalItems ?? progress?.playlistCount;

  int? receivedItems = _parseFlexibleInt(metadata?['received_count']);
  receivedItems ??= summary?.completedItems;
  receivedItems ??= progress?.playlistCompletedItems;
  final pending = progress?.playlistPendingItems;
  if (pending != null) {
    final pendingPositive = pending > 0;
    if (!pendingPositive) {
      return false;
    }
    if (pendingPositive && (totalItems == null || receivedItems == null)) {
      return true;
    }
  }
  if (receivedItems == null && pending != null && totalItems != null) {
    receivedItems = math.max(totalItems - pending, 0);
  }
  if (receivedItems == null) {
    if (metadataEntriesCount > 0) {
      receivedItems = metadataEntriesCount;
    } else if (summaryEntriesCount > 0) {
      receivedItems = summaryEntriesCount;
    }
  }

  var collecting = false;
  var decided = false;
  if (totalItems != null && totalItems > 0) {
    final received = math.max(receivedItems ?? 0, 0);
    collecting = received < totalItems;
    decided = true;
  }

  if (!decided && indefiniteAwaiting) {
    collecting = true;
    decided = true;
  }

  if (!decided && hasAnyEntries) {
    collecting = false;
    decided = true;
  }

  final stageValue = progress?.stage?.trim().toUpperCase();
  final stageNameValue = progress?.stageName?.trim().toUpperCase();
  final bool stageSuggestsCollecting =
      stageValue == 'WAIT_FOR_ELEMENTS' ||
      stageNameValue == 'ESPERANDO ELEMENTOS' ||
      stageValue == 'GETTING_ITEMS' ||
      stageNameValue == 'OBTENIENDO ELEMENTOS';

  if (!decided) {
    collecting = stageSuggestsCollecting;
  } else if (!collecting && stageSuggestsCollecting) {
    final bool lacksEntries = !hasAnyEntries;
    var missingCounts = false;
    if (totalItems == null) {
      missingCounts = true;
    } else if (receivedItems == null || receivedItems < totalItems) {
      missingCounts = true;
    }
    if (lacksEntries && missingCounts) {
      collecting = true;
    }
  }

  if (!decided && indefiniteAwaiting) {
    collecting = true;
  }

  return collecting;
}

bool _parseFlexibleBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'on';
  }
  return false;
}

String? _parseNonEmptyString(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String? _resolvePlaylistCollectionError(
  Map<String, dynamic>? playlistMetadata,
  DownloadJobModel job,
) {
  final metadataError = _parseNonEmptyString(
    playlistMetadata != null ? playlistMetadata['collection_error'] : null,
  );
  if (metadataError != null) {
    return metadataError;
  }
  return _parseNonEmptyString(job.metadata['collection_error']);
}

int? _parseFlexibleInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }
  return null;
}

List<int> _parseIndexList(Object? value) {
  if (value is Iterable) {
    final indices = <int>[];
    for (final entry in value) {
      final parsed = _parseFlexibleInt(entry);
      if (parsed != null && parsed > 0) {
        indices.add(parsed);
      }
    }
    return indices;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const <int>[];
    }
    final segments = trimmed.split(RegExp(r"[\s,]+"));
    final indices = <int>[];
    for (final segment in segments) {
      if (segment.isEmpty) {
        continue;
      }
      final parsed = int.tryParse(segment);
      if (parsed != null && parsed > 0) {
        indices.add(parsed);
      }
    }
    return indices;
  }
  final single = _parseFlexibleInt(value);
  if (single != null && single > 0) {
    return <int>[single];
  }
  return const <int>[];
}

bool _selectionSpecConfigured(Object? value) {
  if (value == null) {
    return false;
  }
  if (value is String) {
    return value.trim().isNotEmpty;
  }
  if (value is num) {
    return value > 0;
  }
  if (value is Iterable) {
    for (final entry in value) {
      final parsed = _parseFlexibleInt(entry);
      if (parsed != null && parsed > 0) {
        return true;
      }
    }
    return false;
  }
  return false;
}

bool _jobRequiresPlaylistSelection(
  DownloadJobModel job,
  Map<String, dynamic>? playlistMetadata,
) {
  if (job.isTerminal) {
    return false;
  }

  if (_hasPersistedPlaylistSelection(job, playlistMetadata)) {
    return false;
  }

  final collectionError = _resolvePlaylistCollectionError(
    playlistMetadata,
    job,
  );
  if (collectionError != null) {
    return false;
  }

  final hint = job.metadata['requires_playlist_selection'];
  if (hint != null) {
    return _parseFlexibleBool(hint);
  }
  if (!job.isPlaylist) {
    return false;
  }

  int? inferredCount;
  if (playlistMetadata != null) {
    final entries = playlistMetadata['entries'];
    if (entries is List) {
      inferredCount = entries.length;
    }
    if (inferredCount == null) {
      final entryRefs = playlistMetadata['entry_refs'];
      if (entryRefs is List) {
        inferredCount = entryRefs.length;
      }
    }
    inferredCount ??=
        _parseFlexibleInt(
          playlistMetadata['entry_count'] ?? playlistMetadata['total_items'],
        ) ??
        _parseFlexibleInt(job.metadata['playlist_entry_count']);
  }

  inferredCount ??=
      job.playlist?.totalItems ??
      job.playlist?.entryCount ??
      job.playlist?.entries.length;

  inferredCount ??=
      job.progress?.playlistTotalItems ?? job.progress?.playlistCount;

  if (inferredCount != null) {
    return inferredCount > 1;
  }

  return _isPlaylistCollecting(
    metadata: playlistMetadata,
    summary: job.playlist,
    progress: job.progress,
    collectionError: collectionError,
  );
}

bool _hasPersistedPlaylistSelection(
  DownloadJobModel job,
  Map<String, dynamic>? playlistMetadata,
) {
  final selectionHint = job.metadata['requires_playlist_selection'];
  if (selectionHint != null && !_parseFlexibleBool(selectionHint)) {
    return true;
  }
  if (_selectionSpecConfigured(job.options['playlist_items'])) {
    return true;
  }
  if (playlistMetadata != null && playlistMetadata.isNotEmpty) {
    final selected = _parseIndexList(playlistMetadata['selected_indices']);
    if (selected.isNotEmpty) {
      return true;
    }
  }
  return false;
}

String? _durationLabel(DownloadPreview? preview) {
  if (preview == null) {
    return null;
  }
  final text = preview.durationText;
  if (text != null && text.isNotEmpty) {
    return text;
  }
  final duration = preview.duration;
  if (duration == null) {
    return null;
  }
  return _formatDurationHuman(duration);
}

String _formatDurationHuman(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
