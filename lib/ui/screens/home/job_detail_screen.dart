import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/ui/screens/home/playlist_detail_screen.dart';
import 'package:vidra/ui/widgets/jobs/download_job_card.dart';

class JobDetailScreen extends StatefulWidget {
  const JobDetailScreen({
    super.key,
    required this.jobId,
    this.initialJob,
    this.parentJobId,
  });

  final String jobId;
  final DownloadJobModel? initialJob;
  final String? parentJobId;

  static Route<void> route(String jobId) {
    return MaterialPageRoute<void>(
      builder: (_) => JobDetailScreen(jobId: jobId),
      settings: RouteSettings(name: 'job-detail/$jobId'),
    );
  }

  static Route<void> entryRoute({
    required DownloadJobModel entryJob,
    required String parentJobId,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => JobDetailScreen(
        jobId: entryJob.id,
        initialJob: entryJob,
        parentJobId: parentJobId,
      ),
      settings: RouteSettings(name: 'entry-detail/${entryJob.id}'),
    );
  }

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  bool _optionsLoading = false;
  bool _logsLoading = false;
  String? _optionsError;
  String? _logsError;
  bool _hydratedOnce = false;
  DownloadJobModel? _ephemeralJob;
  _EntryJobContext? _entryContext;
  bool _optionsAutoRequested = false;
  bool _logsAutoRequested = false;
  bool _optionsHydrated = false;
  bool _logsHydrated = false;

  final DateFormat _timeFormat = DateFormat('HH:mm:ss');

  DownloadController get _controller => context.read<DownloadController>();

