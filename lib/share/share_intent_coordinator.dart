import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/share/pending_download_entry.dart';
import 'package:vidra/share/share_download_utils.dart';
import 'package:vidra/share/share_intent_payload.dart';
import 'package:vidra/share/share_preset_ids.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/notifications/download_notification_manager.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';
import 'package:vidra/state/pending_download_inbox.dart';

class ShareIntentCoordinator {
  ShareIntentCoordinator({
    required DownloadController downloadController,
    required PreferencesModel preferencesModel,
    required PendingDownloadInbox pendingDownloadInbox,
    required DownloadNotificationManager notificationManager,
  }) : _downloadController = downloadController,
       _preferencesModel = preferencesModel,
       _pendingDownloadInbox = pendingDownloadInbox,
       _notificationManager = notificationManager,
       _backendStateListenable = downloadController.backendStateListenable {
    _pendingDownloadInbox.addListener(_handlePendingInboxChanged);
    _backendStateListenable.addListener(_handleBackendStateChanged);
    _ensurePendingPullScheduled();
    _processPendingEntries();
  }

  static const EventChannel _shareEventChannel = EventChannel(
    'dev.chomusuke.vidra/share/events',
  );
  static const MethodChannel _nativeChannel = MethodChannel(
    'dev.chomusuke.vidra/native',
  );

  final DownloadController _downloadController;
  final PreferencesModel _preferencesModel;
  final PendingDownloadInbox _pendingDownloadInbox;
  final DownloadNotificationManager _notificationManager;
  final ValueListenable<BackendState> _backendStateListenable;
  final List<PendingDownloadEntryModel> _pendingNativeEntries =
      <PendingDownloadEntryModel>[];
  final StreamController<ShareIntentPayload> _manualFlowController =
      StreamController<ShareIntentPayload>.broadcast();
  Timer? _pendingPullTimer;
  bool _processingPendingDownloads = false;
  bool _pendingDownloadsQueued = false;
  bool _pendingExternalStartup = false;

  GlobalKey<NavigatorState>? _navigatorKey;
  StreamSubscription<dynamic>? _subscription;
  bool _initialized = false;
  bool get _shareIntegrationSupported => Platform.isAndroid;
  bool get _backendReady =>
      _backendStateListenable.value == BackendState.running;

  bool get isInitialized => _initialized;

  Stream<ShareIntentPayload> get manualFlowStream =>
      _manualFlowController.stream;

