import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_screen_overlay/flutter_screen_overlay.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

class ShareIntentWrapper extends StatefulWidget {
  final Widget child;

  const ShareIntentWrapper({super.key, required this.child});

  @override
  State<ShareIntentWrapper> createState() => _ShareIntentWrapperState();
}

class _ShareIntentWrapperState extends State<ShareIntentWrapper> {
  StreamSubscription? _intentDataStreamSubscription;
  static const _platform = MethodChannel('vidra_channel');
  bool _isPreparingOverlay = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🦁 [MAIN] Wrapper limpio iniciado. Escuchando intents...');
    _initIntents();
  }

  // --- LÓGICA DE COMPARTIR NATIVA ---
  void _initIntents() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
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

  Future<void> _processIntent(String url) async {
    if (url.trim().isEmpty) return;
    setState(() => _isPreparingOverlay = true);

    try {
      final settingsCtrl = context.read<SettingsController>();
      final systemCtrl = context.read<SystemController>();
      final currentOptsJson = settingsCtrl.getDownloadOptionsPayload();

      if (Platform.isAndroid) {
        bool isGranted = await FlutterScreenOverlay.isPermissionGranted();
        if (isGranted) {
          debugPrint('⏳ Esperando confirmación del puerto del Isolate...');
          await systemCtrl.whenPortReady;
          debugPrint('🦁 [MAIN] Lanzando Overlay...');
          await FlutterScreenOverlay.showOverlay(
            enableDrag: false,
            flag: OverlayFlag.defaultFlag,
            alignment: OverlayAlignment.bottomCenter,
            visibility: NotificationVisibility.visibilitySecret,
            positionGravity: PositionGravity.auto,
            startPosition: OverlayPosition(0, 0),
          );

          // Solo enviamos URL y Opciones. El puerto y token ya no son necesarios
          // porque el Overlay hablará por IPC (IsolateNameServer)
          await FlutterScreenOverlay.shareData({
            'url': url,
            'options': currentOptsJson,
          });

          // Ocultamos la UI mandándola a segundo plano inmediatamente
          try {
            await _platform.invokeMethod('moveToBackground');
          } catch (e) {
            debugPrint('Error enviando al background: $e');
          }
        } else {
          // Si no hay permiso de overlay, mandamos directo a la UI
          if (mounted) {
            context.read<DownloadsController>().addDownload(
              url,
              currentOptsJson,
            );
          }
        }
      } else {
        if (mounted) {
          context.read<DownloadsController>().addDownload(url, currentOptsJson);
        }
      }
    } finally {
      if (mounted) setState(() => _isPreparingOverlay = false);
    }
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isPreparingOverlay)
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Cargando selector...',
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
