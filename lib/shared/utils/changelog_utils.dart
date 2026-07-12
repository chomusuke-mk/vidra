import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';

class ChangelogUtils {
  /// Despliega el modal limitando su tamaño horizontal y vertical
  static Future<void> showChangelogDialog(BuildContext context) async {
    String changelogContent = '';
    final locale = context.read<LocaleController>().localeStrings;
    try {
      changelogContent = await rootBundle.loadString('CHANGELOG.md');
    } catch (e) {
      changelogContent = locale.clFileLoadingError;
    }

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(locale.clTitle),
        content: SizedBox(
          width:
              550, // <-- Limita el crecimiento horizontal infinito en pantallas anchas
          height:
              450, // <-- Altura fija requerida para el scroll interno de Markdown
          child: Markdown(data: changelogContent, selectable: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(locale.clClose),
          ),
        ],
      ),
    );
  }

  /// Verifica la versión actual y lo muestra de forma automática si es un cambio de versión
  static Future<void> checkFirstTime(BuildContext context) async {
    final prefs = context.read<SharedPreferences>();
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final lastVersion = prefs.getString('last_seen_changelog_version');

    if (lastVersion != currentVersion) {
      await prefs.setString('last_seen_changelog_version', currentVersion);
      if (context.mounted) {
        await showChangelogDialog(context);
      }
    }
  }
}