  @override
  void initState() {
    super.initState();
    _ephemeralJob = widget.initialJob;
    _entryContext = _EntryJobContext.from(
      jobId: widget.jobId,
      parentJobId: widget.parentJobId,
      initialJob: widget.initialJob,
    );
    _seedHydrationFlags(_ephemeralJob);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydratedOnce) {
      return;
    }
    _hydratedOnce = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_primeLazyPayloads());
      }
    });
  }

  @override
  void didUpdateWidget(covariant JobDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialJob != widget.initialJob) {
      _ephemeralJob = widget.initialJob;
    }
    if (oldWidget.initialJob != widget.initialJob ||
        oldWidget.parentJobId != widget.parentJobId ||
        oldWidget.jobId != widget.jobId) {
      _entryContext = _EntryJobContext.from(
        jobId: widget.jobId,
        parentJobId: widget.parentJobId,
        initialJob: widget.initialJob ?? _ephemeralJob,
      );
      _optionsAutoRequested = false;
      _logsAutoRequested = false;
      _seedHydrationFlags(_ephemeralJob ?? widget.initialJob);
    }
  }

  Future<void> _primeLazyPayloads() async {
    final job = _controller.jobById(widget.jobId);
    if (job == null) {
      await _controller.refreshJobs();
    }
  }

  void _seedHydrationFlags(DownloadJobModel? job) {
    _optionsHydrated = job?.options.isNotEmpty ?? false;
    _logsHydrated = job?.logs.isNotEmpty ?? false;
  }

  DownloadJobModel? _resolvedJobSnapshot() {
    return _controller.jobById(widget.jobId) ??
        _ephemeralJob ??
        widget.initialJob;
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _optionsAutoRequested = false;
      _logsAutoRequested = false;
      _seedHydrationFlags(_resolvedJobSnapshot());
    });
    await _controller.refreshJobs();
    await _primeLazyPayloads();
  }

  Future<void> _refreshOptions({bool force = false}) async {
    if (_entryContext != null) {
      await _refreshEntryOptions(force: force);
      return;
    }
    if (_optionsLoading) {
      return;
    }
    setState(() {
      _optionsLoading = true;
      _optionsError = null;
      _optionsHydrated = false;
    });
    try {
      await _controller.loadJobOptions(widget.jobId, forceRefresh: force);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _optionsError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _optionsLoading = false;
          _optionsHydrated = true;
        });
      }
    }
  }

  Future<void> _refreshLogs({bool force = false}) async {
    if (_entryContext != null) {
      await _refreshEntryLogs(force: force);
      return;
    }
    if (_logsLoading) {
      return;
    }
    setState(() {
      _logsLoading = true;
      _logsError = null;
      _logsHydrated = false;
    });
    try {
      await _controller.loadJobLogs(widget.jobId, forceRefresh: force);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _logsError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _logsLoading = false;
          _logsHydrated = true;
        });
      }
    }
  }

  bool _expectsOptionsPayload(DownloadJobModel job) {
    if (_entryContext != null) {
      return true;
    }
    return job.optionsExternal;
  }

  bool _expectsLogsPayload(DownloadJobModel job) {
    if (_entryContext != null) {
      return true;
    }
    return job.logsExternal;
  }

  bool _needsOptionsFetch(DownloadJobModel job) {
    return _expectsOptionsPayload(job) && job.options.isEmpty;
  }

  bool _needsLogsFetch(DownloadJobModel job) {
    return _expectsLogsPayload(job) && job.logs.isEmpty;
  }

  void _ensureOptionsRequested(DownloadJobModel job) {
    if (_optionsAutoRequested || _optionsLoading) {
      return;
    }
    if (!_needsOptionsFetch(job)) {
      return;
    }
    _optionsAutoRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_refreshOptions());
    });
  }

  void _ensureLogsRequested(DownloadJobModel job) {
    if (_logsAutoRequested || _logsLoading) {
      return;
    }
    if (!_needsLogsFetch(job)) {
      return;
    }
    _logsAutoRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_refreshLogs());
    });
  }

  Future<void> _refreshEntryOptions({bool force = false}) async {
    final context = _entryContext;
    if (context == null || _optionsLoading) {
      return;
    }
    setState(() {
      _optionsLoading = true;
      _optionsError = null;
      _optionsHydrated = false;
    });
    try {
      final options = await _controller.loadEntryJobOptions(
        context.parentJobId,
        entryId: context.entryId,
        entryIndex: context.playlistIndex,
        forceRefresh: force,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final source = _ephemeralJob ?? widget.initialJob;
        if (source != null) {
          _ephemeralJob = source.copyWith(
            options: options,
            optionsExternal: true,
          );
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _optionsError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _optionsLoading = false;
          _optionsHydrated = true;
        });
      }
    }
  }

  Future<void> _refreshEntryLogs({bool force = false}) async {
    final context = _entryContext;
    if (context == null || _logsLoading) {
      return;
    }
    setState(() {
      _logsLoading = true;
      _logsError = null;
      _logsHydrated = false;
    });
    try {
      final logs = await _controller.loadEntryJobLogs(
        context.parentJobId,
        entryId: context.entryId,
        entryIndex: context.playlistIndex,
        forceRefresh: force,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final source = _ephemeralJob ?? widget.initialJob;
        if (source != null) {
          _ephemeralJob = source.copyWith(logs: logs, logsExternal: true);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _logsError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _logsLoading = false;
          _logsHydrated = true;
        });
      }
    }
  }

  Future<void> _copyLogs(List<DownloadLogEntry> logs) async {
    if (logs.isEmpty) {
      return;
    }
    final buffer = StringBuffer();
    for (final log in logs) {
      final timestamp = _formatLogTimestamp(log.timestamp);
      final level = log.level.toUpperCase().padRight(5);
      buffer.writeln('[$timestamp] $level ${log.message}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) {
      return;
    }
    final localizations = VidraLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localizations.ui(AppStringKey.jobDetailLogsCopied)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controllerJob = context.select<DownloadController, DownloadJobModel?>(
      (controller) => controller.jobById(widget.jobId),
    );
    final job = controllerJob ?? _ephemeralJob;
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_resolveTitle(localizations, job)),
        actions: [
          if (widget.parentJobId != null)
            Semantics(
              button: true,
              label: localizations.ui(AppStringKey.jobDetailViewParentAction),
              child: IconButton(
                tooltip: localizations.ui(
                  AppStringKey.jobDetailViewParentAction,
                ),
                icon: const Icon(Icons.work_outline),
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(JobDetailScreen.route(widget.parentJobId!));
                },
              ),
            ),
          Semantics(
            button: true,
            label: localizations.ui(AppStringKey.jobDetailRefreshAction),
            child: IconButton(
              tooltip: localizations.ui(AppStringKey.jobDetailRefreshAction),
              icon: const Icon(Icons.refresh),
              onPressed: _handleRefresh,
            ),
          ),
          if (job?.isPlaylist == true)
            Semantics(
              button: true,
              label: localizations.ui(
                AppStringKey.jobDetailPlaylistDetailsAction,
              ),
              child: IconButton(
                tooltip: localizations.ui(
                  AppStringKey.jobDetailPlaylistDetailsAction,
                ),
                icon: const Icon(Icons.queue_music),
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(PlaylistDetailScreen.route(widget.jobId));
                },
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: job == null
            ? _buildMissingJobBody(theme, localizations)
            : _buildDetailBody(context, localizations, job),
      ),
    );
  }

  Widget _buildMissingJobBody(
    ThemeData theme,
    VidraLocalizations localizations,
  ) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        Icon(Icons.work_off, size: 48, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Text(
          localizations.ui(AppStringKey.jobDetailMissingJobMessage),
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _buildDetailBody(
    BuildContext context,
    VidraLocalizations localizations,
    DownloadJobModel job,
  ) {
    return DefaultTabController(
      length: 2,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    _buildOverviewSection(job),
                    const SizedBox(height: 16),
                    _buildDetailsTabBar(context, localizations),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          children: [
            Builder(
              builder: (context) =>
                  _buildOptionsTab(context, localizations, job),
            ),
            Builder(
              builder: (context) => _buildLogsTab(context, localizations, job),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsTab(
    BuildContext context,
    VidraLocalizations localizations,
    DownloadJobModel job,
  ) {
    _ensureLogsRequested(job);
    return CustomScrollView(
      primary: false,
      key: const PageStorageKey<String>('job_logs_tab'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 16),
              _buildLogsSection(localizations, job),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsTab(
    BuildContext context,
    VidraLocalizations localizations,
    DownloadJobModel job,
  ) {
    _ensureOptionsRequested(job);
    return CustomScrollView(
      primary: false,
      key: const PageStorageKey<String>('job_options_tab'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 16),
              _buildOptionsSection(localizations, job),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsTabBar(
    BuildContext context,
    VidraLocalizations localizations,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: TabBar(
          labelStyle: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          tabs: [
            Tab(text: localizations.ui(AppStringKey.jobDetailOptionsTab)),
            Tab(text: localizations.ui(AppStringKey.jobDetailLogsTab)),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection(DownloadJobModel job) {
    final isEntryView = _entryContext != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DownloadJobCard(
        job: job,
        onShowDetails: null,
        enableActions: !isEntryView,
        showDefaultActions: !isEntryView,
        onTap: job.isPlaylist && widget.parentJobId == null
            ? () =>
                  Navigator.of(context).push(PlaylistDetailScreen.route(job.id))
            : null,
      ),
    );
  }

  Widget _buildOptionsSection(
    VidraLocalizations localizations,
    DownloadJobModel job,
  ) {
    final options = job.options;
    final expectsExternal = _expectsOptionsPayload(job);
    final awaitingRemote =
        expectsExternal && (_optionsLoading || !_optionsHydrated);
    Widget child;
    if (options.isEmpty) {
      child = awaitingRemote
          ? const _AsyncContentPlaceholder()
          : Text(localizations.ui(AppStringKey.jobDetailNoOptions));
    } else {
      final encoder = const JsonEncoder.withIndent('  ');
      child = SelectableText(
        encoder.convert(options),
        style: const TextStyle(fontFamily: 'monospace', height: 1.4),
      );
    }
    return _SectionCard(
      localizations: localizations,
      title: localizations.ui(AppStringKey.jobDetailOptionsTitle),
      subtitle: expectsExternal
          ? localizations.ui(AppStringKey.jobDetailOptionsSubtitle)
          : null,
      isLoading: _optionsLoading,
      errorText: _optionsError,
      onRefresh: () {
        _optionsAutoRequested = false;
        unawaited(_refreshOptions(force: true));
      },
      child: child,
    );
  }

  Widget _buildLogsSection(
    VidraLocalizations localizations,
    DownloadJobModel job,
  ) {
    final logs = job.logs;
    final expectsExternal = _expectsLogsPayload(job);
    final awaitingRemote = expectsExternal && (_logsLoading || !_logsHydrated);
    Widget child;
    if (logs.isEmpty) {
      child = awaitingRemote
          ? const _AsyncContentPlaceholder()
          : Text(localizations.ui(AppStringKey.jobDetailNoLogs));
    } else {
      child = Column(
        children: logs
            .map(
              (log) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _LogLine(
                  timestamp: _formatLogTimestamp(log.timestamp),
                  level: log.level,
                  message: log.message,
                  localizations: localizations,
                ),
              ),
            )
            .toList(growable: false),
      );
    }
    final copyLogsLabel = localizations.ui(AppStringKey.jobDetailCopyLogs);
    return _SectionCard(
      localizations: localizations,
      title: localizations.ui(AppStringKey.jobDetailLogsTitle),
      subtitle: expectsExternal
          ? localizations.ui(AppStringKey.jobDetailLogsSubtitle)
          : null,
      isLoading: _logsLoading,
      errorText: _logsError,
      onRefresh: () {
        _logsAutoRequested = false;
        unawaited(_refreshLogs(force: true));
      },
      actions: [
        Semantics(
          button: true,
          enabled: logs.isNotEmpty,
          label: copyLogsLabel,
          child: IconButton(
            tooltip: copyLogsLabel,
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: logs.isEmpty ? null : () => _copyLogs(logs),
          ),
        ),
      ],
      child: child,
    );
  }

  String _resolveTitle(
    VidraLocalizations localizations,
    DownloadJobModel? job,
  ) {
    if (job == null) {
      return localizations.ui(AppStringKey.jobDetailTitleFallback);
    }
    final previewTitle = job.preview?.title?.trim();
    if (previewTitle != null && previewTitle.isNotEmpty) {
      return previewTitle;
    }
    if (job.urls.isNotEmpty) {
      return job.urls.first;
    }
    return job.id;
  }

  String _formatLogTimestamp(DateTime? timestamp) {
    if (timestamp == null) {
      return '--:--:--';
    }
    return _timeFormat.format(timestamp.toLocal());
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.localizations,
    required this.title,
    required this.child,
    this.subtitle,
    this.isLoading = false,
    this.errorText,
    this.onRefresh,
    this.actions = const <Widget>[],
  });

  final VidraLocalizations localizations;
  final String title;
  final Widget child;
  final String? subtitle;
  final bool isLoading;
  final String? errorText;
  final VoidCallback? onRefresh;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reloadLabel = localizations.ui(AppStringKey.jobDetailReloadAction);
    final reloadSectionTemplate = localizations.ui(
      AppStringKey.jobDetailReloadSection,
    );
    final reloadSectionLabel = reloadSectionTemplate.replaceAll(
      '{title}',
      title,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(subtitle!, style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (onRefresh != null)
                    Semantics(
                      button: true,
                      enabled: !isLoading,
                      label: reloadSectionLabel,
                      child: IconButton(
                        tooltip: reloadLabel,
                        icon: const Icon(Icons.refresh),
                        onPressed: isLoading ? null : onRefresh,
                      ),
                    ),
                  ...actions,
                ],
              ),
              const SizedBox(height: 12),
              if (errorText != null) ...[
                Text(
                  errorText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _AsyncContentPlaceholder extends StatelessWidget {
  const _AsyncContentPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          height: 32,
          width: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _EntryJobContext {
  const _EntryJobContext({
    required this.jobId,
    required this.parentJobId,
    this.entryId,
    this.playlistIndex,
  });

  final String jobId;
  final String parentJobId;
  final String? entryId;
  final int? playlistIndex;

  static _EntryJobContext? from({
    required String jobId,
    required String? parentJobId,
    DownloadJobModel? initialJob,
  }) {
    final normalizedParent = parentJobId?.trim();
    if (normalizedParent == null || normalizedParent.isEmpty) {
      return null;
    }
    String? resolvedEntryId;
    int? resolvedIndex;
    final metadata = initialJob?.metadata ?? const <String, dynamic>{};
    final entryIdValue = metadata['entry_id'];
    if (entryIdValue is String && entryIdValue.trim().isNotEmpty) {
      resolvedEntryId = entryIdValue.trim();
    }
    final indexValue = metadata['playlist_index'];
    if (indexValue is int) {
      resolvedIndex = indexValue;
    } else if (indexValue is num) {
      resolvedIndex = indexValue.toInt();
    }
    return _EntryJobContext(
      jobId: jobId,
      parentJobId: normalizedParent,
      entryId: resolvedEntryId,
      playlistIndex: resolvedIndex,
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({
    required this.timestamp,
    required this.level,
    required this.message,
    required this.localizations,
  });

  final String timestamp;
  final String level;
  final String message;
  final VidraLocalizations localizations;

  Color _resolveLevelColor(ThemeData theme) {
    switch (level.toLowerCase()) {
      case 'error':
      case 'critical':
        return theme.colorScheme.error;
      case 'warning':
      case 'warn':
        return theme.colorScheme.tertiary;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticsTemplate = localizations.ui(
      AppStringKey.jobDetailLogLineSemantics,
    );
    final semanticsLabel = semanticsTemplate
        .replaceAll('{timestamp}', timestamp)
        .replaceAll('{level}', level.toUpperCase())
        .replaceAll('{message}', message)
        .trim();
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(
                timestamp,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: Text(
                level.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _resolveLevelColor(theme),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(message)),
          ],
        ),
      ),
    );
  }
}
