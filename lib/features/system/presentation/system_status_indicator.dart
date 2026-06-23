import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'system_details_screen.dart'; // La crearemos en el siguiente paso

class SystemStatusIndicator extends StatelessWidget {
  const SystemStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SystemController>().state;

    Color color;
    IconData icon;
    String label;

    switch (state) {
      case SystemState.ready:
        color = Colors.green;
        icon = Icons.check_circle;
        label = 'Listo';
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
        // Al tocar la pastilla, abrimos el Centro de Mando
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