  void attachNavigatorKey(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  void detachNavigatorKey(GlobalKey<NavigatorState> navigatorKey) {
    if (_navigatorKey == navigatorKey) {
      _navigatorKey = null;
    }
  }

  void initialize() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    if (!_shareIntegrationSupported) {
      debugPrint('Share intent integration disabled on this platform.');
      _processPendingEntries();
      return;
    }
    _subscription ??= _shareEventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleIncomingPayload(Map<dynamic, dynamic>.from(event));
        }
      },
      onError: (error, stackTrace) {
        debugPrint('Share intent channel error: $error');
        debugPrint('$stackTrace');
      },
    );
    _processPendingEntries();
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_manualFlowController.close());
    _pendingDownloadInbox.removeListener(_handlePendingInboxChanged);
    _backendStateListenable.removeListener(_handleBackendStateChanged);
    _pendingPullTimer?.cancel();
    _pendingPullTimer = null;
  }

  void _handleIncomingPayload(Map<dynamic, dynamic> rawPayload) {
    final payload = ShareIntentPayload.fromMap(rawPayload);
    if (payload.urls.isEmpty && payload.rawText.trim().isEmpty) {
      return;
    }
    if (_shareIntegrationSupported) {
      debugPrint(
        '[ShareIntentCoordinator] Incoming event payload skipped on Android to avoid duplicate; waiting for native inbox.',
      );
      return;
    }
    final presetId = payload.presetId ?? '';
    final key = _keyForPayload(payload, presetId: presetId);
    debugPrint(
      '[ShareIntentCoordinator] Incoming event payload preset=$presetId '
      'urls=${payload.urls.length} rawTextEmpty=${payload.rawText.trim().isEmpty} '
      'timestamp=${payload.timestamp.toIso8601String()} key=$key',
    );
    if (_shouldAutoReturn(payload, presetId)) {
      unawaited(_requestReturnToPreviousApp(payload));
    }
    _enqueuePendingEntry(_fromPayload(payload));
    _processPendingEntries();
  }

  bool _shouldAutoReturn(ShareIntentPayload payload, String presetId) {
    if (!payload.directShare) {
      return false;
    }
    return presetId == SharePresetIds.audioBest ||
        presetId == SharePresetIds.videoBest ||
        presetId == SharePresetIds.manual;
  }

  Future<bool> _runPreset(
    String presetId,
    ShareIntentPayload payload, {
    bool autoLaunch = false,
    bool requestReturn = true,
    Map<String, dynamic>? preferenceOverrides,
    ManualDownloadOptionsModel? manualOptions,
  }) async {
    final navigator = _navigatorKey?.currentState;
    final messenger = navigator == null
        ? null
        : ScaffoldMessenger.maybeOf(navigator.context);
    final localizations = navigator == null
        ? null
        : VidraLocalizations.of(navigator.context);
    try {
      final baseOptions = await buildBackendOptions(_preferencesModel);
      final options = baseOptions.options;
      final ensuredHomePath = baseOptions.ensuredHomePathNotice;
      if (ensuredHomePath != null &&
          messenger != null &&
          localizations != null) {
        final ensuredMessage = localizations
            .ui(AppStringKey.homePathsEnsureDownloads)
            .replaceAll('{path}', ensuredHomePath);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(ensuredMessage)));
      }
      _applyPresetOverrides(presetId, options);
      _applyManualSelectionOverrides(manualOptions, options);
      _applyPreferenceOverrides(preferenceOverrides, options);
      final metadata = buildShareMetadata(
        payload,
        presetId,
        autoLaunch: autoLaunch,
      );
      final urls = joinSharedUrls(payload.urls);
      if (urls.trim().isEmpty) {
        final fallbackMessage =
            localizations?.ui(AppStringKey.enterUrl) ?? 'URL required';
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(fallbackMessage)));
        return false;
      }
      final success = await _downloadController.startDownload(
        urls,
        options,
        metadata: metadata,
      );
      if (success && messenger != null) {
        final startedText =
            localizations?.ui(AppStringKey.homeDownloadStarted) ??
            'Download started';
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(startedText)));
      } else if (!success && messenger != null) {
        final fallbackError =
            localizations?.ui(AppStringKey.homeDownloadFailed) ??
            'Download failed';
        final errorMessage = _downloadController.lastError ?? fallbackError;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(errorMessage)));
      }
      if (success && requestReturn) {
        unawaited(_requestReturnToPreviousApp(payload));
      }
      return success;
    } catch (error, stackTrace) {
      debugPrint('Share preset failed: $error');
      debugPrint('$stackTrace');
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${localizations?.ui(AppStringKey.homeDownloadFailed) ?? 'Download failed'}: $error',
            ),
          ),
        );
      return false;
    }
  }

  Future<void> _requestReturnToPreviousApp(ShareIntentPayload payload) async {
    if (!Platform.isAndroid) {
      return;
    }
    final presetId = payload.presetId;
    if (!payload.directShare) {
      return;
    }
    if (presetId != SharePresetIds.audioBest &&
        presetId != SharePresetIds.videoBest &&
        presetId != SharePresetIds.manual) {
      return;
    }
    debugPrint(
      '[ShareIntentCoordinator] Requesting return to previous app preset=$presetId '
      'directShare=${payload.directShare}',
    );
    try {
      await _nativeChannel.invokeMethod('returnToPreviousApp');
      debugPrint('[ShareIntentCoordinator] returnToPreviousApp invoked');
    } catch (error, stackTrace) {
      debugPrint('Auto return request failed: $error');
      debugPrint(stackTrace.toString());
    }
  }

  void _applyPresetOverrides(String presetId, Map<String, dynamic> options) {
    switch (presetId) {
      case SharePresetIds.videoBest:
        options['extract_audio'] = false;
        options['format'] = 'bestvideo+bestaudio/best';
        options['merge_output_format'] ??= 'mkv';
        break;
      case SharePresetIds.audioBest:
        options['extract_audio'] = true;
        options['audio_format'] = 'best';
        options['audio_quality'] = 0;
        options['format'] = 'bestaudio/best';
        break;
      default:
        break;
    }
  }

  void _applyManualSelectionOverrides(
    ManualDownloadOptionsModel? manualOptions,
    Map<String, dynamic> options,
  ) {
    if (manualOptions == null) {
      return;
    }
    if (manualOptions.onlyAudio) {
      options['extract_audio'] = true;
      options['video_resolution'] = 'none';
      options['video_subtitles'] = 'none';
      options['format'] = 'bestaudio/best';
    } else {
      options['extract_audio'] = false;
    }

    final resolution = manualOptions.resolution?.trim();
    if (resolution != null && resolution.isNotEmpty) {
      options['video_resolution'] = resolution;
    }
    final videoFormat = manualOptions.videoFormat?.trim();
    if (videoFormat != null && videoFormat.isNotEmpty) {
      options['merge_output_format'] = videoFormat;
    }
    final audioFormat = manualOptions.audioFormat?.trim();
    if (audioFormat != null && audioFormat.isNotEmpty) {
      options['audio_format'] = audioFormat;
    }
    final audioLanguage = manualOptions.audioLanguage?.trim();
    if (audioLanguage != null && audioLanguage.isNotEmpty) {
      options['audio_language'] = audioLanguage;
    }
    final subtitles = manualOptions.subtitles?.trim();
    if (subtitles != null && subtitles.isNotEmpty) {
      options['video_subtitles'] = subtitles;
    }
  }

  void _applyPreferenceOverrides(
    Map<String, dynamic>? overrides,
    Map<String, dynamic> options,
  ) {
    if (overrides == null || overrides.isEmpty) {
      return;
    }
    overrides.forEach((key, value) {
      if (value == null) {
        options.remove(key);
      } else {
        options[key] = value;
      }
    });
  }

  void _handlePendingInboxChanged() {
    debugPrint('[ShareIntentCoordinator] Pending inbox changed');
    if (_processingPendingDownloads) {
      _pendingDownloadsQueued = true;
      return;
    }
    _processPendingEntries();
  }

  void _handleBackendStateChanged() {
    debugPrint(
      '[ShareIntentCoordinator] Backend state changed: ready=$_backendReady '
      'pending=${_pendingNativeEntries.length}',
    );
    _maybeShowBackendStartupNotification();
    if (_backendReady) {
      _processPendingEntries();
    }
  }

  void _processPendingEntries() {
    debugPrint(
      '[ShareIntentCoordinator] _processPendingEntries backendReady=$_backendReady '
      'pendingNative=${_pendingNativeEntries.length}',
    );
    final entries = _pendingDownloadInbox.takeEntries();
    if (entries.isNotEmpty) {
      debugPrint(
        '[ShareIntentCoordinator] Pulled ${entries.length} entries from native inbox '
        'pendingBefore=${_pendingNativeEntries.length}',
      );
      for (final entry in entries) {
        final presetId = entry.presetId.isNotEmpty
            ? entry.presetId
            : (entry.payload.presetId ?? '');
        final key = _keyForPayload(entry.payload, presetId: presetId);
        if (_shouldAutoReturn(entry.payload, presetId)) {
          unawaited(_requestReturnToPreviousApp(entry.payload));
        }
        debugPrint(
          '[ShareIntentCoordinator] Native entry id=${entry.id} preset=$presetId '
          'urls=${entry.payload.urls.length} ts=${entry.addedAt.toIso8601String()} key=$key',
        );
        _enqueuePendingEntry(entry);
      }
      debugPrint(
        '[ShareIntentCoordinator] Pending after native pull=${_pendingNativeEntries.length}',
      );
    }
    if (_pendingNativeEntries.isEmpty) {
      _pendingExternalStartup = false;
      _notificationManager.dismissBackendStartupNotification();
      return;
    }
    if (!_backendReady) {
      return;
    }
    _processingPendingDownloads = true;
    unawaited(
      _handlePendingEntries().whenComplete(() {
        _processingPendingDownloads = false;
        if (_pendingDownloadsQueued) {
          _pendingDownloadsQueued = false;
          _processPendingEntries();
        }
      }),
    );
  }

  void _enqueuePendingEntry(PendingDownloadEntryModel entry) {
    final presetId = entry.presetId.isNotEmpty
        ? entry.presetId
        : (entry.payload.presetId ?? '');
    final key = _keyForPayload(entry.payload, presetId: presetId);
    if (entry.payload.directShare && _shareIntegrationSupported) {
      _pendingExternalStartup = true;
      _maybeShowBackendStartupNotification();
    }
    debugPrint(
      '[ShareIntentCoordinator] Enqueue entry id=${entry.id} preset=${entry.presetId} '
      'urls=${entry.payload.urls.length} key=$key '
      'pendingBefore=${_pendingNativeEntries.length}',
    );
    _pendingNativeEntries.add(entry);
    debugPrint(
      '[ShareIntentCoordinator] Pending after enqueue=${_pendingNativeEntries.length}',
    );
  }

  PendingDownloadEntryModel _fromPayload(ShareIntentPayload payload) {
    final presetId = payload.presetId ?? SharePresetIds.manual;
    return PendingDownloadEntryModel(
      id: payload.timestamp.millisecondsSinceEpoch.toString(),
      presetId: presetId,
      payload: payload,
      addedAt: DateTime.now(),
      options: null,
      preferenceOverrides: null,
    );
  }

  Future<void> _handlePendingEntries() async {
    while (_pendingNativeEntries.isNotEmpty) {
      if (!_backendReady) {
        return;
      }
      final entry = _pendingNativeEntries.first;
      final presetId = entry.presetId.isNotEmpty
          ? entry.presetId
          : (entry.payload.presetId ?? SharePresetIds.manual);
      final key = _keyForPayload(entry.payload, presetId: presetId);
      debugPrint(
        '[ShareIntentCoordinator] Processing entry id=${entry.id} preset=$presetId '
        'pending=${_pendingNativeEntries.length} key=$key backendReady=$_backendReady',
      );
      try {
        final success = await _runPreset(
          presetId,
          entry.payload,
          autoLaunch: true,
          requestReturn: false,
          preferenceOverrides: entry.preferenceOverrides,
          manualOptions: entry.options,
        );
        if (success) {
          debugPrint(
            '[ShareIntentCoordinator] Entry success id=${entry.id} key=$key',
          );
          _pendingNativeEntries.removeAt(0);
          if (_pendingNativeEntries.isEmpty) {
            _pendingExternalStartup = false;
            _notificationManager.dismissBackendStartupNotification();
          }
        } else {
          debugPrint(
            '[ShareIntentCoordinator] Entry failed id=${entry.id} key=$key',
          );
          return;
        }
      } catch (error, stackTrace) {
        debugPrint('Pending entry failed: $error key=$key');
        debugPrint(stackTrace.toString());
        return;
      }
    }
  }

  String _keyForPayload(
    ShareIntentPayload payload, {
    required String presetId,
  }) {
    final urls = payload.urls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .join('|');
    final raw = payload.rawText.trim();
    final source = payload.sourcePackage?.trim() ?? '';
    return 'p:$presetId|u:$urls|r:$raw|s:$source';
  }

  void _ensurePendingPullScheduled() {
    if (!_shareIntegrationSupported) {
      return;
    }
    _pendingPullTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_pendingDownloadInbox.pullFromNative());
    });
    unawaited(_pendingDownloadInbox.pullFromNative());
  }

  void _maybeShowBackendStartupNotification() {
    if (!_shareIntegrationSupported || !Platform.isAndroid) {
      return;
    }
    if (!_pendingExternalStartup) {
      _notificationManager.dismissBackendStartupNotification();
      return;
    }
    if (_backendReady) {
      _pendingExternalStartup = false;
      _notificationManager.dismissBackendStartupNotification();
      return;
    }
    _notificationManager.showBackendStartupNotification();
  }
}
