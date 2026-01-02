import 'dart:math' as math;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/data/models/playlist_preview.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/state/download_controller.dart';

Future<PlaylistSelectionResult?> showPlaylistSelectionDialog(
  BuildContext context,
  DownloadController controller,
  String jobId,
  PlaylistPreviewData previewData,
) {
  final playlist = previewData.playlist;
  if (playlist == null) {
    return Future.value(null);
  }
  return showDialog<PlaylistSelectionResult>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _PlaylistSelectionDialog(
      controller: controller,
      jobId: jobId,
      previewData: previewData,
      initialPlaylist: playlist,
    ),
  );
}

class PlaylistSelectionResult {
  const PlaylistSelectionResult({required this.selectedIndices});

  final Set<int>? selectedIndices;

  bool get downloadAll => selectedIndices == null || selectedIndices!.isEmpty;
}

PlaylistPreviewData? _buildPreviewDataFromJob(DownloadJobModel job) {
  Map<String, dynamic>? previewJson;
  final previewRaw = job.metadata['preview'];
  if (previewRaw is Map<String, dynamic>) {
    previewJson = Map<String, dynamic>.from(previewRaw);
  } else if (previewRaw is Map) {
    previewJson = previewRaw.cast<String, dynamic>();
  }

  Map<String, dynamic>? playlistJson;
  final playlistRaw = job.metadata['playlist'];
  if (playlistRaw is Map<String, dynamic>) {
    playlistJson = Map<String, dynamic>.from(playlistRaw);
  } else if (playlistRaw is Map) {
    playlistJson = playlistRaw.cast<String, dynamic>();
  }

  if (previewJson == null && playlistJson == null) {
    return null;
  }
  previewJson ??= <String, dynamic>{};
  if (playlistJson != null) {
    previewJson['playlist'] = playlistJson;
  }
  return PlaylistPreviewData.fromJson(previewJson);
}

enum _PlaylistSortKey { originalOrder, title, duration, uploader }

enum _TableColumnType { selection, order, duration, channel, title }

class _PlaylistSelectionDialog extends StatefulWidget {
  const _PlaylistSelectionDialog({
    required this.controller,
    required this.jobId,
    required this.previewData,
    required this.initialPlaylist,
  });

  final DownloadController controller;
  final String jobId;
  final PlaylistPreviewData previewData;
  final PlaylistPreview initialPlaylist;

  @override
  State<_PlaylistSelectionDialog> createState() =>
      _PlaylistSelectionDialogState();
}

class _PlaylistSelectionDialogState extends State<_PlaylistSelectionDialog> {
  static const double _selectorColumnWidth = 45;
  static const double _indexColumnWidth = 70;
  static const double _titlePreferredWidth = 350;
  static const double _durationColumnWidth = 100;
  static const double _channelColumnWidth = 150;
  static const double _dataRowHeight = 56;
  static const double _breakpointShowDuration = 720;
  static const double _breakpointShowCheckbox = 640;
  static const double _breakpointShowIndex = 560;
  static const double _breakpointShowChannel = 480;
  static const List<int> _pageSizeOptions = [25, 50, 100, 200];
  static const double _columnSpacing = 0;
  static const double _horizontalMargin = 0;
  static const Duration _tableRenderInterval = Duration(seconds: 1);
  late List<PlaylistPreviewEntry> _entries;
  late Set<int> _selected;
  _PlaylistSortKey _sortKey = _PlaylistSortKey.originalOrder;
  bool _ascending = true;
  String _filterText = '';
  int _pageIndex = 0;
  int _pageSize = _pageSizeOptions.first;
  late final TextEditingController _filterController;
  late final ScrollController _verticalScrollController;
  late final ScrollController _horizontalScrollController;
  late PlaylistPreviewData _currentPreview;
  late PlaylistPreview _currentPlaylist;
  PlaylistPreviewData? _pendingPreviewData;
  bool _pendingPreviewScheduled = false;
  DateTime? _lastPreviewAppliedAt;
  Widget? _cachedTable;
  List<PlaylistPreviewEntry> _cachedTableEntries =
      const <PlaylistPreviewEntry>[];
  List<PlaylistPreviewEntry> _cachedFilteredEntries =
      const <PlaylistPreviewEntry>[];
  bool _tableCacheDirty = true;
  bool _tableCacheUpdateScheduled = false;
  DateTime? _lastTableRenderAt;
  bool _cachedSelectionEnabled = true;

