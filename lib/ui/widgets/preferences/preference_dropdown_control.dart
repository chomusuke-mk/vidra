import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:provider/provider.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/preferences/preference_options.dart';
import 'package:vidra/models/preference.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';

final Map<String, Map<String, Map<Object, String>>> _optionsCache = {};
const Set<String> _localizedLanguageOptionKeys = {
  'audio_language',
  'video_subtitles',
};

const double _compactFieldHeight = 30.0;
const double _compactVerticalPadding = 7.0;
const double _compactBorderWidth = 1.5;
const double _compactFocusedBorderWidth = 2.0;

class PreferenceDropdownControl extends StatefulWidget {
  const PreferenceDropdownControl({
    super.key,
    required this.preference,
    this.language,
    this.writeable = false,
    this.label,
    this.leadingIcon,
    this.helperText,
    this.isCompact = false,
    this.minCompactWidth,
  });

  final Preference preference;
  final String? language;
  final bool writeable;
  final Widget? label;
  final Widget? leadingIcon;
  final String? helperText;
  final bool isCompact;
  final double? minCompactWidth;

  @override
  State<PreferenceDropdownControl> createState() =>
      _PreferenceDropdownControlState();
}

class _PreferenceDropdownControlState extends State<PreferenceDropdownControl> {
  late final TextEditingController _controller;
  FocusNode? _focusNode;
  bool _focusListenerAttached = false;
  Map<Object, String>? _cachedOptions;
  List<DropdownMenuEntry<Object>>? _cachedEntries;
  String? _cachedOptionsKey;
  String? _cachedPlaceholder;
  double? _cachedCompactWidth;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant PreferenceDropdownControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final preferenceChanged = oldWidget.preference.key != widget.preference.key;
    final writeableChanged = oldWidget.writeable != widget.writeable;
    final minWidthChanged = oldWidget.minCompactWidth != widget.minCompactWidth;
    if (preferenceChanged || writeableChanged) {
      _cachedOptions = null;
      _cachedEntries = null;
      _cachedOptionsKey = null;
      _cachedPlaceholder = null;
      if (!widget.writeable) {
        _focusNode?.dispose();
        _focusNode = null;
        _focusListenerAttached = false;
      }
    }
    if (preferenceChanged || minWidthChanged) {
      _cachedCompactWidth = null;
    }
  }

  double _computeCompactWidth(
    BuildContext context,
    Iterable<DropdownMenuEntry<Object>> entries,
    String? placeholder,
    String displayValue,
  ) {
    final textStyle =
        Theme.of(context).textTheme.bodyLarge ??
        Theme.of(context).textTheme.bodyMedium ??
        const TextStyle();
    final textDirection = Directionality.of(context);
    final painter = TextPainter(
      textDirection: textDirection,
      maxLines: 1,
      textAlign: TextAlign.start,
    );

    double maxLabelWidth = 0;

    void measure(String? value) {
      if (value == null || value.isEmpty) {
        return;
      }
      painter
        ..text = TextSpan(text: value, style: textStyle)
        ..layout(maxWidth: double.infinity);
      maxLabelWidth = math.max(maxLabelWidth, painter.width);
    }

    String? longest;
    String? secondLongest;
    int longestLength = -1;
    int secondLength = -1;

    for (final entry in entries) {
      final label = entry.label;
      final length = label.runes.length;
      if (length > longestLength) {
        secondLongest = longest;
        secondLength = longestLength;
        longest = label;
        longestLength = length;
      } else if (length > secondLength) {
        secondLongest = label;
        secondLength = length;
      }
    }

    final samples = <String>{displayValue};
    if (placeholder != null) {
      samples.add(placeholder);
    }
    if (longest != null) {
      samples.add(longest);
    }
    if (secondLongest != null) {
      samples.add(secondLongest);
    }

    for (final value in samples) {
      measure(value);
    }

    final double horizontalPadding = 24; // dense padding (12 left + 12 right)
    final double trailingIconWidth = 32; // dropdown arrow with spacing
    final double leadingIconWidth = widget.leadingIcon == null
        ? 0
        : (IconTheme.of(context).size ?? 24) + 24; // icon plus padding

    final double computed =
        maxLabelWidth +
        horizontalPadding +
        trailingIconWidth +
        leadingIconWidth;

    final minWidth = widget.minCompactWidth ?? 80;
    return math.max(minWidth, computed.ceilToDouble());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode?.dispose();
    super.dispose();
  }

  Map<Object, String> _buildOptions(
    BuildContext context,
    String languageValue,
  ) {
    final cacheForKey = _optionsCache.putIfAbsent(
      widget.preference.key,
      () => <String, Map<Object, String>>{},
    );
    final cacheKey = _optionsCacheKey(context, languageValue);
    final cached = cacheForKey[cacheKey];
    if (cached != null) {
      return cached;
    }

    final Map<Object, String> options = {};
    final completions = dropdownOptions[widget.preference.key];
    final shouldLocalizeLanguages = _localizedLanguageOptionKeys.contains(
      widget.preference.key,
    );
    final localeNames = shouldLocalizeLanguages
        ? LocaleNames.of(context)
        : null;
    if (completions is Map<Object, Object>) {
      options.addAll(
        completions.map((key, value) {
          late final String showValue;
          if (value is Function) {
            try {
              showValue = value(languageValue);
            } catch (_) {
              showValue = value.toString();
            }
          } else {
            showValue = value.toString();
          }
          final localized = _maybeFormatLanguageLabel(
            key,
            showValue,
            localeNames,
          );
          return MapEntry(key, localized);
        }),
      );
    } else if (completions is List) {
      for (final entry in completions) {
        final label = '$entry';
        final localized = _maybeFormatLanguageLabel(entry, label, localeNames);
        options[entry] = localized;
      }
    }
    if (widget.preference.isTypeAllowed(bool) && !options.containsKey(false)) {
      options[false] = resolveAppString(AppStringKey.offLabel, languageValue);
    }
    final unmodifiable = Map<Object, String>.unmodifiable(options);
    cacheForKey[cacheKey] = unmodifiable;
    return unmodifiable;
  }

  String _optionsCacheKey(BuildContext context, String languageValue) {
    final locale = Localizations.maybeLocaleOf(context);
    if (locale == null) {
      return languageValue;
    }
    return '$languageValue|${locale.toLanguageTag()}';
  }

  String _maybeFormatLanguageLabel(
    Object key,
    String value,
    LocaleNames? localeNames,
  ) {
    if (localeNames == null) {
      return value;
    }
    if (key is! String) {
      return value;
    }
    if (!_localizedLanguageOptionKeys.contains(widget.preference.key)) {
      return value;
    }
    final localized = localeNames.nameOf(key) ?? value;
    return '${key.toLowerCase()} - $localized';
  }

  Object? _resolveCurrentSelection(Map<Object, String> options) {
    final stored = widget.preference.get('value');
    if (options.containsKey(stored)) {
      return stored;
    }
    return widget.preference.getDefaultValue<Object?>();
  }

  void _ensureOptionCache(BuildContext context, String languageValue) {
    final cacheKey = _optionsCacheKey(context, languageValue);
    if (_cachedOptions != null && _cachedOptionsKey == cacheKey) {
      return;
    }
    final options = _buildOptions(context, languageValue);
    final placeholder = (textPlaceholder[widget.preference.key] ?? []).join(
      ', ',
    );
    _cachedOptions = options;
    _cachedEntries = options.entries
        .map(
          (entry) =>
              DropdownMenuEntry<Object>(value: entry.key, label: entry.value),
        )
        .toList(growable: false);
    _cachedOptionsKey = cacheKey;
    _cachedPlaceholder = placeholder.isEmpty ? null : placeholder;
    _cachedCompactWidth = null;
  }

  void _ensureCompactWidth(
    BuildContext context,
    Iterable<DropdownMenuEntry<Object>> entries,
    String? placeholder,
    String displayValue,
  ) {
    if (!widget.isCompact) {
      return;
    }
    if (_cachedCompactWidth != null) {
      return;
    }
    _cachedCompactWidth = _computeCompactWidth(
      context,
      entries,
      placeholder,
      displayValue,
    );
  }

  InputDecorationTheme? _buildCompactInputDecorationTheme(
    BuildContext context,
  ) {
    if (!widget.isCompact) {
      return null;
    }
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(8);
    OutlineInputBorder outline(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: _compactVerticalPadding,
      ),
      constraints: const BoxConstraints.tightFor(height: _compactFieldHeight),
      border: OutlineInputBorder(borderRadius: borderRadius),
      enabledBorder: outline(
        colorScheme.outlineVariant,
        width: _compactBorderWidth,
      ),
      focusedBorder: outline(
        colorScheme.primary,
        width: _compactFocusedBorderWidth,
      ),
    );
  }

  Future<void> _updatePreference(Object value) async {
    final model = context.read<PreferencesModel>();
    await model.setPreferenceValue(widget.preference, value);
  }

  @override
  Widget build(BuildContext context) {
    final preferencesModel = context.watch<PreferencesModel>();
    final languageValue = widget.language ?? preferencesModel.effectiveLanguage;
    _ensureOptionCache(context, languageValue);

    final options = _cachedOptions ?? const <Object, String>{};
    final entries = _cachedEntries ?? const <DropdownMenuEntry<Object>>[];
    final placeHolder = _cachedPlaceholder;

    final focusNode = widget.writeable ? (_focusNode ??= FocusNode()) : null;

    Object? currentSelection = _resolveCurrentSelection(options);

    void syncControllerText({bool force = false}) {
      final displayValue =
          options[currentSelection] ?? currentSelection?.toString() ?? '';
      if ((force || !widget.writeable || !(focusNode?.hasFocus ?? false)) &&
          _controller.text != displayValue) {
        _controller
          ..text = displayValue
          ..selection = TextSelection.fromPosition(
            TextPosition(offset: displayValue.length),
          );
      }
    }

    if (widget.writeable && !_focusListenerAttached) {
      focusNode?.addListener(() {
        if (!focusNode.hasFocus) {
          syncControllerText(force: true);
        }
      });
      _focusListenerAttached = true;
    }

    syncControllerText();

    final displayValue = _controller.text;
    _ensureCompactWidth(context, entries, placeHolder, displayValue);
    final compactWidth = widget.isCompact ? _cachedCompactWidth : null;

    final shouldUseLazySheet = entries.length > 24;
    final inputDecorationTheme = _buildCompactInputDecorationTheme(context);

    final dropdown = DropdownMenu<Object>(
      key: ValueKey('control_${widget.preference.key}_dropdown'),
      label: widget.label,
      hintText: placeHolder,
      focusNode: focusNode,
      controller: _controller,
      initialSelection: currentSelection,
      dropdownMenuEntries: entries,
      enableFilter: widget.writeable,
      enableSearch: widget.writeable,
      requestFocusOnTap: widget.writeable,
      menuHeight: 320,
      width: compactWidth,
      leadingIcon: widget.leadingIcon,
      helperText: widget.helperText,
      menuStyle: widget.isCompact
          ? const MenuStyle(
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            )
          : null,
      inputDecorationTheme: inputDecorationTheme,
      onSelected: (value) async {
        if (value == null) {
          return;
        }
        currentSelection = value;
        await _updatePreference(value);
        syncControllerText(force: true);
      },
    );

    if (shouldUseLazySheet) {
      final lazyField = _LazyDropdownField(
        label: widget.label,
        helperText: widget.helperText,
        leadingIcon: widget.leadingIcon,
        placeholder: placeHolder,
        displayValue: displayValue,
        compact: widget.isCompact,
        onTap: () async {
          final selection = await _showLazySelectionSheet(
            context,
            entries,
            currentSelection,
            placeHolder,
          );
          if (selection == null) {
            return;
          }
          await _updatePreference(selection);
          syncControllerText(force: true);
        },
      );

      if (widget.isCompact) {
        return SizedBox(
          key: ValueKey('control_${widget.preference.key}'),
          width: compactWidth,
          height: _compactFieldHeight,
          child: lazyField,
        );
      }

      return ConstrainedBox(
        key: ValueKey('control_${widget.preference.key}'),
        constraints: const BoxConstraints(maxWidth: 320),
        child: lazyField,
      );
    }

    if (widget.isCompact) {
      return SizedBox(
        key: ValueKey('control_${widget.preference.key}'),
        width: compactWidth,
        height: _compactFieldHeight,
        child: dropdown,
      );
    }

    return ConstrainedBox(
      key: ValueKey('control_${widget.preference.key}'),
      constraints: const BoxConstraints(maxWidth: 320),
      child: dropdown,
    );
  }

  Future<Object?> _showLazySelectionSheet(
    BuildContext context,
    List<DropdownMenuEntry<Object>> entries,
    Object? currentSelection,
    String? placeholder,
  ) {
    final title = _resolveSheetTitle();
    final initialText = _controller.text;
    return showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: _CompactDropdownSheet(
            title: title,
            entries: entries,
            initialSelection: currentSelection,
            allowCustom: widget.writeable,
            initialText: initialText,
            placeholder: placeholder,
          ),
        );
      },
    );
  }

  String _resolveSheetTitle() {
    final labelWidget = widget.label;
    if (labelWidget is Text && labelWidget.data != null) {
      return labelWidget.data!;
    }
    return widget.preference.key;
  }
}

