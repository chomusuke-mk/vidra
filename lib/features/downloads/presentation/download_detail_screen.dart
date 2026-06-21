import 'dart:convert'; // Para el formateo del JSON
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/presentation/selection_wrapper.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'download_detail_controller.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart' as model;
import 'package:vidra/shared/widgets/download_card.dart'; // Tu nueva tarjeta mágica

class DownloadDetailScreen extends StatelessWidget {
  final model.Download download;

  const DownloadDetailScreen({super.key, required this.download});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => DownloadDetailController(
        context.read<DownloadRepository>(),
        download,
      ),
      // Envolvemos el Scaffold con nuestro SelectionFabWrapper
      child: SelectionFabWrapper(
        child: Scaffold(
          // Quitamos el const de AppBar si tu linter se queja, aunque aquí es seguro
          appBar: AppBar(title: Text('Detalles de Descarga')),
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
    context.watch<DownloadsController>();
    if (controller.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Sincronizando información...'),
          ],
        ),
      );
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
      tabs.add(const Tab(text: 'Sub-Descargas'));
      destinations.add(
        const NavigationRailDestination(
          icon: Icon(Icons.format_list_numbered),
          label: Text('Sub-Descargas'),
        ),
      );
      views.add(_buildSubDownloadsTab(subDownloads));
    }

    // Pestaña Fija: Logs
    tabs.add(const Tab(text: 'Logs'));
    destinations.add(
      const NavigationRailDestination(
        icon: Icon(Icons.receipt_long),
        label: Text('Logs'),
      ),
    );
    views.add(_buildLogsTab(controller));

    // Pestaña Fija: Configuración
    tabs.add(const Tab(text: 'Configuración'));
    destinations.add(
      const NavigationRailDestination(
        icon: Icon(Icons.settings_applications),
        label: Text('Configuración'),
      ),
    );
    views.add(_buildConfigTab(currentDownload.options));

    // Evitamos desbordamientos del índice si la pestaña de sub-descargas desaparece dinámicamente
    if (_selectedIndex >= views.length) _selectedIndex = 0;

    return Column(
      children: [
        // ZONA SUPERIOR: El Card Maestro (Fijo)
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
  // VISTAS DE LAS PESTAÑAS
  // =========================================================================

  Widget _buildSubDownloadsTab(List<model.SubDownload> subDownloads) {
    if (subDownloads.isEmpty) {
      return const Center(child: Text('Aún no hay sub-descargas.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: subDownloads.length,
      itemBuilder: (context, index) {
        final sub = subDownloads[index];
        return DownloadCard(
          info: sub.info,
          state: sub.state,
          isDetailScreen: true,
        );
      },
    );
  }

  Widget _buildLogsTab(DownloadDetailController controller) {
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
              label: const Text('Recargar'),
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
                          ? 'No hay logs disponibles.'
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

  Widget _buildConfigTab(Map<String, dynamic>? options) {
    if (options == null || options.isEmpty) {
      return const Center(
        child: Text('No hay configuración disponible para esta descarga.'),
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
