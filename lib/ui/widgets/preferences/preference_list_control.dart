import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/constants/layout_breakpoints.dart';
import 'package:vidra/data/preferences/preference_options.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/models/preference.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/ui/models/preference_ui_models.dart';

class PreferenceListControl extends StatefulWidget {
  const PreferenceListControl({
    super.key,
    required this.preference,
    this.options,
    this.allowCustomCategories = false,
    this.allowSelection = false,
    this.joinDelimiter = ',',
    this.allowTextEditing = true,
    this.isCompact = false,
  });

  final Preference preference;
  final List<String>? options;
  final bool allowCustomCategories;
  final bool allowSelection;
  final String joinDelimiter;
  final bool allowTextEditing;
  final bool isCompact;

  @override
  State<PreferenceListControl> createState() => PreferenceListControlState();
}

class PreferenceListControlState extends State<PreferenceListControl> {
  late final TextEditingController _textController;
  late final TextEditingController _customController;
  late final FocusNode _textFocusNode;
  late final FocusNode _customFocusNode;
  late final Set<String> _customEntries;
  late final ValueNotifier<PreferenceInputMode> _modeNotifier;
  String _lastSyncedText = '';
  List<String> _lastAutocompleteOptions = const <String>[];
  Set<String>? _pendingSelection;
  List<String> _selectionCache = const <String>[];
  bool _selectionCacheValid = false;
  int _autocompleteVersion = 0;

