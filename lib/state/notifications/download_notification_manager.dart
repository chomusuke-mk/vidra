import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/utils/download_formatters.dart';

import 'windows_icon_path.dart';

/// Coordinates OS-level notifications for download job updates.
class DownloadNotificationManager {
  DownloadNotificationManager({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? clock,
    String Function()? languageResolver,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _clock = clock ?? DateTime.now,
       _languageResolver = languageResolver ?? _defaultLanguageResolver,
       _sessionStartedAt = (clock ?? DateTime.now)();

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _clock;
  final String Function() _languageResolver;
  final DateTime _sessionStartedAt;
  FlutterLocalNotificationsWindows? _windowsPlugin;
  bool _initialized = false;
  Completer<void>? _initializationCompleter;
  final Map<String, _NotificationTracker> _trackers =
      <String, _NotificationTracker>{};
  final Map<String, DownloadJobModel> _terminalJobs =
      <String, DownloadJobModel>{};
  final Set<String> _playlistAttentionJobs = <String>{};
  Future<bool> Function(String jobId)? _onRetryJob;

  static const String _windowsTitleBinding = 'vidra_title';
  static const String _windowsStageBinding = 'vidra_stage';
  static const int _androidFlagNoClear = 0x00000020; // FLAG_NO_CLEAR
  static const String _actionOpen = 'vidra_open';
  static const String _actionRetry = 'vidra_retry';
  static const String _actionDismiss = 'vidra_dismiss';
  static const String _darwinCategoryVideoSuccess =
      'vidra_terminal_video_success';
  static const String _darwinCategoryFailure = 'vidra_terminal_failure';
  static const String _darwinCategoryDismissOnly =
      'vidra_terminal_dismiss_only';
  static const String _progressChannelId = 'vidra_download_progress';
  static const String _terminalChannelId = 'vidra_download_terminal';
  static const String _playlistAttentionChannelId = 'vidra_playlist_attention';
  static const String _backendStateChannelId = 'vidra_backend_state';
  static const int _backendStartupNotificationId = 9001;

  bool get _supportsNotifications => !kIsWeb;
  bool get _isWindows =>
      _supportsNotifications && defaultTargetPlatform == TargetPlatform.windows;

  /// Ensures the underlying plugin is configured and channels exist.
  Future<void> initialize() async {
    if (!_supportsNotifications) {
      return;
    }
    if (_initialized) {
      return;
    }
    if (_initializationCompleter != null) {
      return _initializationCompleter!.future;
    }
    final completer = Completer<void>();
    _initializationCompleter = completer;
    try {
      final lookup = _stringLookup();
      final darwinCategories = _buildDarwinCategories(lookup);
      final linuxDefaultAction = lookup(
        AppStringKey.notificationLinuxDefaultAction,
      );
      final windowsIconPath = resolveWindowsToastIconPath();
      final initializationSettings = InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: darwinCategories,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: darwinCategories,
        ),
        linux: LinuxInitializationSettings(
          defaultActionName: linuxDefaultAction,
        ),
        windows: WindowsInitializationSettings(
          appName: 'Vidra',
          appUserModelId: 'dev.chomusuke.vidra',
          guid: '0c0a1be1-3e36-4d0b-9df9-7f867369b1a4',
          iconPath: windowsIconPath,
        ),
      );
      await _plugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      _windowsPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            FlutterLocalNotificationsWindows
          >();
      await _configurePlatformChannels();
      _initialized = true;
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _initializationCompleter = null;
    }
  }

  /// Cancels any persisted notification for [jobId].
  Future<void> handleJobRemoved(String jobId) async {
    _trackers.remove(jobId);
    _terminalJobs.remove(jobId);
    await dismissPlaylistSelectionAttention(jobId);
    if (!_supportsNotifications || !_initialized) {
      return;
    }
    await _plugin.cancel(_notificationId(jobId));
  }

