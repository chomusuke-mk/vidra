import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/presentation/selection_wrapper.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/domain/download.dart'
    as download_model;
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/settings/presentation/settings_screen.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/shared/utils/toast_utils.dart';
import 'package:vidra/shared/widgets/download_card.dart';
import 'download_detail_screen.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/system/presentation/system_status_indicator.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/utils/changelog_utils.dart';
import 'package:vidra/shared/utils/tutorial_utils.dart';
import 'package:vidra/features/downloads/presentation/widgets/quick_settings_bottom_sheet.dart';
import 'package:vidra/features/downloads/presentation/widgets/cut_video_bottom_sheet.dart';
import 'package:vidra/core/theme/colors.dart';
import 'package:vidra/core/theme/layout.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final TextEditingController _urlController = TextEditingController();
  int _selectedIndex = 0;

  bool _showFilters = false;
  String _searchQuery = '';
  String _typeFilter = 'all'; // 'all', 'video', 'list'

  @override
  void initState() {
    super.initState();
    // Se ejecuta automáticamente al renderizarse la vista principal
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ChangelogUtils.checkFirstTime(context);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) TutorialUtils.showMainAppTutorial(context);
      });
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _addDownload() async {
    if (_urlController.text.trim().isEmpty) return;
    final settingsCtrl = context.read<SettingsController>();
    final downloadsCtrl = context.read<DownloadsController>();
    final currentOptions = settingsCtrl.getDownloadOptionsPayload();
    final locale = context.read<LocaleController>().localeStrings;
    final result = await downloadsCtrl.addDownload(
      _urlController.text,
      currentOptions,
    );
    if (result) {
      _urlController.clear();
      ToastUtils.showInfo(locale.dDownloadSent);
    } else {
      ToastUtils.showError(locale.dDownloadSentError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadsCtrl = context.watch<DownloadsController>();
    final settingsCtrl = context.watch<SettingsController>();
    final locale = context.watch<LocaleController>().localeStrings;
    // 1. APLICAMOS EL FILTRADO MAESTRO AQUÍ
    final filteredAll = downloadsCtrl.downloads.where((d) {
      if (_searchQuery.isNotEmpty) {
        final title = d.info?.title?.toLowerCase() ?? '';
        if (!title.contains(_searchQuery.toLowerCase())) return false;
      }
      if (_typeFilter != 'all') {
        final isList = d.info?.type == download_model.DownloadType.list;
        if (_typeFilter == 'list' && !isList) return false;
        if (_typeFilter == 'video' && isList) {
          return false;
        }
      }
      return true;
    }).toList();
    // 2. SEPARAMOS EN PESTAÑAS BASADOS EN LA LISTA YA FILTRADA
    final inProgress = filteredAll.where((d) {
      final state = d.state?.value;
      return state == download_model.DownloadStateEnum.requested ||
          state == download_model.DownloadStateEnum.pending ||
          state == download_model.DownloadStateEnum.awaitingSelection ||
          state == download_model.DownloadStateEnum.inProgress ||
          state == download_model.DownloadStateEnum.cancelling ||
          state == download_model.DownloadStateEnum.paused ||
          state == download_model.DownloadStateEnum.pausing;
    }).toList();

    final completed = filteredAll
        .where(
          (d) =>
              d.state?.value == download_model.DownloadStateEnum.completed ||
              d.state?.value ==
                  download_model.DownloadStateEnum.completedWithErrors,
        )
        .toList();

    final errors = filteredAll.where((d) {
      final state = d.state?.value;
      return state == download_model.DownloadStateEnum.failed ||
          state == download_model.DownloadStateEnum.cancelled ||
          state == download_model.DownloadStateEnum.deleted ||
          state == download_model.DownloadStateEnum.completedWithErrors;
    }).toList();

    final lists = [filteredAll, inProgress, completed, errors];
    final hasActiveFilter = _searchQuery.isNotEmpty || _typeFilter != 'all';

    return SelectionFabWrapper(
      child: Scaffold(
        // --- ZONA SUPERIOR (AppBar rediseñada) ---
        appBar: AppBar(
          titleSpacing: 0,
          leading: Padding(
            padding: EdgeInsets.all(8.0),
            child: SystemStatusIndicator(key: AppTutorialKeys.mainSystemStatus),
          ),
          // 2. Barra de texto para URL (Centro)
          title: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.maxFormWidth,
            ),
            child: TextField(
              key: AppTutorialKeys.mainUrlBar,
              controller: _urlController,
              decoration: InputDecoration(
                hintText: locale.dVideoUrl,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color:
                        Theme.of(
                          context,
                        ).extension<VidraSemanticColors>()?.borderSubtle ??
                        Theme.of(context).dividerColor.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color:
                        Theme.of(
                          context,
                        ).extension<VidraSemanticColors>()?.borderSubtle ??
                        Theme.of(context).dividerColor.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16,
                ),
                // Icono Pegar dentro de la barra
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  tooltip: locale.dPaste,
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _urlController.text = data!.text!;
                    }
                  },
                ),
              ),
              onSubmitted: (_) => _addDownload(),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: locale.dShowTutorial,
              onPressed: () =>
                  TutorialUtils.showMainAppTutorial(context, force: true),
            ),
            IconButton(
              key: AppTutorialKeys.mainFilter,
              icon: Icon(
                hasActiveFilter ? Icons.filter_alt : Icons.filter_alt_outlined,
                color: hasActiveFilter
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: locale.dFilters,
              onPressed: () => setState(() => _showFilters = !_showFilters),
            ),
            IconButton(
              key: AppTutorialKeys.mainSettings,
              icon: const Icon(Icons.settings),
              tooltip: locale.dSettings,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FittedBox(
          fit: BoxFit.scaleDown,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!Platform.isAndroid)
                  Badge(
                    isLabelVisible:
                        ((settingsCtrl
                                    .downloadOptions
                                    .sponsorblockRemove
                                    .isNotEmpty
                                ? 1
                                : 0) +
                            (settingsCtrl.downloadOptions.cutVideo ? 1 : 0)) >
                        0,
                    backgroundColor: Colors.red,
                    label: Text(
                      '${(settingsCtrl.downloadOptions.sponsorblockRemove.isNotEmpty ? 1 : 0) + (settingsCtrl.downloadOptions.cutVideo ? 1 : 0)}',
                    ),
                    child: FloatingActionButton(
                      heroTag: 'cut_video_fab',
                      tooltip: locale.dCutVideo,
                      onPressed: () => CutVideoBottomSheet.show(context),
                      child: const Icon(Icons.cut_outlined),
                    ),
                  ),
                const SizedBox(width: AppSpacing.space12),
                FloatingActionButton(
                  key: AppTutorialKeys.mainQuickSettings,
                  heroTag: 'quick_settings_fab',
                  tooltip: locale.dQuickSettings,
                  onPressed: () => QuickSettingsBottomSheet.show(context),
                  child: const Icon(Icons.construction_outlined),
                ),
                const SizedBox(width: AppSpacing.space12),
                FloatingActionButton.extended(
                  heroTag: 'download_fab',
                  onPressed: _addDownload,
                  icon: const Icon(Icons.download),
                  label: Text(
                    locale.dDownload,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        // --- CUERPO: Barra de Filtros + Lista de descargas ---
        body: Column(
          children: [
            // BARRA DE FILTROS ANIMADA
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _showFilters
                  ? _buildMainFiltersBar(locale)
                  : const SizedBox.shrink(),
            ),

            // ÁREA DE PESTAÑAS (Layout Vertical o Horizontal) O PROGRESO DE INICIALIZACIÓN
            Expanded(
              child: _buildMainContent(context, downloadsCtrl, lists, locale),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    DownloadsController downloadsCtrl,
    List<List<download_model.Download>> lists,
    AppStringKey locale,
  ) {
    final sysCtrl = context.watch<SystemController>();
    final updateCtrl = context.watch<UpdateController>();

    final isMissingResources =
        sysCtrl.state == SystemState.missingResources ||
        updateCtrl.isAutoDownloadingMissing;

    if (isMissingResources) {
      return _buildStartupProgressView(context, updateCtrl, locale);
    }

    if (downloadsCtrl.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isShort =
            AppBreakpoints.fromWidth(constraints.maxWidth) ==
            VidraBreakpoint.compact;
        if (isShort) return _buildVerticalLayout(lists, locale);
        return _buildHorizontalLayout(lists, locale);
      },
    );
  }

  Widget _buildStartupProgressView(
    BuildContext context,
    UpdateController updateCtrl,
    AppStringKey locale,
  ) {
    final theme = Theme.of(context);
    final semanticColors = theme.extension<VidraSemanticColors>();
    final progress = updateCtrl.missingModulesProgress;
    final hasError =
        updateCtrl.getState(ComponentType.ytDlp).status ==
            ComponentStatus.error ||
        updateCtrl.getState(ComponentType.ytDlpEjs).status ==
            ComponentStatus.error;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.space24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(AppSpacing.space24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  semanticColors?.borderSubtle ??
                  theme.dividerColor.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.space16),
                decoration: BoxDecoration(
                  color: hasError
                      ? (semanticColors?.error ?? Colors.red).withValues(
                          alpha: 0.1,
                        )
                      : theme.colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasError ? Icons.error_outline : Icons.downloading,
                  size: 48,
                  color: hasError
                      ? (semanticColors?.error ?? Colors.red)
                      : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.space16),
              Text(
                hasError
                    ? locale.dDownloadingEngineError
                    : locale.dEngineDownloading,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.space8),
              Text(
                hasError
                    ? locale.sdGithubConnectionError
                    : (progress > 0.0
                          ? '${(progress * 100).toStringAsFixed(0)}%'
                          : locale.dEngineDownloadingDesc),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (!hasError)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress > 0.0 ? progress : null,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              if (hasError)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.space8),
                  child: FilledButton.icon(
                    onPressed: () => updateCtrl.retryMissingModulesDownload(),
                    icon: const Icon(Icons.refresh),
                    label: Text(locale.sdButtonRetry),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET EXCLUSIVO DEL FILTRO MAIN ---
  Widget _buildMainFiltersBar(AppStringKey locale) {
    final semanticColors = Theme.of(context).extension<VidraSemanticColors>();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space16,
        vertical: AppSpacing.space12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color:
                semanticColors?.borderSubtle ??
                Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: locale.dSearchDownloads,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color:
                      semanticColors?.borderSubtle ??
                      Theme.of(context).dividerColor.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color:
                      semanticColors?.borderSubtle ??
                      Theme.of(context).dividerColor.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: AppSpacing.space12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'all',
                  label: Text(
                    locale.dFilterEverything,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: 'video',
                  label: Text(
                    locale.dFilterVideoAudio,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: 'list',
                  label: Text(
                    locale.dFilterPlaylist,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {_typeFilter},
              onSelectionChanged: (set) =>
                  setState(() => _typeFilter = set.first),
            ),
          ),
        ],
      ),
    );
  }

  // --- LAYOUT VERTICAL (Pantallas estrechas / Móviles) ---
  Widget _buildVerticalLayout(
    List<List<download_model.Download>> lists,
    AppStringKey locale,
  ) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                icon: const Icon(Icons.list_alt_outlined),
                text: locale.dEverything,
              ),
              Tab(
                icon: const Icon(
                  Icons.downloading_outlined,
                  color: Color(0xFF2196F3),
                ),
                text: locale.dInProgress,
              ),
              Tab(
                icon: const Icon(
                  Icons.check_circle_outline,
                  color: Color(0xFF4CAF50),
                ),
                text: locale.dCompleted,
              ),
              Tab(
                icon: const Icon(Icons.error_outline, color: Color(0xFFF44336)),
                text: locale.dError,
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: lists
                  .map((list) => _buildDownloadList(list, locale))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  // --- LAYOUT HORIZONTAL (Pantallas anchas / PC) ---
  Widget _buildHorizontalLayout(
    List<List<download_model.Download>> lists,
    AppStringKey locale,
  ) {
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) =>
              setState(() => _selectedIndex = index),
          labelType: NavigationRailLabelType.all,
          destinations: [
            NavigationRailDestination(
              icon: const Icon(Icons.list_alt_outlined),
              selectedIcon: const Icon(Icons.list_alt),
              label: Text(locale.dEverything),
            ),
            NavigationRailDestination(
              icon: const Icon(
                Icons.downloading_outlined,
                color: Color(0xFF2196F3),
              ),
              selectedIcon: const Icon(
                Icons.downloading,
                color: Color(0xFF2196F3),
              ),
              label: Text(locale.dInProgress),
            ),
            NavigationRailDestination(
              icon: const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF4CAF50),
              ),
              selectedIcon: const Icon(
                Icons.check_circle,
                color: Color(0xFF4CAF50),
              ),
              label: Text(locale.dCompleted),
            ),
            NavigationRailDestination(
              icon: const Icon(Icons.error_outline, color: Color(0xFFF44336)),
              selectedIcon: const Icon(Icons.error, color: Color(0xFFF44336)),
              label: Text(locale.dError),
            ),
          ],
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(
          child: IndexedStack(
            index: _selectedIndex,
            children: lists
                .map((list) => _buildDownloadList(list, locale))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadList(
    List<download_model.Download> list,
    AppStringKey locale,
  ) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.15),
            ),
            const SizedBox(height: AppSpacing.space16),
            Text(
              locale.dNoDownloads,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final download = list[index];
        return _SlideInListItem(
          key: ValueKey(download.id),
          itemId: download.id!, // <-- NUEVO: Le pasamos el ID único
          child: _DownloadListItem(download: download),
        );
      },
    );
  }
}

