import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:vidra/core/theme/colors.dart';
import 'package:vidra/core/theme/typography.dart';
import 'package:vidra/core/theme/animations.dart';
import 'package:vidra/core/theme/layout.dart';
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
  final bool isSubItem;
  final VoidCallback? onTap;
  final VoidCallback? onActionTap;

  const DownloadCard({
    super.key,
    this.downloadId,
    required this.info,
    required this.state,
    this.isDetailScreen = false,
    this.isSubItem = false,
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
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final isList = info?.type == model.DownloadType.list;
    final hasFile = info?.file != null && info!.file!.isNotEmpty;

    // 1. Mostrar Play:
    // Sub-items: si está completado y tiene archivo
    // Items normales: si está completado, no es lista y tiene archivo
    final showPlay = isSubItem
        ? (isCompleted && hasFile)
        : (isCompleted && !isList && hasFile);

    // 2. Mostrar Carpeta:
    // Sub-items: si está completado, tiene archivo y es desktop
    // Items normales: si está completado (o con errores), es desktop y tiene archivo o es lista
    final showFolder = isSubItem
        ? (isCompleted && hasFile && isDesktop)
        : ((isCompleted || isCompletedWithErrors) &&
              isDesktop &&
              (hasFile || isList));

    // 3. Acciones prohibidas para sub-items (solo permitidas para items principales):
    final showInfo = !isSubItem && !isDetailScreen;
    final showDelete =
        !isSubItem &&
        (isError ||
            isCancelled ||
            isCompleted ||
            isCompletedWithErrors ||
            isAwaiting);
    final showPause =
        !isSubItem && state?.value == model.DownloadStateEnum.inProgress;
    final showCancel = !isSubItem && (isPending || inProgress || isPaused);
    final showResume = !isSubItem && isPaused;
    final showRetry =
        !isSubItem && (isError || isCancelled || isCompletedWithErrors);

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
        const SizedBox(width: AppSpacing.space12),
        Expanded(child: _buildDetails(context)),
        if (actionCount > 0)
          Icon(
            Icons.chevron_left,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            size: 16,
          ), // Pista visual de gesto
      ],
    );

    final semanticColors = Theme.of(context).extension<VidraSemanticColors>();

    Widget buildCardWidget(BuildContext cardContext) {
      return Card(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space16,
          vertical: 6,
        ),
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isError
                ? (semanticColors?.error ?? Theme.of(context).colorScheme.error)
                : (semanticColors?.borderSubtle ?? Colors.transparent),
            width: isError ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (isError) {
              ToastUtils.showError(
                state?.errorMessage ?? locale.dcUnknownError,
              );
            } else if (state?.value ==
                model.DownloadStateEnum.awaitingSelection) {
              context.read<DownloadsController>().requestSelectionModal(
                downloadId!,
              );
            } else {
              final slidable = Slidable.of(cardContext);
              if (slidable != null && actionCount > 0) {
                final isClosed =
                    slidable.actionPaneType.value == ActionPaneType.none &&
                    slidable.animation.value == 0;
                if (isClosed) {
                  slidable.openEndActionPane();
                } else {
                  slidable.close();
                }
              } else if (!isDetailScreen && onTap != null) {
                onTap!();
              }
            }
          },
          onLongPress: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space12),
            child: cardContent,
          ),
        ),
      );
    }

    if (downloadId == null || actionCount == 0) {
      return buildCardWidget(context);
    }

    // =========================================================================
    // LÓGICA DE GESTOS (SLIDABLE)
    // =========================================================================
    return LayoutBuilder(
      builder: (context, constraints) {
        // MATEMÁTICA PURA: Cada botón mide ~54px. Dividimos ese ancho total
        // entre el ancho disponible de la pantalla para obtener el ratio exacto.
        // Lo limitamos (clamp) para que nunca se rompa en pantallas enanas o gigantes.
        final double ratio = ((70.0 * actionCount) / constraints.maxWidth)
            .clamp(0.1, 0.8);

        return Slidable(
          key: ValueKey(downloadId),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: ratio, // <--- AQUÍ APLICAMOS EL CINTURÓN DE SEGURIDAD
            // Borrado gestual a tope SOLO permitido si está completado o en error y NO en pantalla de detalles
            dismissible: showDelete && !isDetailScreen
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
                _buildSlidableAction(
                  onPressed: (_) async {
                    final mimeType = lookupMimeType(info!.file!) ?? 'video/*';
                    await OpenFilex.open(info!.file!, type: mimeType);
                  },
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  icon: Icons.play_arrow,
                  tooltip: locale.dcActionPlay,
                ),
              ],
              if (showFolder) ...[
                _buildSlidableAction(
                  onPressed: (_) async {
                    String? dir;
                    if (info?.file != null && info!.file!.isNotEmpty) {
                      final filePath = info!.file!;
                      try {
                        if (Directory(filePath).existsSync() &&
                            FileSystemEntity.isDirectorySync(filePath)) {
                          dir = filePath;
                        } else {
                          dir = p.dirname(filePath);
                        }
                      } catch (_) {
                        dir = p.dirname(filePath);
                      }
                    }
                    if (dir != null) {
                      final Uri directoryUri = Uri.file(dir);
                      await launchUrl(
                        directoryUri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  icon: Icons.folder,
                  tooltip: locale.dcActionOpenFolder,
                ),
              ],
              if (showInfo) ...[
                _buildSlidableAction(
                  onPressed: (_) => onTap?.call(), // Va a detalles
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  icon: Icons.info,
                  tooltip: locale.dcActionDetails,
                ),
              ],
              if (showResume) ...[
                _buildSlidableAction(
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
                  tooltip: locale.dcActionResume,
                ),
              ],
              if (showRetry) ...[
                _buildSlidableAction(
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
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  icon: Icons.refresh,
                  tooltip: locale.dcActionRetry,
                ),
              ],
              if (showPause) ...[
                _buildSlidableAction(
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
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  icon: Icons.pause,
                  tooltip: locale.dcActionPause,
                ),
              ],
              if (showCancel) ...[
                _buildSlidableAction(
                  onPressed: (_) => _showCancelDialog(context, downloadId!),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  icon: Icons.cancel,
                  tooltip: locale.dcActionCancel,
                ),
              ],
              if (showDelete) ...[
                _buildSlidableAction(
                  onPressed: (_) async {
                    final result = await context
                        .read<DownloadsController>()
                        .sendAction(downloadId!, 'delete');
                    if (result) {
                      ToastUtils.showInfo(locale.dcDownloadRemoving);
                      if (isDetailScreen && context.mounted) {
                        Navigator.maybePop(context);
                      }
                    } else {
                      ToastUtils.showError(locale.dcDownloadRemovingError);
                    }
                  },
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  icon: Icons.delete,
                  tooltip: locale.dcActionDelete,
                ),
              ],
            ],
          ),
          child: Builder(
            builder: (cardContext) => buildCardWidget(cardContext),
          ),
        );
      },
    );
  }

  Widget _buildSlidableAction({
    required SlidableActionCallback onPressed,
    required Color backgroundColor,
    required Color foregroundColor,
    required IconData icon,
    required String tooltip,
  }) {
    return CustomSlidableAction(
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        child: SizedBox.expand(
          child: Center(child: Icon(icon, color: foregroundColor, size: 20)),
        ),
      ),
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
            style: FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(ctx).extension<VidraSemanticColors>()?.error ??
                  Colors.red,
              foregroundColor:
                  Theme.of(ctx).extension<VidraSemanticColors>()?.onError ??
                  Colors.white,
            ),
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

  // --- IMAGEN (96x54 16:9 con Indicadores Animados) ---
  Widget _buildImage(BuildContext context, bool isError) {
    final imageUrl = info?.image ?? '';
    final duration = info?.duration;

    return SizedBox(
      width: 96,
      height: 54,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 96,
                    height: 54,
                    memCacheWidth: 192,
                    fit: BoxFit.contain,
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
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                color: Colors.black45,
                child: Center(
                  child: Icon(
                    Icons.priority_high,
                    color: Theme.of(context).colorScheme.error,
                    size: 28,
                  ),
                ),
              ),
            ),

          // Duration pill (bottom-right corner of thumbnail)
          if (duration != null && duration.isNotEmpty)
            Positioned(
              bottom: AppSpacing.space4,
              right: AppSpacing.space4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space4,
                  vertical: AppSpacing.space2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  duration,
                  style: AppTypography.telemetryMicro(color: Colors.white),
                ),
              ),
            ),

          // Indicador de Estado Animado (Arriba derecha)
          Positioned(top: 1, right: 1, child: _buildAnimatedStateIcon()),

          // Indicador de Tipo (Abajo izquierda)
          Positioned(
            bottom: 0,
            left: 0,
            child: _buildShadowedIcon(
              _mapTypeIcon(info?.type),
              17,
              _mapTypeIconColor(context, info?.type),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedStateIcon() {
    final iconData = _mapStateIcon(state?.value);
    final semanticColor = state?.subStateColor?.color ?? Colors.white;

    // Animación sutil de oscilación/rebote para descargas en progreso
    if (state?.value == model.DownloadStateEnum.inProgress) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(
              0,
              (value * 2).abs() - 1,
            ), // Efecto oscilatorio suave
            child: child,
          );
        },
        child: _buildShadowedIcon(iconData, 15, semanticColor),
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
    final platform = info?.platform ?? '';
    final infoList = [autor, platform].where((e) => e.isNotEmpty).toList();
    String infoText = infoList.join(' • ');
    final locale = context.read<LocaleController>().localeStrings;
    final textTheme = Theme.of(context).textTheme;
    final semanticColors = Theme.of(context).extension<VidraSemanticColors>();
    final isError = state?.value == model.DownloadStateEnum.failed;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxLabelWidth = (constraints.maxWidth * 0.45).clamp(
          40.0,
          300.0,
        );
        final double maxSpeedWidth = (constraints.maxWidth * 0.35).clamp(
          40.0,
          200.0,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Título
            Text(
              info?.title ?? locale.dcGettingDownloadInfo,
              style: textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Info Autor / Platform
            Text(
              infoText,
              style: textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Progreso y Estados Secundarios
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: _AnimatedProgressBar(
                      value:
                          state?.progressValue ??
                          (state?.value == model.DownloadStateEnum.inProgress
                              ? null
                              : 1.0),
                      color:
                          state?.progressColor?.color ??
                          Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                if (state?.progressLabel != null) ...[
                  const SizedBox(width: AppSpacing.space8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxLabelWidth),
                    child: Text(
                      state!.progressLabel!,
                      style: context.telemetrySmall,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
                if (state?.speed != null) ...[
                  const SizedBox(width: AppSpacing.space8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxSpeedWidth),
                    child: Text(
                      state!.speed!,
                      style: context.speedTelemetry,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ],
            ),
            if (state?.subState != null ||
                state?.value == model.DownloadStateEnum.failed ||
                state?.value ==
                    model.DownloadStateEnum.completedWithErrors) ...[
              Text(
                ((state?.value == model.DownloadStateEnum.failed ||
                            state?.value ==
                                model.DownloadStateEnum.completedWithErrors)
                        ? state?.errorMessage ?? locale.dcUnknownError
                        : state?.subState) ??
                    '',
                style: textTheme.labelSmall?.copyWith(
                  color:
                      state?.subStateColor?.color ??
                      (isError
                          ? (semanticColors?.error ??
                                Theme.of(context).colorScheme.error)
                          : Theme.of(context).colorScheme.primary),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        );
      },
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

  Color _mapTypeIconColor(BuildContext context, model.DownloadType? type) {
    switch (type) {
      case model.DownloadType.video:
        return Theme.of(context).colorScheme.primary;
      case model.DownloadType.list:
        return Theme.of(context).colorScheme.tertiary;
      case model.DownloadType.unknown:
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
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
      duration: AppAnimations.normal,
    );
    _lastValue = widget.value;
    // Nace exactamente en el valor actual, sin animar desde 0
    _animation = Tween<double>(begin: _lastValue ?? 0.0, end: _lastValue ?? 0.0)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: AppAnimations.standardCurve,
          ),
        );
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
            CurvedAnimation(
              parent: _controller,
              curve: AppAnimations.standardCurve,
            ),
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
        minHeight: 3,
        color: widget.color,
        backgroundColor: widget.backgroundColor,
      );
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => LinearProgressIndicator(
        value: _animation.value,
        minHeight: 3,
        color: widget.color,
        backgroundColor: widget.backgroundColor,
      ),
    );
  }
}
