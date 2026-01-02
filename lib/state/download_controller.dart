import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/constants/backend_constants.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/data/models/playlist_preview.dart';
import 'package:vidra/data/services/download_service.dart';
import 'package:vidra/i18n/i18n.dart' show I18n;
import 'package:vidra/state/app_lifecycle_observer.dart';
import 'package:vidra/state/notifications/download_notification_manager.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Coordinates download job state between the Flutter UI and the Python
/// backend. The controller listens to websocket broadcasts, keeps an in-memory
/// cache of jobs, and exposes convenience methods to execute backend actions.
class DownloadController extends ChangeNotifier {
  DownloadController({
    required this.backendConfig,
    required String authToken,
    required ValueListenable<BackendState> backendStateListenable,
    DownloadService? service,
    bool logUnhandledJobEvents = true,
    DownloadNotificationManager? notificationManager,
    String Function()? languageResolver,
    AppLifecycleObserver? appLifecycleObserver,
  }) : _backendStateListenable = backendStateListenable,
       _backendState = backendStateListenable.value,
       _authToken = authToken,
       _languageResolver = languageResolver,
       _service =
           service ??
           DownloadService(
             backendConfig,
             authToken: authToken,
             languageResolver: languageResolver,
           ),
        _logUnhandledJobEvents = logUnhandledJobEvents,
       _notificationManager = notificationManager,
       _appLifecycleObserver = appLifecycleObserver {
    _backendStateListenable.addListener(_handleBackendStateChanged);
    _notificationManager?.registerActionHandlers(
      onRetryJob: _handleNotificationRetry,
    );
    _appLifecycleObserver?.addListener(_handleLifecycleStateChanged);
  }

  final BackendConfig backendConfig;
  String _authToken;
  final DownloadService _service;
  final bool _logUnhandledJobEvents;
  final DownloadNotificationManager? _notificationManager;
  final String Function()? _languageResolver;
  final ValueListenable<BackendState> _backendStateListenable;
  final AppLifecycleObserver? _appLifecycleObserver;

  final Map<String, DownloadJobModel> _jobs = <String, DownloadJobModel>{};
  List<DownloadJobModel> _jobsView = const <DownloadJobModel>[];
  bool _jobsViewDirty = true;
  final List<String> _jobOrdering = <String>[];
  final Map<String, _SocketHandle> _jobSockets = <String, _SocketHandle>{};
  final Map<String, Timer> _jobReconnectTimers = <String, Timer>{};
  final Map<String, Duration> _jobRetryDelays = <String, Duration>{};
  final Set<String> _subscribedJobs = <String>{};
  final Set<String> _jobsBeingFetched = <String>{};
  final Map<String, int> _manualJobSubscriptions = <String, int>{};
  final Queue<String> _pendingPlaylistSelectionQueue = ListQueue<String>();
  final Set<String> _queuedPlaylistSelections = <String>{};
  final Set<String> _playlistAttentionNotified = <String>{};
  String? _activePlaylistSelectionJobId;
  final Map<String, Future<Map<String, dynamic>>> _pendingOptionsFetches =
      <String, Future<Map<String, dynamic>>>{};
  final Map<String, Future<Map<String, dynamic>>> _pendingEntryOptionsFetches =
      <String, Future<Map<String, dynamic>>>{};
  final Map<String, Future<List<DownloadLogEntry>>> _pendingLogsFetches =
      <String, Future<List<DownloadLogEntry>>>{};
  final Map<String, Future<List<DownloadLogEntry>>> _pendingEntryLogsFetches =
      <String, Future<List<DownloadLogEntry>>>{};
  final Map<String, Future<DownloadPlaylistSummary?>> _pendingPlaylistFetches =
      <String, Future<DownloadPlaylistSummary?>>{};

  WebSocketChannel? _overviewChannel;
  StreamSubscription<dynamic>? _overviewSubscription;
  Timer? _overviewReconnectTimer;
  Duration _nextOverviewRetryDelay = _baseOverviewRetryDelay;

  bool _isInitializing = false;
  bool _initialized = false;
  bool _initializeRequested = false;
  bool _isSubmitting = false;
  bool _disposed = false;
  String? _lastError;
  Map<String, dynamic>? _overviewSummary;
  BackendState _backendState;

  static const Duration _baseOverviewRetryDelay = Duration(seconds: 2);
  static const Duration _maxOverviewRetryDelay = Duration(seconds: 30);
  static const Duration _baseJobRetryDelay = Duration(seconds: 2);
  static const Duration _maxJobRetryDelay = Duration(seconds: 30);
  static const int _maxPersistedLogs = 200;

  bool get isSubmitting => _isSubmitting;
  bool get isInitialized => _initialized;
  String? get lastError => _lastError;
  Map<String, dynamic>? get overviewSummary => _overviewSummary;
  BackendState get backendState => _backendState;
  bool get backendReady => _backendState == BackendState.running;
  ValueListenable<BackendState> get backendStateListenable =>
      _backendStateListenable;

  void updateAuthToken(String authToken) {
    final normalized = authToken.trim();
    if (normalized.isEmpty || normalized == _authToken) {
      return;
    }
    _authToken = normalized;
    _service.updateAuthToken(normalized);
    if (_disposed) {
      return;
    }

    _cancelOverview();
    for (final jobId in _jobSockets.keys.toList(growable: false)) {
      _closeJobSocket(jobId);
    }

    if (backendReady &&
        (_initialized || _isInitializing || _initializeRequested)) {
      _connectOverview();
      _syncJobSubscriptions();
    }
  }

  List<DownloadJobModel> get jobs {
    if (_jobsViewDirty) {
      _jobsView = List<DownloadJobModel>.unmodifiable(_buildOrderedJobs());
      _jobsViewDirty = false;
    }
    return _jobsView;
  }

  List<DownloadJobModel> _buildOrderedJobs() {
    final ordered = <DownloadJobModel>[];
    final seen = <String>{};
    for (final jobId in _jobOrdering) {
      final job = _jobs[jobId];
      if (job == null) {
        continue;
      }
      ordered.add(job);
      seen.add(jobId);
    }
    if (seen.length != _jobs.length) {
      for (final entry in _jobs.entries) {
        if (seen.contains(entry.key)) {
          continue;
        }
        ordered.add(entry.value);
      }
    }
    return ordered;
  }

  DownloadJobModel? jobById(String jobId) {
    return _jobs[jobId];
  }

  bool jobIsCollectingPlaylistEntries(String jobId) {
    final job = _jobs[jobId];
    if (job == null) {
      return false;
    }
    return _jobIsCollectingPlaylistEntries(job);
  }