  /// Registers callbacks used to fulfill notification action buttons.
  void registerActionHandlers({
    Future<bool> Function(String jobId)? onRetryJob,
  }) {
    _onRetryJob = onRetryJob;
  }

  /// Updates or shows the notification that represents [job].
  Future<void> handleJobUpdated(
    DownloadJobModel job, {
    DownloadJobModel? previous,
    bool playlistSelectionPending = false,
  }) async {
    if (!_supportsNotifications) {
      return;
    }
    await initialize();
    final tracker = _trackers.putIfAbsent(job.id, () => _NotificationTracker());
    tracker.lastStatus = job.status;

    if (job.isTerminal) {
      if (!_shouldNotifyTerminalJob(job, previous)) {
        _trackers.remove(job.id);
        return;
      }
      if (tracker.terminalShown && previous?.status == job.status) {
        return;
      }
      await _showTerminalNotification(job);
      await dismissPlaylistSelectionAttention(job.id);
      tracker
        ..terminalShown = true
        ..lastShown = _clock();
      _trackers.remove(job.id);
      return;
    }

    if (!_shouldShowProgress(job.status)) {
      await handleJobRemoved(job.id);
      return;
    }

    final now = _clock();
    final throttle = _progressThrottle();
    if (tracker.lastShown != null &&
        now.difference(tracker.lastShown!) < throttle) {
      return;
    }

    tracker
      ..lastShown = now
      ..lastPercent = job.progressPercent
      ..terminalShown = false;
    await _showProgressNotification(
      job,
      tracker,
      playlistSelectionPending: playlistSelectionPending,
    );
  }

