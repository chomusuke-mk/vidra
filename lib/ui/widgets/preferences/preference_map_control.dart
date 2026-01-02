import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/constants/layout_breakpoints.dart';
import 'package:vidra/data/preferences/preference_options.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/models/preference.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/ui/models/preference_ui_models.dart';
import 'package:vidra/ui/widgets/preferences/preference_control_shared.dart';
import 'package:vidra/ui/widgets/preferences/preference_text_field_control.dart';

class PreferenceMapControl extends StatefulWidget {
  const PreferenceMapControl({
    super.key,
    required this.preference,
    this.allowTextMode = true,
  });

  final Preference preference;
  final bool allowTextMode;

  @override
  State<PreferenceMapControl> createState() => PreferenceMapControlState();
}

class PreferenceMapControlState extends State<PreferenceMapControl> {
  late final TextEditingController _keyController;
  late final TextEditingController _valueController;
  late final FocusNode _keyFocusNode;
  late final FocusNode _valueFocusNode;
  late final ValueNotifier<PreferenceInputMode> _modeNotifier;
  late final FocusNode _textFocusNode;

  Preference get preference => widget.preference;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController();
    _valueController = TextEditingController();
    _keyFocusNode = FocusNode();
    _valueFocusNode = FocusNode();
    _textFocusNode = FocusNode();
    _modeNotifier = ValueNotifier<PreferenceInputMode>(_initialMode());
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    _keyFocusNode.dispose();
    _valueFocusNode.dispose();
    _textFocusNode.dispose();
    _modeNotifier.dispose();
    super.dispose();
  }

  PreferenceInputMode _initialMode() {
    final value = preference.get('value');
    if (!widget.allowTextMode) {
      return PreferenceInputMode.map;
    }
    if (value is Map) {
      return PreferenceInputMode.map;
    }
    if (value is List) {
      return PreferenceInputMode.list;
    }
    return PreferenceInputMode.text;
  }

  PreferenceInputMode get mode => _modeNotifier.value;

  ValueListenable<PreferenceInputMode> get modeListenable => _modeNotifier;

  bool get allowTextMode => widget.allowTextMode;

  void setMode(PreferenceInputMode mode) {
    if (!widget.allowTextMode && mode == PreferenceInputMode.text) {
      return;
    }
    if (_modeNotifier.value == mode) {
      return;
    }
    _modeNotifier.value = mode;
    setState(() {});
  }

  void toggleMode() {
    if (!widget.allowTextMode) {
      return;
    }
    if (_modeNotifier.value == PreferenceInputMode.map) {
      setMode(PreferenceInputMode.text);
    } else {
      setMode(PreferenceInputMode.map);
    }
  }

  Map<String, String> _currentMapValue() {
    final value = preference.get('value');
    if (value is Map) {
      return value.map(
        (key, dynamic val) => MapEntry(key.toString(), val?.toString() ?? ''),
      );
    }
    return {};
  }

  void _clearEntryControllers() {
    _keyController.clear();
    _valueController.clear();
  }

  Future<void> _updatePreference(Object value) async {
    final model = context.read<PreferencesModel>();
    await model.setPreferenceValue(preference, value);
  }

  Future<void> _addEntry() async {
    final key = _keyController.text.trim();
    final value = _valueController.text.trim();
    if (key.isEmpty || value.isEmpty) {
      return;
    }
    final current = _currentMapValue();
    current[key] = value;
    await _updatePreference(current);
    _clearEntryControllers();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_keyFocusNode);
    });
  }

  Future<void> _removeEntry(String key) async {
    final current = _currentMapValue();
    if (current.remove(key) != null) {
      await _updatePreference(current);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_keyFocusNode);
      });
    }
  }

  Map<String, String>? _tryParseMapString(String input) {
    try {
      final decoded = jsonDecode(input);
      if (decoded is Map) {
        return decoded.map(
          (key, dynamic value) =>
              MapEntry(key.toString(), value?.toString() ?? ''),
        );
      }
    } catch (_) {
      // ignore
    }

    final lines = input.split(RegExp(r'\r?\n'));
    final result = <String, String>{};
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separatorIndex = line.indexOf(':');
      if (separatorIndex <= 0) {
        return null;
      }
      final key = line.substring(0, separatorIndex).trim();
      final value = line.substring(separatorIndex + 1).trim();
      if (key.isEmpty) {
        return null;
      }
      result[key] = value;
    }
    return result.isEmpty ? null : result;
  }

  Future<bool> _applyTextValue(String textValue) async {
    final localizations = VidraLocalizations.of(context);
    final trimmed = textValue.trim();
    if (trimmed.isEmpty) {
      await _updatePreference('');
      _clearEntryControllers();
      return true;
    }

    final parsed = _tryParseMapString(trimmed);
    if (parsed != null) {
      final allowsCustomKeys = allowCustomValues.contains(preference.key);
      final suggestions =
          autocompleteOptions[preference.key] ?? const <String>[];
      final lookup = {
        for (final suggestion in suggestions)
          if (suggestion.trim().isNotEmpty)
            suggestion.trim().toLowerCase(): suggestion.trim(),
      };
      final normalized = <String, String>{};
      for (final entry in parsed.entries) {
        final canonical = lookup[entry.key.toLowerCase()];
        if (canonical != null) {
          normalized[canonical] = entry.value;
          continue;
        }
        if (!allowsCustomKeys) {
          if (!mounted) {
            return false;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                localizations.ui(AppStringKey.invalidMapKey),
              ),
            ),
          );
          await _updatePreference(trimmed);
          return false;
        }
        normalized[entry.key] = entry.value;
      }
      await _updatePreference(normalized);
      _clearEntryControllers();
      return true;
    }

    if (!mounted) {
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          localizations.ui(AppStringKey.invalidMapFormat),
        ),
      ),
    );
    await _updatePreference(trimmed);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = VidraLocalizations.of(context);
    context.watch<PreferencesModel>();
    final mapValue = _currentMapValue();
    final isFullTextPreference = kMapTextKeys.contains(preference.key);
    final maxContentWidth = isFullTextPreference
        ? LayoutBreakpoints.mapFullTextMaxWidth
        : LayoutBreakpoints.mapDefaultTextMaxWidth;
    final supportsDirectoryPicker = folderOptions.contains(preference.key);
    final keySuggestions =
        autocompleteOptions[preference.key] ?? const <String>[];
    final allowsCustomMapKeys = allowCustomValues.contains(preference.key);
    final suggestionLookup = {
      for (final suggestion in keySuggestions)
        if (suggestion.trim().isNotEmpty)
          suggestion.trim().toLowerCase(): suggestion.trim(),
    };

    String? resolveCanonicalKey(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final lower = trimmed.toLowerCase();
      final suggestion = suggestionLookup[lower];
      if (suggestion != null) {
        return suggestion;
      }
      return allowsCustomMapKeys ? trimmed : null;
    }

    Future<bool> attemptAddMapEntry() async {
      final rawKey = _keyController.text.trim();
      if (rawKey.isEmpty) {
        FocusScope.of(context).requestFocus(_keyFocusNode);
        return false;
      }
      final rawValue = _valueController.text.trim();
      if (rawValue.isEmpty) {
        FocusScope.of(context).requestFocus(_valueFocusNode);
        return false;
      }

      final canonicalKey = resolveCanonicalKey(rawKey);
      if (canonicalKey == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.ui(AppStringKey.invalidMapKey)),
          ),
        );
        FocusScope.of(context).requestFocus(_keyFocusNode);
        return false;
      }
      if (canonicalKey != rawKey) {
        _keyController
          ..text = canonicalKey
          ..selection = TextSelection.collapsed(offset: canonicalKey.length);
      }

      await _addEntry();
      return true;
    }

    Widget buildKeyField() {
      InputDecoration decoration() => InputDecoration(
        labelText: localizations.ui(AppStringKey.mapKeyLabel),
      );

      Future<void> handleSubmit() async {
        await attemptAddMapEntry();
      }

      Widget wrapKeyControl(Widget child) {
        return Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: LayoutBreakpoints.mapKeyFieldMaxWidth,
            ),
            child: child,
          ),
        );
      }

      if (keySuggestions.isEmpty) {
        final keyField = TextField(
          key: ValueKey('map_key_${preference.key}'),
          controller: _keyController,
          focusNode: _keyFocusNode,
          textInputAction: TextInputAction.next,
          decoration: decoration(),
          onSubmitted: (_) async => handleSubmit(),
        );
        return wrapKeyControl(keyField);
      }

      final autocomplete = RawAutocomplete<String>(
        key: ValueKey(
          'map_key_autocomplete_${preference.key}_${mapValue.hashCode}',
        ),
        textEditingController: _keyController,
        focusNode: _keyFocusNode,
        optionsBuilder: (value) {
          return filterMapKeySuggestions(
            keySuggestions,
            mapValue,
            query: value.text,
            currentInput: _keyController.text,
          );
        },
        displayStringForOption: (option) => option,
        optionsViewBuilder: (context, onSelected, options) {
          if (options.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 240,
                  maxWidth: 320,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      key: ValueKey(
                        'map_key_autocomplete_${preference.key}_$option',
                      ),
                      title: Text(option),
                      onTap: () {
                        onSelected(option);
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            key: ValueKey('map_key_${preference.key}'),
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.next,
            decoration: decoration(),
            onSubmitted: (_) async => handleSubmit(),
          );
        },
        onSelected: (selection) {
          _keyController
            ..text = selection
            ..selection = TextSelection.collapsed(offset: selection.length);
          FocusScope.of(context).requestFocus(_valueFocusNode);
        },
      );

      return wrapKeyControl(autocomplete);
    }

    Widget buildValueForm() {
      Future<bool> handleValueSubmit(String trimmed) async {
        if (trimmed.isEmpty) {
          return true;
        }
        await attemptAddMapEntry();
        return true;
      }

      Widget buildValueField(double maxWidthConstraint) {
        return PreferenceTextFieldControl(
          key: ValueKey('map_value_field_${preference.key}'),
          preference: preference,
          allowNull: true,
          focusNode: _valueFocusNode,
          controllerOverride: _valueController,
          allowFolder: supportsDirectoryPicker,
          fieldKey: 'map_value_${preference.key}',
          maxWidth: maxWidthConstraint,
          useDirectoryPicker: true,
          submitOnEditingComplete: false,
          submitOnTapOutside: false,
          onSubmit: (value) => handleValueSubmit(value),
          onFolderPicked: (_) async {},
        );
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final maxWidthConstraint = constraints.maxWidth == double.infinity
              ? maxContentWidth
              : constraints.maxWidth;
          return buildValueField(maxWidthConstraint);
        },
      );
    }

    Widget buildEntryCard(MapEntry<String, String> entry) {
      final theme = Theme.of(context);
      final dividerColor = theme.dividerColor;
      final removeTooltip = localizations.ui(AppStringKey.removeEntry);
      final colorScheme = theme.colorScheme;
      final highlightColor = colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.2,
      );
      final borderTint = dividerColor.withValues(alpha: 0.7);

      return Container(
        key: ValueKey('map_entry_${preference.key}_${entry.key}'),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: highlightColor,
          border: Border.all(color: borderTint),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(entry.key, style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  key: ValueKey(
                    'map_entry_${preference.key}_${entry.key}_remove',
                  ),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: removeTooltip,
                  onPressed: () => _removeEntry(entry.key),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(entry.value, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    final addButton = SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        key: ValueKey('map_add_${preference.key}'),
        icon: const Icon(Icons.add, size: 20),
        tooltip: localizations.ui(AppStringKey.addEntry),
        onPressed: () => attemptAddMapEntry(),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      ),
    );

    Widget buildMapBody() {
      final entryList = Column(
        key: ValueKey('control_${preference.key}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final entry in mapValue.entries) buildEntryCard(entry)],
      );

      return LayoutBuilder(
        builder: (context, constraints) {
          final stackFields =
              constraints.maxWidth < LayoutBreakpoints.mapStackThreshold;
          Widget buildInputs() {
            if (stackFields) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildKeyField(),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: LayoutBreakpoints.mapValueFieldMaxWidth,
                          ),
                          child: buildValueForm(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      addButton,
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(fit: FlexFit.loose, child: buildKeyField()),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: LayoutBreakpoints.mapValueFieldMaxWidth,
                  ),
                  child: buildValueForm(),
                ),
                const SizedBox(width: 8),
                addButton,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [entryList, const SizedBox(height: 5), buildInputs()],
          );
        },
      );
    }

    Widget buildTextBody() {
      final textField = PreferenceTextFieldControl(
        key: ValueKey('map_text_${preference.key}'),
        preference: preference,
        suggestions: textPlaceholder[preference.key],
        keyboardType: isFullTextPreference
            ? TextInputType.multiline
            : TextInputType.text,
        allowNull: true,
        focusNode: _textFocusNode,
        minLines: isFullTextPreference ? 3 : 1,
        maxLines: isFullTextPreference ? 8 : 1,
        submitOnEditingComplete: true,
        submitOnTapOutside: true,
        onSubmit: (value) => _applyTextValue(value),
      );

      final maxWidth = isFullTextPreference
          ? LayoutBreakpoints.mapFullTextMaxWidth
          : maxContentWidth;

      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: textField,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _modeNotifier,
      builder: (context, _) {
        if (mode == PreferenceInputMode.text) {
          return buildTextBody();
        }
        return buildMapBody();
      },
    );
  }
}