  /// Establishes the initial websocket connection so the controller can
  /// receive job updates. Safe to call multiple times.
  Future<void> initialize() async {
    _initializeRequested = true;
    if (!_ensureBackendReady('sincronizar las descargas', silent: true)) {
      return;
    }
    if (_initialized || _isInitializing) {
      return;
    }
    _isInitializing = true;
    try {
      _connectOverview();
      await refreshJobs();
      _initialized = true;
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('Failed to initialize DownloadController: $error');
      debugPrint(stackTrace.toString());
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Fetches the latest job list from the backend and reconciles it with the
  /// local cache. Jobs that disappear from the backend are removed locally.
  Future<void> refreshJobs() async {
    if (!_ensureBackendReady('actualizar las descargas')) {
      return;
    }
    try {
      final items = await _service.listJobs();
      _clearLastError();
      final fetchedIds = <String>{};
      var queueChanged = false;
      for (final job in items) {
        final existing = _jobs[job.id];
        final merged = existing != null ? existing.merge(job) : job;
        _cacheJob(merged);
        _afterJobMutation(
          job.id,
          previous: existing,
          updated: merged,
          optionsProvided: job.options.isNotEmpty,
          logsProvided: job.logs.isNotEmpty,
        );
        fetchedIds.add(job.id);
        queueChanged =
            _updatePlaylistSelectionTracking(job.id, merged) || queueChanged;
      }

      final toRemove = _jobs.keys
          .where((id) => !fetchedIds.contains(id))
          .toList(growable: false);
      for (final jobId in toRemove) {
        queueChanged =
            _updatePlaylistSelectionTracking(jobId, null) || queueChanged;
        _jobs.remove(jobId);
        _markJobsViewDirty();
        _removeJobFromOrdering(jobId);
        _closeJobSocket(jobId);
        final notificationManager = _notificationManager;
        if (notificationManager != null) {
          unawaited(notificationManager.handleJobRemoved(jobId));
        }
      }

      _rebuildJobOrdering();
      _syncJobSubscriptions();
      if (queueChanged || items.isNotEmpty || toRemove.isNotEmpty) {
        notifyListeners();
      }
    } on DownloadServiceConnectionException catch (error) {
      _handleConnectionException('Actualización de trabajos', error);
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('Failed to refresh jobs: $error');
      debugPrint(stackTrace.toString());
      notifyListeners();
    }
  }

  Future<PlaylistPreviewData?> previewUrl(
    String url,
    Map<String, dynamic> options,
  ) async {
    if (!_ensureBackendReady('obtener la vista previa')) {
      return null;
    }
    try {
      final payload = await _service.previewUrl(url, options);
      if (payload == null) {
        return null;
      }
      return PlaylistPreviewData.fromJson(payload);
    } catch (error, stackTrace) {
      if (error is DownloadServiceConnectionException) {
        _handleConnectionException('Vista previa de $url', error);
      } else {
        _lastError = error.toString();
        debugPrint('Failed to preview $url: $error');
        debugPrint(stackTrace.toString());
        notifyListeners();
      }
      return null;
    }
  }

  Future<DownloadPlaylistSummary?> loadPlaylist(
    String jobId, {
    bool includeEntries = false,
    int? offset,
    int? limit,
  }) async {
    final cached = _jobs[jobId]?.playlist;
    if (!_ensureBackendReady('cargar la playlist')) {
      return cached;
    }
    try {
      if (includeEntries) {
        final currentPlaylist = _jobs[jobId]?.playlist;
        final bool shouldUseDelta = currentPlaylist?.entriesExternal == true;
        if (shouldUseDelta) {
          int? sinceVersion;
          if (currentPlaylist != null && currentPlaylist.entries.isNotEmpty) {
            sinceVersion = currentPlaylist.entriesVersion;
          }
          final summary = await _fetchPlaylistEntriesSnapshot(
            jobId,
            sinceVersion: sinceVersion,
          );
          if (summary != null) {
            return summary;
          }
        }
      }
      final snapshot = await _service.fetchPlaylistSnapshot(
        jobId,
        includeEntries: includeEntries,
        offset: includeEntries ? offset : null,
        limit: includeEntries ? limit : null,
      );
      if (snapshot == null) {
        return null;
      }
      final targetId = snapshot.jobId.isNotEmpty ? snapshot.jobId : jobId;
      _applyPlaylistUpdate(targetId, snapshot.summary, status: snapshot.status);
      return snapshot.summary;
    } catch (error, stackTrace) {
      if (error is DownloadServiceConnectionException) {
        _handleConnectionException('Carga de playlist $jobId', error);
      } else {
        _lastError = error.toString();
        debugPrint('Failed to load playlist for $jobId: $error');
        debugPrint(stackTrace.toString());
        notifyListeners();
      }
      return null;
    }
  }

  Future<Map<String, dynamic>> loadJobOptions(
    String jobId, {
    bool forceRefresh = false,
    int? expectedVersion,
  }) async {
    if (_disposed) {
      return const <String, dynamic>{};
    }
    final job = _jobs[jobId];
    if (job == null) {
      return const <String, dynamic>{};
    }
    if (!_ensureBackendReady('cargar las opciones del trabajo')) {
      return job.options;
    }
    final needsFetch =
        forceRefresh || (job.optionsExternal && job.options.isEmpty);
    if (!needsFetch) {
      return job.options;
    }
    final sinceVersion = forceRefresh
        ? expectedVersion
        : expectedVersion ?? (job.options.isEmpty ? null : job.optionsVersion);
    return _fetchJobOptionsSnapshot(jobId, sinceVersion: sinceVersion);
  }

  Future<Map<String, dynamic>> loadEntryJobOptions(
    String parentJobId, {
    String? entryId,
    int? entryIndex,
    bool forceRefresh = false,
  }) async {
    if (_disposed) {
      return const <String, dynamic>{};
    }
    final normalizedId = parentJobId.trim();
    if (normalizedId.isEmpty) {
      return const <String, dynamic>{};
    }
    final sanitizedEntryId = entryId?.trim();
    final effectiveEntryId =
        sanitizedEntryId != null && sanitizedEntryId.isNotEmpty
        ? sanitizedEntryId
        : null;
    final effectiveEntryIndex = entryIndex != null && entryIndex > 0
        ? entryIndex
        : null;
    if (!_ensureBackendReady('cargar las opciones del elemento')) {
      return const <String, dynamic>{};
    }
    await _ensureJobCached(normalizedId);
    final cacheKey = _entryOptionsCacheKey(
      normalizedId,
      effectiveEntryId,
      effectiveEntryIndex,
    );
    if (forceRefresh) {
      _pendingEntryOptionsFetches.remove(cacheKey);
    } else {
      final inFlight = _pendingEntryOptionsFetches[cacheKey];
      if (inFlight != null) {
        return inFlight;
      }
    }
    final future =
        _doLoadEntryJobOptions(
          normalizedId,
          entryId: effectiveEntryId,
          entryIndex: effectiveEntryIndex,
        ).whenComplete(() {
          _pendingEntryOptionsFetches.remove(cacheKey);
        });
    _pendingEntryOptionsFetches[cacheKey] = future;
    return future;
  }

  Future<List<DownloadLogEntry>> loadJobLogs(
    String jobId, {
    bool forceRefresh = false,
    int? limit,
    int? expectedVersion,
    bool silent = false,
  }) async {
    if (_disposed) {
      return const <DownloadLogEntry>[];
    }
    final job = _jobs[jobId];
    if (job == null) {
      return const <DownloadLogEntry>[];
    }
    if (!_ensureBackendReady('cargar los registros del trabajo')) {
      return job.logs;
    }
    final needsFetch = forceRefresh || (job.logsExternal && job.logs.isEmpty);
    if (!needsFetch) {
      return job.logs;
    }
    final sinceVersion = forceRefresh
        ? expectedVersion
        : expectedVersion ?? (job.logs.isEmpty ? null : job.logsVersion);
    return _fetchJobLogsSnapshot(
      jobId,
      sinceVersion: sinceVersion,
      limit: limit ?? _maxPersistedLogs,
      silent: silent,
    );
  }

  Future<List<DownloadLogEntry>> loadEntryJobLogs(
    String parentJobId, {
    String? entryId,
    int? entryIndex,
    bool forceRefresh = false,
    int? limit,
  }) async {
    if (_disposed) {
      return const <DownloadLogEntry>[];
    }
    final normalizedId = parentJobId.trim();
    if (normalizedId.isEmpty) {
      return const <DownloadLogEntry>[];
    }
    final sanitizedEntryId = entryId?.trim();
    final effectiveEntryId =
        sanitizedEntryId != null && sanitizedEntryId.isNotEmpty
        ? sanitizedEntryId
        : null;
    final effectiveEntryIndex = entryIndex != null && entryIndex > 0
        ? entryIndex
        : null;
    if (!_ensureBackendReady('cargar los registros del elemento')) {
      return const <DownloadLogEntry>[];
    }
    final effectiveLimit = limit ?? _maxPersistedLogs;
    final cacheKey = _entryLogsCacheKey(
      normalizedId,
      effectiveEntryId,
      effectiveEntryIndex,
      effectiveLimit,
    );
    if (forceRefresh) {
      _pendingEntryLogsFetches.remove(cacheKey);
    } else {
      final inFlight = _pendingEntryLogsFetches[cacheKey];
      if (inFlight != null) {
        return inFlight;
      }
    }
    final future =
        _doLoadEntryJobLogs(
          normalizedId,
          entryId: effectiveEntryId,
          entryIndex: effectiveEntryIndex,
          limit: effectiveLimit,
        ).whenComplete(() {
          _pendingEntryLogsFetches.remove(cacheKey);
        });
    _pendingEntryLogsFetches[cacheKey] = future;
    return future;
  }

  void subscribeToPlaylistUpdates(String jobId) {
    if (_disposed) {
      return;
    }
    final sanitizedId = jobId.trim();
    if (sanitizedId.isEmpty) {
      return;
    }
    final current = _manualJobSubscriptions[sanitizedId] ?? 0;
    _manualJobSubscriptions[sanitizedId] = current + 1;
    _syncJobSubscriptions();
  }

  void unsubscribeFromPlaylistUpdates(String jobId) {
    final sanitizedId = jobId.trim();
    if (sanitizedId.isEmpty) {
      return;
    }
    final current = _manualJobSubscriptions[sanitizedId];
    if (current == null) {
      return;
    }
    if (current <= 1) {
      _manualJobSubscriptions.remove(sanitizedId);
    } else {
      _manualJobSubscriptions[sanitizedId] = current - 1;
    }
    _syncJobSubscriptions();
  }

  String? takeNextPlaylistSelectionRequest() {
    if (_activePlaylistSelectionJobId != null || _disposed) {
      return null;
    }
    while (_pendingPlaylistSelectionQueue.isNotEmpty) {
      final jobId = _pendingPlaylistSelectionQueue.removeFirst();
      final job = _jobs[jobId];
      if (job == null) {
        _queuedPlaylistSelections.remove(jobId);
        _cancelPlaylistAttention(jobId);
        continue;
      }
      if (!_queuedPlaylistSelections.contains(jobId)) {
        continue;
      }
      if (!_jobRequiresPlaylistSelection(job)) {
        _queuedPlaylistSelections.remove(jobId);
        _cancelPlaylistAttention(jobId);
        continue;
      }
      _activePlaylistSelectionJobId = jobId;
      _cancelPlaylistAttention(jobId);
      return jobId;
    }
    return null;
  }

  void completePlaylistSelectionRequest(
    String jobId, {
    bool keepQueued = false,
  }) {
    if (_activePlaylistSelectionJobId == jobId) {
      _activePlaylistSelectionJobId = null;
    }
    _removePendingPlaylistRequest(jobId);
    if (!keepQueued) {
      _queuedPlaylistSelections.remove(jobId);
      _cancelPlaylistAttention(jobId);
    }
  }

  void requeuePlaylistSelection(String jobId) {
    if (_disposed) {
      return;
    }
    _cancelPlaylistAttention(jobId);
    _queuedPlaylistSelections.add(jobId);
    _pendingPlaylistSelectionQueue.add(jobId);
    if (_activePlaylistSelectionJobId == jobId) {
      _activePlaylistSelectionJobId = null;
    }
    final job = _jobs[jobId];
    if (job != null && _jobRequiresPlaylistSelection(job)) {
      _maybeAlertPlaylistSelection(job);
    }
    notifyListeners();
  }

  bool _removePendingPlaylistRequest(String jobId) {
    var removed = false;
    _pendingPlaylistSelectionQueue.removeWhere((id) {
      final shouldRemove = id == jobId;
      if (shouldRemove) {
        removed = true;
      }
      return shouldRemove;
    });
    return removed;
  }

  void _cacheJob(DownloadJobModel job) {
    _jobs[job.id] = job;
    _upsertJobOrdering(job);
    _markJobsViewDirty();
  }

  void _upsertJobOrdering(DownloadJobModel job) {
    _jobOrdering.remove(job.id);
    var insertIndex = -1;
    for (var i = 0; i < _jobOrdering.length; i++) {
      final sibling = _jobs[_jobOrdering[i]];
      if (sibling == null) {
        continue;
      }
      if (sibling.createdAt.isBefore(job.createdAt)) {
        insertIndex = i;
        break;
      }
    }
    if (insertIndex == -1) {
      _jobOrdering.add(job.id);
    } else {
      _jobOrdering.insert(insertIndex, job.id);
    }
  }

  void _removeJobFromOrdering(String jobId) {
    _jobOrdering.remove(jobId);
    _markJobsViewDirty();
  }

  void _rebuildJobOrdering() {
    final orderedJobs = _jobs.values.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _jobOrdering
      ..clear()
      ..addAll(orderedJobs.map((job) => job.id));
    _markJobsViewDirty();
  }

  void _markJobsViewDirty() {
    _jobsViewDirty = true;
  }

  /// Enqueues a new download on the backend using the provided URL and
  /// options. Returns `true` when the request is accepted.
  Future<bool> startDownload(
    String url,
    Map<String, dynamic> options, {
    Map<String, dynamic>? metadata,
    String? owner,
  }) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      _lastError = 'La URL es obligatoria.';
      notifyListeners();
      return false;
    }

    if (!_ensureBackendReady('iniciar una descarga')) {
      return false;
    }

    _isSubmitting = true;
    _lastError = null;
    notifyListeners();

    try {
      final normalizedOwner = owner?.trim();
      final requestOptions = Map<String, dynamic>.from(options);
      final combinedMetadata = <String, dynamic>{
        'client': backendConfig.name,
        'description': backendConfig.description,
        'timestamp': DateTime.now().toIso8601String(),
        'base_uri': backendConfig.baseUri.toString(),
        'api_base_uri': backendConfig.apiBaseUri.toString(),
        'ws_overview_uri': backendConfig.overviewSocketUri.toString(),
        'ws_job_base_uri': backendConfig.jobSocketBaseUri.toString(),
        'timeout_seconds': backendConfig.timeout.inSeconds,
        'host': backendConfig.baseUri.host,
        'port': backendConfig.baseUri.hasPort
            ? backendConfig.baseUri.port
            : null,
        if (backendConfig.metadata.isNotEmpty) ...backendConfig.metadata,
        if (metadata != null) ...metadata,
      };
      if (normalizedOwner != null && normalizedOwner.isNotEmpty) {
        combinedMetadata['owner'] = normalizedOwner;
      }
      combinedMetadata.removeWhere((key, value) => value == null);

      final job = await _service.createJob(
        trimmedUrl,
        requestOptions,
        metadata: combinedMetadata,
        owner: normalizedOwner,
      );
      _cacheJob(job);
      _syncJobSubscriptions();
      unawaited(_refreshSingleJob(job.id));
      notifyListeners();
      return true;
    } on DownloadServiceConnectionException catch (error) {
      _handleConnectionException('Inicio de descarga', error);
      return false;
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('Failed to start download: $error');
      debugPrint(stackTrace.toString());
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Requests the backend to pause the specified job.
  Future<bool> pauseJob(String jobId) {
    if (!_ensureBackendReady('pausar el trabajo')) {
      return Future<bool>.value(false);
    }
    return _performJobAction(
      jobId: jobId,
      optimisticStatus: DownloadStatus.pausing,
      action: () => _service.pauseJob(jobId),
    );
  }

  /// Requests the backend to resume the specified job.
  Future<bool> resumeJob(String jobId) {
    if (!_ensureBackendReady('reanudar el trabajo')) {
      return Future<bool>.value(false);
    }
    return _performJobAction(
      jobId: jobId,
      optimisticStatus: DownloadStatus.running,
      action: () => _service.resumeJob(jobId),
    );
  }

  /// Attempts to cancel the specified job.
  Future<bool> cancelJob(String jobId) {
    if (!_ensureBackendReady('cancelar el trabajo')) {
      return Future<bool>.value(false);
    }
    return _performJobAction(
      jobId: jobId,
      optimisticStatus: DownloadStatus.cancelling,
      action: () => _service.cancelJob(jobId),
    );
  }

  /// Re-enqueues a job by invoking the backend retry endpoint.
  Future<bool> retryJob(String jobId) {
    if (!_ensureBackendReady('reintentar el trabajo')) {
      return Future<bool>.value(false);
    }
    return _performJobAction(
      jobId: jobId,
      optimisticStatus: DownloadStatus.queued,
      action: () => _service.retryJob(jobId),
    );
  }

  /// Retries specific failed playlist entries for a job.
  Future<bool> retryPlaylistEntries(
    String jobId, {
    Iterable<int>? indices,
    Iterable<String>? entryIds,
  }) async {
    if (_disposed) {
      return false;
    }
    if (!_ensureBackendReady('reintentar los elementos de la lista')) {
      return false;
    }
    final sanitizedId = jobId.trim();
    if (sanitizedId.isEmpty) {
      return false;
    }
    await _ensureJobCached(sanitizedId);
    final normalizedIndices = <int>{};
    if (indices != null) {
      for (final index in indices) {
        if (index > 0) {
          normalizedIndices.add(index);
        }
      }
    }
    final normalizedEntryIds = <String>{};
    if (entryIds != null) {
      for (final entryId in entryIds) {
        final trimmed = entryId.trim();
        if (trimmed.isNotEmpty) {
          normalizedEntryIds.add(trimmed);
        }
      }
    }
    if (normalizedIndices.isEmpty && normalizedEntryIds.isEmpty) {
      _lastError = 'Selecciona al menos un elemento para reintentar.';
      notifyListeners();
      return false;
    }
    return _performJobAction(
      jobId: sanitizedId,
      optimisticStatus: DownloadStatus.retrying,
      action: () => _service.retryPlaylistEntries(
        sanitizedId,
        indices: normalizedIndices.isEmpty ? null : normalizedIndices,
        entryIds: normalizedEntryIds.isEmpty ? null : normalizedEntryIds,
      ),
      onResponse: (response) {
        _applyPlaylistRetryResponse(sanitizedId, response);
      },
    );
  }

  /// Retries every failed playlist entry for the provided job.
  Future<bool> retryAllFailedPlaylistEntries(String jobId) async {
    if (_disposed) {
      return false;
    }
    if (!_ensureBackendReady('reintentar los elementos de la lista')) {
      return false;
    }
    final sanitizedId = jobId.trim();
    if (sanitizedId.isEmpty) {
      return false;
    }
    await _ensureJobCached(sanitizedId);
    final job = _jobs[sanitizedId];
    if (job == null) {
      _lastError = 'No se encontró el trabajo solicitado.';
      notifyListeners();
      return false;
    }
    final retryable = _collectRetryablePlaylistIndices(job.playlist);
    if (retryable.isEmpty) {
      _lastError = 'No hay elementos fallidos para reintentar.';
      notifyListeners();
      return false;
    }
    return retryPlaylistEntries(sanitizedId, indices: retryable);
  }

  /// Permanently deletes the job from the backend store.
  Future<bool> deleteJob(String jobId) {
    if (!_ensureBackendReady('eliminar el trabajo')) {
      return Future<bool>.value(false);
    }
    return _performJobAction(
      jobId: jobId,
      action: () => _service.deleteJob(jobId),
      expectDeletion: true,
    );
  }

  Future<bool> submitPlaylistSelection(
    String jobId, {
    Set<int>? indices,
  }) async {
    if (_disposed) {
      return false;
    }
    if (!_ensureBackendReady('enviar la selección de playlist')) {
      return false;
    }
    final filtered = indices?.where((value) => value > 0);
    final iterable = filtered?.toList(growable: false);
    try {
      await _service.submitPlaylistSelection(jobId, indices: iterable);
      completePlaylistSelectionRequest(jobId);
      _clearLastError();
      return true;
    } catch (error, stackTrace) {
      if (error is DownloadServiceConnectionException) {
        _handleConnectionException('Selección de playlist $jobId', error);
      } else {
        _lastError = error.toString();
        debugPrint('Failed to submit playlist selection for $jobId: $error');
        debugPrint(stackTrace.toString());
      }
      requeuePlaylistSelection(jobId);
      return false;
    }
  }

  void _connectOverview() {
    if (_disposed) {
      return;
    }
    _cancelOverview();
    _overviewReconnectTimer?.cancel();
    if (!backendReady) {
      return;
    }
    unawaited(_openOverviewChannel());
  }

  Future<void> _openOverviewChannel() async {
    if (!backendReady) {
      return;
    }
    final uri = _socketUriWithToken(backendConfig.overviewSocketEndpoint());
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(uri);
      await channel.ready;
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      final subscription = channel.stream.listen(
        _handleOverviewSocketMessage,
        onDone: _handleOverviewSocketDone,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Overview socket error: $error');
          debugPrint(stackTrace.toString());
          _handleOverviewSocketDone();
        },
        cancelOnError: true,
      );
      _overviewChannel = channel;
      _overviewSubscription = subscription;
      _nextOverviewRetryDelay = _baseOverviewRetryDelay;
      _clearLastError();
    } catch (error, stackTrace) {
      if (_disposed) {
        return;
      }
      try {
        await channel?.sink.close();
      } catch (_) {
        // ignore cleanup errors
      }
      _recordError('No se pudo conectar con el backend. Reintentando...');
      debugPrint('Failed to connect overview websocket: $error');
      debugPrint(stackTrace.toString());
      _scheduleOverviewReconnect();
    }
  }

