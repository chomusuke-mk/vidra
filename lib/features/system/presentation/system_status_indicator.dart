import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/system/presentation/widgets/system_status_update_bubble.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'package:vidra/shared/utils/tutorial_utils.dart';
import 'system_details_screen.dart';

class SystemStatusIndicator extends StatefulWidget {
  const SystemStatusIndicator({super.key});

  @override
  State<SystemStatusIndicator> createState() => _SystemStatusIndicatorState();
}

class _SystemStatusIndicatorState extends State<SystemStatusIndicator> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowUpdateBubble();
    });
  }

  void _checkAndShowUpdateBubble() {
    if (!mounted) return;
    final updateCtrl = context.read<UpdateController>();
    if (updateCtrl.hasAvailableUpdates &&
        !updateCtrl.hasShownSessionUpdateBubble) {
      updateCtrl.markSessionUpdateBubbleShown();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          SystemStatusUpdateBubble.show(
            context,
            AppTutorialKeys.mainSystemStatus,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SystemController>().state;
    final updateCtrl = context.watch<UpdateController>();
    final locale = context.watch<LocaleController>().localeStrings;

    if (updateCtrl.hasAvailableUpdates &&
        !updateCtrl.hasShownSessionUpdateBubble) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowUpdateBubble();
      });
    }

    Color color;
    IconData icon;
    String label;

    switch (state) {
      case SystemState.ready:
        // Si hay actualizaciones listas para descargar/instalar
        if (updateCtrl.hasAvailableUpdates) {
          color = Colors.blue;
          icon = Icons.system_update;
          label = locale.ssiUpdateAvailable;
        }
        // Si han pasado las horas límite o está buscando en segundo plano
        else if (updateCtrl.isCheckingUpdates || updateCtrl.hasPendingChecks) {
          color = Colors.blueGrey;
          icon = Icons.sync;
          label = locale.ssiSearchingUpdates;
        }
        // Completamente al día
        else {
          color = Colors.green;
          icon = Icons.check_circle;
          label = locale.ssiReady;
        }
        break;
      case SystemState.missingPermissions:
      case SystemState.missingResources:
      case SystemState.fatalError:
        color = Colors.red;
        icon = Icons.warning_rounded;
        label = locale.ssiAttention;
        break;
      case SystemState.initializing:
      case SystemState.startingBackend:
        color = Colors.blue;
        icon = Icons.hourglass_top;
        label = locale.ssiInitializing;
        break;
      case SystemState.retrying:
        color = Colors.orange;
        icon = Icons.sync_problem;
        label = locale.ssiReconnecting;
        break;
    }

    return IconButton(
      tooltip: label,
      icon: Icon(icon, color: color, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        // Se reduce el padding y el tamaño mínimo para optimizar el espacio horizontal
        padding: const EdgeInsets.all(8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () {
        SystemStatusUpdateBubble.hide();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const SystemDetailsScreen(),
        );
      },
    );
  }
}