  /// Alerts the user that [job] requires playlist attention while the app
  /// is backgrounded.
  Future<void> showPlaylistSelectionAttention(DownloadJobModel job) async {
    if (!_supportsNotifications) {
      return;
    }
    await initialize();
    if (_playlistAttentionJobs.contains(job.id)) {
      return;
    }
    final lookup = _stringLookup();
    final title = _titleFor(job);
    final body = lookup(AppStringKey.jobPlaylistBannerSelectionDescription);
    final notificationId = _playlistAttentionNotificationId(job.id);
    final androidDetails = AndroidNotificationDetails(
      _playlistAttentionChannelId,
      lookup(AppStringKey.notificationPlaylistAttentionChannelName),
      channelDescription: lookup(
        AppStringKey.notificationPlaylistAttentionChannelDescription,
      ),
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
      styleInformation: BigTextStyleInformation(body),
      category: AndroidNotificationCategory.reminder,
      playSound: true,
      enableVibration: true,
    );
    final darwinDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentSound: true,
      subtitle: body,
    );
    final windowsDetails = WindowsNotificationDetails(
      scenario: WindowsNotificationScenario.alarm,
      subtitle: body,
      duration: WindowsNotificationDuration.short,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      windows: windowsDetails,
    );
    await _plugin.show(notificationId, title, body, details, payload: job.id);
    _playlistAttentionJobs.add(job.id);
  }

  Future<void> dismissPlaylistSelectionAttention(String jobId) async {
    if (!_playlistAttentionJobs.remove(jobId)) {
      return;
    }
    if (!_supportsNotifications || !_initialized) {
      return;
    }
    await _plugin.cancel(_playlistAttentionNotificationId(jobId));
  }

  Future<void> showBackendStartupNotification() async {
    if (!_supportsNotifications) {
      return;
    }
    await initialize();
    final lookup = _stringLookup();
    final String title = 'Vidra';
    final body = lookup(AppStringKey.homeBackendStatusStartingShort);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _backendStateChannelId,
        lookup(AppStringKey.homeBackendStatusStartingShort),
        channelDescription: lookup(AppStringKey.homeBackendStatusStartingShort),
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        playSound: false,
        enableVibration: false,
        enableLights: false,
        category: AndroidNotificationCategory.service,
        showProgress: true,
        indeterminate: true,
      ),
    );
    await _plugin.show(_backendStartupNotificationId, title, body, details);
  }

  Future<void> dismissBackendStartupNotification() async {
    if (!_supportsNotifications || !_initialized) {
      return;
    }
    await _plugin.cancel(_backendStartupNotificationId);
  }

  Duration _progressThrottle() {
    if (kIsWeb) {
      return const Duration(seconds: 1);
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const Duration(milliseconds: 450);
      case TargetPlatform.windows:
        return const Duration(milliseconds: 600);
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return const Duration(milliseconds: 900);
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const Duration(milliseconds: 700);
    }
  }

  Future<void> _configurePlatformChannels() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final languageCode = _effectiveLanguageCode();
      await androidPlugin.createNotificationChannel(
        _buildProgressChannel(languageCode),
      );
      await androidPlugin.createNotificationChannel(
        _buildTerminalChannel(languageCode),
      );
      await androidPlugin.createNotificationChannel(
        _buildPlaylistAttentionChannel(languageCode),
      );
      await androidPlugin.createNotificationChannel(
        _buildBackendStateChannel(languageCode),
      );
      await androidPlugin.requestNotificationsPermission();
    }
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);
    final macPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    await macPlugin?.requestPermissions(alert: true, badge: true, sound: true);
  }

  AndroidNotificationChannel _buildProgressChannel(String languageCode) {
    return AndroidNotificationChannel(
      _progressChannelId,
      resolveAppString(
        AppStringKey.notificationProgressChannelName,
        languageCode,
      ),
      description: resolveAppString(
        AppStringKey.notificationProgressChannelDescription,
        languageCode,
      ),
      importance: Importance.low,
      playSound: false,
      enableLights: false,
      enableVibration: false,
      showBadge: false,
    );
  }

  AndroidNotificationChannel _buildTerminalChannel(String languageCode) {
    return AndroidNotificationChannel(
      _terminalChannelId,
      resolveAppString(
        AppStringKey.notificationTerminalChannelName,
        languageCode,
      ),
      description: resolveAppString(
        AppStringKey.notificationTerminalChannelDescription,
        languageCode,
      ),
      importance: Importance.high,
    );
  }

  AndroidNotificationChannel _buildPlaylistAttentionChannel(
    String languageCode,
  ) {
    return AndroidNotificationChannel(
      _playlistAttentionChannelId,
      resolveAppString(
        AppStringKey.notificationPlaylistAttentionChannelName,
        languageCode,
      ),
      description: resolveAppString(
        AppStringKey.notificationPlaylistAttentionChannelDescription,
        languageCode,
      ),
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
  }

  AndroidNotificationChannel _buildBackendStateChannel(String languageCode) {
    return AndroidNotificationChannel(
      _backendStateChannelId,
      resolveAppString(AppStringKey.homeBackendStatusStarting, languageCode),
      description: resolveAppString(
        AppStringKey.homeBackendStatusStarting,
        languageCode,
      ),
      importance: Importance.low,
      playSound: false,
      enableLights: false,
      enableVibration: false,
      showBadge: false,
    );
  }

  Future<void> _showProgressNotification(
    DownloadJobModel job,
    _NotificationTracker tracker, {
    bool playlistSelectionPending = false,
  }) async {
    final lookup = _stringLookup();
    final notificationTitle = _titleFor(job);
    final percent = job.progressPercent;
    final progressValue = percent?.clamp(0, 100).round();
    final stageLine = playlistSelectionPending
        ? _playlistSelectionStageLine(job, lookup)
        : _progressStageLine(job);
    final metricsLine = _metricLine(job);
    final bodyParts = <String>[];
    if (stageLine.isNotEmpty) {
      bodyParts.add(stageLine);
    }
    if (metricsLine != null && metricsLine.isNotEmpty) {
      bodyParts.add(metricsLine);
    }
    final body = bodyParts.isEmpty ? _statusLabel(job) : bodyParts.join(' • ');

    if (_isWindows) {
      await _showOrUpdateWindowsProgress(
        job,
        tracker,
        title: notificationTitle,
        bodyText: body,
        progressValue: progressValue,
      );
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      _progressChannelId,
      lookup(AppStringKey.notificationProgressChannelName),
      channelDescription: lookup(
        AppStringKey.notificationProgressChannelDescription,
      ),
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      enableVibration: false,
      showProgress: true,
      maxProgress: 100,
      progress: progressValue ?? 0,
      indeterminate: progressValue == null,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      styleInformation: BigTextStyleInformation(body),
      category: AndroidNotificationCategory.service,
      additionalFlags: Int32List.fromList(<int>[_androidFlagNoClear]),
    );

    final darwinDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentSound: false,
      subtitle: metricsLine,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      _notificationId(job.id),
      notificationTitle,
      body,
      details,
      payload: job.id,
    );
  }

  Future<void> _showOrUpdateWindowsProgress(
    DownloadJobModel job,
    _NotificationTracker tracker, {
    required String title,
    required String bodyText,
    int? progressValue,
  }) async {
    final stageText = bodyText.isEmpty ? _statusLabel(job) : bodyText;
    final percentLabel = progressValue == null ? null : '$progressValue%';
    final notificationId = _notificationId(job.id);
    tracker.windowsProgress ??= _WindowsProgressHandle(
      'progress_$notificationId',
    );
    final handle = tracker.windowsProgress!;
    final progressBar = _createWindowsProgressBar(
      handle.progressId,
      percentLabel,
      progressValue,
    );
    final bindingValues = <String, String>{
      _windowsTitleBinding: title,
      _windowsStageBinding: stageText,
    };
    final windowsDetails = WindowsNotificationDetails(
      duration: WindowsNotificationDuration.long,
      audio: WindowsNotificationAudio.silent(),
      bindings: bindingValues,
      progressBars: <WindowsProgressBar>[progressBar],
    );
    final windowsPlugin = _windowsPlugin;
    final placeholderTitle = '{$_windowsTitleBinding}';
    final placeholderBody = '{$_windowsStageBinding}';

    if (!handle.displayed || windowsPlugin == null) {
      final details = NotificationDetails(windows: windowsDetails);
      if (windowsPlugin != null) {
        await windowsPlugin.show(
          notificationId,
          placeholderTitle,
          placeholderBody,
          payload: job.id,
          details: windowsDetails,
        );
      } else {
        await _plugin.show(
          notificationId,
          placeholderTitle,
          placeholderBody,
          details,
          payload: job.id,
        );
      }
      handle.displayed = true;
      if (windowsPlugin == null) {
        // Without a platform-specific implementation we must fully re-show on
        // every update, so force another show next pass.
        handle.displayed = false;
      }
      return;
    }

    await windowsPlugin.updateBindings(
      id: notificationId,
      bindings: bindingValues,
    );
    await windowsPlugin.updateProgressBar(
      notificationId: notificationId,
      progressBar: progressBar,
    );
  }

  WindowsProgressBar _createWindowsProgressBar(
    String progressId,
    String? percentLabel,
    int? progressValue,
  ) {
    return WindowsProgressBar(
      id: progressId,
      status: '',
      value: _windowsProgressValue(progressValue),
      label: percentLabel,
    );
  }

  double? _windowsProgressValue(int? value) {
    if (value == null) {
      return null;
    }
    final num clamped = value.clamp(0, 100);
    return clamped.toDouble() / 100;
  }

  Future<void> _showTerminalNotification(DownloadJobModel job) async {
    final lookup = _stringLookup();
    final body = _terminalBody(job);
    final actionConfig = _buildTerminalActions(job);
    final androidDetails = AndroidNotificationDetails(
      _terminalChannelId,
      lookup(AppStringKey.notificationTerminalChannelName),
      channelDescription: lookup(
        AppStringKey.notificationTerminalChannelDescription,
      ),
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
      styleInformation: BigTextStyleInformation(body),
      actions: actionConfig.androidActions,
    );
    final darwinDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.active,
      presentSound: true,
      categoryIdentifier: actionConfig.darwinCategory,
    );
    final windowsDetails = WindowsNotificationDetails(
      duration: WindowsNotificationDuration.long,
      scenario: _terminalScenario(job.status),
      subtitle: _statusLabel(job),
      actions: actionConfig.windowsActions,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      windows: windowsDetails,
    );
    await _plugin.show(
      _notificationId(job.id),
      _titleFor(job),
      body,
      details,
      payload: job.id,
    );
    _terminalJobs[job.id] = job;
  }

  String _terminalBody(DownloadJobModel job) {
    final lookup = _stringLookup();
    switch (job.status) {
      case DownloadStatus.completed:
        final playlist = job.playlist;
        if (playlist != null &&
            playlist.completedItems != null &&
            playlist.totalItems != null) {
          return _formatTemplate(
            lookup(AppStringKey.notificationTerminalPlaylistSummary),
            {
              'completed': '${playlist.completedItems}',
              'total': '${playlist.totalItems}',
            },
          );
        }
        final file = job.mainFile;
        if (file != null && file.isNotEmpty) {
          return _formatTemplate(
            lookup(AppStringKey.notificationTerminalSavedTo),
            {'path': file},
          );
        }
        return lookup(AppStringKey.notificationTerminalSuccess);
      case DownloadStatus.failed:
        return sanitizeMessage(job.error) ??
            lookup(AppStringKey.notificationTerminalFailure);
      case DownloadStatus.cancelled:
        return lookup(AppStringKey.notificationTerminalCancelled);
      default:
        return _progressStageLine(job);
    }
  }

  String _playlistSelectionStageLine(
    DownloadJobModel job,
    AppStringLookup lookup,
  ) {
    final waitingLabel = lookup(AppStringKey.jobStageWaitingForSelection);
    final countsLine = _playlistSelectionCounts(job, lookup);
    if (countsLine == null) {
      return waitingLabel;
    }
    return '$waitingLabel: $countsLine';
  }

  String? _playlistSelectionCounts(
    DownloadJobModel job,
    AppStringLookup lookup,
  ) {
    final playlist = job.playlist;
    final total =
        playlist?.totalItems ??
        playlist?.entryCount ??
        job.progress?.playlistTotalItems ??
        job.progress?.playlistCount;
    final received =
        playlist?.completedItems ??
        playlist?.entries.length ??
        job.progress?.playlistCompletedItems;
    if (total == null || total <= 0 || received == null) {
      return null;
    }
    return _formatTemplate(
      lookup(AppStringKey.playlistDialogItemsReceivedOfTotal),
      {'received': '$received', 'total': '$total'},
    );
  }

  String _progressStageLine(DownloadJobModel job) {
    final progress = job.progress;
    final lookup = _stringLookup();
    final stageLabel =
        describeStage(
          progress?.stage,
          progress?.postprocessor,
          progress?.preprocessor,
          lookup: lookup,
        ) ??
        describeStatus(progress?.status, lookup) ??
        _statusLabel(job, lookup: lookup);
    final message = progress?.message;
    return composeStageLine(stageLabel, message) ?? stageLabel;
  }

  String? _metricLine(DownloadJobModel job) {
    final progress = job.progress;
    if (progress == null) {
      return null;
    }
    final lookup = _stringLookup();
    final parts = <String>[];
    final downloaded = progress.downloadedBytes;
    final total = progress.totalBytes;
    if (downloaded != null) {
      if (total != null && total > 0) {
        parts.add(
          '${formatBytesCompact(downloaded)}/${formatBytesCompact(total)}',
        );
      } else {
        parts.add(formatBytesCompact(downloaded));
      }
    } else if (total != null && total > 0) {
      parts.add(formatBytesCompact(total));
    }
    final speed = progress.speed;
    if (speed != null && speed > 0) {
      parts.add(
        _formatTemplate(lookup(AppStringKey.notificationMetricSpeed), {
          'value': formatBytesCompact(speed),
        }),
      );
    }
    final eta = progress.eta;
    if (eta != null && eta > 0) {
      parts.add(
        _formatTemplate(lookup(AppStringKey.notificationMetricEta), {
          'time': formatEta(eta),
        }),
      );
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' · ');
  }

  String _statusLabel(DownloadJobModel job, {AppStringLookup? lookup}) {
    final resolver = lookup ?? _stringLookup();
    return describeStatus(job.status.name, resolver) ?? job.status.name;
  }

  bool _shouldShowProgress(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.running:
      case DownloadStatus.retrying:
      case DownloadStatus.starting:
      case DownloadStatus.queued:
      case DownloadStatus.pausing:
      case DownloadStatus.paused:
      case DownloadStatus.cancelling:
        return true;
      default:
        return false;
    }
  }

  String _titleFor(DownloadJobModel job) {
    final preview = job.preview;
    final candidates = <String?>[
      preview?.title,
      preview?.webpageUrl,
      preview?.originalUrl,
      job.metadata['title'] as String?,
      job.metadata['webpage_url'] as String?,
      job.metadata['original_url'] as String?,
      job.urls.isNotEmpty ? job.urls.first : null,
    ];
    for (final candidate in candidates) {
      if (candidate == null) {
        continue;
      }
      final trimmed = candidate.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    final lookup = _stringLookup();
    return _formatTemplate(lookup(AppStringKey.notificationTitleFallback), {
      'id': job.id,
    });
  }

  int _notificationId(String jobId) {
    final normalized = jobId.hashCode & 0x7fffffff;
    return 1000 + normalized;
  }

  int _playlistAttentionNotificationId(String jobId) {
    final normalized = jobId.hashCode & 0x7fffffff;
    return 200000 + normalized;
  }

  WindowsNotificationScenario _terminalScenario(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return WindowsNotificationScenario.urgent;
      default:
        return WindowsNotificationScenario.reminder;
    }
  }

  bool _shouldNotifyTerminalJob(
    DownloadJobModel job,
    DownloadJobModel? previous,
  ) {
    if (previous == null) {
      return _finishedDuringSession(job);
    }
    if (!previous.isTerminal) {
      return true;
    }
    final currentFinished = job.finishedAt;
    final previousFinished = previous.finishedAt;
    if (currentFinished != null && previousFinished != null) {
      return currentFinished.isAfter(previousFinished);
    }
    if (currentFinished != null && previousFinished == null) {
      return true;
    }
    return false;
  }

  bool _finishedDuringSession(DownloadJobModel job) {
    final finishedAt = job.finishedAt;
    if (finishedAt != null) {
      return !finishedAt.isBefore(_sessionStartedAt);
    }
    final startedAt = job.startedAt;
    if (startedAt != null) {
      return !startedAt.isBefore(_sessionStartedAt);
    }
    return !job.createdAt.isBefore(_sessionStartedAt);
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final context = _resolveActionContext(response);
    final actionId = context.actionId;
    final jobId = context.jobId;
    if (jobId == null || jobId.isEmpty) {
      return;
    }
    switch (actionId) {
      case _actionOpen:
        unawaited(_openOutput(jobId));
        break;
      case _actionRetry:
        final retry = _onRetryJob;
        if (retry != null) {
          unawaited(retry(jobId));
        }
        break;
      case _actionDismiss:
        unawaited(_dismissNotification(jobId));
        break;
      default:
        break;
    }
  }

  _NotificationActionContext _resolveActionContext(
    NotificationResponse response,
  ) {
    final payloadContext = _tryDecodeActionContext(response.payload);
    if (payloadContext != null) {
      return payloadContext;
    }
    final actionContext = _tryDecodeActionContext(response.actionId);
    if (actionContext != null) {
      return actionContext;
    }
    return _NotificationActionContext(
      actionId: response.actionId,
      jobId: response.payload,
    );
  }

  _NotificationActionContext? _tryDecodeActionContext(String? raw) {
    if (raw == null || raw.isEmpty || !raw.contains('action=')) {
      return null;
    }
    try {
      final data = Uri.splitQueryString(raw);
      final actionId = data['action'];
      final jobId = data['job'];
      if (actionId == null || jobId == null) {
        return null;
      }
      return _NotificationActionContext(actionId: actionId, jobId: jobId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openOutput(String jobId) async {
    final job = _terminalJobs[jobId];
    final target = job?.mainFile;
    if (target == null || target.isEmpty) {
      return;
    }
    try {
      final result = await OpenFile.open(target);
      if (result.type != ResultType.done) {
        debugPrint('OpenFile failed for $target (${result.message}).');
      }
    } catch (error) {
      debugPrint('OpenFile exception for $target: $error');
    }
  }

  Future<void> _dismissNotification(String jobId) async {
    await _plugin.cancel(_notificationId(jobId));
    _terminalJobs.remove(jobId);
  }

  _TerminalNotificationActions _buildTerminalActions(DownloadJobModel job) {
    final androidActions = <AndroidNotificationAction>[];
    final windowsActions = <WindowsAction>[];
    String? darwinCategory;
    final lookup = _stringLookup();
    final bool hasFile = job.mainFile != null && job.mainFile!.isNotEmpty;
    final bool canOpen =
        job.status == DownloadStatus.completed && job.isVideo && hasFile;
    final bool canRetry = job.status == DownloadStatus.failed;
    final bool showDismiss =
        job.status == DownloadStatus.completed ||
        job.status == DownloadStatus.failed;

    if (canOpen) {
      androidActions.add(_androidOpenAction(lookup));
      windowsActions.add(_windowsOpenAction(job.id, lookup));
    }
    if (canRetry) {
      androidActions.add(_androidRetryAction(lookup));
      windowsActions.add(_windowsRetryAction(job.id, lookup));
    }
    if (showDismiss) {
      androidActions.add(_androidDismissAction(lookup));
      windowsActions.add(_windowsDismissAction(job.id, lookup));
      if (canOpen) {
        darwinCategory = _darwinCategoryVideoSuccess;
      } else if (canRetry) {
        darwinCategory = _darwinCategoryFailure;
      } else {
        darwinCategory = _darwinCategoryDismissOnly;
      }
    }

    return _TerminalNotificationActions(
      androidActions: androidActions,
      windowsActions: windowsActions,
      darwinCategory: darwinCategory,
    );
  }

  AndroidNotificationAction _androidOpenAction(AppStringLookup lookup) {
    return AndroidNotificationAction(
      _actionOpen,
      lookup(AppStringKey.notificationActionOpen),
      showsUserInterface: true,
      cancelNotification: false,
    );
  }

  AndroidNotificationAction _androidRetryAction(AppStringLookup lookup) {
    return AndroidNotificationAction(
      _actionRetry,
      lookup(AppStringKey.notificationActionRetry),
      showsUserInterface: true,
      cancelNotification: true,
    );
  }

  AndroidNotificationAction _androidDismissAction(AppStringLookup lookup) {
    return AndroidNotificationAction(
      _actionDismiss,
      lookup(AppStringKey.notificationActionDismiss),
      showsUserInterface: false,
      cancelNotification: true,
    );
  }

  WindowsAction _windowsOpenAction(String jobId, AppStringLookup lookup) {
    return WindowsAction(
      content: lookup(AppStringKey.notificationActionOpen),
      arguments: _encodeWindowsArguments(_actionOpen, jobId),
      activationType: WindowsActivationType.foreground,
      activationBehavior: WindowsNotificationBehavior.dismiss,
    );
  }

  WindowsAction _windowsRetryAction(String jobId, AppStringLookup lookup) {
    return WindowsAction(
      content: lookup(AppStringKey.notificationActionRetry),
      arguments: _encodeWindowsArguments(_actionRetry, jobId),
      activationType: WindowsActivationType.foreground,
      activationBehavior: WindowsNotificationBehavior.dismiss,
    );
  }

  WindowsAction _windowsDismissAction(String jobId, AppStringLookup lookup) {
    return WindowsAction(
      content: lookup(AppStringKey.notificationActionDismiss),
      arguments: _encodeWindowsArguments(_actionDismiss, jobId),
      activationType: WindowsActivationType.foreground,
      activationBehavior: WindowsNotificationBehavior.dismiss,
    );
  }

  String _encodeWindowsArguments(String actionId, String jobId) {
    final encodedAction = Uri.encodeComponent(actionId);
    final encodedJob = Uri.encodeComponent(jobId);
    return 'action=$encodedAction&job=$encodedJob';
  }

  List<DarwinNotificationCategory> _buildDarwinCategories(
    AppStringLookup lookup,
  ) {
    final openLabel = lookup(AppStringKey.notificationActionOpen);
    final retryLabel = lookup(AppStringKey.notificationActionRetry);
    final dismissLabel = lookup(AppStringKey.notificationActionDismiss);
    return <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        _darwinCategoryVideoSuccess,
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(
            _actionOpen,
            openLabel,
            options: const <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.foreground,
            },
          ),
          DarwinNotificationAction.plain(
            _actionDismiss,
            dismissLabel,
            options: const <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.destructive,
            },
          ),
        ],
      ),
      DarwinNotificationCategory(
        _darwinCategoryFailure,
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(
            _actionRetry,
            retryLabel,
            options: const <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.foreground,
            },
          ),
          DarwinNotificationAction.plain(
            _actionDismiss,
            dismissLabel,
            options: const <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.destructive,
            },
          ),
        ],
      ),
      DarwinNotificationCategory(
        _darwinCategoryDismissOnly,
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(
            _actionDismiss,
            dismissLabel,
            options: const <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.destructive,
            },
          ),
        ],
      ),
    ];
  }

  static String _defaultLanguageResolver() => 'en';

  AppStringLookup _stringLookup() {
    final languageCode = _effectiveLanguageCode();
    return (key) => resolveAppString(key, languageCode);
  }

  String _formatTemplate(String template, Map<String, String> values) {
    return values.entries.fold<String>(
      template,
      (result, entry) => result.replaceAll('{${entry.key}}', entry.value),
    );
  }

  String _effectiveLanguageCode() {
    final resolved = _languageResolver().trim();
    if (resolved.isEmpty) {
      return 'en';
    }
    return resolved;
  }
}

class _NotificationActionContext {
  const _NotificationActionContext({this.actionId, this.jobId});

  final String? actionId;
  final String? jobId;
}

class _NotificationTracker {
  DateTime? lastShown;
  DownloadStatus? lastStatus;
  double? lastPercent;
  bool terminalShown = false;
  _WindowsProgressHandle? windowsProgress;
}

class _WindowsProgressHandle {
  _WindowsProgressHandle(this.progressId);

  final String progressId;
  bool displayed = false;
}

class _TerminalNotificationActions {
  const _TerminalNotificationActions({
    this.androidActions = const <AndroidNotificationAction>[],
    this.windowsActions = const <WindowsAction>[],
    this.darwinCategory,
  });

  final List<AndroidNotificationAction> androidActions;
  final List<WindowsAction> windowsActions;
  final String? darwinCategory;
}
