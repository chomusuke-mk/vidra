import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/ui/widgets/preferences/preference_dropdown_control.dart';

class MagicOptionsSheet {
  const MagicOptionsSheet._();

  static Future<T?> show<T>(BuildContext context) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _MagicOptionsContent(),
    );
  }
}

class _MagicOptionsContent extends StatelessWidget {
  const _MagicOptionsContent();

  static const double _compactControlMinWidth = 220;

  @override
  Widget build(BuildContext context) {
    final preferencesModel = context.watch<PreferencesModel>();
    final preferences = preferencesModel.preferences;
    final languageValue = preferencesModel.effectiveLanguage;
    final localizations = VidraLocalizations.of(context);

    final mergeControl = PreferenceDropdownControl(
      preference: preferences.mergeOutputFormat,
      leadingIcon: const Icon(Icons.videocam_outlined),
      label: Text(
        preferences.mergeOutputFormat.get('name', languageValue) as String,
      ),
      minCompactWidth: _compactControlMinWidth,
    );
    final audioControl = PreferenceDropdownControl(
      preference: preferences.audioLanguage,
      leadingIcon: const Icon(Icons.language_outlined),
      label: Text(
        preferences.audioLanguage.get('name', languageValue) as String,
      ),
      writeable: true,
      minCompactWidth: _compactControlMinWidth,
    );
    final subtitlesControl = PreferenceDropdownControl(
      preference: preferences.videoSubtitles,
      leadingIcon: const Icon(Icons.subtitles_outlined),
      label: Text(
        preferences.videoSubtitles.get('name', languageValue) as String,
      ),
      writeable: true,
      minCompactWidth: _compactControlMinWidth,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    localizations.ui(AppStringKey.homeOptionsTitle),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: localizations.ui(AppStringKey.homeCloseAction),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                mergeControl,
                const SizedBox(height: 12),
                audioControl,
                const SizedBox(height: 12),
                subtitlesControl,
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