class _LazyDropdownField extends StatelessWidget {
  const _LazyDropdownField({
    required this.displayValue,
    required this.onTap,
    required this.compact,
    this.label,
    this.helperText,
    this.leadingIcon,
    this.placeholder,
  });

  final String displayValue;
  final VoidCallback onTap;
  final bool compact;
  final Widget? label;
  final String? helperText;
  final Widget? leadingIcon;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveValue = displayValue.isEmpty
        ? (placeholder ?? '--')
        : displayValue;

    Widget buildContent() {
      final text = Text(
        effectiveValue,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      final children = <Widget>[
        if (leadingIcon != null) ...[
          IconTheme(
            data: IconTheme.of(context).copyWith(size: 20),
            child: leadingIcon!,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: text),
        Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurfaceVariant),
      ];
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: children,
      );
    }

    OutlineInputBorder outline(Color color, double width) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    final decoration = InputDecoration(
      label: label,
      helperText: helperText,
      isDense: compact,
      contentPadding: compact
          ? const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: _compactVerticalPadding,
            )
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: outline(colorScheme.outlineVariant, _compactBorderWidth),
      focusedBorder: outline(colorScheme.primary, _compactFocusedBorderWidth),
    );

    final field = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: InputDecorator(
          decoration: decoration,
          isEmpty: displayValue.isEmpty,
          child: buildContent(),
        ),
      ),
    );

    if (compact) {
      return SizedBox(height: _compactFieldHeight, child: field);
    }
    return field;
  }
}

