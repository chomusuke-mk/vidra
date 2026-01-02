import 'dart:async';
import 'dart:io' show File, Platform, HttpException;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/state/app_release_updater.dart';
import 'package:vidra/state/release_update_cache.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';
import 'package:vidra/state/backend_update_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vidra/ui/screens/home/license_viewer_screen.dart';

const String _kLogsSheetTitle = 'Registros del backend';
const String _kLogsMissingMessage = 'Archivo de logs no encontrado.';
const String _kLogsTooltipText = 'Ver logs';

class BackendStatusScreen extends StatefulWidget {
  const BackendStatusScreen({super.key});

  @override
  State<BackendStatusScreen> createState() => _BackendStatusScreenState();
}

class _BackendLogSheetBody extends StatefulWidget {
  const _BackendLogSheetBody({required this.content});

  final String content;

  @override
  State<_BackendLogSheetBody> createState() => _BackendLogSheetBodyState();
}

class _BackendLogSheetBodyState extends State<_BackendLogSheetBody> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        child: SelectableText(
          widget.content,
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

class _BackendStatusScreenState extends State<BackendStatusScreen> {
  bool _isDownloadingUpdate = false;
  bool _isInstallReady = false;
  bool _isRefreshing = false;
  String? _updateErrorMessage;

  final GitHubReleaseUpdater _releaseUpdater = GitHubReleaseUpdater(
    owner: 'chomusuke-mk',
    repo: 'vidra',
  );

  String? _currentAppVersion;
  ReleaseUpdateInfo? _latestRelease;
  String? _downloadedInstallerPath;
  double? _downloadProgress;

  void _syncGlobalUpdateIndicator() {
    final indicator = BackendUpdateIndicator.instance;
    if (_isInstallReady) {
      indicator.setState(BackendUpdateStatus.installReady);
    } else if (_isDownloadingUpdate) {
      indicator.setState(BackendUpdateStatus.downloadingUpdate);
    } else if (_latestRelease?.isUpdateAvailable ?? false) {
      indicator.setState(BackendUpdateStatus.updateAvailable);
    } else {
      indicator.setState(BackendUpdateStatus.idle);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapUpdater());
  }

  Future<void> _bootstrapUpdater() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _currentAppVersion = info.version;
      });
      await _refreshUpdateInfo();
    } catch (error) {
      debugPrint('Failed to bootstrap updater: $error');
    }
  }

  void _handleUpdateAction({required bool outdated}) {
    final actionState = _resolveActionState(isLatest: !outdated);
    switch (actionState) {
      case _UpdateActionState.refresh:
        unawaited(_refreshUpdateInfo());
        return;
      case _UpdateActionState.downloadUpdate:
        unawaited(_downloadUpdate());
        break;
      case _UpdateActionState.downloadingUpdate:
        return;
      case _UpdateActionState.install:
        unawaited(_runInstaller());
        break;
    }
    setState(() {});
  }

  _UpdateActionState _resolveActionState({required bool isLatest}) {
    if (_isDownloadingUpdate) {
      return _UpdateActionState.downloadingUpdate;
    }
    if (_isInstallReady) {
      return _UpdateActionState.install;
    }
    return isLatest
        ? _UpdateActionState.refresh
        : _UpdateActionState.downloadUpdate;
  }

  _UpdateStatus _resolveUpdateStatus(bool isLatest) {
    if (_updateErrorMessage != null) {
      return _UpdateStatus.error;
    }
    return isLatest ? _UpdateStatus.ok : _UpdateStatus.warn;
  }

  String _primaryMessage(VidraLocalizations localizations, bool isLatest) {
    if (_isDownloadingUpdate) {
      return localizations.ui(AppStringKey.backendStatusPrimaryDownloading);
    }
    if (_isInstallReady) {
      return localizations.ui(AppStringKey.backendStatusPrimaryInstall);
    }
    if (_isRefreshing) {
      return localizations.ui(AppStringKey.backendStatusPrimarySearching);
    }
    if (!isLatest) {
      return localizations.ui(AppStringKey.backendStatusPrimaryDownload);
    }
    return localizations.ui(AppStringKey.backendStatusPrimaryUpToDate);
  }

  Future<void> _refreshUpdateInfo() async {
    final current = _currentAppVersion;
    if (current == null || current.trim().isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _isRefreshing = true;
      _updateErrorMessage = null;
    });
    _syncGlobalUpdateIndicator();

    final prefs = await SharedPreferences.getInstance();
    final now = _releaseUpdater.now();
    final last = ReleaseUpdateCache.readLastCheck(prefs);

    // Throttle applies to both automatic and manual checks.
    if (last != null &&
        now.difference(last) < GitHubReleaseUpdater.throttleWindow) {
      final cached = ReleaseUpdateCache.read(prefs, currentVersion: current);
      if (mounted) {
        setState(() {
          _latestRelease = cached;
          _isRefreshing = false;
        });
      }
      _syncGlobalUpdateIndicator();
      return;
    }

    try {
      await ReleaseUpdateCache.writeLastCheck(prefs, now);

      final info = await _releaseUpdater.fetchLatest(
        currentVersion: current,
        platform: defaultTargetPlatform,
      );

      await ReleaseUpdateCache.write(prefs, info);

      if (!mounted) {
        return;
      }
      setState(() {
        _latestRelease = info;
        _isRefreshing = false;
      });
    } catch (error) {
      debugPrint('Update check failed: $error');
      final cached = ReleaseUpdateCache.read(prefs, currentVersion: current);
      if (!mounted) {
        return;
      }
      setState(() {
        _latestRelease = cached;
        _isRefreshing = false;
        _updateErrorMessage = error.toString();
      });
    } finally {
      _syncGlobalUpdateIndicator();
      if (mounted && _isRefreshing) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _downloadUpdate() async {
    final localizations = VidraLocalizations.of(context);
    final info = _latestRelease;
    if (info == null || !info.isUpdateAvailable) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _updateErrorMessage = null;
      _isDownloadingUpdate = true;
      _isInstallReady = false;
      _isRefreshing = false;
      _downloadProgress = 0;
    });
    _syncGlobalUpdateIndicator();
    _showSnack(localizations.ui(AppStringKey.backendStatusSnackPreparing));

    final preferencesModel = context.read<PreferencesModel>();
    final downloadsDir = await preferencesModel.preferences
        .ensurePathsHomeEntry();
    if (downloadsDir == null || downloadsDir.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isDownloadingUpdate = false;
        _downloadProgress = null;
        _updateErrorMessage = 'No se pudo resolver la carpeta de descargas.';
      });
      _syncGlobalUpdateIndicator();
      return;
    }

    final finalPath = p.join(downloadsDir, info.assetName);
    final tempPath = '$finalPath.partial';
    final outFile = File(tempPath);
    await outFile.parent.create(recursive: true);

    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', info.assetUrl);
        request.headers['User-Agent'] = 'vidra-app';
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw HttpException(
            'Download failed (${response.statusCode})',
            uri: info.assetUrl,
          );
        }

        final total = response.contentLength;
        final sink = outFile.openWrite();
        final digestSink = AccumulatorSink<crypto.Digest>();
        final hasher = crypto.sha256.startChunkedConversion(digestSink);
        int received = 0;
        try {
          await for (final chunk in response.stream) {
            received += chunk.length;
            hasher.add(chunk);
            sink.add(chunk);

            if (total != null && total > 0 && mounted) {
              setState(() {
                _downloadProgress = received / total;
              });
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
          hasher.close();
        }

        final computed = digestSink.events.single.toString();
        if (computed.toLowerCase() != info.sha256.toLowerCase()) {
          throw StateError('Checksum SHA256 inválido para ${info.assetName}');
        }

        // Move into final name only after checksum verification.
        final finalFile = File(finalPath);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await outFile.rename(finalPath);

        // Authenticode validation intentionally disabled.
      } finally {
        client.close();
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isDownloadingUpdate = false;
        _isInstallReady = true;
        _downloadedInstallerPath = finalPath;
        _downloadProgress = null;
      });
      _syncGlobalUpdateIndicator();
      _showSnack(localizations.ui(AppStringKey.backendStatusSnackReady));
    } catch (error) {
      debugPrint('Update download failed: $error');
      try {
        if (await outFile.exists()) {
          await outFile.delete();
        }
      } catch (_) {}
      if (!mounted) {
        return;
      }
      setState(() {
        _isDownloadingUpdate = false;
        _isInstallReady = false;
        _downloadProgress = null;
        _updateErrorMessage = error.toString();
      });
      _syncGlobalUpdateIndicator();
    }
  }

  Future<void> _runInstaller() async {
    final localizations = VidraLocalizations.of(context);
    final path = _downloadedInstallerPath;
    if (path == null || path.trim().isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isInstallReady = false;
      _updateErrorMessage = null;
      _isRefreshing = false;
    });
    _syncGlobalUpdateIndicator();
    _showSnack(localizations.ui(AppStringKey.backendStatusSnackInstalling));
    await OpenFile.open(path);
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openExternalLink(String url) async {
    final localizations = VidraLocalizations.of(context);
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      _showSnack(localizations.ui(AppStringKey.backendStatusOpenLinkInvalid));
      return;
    }
    final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!success && mounted) {
      final template = localizations.ui(
        AppStringKey.backendStatusOpenLinkFailed,
      );
      _showSnack(template.replaceAll('{url}', url));
    }
  }

  Future<void> _openLicenseViewer() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LicenseViewerScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _showBackendLogsSheet(String? logPath) async {
    final logContent = await _loadLogFile(logPath);
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final mediaQuery = MediaQuery.of(sheetContext);
        final hasContent = logContent != null && logContent.trim().isNotEmpty;
        final displayContent = logContent ?? '';
        final body = hasContent
            ? _BackendLogSheetBody(content: displayContent)
            : const Center(child: Text(_kLogsMissingMessage));
        return Padding(
          padding: mediaQuery.viewInsets + const EdgeInsets.all(24),
          child: SizedBox(
            height: mediaQuery.size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kLogsSheetTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(child: body),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _loadLogFile(String? logPath) async {
    final resolvedPath = logPath?.trim();
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return null;
    }
    try {
      final file = File(resolvedPath);
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsString();
    } catch (error) {
      debugPrint('No se pudo leer el log del backend: $error');
      return null;
    }
  }

  String _platformLabel(
    Map<String, dynamic> metadata,
    VidraLocalizations localizations,
  ) {
    String? metadataValue(String key) {
      final value = metadata[key];
      if (value is! String) {
        return null;
      }
      final text = value.trim();
      return text.isEmpty ? null : text;
    }

    final metadataLabel =
        metadataValue('platform_name') ?? metadataValue('platform');
    if (metadataLabel != null) {
      return metadataLabel;
    }

    final raw = Platform.operatingSystem.trim();
    if (raw.isEmpty) {
      return localizations.ui(AppStringKey.backendStatusUnknownPlatform);
    }
    return raw[0].toUpperCase() + raw.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = VidraLocalizations.of(context);
    final controller = context.watch<DownloadController>();
    final backendConfig = context.watch<BackendConfig>();
    final pythonLauncher = SeriousPythonServerLauncher.instance;
    final backendState = controller.backendState;
    final metadata = Map<String, dynamic>.from(backendConfig.metadata);
    final theme = Theme.of(context);
    final host = backendConfig.baseUri.host;
    final port = backendConfig.baseUri.hasPort
        ? backendConfig.baseUri.port
        : backendConfig.baseUri.scheme == 'https'
        ? 443
        : 80;
    final unknownVersionText = localizations.ui(
      AppStringKey.backendStatusUnknownVersion,
    );
    final version =
        _currentAppVersion ??
        metadata['version']?.toString() ??
        unknownVersionText;
    metadata.putIfAbsent(
      'version',
      () => backendConfig.metadata['version'] ?? unknownVersionText,
    );
    final String? latestVersion =
        _latestRelease?.latestVersion ?? metadata['latest_version']?.toString();
    final isLatest = _latestRelease == null
        ? (latestVersion == null || latestVersion == version)
        : !_latestRelease!.isUpdateAvailable;
    final platformLabel = _platformLabel(metadata, localizations);
    final updateStatus = _resolveUpdateStatus(isLatest);
    final actionState = _resolveActionState(isLatest: isLatest);
    final primaryMessage = _primaryMessage(localizations, isLatest);
    final actionEnabled =
        !_isRefreshing && actionState != _UpdateActionState.downloadingUpdate;

    _syncGlobalUpdateIndicator();

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.ui(AppStringKey.backendStatusTitle)),
        centerTitle: false,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 150),
              children: [
                ValueListenableBuilder<BackendLaunchInfo?>(
                  valueListenable: pythonLauncher.launchInfo,
                  builder: (_, launchInfo, _) {
                    return _StatusHeaderCard(
                      state: backendState,
                      onViewLogs: () =>
                          _showBackendLogsSheet(launchInfo?.logPath),
                    );
                  },
                ),
                const SizedBox(height: 7),
                _UpdateCard(
                  versionText: version,
                  platformName: platformLabel,
                  status: updateStatus,
                  actionState: actionState,
                  errorMessage: _updateErrorMessage,
                  primaryMessage: primaryMessage,
                  downloadProgress: _downloadProgress,
                  actionEnabled: actionEnabled,
                  onAction: () => _handleUpdateAction(outdated: !isLatest),
                ),
                const SizedBox(height: 7),
                _AppInfoCard(
                  backendConfig: backendConfig,
                  metadata: metadata,
                  host: host,
                  port: port,
                  onLinkTap: _openExternalLink,
                  onViewLicenses: _openLicenseViewer,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusHeaderCard extends StatelessWidget {
  const _StatusHeaderCard({required this.state, required this.onViewLogs});

  final BackendState state;
  final VoidCallback onViewLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final stateColor = _backendStateColor(theme, state);
    final statusText = localizations.ui(AppStringKey.backendStatusHeaderLabel);
    final cardColor = theme.colorScheme.surface.withValues(alpha: 0.78);
    final badgeText = _stateBadgeText(localizations, state);
    final statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: stateColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: stateColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        badgeText,
        style: theme.textTheme.labelLarge?.copyWith(
          color: stateColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final logsButton = Tooltip(
      message: _kLogsTooltipText,
      child: IconButton.outlined(
        onPressed: onViewLogs,
        icon: const Icon(Icons.receipt_long_rounded),
      ),
    );

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.hub_outlined, color: stateColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusText,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: stateColor,
                    ),
                    softWrap: true,
                  ),
                ),
                const SizedBox(width: 12),
                statusBadge,
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                logsButton,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    localizations.ui(AppStringKey.backendStatusDescription),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.versionText,
    required this.platformName,
    required this.status,
    required this.actionState,
    required this.errorMessage,
    required this.primaryMessage,
    required this.downloadProgress,
    required this.actionEnabled,
    required this.onAction,
  });

  final String versionText;
  final String platformName;
  final _UpdateStatus status;
  final _UpdateActionState actionState;
  final String? errorMessage;
  final String primaryMessage;
  final double? downloadProgress;
  final bool actionEnabled;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final cardColor = theme.colorScheme.surface.withValues(alpha: 0.78);
    final actionButton = _UpdateActionButton(
      state: actionState,
      enabled: actionEnabled,
      progress: downloadProgress,
      onPressed: actionEnabled ? onAction : null,
    );
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    localizations.ui(AppStringKey.backendStatusUpdateCardTitle),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                actionButton,
              ],
            ),
            const SizedBox(height: 7),
            _UpdateStatusRow(
              status: status,
              versionText: versionText,
              platformName: platformName,
              errorMessage: errorMessage,
              primaryMessage: primaryMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppInfoCard extends StatelessWidget {
  const _AppInfoCard({
    required this.backendConfig,
    required this.metadata,
    required this.host,
    required this.port,
    required this.onLinkTap,
    this.onViewLicenses,
  });

  final BackendConfig backendConfig;
  final Map<String, dynamic> metadata;
  final String host;
  final int port;
  final void Function(String url)? onLinkTap;
  final VoidCallback? onViewLicenses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.surface.withValues(alpha: 0.78);
    final localizations = VidraLocalizations.of(context);
    final developer = metadata['developer']?.toString().trim();
    final developerIcon = metadata['developer_icon']?.toString().trim();
    final developerUrl = metadata['developer_url']?.toString().trim();
    final repositoryUrl = metadata['repository']?.toString().trim();
    const patreonUrl = 'https://www.patreon.com/chomusuke_dev';
    const buyMeACoffeeUrl = 'https://www.buymeacoffee.com/chomusuke';
    final entries = _buildEntries(localizations);
    final actions = <Widget>[];

    if (repositoryUrl != null && repositoryUrl.isNotEmpty) {
      actions.add(
        FilledButton.icon(
          onPressed: onLinkTap == null ? null : () => onLinkTap!(repositoryUrl),
          icon: const _GitHubMark(),
          label: Text(
            localizations.ui(AppStringKey.backendStatusViewCodeAction),
          ),
        ),
      );
    }

    if (onViewLicenses != null) {
      actions.add(
        OutlinedButton.icon(
          onPressed: onViewLicenses,
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(
            localizations.ui(AppStringKey.backendStatusViewLicensesAction),
          ),
        ),
      );
    }

    if (onLinkTap != null) {
      actions.addAll([
        OutlinedButton.icon(
          onPressed: () => onLinkTap!(patreonUrl),
          icon: const Icon(Icons.volunteer_activism_outlined),
          label: Text(
            localizations.ui(AppStringKey.backendStatusDonatePatreonAction),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => onLinkTap!(buyMeACoffeeUrl),
          icon: const Icon(Icons.local_cafe_outlined),
          label: Text(
            localizations.ui(
              AppStringKey.backendStatusDonateBuyMeACoffeeAction,
            ),
          ),
        ),
      ]);
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.ui(AppStringKey.backendStatusAppInfoTitle),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            if (developer != null && developer.isNotEmpty)
              _DeveloperTile(
                name: developer,
                avatarUrl: developerIcon,
                profileUrl: developerUrl,
                onLinkTap: onLinkTap,
              ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: entries
                    .map((entry) => _InfoTile(entry: entry))
                    .toList(growable: false),
              ),
            ],
            if ((repositoryUrl != null && repositoryUrl.isNotEmpty) ||
                onLinkTap != null ||
                onViewLicenses != null) ...[
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<_AppInfoEntry> _buildEntries(VidraLocalizations localizations) {
    String? metadataValue(String key) {
      final value = metadata[key];
      if (value == null) {
        return null;
      }
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    final entries = <_AppInfoEntry>[];

    entries.add(
      _AppInfoEntry(
        label: localizations.ui(AppStringKey.backendStatusServiceNameLabel),
        value: backendConfig.name,
        icon: Icons.badge_outlined,
      ),
    );

    if (backendConfig.description.trim().isNotEmpty) {
      entries.add(
        _AppInfoEntry(
          label: localizations.ui(AppStringKey.backendStatusDescriptionLabel),
          value: backendConfig.description,
          icon: Icons.description_outlined,
        ),
      );
    }

    final environment = metadataValue('environment');
    if (environment != null) {
      entries.add(
        _AppInfoEntry(
          label: localizations.ui(AppStringKey.backendStatusEnvironmentLabel),
          value: environment,
          icon: Icons.layers_outlined,
        ),
      );
    }

    final version = metadataValue('version');
    if (version != null) {
      entries.add(
        _AppInfoEntry(
          label: localizations.ui(AppStringKey.backendStatusVersionLabel),
          value: version,
          icon: Icons.verified_outlined,
        ),
      );
    }

    entries.add(
      _AppInfoEntry(
        label: localizations.ui(AppStringKey.backendStatusHostPortLabel),
        value: '$host:$port',
        icon: Icons.storage_rounded,
      ),
    );

    entries.add(
      _AppInfoEntry(
        label: localizations.ui(AppStringKey.backendStatusBackendBaseLabel),
        value: backendConfig.baseUri.toString(),
        icon: Icons.link_outlined,
      ),
    );

    entries.add(
      _AppInfoEntry(
        label: localizations.ui(AppStringKey.backendStatusApiBaseLabel),
        value: backendConfig.apiBaseUri.toString(),
        icon: Icons.api_outlined,
      ),
    );

    entries.add(
      _AppInfoEntry(
        label: localizations.ui(AppStringKey.backendStatusOverviewSocketLabel),
        value: backendConfig.overviewSocketUri.toString(),
        icon: Icons.podcasts_outlined,
      ),
    );

    entries.add(
      _AppInfoEntry(
        label: localizations.ui(AppStringKey.backendStatusJobSocketLabel),
        value: backendConfig.jobSocketBaseUri.toString(),
        icon: Icons.swap_calls_outlined,
      ),
    );

    entries.add(
      _AppInfoEntry(
        label: localizations.ui(AppStringKey.backendStatusTimeoutLabel),
        value: '${backendConfig.timeout.inSeconds} s',
        icon: Icons.timer_outlined,
      ),
    );

    return entries;
  }
}

class _DeveloperTile extends StatelessWidget {
  const _DeveloperTile({
    required this.name,
    this.avatarUrl,
    this.profileUrl,
    required this.onLinkTap,
  });

  final String name;
  final String? avatarUrl;
  final String? profileUrl;
  final void Function(String url)? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final avatar = CircleAvatar(
      radius: 28,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
          ? NetworkImage(avatarUrl!)
          : null,
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Text(
              _initials(name),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );

    final hasLink = profileUrl != null && profileUrl!.isNotEmpty;
    final linkColor = theme.colorScheme.primary;
    final content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations
                      .ui(AppStringKey.backendStatusDeveloperLabel)
                      .replaceAll('{name}', name),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hasLink)
                  Text(
                    profileUrl!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: linkColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (hasLink) Icon(Icons.open_in_new, size: 18, color: linkColor),
        ],
      ),
    );

    if (!hasLink || onLinkTap == null) {
      return content;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onLinkTap!(profileUrl!),
      child: content,
    );
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final buffer = StringBuffer();
    for (final part in parts) {
      if (buffer.length >= 2) {
        break;
      }
      buffer.write(part[0].toUpperCase());
    }
    if (buffer.isEmpty) {
      return '?';
    }
    return buffer.toString();
  }
}

class _AppInfoEntry {
  const _AppInfoEntry({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.entry});

  final _AppInfoEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(entry.icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            entry.value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _GitHubMark extends StatelessWidget {
  const _GitHubMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          'https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png',
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.code, size: 18),
        ),
      ),
    );
  }
}

