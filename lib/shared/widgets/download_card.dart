import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:vidra/features/downloads/domain/download.dart' as model;
import 'package:vidra/shared/utils/toast_utils.dart';

class DownloadCard extends StatelessWidget {
  final model.Info? info;
  final model.State? state;
  final bool isDetailScreen;
  final VoidCallback? onTap;
  final VoidCallback? onActionTap;

  const DownloadCard({
    super.key,
    required this.info,
    required this.state,
    this.isDetailScreen = false,
    this.onTap,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final isError = state?.value == model.DownloadState.failed;

    Widget cardContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildImage(context, isError),
        const SizedBox(width: 12),
        Expanded(child: _buildDetails(context)),
        _buildMenu(context),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Interceptar click si es un error
          if (isError) {
            ToastUtils.showError(state?.subState ?? "Error desconocido");
          }
          // Acción normal si no es pantalla de detalles
          else if (!isDetailScreen && onTap != null) {
            onTap!();
          }
        },
        child: Opacity(
          opacity: isError ? 0.5 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: cardContent,
          ),
        ),
      ),
    );
  }

  // --- IMAGEN (50x50px con Indicadores) ---
  Widget _buildImage(BuildContext context, bool isError) {
    final imageUrl = info?.image ?? '';

    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        children: [
          // 1. Imagen en Caché
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image, size: 24),
                    ),
                  )
                : Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: Icon(Icons.video_file, size: 24),
                    ),
                  ),
          ),

          // 2. Icono central de error (!)
          if (isError)
            Container(
              color: Colors.black45, // Capa oscura para resaltar la advertencia
              child: Center(
                child: Icon(
                  Icons.priority_high,
                  color: Theme.of(context).colorScheme.error,
                  size: 28,
                ),
              ),
            ),

          // 3. Indicador Superior Derecho (Estado)
          Positioned(
            top: 1,
            right: 1,
            child: _buildShadowedIcon(_mapStateIcon(state?.value), 15),
          ),

          // 4. Indicador Inferior Derecho (Tipo)
          Positioned(
            bottom: 0,
            right: 0,
            child: _buildShadowedIcon(_mapTypeIcon(info?.type), 17),
          ),
        ],
      ),
    );
  }

  // Utilidad para íconos con sombra (asegura que se vean sobre fondos blancos o negros)
  Widget _buildShadowedIcon(IconData iconData, double size) {
    return Icon(
      iconData,
      size: size,
      color: Colors.white,
      shadows: const [
        Shadow(blurRadius: 3.0, color: Colors.black),
        Shadow(blurRadius: 1.0, color: Colors.black),
      ],
    );
  }

  // --- DETALLES CENTRALES ---
  Widget _buildDetails(BuildContext context) {
    final type = info?.type ?? model.DownloadType.unknown;
    final autor = info?.autor ?? 'Desconocido';
    final duration = info?.duration ?? '';

    // Lógica condicional del subtitulo
    String infoText;
    if (type == model.DownloadType.list) {
      infoText = autor;
    } else {
      infoText = duration.isNotEmpty ? '$autor • $duration' : autor;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Título
        Text(
          info?.title ?? 'Recuperando información...',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        //const SizedBox(height: 2),
        // Info Autor / Duration
        Text(
          infoText,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        // Progreso y Estados Secundarios
        if (state?.progressValue != null ||
            (state?.subState?.isNotEmpty ?? false)) ...[
          //const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(
                    value:
                        state?.progressValue ??
                        (state?.value == model.DownloadState.inProgress
                            ? null
                            : 1.0), // Indeterminado si está en progreso pero sin valor específico
                    minHeight: 4,
                    color: _mapColor(state?.progressColor),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              if (state?.progressLabel != null) ...[
                const SizedBox(width: 8),
                Text(
                  state!.progressLabel!,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
              if (state?.speed != null) ...[
                const SizedBox(width: 8),
                Text(state!.speed!, style: const TextStyle(fontSize: 10)),
              ],
            ],
          ),
          if (state?.subState != null) ...[
            //const SizedBox(height: 2),
            Text(
              state!.subState!,
              style: TextStyle(
                fontSize: 10,
                color: _mapColor(state?.subStateColor),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ],
    );
  }

  // --- MENÚ TRES PUNTOS ---
  Widget _buildMenu(BuildContext context) {
    final isCompleted = state?.value == model.DownloadState.completed;
    final isVideo = info?.type == model.DownloadType.video;
    final hasFile = info?.file != null && info!.file!.isNotEmpty;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        if (value == 'action') onActionTap?.call();
        if (value == 'details') onTap?.call();
        if (value == 'play') {
          final mimeType = lookupMimeType(info!.file!) ?? 'video/*';
          await OpenFilex.open(info!.file!, type: mimeType);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'action', child: Text('Acción')),
        if (!isDetailScreen)
          const PopupMenuItem(value: 'details', child: Text('Detalles')),
        if (isVideo && isCompleted && hasFile)
          const PopupMenuItem(value: 'play', child: Text('Reproducir')),
      ],
    );
  }

  // =========================================================================
  // MAPPERS
  // =========================================================================

  Color _mapColor(model.ColorEnum? c) {
    switch (c) {
      case model.ColorEnum.green:
        return Colors.green;
      case model.ColorEnum.yellow:
        return Colors.amber;
      case model.ColorEnum.red:
        return Colors.redAccent;
      case model.ColorEnum.blue:
        return Colors.blue;
      case model.ColorEnum.gray:
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  IconData _mapTypeIcon(model.DownloadType? type) {
    switch (type) {
      case model.DownloadType.video:
        return Icons.slow_motion_video_outlined;
      case model.DownloadType.list:
        return Icons.playlist_play;
      case model.DownloadType.unknown:
      default:
        return Icons.help_outline;
    }
  }

  IconData _mapStateIcon(model.DownloadState? state) {
    switch (state) {
      case model.DownloadState.requested:
      case model.DownloadState.pending:
        return Icons.schedule;
      case model.DownloadState.identifying:
        return Icons.search;
      case model.DownloadState.waitForSelection:
        return Icons.rule;
      case model.DownloadState.inProgress:
        return Icons.downloading; // Icono de flecha animable/movimiento
      case model.DownloadState.completed:
        return Icons.check_circle;
      case model.DownloadState.failed:
        return Icons.error;
      case model.DownloadState.canceled:
        return Icons.cancel;
      case model.DownloadState.paused:
        return Icons.pause_circle;
      case model.DownloadState.deleted:
        return Icons.delete;
      default:
        return Icons.cloud_download;
    }
  }
}
