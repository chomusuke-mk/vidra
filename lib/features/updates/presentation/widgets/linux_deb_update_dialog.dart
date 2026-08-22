import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

class LinuxDebUpdateDialog extends StatelessWidget {
  final VoidCallback? onDismiss;

  const LinuxDebUpdateDialog({
    super.key,
    this.onDismiss,
  });

  static const String aptCommand =
      'sudo apt update && sudo apt install --only-upgrade vidra';

  static Future<void> show([BuildContext? context]) async {
    final targetContext = context ?? ToastUtils.navigatorKey.currentContext;
    if (targetContext == null) return;

    await showDialog(
      context: targetContext,
      builder: (ctx) => const LinuxDebUpdateDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().localeStrings;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(child: Text(locale.sdLinuxDebTitle)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locale.sdLinuxDebMsg),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              ),
            ),
            child: SelectableText(
              aptCommand,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton.tonalIcon(
          icon: const Icon(Icons.copy, size: 18),
          label: Text(locale.sdCopyCommand),
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: aptCommand));
            ToastUtils.showSuccess(locale.sdCommandCopied);
          },
        ),
        TextButton(
          onPressed: () {
            if (onDismiss != null) {
              onDismiss!();
            } else {
              Navigator.of(context, rootNavigator: true).maybePop();
            }
          },
          child: Text(locale.sdClose),
        ),
      ],
    );
  }
}