class _UpdateStatusRow extends StatelessWidget {
  const _UpdateStatusRow({
    required this.status,
    required this.versionText,
    required this.platformName,
    required this.errorMessage,
    required this.primaryMessage,
  });

  final _UpdateStatus status;
  final String versionText;
  final String platformName;
  final String? errorMessage;
  final String primaryMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final color = _statusColor(theme, status);
    final icon = _statusIcon(status);
    final versionPlatform = localizations
        .ui(AppStringKey.backendStatusVersionPlatform)
        .replaceAll('{version}', versionText)
        .replaceAll('{platform}', platformName);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusIndicator(icon: icon, color: color),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                primaryMessage,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                versionPlatform,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (errorMessage != null && errorMessage!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }
}

class _UpdateActionButton extends StatelessWidget {
  const _UpdateActionButton({
    required this.state,
    required this.enabled,
    required this.progress,
    required this.onPressed,
  });

  final _UpdateActionState state;
  final bool enabled;
  final double? progress;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    if (state == _UpdateActionState.downloadingUpdate) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: CircularProgressIndicator.adaptive(
            strokeWidth: 2.5,
            value: progress,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }
    return IconButton.filledTonal(
      onPressed: enabled ? onPressed : null,
      icon: Icon(_actionIcon(state)),
      tooltip: _actionTooltip(state, localizations),
    );
  }
}

