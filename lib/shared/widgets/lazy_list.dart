import 'package:flutter/material.dart';

class LazyList extends StatefulWidget {
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;
  final String? label;

  final bool restrictToSuggestions;

  const LazyList({
    super.key,
    required this.value,
    required this.onChanged,
    this.suggestions = const [],
    this.label,
    this.restrictToSuggestions = true,
  });

  @override
  State<LazyList> createState() => _LazyListState();
}

class _LazyListState extends State<LazyList> {
  TextEditingController? _internalCtrl;
  FocusNode? _internalFocus;

  void _addEntry([String? val]) {
    final text = (val ?? _internalCtrl?.text ?? '').trim();
    if (text.isEmpty || widget.value.contains(text)) return;

    if (widget.restrictToSuggestions && !widget.suggestions.contains(text)) {
      _internalCtrl?.clear();
      return;
    }

    final newList = List<String>.from(widget.value)..add(text);
    widget.onChanged(newList);

    _internalCtrl?.clear();
    _internalFocus?.requestFocus();
  }

  void _removeEntry(String item) {
    final newList = List<String>.from(widget.value)..remove(item);
    widget.onChanged(newList);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.value.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.value.map((item) {
              return InputChip(
                label: Text(item),
                onDeleted: () => _removeEntry(item),
                deleteIcon: const Icon(Icons.cancel),
                tooltip: 'Remove',
              );
            }).toList(),
          ),

        if (widget.value.isNotEmpty) const SizedBox(height: 12),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (widget.suggestions.isEmpty) {
                    return const Iterable<String>.empty();
                  }
                  return widget.suggestions.where(
                    (s) =>
                        s.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        ) &&
                        !widget.value.contains(s),
                  );
                },
                // Cuando se selecciona desde la lista (click o enter en modo estricto)
                onSelected: (String selection) => _addEntry(selection),

                // AQUÍ ESTÁ EL CAMBIO MAESTRO
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  _internalCtrl = controller;
                  _internalFocus = focusNode;

                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: widget.label ?? 'Añadir elemento',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (String value) {
                      if (widget.restrictToSuggestions) {
                        // 1. Modo Estricto: Le decimos al Autocomplete que seleccione la opción resaltada.
                        // Esto disparará 'onSelected' automáticamente si hay una coincidencia válida.
                        onFieldSubmitted();

                        // Si después de eso el texto sigue ahí, significa que el usuario
                        // presionó Enter pero lo que escribió no coincidía con nada de la lista. Lo limpiamos.
                        if (controller.text.isNotEmpty &&
                            !widget.suggestions.contains(controller.text)) {
                          controller.clear();
                        }
                      } else {
                        // 2. Modo Libre: Ignoramos la sugerencia resaltada y añadimos exactamente
                        // el texto parcial o símbolo que el usuario decidió escribir.
                        _addEntry(value);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle),
              color: Theme.of(context).colorScheme.primary,
              iconSize: 32,
              onPressed: () =>
                  _addEntry(), // Mantiene el comportamiento manual si tocan el "+"
              tooltip: 'Add',
            ),
          ],
        ),
      ],
    );
  }
}
