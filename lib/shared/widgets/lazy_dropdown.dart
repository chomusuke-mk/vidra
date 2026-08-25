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

  // Memoized cache structures
  List<DropdownMenuEntry<T>>? _cachedEntries;
  Set<String>? _cachedKnownLabels;
  Map<T, String>? _cachedLabelMap;
  int? _lastItemsLength;

  T? _probedItem;
  String? _probedLabel;

  @override
  void initState() {
    super.initState();
    _rebuildCache();
    _controller = TextEditingController(
      text: _getLabelForValue(widget.value),
    );
    _focusNode = FocusNode();

    if (widget.allowCustom) {
      _focusNode.addListener(_onFocusChanged);
    }
  }

  String _getLabelForValue(T? val) {
    if (val == null) return '';
    return _cachedLabelMap?[val] ?? widget.labelBuilder(val);
  }

  void _rebuildCache({T? probedItem, String? probedLabel}) {
    final entries = <DropdownMenuEntry<T>>[];
    final knownLabels = <String>{};
    final labelMap = <T, String>{};

    for (final item in widget.items) {
      final String label;
      if (probedItem != null && item == probedItem && probedLabel != null) {
        label = probedLabel;
      } else {
        label = widget.labelBuilder(item);
      }
      entries.add(DropdownMenuEntry<T>(value: item, label: label));
      knownLabels.add(label);
      labelMap[item] = label;
    }

    _cachedEntries = List<DropdownMenuEntry<T>>.unmodifiable(entries);
    _cachedKnownLabels = Set<String>.unmodifiable(knownLabels);
    _cachedLabelMap = labelMap;
    _lastItemsLength = widget.items.length;
  }

  bool _shouldInvalidateCache(LazyDropdown<T> oldWidget) {
    _probedItem = null;
    _probedLabel = null;

    if (_cachedEntries == null ||
        _cachedKnownLabels == null ||
        _cachedLabelMap == null) {
      return true;
    }

    // 1. Check if items list structure changed
    if (!identical(oldWidget.items, widget.items)) {
      if (oldWidget.items.length != widget.items.length) return true;
      for (var i = 0; i < widget.items.length; i++) {
        if (oldWidget.items[i] != widget.items[i]) return true;
      }
    } else {
      if (widget.items.length != _lastItemsLength) return true;
    }

    // 2. Check if labelBuilder produces different output (e.g. locale/translation change)
    if (oldWidget.labelBuilder != widget.labelBuilder ||
        oldWidget.label != widget.label) {
      if (widget.value != null &&
          (_cachedLabelMap?.containsKey(widget.value) ?? false)) {
        final sample = widget.labelBuilder(widget.value as T);
        if (sample != _cachedLabelMap![widget.value]) {
          _probedItem = widget.value as T;
          _probedLabel = sample;
          return true;
        }
      } else if (widget.items.isNotEmpty) {
        final firstItem = widget.items.first;
        final sample = widget.labelBuilder(firstItem);
        if (sample != _cachedLabelMap?[firstItem]) {
          _probedItem = firstItem;
          _probedLabel = sample;
          return true;
        }
      }
    }

    return false;
  }

  @override
  void didUpdateWidget(LazyDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_shouldInvalidateCache(oldWidget)) {
      _rebuildCache(probedItem: _probedItem, probedLabel: _probedLabel);
    }

    // Cuando el widget se reconstruye (carga diferida de locales o cambio de idioma),
    // calculamos cuál debería ser el texto correcto en este momento desde la caché.
    final expectedLabel = _getLabelForValue(widget.value);

    // Si el texto que muestra el controlador es diferente al nuevo texto traducido...
    if (_controller.text != expectedLabel) {
      // Validamos para no interrumpir al usuario si está escribiendo una opción personalizada
      if (!widget.allowCustom || !_focusNode.hasFocus) {
        _controller.text =
            expectedLabel; // ¡Forzamos la actualización visual del label!
      }
    }

    // Actualizamos el listener en caso de que la propiedad allowCustom cambie en tiempo real
    if (widget.allowCustom != oldWidget.allowCustom) {
      if (widget.allowCustom) {
        _focusNode.addListener(_onFocusChanged);
      } else {
        _focusNode.removeListener(_onFocusChanged);
      }
    }
  }

  void _onFocusChanged() {
    // Cuando el campo pierde el foco, evaluamos si hay un texto nuevo
    if (!_focusNode.hasFocus && widget.onCustomSubmit != null) {
      final text = _controller.text.trim();
      final isKnown = _cachedKnownLabels?.contains(text) ??
          widget.items.map(widget.labelBuilder).contains(text);

      // Solo emitimos si hay texto y no es idéntico a una opción existente
      if (text.isNotEmpty && !isKnown) {
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
    if (_cachedEntries == null) {
      _rebuildCache();
    }

    return DropdownMenu<T>(
      initialSelection: widget.value,
      controller: _controller,
      focusNode: widget.allowCustom
          ? _focusNode
          : null, // <- Aquí anclamos el nodo
      label: widget.label != null ? Text(widget.label!) : null,
      enableFilter: widget.allowCustom || widget.enableSearch,
      enableSearch: widget.allowCustom || widget.enableSearch,
      requestFocusOnTap: widget.allowCustom || widget.enableSearch,
      dropdownMenuEntries: _cachedEntries!,
      onSelected: (T? selection) {
        if (selection != null) {
          widget.onChanged(selection);
          _controller.text = _getLabelForValue(selection);
        }
      },
    );
  }
}
