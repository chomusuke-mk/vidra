import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'downloads_controller.dart';
import 'selection_modal_controller.dart';

class SelectionFabWrapper extends StatelessWidget {
  final Widget child;

  const SelectionFabWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final downloadsCtrl = context.watch<DownloadsController>();

    // Filtramos las descargas que requieren acción
    final pending = downloadsCtrl.downloads
        .where((d) => d.state?.value == DownloadState.waitForSelection)
        .toList();

    return Stack(
      children: [
        child, // Tu pantalla normal de fondo
        // Si hay descargas pendientes, inyectamos el FAB
        if (pending.isNotEmpty)
          Positioned(
            bottom: 16,
            left: 16, // Inferior Izquierda, como pediste
            child: FloatingActionButton(
              heroTag: 'selection_fab', // Evita colisiones de animación
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Badge(
                label: Text('${pending.length}'),
                child: const Icon(Icons.playlist_add_check),
              ),
              onPressed: () {
                _openSelectionModal(context, pending);
              },
            ),
          ),
      ],
    );
  }

  void _openSelectionModal(BuildContext context, List<Download> pending) {
    // Usamos Dialog en vez de BottomSheet para tener un área gigante en móviles y centrado en PC
    showDialog(
      context: context,
      barrierDismissible: false, // Obliga al usuario a usar la X o los botones
      builder: (ctx) => ChangeNotifierProvider(
        create: (_) => SelectionModalController(
          context.read<DownloadRepository>(),
          pending,
        ),
        child: const _SelectionDialog(),
      ),
    );
  }
}

class _SelectionDialog extends StatelessWidget {
  const _SelectionDialog();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SelectionModalController>();
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600, // Límite de ancho para que se vea bien en PC
        height: MediaQuery.of(context).size.height * 0.85, // 85% de la pantalla
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // --- HEADER: Selector de Descarga y Cierre ---
            Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Download>(
                      value: ctrl.currentDownload,
                      isExpanded: true,
                      items: ctrl.pendingDownloads.map((d) {
                        return DropdownMenuItem(
                          value: d,
                          child: Text(
                            d.info?.title ?? 'Lista Desconocida',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) ctrl.switchDownload(val);
                      },
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),

            // --- BARRA DE HERRAMIENTAS: Búsqueda y Filtros ---
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: ctrl.updateSearch,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Elegidos'),
                  selected: ctrl.showOnlySelected,
                  onSelected: (_) => ctrl.toggleShowOnlySelected(),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // --- ACCIONES RÁPIDAS ---
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.select_all, size: 18),
                    label: const Text('Todo'),
                    onPressed: ctrl.selectAll,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.deselect, size: 18),
                    label: const Text('Nada'),
                    onPressed: ctrl.selectNone,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.flip, size: 18),
                    label: const Text('Invertir'),
                    onPressed: ctrl.invertSelection,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${ctrl.selectedIds.length} / ${ctrl.allEntries.length}',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // --- LISTA PRINCIPAL (Lazy Loading Nativo) ---
            Expanded(
              child: ctrl.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ctrl.filteredEntries.isEmpty
                  ? const Center(child: Text('No hay elementos que coincidan.'))
                  // ListView.builder es la magia: solo renderiza lo que ves
                  : ListView.builder(
                      itemCount: ctrl.filteredEntries.length,
                      itemBuilder: (context, index) {
                        final item = ctrl.filteredEntries[index];
                        final isSelected = ctrl.selectedIds.contains(
                          item.subId,
                        );

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (_) => ctrl.toggleSelection(item.subId!),
                          contentPadding: EdgeInsets.zero,
                          secondary: _buildThumbnail(item.info?.image, context),
                          title: Text(
                            item.info?.title ?? 'Sin título',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            item.info?.duration ?? '00:00',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(),

            // --- BOTÓN DE ENVÍO ---
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: ctrl.isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  ctrl.isSubmitting ? 'Enviando...' : 'Descargar Selección',
                ),
                onPressed: ctrl.isSubmitting || ctrl.isLoading
                    ? null
                    : () async {
                        final success = await ctrl.submit();
                        if (success && context.mounted) {
                          Navigator.pop(
                            context,
                          ); // Cierra el modal si fue un éxito
                        }
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(String? url, BuildContext context) {
    if (url == null || url.isEmpty) {
      return Container(
        width: 60,
        height: 40,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.video_file, size: 20),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 60,
        height: 40,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        errorWidget: (_, _, _) => const Icon(Icons.broken_image),
      ),
    );
  }
}
