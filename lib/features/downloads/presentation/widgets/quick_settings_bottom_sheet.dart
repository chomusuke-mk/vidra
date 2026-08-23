import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/core/constants/languages.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/domain/download_option_formatters.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/shared/widgets/lazy_dropdown.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

/// In-app Quick Settings Modal Bottom Sheet for DownloadsScreen.
/// Synchronized directly with global [SettingsController] and [DownloadOptions].
class QuickSettingsBottomSheet extends StatelessWidget {
  const QuickSettingsBottomSheet({super.key});

  /// Displays the [QuickSettingsBottomSheet] as a modal bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => const QuickSettingsBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().localeStrings;
    final settingsCtrl = context.watch<SettingsController>();
    final opts = settingsCtrl.downloadOptions;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              _buildDragHandle(context),
              _buildHeader(context, locale),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPlaylistTile(
                        context,
                        settingsCtrl,
                        opts,
                        locale,
                      ),
                      const SizedBox(height: 16),
                      _buildModeToggle(
                        context,
                        settingsCtrl,
                        opts,
                        locale,
                      ),
                      const SizedBox(height: 20),
                      if (opts.extractAudio)
                        _buildAudioControls(
                          context,
                          settingsCtrl,
                          opts,
                          locale,
                        )
                      else
                        _buildVideoControls(
                          context,
                          settingsCtrl,
                          opts,
                          locale,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildDragHandle(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppStringKey locale) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.construction_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              locale.qsTitle,
              style:
                  Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ) ??
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: locale.qsClose,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistTile(
    BuildContext context,
    SettingsController settingsCtrl,
    DownloadOptions opts,
    AppStringKey locale,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        locale.sPlaylist,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        locale.sPlaylistDesc,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      value: opts.playlist,
      onChanged: (bool value) {
        settingsCtrl.updateDownloadOptions(opts.copyWith(playlist: value));
      },
    );
  }

  Widget _buildModeToggle(
    BuildContext context,
    SettingsController settingsCtrl,
    DownloadOptions opts,
    AppStringKey locale,
  ) {
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment<bool>(
          value: false,
          icon: const Icon(Icons.movie_outlined),
          label: Text(locale.sVideo),
        ),
        ButtonSegment<bool>(
          value: true,
          icon: const Icon(Icons.music_note_outlined),
          label: Text(locale.sExtractAudio),
        ),
      ],
      selected: {opts.extractAudio},
      onSelectionChanged: (Set<bool> newSelection) {
        settingsCtrl.updateDownloadOptions(
          opts.copyWith(extractAudio: newSelection.first),
        );
      },
    );
  }

  Widget _buildAudioControls(
    BuildContext context,
    SettingsController settingsCtrl,
    DownloadOptions opts,
    AppStringKey locale,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          locale.sAudioFormat,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        LazyDropdown<AudioFormat>(
          value: opts.audioFormat,
          items: AudioFormat.values,
          label: locale.sAudioFormat,
          labelBuilder: (AudioFormat format) => format.name.toUpperCase(),
          onChanged: (AudioFormat val) {
            settingsCtrl.updateDownloadOptions(
              opts.copyWith(audioFormat: val),
            );
          },
        ),
      ],
    );
  }

  Widget _buildVideoControls(
    BuildContext context,
    SettingsController settingsCtrl,
    DownloadOptions opts,
    AppStringKey locale,
  ) {
    final currentVideoVal =
        DownloadOptionFormatters.resolveCurrentVideoVal(opts);
    final currentAudioVal =
        DownloadOptionFormatters.resolveCurrentAudioVal(opts);

    final List<String> friendlySuggestions = languagesCodes.map((code) {
      final name = languagesEndonyms[code] ?? code;
      return '$code - $name';
    }).toList();

    final List<String> visualSubList = opts.subLangs.map((code) {
      final name = languagesEndonyms[code] ?? code;
      return '$code - $name';
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          locale.sVideoResolution,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        LazyDropdown<String>(
          value: currentVideoVal,
          items: DownloadOptionFormatters.videoResolutionOptions,
          label: locale.sVideoResolution,
          labelBuilder: (String val) =>
              DownloadOptionFormatters.formatResolution(val, locale),
          onChanged: (String val) {
            if (val == 'defaultOption') {
              settingsCtrl.updateDownloadOptions(
                opts.copyWith(videoResolution: VideoOption.defaultOption),
              );
            } else if (val == 'bestvideo') {
              settingsCtrl.updateDownloadOptions(
                opts.copyWith(videoResolution: VideoOption.bestvideo),
              );
            } else {
              settingsCtrl.updateDownloadOptions(
                opts.copyWith(
                  videoResolution: VideoOption.resolution,
                  videoResolutionValue: val,
                ),
              );
            }
          },
        ),
        const SizedBox(height: 14),
        Text(
          locale.sMergeOutputFormat,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        LazyDropdown<MergeOutputFormat>(
          value: opts.mergeOutputFormat,
          items: MergeOutputFormat.values,
          label: locale.sMergeOutputFormat,
          labelBuilder: (MergeOutputFormat format) => format.name.toUpperCase(),
          onChanged: (MergeOutputFormat val) {
            settingsCtrl.updateDownloadOptions(
              opts.copyWith(mergeOutputFormat: val),
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          locale.sAudioLanguage,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        LazyDropdown<String>(
          value: currentAudioVal,
          items: DownloadOptionFormatters.audioLanguageOptions,
          label: locale.sAudioLanguage,
          enableSearch: true,
          labelBuilder: (String val) =>
              DownloadOptionFormatters.formatLanguage(val, locale),
          onChanged: (String val) {
            if (val == 'defaultOption') {
              settingsCtrl.updateDownloadOptions(
                opts.copyWith(audioLanguage: AudioOption.defaultOption),
              );
            } else if (val == 'bestaudio') {
              settingsCtrl.updateDownloadOptions(
                opts.copyWith(audioLanguage: AudioOption.bestaudio),
              );
            } else {
              settingsCtrl.updateDownloadOptions(
                opts.copyWith(
                  audioLanguage: AudioOption.language,
                  audioLanguageCode: val,
                ),
              );
            }
          },
        ),
        const SizedBox(height: 14),

        // Subtitle Languages (subLangs)
        Text(
          locale.sSubLangs,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        LazyList(
          value: visualSubList,
          suggestions: friendlySuggestions,
          label: locale.sSearchLang,
          onChanged: (List<String> newList) {
            final codesToSave = newList.map((item) {
              return item.split(' - ').first.trim();
            }).toList();
            settingsCtrl.updateDownloadOptions(
              opts.copyWith(subLangs: codesToSave),
            );
          },
        ),
      ],
    );
  }
}
