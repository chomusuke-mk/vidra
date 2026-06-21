import 'package:flutter/material.dart';

class ToastUtils {
  // Magia senior: Una llave global nos permite mostrar notificaciones
  // desde cualquier parte de la app, incluso sin BuildContext (ej. dentro de un Controller).
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void _show(String message, Color bgColor, IconData icon) {
    // 1. Matamos cualquier notificación que esté en pantalla AHORA MISMO.
    // Esto evita la "cola infinita" de 15 segundos.
    messengerKey.currentState?.hideCurrentSnackBar();

    // 2. Mostramos la nueva instantáneamente.
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating, // Flotante se ve mucho más limpio
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        showCloseIcon: true,
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- MÉTODOS PÚBLICOS PEREZOSOS ---

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
