import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/shared/widgets/inline_time_picker.dart';
import 'package:vidra/shared/widgets/lazy_list.dart';

/// Modal bottom sheet for configuring SponsorBlock segment removal.
/// Follows the same visual pattern and styling as [QuickSettingsBottomSheet].
class CutVideoBottomSheet extends StatelessWidget {
  const CutVideoBottomSheet({super.key});

  /// Displays the [CutVideoBottomSheet] as a modal bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => const CutVideoBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().localeStrings;
    final settingsCtrl = context.watch<SettingsController>();
    final opts = settingsCtrl.downloadOptions;

    final suggestions = SponsorblockCategory.values.map((e) => e.name).toList();
    final visualList = opts.sponsorblockRemove.map((e) => e.name).toList();

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
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            locale.sForceKeyframesAtCuts,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            locale.sForceKeyframesAtCutsDesc,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          value: opts.forceKeyframesAtCuts,
                          onChanged: (val) {
                            settingsCtrl.updateDownloadOptions(
                              opts.copyWith(forceKeyframesAtCuts: val),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Text(
                          locale.sSponsorblockRemove,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          locale.cvDescription,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        LazyList(
                          value: visualList,
                          suggestions: suggestions,
                          label: locale.sSearchCategory,
                          onChanged: (newList) {
                            final newEnums = newList.map((item) {
                              return SponsorblockCategory.values.firstWhere(
                                (e) => e.name == item,
                                orElse: () => SponsorblockCategory.sponsor,
                              );
                            }).toList();
                            settingsCtrl.updateDownloadOptions(
                              opts.copyWith(sponsorblockRemove: newEnums),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            locale.sCutVideo,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            locale.sCutVideoDesc,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          value: opts.cutVideo,
                          onChanged: (val) {
                            settingsCtrl.updateDownloadOptions(
                              opts.copyWith(cutVideo: val),
                            );
                          },
                        ),
                        if (opts.cutVideo) ...[
                          const SizedBox(height: 12),
                          InlineTimePicker(
                            label: locale.sCutVideoStart,
                            initialSeconds: opts.cutVideoStart,
                            onChanged: (newSec) {
                              settingsCtrl.updateDownloadOptions(
                                opts.copyWith(cutVideoStart: newSec),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              locale.sCutVideoUntilEnd,
                              style: const TextStyle(fontSize: 14),
                            ),
                            value: opts.cutVideoUntilEnd,
                            onChanged: (val) {
                              settingsCtrl.updateDownloadOptions(
                                opts.copyWith(cutVideoUntilEnd: val),
                              );
                            },
                          ),
                          if (!opts.cutVideoUntilEnd) ...[
                            const SizedBox(height: 8),
                            InlineTimePicker(
                              label: locale.sCutVideoEnd,
                              initialSeconds: opts.cutVideoEnd,
                              onChanged: (newSec) {
                                settingsCtrl.updateDownloadOptions(
                                  opts.copyWith(cutVideoEnd: newSec),
                                );
                              },
                            ),
                          ],
                        ],
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
            Icons.cut_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              locale.cvTitle,
              style:
                  Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ) ??
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: locale.cvClose,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
