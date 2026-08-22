import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_screen_overlay/flutter_screen_overlay.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

class ShareIntentWrapper extends StatefulWidget {
  final Widget child;

  const ShareIntentWrapper({super.key, required this.child});

  @override
  State<ShareIntentWrapper> createState() => ShareIntentWrapperState();
}

class ShareIntentWrapperState extends State<ShareIntentWrapper>
    with WidgetsBindingObserver {
  @visibleForTesting
  static bool? debugOverrideIsAndroid;

  bool get _isAndroid => debugOverrideIsAndroid ?? Platform.isAndroid;

  StreamSubscription? _intentDataStreamSubscription;
  static const _platform = MethodChannel('vidra_channel');
  int _activeIntentCount = 0;
  bool get _isPreparingOverlay => _activeIntentCount > 0;

  final List<Completer<void>> _resumeCompleters = [];

  @visibleForTesting
  Duration resumeTimeout = const Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('🦁 [MAIN] Wrapper limpio iniciado. Escuchando intents...');
    _initIntents();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final waiters = List<Completer<void>>.from(_resumeCompleters);
      _resumeCompleters.clear();
      for (final completer in waiters) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }
  }

  Future<void> _waitForResume() async {
    final completer = Completer<void>();
    _resumeCompleters.add(completer);
    try {
      await completer.future.timeout(resumeTimeout);
    } on TimeoutException {
      debugPrint(
        '⏳ [ShareWrapper] Timeout esperando el retorno a la aplicación (resumed)',
      );
    } catch (e) {
      debugPrint('⚠️ [ShareWrapper] Error esperando resumed: $e');
    } finally {
      _resumeCompleters.remove(completer);
    }
  }

  // --- LÓGICA DE COMPARTIR NATIVA ---
  void _initIntents() {
    if (!_isAndroid && !Platform.isIOS) return;
    // 1. App en memoria (segundo plano)
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((value) {
          if (value.isNotEmpty) _processIntent(value.first.path);
        });
    // 2. App arranca desde cero (frío)
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) _processIntent(value.first.path);
    });
  }

  @visibleForTesting
  Future<void> processIntentForTesting(String url) => _processIntent(url);

  Future<void> _processIntent(String url) async {
    if (url.trim().isEmpty) return;
    if (!mounted) return;
    setState(() => _activeIntentCount++);

    try {
      final settingsCtrl = context.read<SettingsController>();
      final systemCtrl = context.read<SystemController>();
      final currentOptsJson = settingsCtrl.getDownloadOptionsPayload();
      final localeCtrl = context.read<LocaleController>();
      final locale = localeCtrl.localeStrings;

      if (_isAndroid) {
        bool isGranted = false;
        try {
          isGranted = await FlutterScreenOverlay.isPermissionGranted();
          if (!isGranted) {
            unawaited(
              FlutterScreenOverlay.requestPermission().catchError((_) => false),
            );
            debugPrint(
              '⏳ Esperando que el usuario regrese a la app para continuar...',
            );
            await _waitForResume();
            if (!mounted) return;
            isGranted = await FlutterScreenOverlay.isPermissionGranted();
          }
        } catch (e) {
          debugPrint(
            '⚠️ [ShareWrapper] Error verificando/solicitando permiso de overlay: $e',
          );
          isGranted = false;
        }

        if (!mounted) return;

        if (isGranted) {
          try {
            debugPrint(
              '⏳ Esperando confirmación del puerto del Isolate y Locales...',
            );
            await systemCtrl.whenPortReady;
            await localeCtrl.whenReady;
            if (!mounted) return;
            // Refresh the locale with the updated strings
            final currentLocale = localeCtrl.localeStrings;
            debugPrint('🦁 [MAIN] Lanzando Overlay...');
            await FlutterScreenOverlay.showOverlay(
              height: WindowSize.matchParent,
              width: WindowSize.matchParent,
              alignment: OverlayAlignment.bottomCenter,
              visibility: NotificationVisibility.visibilitySecret,
              flag: OverlayFlag.focusPointer,
              overlayTitle: "Fast download selector",
              overlayContent: null,
              enableDrag: false,
              positionGravity: PositionGravity.none,
              startPosition: OverlayPosition(0, 0),
            );

            // Solo enviamos URL y Opciones. El puerto y token ya no son necesarios
            // porque el Overlay hablará por IPC (IsolateNameServer)
            await FlutterScreenOverlay.shareData({
              'url': url,
              'options': currentOptsJson,
              'locale': currentLocale.toJson(),
            });

            // Ocultamos la UI mandándola a segundo plano inmediatamente
            try {
              await _platform.invokeMethod('moveToBackground');
            } catch (e) {
              debugPrint('Error enviando al background: $e');
            }
          } catch (e) {
            debugPrint(
              '⚠️ [ShareWrapper] Fallo al mostrar overlay, enviando directo a descargas: $e',
            );
            if (mounted) {
              final result = await context
                  .read<DownloadsController>()
                  .addDownload(url, currentOptsJson);
              if (result) {
                ToastUtils.showInfo(locale.shwOverlayDeniedDownloading);
              } else {
                ToastUtils.showError(locale.shwDownloadSentError);
              }
            }
          }
        } else {
          // Si no hay permiso de overlay, mandamos directo a la UI
          if (mounted) {
            final result = await context
                .read<DownloadsController>()
                .addDownload(url, currentOptsJson);
            if (result) {
              ToastUtils.showInfo(locale.shwOverlayDeniedDownloading);
            } else {
              ToastUtils.showError(locale.shwDownloadSentError);
            }
          }
        }
      } else {
        if (mounted) {
          final result = await context.read<DownloadsController>().addDownload(
            url,
            currentOptsJson,
          );
          if (result) {
            ToastUtils.showInfo(locale.shwDownloadSent);
          } else {
            ToastUtils.showError(locale.shwDownloadSentError);
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          if (_activeIntentCount > 0) _activeIntentCount--;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentDataStreamSubscription?.cancel();
    final waiters = List<Completer<void>>.from(_resumeCompleters);
    _resumeCompleters.clear();
    for (final completer in waiters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().localeStrings;
    return Stack(
      children: [
        widget.child,
        if (_isPreparingOverlay)
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      locale.shwLoadingSelector,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
