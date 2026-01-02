import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:provider/provider.dart';
import 'package:vidra/constants/languages.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/state/initial_permissions_controller.dart';
import 'package:vidra/ui/screens/home/backend_status_screen.dart';
import 'package:vidra/ui/widgets/backend_status_indicator.dart';

class InitialPermissionsSheet extends StatelessWidget {
  const InitialPermissionsSheet({super.key, this.onCloseRequested});

  final VoidCallback? onCloseRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferencesModel = context.watch<PreferencesModel>();
    final localizations = VidraLocalizations.of(context);
    final isDark = preferencesModel.isDarkModeEnabled;

    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.99),
        child: Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            title: Text(localizations.ui(AppStringKey.initialPermissionsTitle)),
            actions: [
              const _CompactLanguageButton(),
              BackendStatusIndicator(onTap: () => _openBackendStatus(context)),
              IconButton(
                tooltip: localizations.ui(AppStringKey.homeThemeToggleTooltip),
                icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
                onPressed: () async {
                  await preferencesModel.setPreferenceValue(
                    preferencesModel.preferences.isDarkTheme,
                    !isDark,
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: _InitialPermissionsContent(
              onCloseRequested: onCloseRequested,
            ),
          ),
        ),
      ),
    );
  }
}

class _InitialPermissionsContent extends StatelessWidget {
  const _InitialPermissionsContent({this.onCloseRequested});

  final VoidCallback? onCloseRequested;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InitialPermissionsController>();
    final localizations = VidraLocalizations.of(context);
    final theme = Theme.of(context);
    final permissions = controller.permissions
        .where(
          (state) => state.availability != PermissionAvailability.notRequired,
        )
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              localizations.ui(
                                AppStringKey.initialPermissionsSubtitle,
                              ),
                              style: theme.textTheme.titleMedium,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filledTonal(
                            tooltip: localizations.ui(
                              AppStringKey.initialPermissionsRefreshButton,
                            ),
                            onPressed: controller.isLoading
                                ? null
                                : () => controller.refreshStatuses(),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (controller.isLoading) ...[
                        const LinearProgressIndicator(minHeight: 3),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final state = permissions[index];
                    final presentation = _presentations[state.type]!;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == permissions.length - 1 ? 0 : 12,
                      ),
                      child: _PermissionCard(
                        state: state,
                        presentation: presentation,
                      ),
                    );
                  },
                    childCount: permissions.length),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.center,
            child: FilledButton.icon(
              icon: const Icon(Icons.arrow_forward_rounded),
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                controller.dismissForSession();
                onCloseRequested?.call();
              },
              label: Text(
                localizations.ui(AppStringKey.initialPermissionsContinueButton),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.state, required this.presentation});

  final PermissionCardState state;
  final _PermissionPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<InitialPermissionsController>();
    final localizations = VidraLocalizations.of(context);
    final theme = Theme.of(context);
    final title = localizations.ui(presentation.titleKey);
    final description = localizations.ui(presentation.descriptionKey);
    final recommendedSuffix = state.isRecommended
        ? ' (${localizations.ui(AppStringKey.initialPermissionsRecommendedLabel)})'
        : '';
    final displayTitle = '$title$recommendedSuffix';
    final isSatisfied = state.satisfiesRequirement;
    final badgeColor = isSatisfied
        ? Colors.green.shade500
        : Colors.amber.shade700;
    final badgeIcon = isSatisfied
        ? Icons.check_circle
        : Icons.warning_amber_rounded;
    final cardColor = isSatisfied
        ? theme.colorScheme.surfaceContainerHigh
        : Colors.amber.shade100.withValues(alpha: 0.1);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cardColor,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    presentation.icon,
                    size: 20,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              displayTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(badgeIcon, color: badgeColor, size: 22),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (state.action != PermissionAction.none) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                icon: const Icon(Icons.verified_user_outlined),
                onPressed: state.isRequesting
                    ? null
                    : () => controller.performAction(state.type),
                label: state.isRequesting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        localizations.ui(
                          AppStringKey.initialPermissionsActionGrant,
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionPresentation {
  const _PermissionPresentation({
    required this.titleKey,
    required this.descriptionKey,
    required this.icon,
  });

  final String titleKey;
  final String descriptionKey;
  final IconData icon;
}

const Map<InitialPermissionType, _PermissionPresentation> _presentations = {
  InitialPermissionType.notifications: _PermissionPresentation(
    titleKey: AppStringKey.initialPermissionsNotificationsTitle,
    descriptionKey: AppStringKey.initialPermissionsNotificationsDescription,
    icon: Icons.notifications_active_outlined,
  ),
  InitialPermissionType.manageStorage: _PermissionPresentation(
    titleKey: AppStringKey.initialPermissionsManageStorageTitle,
    descriptionKey: AppStringKey.initialPermissionsManageStorageDescription,
    icon: Icons.sd_storage_rounded,
  ),
  InitialPermissionType.legacyStorage: _PermissionPresentation(
    titleKey: AppStringKey.initialPermissionsLegacyStorageTitle,
    descriptionKey: AppStringKey.initialPermissionsLegacyStorageDescription,
    icon: Icons.folder_shared_outlined,
  ),
  InitialPermissionType.overlay: _PermissionPresentation(
    titleKey: AppStringKey.initialPermissionsOverlayTitle,
    descriptionKey: AppStringKey.initialPermissionsOverlayDescription,
    icon: Icons.auto_awesome_mosaic_outlined,
  ),
};

class _CompactLanguageButton extends StatelessWidget {
  const _CompactLanguageButton();

  @override
  Widget build(BuildContext context) {
    final preferencesModel = context.watch<PreferencesModel>();
    final localeNames = LocaleNames.of(context);
    final localizations = VidraLocalizations.of(context);
    final currentValue = preferencesModel.effectiveLanguage;
    final chipText = currentValue.toUpperCase();

    return PopupMenuButton<String>(
      tooltip: localizations.ui(AppStringKey.homeLanguageButtonTooltip),
      initialValue: currentValue,
      onSelected: (value) async {
        if (value == currentValue) {
          return;
        }
        await preferencesModel.setPreferenceValue(
          preferencesModel.preferences.language,
          value,
        );
      },
      itemBuilder: (context) {
        return languageOptions
            .map(
              (code) => PopupMenuItem<String>(
                value: code,
                child: Text(_languageLabel(localeNames, code)),
              ),
            )
            .toList(growable: false);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Chip(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          label: Text(chipText),
        ),
      ),
    );
  }
}

String _languageLabel(LocaleNames? names, String code) {
  final mapped = languageEndonyms[code] ?? names?.nameOf(code);
  final safe = mapped != null && mapped.trim().isNotEmpty
      ? mapped.trim()
      : code.toUpperCase();
  final suffix = code.toUpperCase();
  if (safe.toLowerCase() == suffix.toLowerCase()) {
    return safe;
  }
  return '$safe ($suffix)';
}

void _openBackendStatus(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const BackendStatusScreen(),
      fullscreenDialog: true,
    ),
  );
}
