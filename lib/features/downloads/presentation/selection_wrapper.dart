import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/shared/utils/toast_utils.dart';
import 'downloads_controller.dart';
import 'selection_modal_controller.dart';

class SelectionFabWrapper extends StatefulWidget {
  final Widget child;

  const SelectionFabWrapper({super.key, required this.child});

  @override
  State<SelectionFabWrapper> createState() => _SelectionFabWrapperState();
}

class _SelectionFabWrapperState extends State<SelectionFabWrapper> {
  final List<String> _queue = [];
  final Set<String> _dismissedIds = {};

  String? _activeModalId;
  BuildContext? _dialogContext;

  @override
  void initState() {
    super.initState();
    // Escuchamos los cambios del controlador de forma global
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DownloadsController>().addListener(_onDownloadsUpdated);
    });
  }

  void _onDownloadsUpdated() {
    if (!mounted) return;

    final ctrl = context.read<DownloadsController>();
    final awaitingDownloads = ctrl.downloads
        .where((d) => d.state?.value == DownloadStateEnum.awaitingSelection)
        .toList();
    final awaitingIds = awaitingDownloads.map((d) => d.id!).toSet();

    // 1. Manejar peticiones manuales desde DownloadCard (Prioridad Alta)
    final manualReq = ctrl.manualModalRequestId;
    if (manualReq != null) {
      ctrl.consumeManualModalRequest();
      _dismissedIds.remove(manualReq);
      _queue.remove(manualReq);
      _queue.insert(0, manualReq); // Ponemos al inicio de la cola

      if (_activeModalId != null && _activeModalId != manualReq) {
        // Ya hay un modal abierto y no queremos interrumpirlo
        ToastUtils.showInfo("Selección encolada");
      }
    }

    // 2. Auto-cerrar el modal si la descarga en pantalla ya no está en estado "awaitingSelection"
    // (Por ejemplo, cambió de estado por un Delta mientras el modal estaba abierto)
    if (_activeModalId != null && !awaitingIds.contains(_activeModalId)) {
      _closeCurrentModal();
    }

    // 3. Limpiar las colas de IDs que ya no existen o no están pendientes
    _queue.removeWhere((id) => !awaitingIds.contains(id));
    _dismissedIds.removeWhere((id) => !awaitingIds.contains(id));

    // 4. Agregar a la cola nuevos deltas automáticamente
    for (var id in awaitingIds) {
      if (id != _activeModalId &&
          !_queue.contains(id) &&
          !_dismissedIds.contains(id)) {
        _queue.add(id);
      }
    }

    // 5. Procesar el siguiente elemento de la cola
    _processQueue(awaitingDownloads);
  }

  void _processQueue(List<Download> awaitingDownloads) {
    // Solo abrimos uno si no hay nada activo y la cola tiene elementos
    if (_activeModalId == null && _queue.isNotEmpty) {
      final nextId = _queue.removeAt(0);
      final download = awaitingDownloads
          .where((d) => d.id == nextId)
          .firstOrNull;

      if (download != null) {
        _openModal(download);
      } else {
        _processQueue(
          awaitingDownloads,
        ); // Intentar con el siguiente por si se corrompió
      }
    }
  }

  void _openModal(Download download) {
    _activeModalId = download.id;

    showDialog(
      context: context,
      barrierDismissible: false, // Forzar uso de botones para salir
      builder: (ctx) {
        _dialogContext =
            ctx; // Guardamos el contexto para poder auto-cerrarlo remotamente
        return ChangeNotifierProvider(
          create: (_) => SelectionModalController(
            context.read<DownloadRepository>(),
            [
              download,
            ], // Solo inyectamos ESE elemento para respetar la cola aislada
          ),
          child: const _SelectionDialog(), // Usa tu UI actual
        );
      },
    ).then((_) {
      if (!mounted) return;

      // Si el modal se cierra (por el usuario o automáticamente), lo marcamos como descartado
      // para que el stream no lo vuelva a abrir inmediatamente.
      if (_activeModalId != null) {
        _dismissedIds.add(_activeModalId!);
      }
      _activeModalId = null;
      _dialogContext = null;

      // Llamamos a la validación para abrir el siguiente en la cola
      _onDownloadsUpdated();
    });
  }

  void _closeCurrentModal() {
    if (_dialogContext != null && _dialogContext!.mounted) {
      Navigator.pop(_dialogContext!);
      // Nota: El .then() del showDialog ejecutará el resto del ciclo de limpieza
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mantenemos el FAB como indicador general para reabrir cosas descartadas
    final pending = context
        .watch<DownloadsController>()
        .downloads
        .where((d) => d.state?.value == DownloadStateEnum.awaitingSelection)
        .toList();

    return Stack(
      children: [
        widget.child, // Tu pantalla normal de fondo
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
                bool enqueued = false;
                for (var p in pending) {
                  _dismissedIds.remove(p.id);
                  if (p.id != _activeModalId && !_queue.contains(p.id)) {
                    _queue.add(p.id!);
                    enqueued = true;
                  }
                }

                if (_activeModalId == null) {
                  _processQueue(pending);
                } else if (enqueued) {
                  ToastUtils.showInfo("Listas re-encoladas");
                }
              },
            ),
          ),
      ],
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
