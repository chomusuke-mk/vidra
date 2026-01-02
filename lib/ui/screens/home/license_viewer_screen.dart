import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';

class LicenseViewerScreen extends StatefulWidget {
  const LicenseViewerScreen({super.key});

  @override
  State<LicenseViewerScreen> createState() => _LicenseViewerScreenState();
}

class _LicenseViewerScreenState extends State<LicenseViewerScreen> {
  static const String _defaultAsset = 'THIRD_PARTY_LICENSES.txt';
  static const String _licenseDirPrefix = 'third_party_licenses/';
  static const List<String> _topLevelAssets = <String>[
    'THIRD_PARTY_LICENSES.txt',
    'LICENSE',
  ];

  final ScrollController _contentController = ScrollController();
  List<String> _assets = const <String>[];
  String? _selectedAsset;
  String? _content;
  String? _manifestError;
  String? _loadError;
  bool _loadingManifest = true;
  bool _loadingContent = false;

  @override
  void initState() {
    super.initState();
    _loadManifest();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadManifest() async {
    setState(() {
      _loadingManifest = true;
      _manifestError = null;
      _assets = const <String>[];
    });
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final entries = manifest.listAssets();
      final assets = entries.where(_isLicenseAsset).toList(growable: true)
        ..sort();
      _prioritizeDefault(assets);
      final initial = _resolveInitialSelection(assets);
      setState(() {
        _assets = assets;
        _selectedAsset = initial;
        _loadingManifest = false;
      });
      if (initial != null) {
        await _loadContent(initial);
      }
    } catch (error) {
      setState(() {
        _manifestError = error.toString();
        _loadingManifest = false;
      });
    }
  }

  bool _isLicenseAsset(String asset) {
    if (asset.startsWith(_licenseDirPrefix)) {
      return true;
    }
    return _topLevelAssets.contains(asset);
  }

  void _prioritizeDefault(List<String> assets) {
    if (assets.isEmpty) {
      return;
    }
    final hasDefault = assets.remove(_defaultAsset);
    if (hasDefault) {
      assets.insert(0, _defaultAsset);
    }
  }

  String? _resolveInitialSelection(List<String> assets) {
    if (assets.isEmpty) {
      return null;
    }
    if (assets.contains(_defaultAsset)) {
      return _defaultAsset;
    }
    return assets.first;
  }

  Future<void> _loadContent(String asset) async {
    setState(() {
      _selectedAsset = asset;
      _content = null;
      _loadError = null;
      _loadingContent = true;
    });
    try {
      final text = await rootBundle.loadString(asset);
      if (!mounted) {
        return;
      }
      setState(() {
        _content = text;
        _loadingContent = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.toString();
        _loadingContent = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    localizations.ui(AppStringKey.backendLicensesTitle),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: localizations.ui(
                      AppStringKey.preferenceDropdownDialogCloseTooltip,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(theme, localizations)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, VidraLocalizations localizations) {
    if (_loadingManifest) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_manifestError != null) {
      return _CenteredMessage(
        message: localizations.ui(AppStringKey.backendLicensesLoadError),
        details: _manifestError,
      );
    }
    if (_assets.isEmpty) {
      return _CenteredMessage(
        message: localizations.ui(AppStringKey.backendLicensesEmpty),
      );
    }

    return Row(
      children: [
        _buildSidebar(theme, localizations),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: _buildContentArea(theme, localizations)),
      ],
    );
  }

  Widget _buildSidebar(ThemeData theme, VidraLocalizations localizations) {
    return Container(
      width: 260,
      color: theme.colorScheme.surface,
      child: ListView.separated(
        itemCount: _assets.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final asset = _assets[index];
          final selected = asset == _selectedAsset;
          return ListTile(
            dense: true,
            selected: selected,
            selectedColor: theme.colorScheme.onSurface,
            selectedTileColor: theme.colorScheme.surfaceContainerHighest,
            title: Text(_labelForAsset(asset)),
            onTap: () => _loadContent(asset),
          );
        },
      ),
    );
  }

  Widget _buildContentArea(ThemeData theme, VidraLocalizations localizations) {
    if (_loadingContent) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _CenteredMessage(
        message: localizations.ui(AppStringKey.backendLicensesLoadError),
        details: _loadError,
      );
    }
    if (_content == null || _content!.isEmpty) {
      return _CenteredMessage(
        message: localizations.ui(AppStringKey.backendLicensesEmpty),
      );
    }

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Scrollbar(
        controller: _contentController,
        child: SingleChildScrollView(
          controller: _contentController,
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            _content!,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  String _labelForAsset(String asset) {
    final segments = asset.split('/');
    final fileName = segments.isNotEmpty ? segments.last : asset;
    return fileName;
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message, this.details});

  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
