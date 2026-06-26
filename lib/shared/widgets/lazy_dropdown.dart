import 'package:flutter/material.dart';

class LazyDropdown<T> extends StatefulWidget {
  final T? value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;
  final String? label;

  final bool allowCustom;
  final ValueChanged<String>? onCustomSubmit;

  final bool enableSearch;

  const LazyDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
    this.label,
    this.allowCustom = false,
    this.onCustomSubmit,
    this.enableSearch = false,
  });

  @override
  State<LazyDropdown<T>> createState() => _LazyDropdownState<T>();
}

class _LazyDropdownState<T> extends State<LazyDropdown<T>> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    // Pre-llenamos el controlador con la etiqueta actual para evitar desincronizaciones
    _controller = TextEditingController(
      text: widget.value != null ? widget.labelBuilder(widget.value as T) : '',
    );
    _focusNode = FocusNode();

    if (widget.allowCustom) {
      _focusNode.addListener(_onFocusChanged);
    }
  }

  void _onFocusChanged() {
    // Cuando el campo pierde el foco, evaluamos si hay un texto nuevo
    if (!_focusNode.hasFocus && widget.onCustomSubmit != null) {
      final text = _controller.text.trim();
      final knownLabels = widget.items.map(widget.labelBuilder);

      // Solo emitimos si hay texto y no es idéntico a una opción existente
      if (text.isNotEmpty && !knownLabels.contains(text)) {
        widget.onCustomSubmit!(text);
      }
    }
  }

  @override
  void dispose() {
    if (widget.allowCustom) {
      _focusNode.removeListener(_onFocusChanged);
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<T>(
      initialSelection: widget.value,
      controller: widget.allowCustom ? _controller : null,
      focusNode: widget.allowCustom
          ? _focusNode
          : null, // <- Aquí anclamos el nodo
      label: widget.label != null ? Text(widget.label!) : null,
      enableFilter: widget.allowCustom || widget.enableSearch,
      enableSearch: widget.allowCustom || widget.enableSearch,
      requestFocusOnTap: widget.allowCustom || widget.enableSearch,
      dropdownMenuEntries: widget.items
          .map(
            (e) =>
                DropdownMenuEntry<T>(value: e, label: widget.labelBuilder(e)),
          )
          .toList(growable: false),
      onSelected: (T? selection) {
        if (selection != null) {
          widget.onChanged(selection);
        }
      },
    );
  }
}