  @override
  void initState() {
    super.initState();
    _entries = <PlaylistPreviewEntry>[];
    _selected = <int>{};
    _filterController = TextEditingController(text: _filterText);
    _verticalScrollController = ScrollController();
    _horizontalScrollController = ScrollController();
    _currentPreview = widget.previewData;
    _currentPlaylist = widget.initialPlaylist;
    _syncPreview(widget.previewData, useSetState: false);
    widget.controller.addListener(_handleControllerUpdate);
  }

  @override
  void didUpdateWidget(covariant _PlaylistSelectionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerUpdate);
      widget.controller.addListener(_handleControllerUpdate);
    }
    if (oldWidget.jobId != widget.jobId ||
        oldWidget.previewData != widget.previewData) {
      _syncPreview(widget.previewData);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerUpdate);
    _filterController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _handleControllerUpdate() {
    if (!mounted) {
      return;
    }
    final job = widget.controller.jobById(widget.jobId);
    if (job == null) {
      return;
    }
    final preview = _buildPreviewDataFromJob(job);
    if (preview == null || preview.playlist == null) {
      return;
    }
    _schedulePreviewSync(preview);
  }

  void _schedulePreviewSync(PlaylistPreviewData preview) {
    _pendingPreviewData = preview;
    if (_pendingPreviewScheduled) {
      return;
    }
    final delay = _previewUpdateDelay(preview);
    _pendingPreviewScheduled = true;
    if (delay <= Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyPendingPreview();
      });
      return;
    }
    Future<void>.delayed(delay, () {
      _applyPendingPreview();
    });
  }

  void _applyPendingPreview() {
    if (!mounted) {
      _pendingPreviewData = null;
      _pendingPreviewScheduled = false;
      return;
    }
    final pending = _pendingPreviewData;
    _pendingPreviewData = null;
    _pendingPreviewScheduled = false;
    if (pending != null) {
      _syncPreview(pending);
      _lastPreviewAppliedAt = DateTime.now();
    }
  }

  Duration _previewUpdateDelay(PlaylistPreviewData preview) {
    final playlist = preview.playlist;
    if (playlist == null) {
      return Duration.zero;
    }
    final receivedCount = playlist.receivedCount ?? playlist.entries.length;
    final collecting = widget.controller.jobIsCollectingPlaylistEntries(
      widget.jobId,
    );
    if (!collecting || receivedCount < 200) {
      return Duration.zero;
    }
    final lastApplied = _lastPreviewAppliedAt;
    if (lastApplied == null) {
      return const Duration(milliseconds: 120);
    }
    final elapsed = DateTime.now().difference(lastApplied);
    if (elapsed >= const Duration(milliseconds: 120)) {
      return Duration.zero;
    }
    return const Duration(milliseconds: 120) - elapsed;
  }

  void _syncPreview(
    PlaylistPreviewData previewData, {
    bool useSetState = true,
  }) {
    final playlist = previewData.playlist;
    if (playlist == null) {
      return;
    }
    final updatedEntries = List<PlaylistPreviewEntry>.from(playlist.entries);
    final previousIndices = <int>{
      for (final entry in _entries)
        if (entry.index != null) entry.index!,
    };
    final newIndices = <int>{
      for (final entry in updatedEntries)
        if (entry.index != null) entry.index!,
    };
    final structureChanged = !setEquals(previousIndices, newIndices);
    final entriesChanged = !_entriesMatch(_entries, updatedEntries);
    if (!structureChanged && !entriesChanged) {
      void updateMetadataOnly() {
        _currentPreview = previewData;
        _currentPlaylist = playlist;
        _lastPreviewAppliedAt = DateTime.now();
      }

      if (useSetState) {
        setState(updateMetadataOnly);
      } else {
        updateMetadataOnly();
      }
      return;
    }
    void apply() {
      _currentPreview = previewData;
      _currentPlaylist = playlist;
      _entries = updatedEntries;
      if (structureChanged) {
        _selected.removeWhere((index) => !newIndices.contains(index));
        final added = newIndices.difference(previousIndices);
        _selected.addAll(added);
      }
      _lastPreviewAppliedAt = DateTime.now();
      _markTableCacheDirty();
    }

    if (useSetState) {
      setState(apply);
    } else {
      apply();
    }
  }

  bool _entriesMatch(
    List<PlaylistPreviewEntry> previous,
    List<PlaylistPreviewEntry> next,
  ) {
    if (identical(previous, next)) {
      return true;
    }
    if (previous.length != next.length) {
      return false;
    }
    for (var i = 0; i < previous.length; i++) {
      final a = previous[i];
      final b = next[i];
      if (a.index != b.index ||
          a.id != b.id ||
          a.title != b.title ||
          a.durationSeconds != b.durationSeconds ||
          a.durationText != b.durationText ||
          a.uploader != b.uploader ||
          a.channel != b.channel ||
          a.webpageUrl != b.webpageUrl ||
          a.thumbnailUrl != b.thumbnailUrl ||
          a.isLive != b.isLive) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final preview = _currentPreview.preview;
    final image = _currentPlaylist.thumbnailUrl ?? preview.thumbnailUrl;
    final title =
        _currentPlaylist.title ??
        preview.title ??
        localizations.ui(AppStringKey.playlistTitleFallback);
    final uploader = _currentPlaylist.uploader ?? preview.uploader;
    final bool hasIndefiniteLength = _currentPlaylist.hasIndefiniteLength;
    final int? expectedTotalItems = hasIndefiniteLength
        ? null
        : _currentPlaylist.entryCount;
    final int receivedItems = _currentPlaylist.receivedCount ?? _entries.length;
    final bool collectionCompleteFlag =
        _currentPlaylist.collectionComplete &&
        !_currentPlaylist.isCollectingEntries;
    final bool controllerCollecting = widget.controller
        .jobIsCollectingPlaylistEntries(widget.jobId);
    final bool isCollecting =
        (!collectionCompleteFlag &&
        (controllerCollecting ||
            _currentPlaylist.isCollectingEntries ||
            (expectedTotalItems != null &&
                receivedItems < expectedTotalItems)));
    final double? collectingProgress =
        expectedTotalItems != null && expectedTotalItems > 0
        ? (receivedItems / expectedTotalItems).clamp(0.0, 1.0).toDouble()
        : null;
    late final String itemsLabel;
    if (expectedTotalItems != null) {
      if (isCollecting) {
        itemsLabel = _formatTemplate(
          localizations.ui(AppStringKey.playlistDialogItemsReceivedOfTotal),
          {'received': '$receivedItems', 'total': '$expectedTotalItems'},
        );
      } else {
        itemsLabel = _formatTemplate(
          localizations.ui(AppStringKey.playlistDialogItemsTotal),
          {'count': '$expectedTotalItems'},
        );
      }
    } else {
      itemsLabel = _formatTemplate(
        localizations.ui(
          isCollecting
              ? AppStringKey.playlistDialogItemsReceived
              : AppStringKey.playlistDialogItemsTotal,
        ),
        {'count': '$receivedItems'},
      );
    }
    final selectionEnabled = !isCollecting;
    _maybeRefreshTableCache(theme, localizations, selectionEnabled);
    final displayedFilteredEntries = _cachedFilteredEntries;
    final Widget tableWidget =
        _cachedTable ??
        _buildTable(
          theme,
          displayedFilteredEntries,
          selectionEnabled,
          localizations,
        );

    final allSelected =
        _selected.length == _cachedTableEntries.length &&
        _cachedTableEntries.isNotEmpty;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: SizedBox(
        width: 760,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (image != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          image,
                          width: 85,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 85,
                            height: 50,
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                            ),
                          ),
                        ),
                      ),
                    if (image != null) const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            uploader != null && uploader.isNotEmpty
                                ? '$title — $uploader'
                                : title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(itemsLabel, style: theme.textTheme.bodySmall),
                          if (isCollecting) ...[
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: collectingProgress,
                              minHeight: 4,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              localizations.ui(
                                AppStringKey.playlistDialogAwaitingEntries,
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                          if (_currentPlaylist.descriptionShort != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _currentPlaylist.descriptionShort!,
                              style: theme.textTheme.bodySmall,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              _buildToolbar(
                theme,
                displayedFilteredEntries.length,
                localizations,
              ),
              const SizedBox(height: 5),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: tableWidget,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.ui(AppStringKey.homeCloseAction)),
        ),
        FilledButton.icon(
          onPressed:
              isCollecting ||
                  _entries.isEmpty ||
                  (_selected.isEmpty && _entries.isNotEmpty)
              ? null
              : () {
                  Navigator.of(context).pop(
                    PlaylistSelectionResult(
                      selectedIndices: allSelected
                          ? null
                          : Set<int>.from(_selected),
                    ),
                  );
                },
          icon: const Icon(Icons.download),
          label: Text(
            allSelected
                ? localizations.ui(AppStringKey.playlistDialogDownloadAll)
                : _formatTemplate(
                    localizations.ui(
                      AppStringKey.playlistDialogDownloadSelection,
                    ),
                    {'count': '${_selected.length}'},
                  ),
          ),
        ),
      ],
    );
  }

  double _tableHeightForRows(int rowCount) {
    final effectiveRows = math.max(rowCount, 1);
    return 46 + (effectiveRows * _dataRowHeight);
  }

  Widget _buildToolbar(
    ThemeData theme,
    int filteredCount,
    VidraLocalizations localizations,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _breakpointShowDuration;
        final searchWidth = math.min(
          availableWidth,
          math.max(220.0, availableWidth - 200.0),
        );

        return Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 200, maxWidth: searchWidth),
              child: TextField(
                controller: _filterController,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  labelText: localizations.ui(
                    AppStringKey.playlistDialogFilterLabel,
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() {
                  _filterText = value.trim();
                  _pageIndex = 0;
                  _markTableCacheDirty(forceImmediate: true);
                }),
              ),
            ),
            DropdownButton<_PlaylistSortKey>(
              value: _sortKey,
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _sortKey = value;
                  _pageIndex = 0;
                  _markTableCacheDirty(forceImmediate: true);
                });
              },
              items: [
                DropdownMenuItem(
                  value: _PlaylistSortKey.originalOrder,
                  child: Text(
                    localizations.ui(AppStringKey.playlistDialogSortOriginal),
                  ),
                ),
                DropdownMenuItem(
                  value: _PlaylistSortKey.title,
                  child: Text(
                    localizations.ui(AppStringKey.playlistDialogSortTitle),
                  ),
                ),
                DropdownMenuItem(
                  value: _PlaylistSortKey.duration,
                  child: Text(
                    localizations.ui(AppStringKey.playlistDialogSortDuration),
                  ),
                ),
                DropdownMenuItem(
                  value: _PlaylistSortKey.uploader,
                  child: Text(
                    localizations.ui(AppStringKey.playlistDialogSortChannel),
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: _ascending
                  ? localizations.ui(AppStringKey.playlistDialogSortAscending)
                  : localizations.ui(AppStringKey.playlistDialogSortDescending),
              onPressed: () => setState(() {
                _ascending = !_ascending;
                _pageIndex = 0;
                _markTableCacheDirty(forceImmediate: true);
              }),
              icon: Icon(
                _ascending ? Icons.arrow_upward : Icons.arrow_downward,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTable(
    ThemeData theme,
    List<PlaylistPreviewEntry> entries,
    bool selectionEnabled,
    VidraLocalizations localizations,
  ) {
    final totalPages = (entries.length / _pageSize).ceil();
    final rawIndex = _pageIndex;
    final pageIndex = totalPages == 0 ? 0 : rawIndex.clamp(0, totalPages - 1);
    if (pageIndex != rawIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _pageIndex = pageIndex;
          _markTableCacheDirty(forceImmediate: true);
        });
      });
    }

    final hasEntries = entries.isNotEmpty;
    final start = hasEntries ? pageIndex * _pageSize : 0;
    final visibleEntries = hasEntries
        ? entries.skip(start).take(_pageSize).toList(growable: false)
        : const <PlaylistPreviewEntry>[];
    final end = hasEntries ? start + visibleEntries.length : 0;
    final rangeLabel = hasEntries
        ? _formatTemplate(
            localizations.ui(AppStringKey.homePaginationRangeLabel),
            {
              'start': '${start + 1}',
              'end': '$end',
              'total': '${entries.length}',
            },
          )
        : localizations.ui(AppStringKey.homePaginationNoItems);
    final allFilteredSelectable = entries.any((entry) => entry.index != null);
    final allFilteredSelected =
        allFilteredSelectable &&
        entries.every((entry) {
          final index = entry.index;
          return index != null && _selected.contains(index);
        });
    final tableHeight = _tableHeightForRows(visibleEntries.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : _breakpointShowCheckbox;
              final showDurationColumn =
                  availableWidth >= _breakpointShowDuration;
              final showCheckboxColumn =
                  availableWidth >= _breakpointShowCheckbox;
              final showIndexColumn = availableWidth >= _breakpointShowIndex;
              final showChannelColumn =
                  availableWidth >= _breakpointShowChannel;

              final columnTypes = <_TableColumnType>[
                if (showCheckboxColumn) _TableColumnType.selection,
                if (showIndexColumn) _TableColumnType.order,
                _TableColumnType.title,
                if (showDurationColumn) _TableColumnType.duration,
                if (showChannelColumn) _TableColumnType.channel,
              ];

              final sortColumnType = _columnTypeForSortKey(_sortKey);
              final computedSortColumnIndex =
                  sortColumnType != null && columnTypes.contains(sortColumnType)
                  ? columnTypes.indexOf(sortColumnType)
                  : null;

              final columns = <DataColumn>[
                for (final columnType in columnTypes)
                  _buildDataColumn(
                    columnType,
                    localizations,
                    allFilteredSelected: allFilteredSelected,
                    allFilteredSelectable: allFilteredSelectable,
                    filteredEntries: entries,
                    selectionEnabled: selectionEnabled,
                  ),
              ];

              final rows = <DataRow>[
                for (final entry in visibleEntries)
                  _buildRow(
                    theme,
                    entry,
                    columnTypes,
                    selectionEnabled,
                    localizations,
                  ),
              ];

              return Scrollbar(
                controller: _verticalScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _verticalScrollController,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: availableWidth,
                    height: tableHeight,
                    child: DataTable2(
                      showCheckboxColumn: false,
                      sortColumnIndex: computedSortColumnIndex,
                      sortAscending: _ascending,
                      headingRowHeight: 46,
                      dataRowHeight: _dataRowHeight,
                      horizontalMargin: _horizontalMargin,
                      columnSpacing: _columnSpacing,
                      checkboxHorizontalMargin: 0,
                      minWidth: availableWidth,
                      columns: columns,
                      rows: rows,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildTableFooter(
          theme,
          localizations,
          rangeLabel,
          totalPages,
          pageIndex,
        ),
      ],
    );
  }

  _TableColumnType? _columnTypeForSortKey(_PlaylistSortKey key) {
    switch (key) {
      case _PlaylistSortKey.originalOrder:
        return _TableColumnType.order;
      case _PlaylistSortKey.title:
        return _TableColumnType.title;
      case _PlaylistSortKey.duration:
        return _TableColumnType.duration;
      case _PlaylistSortKey.uploader:
        return _TableColumnType.channel;
    }
  }

  DataColumn _buildDataColumn(
    _TableColumnType columnType,
    VidraLocalizations localizations, {
    required bool allFilteredSelected,
    required bool allFilteredSelectable,
    required List<PlaylistPreviewEntry> filteredEntries,
    required bool selectionEnabled,
  }) {
    switch (columnType) {
      case _TableColumnType.selection:
        return DataColumn2(
          fixedWidth: _selectorColumnWidth,
          label: SizedBox(
            width: _selectorColumnWidth,
            child: Center(
              child: Checkbox(
                value: allFilteredSelected,
                onChanged: selectionEnabled && allFilteredSelectable
                    ? (checked) =>
                          _toggleSelectAll(checked ?? false, filteredEntries)
                    : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                splashRadius: 18,
              ),
            ),
          ),
        );
      case _TableColumnType.order:
        return DataColumn2(
          fixedWidth: _indexColumnWidth,
          label: const Text('#', textAlign: TextAlign.center),
          numeric: true,
          onSort: (_, _) => _applySort(_PlaylistSortKey.originalOrder),
        );
      case _TableColumnType.duration:
        return DataColumn2(
          fixedWidth: _durationColumnWidth,
          label: Text(
            localizations.ui(AppStringKey.playlistDialogColumnDuration),
          ),
          onSort: (_, _) => _applySort(_PlaylistSortKey.duration),
        );
      case _TableColumnType.channel:
        return DataColumn2(
          fixedWidth: _channelColumnWidth,
          label: Text(
            localizations.ui(AppStringKey.playlistDialogColumnChannel),
          ),
          onSort: (_, _) => _applySort(_PlaylistSortKey.uploader),
        );
      case _TableColumnType.title:
        return DataColumn2(
          label: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              localizations.ui(AppStringKey.playlistDialogColumnTitle),
            ),
          ),
          size: ColumnSize.L,
          onSort: (_, _) => _applySort(_PlaylistSortKey.title),
        );
    }
  }

  Widget _buildTableFooter(
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
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
                  isDense: true,
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
                  onPressed: pageIndex > 0 ? () => _goToPage(0) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: localizations.ui(
                    AppStringKey.homePaginationPrevious,
                  ),
                  onPressed: pageIndex > 0
                      ? () => _goToPage(pageIndex - 1)
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
                      ? () => _goToPage(pageIndex + 1)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.last_page),
                  tooltip: localizations.ui(AppStringKey.homePaginationLast),
                  onPressed: pageIndex < totalPages - 1
                      ? () => _goToPage(totalPages - 1)
                      : null,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _changePageSize(int newSize) {
    setState(() {
      _pageSize = newSize;
      _pageIndex = 0;
      _markTableCacheDirty(forceImmediate: true);
    });
  }

  void _goToPage(int newPage) {
    setState(() {
      _pageIndex = newPage;
      _markTableCacheDirty(forceImmediate: true);
    });
  }

  DataRow _buildRow(
    ThemeData theme,
    PlaylistPreviewEntry entry,
    List<_TableColumnType> columnTypes,
    bool selectionEnabled,
    VidraLocalizations localizations,
  ) {
    final index = entry.index ?? -1;
    final isSelected = _selected.contains(index);
    final duration = entry.durationText ?? _formatDuration(entry.duration);
    final thumbnail = entry.thumbnailUrl;

    final cells = <DataCell>[];

    for (final columnType in columnTypes) {
      switch (columnType) {
        case _TableColumnType.selection:
          cells.add(
            DataCell(
              SizedBox(
                width: _selectorColumnWidth,
                child: Center(
                  child: Checkbox(
                    value: isSelected,
                    onChanged: selectionEnabled
                        ? (value) => _toggleSelection(index, value ?? false)
                        : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                  ),
                ),
              ),
            ),
          );
          break;
        case _TableColumnType.order:
          cells.add(
            DataCell(
              SizedBox(
                width: _indexColumnWidth,
                child: Text(
                  index > 0 ? index.toString() : '-',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
          break;
        case _TableColumnType.duration:
          cells.add(
            DataCell(
              SizedBox(
                width: _durationColumnWidth,
                child: Text(
                  duration ?? '—',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
          break;
        case _TableColumnType.channel:
          cells.add(
            DataCell(
              SizedBox(
                width: _channelColumnWidth,
                child: Text(
                  entry.uploader ?? entry.channel ?? '—',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
          break;
        case _TableColumnType.title:
          cells.add(
            DataCell(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: LayoutBuilder(
                  builder: (context, cellConstraints) {
                    final maxWidth = cellConstraints.hasBoundedWidth
                        ? cellConstraints.maxWidth
                        : _titlePreferredWidth;
                    final thumbWidth = thumbnail != null ? 48.0 : 0.0;
                    final spacing = thumbnail != null ? 12.0 : 0.0;
                    final textWidth = math.max(
                      0.0,
                      maxWidth - thumbWidth - spacing,
                    );
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (thumbnail != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                thumbnail,
                                width: 48,
                                height: 36,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 48,
                                  height: 36,
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.image_not_supported_outlined,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        SizedBox(
                          width: textWidth,
                          child: Text(
                            entry.title ??
                                entry.id ??
                                _formatTemplate(
                                  localizations.ui(
                                    AppStringKey
                                        .playlistDialogEntryFallbackTitle,
                                  ),
                                  {
                                    'index': entry.index != null
                                        ? '${entry.index}'
                                        : '?',
                                  },
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
          break;
      }
    }

    return DataRow(
      selected: isSelected,
      onSelectChanged: selectionEnabled
          ? (_) => _toggleSelection(index, !isSelected)
          : null,
      cells: cells,
    );
  }

  List<PlaylistPreviewEntry> _filteredEntriesFrom(
    List<PlaylistPreviewEntry> source,
  ) {
    final query = _filterText.trim().toLowerCase();
    final items = List<PlaylistPreviewEntry>.from(source);
    if (query.isNotEmpty) {
      items.retainWhere((entry) {
        final haystack = [
          entry.title,
          entry.uploader,
          entry.channel,
        ].whereType<String>().map((value) => value.toLowerCase()).join(' ');
        return haystack.contains(query);
      });
    }
    items.sort(_sortComparator);
    if (_ascending) {
      return items;
    }
    return items.reversed.toList(growable: false);
  }

  void _markTableCacheDirty({bool forceImmediate = false}) {
    if (forceImmediate) {
      _lastTableRenderAt = null;
    }
    if (_tableCacheDirty && !forceImmediate) {
      return;
    }
    _tableCacheDirty = true;
  }

  void _scheduleTableCacheUpdate() {
    if (_tableCacheUpdateScheduled) {
      return;
    }
    final now = DateTime.now();
    final elapsed = _lastTableRenderAt == null
        ? _tableRenderInterval
        : now.difference(_lastTableRenderAt!);
    final wait = elapsed >= _tableRenderInterval
        ? Duration.zero
        : _tableRenderInterval - elapsed;
    _tableCacheUpdateScheduled = true;
    Future<void>.delayed(wait, () {
      if (!mounted) {
        _tableCacheUpdateScheduled = false;
        return;
      }
      _tableCacheUpdateScheduled = false;
      if (_tableCacheDirty) {
        setState(() {
          // Trigger rebuild so the cache refreshes inside build.
        });
      }
    });
  }

  void _maybeRefreshTableCache(
    ThemeData theme,
    VidraLocalizations localizations,
    bool selectionEnabled,
  ) {
    final now = DateTime.now();
    final bool canRenderNow =
        _lastTableRenderAt == null ||
        now.difference(_lastTableRenderAt!) >= _tableRenderInterval;
    final bool selectionChanged = selectionEnabled != _cachedSelectionEnabled;
    if (_cachedTable == null || selectionChanged) {
      _rebuildTableCache(theme, localizations, selectionEnabled);
      return;
    }
    if (_tableCacheDirty && canRenderNow) {
      _rebuildTableCache(theme, localizations, selectionEnabled);
      return;
    }
    if (_tableCacheDirty && !canRenderNow) {
      _scheduleTableCacheUpdate();
    }
  }

  void _rebuildTableCache(
    ThemeData theme,
    VidraLocalizations localizations,
    bool selectionEnabled,
  ) {
    final snapshotEntries = List<PlaylistPreviewEntry>.from(_entries);
    final filteredSnapshot = _filteredEntriesFrom(snapshotEntries);
    _cachedTableEntries = snapshotEntries;
    _cachedFilteredEntries = filteredSnapshot;
    _cachedTable = _buildTable(
      theme,
      filteredSnapshot,
      selectionEnabled,
      localizations,
    );
    _cachedSelectionEnabled = selectionEnabled;
    _lastTableRenderAt = DateTime.now();
    _tableCacheDirty = false;
  }

  void _applySort(_PlaylistSortKey key) {
    setState(() {
      if (_sortKey == key) {
        _ascending = !_ascending;
      } else {
        _sortKey = key;
        _ascending = true;
      }
      _pageIndex = 0;
      _markTableCacheDirty(forceImmediate: true);
    });
  }

  int _sortComparator(PlaylistPreviewEntry a, PlaylistPreviewEntry b) {
    switch (_sortKey) {
      case _PlaylistSortKey.originalOrder:
        return (a.index ?? 0).compareTo(b.index ?? 0);
      case _PlaylistSortKey.title:
        return (a.title ?? '').toLowerCase().compareTo(
          (b.title ?? '').toLowerCase(),
        );
      case _PlaylistSortKey.duration:
        return (a.durationSeconds ?? 0).compareTo(b.durationSeconds ?? 0);
      case _PlaylistSortKey.uploader:
        return (a.uploader ?? a.channel ?? '').toLowerCase().compareTo(
          (b.uploader ?? b.channel ?? '').toLowerCase(),
        );
    }
  }

  void _toggleSelectAll(bool selectAll, List<PlaylistPreviewEntry> entries) {
    setState(() {
      if (selectAll) {
        for (final entry in entries) {
          final index = entry.index;
          if (index != null) {
            _selected.add(index);
          }
        }
      } else {
        for (final entry in entries) {
          final index = entry.index;
          if (index != null) {
            _selected.remove(index);
          }
        }
      }
      _markTableCacheDirty(forceImmediate: true);
    });
  }

  void _toggleSelection(int index, bool value) {
    if (index <= 0) {
      return;
    }
    setState(() {
      if (value) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
      _markTableCacheDirty(forceImmediate: true);
    });
  }

  String _formatTemplate(String template, Map<String, String> values) {
    return values.entries.fold<String>(
      template,
      (result, entry) => result.replaceAll('{${entry.key}}', entry.value),
    );
  }

  String? _formatDuration(Duration? duration) {
    if (duration == null) {
      return null;
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
