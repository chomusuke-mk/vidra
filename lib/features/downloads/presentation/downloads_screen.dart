import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Necesario para el Clipboard (Portapapeles)
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/presentation/selection_wrapper.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/domain/download.dart'
    as download_model;
import 'package:vidra/features/settings/presentation/settings_screen.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/shared/widgets/download_card.dart';
import 'download_detail_screen.dart';

// Importamos nuestra pastilla indicadora
import 'package:vidra/features/system/presentation/system_status_indicator.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final TextEditingController _urlController = TextEditingController();
  int _selectedIndex = 0; // Para el layout horizontal (NavigationRail)

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _addDownload() {
    if (_urlController.text.trim().isEmpty) return;

    final settingsCtrl = context.read<SettingsController>();
    final downloadsCtrl = context.read<DownloadsController>();

    // Extraemos el payload JSON del controlador de configuraciones
    final currentOptions = settingsCtrl.getDownloadOptionsPayload();
    downloadsCtrl.addDownload(_urlController.text, currentOptions);

    _urlController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final downloadsCtrl = context.watch<DownloadsController>();

    // =========================================================================
    // LÓGICA DE FILTRADO PARA LAS PESTAÑAS
    // =========================================================================
    final all = downloadsCtrl.downloads;

    final inProgress = all.where((d) {
      final state = d.state?.value;
      return state == download_model.DownloadState.requested ||
          state == download_model.DownloadState.pending ||
          state == download_model.DownloadState.identifying ||
          state == download_model.DownloadState.waitForSelection ||
          state == download_model.DownloadState.inProgress ||
          state == download_model.DownloadState.paused;
    }).toList();

    final completed = all
        .where((d) => d.state?.value == download_model.DownloadState.completed)
        .toList();

    final errors = all.where((d) {
      final state = d.state?.value;
      return state == download_model.DownloadState.failed ||
          state == download_model.DownloadState.canceled ||
          state == download_model.DownloadState.deleted;
    }).toList();

    final lists = [all, inProgress, completed, errors];

    return SelectionFabWrapper(
      child: Scaffold(
        // --- ZONA SUPERIOR (AppBar rediseñada) ---
        appBar: AppBar(
          titleSpacing: 0,
          // 1. Botón Settings (Izquierda)
          leading: IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configuración',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          // 2. Barra de texto para URL (Centro)
          title: TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'URL del video...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              // Icono Pegar dentro de la barra
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                tooltip: 'Pegar',
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
          // 3. Botones (Derecha)
          actions: [
            // LA PASTILLA DEL CEREBRO VA AQUÍ
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: SystemStatusIndicator(),
            ),
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Añadir Descarga',
              color: Theme.of(context).colorScheme.primary,
              onPressed: _addDownload,
            ),
            const SizedBox(width: 4),
          ],
        ),

        // --- ZONA INFERIOR (Submenús / Tabs Responsivos) ---
        body: downloadsCtrl.isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Layout "Vertical" (Tabs arriba) si el ancho es menor a 600
                  final isShort = constraints.maxWidth < 600;
                  if (isShort) return _buildVerticalLayout(lists);
                  // Layout "Horizontal" (Tabs laterales) si hay espacio
                  return _buildHorizontalLayout(lists);
                },
              ),
      ),
    );
  }

  // --- LAYOUT VERTICAL (Pantallas estrechas / Móviles) ---
  Widget _buildVerticalLayout(List<List<download_model.Download>> lists) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Todo'),
              Tab(text: 'En progreso'),
              Tab(text: 'Completado'),
              Tab(text: 'Error'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: lists.map((list) => _buildDownloadList(list)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // --- LAYOUT HORIZONTAL (Pantallas anchas / PC) ---
  Widget _buildHorizontalLayout(List<List<download_model.Download>> lists) {
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) =>
              setState(() => _selectedIndex = index),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.list),
              label: Text('Todo'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.downloading),
              label: Text('En progreso'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.done_all),
              label: Text('Completado'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.error_outline),
              label: Text('Error'),
            ),
          ],
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(
          child: IndexedStack(
            index: _selectedIndex,
            children: lists.map((list) => _buildDownloadList(list)).toList(),
          ),
        ),
      ],
    );
  }

  // --- HELPER: Renderiza la lista sin repetir código ---
  Widget _buildDownloadList(List<download_model.Download> list) {
    if (list.isEmpty) {
      return const Center(child: Text('No hay descargas en esta categoría.'));
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        return _DownloadListItem(download: list[index]);
      },
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
