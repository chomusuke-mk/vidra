import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/presentation/selection_wrapper.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'download_detail_controller.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart' as model;
import 'package:vidra/shared/widgets/download_card.dart';

class DownloadDetailScreen extends StatelessWidget {
  final model.Download download;

  const DownloadDetailScreen({super.key, required this.download});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().localeStrings;
    return ChangeNotifierProvider(
      create: (context) => DownloadDetailController(
        context.read<DownloadRepository>(),
        context.read<SystemController>(),
        download,
      ),
      // Envolvemos el Scaffold con nuestro SelectionFabWrapper
      child: SelectionFabWrapper(
        child: Scaffold(
          // Quitamos el const de AppBar si tu linter se queja, aunque aquí es seguro
          appBar: AppBar(title: Text(locale.ddTitle)),
          body: _DetailView(),
        ),
      ),
    );
  }
}

class _DetailView extends StatefulWidget {
  const _DetailView();

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DownloadDetailController>();
    final locale = context.watch<LocaleController>().localeStrings;
    context.watch<DownloadsController>();
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentDownload = controller.download;
    final subDownloads = currentDownload.subDownloads ?? [];

    // 1. Lógica Condicional de Pestañas
    final isListType = currentDownload.info?.type == model.DownloadType.list;
    final hasSubDownloads = subDownloads.isNotEmpty;
    final showSubsTab = isListType || hasSubDownloads;

    // Preparamos las listas dinámicas
    final tabs = <Tab>[];
    final destinations = <NavigationRailDestination>[];
    final views = <Widget>[];

    // Pestaña Opcional: Sub-Descargas
    if (showSubsTab) {
      tabs.add(Tab(text: locale.ddSubDownloads));
      destinations.add(
        NavigationRailDestination(
          icon: Icon(Icons.format_list_numbered),
          label: Text(locale.ddSubDownloads),
        ),
      );
      views.add(_buildSubDownloadsTab(context, controller, locale));
    }

    // Pestaña Fija: Logs
    tabs.add(Tab(text: locale.ddLogs));
    destinations.add(
      NavigationRailDestination(
        icon: Icon(Icons.receipt_long),
        label: Text(locale.ddLogs),
      ),
    );
    views.add(_buildLogsTab(controller, locale));

    // Pestaña Fija: Configuración
    tabs.add(Tab(text: locale.ddSettings));
    destinations.add(
      NavigationRailDestination(
        icon: Icon(Icons.settings_applications),
        label: Text(locale.ddSettings),
      ),
    );
    views.add(_buildConfigTab(currentDownload.options, locale));

    // Evitamos desbordamientos del índice si la pestaña de sub-descargas desaparece dinámicamente
    if (_selectedIndex >= views.length) _selectedIndex = 0;

    return Column(
      children: [
        // ZONA SUPERIOR: El Card Maestro
        DownloadCard(
          info: currentDownload.info,
          state: currentDownload.state,
          isDetailScreen: true,
        ),
        const Divider(height: 1),
        // ZONA INFERIOR: Menús y Contenido
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isShort = constraints.maxWidth < 600;
              if (isShort) {
                return DefaultTabController(
                  // El key fuerza a reconstruir el widget si cambia la cantidad de pestañas
                  key: ValueKey(tabs.length),
                  length: tabs.length,
                  child: Column(
                    children: [
                      TabBar(tabs: tabs),
                      Expanded(child: TabBarView(children: views)),
                    ],
                  ),
                );
              }

              // Layout PC / Tablet Apaisada
              return Row(
                children: [
                  NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (int index) =>
                        setState(() => _selectedIndex = index),
                    labelType: NavigationRailLabelType.all,
                    destinations: destinations,
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(
                    child: IndexedStack(index: _selectedIndex, children: views),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // VISTA SUB-DESCARGAS CON BUSCADOR Y FILTROS
  // =========================================================================
  Widget _buildSubDownloadsTab(
    BuildContext context,
    DownloadDetailController controller,
    AppStringKey locale,
  ) {
    final list = controller.filteredSubDownloads;
    final hasActiveFilters =
        controller.activeFilters.isNotEmpty ||
        controller.searchQuery.isNotEmpty;

    return Column(
      children: [
        // Cabecera con título y botón de visibilidad de filtros
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${list.length} ${locale.ddElements}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: Icon(
                  hasActiveFilters
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                  color: hasActiveFilters ? Colors.blue : null,
                ),
                tooltip: locale.ddSearchFilter,
                onPressed: controller.toggleSearchVisibility,
              ),
            ],
          ),
        ),

        // La Barra de Búsqueda y Filtros Animada
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: !controller.isSearchVisible
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: locale.ddSearchList,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: controller.searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => controller.updateSearch(''),
                                )
                              : null,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                        ),
                        onChanged: controller.updateSearch,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _buildFilterChip(
                              controller,
                              model.DownloadState.failed,
                              locale.ddErrors,
                              Icons.error,
                              Colors.red,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              controller,
                              model.DownloadState.inProgress,
                              locale.ddDownloading,
                              Icons.downloading,
                              Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              controller,
                              model.DownloadState.completed,
                              locale.ddCompleted,
                              Icons.check_circle,
                              Colors.green,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              controller,
                              model.DownloadState.pending,
                              locale.ddPending,
                              Icons.schedule,
                              Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),

        // La lista
        Expanded(
          child: list.isEmpty
              ? Center(child: Text(locale.ddNoElements))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final sub = list[index];
                    return DownloadCard(
                      downloadId: sub.subId,
                      info: sub.info,
                      state: sub.state,
                      isDetailScreen: true,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(
    DownloadDetailController ctrl,
    model.DownloadState state,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = ctrl.activeFilters.contains(state);
    return FilterChip(
      showCheckmark: false,
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? color : Colors.grey),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? color : null,
              fontWeight: isSelected ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
      onSelected: (_) => ctrl.toggleFilter(state),
      backgroundColor: Colors.transparent,
      selectedColor: color.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? color : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildLogsTab(
    DownloadDetailController controller,
    AppStringKey locale,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Botón superior de recarga
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(locale.ddReload),
              onPressed: controller.isLoadingLogs
                  ? null
                  : () => controller.fetchLogs(),
            ),
          ),
        ),

        // Contenedor del Log
        Expanded(
          child: controller.isLoadingLogs
              ? const Center(child: CircularProgressIndicator())
              : Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      controller.logs.isEmpty
                          ? locale.ddNoLogs
                          : controller.logs,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildConfigTab(Map<String, dynamic>? options, AppStringKey locale) {
    if (options == null || options.isEmpty) {
      return Center(child: Text(locale.ddNoSettings),
      );
    }

    // Convertimos el Map a un String JSON formateado (Indented)
    final jsonString = const JsonEncoder.withIndent('  ').convert(options);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: SelectableText(
            jsonString,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      ),
    );
  }
}
