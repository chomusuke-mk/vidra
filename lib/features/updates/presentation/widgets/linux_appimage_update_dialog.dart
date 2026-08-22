import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

class LinuxAppImageUpdateDialog extends StatelessWidget {
  final VoidCallback? onDismiss;

  const LinuxAppImageUpdateDialog({
    super.key,
    this.onDismiss,
  });

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

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.purple),
          const SizedBox(width: 8),
          Expanded(child: Text(locale.sdLinuxAppImageTitle)),
        ],
      ),
      content: Text(locale.sdLinuxAppImageMsg),
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.open_in_browser, size: 18),
          label: const Text('GitHub'),
          onPressed: () async {
            final uri = Uri.parse(
              'https://github.com/chomusuke-mk/vidra/releases/latest',
            );
            await launchUrl(uri, mode: LaunchMode.externalApplication);
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
