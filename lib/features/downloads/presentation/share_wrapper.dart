import 'dart:async';
import 'dart:io'; // <-- AÑADIDO PARA LA VALIDACIÓN DE PLATAFORMA
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
    // 🛡️ PROTECCIÓN DE PLATAFORMA: Los Intents de compartir solo existen en Móvil
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint(
        'Plataforma de escritorio detectada. Saltando inicialización de Intents.',
      );
      return;
    }
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((shared) {
          if (shared.isNotEmpty) _processShare(shared.first.path);
        })
        .catchError((e) {
          debugPrint('Error al obtener el Intent inicial: $e');
        });

    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (shared) {
            if (shared.isNotEmpty) _processShare(shared.first.path);
          },
          onError: (e) {
            debugPrint('Error en el Stream de Intents: $e');
          },
        );
  }

  void _processShare(String payload) async {
    // 1. Mostrar la pantalla de carga instantáneamente
    setState(() => _isPreparingOverlay = true);

    try {
      final match = RegExp(r'https?://[^\s]+').firstMatch(payload);
      final url = match != null ? match.group(0)! : payload;

      final settingsCtrl = context.read<SettingsController>();
      final currentOptsJson = settingsCtrl.getDownloadOptionsPayload();

      // PROTECCIÓN EXTRA: FlutterOverlayWindow solo funciona en Android
      if (Platform.isAndroid) {
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
      } else {
        // Si por algún milagro llega aquí en iOS u otra plataforma,
        // simplemente agregamos la descarga directamente sin Overlay.
        if (mounted) {
          context.read<DownloadsController>().addDownload(url, currentOptsJson);
        }
      }
    } finally {
      // 4. Apagar el spinner cuando el trabajo nativo haya terminado
      if (mounted) {
        setState(() => _isPreparingOverlay = false);
      }
    }
  }

  void _initOverlayListener() {
    // Escuchar el Overlay solo tiene sentido en Android
    if (!Platform.isAndroid) return;
    try {
      _overlayListener = FlutterOverlayWindow.overlayListener.listen((event) {
        if (event is Map && event["action"] == "START_DOWNLOAD") {
          final url = event["url"];
          final finalOptions = Map<String, dynamic>.from(event["options"]);

          if (mounted) {
            context.read<DownloadsController>().addDownload(url, finalOptions);
          }
        }
      });
    } catch (e) {
      debugPrint('Error inicializando el listener del Overlay: $e');
    }
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
