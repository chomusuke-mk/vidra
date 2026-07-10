import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'system_details_screen.dart';

class SystemStatusIndicator extends StatelessWidget {
  const SystemStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SystemController>().state;
    final updateCtrl = context.watch<UpdateController>();

    Color color;
    IconData icon;
    String label;

    switch (state) {
      case SystemState.ready:
        // Si hay actualizaciones listas para descargar/instalar
        if (updateCtrl.hasAvailableUpdates) {
          color = Colors.blue;
          icon = Icons.system_update;
          label = 'Actualización';
        }
        // Si han pasado las horas límite o está buscando en segundo plano
        else if (updateCtrl.isCheckingUpdates || updateCtrl.hasPendingChecks) {
          color = Colors.blueGrey;
          icon = Icons.sync;
          label = 'Buscando updates';
        }
        // Completamente al día
        else {
          color = Colors.green;
          icon = Icons.check_circle;
          label = 'Listo';
        }
        break;
      case SystemState.missingPermissions:
      case SystemState.missingResources:
      case SystemState.fatalError:
        color = Colors.red;
        icon = Icons.warning_rounded;
        label = 'Atención';
        break;
      case SystemState.initializing:
      case SystemState.startingBackend:
        color = Colors.blue;
        icon = Icons.hourglass_top;
        label = 'Iniciando';
        break;
      case SystemState.retrying:
        color = Colors.orange;
        icon = Icons.sync_problem;
        label = 'Reconectando';
        break;
    }

    return ActionChip(
      avatar: Icon(icon, color: color, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
      backgroundColor: color.withValues(alpha: 0.1),
      onPressed: () {
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
