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
  List<String>? _cachedLowerLabels;
  Set<String>? _cachedKnownLabels;
  Map<T, String>? _cachedLabelMap;
  int? _lastItemsLength;
  Widget? _cachedDropdownMenu;

  String? _lastFilterQuery;
  List<DropdownMenuEntry<T>>? _lastFilteredEntries;

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
    _cachedDropdownMenu = _buildDropdownMenu();
  }

  String _getLabelForValue(T? val) {
    if (val == null) return '';
    return _cachedLabelMap?[val] ?? widget.labelBuilder(val);
  }

  void _rebuildCache({T? probedItem, String? probedLabel}) {
    final items = widget.items;
    final count = items.length;
    final knownLabels = widget.allowCustom ? <String>{} : null;
    final labelMap = <T, String>{};
    final lowerLabels = List<String>.filled(count, '', growable: false);

    final entries = List<DropdownMenuEntry<T>>.generate(count, (i) {
      final item = items[i];
      final String label =
          (probedItem != null && item == probedItem && probedLabel != null)
              ? probedLabel
              : widget.labelBuilder(item);
      if (knownLabels != null) {
        knownLabels.add(label);
      }
      labelMap[item] = label;
      lowerLabels[i] = label.toLowerCase();
      return DropdownMenuEntry<T>(value: item, label: label);
    }, growable: false);

    _cachedEntries = entries;
    _cachedLowerLabels = lowerLabels;
    _cachedKnownLabels = knownLabels;
    _cachedLabelMap = labelMap;
    _lastItemsLength = count;
    _lastFilterQuery = null;
    _lastFilteredEntries = null;
  }

  bool _shouldInvalidateCache(LazyDropdown<T> oldWidget) {
    // Fast O(1) identity check
    if (identical(oldWidget.items, widget.items) &&
        identical(oldWidget.labelBuilder, widget.labelBuilder) &&
        oldWidget.label == widget.label) {
      return false;
    }

    _probedItem = null;
    _probedLabel = null;

    if (_cachedEntries == null ||
        _cachedLabelMap == null ||
        _cachedLowerLabels == null) {
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
    if (!identical(oldWidget.labelBuilder, widget.labelBuilder) ||
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

    final bool invalidated = _shouldInvalidateCache(oldWidget);
    if (invalidated) {
      _rebuildCache(probedItem: _probedItem, probedLabel: _probedLabel);
    }

    final bool valueChanged = widget.value != oldWidget.value;
    final bool configChanged = widget.label != oldWidget.label ||
        widget.allowCustom != oldWidget.allowCustom ||
        widget.enableSearch != oldWidget.enableSearch;

    // When cache is not invalidated and value hasn't changed, avoid resetting controller text
    if (invalidated || valueChanged) {
      final expectedLabel = _getLabelForValue(widget.value);
      if (_controller.text != expectedLabel) {
        if (!widget.allowCustom || !_focusNode.hasFocus) {
          _controller.text = expectedLabel;
        }
      }
    }

    // Update focus listener if allowCustom changed
    if (widget.allowCustom != oldWidget.allowCustom) {
      if (widget.allowCustom) {
        _focusNode.addListener(_onFocusChanged);
      } else {
        _focusNode.removeListener(_onFocusChanged);
      }
    }

    if (invalidated || valueChanged || configChanged || _cachedDropdownMenu == null) {
      _cachedDropdownMenu = _buildDropdownMenu();
    }
  }

  void _onFocusChanged() {
    // When focus is lost, evaluate whether there is a new custom text
    if (!_focusNode.hasFocus && widget.onCustomSubmit != null) {
      final text = _controller.text.trim();
      if (text.isEmpty) return;

      _cachedKnownLabels ??= _cachedEntries?.map((e) => e.label).toSet() ??
          widget.items.map(widget.labelBuilder).toSet();

      final isKnown = _cachedKnownLabels!.contains(text);

      if (!isKnown) {
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

  static const int _maxFilterResults = 50;

  List<DropdownMenuEntry<T>> _filterCallback(
    List<DropdownMenuEntry<T>> entries,
    String filter,
  ) {
    final query = filter.trim().toLowerCase();
    if (query.isEmpty) {
      _lastFilterQuery = '';
      _lastFilteredEntries = _cachedEntries;
      return _cachedEntries!;
    }

    if (query == _lastFilterQuery && _lastFilteredEntries != null) {
      return _lastFilteredEntries!;
    }

    final lower = _cachedLowerLabels;
    final allEntries = _cachedEntries;
    if (lower == null || allEntries == null) {
      return entries;
    }

    final total = allEntries.length;
    final result = <DropdownMenuEntry<T>>[];

    for (var i = 0; i < total; i++) {
      if (lower[i].contains(query)) {
        result.add(allEntries[i]);
        if (result.length >= _maxFilterResults) {
          break;
        }
      }
    }

    _lastFilterQuery = query;
    _lastFilteredEntries = result;
    return result;
  }

  int? _searchCallback(List<DropdownMenuEntry<T>> entries, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || entries.isEmpty) {
      return null;
    }

    final lowerQuery = trimmed.toLowerCase();

    // Fast path: use pre-computed lowercase labels when querying master cached entries
    if (identical(entries, _cachedEntries) &&
        _cachedLowerLabels != null &&
        _cachedLowerLabels!.length == entries.length) {
      final lowerLabels = _cachedLowerLabels!;
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].enabled && lowerLabels[i].contains(lowerQuery)) {
          return i;
        }
      }
      return null;
    }

    // Fallback path: search entries directly (e.g. filtered subset or dynamic entries)
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.enabled && entry.label.toLowerCase().contains(lowerQuery)) {
        return i;
      }
    }

    return null;
  }

  Widget _buildDropdownMenu() {
    final bool isSearchOrCustom = widget.allowCustom || widget.enableSearch;

    return DropdownMenu<T>(
      initialSelection: widget.value,
      controller: _controller,
      focusNode: widget.allowCustom ? _focusNode : null,
      label: widget.label != null ? Text(widget.label!) : null,
      enableFilter: isSearchOrCustom,
      enableSearch: isSearchOrCustom,
      requestFocusOnTap: isSearchOrCustom,
      dropdownMenuEntries: _cachedEntries!,
      filterCallback: isSearchOrCustom ? _filterCallback : null,
      searchCallback: isSearchOrCustom ? _searchCallback : null,
      onSelected: (T? selection) {
        if (selection != null) {
          widget.onChanged(selection);
          _controller.text = _getLabelForValue(selection);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedEntries == null) {
      _rebuildCache();
    }
    _cachedDropdownMenu ??= _buildDropdownMenu();

    return _cachedDropdownMenu!;
  }
}