// =========================================================================
// ANIMADOR DE ENTRADA (Empuja y Desliza)
// =========================================================================
class _SlideInListItem extends StatefulWidget {
  final String itemId;
  final Widget child;
  const _SlideInListItem({
    required this.key,
    required this.itemId,
    required this.child,
  }) : super(key: key);
  @override
  // ignore: overridden_fields
  final Key key;
  @override
  State<_SlideInListItem> createState() => _SlideInListItemState();
}

class _SlideInListItemState extends State<_SlideInListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _sizeAnim;

  // Memoria estática que recuerda qué IDs ya fueron animados.
  static final Set<String> _animatedItems = {};

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart));

    _sizeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    // Si la descarga ya se animó antes (porque hicimos scroll abajo/arriba), saltamos la animación.
    if (_animatedItems.contains(widget.itemId)) {
      _ctrl.value =
          1.0; // Lo pintamos abierto y al 100% de tamaño instantáneamente.
    } else {
      // Si es una descarga NUEVA, la registramos y hacemos la animación fluida.
      _animatedItems.add(widget.itemId);
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _sizeAnim,
      child: SlideTransition(position: _slideAnim, child: widget.child),
    );
  }
}

// =========================================================================
// ITEM DE LA LISTA
// =========================================================================
class _DownloadListItem extends StatelessWidget {
  final download_model.Download download;
  const _DownloadListItem({required this.download});

  @override
  Widget build(BuildContext context) {
    return DownloadCard(
      downloadId: download.id,
      info: download.info,
      state: download.state,
      isDetailScreen: false,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DownloadDetailScreen(download: download),
          ),
        );
      },
      onActionTap: () {
        debugPrint('Tapped Action on ${download.id}');
      },
    );
  }
}
