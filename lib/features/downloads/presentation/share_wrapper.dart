import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para el MethodChannel
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';

class ShareIntentWrapper extends StatefulWidget {
  final Widget child;

  const ShareIntentWrapper({super.key, required this.child});

  @override
  State<ShareIntentWrapper> createState() => _ShareIntentWrapperState();
}

class _ShareIntentWrapperState extends State<ShareIntentWrapper> {
  StreamSubscription? _intentDataStreamSubscription;
  StreamSubscription? _overlayListener;

  // 1. Declaramos nuestro canal nativo reciclado
  static const _platform = MethodChannel('vidra_channel');

  bool _isPreparingOverlay = false;

  @override
  void initState() {
    super.initState();
    _initIntents();
    _initOverlayListener();
  }

  void _initIntents() {
    ReceiveSharingIntent.instance.getInitialMedia().then((shared) {
      if (shared.isNotEmpty) _processShare(shared.first.path);
    });

    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((shared) {
          if (shared.isNotEmpty) _processShare(shared.first.path);
        });
  }

  void _processShare(String payload) async {
    // 1. Mostrar la pantalla de carga instantáneamente
    setState(() => _isPreparingOverlay = true);

    try {
      final match = RegExp(r'https?://[^\s]+').firstMatch(payload);
      final url = match != null ? match.group(0)! : payload;

      final settingsCtrl = context.read<SettingsController>();
      final currentOptsJson = settingsCtrl.getDownloadOptionsPayload();

      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        await FlutterOverlayWindow.requestPermission();
      }

      if (await FlutterOverlayWindow.isPermissionGranted()) {
        await FlutterOverlayWindow.showOverlay(
          width: WindowSize.matchParent,
          height: WindowSize.matchParent,
          alignment: OverlayAlignment.bottomCenter,
          enableDrag: false,
          flag: OverlayFlag.focusPointer,
          startPosition: OverlayPosition(0, 0),
        );

        // 2. Enviamos los datos + el tema actual
        await FlutterOverlayWindow.shareData({
          "url": url,
          "options": currentOptsJson,
        });

        // 3. Mandamos la app al fondo
        try {
          await _platform.invokeMethod('moveToBackground');
        } catch (e) {
          debugPrint('Error mandando la app al fondo: $e');
        }
      } else {
        debugPrint('Permiso de overlay no concedido');
      }
    } finally {
      // 4. Apagar el spinner cuando el trabajo nativo haya terminado
      if (mounted) {
        setState(() => _isPreparingOverlay = false);
      }
    }
  }

  void _initOverlayListener() {
    _overlayListener = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map && event["action"] == "START_DOWNLOAD") {
        final url = event["url"];
        final finalOptions = Map<String, dynamic>.from(event["options"]);

        // ignore: use_build_context_synchronously
        context.read<DownloadsController>().addDownload(url, finalOptions);
      }
    });
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    _overlayListener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NUEVO: Envolvemos tu app principal en un Stack para mostrar el Loading
    return Stack(
      children: [
        widget.child, // Tu app normal
        // El velo oscuro con el Loading
        if (_isPreparingOverlay)
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.6), // Fondo oscuro
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