  Uri _socketUriWithToken(Uri uri) {
    final token = _authToken.trim();
    if (token.isEmpty) {
      return uri;
    }
    final updated = Map<String, String>.from(uri.queryParameters);
    updated['token'] = token;
    return uri.replace(queryParameters: updated);
  }

  void _handleOverviewSocketMessage(dynamic raw) {
    final event = _decodeSocketEvent(raw);
    if (event == null) {
      return;
    }
    final name = event['event'] as String?;
    final payload = event['payload'];
    switch (name) {
      case BackendSocketEvent.update:
        _handleUpdateEvent(payload, fromOverview: true);
        break;
      case BackendSocketEvent.log:
        _handleLogEvent(payload);
        break;
      case BackendSocketEvent.overview:
        _handleOverviewSnapshot(payload);
        break;
      default:
        if (name != null && name.isNotEmpty) {
          debugPrint('Unhandled overview socket event: $name');
        }
        break;
    }
  }

  void _handleOverviewSocketDone() {
    if (_disposed) {
      return;
    }
    _cancelOverview();
    _recordError('Conexión con el backend perdida. Reintentando...');
    _scheduleOverviewReconnect();
  }

  void _scheduleOverviewReconnect([
    Duration delay = const Duration(seconds: 2),
  ]) {
    if (_disposed || !backendReady) {
      return;
    }
    _overviewReconnectTimer?.cancel();
    final effectiveDelay = delay == const Duration(seconds: 2)
        ? _nextOverviewRetryDelay
        : delay;
    _overviewReconnectTimer = Timer(effectiveDelay, _connectOverview);
    _nextOverviewRetryDelay = _increaseWithBackoff(
      effectiveDelay,
      _maxOverviewRetryDelay,
      minimum: _baseOverviewRetryDelay,
    );
  }

  void _cancelOverview() {
    _overviewSubscription?.cancel();
    _overviewSubscription = null;
    try {
      _overviewChannel?.sink.close();
    } catch (_) {
      // ignore close errors
    }
    _overviewChannel = null;
  }

  void _handleOverviewSnapshot(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final data = payload.cast<String, dynamic>();
    Map<String, dynamic>? summary;
    final summaryRaw = data['summary'];
    if (summaryRaw is Map) {
      summary = summaryRaw.cast<String, dynamic>();
    }
    final normalized = Map<String, dynamic>.unmodifiable(summary ?? data);
    final previous = _overviewSummary;
    if (previous != null && mapEquals(previous, normalized)) {
      return;
    }
    _overviewSummary = normalized;
    notifyListeners();
  }

  void _syncJobSubscriptions() {
    if (_disposed) {
      return;
    }
    if (!backendReady) {
      final currentJobIds = _jobSockets.keys.toList(growable: false);
      for (final jobId in currentJobIds) {
        _closeJobSocket(jobId);
      }
      return;
    }
    final desired = <String>{
      for (final entry in _manualJobSubscriptions.entries)
        if (entry.value > 0) entry.key,
    };

    for (final entry in _jobs.entries) {
      if (_shouldListenToJob(entry.value)) {
        desired.add(entry.key);
      }
    }

    for (final jobId in desired) {
      _ensureJobSocket(jobId);
    }

    final currentJobIds = _jobSockets.keys.toList(growable: false);
    for (final jobId in currentJobIds) {
      if (!desired.contains(jobId)) {
        _closeJobSocket(jobId);
      }
    }
  }

  void _ensureJobSocket(String jobId, {bool force = false}) {
    if (_disposed) {
      return;
    }
    final sanitizedId = jobId.trim();
    if (sanitizedId.isEmpty) {
      return;
    }
    if (!backendReady) {
      _closeJobSocket(sanitizedId);
      return;
    }
    if (!force && _jobSockets.containsKey(sanitizedId)) {
      return;
    }
    _closeJobSocket(sanitizedId);
    unawaited(_openJobSocket(sanitizedId));
  }