class PreferenceMapModeToggle extends StatefulWidget {
  const PreferenceMapModeToggle({
    super.key,
    required this.controllerKey,
  });

  final GlobalKey<PreferenceMapControlState> controllerKey;

  @override
  State<PreferenceMapModeToggle> createState() =>
      _PreferenceMapModeToggleState();
}

class _PreferenceMapModeToggleState extends State<PreferenceMapModeToggle> {
  PreferenceMapControlState? _controllerState;

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
  void didUpdateWidget(covariant PreferenceMapModeToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controllerKey != widget.controllerKey) {
      _detachController();
    }
    _attachController();
  }

  void _attachController() {
    final state = widget.controllerKey.currentState;
    if (state == _controllerState || state == null) {
      return;
    }
    _detachController();
    _controllerState = state;
    _controllerState!.modeListenable.addListener(_handleControllerChanged);
  }

  void _detachController() {
    _controllerState?.modeListenable.removeListener(_handleControllerChanged);
    _controllerState = null;
  }

  void _handleControllerChanged() {
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
    final state = _controllerState;
    if (state == null) {
      return const SizedBox.shrink();
    }
    if (!state.allowTextMode) {
      return const SizedBox.shrink();
    }
    final localizations = VidraLocalizations.of(context);
    final mode = state.mode;
    final icon = mode == PreferenceInputMode.text ? Icons.map : Icons.edit;
    final tooltip = localizations.ui(
      mode == PreferenceInputMode.text
          ? AppStringKey.mapMode
          : AppStringKey.textMode,
    );
    final targetMode = mode == PreferenceInputMode.text
        ? PreferenceInputMode.map
        : PreferenceInputMode.text;
    return IconButton(
      key: ValueKey(
        'map_mode_toggle_${state.preference.key}_${targetMode.name}',
      ),
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: state.toggleMode,
    );
  }
}
