import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

class FatalErrorDialog extends StatelessWidget {
  final VoidCallback? onRestart;

  const FatalErrorDialog({super.key, this.onRestart});

  static bool _isOpen = false;

  /// Muestra el diálogo modal no descartable de error fatal
  static Future<void> show([
    BuildContext? context,
    VoidCallback? onRestart,
  ]) async {
    if (_isOpen) return;

    final targetContext = context ?? ToastUtils.navigatorKey.currentContext;
    if (targetContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final delayedContext = ToastUtils.navigatorKey.currentContext;
        if (delayedContext != null) {
          show(delayedContext, onRestart);
        }
      });
      return;
    }

    _isOpen = true;
    try {
      await showDialog(
        context: targetContext,
        barrierDismissible: false,
        builder: (ctx) => FatalErrorDialog(onRestart: onRestart),
      );
    } finally {
      _isOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    AppStringKey? locale;
    try {
      locale = context.read<LocaleController>().localeStrings;
    } catch (_) {
      // Fallback si no está disponible LocaleController en el árbol
    }

    final title = (locale != null && locale.feTitle.isNotEmpty)
        ? locale.feTitle
        : 'Fatal System Error';
    final message = (locale != null && locale.feMessage.isNotEmpty)
        ? locale.feMessage
        : 'The download engine failed to load after an update. Please restart the application.';
    final restartBtn = (locale != null && locale.feRestartButton.isNotEmpty)
        ? locale.feRestartButton
        : 'Restart Application';

    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 48),
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton.icon(
            onPressed: () {
              if (onRestart != null) {
                onRestart!();
              } else {
                exit(0);
              }
            },
            icon: const Icon(Icons.power_settings_new),
            label: Text(restartBtn),
          ),
        ],
      ),
    );
  }
}
