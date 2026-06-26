import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/shared/utils/notification_service.dart';

class ShareIntentWrapper extends StatefulWidget {
  final Widget child;

  const ShareIntentWrapper({super.key, required this.child});

  @override
  State<ShareIntentWrapper> createState() => _ShareIntentWrapperState();
}

class _ShareIntentWrapperState extends State<ShareIntentWrapper>
    with WidgetsBindingObserver {
  StreamSubscription? _intentDataStreamSubscription;
  static StreamSubscription? _globalOverlayListener;

  // 1. Declaramos nuestro canal nativo reciclado
  static const _platform = MethodChannel('vidra_channel');

  bool _isPreparingOverlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('🦁 [MAIN] Wrapper InitState. Suscribiendo listeners...');
    _initIntents();
    _initOverlayListener();
    _processPersistentQueue();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentDataStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('🦁 [MAIN] Cambio de ciclo de vida nativo: ${state.name}');
    // ponytail: Al regresar a primer plano, vaciamos la caja de descargas perdidas
    if (state == AppLifecycleState.resumed) {
      debugPrint('🦁 [MAIN] App regresó al frente. Revisando caja fuerte...');
      _processPersistentQueue();
    }
  }

  Future<void> _processPersistentQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final queue = prefs.getStringList('vidra_pending_queue') ?? [];
      debugPrint('🦁 [MAIN] Caja fuerte revisada. Elementos: ${queue.length}');
      if (queue.isEmpty) return;

      for (var item in queue) {
        final data = jsonDecode(item);
        final url = data["url"].toString();
        final options = Map<String, dynamic>.from(data["options"]);
        if (mounted) {
          debugPrint('🦁 [MAIN] Encolando descarga desde caja fuerte: $url');
          context.read<DownloadsController>().addDownload(url, options);
        }
      }

      await prefs.setStringList('vidra_pending_queue', []);
      debugPrint('🦁 [MAIN] Caja fuerte vaciada.');
      debugPrint('📥 ${queue.length} descargas rescatadas de la caja fuerte.');
    } catch (e) {
      debugPrint('🦁 [MAIN] Error en queue persistente: $e');
    }
  }

  Future<void> _removeFromQueue(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final queue = prefs.getStringList('vidra_pending_queue') ?? [];
      if (queue.isEmpty) return;

      final newQueue = queue
          .where((item) => jsonDecode(item)["url"] != url)
          .toList();
      await prefs.setStringList('vidra_pending_queue', newQueue);
      debugPrint(
        '🦁 [MAIN] URL eliminada de caja fuerte porque llegó por MethodChannel.',
      );
    } catch (e) {
      debugPrint('🦁 [MAIN] Error al remover de la queue persistente: $e');
    }
  }

  // --- ESCUCHA DIRECTA (Solo funciona si el hilo no está dormido) ---
  void _initOverlayListener() {
    if (!Platform.isAndroid) return;
    if (_globalOverlayListener != null) {
      debugPrint('🦁 [MAIN] El listener ya estaba activo, saltando creación.');
      return;
    }
    try {
      _globalOverlayListener = FlutterOverlayWindow.overlayListener.listen((
        event,
      ) {
        debugPrint(
          '🦁 [MAIN] EVENTO MethodChannel recibido desde el Overlay: $event',
        );
        if (event is Map && event["action"] == "START_DOWNLOAD") {
          try {
            final url = event["url"].toString();
            final finalOptions = Map<String, dynamic>.from(event["options"]);

            if (mounted) {
              debugPrint(
                '🦁 [MAIN] Encolando descarga vía MethodChannel: $url',
              );
              context.read<DownloadsController>().addDownload(
                url,
                finalOptions,
              );
            }
            // Si el MethodChannel funcionó, lo borramos de la caja fuerte para no duplicar
            _removeFromQueue(url);
          } catch (e) {
            debugPrint('🦁 [MAIN] Error parseando evento del overlay: $e');
          }
        }
      });
      debugPrint('🦁 [MAIN] Listener global conectado exitosamente.');
    } catch (e) {
      debugPrint('🦁 [MAIN] Error inicializando el listener del Overlay: $e');
    }
  }

  // --- LÓGICA DE COMPARTIR NATIVA ---
  void _initIntents() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((shared) {
          if (shared.isNotEmpty) _processShare(shared.first.path);
        })
        .catchError((e) {
          debugPrint('Error Initial Intent: $e');
        });

    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (shared) {
            if (shared.isNotEmpty) _processShare(shared.first.path);
          },
          onError: (e) {
            debugPrint('Error Stream Intent: $e');
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
      final sysCtrl = context
          .read<SystemController>(); // <-- ¡CRÍTICO! Traemos el Cerebro
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
            "port": sysCtrl.backendPort,
            "token": sysCtrl.backendToken,
          });

          // 3. Mandamos la app al fondo
          try {
            // Levantamos los escudos
            await NotificationService.keepAppAlive();
            // Mandamos la Activity al fondo
            debugPrint(
              '🦁 [MAIN] Método moveToBackground invocado desde MethodChannel.',
            );
            await _platform.invokeMethod('moveToBackground');
          } catch (e) {
            debugPrint('Error enviando al background: $e');
          }
        } else {
          debugPrint('Permiso de overlay no concedido');
        }
      } else {
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
