import 'package:flutter/material.dart';

enum ControllerType { switchCtrl, dropdown, text, complex }

class SettingRow extends StatelessWidget {
  final String title;
  final String? description;
  final ControllerType type;
  final Widget child;

  const SettingRow({
    super.key,
    required this.title,
    this.description,
    required this.type,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool stackVertically = false;
        double requiredWidth = 0;

        // Regla 1: Horizontal mínimo requerido de menor a mayor
        switch (type) {
          case ControllerType.switchCtrl:
            requiredWidth = 60;
            break;
          case ControllerType.dropdown:
            requiredWidth = 180;
            break;
          case ControllerType.text:
            requiredWidth = 250;
            break;
          case ControllerType.complex:
            stackVertically = true; // Regla 2: Los demás siempre van debajo
            break;
        }

        // Dejamos un espacio "seguro" de 150px para leer cómodamente el título
        if (!stackVertically && constraints.maxWidth < (150 + requiredWidth)) {
          stackVertically = true;
        }

        // Título y Descripción
        final textSection = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(
                description!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ],
        );

        // Ajustamos el tamaño del controlador para que no crezca al infinito a la derecha
        Widget controllerWidget = child;
        if (type == ControllerType.dropdown) {
          controllerWidget = SizedBox(width: 180, child: child);
        } else if (type == ControllerType.text) {
          controllerWidget = SizedBox(width: 250, child: child);
        }

        // Regla 3: Si va debajo alineado a la izquierda. Si está a la derecha, pegado a la derecha.
        final alignedChild = Align(
          alignment: stackVertically
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: controllerWidget,
        );

        if (stackVertically) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [textSection, const SizedBox(height: 12), alignedChild],
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: textSection),
                const SizedBox(width: 16),
                alignedChild,
              ],
            ),
          );
        }
      },
    );
  }
}
