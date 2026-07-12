import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/domain/download.dart' as model;
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/shared/utils/toast_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class DownloadCard extends StatelessWidget {
  final String? downloadId;
  final model.Info? info;
  final model.DownloadState? state;
  final bool isDetailScreen;
  final VoidCallback? onTap;
  final VoidCallback? onActionTap;

  const DownloadCard({
    super.key,
    this.downloadId,
    required this.info,
    required this.state,
    this.isDetailScreen = false,
    this.onTap,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    // Los que lo invocan ya hacen context.watch Locale
    final locale = context.read<LocaleController>().localeStrings;
    final isError = state?.value == model.DownloadStateEnum.failed;
    final isCompleted = state?.value == model.DownloadStateEnum.completed;
    final isCompletedWithErrors =
        state?.value == model.DownloadStateEnum.completedWithErrors;
    final inProgress = state?.value == model.DownloadStateEnum.inProgress;
    final isPending =
        state?.value == model.DownloadStateEnum.pending ||
        state?.value == model.DownloadStateEnum.requested;
    final isPaused = state?.value == model.DownloadStateEnum.paused;
    final isCancelled = state?.value == model.DownloadStateEnum.cancelled;
    final isAwaiting =
        state?.value == model.DownloadStateEnum.awaitingSelection;

    // --- LÓGICA DE VISIBILIDAD DE BOTONES ---
    final isList = info?.type == model.DownloadType.list;
    final hasFile = info?.file != null && info!.file!.isNotEmpty;

    // 1. Mostrar Play
    final showPlay = isCompleted && !isList && hasFile;
    // 2. Mostrar Carpeta
    final showFolder = isCompleted && !isList && hasFile && !Platform.isAndroid;
    // 3. Mostrar Info
    final showInfo = isError && !isDetailScreen;
    // 4. Borrar
    final showDelete =
        (isError || isCancelled || isCompleted || isCompletedWithErrors) &&
        !isDetailScreen;
    // 5. Pausar
    final showPause =
        state?.value == model.DownloadStateEnum.inProgress && !isDetailScreen;
    // 6. Cancelar (Estados pendientes y progreso)
    final showCancel =
        (isPending || inProgress || isPaused || isAwaiting) && !isDetailScreen;
    // 7. Reanudar (Si está en pausa)
    final showResume = isPaused && !isDetailScreen;
    // 8. Reintentar (Si canceló manualmente o falló)
    final showRetry =
        (isError || isCancelled || isCompletedWithErrors) && !isDetailScreen;

    int actionCount = 0;
    if (showPlay) actionCount += 1;
    if (showFolder) actionCount += 1;
    if (showInfo) actionCount += 1;
    if (showResume) actionCount += 1;
    if (showRetry) actionCount += 1;
    if (showPause) actionCount += 1;
    if (showCancel) actionCount += 1;
    if (showDelete) actionCount += 1;

    Widget cardContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildImage(context, isError),
        const SizedBox(width: 12),
        Expanded(child: _buildDetails(context)),
        if (actionCount > 0)
          const Icon(
            Icons.chevron_left,
            color: Colors.grey,
            size: 16,
          ), // Pista visual de gesto
      ],
    );

    final cardWidget = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (isError) {
            ToastUtils.showError(state?.errorMessage ?? locale.dcUnknownError);
          } else if (state?.value ==
              model.DownloadStateEnum.awaitingSelection) {
            context.read<DownloadsController>().requestSelectionModal(
              downloadId!,
            );
          } else if (!isDetailScreen && onTap != null) {
            onTap!();
          }
        },
        child: Opacity(
          opacity: isError ? 0.6 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: cardContent,
          ),
        ),
      ),
    );

    if (downloadId == null || actionCount == 0) return cardWidget;

    // =========================================================================
    // LÓGICA DE GESTOS (SLIDABLE)
    // =========================================================================
    return LayoutBuilder(
      builder: (context, constraints) {
        // MATEMÁTICA PURA: Cada botón mide ~70px. Dividimos ese ancho total
        // entre el ancho disponible de la pantalla para obtener el ratio exacto.
        // Lo limitamos (clamp) para que nunca se rompa en pantallas enanas o gigantes.
        final double ratio = ((70.0 * actionCount) / constraints.maxWidth)
            .clamp(0.1, 0.8);

        return Slidable(
          key: ValueKey(downloadId),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: ratio, // <--- AQUÍ APLICAMOS EL CINTURÓN DE SEGURIDAD
            // Borrado gestual a tope SOLO permitido si está completado o en error
            dismissible: showDelete
                ? DismissiblePane(
                    onDismissed: () async {
                      final result = await context
                          .read<DownloadsController>()
                          .sendAction(downloadId!, 'delete');
                      if (result) {
                        ToastUtils.showInfo(locale.dcDownloadRemoving);
                      } else {
                        ToastUtils.showError(locale.dcDownloadRemovingError);
                      }
                    },
                  )
                : null,

            children: [
              if (showPlay) ...[
                SlidableAction(
                  onPressed: (_) async {
                    final mimeType = lookupMimeType(info!.file!) ?? 'video/*';
                    await OpenFilex.open(info!.file!, type: mimeType);
                  },
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  icon: Icons.play_arrow,
                ),
              ],
              if (showFolder) ...[
                SlidableAction(
                  onPressed: (_) async {
                    final dir = p.dirname(info!.file!);
                    final Uri directoryUri = Uri.file(dir);
                    await launchUrl(
                      directoryUri,
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  icon: Icons.folder,
                ),
              ],
              if (showInfo) ...[
                SlidableAction(
                  onPressed: (_) => onTap?.call(), // Va a detalles
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  icon: Icons.info,
                ),
              ],
              if (showResume) ...[
                SlidableAction(
                  onPressed: (_) async {
                    final result = await context
                        .read<DownloadsController>()
                        .sendAction(downloadId!, 'resume');
                    if (result) {
                      ToastUtils.showInfo(locale.dcDownloadResuming);
                    } else {
                      ToastUtils.showError(locale.dcDownloadResumingError);
                    }
                  },
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  icon: Icons.play_arrow,
                ),
              ],
              if (showRetry) ...[
                SlidableAction(
                  onPressed: (_) async {
                    final result = await context
                        .read<DownloadsController>()
                        .sendAction(downloadId!, 'retry');
                    if (result) {
                      ToastUtils.showInfo(locale.dcDownloadRetrying);
                    } else {
                      ToastUtils.showError(locale.dcDownloadRetryingError);
                    }
                  },
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  icon: Icons.refresh,
                ),
              ],
              if (showPause) ...[
                SlidableAction(
                  onPressed: (_) async {
                    final result = await context
                        .read<DownloadsController>()
                        .sendAction(downloadId!, 'pause');
                    if (result) {
                      ToastUtils.showInfo(locale.dcDownloadPausing);
                    } else {
                      ToastUtils.showError(locale.dcDownloadPausingError);
                    }
                  },
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.white,
                  icon: Icons.pause,
                ),
              ],
              if (showCancel) ...[
                SlidableAction(
                  onPressed: (_) => _showCancelDialog(context, downloadId!),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  icon: Icons.cancel,
                ),
              ],
              if (showDelete) ...[
                SlidableAction(
                  onPressed: (_) async {
                    final result = await context
                        .read<DownloadsController>()
                        .sendAction(downloadId!, 'delete');
                    if (result) {
                      ToastUtils.showInfo(locale.dcDownloadRemoving);
                    } else {
                      ToastUtils.showError(locale.dcDownloadRemovingError);
                    }
                  },
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  icon: Icons.delete,
                ),
              ],
            ],
          ),
          child: cardWidget,
        );
      },
    );
  }

  void _showCancelDialog(BuildContext context, String id) {
    // SOLUCIÓN AL BUG DEL DIÁLOGO: Capturamos la referencia al Controller ANTES
    // de abrir el Dialog. Así, aunque la Tarjeta se desactive al fondo,
    // la acción de cancelación no dependerá del contexto del UI.
    final controller = context.read<DownloadsController>();
    final locale = context.read<LocaleController>().localeStrings;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.dcDownloadCancelTitle),
        content: Text(locale.dcDownloadCancelMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(locale.dcDownloadNoCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final result = await controller.sendAction(id, 'cancel');
              if (result) {
                ToastUtils.showInfo(locale.dcDownloadCancelling);
              } else {
                ToastUtils.showError(locale.dcDownloadCancellingError);
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: Text(locale.dcDownloadCancel),
          ),
        ],
      ),
    );
  }

  // --- IMAGEN (50x50px con Indicadores Animados) ---
  Widget _buildImage(BuildContext context, bool isError) {
    final imageUrl = info?.image ?? '';

    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        children: [
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
          if (isError)
            Container(
              color: Colors.black45,
              child: Center(
                child: Icon(
                  Icons.priority_high,
                  color: Theme.of(context).colorScheme.error,
                  size: 28,
                ),
              ),
            ),

          // Indicador de Estado Animado (Arriba derecha)
          Positioned(top: 1, right: 1, child: _buildAnimatedStateIcon()),

          // Indicador de Tipo (Abajo derecha)
          Positioned(
            bottom: 0,
            right: 0,
            child: _buildShadowedIcon(
              _mapTypeIcon(info?.type),
              17,
              _mapTypeIconColor(info?.type),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedStateIcon() {
    final iconData = _mapStateIcon(state?.value);
    final semanticColor = state?.subStateColor?.color ?? Colors.white;

    // Animación sutil de rebote para descargas en progreso
    if (state?.value == model.DownloadStateEnum.inProgress) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(seconds: 1),
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, (value * 2).abs() - 1), // Efecto rebote suave
            child: child,
          );
        },
        child: _buildShadowedIcon(iconData, 15, semanticColor),
        onEnd:
            () {}, // Idealmente aquí haríamos un bucle, pero para mantenerlo ligero lo dejamos así
      );
    }
    return _buildShadowedIcon(iconData, 15, semanticColor);
  }

  // Utilidad para íconos con sombra (asegura que se vean sobre fondos blancos o negros)
  Widget _buildShadowedIcon(IconData iconData, double size, Color color) {
    return Icon(
      iconData,
      size: size,
      color: color,
      shadows: const [
        Shadow(blurRadius: 3.0, color: Colors.black),
        Shadow(blurRadius: 1.0, color: Colors.black),
      ],
    );
  }

  // --- DETALLES CENTRALES ---
  Widget _buildDetails(BuildContext context) {
    final autor = info?.autor ?? '';
    final duration = info?.duration ?? '';
    final platform = info?.platform ?? '';
    final infoList = [
      autor,
      duration,
      platform,
    ].where((e) => e.isNotEmpty).toList();
    String infoText = infoList.join(' • ');
    final locale = context.read<LocaleController>().localeStrings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Título
        Text(
          info?.title ?? locale.dcGettingDownloadInfo,
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
        //const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: _AnimatedProgressBar(
                  value:
                      state?.progressValue ??
                      (state?.value == model.DownloadStateEnum.inProgress
                          ? null
                          : 1.0),
                  color: state?.progressColor?.color ?? Colors.blue,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            if (state?.progressLabel != null) ...[
              const SizedBox(width: 8),
              Text(state!.progressLabel!, style: const TextStyle(fontSize: 10)),
            ],
            if (state?.speed != null) ...[
              const SizedBox(width: 8),
              Text(state!.speed!, style: const TextStyle(fontSize: 10)),
            ],
          ],
        ),
        if (state?.subState != null ||
            state?.value == model.DownloadStateEnum.failed ||
            state?.value == model.DownloadStateEnum.completedWithErrors) ...[
          //const SizedBox(height: 2),
          Text(
            ((state?.value == model.DownloadStateEnum.failed ||
                        state?.value ==
                            model.DownloadStateEnum.completedWithErrors)
                    ? state?.errorMessage ?? locale.dcUnknownError
                    : state?.subState) ??
                '',
            style: TextStyle(
              fontSize: 10,
              color: state?.subStateColor?.color ?? Colors.blue,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  // =========================================================================
  // MAPPERS
  // =========================================================================

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

  Color _mapTypeIconColor(model.DownloadType? type) {
    switch (type) {
      case model.DownloadType.video:
        return Colors.blue;
      case model.DownloadType.list:
        return Colors.deepPurpleAccent;
      case model.DownloadType.unknown:
      default:
        return Colors.grey;
    }
  }

  IconData _mapStateIcon(model.DownloadStateEnum? state) {
    switch (state) {
      case model.DownloadStateEnum.requested:
      case model.DownloadStateEnum.pending:
        return Icons.schedule;
      case model.DownloadStateEnum.awaitingSelection:
        return Icons.rule;
      case model.DownloadStateEnum.inProgress:
        return Icons.downloading; // Icono de flecha animable/movimiento
      case model.DownloadStateEnum.completed:
        return Icons.check_circle;
      case model.DownloadStateEnum.failed:
        return Icons.error;
      case model.DownloadStateEnum.cancelled:
        return Icons.cancel;
      case model.DownloadStateEnum.paused:
        return Icons.pause_circle;
      case model.DownloadStateEnum.deleted:
        return Icons.delete;
      default:
        return Icons.cloud_download;
    }
  }
}

// =========================================================================
// BARRA DE PROGRESO INTELIGENTE (Soluciona el bug del Scroll)
// =========================================================================
class _AnimatedProgressBar extends StatefulWidget {
  final double? value;
  final Color color;
  final Color backgroundColor;

  const _AnimatedProgressBar({
    required this.value,
    required this.color,
    required this.backgroundColor,
  });

  @override
  State<_AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<_AnimatedProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double? _lastValue;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _lastValue = widget.value;
    // Nace exactamente en el valor actual, sin animar desde 0
    _animation = Tween<double>(
      begin: _lastValue ?? 0.0,
      end: _lastValue ?? 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(_AnimatedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Solo anima si el valor real vino del backend y es diferente
    if (widget.value != oldWidget.value && widget.value != null) {
      _animation =
          Tween<double>(
            begin: _animation.value, // Comienza desde donde se quedó
            end: widget.value!,
          ).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          );
      _controller.forward(from: 0.0);
      _lastValue = widget.value;
    } else if (widget.value == null) {
      _lastValue = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lastValue == null) {
      return LinearProgressIndicator(
        value: null,
        minHeight: 4,
        color: widget.color,
        backgroundColor: widget.backgroundColor,
      );
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => LinearProgressIndicator(
        value: _animation.value,
        minHeight: 4,
        color: widget.color,
        backgroundColor: widget.backgroundColor,
      ),
    );
  }
}
