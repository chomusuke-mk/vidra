import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/presentation/selection_wrapper.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/domain/download.dart'
    as download_model;
import 'package:vidra/features/settings/presentation/settings_screen.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/shared/widgets/download_card.dart';
import 'download_detail_screen.dart';
import 'package:vidra/features/system/presentation/system_status_indicator.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final TextEditingController _urlController = TextEditingController();
  int _selectedIndex = 0;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _addDownload() {
    if (_urlController.text.trim().isEmpty) return;
    final settingsCtrl = context.read<SettingsController>();
    final downloadsCtrl = context.read<DownloadsController>();
    final currentOptions = settingsCtrl.getDownloadOptionsPayload();
    downloadsCtrl.addDownload(_urlController.text, currentOptions);
    _urlController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final downloadsCtrl = context.watch<DownloadsController>();
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
          leading: const Padding(
            padding: EdgeInsets.all(8.0),
            // TODO: Haz que tu SystemStatusIndicator sea más cuadrado/pequeño o solo ícono
            child: SystemStatusIndicator(),
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
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Configuración',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addDownload,
          icon: const Icon(Icons.download),
          label: const Text(
            'Descargar',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
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

  // Busca tu función _buildDownloadList y actualízala así:
  Widget _buildDownloadList(List<download_model.Download> list) {
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
              ).colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No hay descargas aquí',
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