enum _UpdateStatus { ok, warn, error }

enum _UpdateActionState { refresh, downloadUpdate, downloadingUpdate, install }

IconData _statusIcon(_UpdateStatus status) {
  switch (status) {
    case _UpdateStatus.ok:
      return Icons.verified_rounded;
    case _UpdateStatus.warn:
      return Icons.warning_amber_rounded;
    case _UpdateStatus.error:
      return Icons.error_outline;
  }
}

Color _statusColor(ThemeData theme, _UpdateStatus status) {
  switch (status) {
    case _UpdateStatus.ok:
      return Colors.green.shade400;
    case _UpdateStatus.warn:
      return Colors.amber.shade600;
    case _UpdateStatus.error:
      return theme.colorScheme.error;
  }
}

IconData _actionIcon(_UpdateActionState state) {
  switch (state) {
    case _UpdateActionState.refresh:
      return Icons.refresh_rounded;
    case _UpdateActionState.downloadUpdate:
      return Icons.download_rounded;
    case _UpdateActionState.downloadingUpdate:
      return Icons.downloading_rounded;
    case _UpdateActionState.install:
      return Icons.install_mobile_rounded;
  }
}

String _actionTooltip(
  _UpdateActionState state,
  VidraLocalizations localizations,
) {
  switch (state) {
    case _UpdateActionState.refresh:
      return localizations.ui(AppStringKey.backendStatusTooltipRefresh);
    case _UpdateActionState.downloadUpdate:
      return localizations.ui(AppStringKey.backendStatusTooltipDownload);
    case _UpdateActionState.downloadingUpdate:
      return localizations.ui(AppStringKey.backendStatusTooltipDownloading);
    case _UpdateActionState.install:
      return localizations.ui(AppStringKey.backendStatusTooltipInstall);
  }
}

Color _backendStateColor(ThemeData theme, BackendState state) {
  switch (state) {
    case BackendState.running:
      return Colors.green.shade400;
    case BackendState.stopped:
      return theme.colorScheme.error;
    case BackendState.starting:
      return theme.colorScheme.tertiary;
    case BackendState.unpacking:
      return theme.colorScheme.secondary;
    case BackendState.unknown:
      return theme.colorScheme.outline;
  }
}

String _stateBadgeText(VidraLocalizations localizations, BackendState state) {
  switch (state) {
    case BackendState.running:
      return localizations.ui(AppStringKey.backendStatusBadgeActive);
    case BackendState.unpacking:
    case BackendState.starting:
      return localizations.ui(AppStringKey.backendStatusBadgeBusy);
    case BackendState.stopped:
      return localizations.ui(AppStringKey.backendStatusBadgeStopped);
    case BackendState.unknown:
      return localizations.ui(AppStringKey.backendStatusBadgeUnknown);
  }
}