class _CompactDropdownSheet extends StatefulWidget {
  const _CompactDropdownSheet({
    required this.title,
    required this.entries,
    required this.initialSelection,
    required this.allowCustom,
    required this.initialText,
    this.placeholder,
  });

  final String title;
  final List<DropdownMenuEntry<Object>> entries;
  final Object? initialSelection;
  final bool allowCustom;
  final String initialText;
  final String? placeholder;

  @override
  State<_CompactDropdownSheet> createState() => _CompactDropdownSheetState();
}

class _CompactDropdownSheetState extends State<_CompactDropdownSheet> {
  late final TextEditingController _searchController;
  late final TextEditingController _customController;
  String _query = '';
  Object? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    _searchController = TextEditingController();
    _customController = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customController.dispose();
    super.dispose();
  }

  List<DropdownMenuEntry<Object>> get _filteredEntries {
    if (_query.isEmpty) {
      return widget.entries;
    }
    final normalized = _query.toLowerCase();
    return widget.entries
        .where((entry) => entry.label.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  void _confirmCustomValue() {
    final text = _customController.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = VidraLocalizations.of(context);
    final entries = _filteredEntries;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: localizations.ui(
                    AppStringKey.preferenceDropdownDialogCloseTooltip,
                  ),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          if (widget.allowCustom)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _customController,
                decoration: InputDecoration(
                  labelText:
                      widget.placeholder ??
                      localizations.ui(
                        AppStringKey.preferenceDropdownDialogValueLabel,
                      ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _confirmCustomValue,
                  ),
                ),
                onSubmitted: (_) => _confirmCustomValue(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: localizations.ui(
                  AppStringKey.preferenceDropdownDialogSearchLabel,
                ),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() {
                _query = value;
              }),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      localizations.ui(
                        AppStringKey.preferenceDropdownDialogNoResults,
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final selected = entry.value == _selected;
                      return ListTile(
                        title: Text(entry.label),
                        trailing: selected ? const Icon(Icons.check) : null,
                        onTap: () {
                          setState(() {
                            _selected = entry.value;
                          });
                          Navigator.of(context).pop(entry.value);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
