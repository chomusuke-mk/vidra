import 'package:flutter/material.dart';

/// ponytail: Eliminado el "Text Mode" (JSON parser). Si necesitas editar JSON, usa un TextField.
/// Se reemplazaron las tarjetas verticales gigantes por un Wrap de InputChips para la visualización.
/// Se usa DropdownMenu nativo con expandedInsets para resolver el Autocomplete de claves gratis.
class LazyMap extends StatefulWidget {
  final Map<String, String> value;
  final ValueChanged<Map<String, String>> onChanged;

  // Si se proveen, la clave se convierte en un DropdownMenu filtrable (Autocomplete)
  final List<String> keySuggestions;

  const LazyMap({
    super.key,
    required this.value,
    required this.onChanged,
    this.keySuggestions = const [],
  });

  @override
  State<LazyMap> createState() => _LazyMapState();
}

class _LazyMapState extends State<LazyMap> {
  final _keyCtrl = TextEditingController();
  final _valCtrl = TextEditingController();
  final _valFocus = FocusNode();

  void _addEntry() {
    final k = _keyCtrl.text.trim();
    final v = _valCtrl.text.trim();
    if (k.isEmpty || v.isEmpty) return;

    // Mutamos sobre una copia para mantener el estado inmutable
    final newMap = Map<String, String>.from(widget.value)..[k] = v;
    widget.onChanged(newMap);

    _keyCtrl.clear();
    _valCtrl.clear();
    _valFocus.unfocus();
  }

  void _removeEntry(String key) {
    final newMap = Map<String, String>.from(widget.value)..remove(key);
    widget.onChanged(newMap);
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valCtrl.dispose();
    _valFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Visualización de elementos existentes (Chips)
        if (widget.value.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.value.entries.map((e) {
              return InputChip(
                label: Text('${e.key}: ${e.value}'),
                onDeleted: () => _removeEntry(e.key),
                deleteIcon: const Icon(Icons.cancel),
                tooltip: 'Remove',
              );
            }).toList(),
          ),

        if (widget.value.isNotEmpty) const SizedBox(height: 12),

        // 2. Formulario de inserción en una sola línea
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: widget.keySuggestions.isEmpty
                  ? TextField(
                      controller: _keyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Key',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) =>
                          _valFocus.requestFocus(), // Pasa el foco al valor
                    )
                  : DropdownMenu<String>(
                      controller: _keyCtrl,
                      label: const Text('Key'),
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      expandedInsets: EdgeInsets
                          .zero, // Magia: Fuerza al menú a ocupar el Expanded
                      dropdownMenuEntries: widget.keySuggestions
                          .map((k) => DropdownMenuEntry(value: k, label: k))
                          .toList(growable: false),
                      onSelected: (_) => _valFocus.requestFocus(),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _valCtrl,
                focusNode: _valFocus,
                decoration: const InputDecoration(
                  labelText: 'Value',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) =>
                    _addEntry(), // Enter añade la entrada directamente
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle),
              color: Theme.of(context).colorScheme.primary,
              iconSize: 32,
              onPressed: _addEntry,
              tooltip: 'Add entry',
            ),
          ],
        ),
      ],
    );
  }
}
