import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/preferences/sections.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/ui/models/preference_ui_models.dart';
import 'package:vidra/ui/widgets/settings/preference_controls.dart';
import 'package:vidra/ui/widgets/settings/preference_tile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  static const double _compactWidthBreakpoint = 720;
  static const PreferenceControlBuilder _controlBuilder =
      PreferenceControlBuilder();
  late final List<PreferenceSection> _sections;
  int _selectedIndex = 0;
  late final TabController _tabController;
  final Map<int, _SectionCache> _sectionCache = <int, _SectionCache>{};
  String? _cachedLanguage;

  @override
  void initState() {
    super.initState();
    final preferencesModel = context.read<PreferencesModel>();
    final preferences = preferencesModel.preferences;
    _sections = buildPreferenceSections(preferences);
    _cachedLanguage = preferencesModel.effectiveLanguage;
    _tabController = TabController(
      length: _sections.length,
      vsync: this,
      initialIndex: _selectedIndex,
    );
    _tabController.addListener(_handleTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final language = context.read<PreferencesModel>().effectiveLanguage;
      for (var index = 0; index < _sections.length; index++) {
        if (index == _selectedIndex) {
          continue;
        }
        _resolveSectionTiles(context, index, language);
      }
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferencesModel = context.watch<PreferencesModel>();
    final languageValue = preferencesModel.effectiveLanguage;
    final localizations = VidraLocalizations.of(context);

    if (_cachedLanguage != languageValue) {
      _sectionCache.clear();
      _cachedLanguage = languageValue;
    }

    final navItems = _buildNavigationItems(localizations);
    final railDestinations = navItems
        .map(
          (item) => NavigationRailDestination(
            icon: Icon(item.icon),
            label: Text(item.label),
          ),
        )
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.ui(AppStringKey.settingsTitle),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < _compactWidthBreakpoint;
          final sectionTiles = _resolveSectionTiles(
            context,
            _selectedIndex,
            languageValue,
          );
          final content = Expanded(
            child: ListView.builder(
              key: ValueKey('settings_list_$_selectedIndex'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
              itemCount: sectionTiles.length,
              itemBuilder: (context, index) {
                return sectionTiles[index];
              },
            ),
          );

          if (isCompact) {
            return Column(
              children: [
                TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: navItems
                      .map(
                        (item) => Tab(
                          icon: Tooltip(
                            message: item.label,
                            waitDuration: const Duration(milliseconds: 250),
                            child: Icon(item.icon),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                const Divider(height: 1, thickness: 1),
                content,
              ],
            );
          }

          return Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (int index) {
                  _handleDestinationSelected(index);
                },
                labelType: NavigationRailLabelType.all,
                destinations: railDestinations,
              ),
              const VerticalDivider(thickness: 1, width: 1),
              content,
            ],
          );
        },
      ),
    );
  }

  List<_SettingsNavItem> _buildNavigationItems(
    VidraLocalizations localizations,
  ) {
    return [
      _SettingsNavItem(
        icon: Icons.settings,
        label: localizations.ui(AppStringKey.general),
      ),
      _SettingsNavItem(
        icon: Icons.network_wifi,
        label: localizations.ui(AppStringKey.network),
      ),
      _SettingsNavItem(
        icon: Icons.video_library,
        label: localizations.ui(AppStringKey.video),
      ),
      _SettingsNavItem(
        icon: Icons.download,
        label: localizations.ui(AppStringKey.downloadSection),
      ),
    ];
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    final index = _tabController.index;
    if (index != _selectedIndex) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  void _handleDestinationSelected(int index) {
    if (index == _selectedIndex) {
      return;
    }
    setState(() {
      _selectedIndex = index;
      _tabController.index = index;
    });
  }

  List<Widget> _resolveSectionTiles(
    BuildContext context,
    int index,
    String language,
  ) {
    final cached = _sectionCache[index];
    if (cached != null && cached.language == language) {
      return cached.tiles;
    }

    final section = _sections[index];
    final tiles = section.preferences
        .map((preference) {
          final control = _controlBuilder.build(
            context: context,
            preference: preference,
            languageOverride: language,
          );
          return PreferenceTile(
            key: ValueKey('settings_pref_${preference.key}'),
            preference: preference,
            languageValue: language,
            control: control,
          );
        })
        .toList(growable: false);

    final cachedEntry = _SectionCache(language: language, tiles: tiles);
    _sectionCache[index] = cachedEntry;
    return cachedEntry.tiles;
  }
}

class _SettingsNavItem {
  const _SettingsNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _SectionCache {
  const _SectionCache({required this.language, required this.tiles});

  final String language;
  final List<Widget> tiles;
}