  Future<void> _openJobSocket(String jobId) async {
    if (!backendReady) {
      return;
    }
    final uri = _socketUriWithToken(backendConfig.jobSocketEndpoint(jobId));
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(uri);
      await channel.ready;
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      final targetJob = _jobs[jobId];
      final manualSubscription = _hasManualSubscription(jobId);
      if (!manualSubscription &&
          (targetJob == null || !_shouldListenToJob(targetJob))) {
        await channel.sink.close();
        return;
      }
      final subscription = channel.stream.listen(
        (dynamic raw) => _handleJobSocketMessage(jobId, raw),
        onDone: () => _handleJobSocketDone(jobId),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Job socket error for $jobId: $error');
          debugPrint(stackTrace.toString());
          _handleJobSocketDone(jobId);
        },
        cancelOnError: true,
      );
      _jobSockets[jobId] = _SocketHandle(channel, subscription);
      _subscribedJobs.add(jobId);
      _jobRetryDelays[jobId] = _baseJobRetryDelay;
      _clearLastError();
    } catch (error, stackTrace) {
      if (_disposed) {
        return;
      }
      try {
        await channel?.sink.close();
      } catch (_) {
        // ignore cleanup errors
      }
      debugPrint('Failed to connect job websocket $jobId: $error');
      debugPrint(stackTrace.toString());
      _recordError('No se pudo conectar con el backend. Reintentando...');
      _scheduleJobReconnect(jobId);
    }
  }

  void _closeJobSocket(String jobId) {
    _jobReconnectTimers.remove(jobId)?.cancel();
    _jobRetryDelays.remove(jobId);
    final handle = _jobSockets.remove(jobId);
    handle?.subscription.cancel();
    try {
      handle?.channel.sink.close();
    } catch (_) {
      // channel may already be closed
    }
    _subscribedJobs.remove(jobId);
  }

  void _handleJobSocketMessage(String jobId, dynamic raw) {
    final event = _decodeSocketEvent(raw);
    if (event == null) {
      return;
    }
    final name = event['event'] as String?;
    final payload = event['payload'];
    switch (name) {
      case BackendSocketEvent.update:
        _handleUpdateEvent(payload, fromOverview: false);
        break;
      case BackendSocketEvent.progress:
        _handleJobProgress(payload);
        break;
      case BackendSocketEvent.playlistPreviewEntry:
        _handlePlaylistPreviewEntry(payload);
        break;
      case BackendSocketEvent.playlistSnapshot:
        _handlePlaylistSnapshot(payload);
        break;
      case BackendSocketEvent.playlistProgress:
        _handlePlaylistProgress(payload);
        break;
      case BackendSocketEvent.playlistEntryProgress:
        _handlePlaylistEntryProgress(payload);
        break;
      case BackendSocketEvent.globalInfo:
        _handleGlobalInfoEvent(payload);
        break;
      case BackendSocketEvent.entryInfo:
        _handleEntryInfoEvent(payload);
        break;
      case BackendSocketEvent.listInfoEnds:
        _handleListInfoEnds(payload);
        break;
      case BackendSocketEvent.log:
        _handleLogEvent(payload);
        break;
      default:
        if (_logUnhandledJobEvents && name != null && name.isNotEmpty) {
          debugPrint('Unhandled job socket event $name for job $jobId');
        }
        break;
    }
  }

  void _handleJobSocketDone(String jobId) {
    _jobReconnectTimers.remove(jobId)?.cancel();
    final handle = _jobSockets.remove(jobId);
    handle?.subscription.cancel();
    try {
      handle?.channel.sink.close();
    } catch (_) {
      // close may already be in progress
    }
    _subscribedJobs.remove(jobId);
    if (_disposed) {
      return;
    }
    _recordError('Conexión con el backend perdida. Reintentando...');
    _scheduleJobReconnect(jobId);
  }

  void _scheduleJobReconnect(
    String jobId, [
    Duration delay = const Duration(seconds: 2),
  ]) {
    if (_disposed || !backendReady) {
      return;
    }
    final job = _jobs[jobId];
    final manualSubscription = _hasManualSubscription(jobId);
    if (!manualSubscription && (job == null || !_shouldListenToJob(job))) {
      _jobReconnectTimers.remove(jobId)?.cancel();
      return;
    }
    final baseDelay = _jobRetryDelays[jobId] ?? _baseJobRetryDelay;
    final effectiveDelay = delay == const Duration(seconds: 2)
        ? baseDelay
        : delay;
    _jobReconnectTimers[jobId]?.cancel();
    _jobReconnectTimers[jobId] = Timer(effectiveDelay, () {
      _jobReconnectTimers.remove(jobId);
      if (_disposed) {
        return;
      }
      final current = _jobs[jobId];
      if (_hasManualSubscription(jobId) ||
          (current != null && _shouldListenToJob(current))) {
        _ensureJobSocket(jobId, force: true);
      }
    });
    _jobRetryDelays[jobId] = _increaseWithBackoff(
      effectiveDelay,
      _maxJobRetryDelay,
      minimum: _baseJobRetryDelay,
    );
  }

  bool _shouldListenToJob(DownloadJobModel job) {
    if (_jobRequiresPlaylistSelection(job)) {
      return true;
    }
    switch (job.status) {
      case DownloadStatus.running:
      case DownloadStatus.starting:
      case DownloadStatus.retrying:
      case DownloadStatus.cancelling:
      case DownloadStatus.pausing:
      case DownloadStatus.queued:
        return true;
      default:
        return false;
    }
  }

  bool _hasManualSubscription(String jobId) {
    return (_manualJobSubscriptions[jobId] ?? 0) > 0;
  }

  void _handleJobProgress(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final jobId = payload['job_id'] as String?;
    if (jobId == null) {
      return;
    }
    final existing = _jobs[jobId];
    if (existing == null) {
      if (!_jobsBeingFetched.contains(jobId)) {
        unawaited(_refreshSingleJob(jobId));
      }
      return;
    }
    final progress = DownloadProgress.fromJson(payload.cast<String, dynamic>());
    final updatedJob = existing.applyProgress(progress);
    _cacheJob(updatedJob);
    _afterJobMutation(jobId, previous: existing, updated: updatedJob);
    notifyListeners();
  }

  void _handlePlaylistSnapshot(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final data = payload.cast<String, dynamic>();
    final jobId = data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      return;
    }
    final rawPlaylist = data['playlist'];
    if (rawPlaylist is! Map) {
      return;
    }
    final summary = DownloadPlaylistSummary.fromJson(
      rawPlaylist.cast<String, dynamic>(),
    );
    DownloadStatus? status;
    final statusRaw = data['status'] as String?;
    if (statusRaw != null && statusRaw.isNotEmpty) {
      status = downloadStatusFromString(statusRaw);
    }
    _applyPlaylistUpdate(jobId, summary, status: status);
  }

  void _handlePlaylistProgress(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final data = payload.cast<String, dynamic>();
    final jobId = data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      return;
    }
    final summary = DownloadPlaylistSummary.fromProgressEvent(data);
    if (summary == null) {
      return;
    }
    DownloadStatus? status;
    final statusRaw = data['status'] as String?;
    if (statusRaw != null && statusRaw.isNotEmpty) {
      status = downloadStatusFromString(statusRaw);
    }
    _applyPlaylistUpdate(jobId, summary, status: status);
  }

  void _handleGlobalInfoEvent(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final data = payload.cast<String, dynamic>();
    final jobId = data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      return;
    }

    final metadata = <String, dynamic>{};
    final isPlaylist = _coerceBool(data['is_playlist']);
    if (isPlaylist != null) {
      metadata['is_playlist'] = isPlaylist;
    }
    final selectionRequired = _coerceBool(data['selection_required']);
    if (selectionRequired != null) {
      metadata['requires_playlist_selection'] = selectionRequired;
    }
    final preview = data['preview'];
    if (preview is Map) {
      metadata['preview'] = Map<String, dynamic>.from(
        preview.cast<String, dynamic>(),
      );
    }
    final playlist = data['playlist'];
    Map<String, dynamic>? playlistData;
    if (playlist is Map) {
      playlistData = Map<String, dynamic>.from(
        playlist.cast<String, dynamic>(),
      );
      metadata['playlist'] = playlistData;
    }

    final progress = <String, dynamic>{};
    final playlistTotal = _parseInt(data['playlist_total_items']);
    if (playlistTotal != null) {
      progress['playlist_total_items'] = playlistTotal;
    }

    final updatePayload = <String, dynamic>{'job_id': jobId};
    final status = data['status'] as String?;
    if (status != null && status.isNotEmpty) {
      updatePayload['status'] = status;
    }
    final kind = data['kind'] as String?;
    if (kind != null && kind.isNotEmpty) {
      updatePayload['kind'] = kind;
    }
    final reason = data['reason'] as String?;
    if (reason != null && reason.isNotEmpty) {
      updatePayload['reason'] = reason;
    }
    if (data.containsKey('error')) {
      updatePayload['error'] = data['error'];
    }
    if (metadata.isNotEmpty) {
      updatePayload['metadata'] = metadata;
    }
    if (playlistData != null) {
      updatePayload['playlist'] = playlistData;
    }
    if (progress.isNotEmpty) {
      updatePayload['progress'] = progress;
    }

    if (updatePayload.length <= 1) {
      return;
    }

    _handleUpdateEvent(updatePayload, fromOverview: false);
  }

  void _handleEntryInfoEvent(dynamic payload) {
    _handlePlaylistPreviewEntry(payload);
  }

  void _handleListInfoEnds(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final data = payload.cast<String, dynamic>();
    final jobId = data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      return;
    }
    final job = _jobs[jobId];
    if (job == null) {
      if (!_jobsBeingFetched.contains(jobId)) {
        unawaited(_refreshSingleJob(jobId));
      }
      return;
    }

    final metadataCopy = Map<String, dynamic>.from(job.metadata);
    final playlistMetadata = _cloneStringKeyedMap(metadataCopy['playlist']);
    if (_jobHasPersistedPlaylistSelection(job, playlistMetadata)) {
      return;
    }

    final rawEntries = data['entries'];
    if (rawEntries is! List) {
      return;
    }
    final parsedEntries = rawEntries
        .whereType<Map>()
        .map(
          (entry) => Map<String, dynamic>.from(entry.cast<String, dynamic>()),
        )
        .toList();

    for (final entry in parsedEntries) {
      final index = _parseInt(entry['index']);
      if (index != null) {
        entry['index'] = index;
      }
    }
    parsedEntries.sort((a, b) {
      final aIndex = _parseInt(a['index']) ?? 0;
      final bIndex = _parseInt(b['index']) ?? 0;
      return aIndex.compareTo(bIndex);
    });

    playlistMetadata['entries'] = List<Map<String, dynamic>>.unmodifiable(
      parsedEntries,
    );
    playlistMetadata['is_collecting_entries'] = false;

    final entryCount = _parseInt(data['entry_count']);
    if (entryCount != null && entryCount > 0) {
      playlistMetadata['entry_count'] = entryCount;
      final totalItems = _parseInt(playlistMetadata['total_items']);
      if (totalItems == null || totalItems <= 0) {
        playlistMetadata['total_items'] = entryCount;
      }
    }

    final receivedCount = parsedEntries.length;
    playlistMetadata['received_count'] = receivedCount;

    final errorMessage = data['error'];
    if (errorMessage is String && errorMessage.trim().isNotEmpty) {
      playlistMetadata['collection_error'] = errorMessage.trim();
    } else {
      playlistMetadata.remove('collection_error');
    }

    metadataCopy['playlist'] = Map<String, dynamic>.unmodifiable(
      playlistMetadata,
    );
    final updatedMetadata = Map<String, dynamic>.unmodifiable(metadataCopy);

    var updatedJob = job;
    var changed = false;
    if (!mapEquals(job.metadata, updatedMetadata)) {
      updatedJob = updatedJob.copyWith(metadata: updatedMetadata);
      changed = true;
    }

    DownloadPlaylistSummary? summary;
    try {
      summary = DownloadPlaylistSummary.fromJson(
        playlistMetadata.cast<String, dynamic>(),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to parse playlist summary from list_info_ends: $error',
      );
      debugPrint(stackTrace.toString());
    }

    if (summary != null) {
      final merged = updatedJob.playlist == null
          ? summary
          : updatedJob.playlist!.merge(summary);
      if (_playlistSummariesDiffer(updatedJob.playlist, merged)) {
        updatedJob = updatedJob.copyWith(playlist: merged);
        changed = true;
      }
    }

    if (changed) {
      _cacheJob(updatedJob);
      notifyListeners();
    }
  }

  void _handlePlaylistPreviewEntry(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final data = payload.cast<String, dynamic>();
    final jobId = data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      return;
    }
    final rawEntry = data['entry'];
    if (rawEntry is! Map) {
      return;
    }
    final job = _jobs[jobId];
    if (job == null) {
      if (!_jobsBeingFetched.contains(jobId)) {
        unawaited(_refreshSingleJob(jobId));
      }
      return;
    }

    final entryMap = Map<String, dynamic>.from(
      rawEntry.cast<String, dynamic>(),
    );
    final entryIndex = _parseInt(data['index']) ?? _parseInt(entryMap['index']);
    if (entryIndex == null || entryIndex <= 0) {
      return;
    }
    entryMap['index'] = entryIndex;

    final metadataCopy = Map<String, dynamic>.from(job.metadata);
    final playlistRaw = metadataCopy['playlist'];
    final playlistMetadata = playlistRaw is Map<String, dynamic>
        ? Map<String, dynamic>.from(playlistRaw)
        : <String, dynamic>{};

    if (_jobHasPersistedPlaylistSelection(job, playlistMetadata)) {
      return;
    }

    var entriesChanged = playlistRaw is! Map<String, dynamic>;
    final existingEntriesRaw = playlistMetadata['entries'];
    final entries = existingEntriesRaw is List
        ? existingEntriesRaw
              .whereType<Map>()
              .map(
                (item) =>
                    Map<String, dynamic>.from(item.cast<String, dynamic>()),
              )
              .toList()
        : <Map<String, dynamic>>[];

    final existingIndex = entries.indexWhere((item) {
      final index = _parseInt(item['index']);
      return index != null && index == entryIndex;
    });

    if (existingIndex >= 0) {
      final previous = entries[existingIndex];
      if (!mapEquals(previous, entryMap)) {
        entries[existingIndex] = entryMap;
        entriesChanged = true;
      }
    } else {
      entries.add(entryMap);
      entriesChanged = true;
    }

    entries.sort((a, b) {
      final aIndex = _parseInt(a['index']) ?? 0;
      final bIndex = _parseInt(b['index']) ?? 0;
      return aIndex.compareTo(bIndex);
    });

    var countsChanged = false;
    final entryCount = _parseInt(data['entry_count']);
    if (entryCount != null && entryCount > 0) {
      if (_parseInt(playlistMetadata['entry_count']) != entryCount) {
        playlistMetadata['entry_count'] = entryCount;
        countsChanged = true;
      }
      final currentTotal = _parseInt(playlistMetadata['total_items']);
      if (currentTotal == null || currentTotal <= 0) {
        playlistMetadata['total_items'] = entryCount;
        countsChanged = true;
      }
    }

    final receivedCount = _parseInt(data['received_count']);
    final effectiveReceived = receivedCount != null && receivedCount > 0
        ? receivedCount
        : entries.length;
    if (_parseInt(playlistMetadata['received_count']) != effectiveReceived) {
      playlistMetadata['received_count'] = effectiveReceived;
      countsChanged = true;
    }

    if (!entriesChanged && !countsChanged) {
      return;
    }

    playlistMetadata['entries'] = List<Map<String, dynamic>>.unmodifiable(
      entries,
    );
    metadataCopy['playlist'] = Map<String, dynamic>.unmodifiable(
      playlistMetadata,
    );

    final snapshotInFlight = _activePlaylistSelectionJobId == jobId;
    final updatedJob = job.copyWith(
      metadata: Map<String, dynamic>.unmodifiable(metadataCopy),
    );
    _cacheJob(updatedJob);
    if (!snapshotInFlight) {
      notifyListeners();
    }
  }

  void _handlePlaylistEntryProgress(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final data = payload.cast<String, dynamic>();
    final jobId = data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      return;
    }
    final entryIndex =
        _parseInt(data['playlist_index']) ??
        _parseInt(data['entry_index']) ??
        _parseInt(data['index']);
    if (entryIndex == null || entryIndex <= 0) {
      return;
    }

    final job = _jobs[jobId];
    if (job == null) {
      if (!_jobsBeingFetched.contains(jobId)) {
        unawaited(_refreshSingleJob(jobId));
      }
      return;
    }

    final entryPayload = _buildPlaylistEntryProgressEntry(
      job,
      data,
      entryIndex,
    );
    if (entryPayload == null) {
      return;
    }

    final syntheticPayload = <String, dynamic>{
      'job_id': jobId,
      'entry': entryPayload,
    };
    final entryCount = _parseInt(data['entry_count']);
    if (entryCount != null) {
      syntheticPayload['entry_count'] = entryCount;
    }
    final receivedCount = _parseInt(data['received_count']);
    if (receivedCount != null) {
      syntheticPayload['received_count'] = receivedCount;
    }
    _handlePlaylistPreviewEntry(syntheticPayload);

    final summaryPayload = <String, dynamic>{};
    if (entryPayload['is_completed'] == true) {
      summaryPayload['completed_indices'] = <int>[entryIndex];
    }
    if (entryPayload['is_current'] == true) {
      summaryPayload['current_index'] = entryIndex;
      final entryId = entryPayload['id'];
      if (entryId is String && entryId.isNotEmpty) {
        summaryPayload['current_entry_id'] = entryId;
      }
    }

    if (summaryPayload.isEmpty) {
      return;
    }

    try {
      final summary = DownloadPlaylistSummary.fromJson(
        summaryPayload.cast<String, dynamic>(),
      );
      _applyPlaylistUpdate(jobId, summary);
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to parse playlist entry progress for job $jobId: $error',
      );
      debugPrint(stackTrace.toString());
    }
  }

  bool _playlistSummariesDiffer(
    DownloadPlaylistSummary? previous,
    DownloadPlaylistSummary next,
  ) {
    if (previous == null) {
      return true;
    }
    const tolerance = 0.0001;

    bool percentsEqual(double? a, double? b) {
      if (a == null && b == null) {
        return true;
      }
      if (a == null || b == null) {
        return false;
      }
      return (a - b).abs() < tolerance;
    }

    bool indicesEqual(List<int>? a, List<int>? b) {
      if (a == null && b == null) {
        return true;
      }
      if (a == null || b == null) {
        return false;
      }
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          return false;
        }
      }
      return true;
    }

    if (previous.id != next.id || previous.title != next.title) {
      return true;
    }
    if (previous.entryCount != next.entryCount ||
        previous.totalItems != next.totalItems ||
        previous.completedItems != next.completedItems ||
        previous.pendingItems != next.pendingItems) {
      return true;
    }
    if (!percentsEqual(previous.percent, next.percent)) {
      return true;
    }
    if (previous.currentIndex != next.currentIndex ||
        previous.currentEntryId != next.currentEntryId) {
      return true;
    }
    if (previous.entries.length != next.entries.length) {
      return true;
    }
    if (previous.entryRefs.length != next.entryRefs.length) {
      return true;
    }
    if (!indicesEqual(previous.completedIndices, next.completedIndices)) {
      return true;
    }
    if (!indicesEqual(previous.failedIndices, next.failedIndices)) {
      return true;
    }
    if (!indicesEqual(previous.pendingRetryIndices, next.pendingRetryIndices)) {
      return true;
    }

    bool entryErrorsEqual(
      List<DownloadPlaylistEntryError> a,
      List<DownloadPlaylistEntryError> b,
    ) {
      if (identical(a, b)) {
        return true;
      }
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i++) {
        final left = a[i];
        final right = b[i];
        if (left.index != right.index ||
            left.entryId != right.entryId ||
            left.url != right.url ||
            left.message != right.message ||
            left.pendingRetry != right.pendingRetry ||
            left.lastStatus != right.lastStatus) {
          return false;
        }
        final leftTimestamp = left.recordedAt?.toUtc();
        final rightTimestamp = right.recordedAt?.toUtc();
        if (leftTimestamp != rightTimestamp) {
          return false;
        }
      }
      return true;
    }

    if (!entryErrorsEqual(previous.entryErrors, next.entryErrors)) {
      return true;
    }

    return false;
  }

  void _applyPlaylistUpdate(
    String jobId,
    DownloadPlaylistSummary summary, {
    DownloadStatus? status,
    bool notify = true,
  }) {
    final existing = _jobs[jobId];
    if (existing == null) {
      if (!_jobsBeingFetched.contains(jobId)) {
        unawaited(_refreshSingleJob(jobId));
      }
      return;
    }
    final mergedPlaylist = existing.playlist == null
        ? summary
        : existing.playlist!.merge(summary);
    final playlistChanged = _playlistSummariesDiffer(
      existing.playlist,
      mergedPlaylist,
    );
    final statusChanged = status != null && status != existing.status;
    if (!playlistChanged && !statusChanged) {
      return;
    }
    final updated = statusChanged
        ? existing.copyWith(status: status, playlist: mergedPlaylist)
        : existing.copyWith(playlist: mergedPlaylist);
    _cacheJob(updated);
    if (notify) {
      notifyListeners();
    }
  }

  void _applyPlaylistRetryResponse(
    String jobId,
    Map<String, dynamic> response,
  ) {
    if (_disposed) {
      return;
    }
    final pending = _coerceIntList(response['pending_indices']);
    if (pending.isEmpty) {
      return;
    }
    final summary = DownloadPlaylistSummary(
      pendingRetryIndices: List<int>.unmodifiable(pending),
    );
    _applyPlaylistUpdate(jobId, summary);
  }

  List<int> _collectRetryablePlaylistIndices(DownloadPlaylistSummary? summary) {
    if (summary == null) {
      return const <int>[];
    }
    final candidates = <int>{};
    final failed = summary.failedIndices;
    if (failed != null && failed.isNotEmpty) {
      for (final index in failed) {
        if (index > 0) {
          candidates.add(index);
        }
      }
    }
    for (final error in summary.entryErrors) {
      if (error.index > 0) {
        candidates.add(error.index);
      }
    }
    if (candidates.isEmpty) {
      return const <int>[];
    }
    final pending = summary.pendingRetryIndices;
    if (pending != null && pending.isNotEmpty) {
      final pendingSet = <int>{};
      for (final index in pending) {
        if (index > 0) {
          pendingSet.add(index);
        }
      }
      if (pendingSet.isNotEmpty) {
        candidates.removeWhere(pendingSet.contains);
      }
    }
    if (candidates.isEmpty) {
      return const <int>[];
    }
    final ordered = candidates.toList()..sort();
    return List<int>.unmodifiable(ordered);
  }

  bool _jobRequiresPlaylistSelection(DownloadJobModel job) {
    if (job.isTerminal) {
      return false;
    }
    Map<String, dynamic>? playlistMetadata;
    final rawPlaylist = job.metadata['playlist'];
    if (rawPlaylist is Map<String, dynamic>) {
      playlistMetadata = rawPlaylist;
    } else if (rawPlaylist is Map) {
      try {
        playlistMetadata = rawPlaylist.cast<String, dynamic>();
      } catch (_) {
        playlistMetadata = null;
      }
    }

    if (_jobHasPersistedPlaylistSelection(job, playlistMetadata)) {
      return false;
    }

    final explicit = _coerceBool(job.metadata['requires_playlist_selection']);
    if (explicit != null) {
      return explicit;
    }
    var playlistLikely = job.isPlaylist;
    if (!playlistLikely) {
      final optionsPlaylistFlag = _coerceBool(job.options['playlist']);
      final metadataPlaylist = job.metadata['playlist'];
      final metadataSuggestsPlaylist =
          metadataPlaylist is Map && metadataPlaylist.isNotEmpty;
      final progressSuggestsPlaylist =
          job.progress?.hasPlaylistMetrics ?? false;
      playlistLikely =
          (optionsPlaylistFlag ?? false) ||
          metadataSuggestsPlaylist ||
          progressSuggestsPlaylist;
    }
    if (!playlistLikely) {
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
      inferredCount ??= _coerceInt(
        playlistMetadata['entry_count'] ?? playlistMetadata['total_items'],
      );
      inferredCount ??= _coerceInt(job.metadata['playlist_entry_count']);
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

    if (_jobIsCollectingPlaylistEntries(job)) {
      return true;
    }

    return false;
  }

  bool _jobHasPersistedPlaylistSelection(
    DownloadJobModel job,
    Map<String, dynamic>? playlistMetadata,
  ) {
    final hint = job.metadata['requires_playlist_selection'];
    final hintValue = _coerceBool(hint);
    if (hintValue == false) {
      return true;
    }
    if (_playlistSelectionConfigured(job.options['playlist_items'])) {
      return true;
    }
    if (playlistMetadata != null && playlistMetadata.isNotEmpty) {
      final selected = _coerceIntList(playlistMetadata['selected_indices']);
      if (selected.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  bool _jobIsCollectingPlaylistEntries(DownloadJobModel job) {
    final playlistMetadata = _cloneStringKeyedMap(job.metadata['playlist']);
    final summary = job.playlist;
    final progress = job.progress;

    String? collectionErrorFrom(Object? value) {
      return _parseNonEmptyString(value);
    }

    final collectionError =
        collectionErrorFrom(playlistMetadata['collection_error']) ??
        collectionErrorFrom(job.metadata['collection_error']);
    if (collectionError != null) {
      return false;
    }

    final bool metadataCompleteFlag =
        playlistMetadata.containsKey('collection_complete')
        ? (_coerceBool(playlistMetadata['collection_complete']) ?? false)
        : false;
    if (metadataCompleteFlag) {
      return false;
    }
    if (summary?.collectionComplete == true) {
      return false;
    }

    final metadataEntriesRaw = playlistMetadata['entries'];
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
        playlistMetadata.containsKey('has_indefinite_length')
        ? (_coerceBool(playlistMetadata['has_indefinite_length']) ?? false)
        : false;
    final bool hasIndefiniteLength =
        metadataIndefiniteFlag || summary?.hasIndefiniteLength == true;
    final bool indefiniteAwaiting =
        hasIndefiniteLength && !metadataCompleteFlag;

    final bool? metadataCollectingFlag =
        playlistMetadata.containsKey('is_collecting_entries')
        ? _coerceBool(playlistMetadata['is_collecting_entries'])
        : null;
    if (metadataCollectingFlag != null) {
      return metadataCollectingFlag;
    }
    final bool? summaryCollectingFlag = summary?.isCollectingEntries;
    if (summaryCollectingFlag != null) {
      return summaryCollectingFlag;
    }

    int? totalItems = _coerceInt(
      playlistMetadata['total_items'] ?? playlistMetadata['entry_count'],
    );
    totalItems ??= summary?.totalItems ?? summary?.entryCount;
    totalItems ??= progress?.playlistTotalItems ?? progress?.playlistCount;

    int? receivedItems = _coerceInt(playlistMetadata['received_count']);
    receivedItems ??= summary?.completedItems;
    receivedItems ??= progress?.playlistCompletedItems;

    final pendingItems = progress?.playlistPendingItems;
    if (pendingItems != null) {
      final pendingPositive = pendingItems > 0;
      if (!pendingPositive) {
        if (totalItems != null && totalItems > 0) {
          receivedItems ??= totalItems;
        }
      } else if (totalItems == null || receivedItems == null) {
        return true;
      }
    }

    if (receivedItems == null && pendingItems != null && totalItems != null) {
      receivedItems = math.max(totalItems - pendingItems, 0);
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

  String? _parseNonEmptyString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  bool? _coerceBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      if (value == 0) {
        return false;
      }
      if (value == 1) {
        return true;
      }
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) {
        return null;
      }
      if (normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'on') {
        return true;
      }
      if (normalized == 'false' ||
          normalized == '0' ||
          normalized == 'no' ||
          normalized == 'off') {
        return false;
      }
    }
    return null;
  }

  int? _coerceInt(Object? value) {
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

  List<int> _coerceIntList(Object? value) {
    if (value is Iterable) {
      final indices = <int>[];
      for (final entry in value) {
        final parsed = _coerceInt(entry);
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
      final parts = trimmed.split(RegExp(r'[\s,]+'));
      final indices = <int>[];
      for (final part in parts) {
        if (part.isEmpty) {
          continue;
        }
        final parsed = int.tryParse(part);
        if (parsed != null && parsed > 0) {
          indices.add(parsed);
        }
      }
      return indices;
    }
    final single = _coerceInt(value);
    if (single != null && single > 0) {
      return <int>[single];
    }
    return const <int>[];
  }

  bool _playlistSelectionConfigured(Object? value) {
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
        final parsed = _coerceInt(entry);
        if (parsed != null && parsed > 0) {
          return true;
        }
      }
      return false;
    }
    return false;
  }

  bool _updatePlaylistSelectionTracking(String jobId, DownloadJobModel? job) {
    final jobModel = job;
    final requiresSelection =
        jobModel != null && _jobRequiresPlaylistSelection(jobModel);
    if (!requiresSelection) {
      final removedQueued = _queuedPlaylistSelections.remove(jobId);
      final removedPending = _removePendingPlaylistRequest(jobId);
      if (_activePlaylistSelectionJobId == jobId) {
        _activePlaylistSelectionJobId = null;
      }
      final removedAttention = _cancelPlaylistAttention(jobId);
      return removedQueued || removedPending || removedAttention;
    }
    final addedQueued = _queuedPlaylistSelections.add(jobId);
    var addedPending = false;
    if (!_pendingPlaylistSelectionQueue.contains(jobId)) {
      _pendingPlaylistSelectionQueue.add(jobId);
      addedPending = true;
    }
    if (addedQueued) {
      _notifyPlaylistSelectionAttention(jobModel);
    }
    return addedQueued || addedPending;
  }

  void _notifyPlaylistSelectionAttention(DownloadJobModel? job) {
    if (job == null) {
      return;
    }
    _maybeAlertPlaylistSelection(job);
  }

  bool _cancelPlaylistAttention(String jobId) {
    final removed = _playlistAttentionNotified.remove(jobId);
    if (removed) {
      final notificationManager = _notificationManager;
      if (notificationManager != null) {
        unawaited(notificationManager.dismissPlaylistSelectionAttention(jobId));
      }
    }
    return removed;
  }

  void _handleLifecycleStateChanged() {
    if (_disposed) {
      return;
    }
    final observer = _appLifecycleObserver;
    if (observer == null) {
      return;
    }
    if (observer.isForeground) {
      final pending = _playlistAttentionNotified.toList(growable: false);
      for (final jobId in pending) {
        _cancelPlaylistAttention(jobId);
      }
      return;
    }
    for (final jobId in _queuedPlaylistSelections) {
      final job = _jobs[jobId];
      if (job == null) {
        continue;
      }
      _maybeAlertPlaylistSelection(job);
    }
  }

  void _maybeAlertPlaylistSelection(DownloadJobModel job) {
    final observer = _appLifecycleObserver;
    if (observer == null || observer.isForeground) {
      _cancelPlaylistAttention(job.id);
      return;
    }
    final notificationManager = _notificationManager;
    if (notificationManager == null) {
      return;
    }
    if (!_playlistAttentionNotified.add(job.id)) {
      return;
    }
    unawaited(notificationManager.showPlaylistSelectionAttention(job));
  }

  void _handleLogEvent(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final jobId = payload['job_id'] as String?;
    if (jobId == null) {
      return;
    }
    final existing = _jobs[jobId];
    if (existing == null) {
      if (!_jobsBeingFetched.contains(jobId)) {
        unawaited(_refreshSingleJob(jobId));
      }
      return;
    }
    final entry = DownloadLogEntry.fromJson(payload.cast<String, dynamic>());
    final updatedLogs = List<DownloadLogEntry>.from(existing.logs)..add(entry);
    if (updatedLogs.length > 200) {
      updatedLogs.removeRange(0, updatedLogs.length - 200);
    }
    final updatedJob = existing.copyWith(logs: updatedLogs);
    _cacheJob(updatedJob);
    notifyListeners();
  }

  void _handleUpdateEvent(dynamic payload, {required bool fromOverview}) {
    if (payload is! Map) {
      return;
    }
    final data = payload.cast<String, dynamic>();
    final jobId = data['job_id'] as String?;
    final reason = data['reason'] as String?;
    if (jobId == null || jobId.isEmpty) {
      unawaited(refreshJobs());
      return;
    }

    final normalizedReason = reason?.toLowerCase();
    if (normalizedReason == BackendJobUpdateReason.deleted) {
      final removed = _jobs.remove(jobId);
      if (removed != null) {
        _markJobsViewDirty();
      }
      if (removed != null) {
        _removeJobFromOrdering(jobId);
      }
      final queueChanged = _updatePlaylistSelectionTracking(jobId, null);
      _closeJobSocket(jobId);
      _jobsBeingFetched.remove(jobId);
      var shouldNotify = queueChanged;
      if (removed != null) {
        _syncJobSubscriptions();
        shouldNotify = true;
      }
      final notificationManager = _notificationManager;
      if (notificationManager != null) {
        unawaited(notificationManager.handleJobRemoved(jobId));
      }
      if (shouldNotify) {
        notifyListeners();
      }
      return;
    }

    final statusRaw = data['status'] as String?;
    final error = data['error'] as String?;
    final hasErrorKey = data.containsKey('error');

    final existing = _jobs[jobId];
    DownloadJobModel? parsedJob;
    var parsedCreatedAtProvided = data.containsKey('created_at');
    try {
      parsedJob = DownloadJobModel.fromJson(data);
    } catch (error, stackTrace) {
      debugPrint('Failed to parse job update for $jobId: $error');
      debugPrint(stackTrace.toString());
    }

    var changed = false;
    bool queueChanged = false;
    if (parsedJob != null) {
      if (!parsedCreatedAtProvided && existing != null) {
        parsedJob = parsedJob.copyWith(createdAt: existing.createdAt);
      }
      final merged = existing == null ? parsedJob : existing.merge(parsedJob);
      _cacheJob(merged);
      _afterJobMutation(
        jobId,
        previous: existing,
        updated: merged,
        optionsProvided: parsedJob.options.isNotEmpty,
        logsProvided: parsedJob.logs.isNotEmpty,
      );
      changed = true;
      queueChanged = _updatePlaylistSelectionTracking(jobId, merged);
    } else if (existing != null && (statusRaw != null || hasErrorKey)) {
      final status = statusRaw != null
          ? downloadStatusFromString(statusRaw)
          : DownloadStatus.unknown;
      final resolvedStatus = status != DownloadStatus.unknown
          ? status
          : existing.status;
      final resolvedError = hasErrorKey ? error : existing.error;
      if (resolvedStatus != existing.status ||
          resolvedError != existing.error) {
        final updatedJob = existing.copyWith(
          status: resolvedStatus,
          error: resolvedError,
        );
        _cacheJob(updatedJob);
        changed = true;
        queueChanged = _updatePlaylistSelectionTracking(jobId, updatedJob);
      }
    } else if (existing != null) {
      queueChanged = _updatePlaylistSelectionTracking(jobId, existing);
    }

    if (changed || queueChanged) {
      _syncJobSubscriptions();
      notifyListeners();
      return;
    }

    if (fromOverview || existing == null) {
      unawaited(_refreshSingleJob(jobId));
    }
  }

  Future<void> _refreshSingleJob(String jobId) async {
    if (!backendReady) {
      return;
    }
    if (!_jobsBeingFetched.add(jobId)) {
      return;
    }
    try {
      final job = await _service.getJob(jobId);
      var queueChanged = false;
      var stateChanged = false;
      if (job == null) {
        final removed = _jobs.remove(jobId);
        if (removed != null) {
          _markJobsViewDirty();
        }
        _closeJobSocket(jobId);
        queueChanged = _updatePlaylistSelectionTracking(jobId, null);
        stateChanged = removed != null;
        if (removed != null) {
          _removeJobFromOrdering(jobId);
        }
        final notificationManager = _notificationManager;
        if (notificationManager != null) {
          unawaited(notificationManager.handleJobRemoved(jobId));
        }
      } else {
        final existing = _jobs[jobId];
        final merged = existing != null ? existing.merge(job) : job;
        _cacheJob(merged);
        _afterJobMutation(
          jobId,
          previous: existing,
          updated: merged,
          optionsProvided: job.options.isNotEmpty,
          logsProvided: job.logs.isNotEmpty,
        );
        queueChanged = _updatePlaylistSelectionTracking(jobId, merged);
        stateChanged = true;
      }
      if (stateChanged || queueChanged) {
        _syncJobSubscriptions();
        notifyListeners();
      }
    } on DownloadServiceConnectionException catch (error) {
      _handleConnectionException('Actualización puntual de $jobId', error);
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('Failed to refresh job $jobId: $error');
      debugPrint(stackTrace.toString());
      notifyListeners();
    } finally {
      _jobsBeingFetched.remove(jobId);
    }
  }

  Future<void> _ensureJobCached(String jobId) async {
    if (_disposed) {
      return;
    }
    final normalizedId = jobId.trim();
    if (normalizedId.isEmpty) {
      return;
    }
    if (_jobs.containsKey(normalizedId)) {
      return;
    }
    if (_jobsBeingFetched.contains(normalizedId)) {
      return;
    }
    await _refreshSingleJob(normalizedId);
  }

  void _afterJobMutation(
    String jobId, {
    DownloadJobModel? previous,
    required DownloadJobModel updated,
    bool optionsProvided = false,
    bool logsProvided = false,
  }) {
    if (_disposed) {
      return;
    }
    _maybeHydrateJobOptions(
      jobId,
      previous: previous,
      updated: updated,
      optionsProvided: optionsProvided,
    );
    _maybeHydrateJobLogs(
      jobId,
      previous: previous,
      updated: updated,
      logsProvided: logsProvided,
    );
    _maybeHydratePlaylistEntries(jobId, previous: previous, updated: updated);
    final notificationManager = _notificationManager;
    if (notificationManager != null) {
      final playlistSelectionPending = _queuedPlaylistSelections.contains(
        jobId,
      );
      unawaited(
        notificationManager.handleJobUpdated(
          updated,
          previous: previous,
          playlistSelectionPending: playlistSelectionPending,
        ),
      );
    }
  }

  Future<bool> _handleNotificationRetry(String jobId) async {
    if (_disposed) {
      return false;
    }
    final normalizedId = jobId.trim();
    if (normalizedId.isEmpty) {
      return false;
    }
    await _ensureJobCached(normalizedId);
    if (_disposed) {
      return false;
    }
    final job = _jobs[normalizedId];
    if (job == null || job.status != DownloadStatus.failed) {
      return false;
    }
    return retryJob(normalizedId);
  }

  void _maybeHydrateJobOptions(
    String jobId, {
    DownloadJobModel? previous,
    required DownloadJobModel updated,
    required bool optionsProvided,
  }) {
    if (!updated.optionsExternal || optionsProvided) {
      return;
    }
    final missingInline = updated.options.isEmpty;
    final versionChanged =
        updated.optionsVersion != null &&
        updated.optionsVersion != previous?.optionsVersion;
    if (!missingInline && !versionChanged) {
      return;
    }
    unawaited(
      loadJobOptions(
        jobId,
        forceRefresh: versionChanged,
        expectedVersion: versionChanged ? previous?.optionsVersion : null,
      ),
    );
  }

  void _maybeHydrateJobLogs(
    String jobId, {
    DownloadJobModel? previous,
    required DownloadJobModel updated,
    required bool logsProvided,
  }) {
    if (!updated.logsExternal || logsProvided) {
      return;
    }
    final missingInline = updated.logs.isEmpty;
    final versionChanged =
        updated.logsVersion != null &&
        updated.logsVersion != previous?.logsVersion;
    if (!missingInline && !versionChanged) {
      return;
    }
    unawaited(
      loadJobLogs(
        jobId,
        forceRefresh: versionChanged,
        expectedVersion: versionChanged ? previous?.logsVersion : null,
        limit: _maxPersistedLogs,
        silent: true,
      ),
    );
  }

  void _maybeHydratePlaylistEntries(
    String jobId, {
    DownloadJobModel? previous,
    required DownloadJobModel updated,
  }) {
    final playlist = updated.playlist;
    if (playlist == null || !playlist.entriesExternal) {
      return;
    }
    final previousPlaylist = previous?.playlist;
    final missingEntries = playlist.entries.isEmpty;
    final versionChanged =
        playlist.entriesVersion != previousPlaylist?.entriesVersion;
    if (!missingEntries && !versionChanged) {
      return;
    }
    final sinceVersion = missingEntries
        ? null
        : previousPlaylist?.entriesVersion;
    unawaited(_fetchPlaylistEntriesSnapshot(jobId, sinceVersion: sinceVersion));
  }

  Future<Map<String, dynamic>> _fetchJobOptionsSnapshot(
    String jobId, {
    int? sinceVersion,
  }) {
    final inFlight = _pendingOptionsFetches[jobId];
    if (inFlight != null) {
      return inFlight;
    }
    final future = _doFetchJobOptionsSnapshot(jobId, sinceVersion: sinceVersion)
        .whenComplete(() {
          _pendingOptionsFetches.remove(jobId);
        });
    _pendingOptionsFetches[jobId] = future;
    return future;
  }

  Future<Map<String, dynamic>> _doFetchJobOptionsSnapshot(
    String jobId, {
    int? sinceVersion,
  }) async {
    if (_disposed) {
      return const <String, dynamic>{};
    }
    if (!_ensureBackendReady('cargar las opciones del trabajo', silent: true)) {
      return _jobs[jobId]?.options ?? const <String, dynamic>{};
    }
    try {
      final snapshot = await _service.fetchJobOptions(
        jobId,
        sinceVersion: sinceVersion,
        includeOptions: true,
      );
      if (snapshot == null) {
        return _jobs[jobId]?.options ?? const <String, dynamic>{};
      }
      final targetId = snapshot.jobId.isNotEmpty ? snapshot.jobId : jobId;
      final job = _jobs[targetId];
      if (job == null) {
        return snapshot.options;
      }
      final resolvedOptions = snapshot.hasOptions
          ? snapshot.options
          : job.options;
      final updated = job.copyWith(
        options: resolvedOptions,
        optionsVersion: snapshot.version ?? job.optionsVersion,
        optionsExternal: snapshot.external || job.optionsExternal,
      );
      final changed =
          !mapEquals(job.options, updated.options) ||
          job.optionsVersion != updated.optionsVersion ||
          job.optionsExternal != updated.optionsExternal;
      if (changed) {
        _cacheJob(updated);
        notifyListeners();
      }
      return updated.options;
    } catch (error, stackTrace) {
      if (error is DownloadServiceConnectionException) {
        _handleConnectionException('Opciones de $jobId', error);
      } else {
        _lastError = error.toString();
        debugPrint('Failed to load options for $jobId: $error');
        debugPrint(stackTrace.toString());
        notifyListeners();
      }
      return _jobs[jobId]?.options ?? const <String, dynamic>{};
    }
  }

  Future<List<DownloadLogEntry>> _fetchJobLogsSnapshot(
    String jobId, {
    int? sinceVersion,
    int? limit,
    bool silent = false,
  }) {
    final inFlight = _pendingLogsFetches[jobId];
    if (inFlight != null) {
      return inFlight;
    }
    final future =
        _doFetchJobLogsSnapshot(
          jobId,
          sinceVersion: sinceVersion,
          limit: limit ?? _maxPersistedLogs,
          silent: silent,
        ).whenComplete(() {
          _pendingLogsFetches.remove(jobId);
        });
    _pendingLogsFetches[jobId] = future;
    return future;
  }

  Future<List<DownloadLogEntry>> _doFetchJobLogsSnapshot(
    String jobId, {
    int? sinceVersion,
    int? limit,
    bool silent = false,
  }) async {
    if (_disposed) {
      return const <DownloadLogEntry>[];
    }
    if (!_ensureBackendReady(
      'cargar los registros del trabajo',
      silent: true,
    )) {
      return _jobs[jobId]?.logs ?? const <DownloadLogEntry>[];
    }
    try {
      final snapshot = await _service.fetchJobLogs(
        jobId,
        sinceVersion: sinceVersion,
        includeLogs: true,
        limit: limit ?? _maxPersistedLogs,
      );
      if (snapshot == null) {
        return _jobs[jobId]?.logs ?? const <DownloadLogEntry>[];
      }
      final targetId = snapshot.jobId.isNotEmpty ? snapshot.jobId : jobId;
      final job = _jobs[targetId];
      if (job == null) {
        return snapshot.logs;
      }
      final delta = snapshot.delta;
      final bool canAppend =
          delta != null &&
          delta.type.toLowerCase() != 'full' &&
          delta.since != null &&
          sinceVersion != null &&
          delta.since == sinceVersion &&
          job.logsVersion == sinceVersion;
      List<DownloadLogEntry> mergedLogs;
      if (snapshot.logs.isEmpty) {
        mergedLogs = job.logs;
      } else if (canAppend && job.logs.isNotEmpty) {
        mergedLogs = List<DownloadLogEntry>.from(job.logs)
          ..addAll(snapshot.logs);
      } else {
        mergedLogs = snapshot.logs;
      }
      if (mergedLogs.length > _maxPersistedLogs) {
        mergedLogs = mergedLogs.sublist(mergedLogs.length - _maxPersistedLogs);
      }
      final updated = job.copyWith(
        logs: mergedLogs,
        logsVersion: snapshot.version ?? job.logsVersion,
        logsExternal: snapshot.external || job.logsExternal,
      );
      final changed =
          !listEquals(job.logs, updated.logs) ||
          job.logsVersion != updated.logsVersion ||
          job.logsExternal != updated.logsExternal;
      if (changed) {
        _cacheJob(updated);
        notifyListeners();
      }
      return updated.logs;
    } catch (error, stackTrace) {
      if (error is DownloadServiceConnectionException) {
        _handleConnectionException('Logs de $jobId', error, silent: silent);
      } else {
        _lastError = error.toString();
        debugPrint('Failed to load logs for $jobId: $error');
        debugPrint(stackTrace.toString());
        notifyListeners();
      }
      return _jobs[jobId]?.logs ?? const <DownloadLogEntry>[];
    }
  }

  String _entryOptionsCacheKey(
    String parentJobId,
    String? entryId,
    int? entryIndex,
  ) {
    final buffer = StringBuffer(parentJobId)..write('::entry-options');
    if (entryId != null && entryId.isNotEmpty) {
      buffer
        ..write('::id=')
        ..write(entryId);
    }
    if (entryIndex != null && entryIndex > 0) {
      buffer
        ..write('::idx=')
        ..write(entryIndex);
    }
    return buffer.toString();
  }

  String _entryLogsCacheKey(
    String parentJobId,
    String? entryId,
    int? entryIndex,
    int limit,
  ) {
    final buffer = StringBuffer(parentJobId)..write('::entry');
    if (entryId != null && entryId.isNotEmpty) {
      buffer
        ..write('::id=')
        ..write(entryId);
    }
    if (entryIndex != null && entryIndex > 0) {
      buffer
        ..write('::idx=')
        ..write(entryIndex);
    }
    buffer
      ..write('::limit=')
      ..write(limit);
    return buffer.toString();
  }

  Future<List<DownloadLogEntry>> _doLoadEntryJobLogs(
    String parentJobId, {
    String? entryId,
    int? entryIndex,
    int? limit,
  }) async {
    if (_disposed) {
      return const <DownloadLogEntry>[];
    }
    if (!_ensureBackendReady(
      'cargar los registros del elemento',
      silent: true,
    )) {
      return const <DownloadLogEntry>[];
    }
    try {
      final snapshot = await _service.fetchJobLogs(
        parentJobId,
        includeLogs: true,
        limit: limit ?? _maxPersistedLogs,
        entryId: entryId,
        entryIndex: entryIndex,
      );
      if (snapshot == null) {
        return const <DownloadLogEntry>[];
      }
      return snapshot.logs;
    } catch (error, stackTrace) {
      if (error is DownloadServiceConnectionException) {
        _handleConnectionException('Logs de $parentJobId (entrada)', error);
      } else {
        _lastError = error.toString();
        debugPrint('Failed to load entry logs for $parentJobId: $error');
        debugPrint(stackTrace.toString());
        notifyListeners();
      }
      return const <DownloadLogEntry>[];
    }
  }

  Future<Map<String, dynamic>> _doLoadEntryJobOptions(
    String parentJobId, {
    String? entryId,
    int? entryIndex,
  }) async {
    if (_disposed) {
      return const <String, dynamic>{};
    }
    if (!_ensureBackendReady(
      'cargar las opciones del elemento',
      silent: true,
    )) {
      return const <String, dynamic>{};
    }
    try {
      final snapshot = await _service.fetchJobOptions(
        parentJobId,
        includeOptions: true,
        entryId: entryId,
        entryIndex: entryIndex,
      );
      if (snapshot == null) {
        return const <String, dynamic>{};
      }
      return snapshot.options;
    } catch (error, stackTrace) {
      if (error is DownloadServiceConnectionException) {
        _handleConnectionException('Opciones de $parentJobId (entrada)', error);
      } else {
        _lastError = error.toString();
        debugPrint('Failed to load entry options for $parentJobId: $error');
        debugPrint(stackTrace.toString());
        notifyListeners();
      }
      return const <String, dynamic>{};
    }
  }

  Future<DownloadPlaylistSummary?> _fetchPlaylistEntriesSnapshot(
    String jobId, {
    int? sinceVersion,
  }) {
    final inFlight = _pendingPlaylistFetches[jobId];
    if (inFlight != null) {
      return inFlight;
    }
    final future =
        _doFetchPlaylistEntriesSnapshot(
          jobId,
          sinceVersion: sinceVersion,
        ).whenComplete(() {
          _pendingPlaylistFetches.remove(jobId);
        });
    _pendingPlaylistFetches[jobId] = future;
    return future;
  }

  Future<DownloadPlaylistSummary?> _doFetchPlaylistEntriesSnapshot(
    String jobId, {
    int? sinceVersion,
  }) async {
    if (_disposed) {
      return _jobs[jobId]?.playlist;
    }
    if (!_ensureBackendReady('cargar la playlist', silent: true)) {
      return _jobs[jobId]?.playlist;
    }
    try {
      final snapshot = await _service.fetchPlaylistDelta(
        jobId,
        sinceVersion: sinceVersion,
      );
      if (snapshot == null) {
        return null;
      }
      final targetId = snapshot.jobId.isNotEmpty ? snapshot.jobId : jobId;
      final delta = snapshot.delta;
      if (delta?.isNoop == true) {
        return _jobs[targetId]?.playlist ?? snapshot.summary;
      }
      if (!_jobs.containsKey(targetId)) {
        return snapshot.summary;
      }
      final before = _jobs[targetId]?.playlist;
      _applyPlaylistUpdate(targetId, snapshot.summary, status: snapshot.status);
      final updated = _jobs[targetId]?.playlist ?? before;
      return updated ?? snapshot.summary;
    } catch (error, stackTrace) {
      if (error is DownloadServiceConnectionException) {
        _handleConnectionException('Entradas de playlist $jobId', error);
      } else {
        _lastError = error.toString();
        debugPrint('Failed to load playlist entries for $jobId: $error');
        debugPrint(stackTrace.toString());
        notifyListeners();
      }
      return _jobs[jobId]?.playlist;
    }
  }

  /// Attempts to convert a websocket payload into a JSON map. Returns `null`
  /// when the payload cannot be decoded.
  Map<String, dynamic>? _decodeSocketEvent(dynamic raw) {
    if (raw == null) {
      return null;
    }
    try {
      final text = raw is String
          ? raw
          : raw is List<int>
          ? utf8.decode(raw)
          : raw.toString();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to decode websocket message: $error');
      debugPrint(stackTrace.toString());
    }
    return null;
  }

  String _effectiveLanguageCode() {
    final resolved = _languageResolver?.call();
    if (resolved == null) {
      return I18n.fallbackLocale;
    }
    final trimmed = resolved.trim();
    return trimmed.isEmpty ? I18n.fallbackLocale : trimmed;
  }

  String _localize(String key, {Map<String, String>? values}) {
    try {
      final template = resolveAppString(key, _effectiveLanguageCode());
      if (values == null || values.isEmpty) {
        return template;
      }
      return values.entries.fold<String>(
        template,
        (result, entry) =>
            result.replaceAll('{${entry.key}}', entry.value),
      );
    } on StateError {
      return key;
    }
  }

  static const Map<String, String> _backendActionDescriptionKeys =
      <String, String>{
        'sincronizar las descargas': AppStringKey.backendActionSyncDownloads,
        'actualizar las descargas':
            AppStringKey.backendActionRefreshDownloads,
        'obtener la vista previa': AppStringKey.backendActionFetchPreview,
        'cargar la playlist': AppStringKey.backendActionLoadPlaylist,
        'cargar las opciones del trabajo':
            AppStringKey.backendActionLoadJobOptions,
        'cargar las opciones del elemento':
            AppStringKey.backendActionLoadEntryOptions,
        'cargar los registros del trabajo':
            AppStringKey.backendActionLoadJobLogs,
        'cargar los registros del elemento':
            AppStringKey.backendActionLoadEntryLogs,
        'iniciar una descarga': AppStringKey.backendActionStartDownload,
        'pausar el trabajo': AppStringKey.backendActionPauseJob,
        'reanudar el trabajo': AppStringKey.backendActionResumeJob,
        'cancelar el trabajo': AppStringKey.backendActionCancelJob,
        'reintentar el trabajo': AppStringKey.backendActionRetryJob,
        'reintentar los elementos de la lista':
            AppStringKey.backendActionRetryEntries,
        'eliminar el trabajo': AppStringKey.backendActionDeleteJob,
        'enviar la selección de playlist':
            AppStringKey.backendActionSendPlaylistSelection,
      };

  String _localizedActionDescription(String actionDescription) {
    if (actionDescription.isEmpty) {
      return '';
    }
    final key = _backendActionDescriptionKeys[actionDescription];
    if (key != null) {
      return _localize(key);
    }
    return actionDescription;
  }

  bool _ensureBackendReady(String actionDescription, {bool silent = false}) {
    if (backendReady) {
      return true;
    }
    if (!silent) {
      _recordError(_backendWaitMessage(actionDescription));
    }
    return false;
  }

  String _backendWaitMessage(String actionDescription) {
    final localizedAction = _localizedActionDescription(actionDescription);
    final suffix = localizedAction.isEmpty
        ? ''
        : _localize(
            AppStringKey.backendWaitActionSuffix,
            values: {'action': localizedAction},
          );
    switch (_backendState) {
      case BackendState.unpacking:
        return _localize(
          AppStringKey.backendWaitUnpacking,
          values: {'suffix': suffix},
        );
      case BackendState.starting:
        return _localize(
          AppStringKey.backendWaitStarting,
          values: {'suffix': suffix},
        );
      case BackendState.stopped:
        return _localize(
          AppStringKey.backendWaitStopped,
          values: {'suffix': suffix},
        );
      case BackendState.unknown:
        return _localize(
          AppStringKey.backendWaitUnknown,
          values: {'suffix': suffix},
        );
      case BackendState.running:
        return '';
    }
  }

  void _handleBackendStateChanged() {
    if (_disposed) {
      return;
    }
    final next = _backendStateListenable.value;
    if (next == _backendState) {
      return;
    }
    final wasReady = backendReady;
    _backendState = next;
    if (!backendReady) {
      _handleBackendUnavailable();
      notifyListeners();
      return;
    }
    if (!wasReady) {
      _clearLastError();
      if (_initializeRequested && !_initialized && !_isInitializing) {
        unawaited(initialize());
      } else if (_initialized) {
        _connectOverview();
      }
    }
    notifyListeners();
  }

  void _handleBackendUnavailable() {
    _isInitializing = false;
    final bool wasInitialized = _initialized;
    _initialized = false;
    _teardownRealtimeConnections();
    if (wasInitialized) {
      _recordError(_backendWaitMessage('sincronizar las descargas'));
    }
  }

  void _teardownRealtimeConnections() {
    _overviewReconnectTimer?.cancel();
    _overviewReconnectTimer = null;
    _cancelOverview();

    for (final timer in _jobReconnectTimers.values) {
      timer.cancel();
    }
    _jobReconnectTimers.clear();

    for (final handle in _jobSockets.values) {
      handle.subscription.cancel();
      try {
        handle.channel.sink.close();
      } catch (_) {
        // channel cleanup best-effort
      }
    }
    _jobSockets.clear();
    _jobRetryDelays.clear();
    _subscribedJobs.clear();
  }

  void _handleConnectionException(
    String scope,
    DownloadServiceConnectionException error, {
    bool silent = false,
  }) {
    if (_disposed) {
      return;
    }
    final rawMessage = error.message?.toString() ?? '';
    final normalized = rawMessage.trim().isEmpty
      ? _localize(AppStringKey.backendWaitConnectionFailed)
      : rawMessage.trim();
    final changed = _lastError != normalized;
    if (!silent) {
      _recordError(normalized);
    }
    if (changed || silent) {
      debugPrint('$scope: $normalized');
    }
  }

  void _recordError(String message) {
    if (_disposed || _lastError == message) {
      return;
    }
    _lastError = message;
    notifyListeners();
  }

  void _clearLastError() {
    if (_disposed || _lastError == null) {
      return;
    }
    _lastError = null;
    notifyListeners();
  }

  Duration _increaseWithBackoff(
    Duration current,
    Duration max, {
    Duration? minimum,
  }) {
    final minDuration = minimum ?? current;
    final minMs = minDuration.inMilliseconds == 0
        ? 1
        : minDuration.inMilliseconds;
    final currentMs = current.inMilliseconds == 0
        ? minMs
        : current.inMilliseconds;
    final doubled = currentMs * 2;
    final capped = math.min(doubled, max.inMilliseconds);
    final clamped = math.max(capped, minMs);
    return Duration(milliseconds: clamped);
  }

  int? _parseInt(Object? value) {
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

  Map<String, dynamic> _cloneStringKeyedMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, dynamic entryValue) {
        if (key is String) {
          result[key] = entryValue;
        }
      });
      return result;
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic>? _buildPlaylistEntryProgressEntry(
    DownloadJobModel job,
    Map<String, dynamic> data,
    int entryIndex,
  ) {
    final entryPayload = <String, dynamic>{'index': entryIndex};

    final rawEntry = data['entry'];
    if (rawEntry is Map) {
      try {
        entryPayload.addAll(rawEntry.cast<String, dynamic>());
      } catch (_) {
        entryPayload.addAll(Map<String, dynamic>.from(rawEntry));
      }
    } else {
      final existing = _findPlaylistEntryMetadata(job, entryIndex);
      if (existing != null) {
        entryPayload.addAll(existing);
      }
    }

    final entryId =
        _normalizeString(data['playlist_entry_id']) ??
        _normalizeString(data['entry_id']);
    if (entryId != null && entryId.isNotEmpty) {
      entryPayload['id'] = entryId;
    } else if (!entryPayload.containsKey('id')) {
      final existing = _findPlaylistEntryMetadata(job, entryIndex);
      final existingId = _normalizeString(existing?['id']);
      if (existingId != null && existingId.isNotEmpty) {
        entryPayload['id'] = existingId;
      }
    }

    final status = _normalizeString(data['status']);
    if (status != null) {
      entryPayload['status'] = status;
    }

    final state = _normalizeString(data['state'])?.toLowerCase();
    if (state != null && state.isNotEmpty) {
      entryPayload['state_hint'] = state;
    }

    final bool? activeFlag = _coerceBool(data['is_active']);
    final bool? terminalFlag = _coerceBool(data['is_terminal']);
    bool? isCompleted;
    bool? isCurrent;
    if (state != null) {
      isCompleted = state == 'completed';
      if (state == 'failed' || state == 'cancelled') {
        isCurrent = false;
      } else {
        isCurrent = (state == 'active' || state == 'reopened') && !isCompleted;
      }
    }
    if (isCurrent == null && activeFlag != null) {
      isCurrent = activeFlag && (isCompleted != true);
    }
    if (isCompleted == null && terminalFlag == true) {
      isCompleted = true;
    }
    if (isCompleted != null) {
      entryPayload['is_completed'] = isCompleted;
    }
    if (isCurrent != null) {
      entryPayload['is_current'] = isCurrent;
    }

    final progress = _extractPlaylistEntryProgress(data);
    if (progress.isNotEmpty) {
      entryPayload['progress'] = progress;
      entryPayload['progress_snapshot'] = Map<String, dynamic>.from(progress);
    }

    final timestamp = _normalizeString(data['timestamp']);
    if (timestamp != null && timestamp.isNotEmpty) {
      entryPayload['last_progress_at'] = timestamp;
    }

    return entryPayload;
  }

  Map<String, dynamic> _extractPlaylistEntryProgress(
    Map<String, dynamic> data,
  ) {
    const progressKeys = <String>[
      'status',
      'stage',
      'stage_name',
      'percent',
      'stage_percent',
      'downloaded_bytes',
      'total_bytes',
      'speed',
      'eta',
      'elapsed',
      'message',
      'filename',
      'tmpfilename',
    ];
    final progress = <String, dynamic>{};
    for (final key in progressKeys) {
      final value = data[key];
      if (value != null) {
        progress[key] = value;
      }
    }
    return progress;
  }

  Map<String, dynamic>? _findPlaylistEntryMetadata(
    DownloadJobModel job,
    int entryIndex,
  ) {
    final playlistRaw = job.metadata['playlist'];
    if (playlistRaw is Map) {
      final entriesRaw = playlistRaw['entries'];
      if (entriesRaw is List) {
        for (final entry in entriesRaw) {
          if (entry is! Map) {
            continue;
          }
          try {
            final entryMap = entry.cast<String, dynamic>();
            final indexValue = _parseInt(entryMap['index']);
            if (indexValue != null && indexValue == entryIndex) {
              return Map<String, dynamic>.from(entryMap);
            }
          } catch (_) {
            continue;
          }
        }
      }
    }
    return null;
  }

  String? _normalizeString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  Future<bool> _performJobAction({
    required String jobId,
    required Future<Map<String, dynamic>> Function() action,
    DownloadStatus? optimisticStatus,
    bool expectDeletion = false,
    void Function(Map<String, dynamic> response)? onResponse,
  }) async {
    if (_disposed) {
      return false;
    }

    final existing = _jobs[jobId];
    DownloadJobModel? backup;
    if (existing != null && optimisticStatus != null) {
      backup = existing;
      final optimisticJob = existing.copyWith(status: optimisticStatus);
      _cacheJob(optimisticJob);
      _syncJobSubscriptions();
      notifyListeners();
    }

    try {
      final response = await action();
      if (onResponse != null) {
        onResponse(response);
      }
      final handled = _applyJobActionResponse(
        jobId,
        response,
        expectDeletion: expectDeletion,
      );
      if (!expectDeletion && !handled) {
        unawaited(_refreshSingleJob(jobId));
      }
      if (expectDeletion && !handled) {
        _jobs.remove(jobId);
        _markJobsViewDirty();
        _removeJobFromOrdering(jobId);
        _closeJobSocket(jobId);
        _jobsBeingFetched.remove(jobId);
        _syncJobSubscriptions();
        notifyListeners();
      }
      _clearLastError();
      return true;
    } catch (error, stackTrace) {
      if (_disposed) {
        return false;
      }
      if (backup != null) {
        _cacheJob(backup);
        _syncJobSubscriptions();
        notifyListeners();
      }
      if (error is DownloadServiceConnectionException) {
        _handleConnectionException('Acción sobre $jobId', error);
        return false;
      }
      _lastError = error.toString();
      debugPrint('Failed to perform action on $jobId: $error');
      debugPrint(stackTrace.toString());
      notifyListeners();
      return false;
    }
  }

  bool _applyJobActionResponse(
    String jobId,
    Map<String, dynamic> response, {
    bool expectDeletion = false,
  }) {
    if (_disposed) {
      return false;
    }
    if (response.isEmpty) {
      return false;
    }

    final reason = response['reason'] as String?;
    final statusRaw = response['status'] as String?;
    final normalizedReason = reason?.toLowerCase();
    final normalizedStatus = statusRaw?.toLowerCase();
    final isDeletion =
        expectDeletion ||
        normalizedReason == BackendJobUpdateReason.deleted ||
        normalizedStatus == BackendJobStatus.deleted;

    if (isDeletion) {
      final removed = _jobs.remove(jobId);
      if (removed != null) {
        _markJobsViewDirty();
      }
      _closeJobSocket(jobId);
      _jobsBeingFetched.remove(jobId);
      if (removed != null) {
        _removeJobFromOrdering(jobId);
        _syncJobSubscriptions();
        notifyListeners();
        return true;
      }
      return false;
    }

    final existing = _jobs[jobId];
    if (existing == null) {
      return false;
    }

    var updated = existing;
    if (statusRaw != null) {
      final status = downloadStatusFromString(statusRaw);
      if (status != DownloadStatus.unknown || statusRaw.isNotEmpty) {
        updated = updated.copyWith(
          status: status != DownloadStatus.unknown ? status : updated.status,
        );
      }
    }
    if (response.containsKey('error')) {
      final errorValue = response['error'];
      updated = updated.copyWith(
        error: errorValue is String ? errorValue : null,
      );
    }

    if (!identical(updated, existing)) {
      _cacheJob(updated);
      _syncJobSubscriptions();
      notifyListeners();
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _backendStateListenable.removeListener(_handleBackendStateChanged);
    _appLifecycleObserver?.removeListener(_handleLifecycleStateChanged);
    _teardownRealtimeConnections();
    _manualJobSubscriptions.clear();
    _service.dispose();
    super.dispose();
  }
}

class _SocketHandle {
  _SocketHandle(this.channel, this.subscription);

  final WebSocketChannel channel;
  final StreamSubscription<dynamic> subscription;
}