  Preference get preference => widget.preference;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _customController = TextEditingController();
    _textFocusNode = FocusNode();
    _customFocusNode = FocusNode();
    _customEntries = <String>{};
    _modeNotifier = ValueNotifier<PreferenceInputMode>(_initialMode());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTextController();
  }

  @override
  void dispose() {
    _textController.dispose();
    _customController.dispose();
    _textFocusNode.dispose();
    _customFocusNode.dispose();
    _modeNotifier.dispose();
    super.dispose();
  }

  PreferenceInputMode _initialMode() {
    final value = preference.get('value');
    if (value is List) {
      return PreferenceInputMode.list;
    }
    if (canUseTextMode) {
      return PreferenceInputMode.text;
    }
    return PreferenceInputMode.list;
  }

  ValueNotifier<PreferenceInputMode> get modeListenable => _modeNotifier;
  PreferenceInputMode get mode => _modeNotifier.value;

  bool get canUseTextMode =>
      widget.allowCustomCategories && widget.allowTextEditing;

  void _setMode(PreferenceInputMode mode) {
    if (!canUseTextMode && mode == PreferenceInputMode.text) {
      return;
    }
    if (_modeNotifier.value == mode) {
      return;
    }
    _modeNotifier.value = mode;
    setState(() {});
  }

  void toggleMode() {
    if (!canUseTextMode) {
      return;
    }
    _setMode(
      mode == PreferenceInputMode.text
          ? PreferenceInputMode.list
          : PreferenceInputMode.text,
    );
  }

  List<String> get _baseOptions {
    final options = widget.options ?? autocompleteOptions[preference.key];
    return options == null
        ? const <String>[]
        : List<String>.unmodifiable(options);
  }

  Set<String> get _baseSet => _baseOptions.toSet();

  List<String> _currentListValue() {
    final value = preference.get('value');
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    if (value is String && value.isNotEmpty) {
      final delimiter = widget.joinDelimiter.isEmpty
          ? ','
          : widget.joinDelimiter;
      return value
          .split(delimiter)
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  void _syncTextController() {
    final joined = _joinValues(_currentListValue());
    if (_lastSyncedText == joined) {
      return;
    }
    _lastSyncedText = joined;
    if (_textController.text != joined) {
      _textController
        ..text = joined
        ..selection = TextSelection.fromPosition(
          TextPosition(offset: joined.length),
        );
    }
  }

  String _joinValues(List<String> values) {
    final delimiter = widget.joinDelimiter.isEmpty ? ',' : widget.joinDelimiter;
    return values.join(delimiter);
  }

  List<String> _normalizeSelection() {
    final raw = _currentListValue();
    if (widget.allowCustomCategories) {
      return raw;
    }
    final filtered = raw.where(_baseSet.contains).toList(growable: false);
    if (raw.length != filtered.length) {
      _updatePreference(filtered);
    }
    _customEntries.removeWhere((entry) => !filtered.contains(entry));
    if (!canUseTextMode && mode == PreferenceInputMode.text) {
      _setMode(PreferenceInputMode.list);
    }
    _selectionCache = filtered;
    _selectionCacheValid = true;
    return filtered;
  }

  @visibleForTesting
  List<String> debugLastAutocompleteOptions() =>
      List<String>.unmodifiable(_lastAutocompleteOptions);
  Future<void> _updatePreference(Object value) async {
    final model = context.read<PreferencesModel>();
    await model.setPreferenceValue(preference, value);
  }

  Future<void> _applySelection(Set<String> values) async {
    final allowed = widget.allowCustomCategories
        ? values
        : values.where(_baseSet.contains).toSet();
    final current = _currentListValue();
    final remaining = Set<String>.from(allowed);
    final ordered = <String>[];
    for (final value in current) {
      if (remaining.remove(value)) {
        ordered.add(value);
      }
    }
    ordered.addAll(remaining);

    if (mounted) {
      setState(() {
        if (widget.allowCustomCategories) {
          final customValues = ordered.where(
            (value) => !_baseSet.contains(value),
          );
          if (widget.allowSelection) {
            _customEntries.addAll(customValues);
          } else {
            _customEntries
              ..clear()
              ..addAll(customValues);
          }
        } else {
          _customEntries.removeWhere((value) => !ordered.contains(value));
        }
        _pendingSelection = Set<String>.from(ordered);
        _syncTextControllerWithValues(ordered);
      });
    } else {
      if (widget.allowCustomCategories) {
        final customValues = ordered.where(
          (value) => !_baseSet.contains(value),
        );
        if (widget.allowSelection) {
          _customEntries.addAll(customValues);
        } else {
          _customEntries
            ..clear()
            ..addAll(customValues);
        }
      } else {
        _customEntries.removeWhere((value) => !ordered.contains(value));
      }
      _pendingSelection = Set<String>.from(ordered);
      _syncTextControllerWithValues(ordered);
    }

    _selectionCache = List<String>.unmodifiable(ordered);
    _selectionCacheValid = true;

    await _updatePreference(ordered);
    if (!mounted) {
      return;
    }

    if (!widget.allowSelection) {
      final suggestions =
          widget.options ??
          autocompleteOptions[preference.key] ??
          const <String>[];
      final filtered = suggestions
          .where((option) => !allowed.contains(option))
          .toList(growable: false);
      setState(() {
        _pendingSelection = null;
        _lastAutocompleteOptions = suggestions.isEmpty
            ? const <String>[]
            : List<String>.unmodifiable(filtered);
        _autocompleteVersion++;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final currentValue = _customController.value;
        final toggledSelection = TextSelection.collapsed(
          offset: currentValue.selection.baseOffset,
          affinity: currentValue.selection.affinity == TextAffinity.downstream
              ? TextAffinity.upstream
              : TextAffinity.downstream,
        );
        _customController.value = currentValue.copyWith(
          selection: toggledSelection,
        );
        _customController.value = currentValue;
      });
    } else {
      setState(() {
        _pendingSelection = null;
      });
    }
  }

  void _syncTextControllerWithValues(List<String> values) {
    final joined = _joinValues(values);
    _lastSyncedText = joined;
    if (_textController.text != joined) {
      _textController
        ..text = joined
        ..selection = TextSelection.fromPosition(
          TextPosition(offset: joined.length),
        );
    }
  }

  Set<String> _activeSelection() {
    final pending = _pendingSelection;
    if (pending != null) {
      return Set<String>.from(pending);
    }
    if (_selectionCacheValid) {
      return _selectionCache.toSet();
    }
    final current = _normalizeSelection();
    return current.toSet();
  }

  Iterable<String> _customOptions(Set<String> selection) {
    return ({
      ..._customEntries,
      ...selection.where((value) => !_baseSet.contains(value)),
    }..removeWhere(_baseSet.contains));
  }

  Future<void> _handleTextSubmit() async {
    final trimmed = _textController.text.trim();
    if (trimmed.isEmpty) {
      await _updatePreference(<String>[]);
      if (!widget.allowCustomCategories) {
        _customEntries.clear();
      }
      return;
    }
    final delimiter = widget.joinDelimiter.isEmpty ? ',' : widget.joinDelimiter;
    final segments = trimmed
        .split(delimiter)
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (segments.isEmpty) {
      await _updatePreference(<String>[]);
      if (!widget.allowCustomCategories) {
        _customEntries.clear();
      }
      return;
    }

    final filtered = widget.allowCustomCategories
        ? segments
        : segments.where(_baseSet.contains).toList(growable: false);

    if (widget.allowCustomCategories) {
      final custom = filtered
          .where((value) => !_baseSet.contains(value))
          .toSet();
      if (custom.isNotEmpty) {
        _customEntries.addAll(custom);
      }
    } else {
      _customEntries.removeWhere((value) => !filtered.contains(value));
    }

    await _updatePreference(filtered);
  }

  Future<void> _addCategory([String? explicitValue]) async {
    final hasSuggestions = _baseOptions.isNotEmpty;
    if (!widget.allowCustomCategories &&
        !widget.allowSelection &&
        !hasSuggestions) {
      return;
    }
    final raw = (explicitValue ?? _customController.text).trim();
    if (raw.isEmpty) {
      return;
    }
    final lower = raw.toLowerCase();
    String candidate = raw;
    for (final option in _baseOptions) {
      if (option.toLowerCase() == lower) {
        candidate = option;
        break;
      }
    }
    if (!widget.allowCustomCategories && !_baseSet.contains(candidate)) {
      _customController.clear();
      return;
    }
    final selection = _activeSelection();
    if (selection.contains(candidate)) {
      _customController.clear();
      return;
    }
    if (widget.allowCustomCategories && !_baseSet.contains(candidate)) {
      final existing = _customEntries.firstWhere(
        (entry) => entry.toLowerCase() == candidate.toLowerCase(),
        orElse: () => candidate,
      );
      candidate = existing;
      _customEntries.add(candidate);
    }
    selection.add(candidate);
    _customController.clear();
    await _applySelection(selection);
    if (widget.allowSelection || widget.allowCustomCategories) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _customFocusNode.requestFocus();
      });
    }
  }

  void _removeCategory(String category) {
    final selection = _activeSelection();
    final wasSelected = selection.remove(category);
    final isCustom = !_baseSet.contains(category);

    if (isCustom && _customEntries.remove(category)) {
      setState(() {});
    }

    if (!wasSelected) {
      return;
    }

    _applySelection(selection);
  }

  void _toggleCategory(String category, bool selected) {
    if (!widget.allowSelection) {
      return;
    }
    final selection = _activeSelection();
    if (selected) {
      selection.add(category);
    } else {
      selection.remove(category);
    }
    _applySelection(selection);
  }

  List<String> _orderedChips(Set<String> selection) {
    final chipCategories = <String>[];
    if (widget.allowSelection) {
      chipCategories.addAll(_baseOptions);
      chipCategories.addAll(_customOptions(selection));
    } else {
      chipCategories.addAll(selection);
    }
    final seen = <String>{};
    final ordered = <String>[];
    for (final category in chipCategories) {
      if (seen.add(category)) {
        ordered.add(category);
      }
    }
    return ordered;
  }

  Widget _buildTextEditor() {
    final localizations = VidraLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: LayoutBreakpoints.listTextEditorMaxWidth,
      ),
      child: TextField(
        key: ValueKey('control_${preference.key}_text'),
        controller: _textController,
        focusNode: _textFocusNode,
        minLines: 3,
        maxLines: 8,
        decoration: InputDecoration(
          hintText: localizations.ui(AppStringKey.customValue),
        ),
        onSubmitted: (_) => _handleTextSubmit(),
        onEditingComplete: _handleTextSubmit,
        onTapOutside: (_) => _handleTextSubmit(),
      ),
    );
  }

  Widget _buildCustomInput(
    Set<String> selection, {
    bool compact = false,
  }) {
    final localizations = VidraLocalizations.of(context);
    InputDecoration decoration() => InputDecoration(
      hintText: localizations.ui(AppStringKey.customValue),
      isDense: compact,
      contentPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
          : null,
    );

    Widget buildPlainField() {
      _lastAutocompleteOptions = const <String>[];
      return TextField(
        key: ValueKey('${preference.key}_custom_input'),
        controller: _customController,
        focusNode: _customFocusNode,
        decoration: decoration(),
        textAlignVertical: compact ? TextAlignVertical.center : null,
        onSubmitted: (_) async {
          await _addCategory();
        },
      );
    }

    Widget buildAutocompleteField() {
      final suggestions =
          widget.options ??
          autocompleteOptions[preference.key] ??
          const <String>[];
      return RawAutocomplete<String>(
        key: ValueKey(
          '${preference.key}_custom_autocomplete_$_autocompleteVersion',
        ),
        textEditingController: _customController,
        focusNode: _customFocusNode,
        optionsBuilder: (textEditingValue) {
          final currentSelection = _activeSelection();
          final query = textEditingValue.text.trim().toLowerCase();
          final filtered = suggestions
              .where((option) {
                if (currentSelection.contains(option)) {
                  return false;
                }
                if (query.isEmpty) {
                  return true;
                }
                return option.toLowerCase().contains(query);
              })
              .toList(growable: false);
          _lastAutocompleteOptions = List<String>.unmodifiable(filtered);
          return filtered;
        },
        displayStringForOption: (option) => option,
        optionsViewBuilder: (context, onSelected, options) {
          if (options.isEmpty) {
            return const SizedBox.shrink();
          }
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: LayoutBreakpoints.listAutocompleteMaxHeight,
                  maxWidth: LayoutBreakpoints.listAutocompleteMaxWidth,
                ),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final option in options)
                      ListTile(
                        key: ValueKey(
                          '${preference.key}_autocomplete_option_$option',
                        ),
                        title: Text(option),
                        onTap: () => onSelected(option),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            key: ValueKey('${preference.key}_custom_input'),
            controller: controller,
            focusNode: focusNode,
            decoration: decoration(),
            textAlignVertical: compact ? TextAlignVertical.center : null,
            onSubmitted: (_) async {
              onFieldSubmitted();
              await _addCategory();
            },
          );
        },
        onSelected: (selection) async {
          await _addCategory(selection);
        },
      );
    }

    final suggestionPool =
        widget.options ??
        autocompleteOptions[preference.key] ??
        const <String>[];
    final useAutocomplete = !widget.allowSelection && suggestionPool.isNotEmpty;
    final field = useAutocomplete
        ? buildAutocompleteField()
        : buildPlainField();

    final Widget addButton = compact
        ? IconButton(
            key: ValueKey('${preference.key}_custom_add'),
            icon: const Icon(Icons.add, size: 20),
            tooltip: localizations.ui(AppStringKey.addEntry),
            onPressed: () async {
              await _addCategory();
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          )
        : IconButton(
            key: ValueKey('${preference.key}_custom_add'),
            icon: const Icon(Icons.add),
            tooltip: localizations.ui(AppStringKey.addEntry),
            onPressed: () async {
              await _addCategory();
            },
          );

    if (compact) {
      final compactField = ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: LayoutBreakpoints.listCompactFieldMaxWidth,
        ),
        child: field,
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [compactField, const SizedBox(width: 4), addButton],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double buttonTotalWidth = 48;
        const double spacingWidth = 8;
        final bool hasFiniteWidth = constraints.maxWidth != double.infinity;
        final double fieldMax = LayoutBreakpoints.listCustomFieldMaxWidth;
        final double effectiveWidth = hasFiniteWidth
            ? constraints.maxWidth
            : fieldMax + buttonTotalWidth + spacingWidth;
        final bool stackVertically =
            effectiveWidth < fieldMax + buttonTotalWidth + spacingWidth;
        final double maxFieldWidth = stackVertically
            ? fieldMax
            : (hasFiniteWidth
                  ? math.min(
                      fieldMax,
                      math.max(
                        0,
                        effectiveWidth - (buttonTotalWidth + spacingWidth),
                      ),
                    )
                  : fieldMax);

        final Widget constrainedField = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxFieldWidth),
          child: field,
        );
        if (stackVertically) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              constrainedField,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: addButton),
            ],
          );
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              constrainedField,
              const SizedBox(width: spacingWidth),
              addButton,
            ],
          ),
        );
      },
    );
  }

  Widget _buildChip(String category, bool isActive) {
    final isSuggested = _baseSet.contains(category);
    final showDelete = (!widget.allowSelection && isSuggested) || !isSuggested;
    final bool isSelectable = widget.allowSelection;
    final bool highlightSuggested =
        widget.allowCustomCategories && !widget.allowSelection;
    final Color? chipBackground = highlightSuggested && isSuggested
        ? Theme.of(context).colorScheme.secondaryContainer
        : null;
    final Color? chipTextColor = highlightSuggested && isSuggested
        ? Theme.of(context).colorScheme.onSecondaryContainer
        : null;

    return InputChip(
      key: ValueKey('${preference.key}_chip_$category'),
      label: Text(category),
      selected: isSelectable ? isActive : false,
      showCheckmark: isSelectable,
      onSelected: isSelectable
          ? (value) => _toggleCategory(category, value)
          : null,
      labelStyle: chipTextColor != null
          ? Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: chipTextColor)
          : null,
      backgroundColor: chipBackground,
      selectedColor: chipBackground,
      deleteIcon: showDelete
          ? Icon(
              Icons.close,
              key: ValueKey('${preference.key}_delete_$category'),
            )
          : null,
      onDeleted: showDelete ? () => _removeCategory(category) : null,
    );
  }

  Widget _buildListBody() {
    final selection = _activeSelection();
    final ordered = _orderedChips(selection);
    final showCustomInput =
        widget.allowCustomCategories ||
        (!widget.allowSelection && _baseOptions.isNotEmpty);

    final wrapChildren = <Widget>[
      for (final category in ordered)
        _buildChip(category, selection.contains(category)),
    ];

    if (widget.isCompact && showCustomInput) {
      wrapChildren.add(
        _buildCustomInput(selection, compact: true),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          key: ValueKey('${preference.key}_chip_wrap'),
          spacing: 8,
          runSpacing: 8,
          children: wrapChildren,
        ),
        if (showCustomInput && !widget.isCompact) ...[
          const SizedBox(height: 12),
          _buildCustomInput(selection),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<PreferencesModel>();
    _syncTextController();

    return AnimatedBuilder(
      animation: _modeNotifier,
      builder: (context, _) {
        final showTextEditor =
            canUseTextMode && _modeNotifier.value == PreferenceInputMode.text;
        return showTextEditor ? _buildTextEditor() : _buildListBody();
      },
    );
  }
}

class PreferenceListModeToggle extends StatefulWidget {
  const PreferenceListModeToggle({
    super.key,
    required this.controllerKey,
  });

  final GlobalKey<PreferenceListControlState> controllerKey;

  @override
  State<PreferenceListModeToggle> createState() =>
      _PreferenceListModeToggleState();
}

class _PreferenceListModeToggleState extends State<PreferenceListModeToggle> {
  PreferenceListControlState? _controllerState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachController();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant PreferenceListModeToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controllerKey != widget.controllerKey) {
      _detachController();
    }
    _attachController();
  }

  void _attachController() {
    final state = widget.controllerKey.currentState;
    if (state == null || state == _controllerState) {
      return;
    }
    _detachController();
    _controllerState = state;
    _controllerState!.modeListenable.addListener(_handleChange);
  }

  void _detachController() {
    _controllerState?.modeListenable.removeListener(_handleChange);
    _controllerState = null;
  }

  void _handleChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _attachController();
    final controller = _controllerState;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    if (!controller.canUseTextMode) {
      return const SizedBox.shrink();
    }
    final localizations = VidraLocalizations.of(context);
    final mode = controller.mode;
    final icon = mode == PreferenceInputMode.text
        ? Icons.view_list
        : Icons.edit;
    final tooltip = localizations.ui(
      mode == PreferenceInputMode.text
          ? AppStringKey.listMode
          : AppStringKey.textMode,
    );
    final targetMode = mode == PreferenceInputMode.text
        ? PreferenceInputMode.list
        : PreferenceInputMode.text;
    return IconButton(
      key: ValueKey('${controller.preference.key}_mode_${targetMode.name}'),
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: controller.toggleMode,
    );
  }
}
