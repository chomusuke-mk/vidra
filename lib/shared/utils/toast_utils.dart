import 'dart:async';
import 'package:flutter/material.dart';

class ToastUtils {
  // 1. Cambiamos de ScaffoldMessengerKey a NavigatorKey.
  // Esto nos da acceso a la capa "Overlay" (el nivel más alto en la jerarquía visual),
  // garantizando que las notificaciones aparezcan sobre CUALQUIER elemento flotante.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static OverlayEntry? _currentOverlay;
  static _ToastWidgetState? _currentState;
  static Timer? _timer;

  static void _show(String message, Color bgColor, IconData icon) {
    // 2. Matamos al instante la notificación anterior si entra una nueva
    _timer?.cancel();
    _killCurrent();

    final overlayState = navigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    // 3. Creamos el nuevo Toast con su animación
    _currentOverlay = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        bgColor: bgColor,
        icon: icon,
        onStateCreated: (state) => _currentState = state,
        onCloseTap: () => _hideCurrent(animate: true),
      ),
    );

    // 4. Lo inyectamos en la pantalla
    overlayState.insert(_currentOverlay!);

    // 5. Programamos su salida animada después de 3 segundos
    _timer = Timer(
      const Duration(seconds: 3),
      () => _hideCurrent(animate: true),
    );
  }

  static void _killCurrent() {
    if (_currentOverlay != null) {
      _currentOverlay!.remove();
      _currentOverlay = null;
      _currentState = null;
    }
  }

  static Future<void> _hideCurrent({bool animate = false}) async {
    final targetOverlay = _currentOverlay;
    if (targetOverlay == null) return;

    _timer?.cancel();

    if (animate && _currentState != null) {
      // Esperamos que termine la animación de salida (Bounce/Fade Out)
      await _currentState!.reverse();
    }

    // Si nadie interrumpió y sobrescribió la notificación en este lapso:
    if (_currentOverlay == targetOverlay) {
      _killCurrent();
    }
  }

  // --- MÉTODOS PÚBLICOS ---

  static void showError(String message) {
    _show(message, Colors.red.shade700, Icons.error_outline);
  }

  static void showSuccess(String message) {
    _show(message, Colors.green.shade700, Icons.check_circle_outline);
  }

  static void showInfo(String message) {
    _show(message, Colors.blue.shade700, Icons.info_outline);
  }
}

// =====================================================================
// WIDGET INTERNO ANIMADO
// =====================================================================
class _ToastWidget extends StatefulWidget {
  final String message;
  final Color bgColor;
  final IconData icon;
  final Function(_ToastWidgetState) onStateCreated;
  final VoidCallback onCloseTap;

  const _ToastWidget({
    required this.message,
    required this.bgColor,
    required this.icon,
    required this.onStateCreated,
    required this.onCloseTap,
  });

  @override
  _ToastWidgetState createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Animación de Deslizamiento con rebote sutil (Entra desde abajo)
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeIn,
          ),
        );

    // Animación de Opacidad (Fade In/Out)
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();
  }

  Future<void> reverse() async {
    if (mounted) {
      await _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Material es vital en un Overlay para que los textos hereden el estilo por defecto
      // y no aparezcan con subrayados amarillos
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: widget.bgColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onCloseTap,
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
