import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vidra/core/theme/colors.dart';
import 'package:vidra/core/theme/typography.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

class LinuxAppImageUpdateDialog extends StatelessWidget {
  final VoidCallback? onDismiss;

  const LinuxAppImageUpdateDialog({
    super.key,
    this.onDismiss,
  });

  static String get appImageCommand {
    final currentPath =
        Platform.environment['APPIMAGE'] ?? './vidra-x86_64.AppImage';
    return 'wget -O AppImageUpdate-x86_64.AppImage https://github.com/AppImageCommunity/AppImageUpdate/releases/download/continuous/AppImageUpdate-x86_64.AppImage && '
        'chmod +x AppImageUpdate-x86_64.AppImage && '
        './AppImageUpdate-x86_64.AppImage "$currentPath"';
  }

  static Future<void> show([BuildContext? context]) async {
    final targetContext = context ?? ToastUtils.navigatorKey.currentContext;
    if (targetContext == null) return;

    await showDialog(
      context: targetContext,
      builder: (ctx) => const LinuxAppImageUpdateDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().localeStrings;
    final cmd = appImageCommand;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(locale.sdLinuxAppImageTitle)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locale.sdLinuxAppImageMsg),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).extension<VidraSemanticColors>()?.borderSubtle ??
                    Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: SelectableText(
              cmd,
              style: context.consoleLog.copyWith(
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
            await Clipboard.setData(ClipboardData(text: cmd));
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
