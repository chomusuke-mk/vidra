import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/state/backend_update_indicator.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';

/// Public helper that mirrors the banner message shown on the home screen
/// and can be re-used anywhere we need a textual status.
String backendStatusText(VidraLocalizations localizations, BackendState state) {
  switch (state) {
    case BackendState.unpacking:
      return localizations.ui(AppStringKey.homeBackendStatusUnpacking);
    case BackendState.starting:
      return localizations.ui(AppStringKey.homeBackendStatusStarting);
    case BackendState.unknown:
      return localizations.ui(AppStringKey.homeBackendStatusUnknown);
    case BackendState.stopped:
      return localizations.ui(AppStringKey.homeBackendStatusStopped);
    case BackendState.running:
      return '';
  }
}

/// Determines whether a loader should be presented for the current state.
bool backendStateShowsProgress(BackendState state) {
  return state == BackendState.starting ||
      state == BackendState.unpacking ||
      state == BackendState.unknown;
}

class BackendStatusIndicator extends StatelessWidget {
  const BackendStatusIndicator({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final backendConfig = context.watch<BackendConfig>();
    final metadata = backendConfig.metadata;
    return ValueListenableBuilder<BackendState>(
      valueListenable: SeriousPythonServerLauncher.instance.state,
      builder: (context, backendState, _) {
        return ValueListenableBuilder<BackendUpdateStatus>(
          valueListenable: BackendUpdateIndicator.instance.state,
          builder: (context, updateStatus, _) {
            final indicatorStatus = _resolveBackendIndicatorStatus(
              backendState,
              updateStatus,
              _hasBackendUpdateAvailable(metadata),
            );
            final theme = Theme.of(context);
            final indicator = _buildIndicator(theme, indicatorStatus);
            final tooltip = _indicatorTooltip(
              VidraLocalizations.of(context),
              indicatorStatus,
              backendState,
            );
            final child = SizedBox(
              width: 40,
              height: kToolbarHeight,
              child: Center(child: indicator),
            );
            return Tooltip(
              message: tooltip.isEmpty
                  ? backendState.name.toUpperCase()
                  : tooltip,
              waitDuration: const Duration(milliseconds: 200),
              child: _wrapWithTap(theme, child),
            );
          },
        );
      },
    );
  }

  Widget _wrapWithTap(ThemeData theme, Widget child) {
    final padded = Padding(
      padding: EdgeInsets.symmetric(horizontal: theme.useMaterial3 ? 4 : 8),
      child: child,
    );
    if (onTap == null) {
      return padded;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: padded,
      ),
    );
  }
}

enum _BackendIndicatorStatus {
  loading,
  error,
  installReady,
  downloading,
  updateAvailable,
  running,
}

_BackendIndicatorStatus _resolveBackendIndicatorStatus(
  BackendState backendState,
  BackendUpdateStatus updateStatus,
  bool hasUpdateAvailable,
) {
  if (backendStateShowsProgress(backendState)) {
    return _BackendIndicatorStatus.loading;
  }
  if (backendState == BackendState.stopped) {
    return _BackendIndicatorStatus.error;
  }
  if (updateStatus == BackendUpdateStatus.installReady) {
    return _BackendIndicatorStatus.installReady;
  }
  if (updateStatus == BackendUpdateStatus.downloadingUpdate) {
    return _BackendIndicatorStatus.downloading;
  }
  if (hasUpdateAvailable) {
    return _BackendIndicatorStatus.updateAvailable;
  }
  return _BackendIndicatorStatus.running;
}

Widget _buildIndicator(ThemeData theme, _BackendIndicatorStatus status) {
  switch (status) {
    case _BackendIndicatorStatus.loading:
      return SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator.adaptive(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
        ),
      );
    case _BackendIndicatorStatus.error:
      return Icon(
        Icons.stop_circle_outlined,
        size: 22,
        color: theme.colorScheme.error,
      );
    case _BackendIndicatorStatus.installReady:
      return Icon(
        Icons.system_update_alt,
        size: 22,
        color: theme.colorScheme.tertiary,
      );
    case _BackendIndicatorStatus.downloading:
      return Icon(
        Icons.downloading_rounded,
        size: 22,
        color: theme.colorScheme.primary,
      );
    case _BackendIndicatorStatus.updateAvailable:
      return Icon(
        Icons.download_for_offline_outlined,
        size: 22,
        color: theme.colorScheme.secondary,
      );
    case _BackendIndicatorStatus.running:
      return Icon(Icons.task_alt, size: 22, color: Colors.green.shade400);
  }
}

String _indicatorTooltip(
  VidraLocalizations localizations,
  _BackendIndicatorStatus status,
  BackendState backendState,
) {
  switch (status) {
    case _BackendIndicatorStatus.loading:
    case _BackendIndicatorStatus.error:
      return backendStatusText(localizations, backendState);
    case _BackendIndicatorStatus.installReady:
      return localizations.ui(AppStringKey.homeBackendStatusInstallReady);
    case _BackendIndicatorStatus.downloading:
      return localizations.ui(AppStringKey.homeBackendStatusDownloadingUpdate);
    case _BackendIndicatorStatus.updateAvailable:
      return localizations.ui(AppStringKey.homeBackendStatusUpdateAvailable);
    case _BackendIndicatorStatus.running:
      return localizations.ui(AppStringKey.homeBackendStatusRunning);
  }
}

bool _hasBackendUpdateAvailable(Map<String, dynamic> metadata) {
  final version = metadata['version']?.toString().trim();
  final latest = metadata['latest_version']?.toString().trim();
  if (version == null || latest == null) {
    return false;
  }
  if (version.isEmpty || latest.isEmpty) {
    return false;
  }
  return version != latest;
}
