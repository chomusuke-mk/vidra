import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/constants/layout_breakpoints.dart';
import 'package:vidra/data/preferences/preference_options.dart';
import 'package:vidra/models/preference.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/ui/widgets/preferences/preference_text_field_control.dart';

class PreferenceSwitchControl extends StatefulWidget {
  const PreferenceSwitchControl({
    super.key,
    required this.preference,
    this.language,
    this.showSwitch = true,
    this.showField = true,
  }) : assert(showSwitch || showField);

  final Preference preference;
  final String? language;
  final bool showSwitch;
  final bool showField;

  @override
  State<PreferenceSwitchControl> createState() =>
      _PreferenceSwitchControlState();
}

class _PreferenceSwitchControlState extends State<PreferenceSwitchControl> {
  Preference get preference => widget.preference;

  bool get _allowsString => preference.isTypeAllowed(String);
  bool get _allowsInt => preference.isTypeAllowed(int);

  Future<void> _updatePreference(Object value) async {
    final model = context.read<PreferencesModel>();
    await model.setPreferenceValue(preference, value);
  }

  Future<void> _changeBoolean(Object rawValue) async {
    Object newValue = rawValue;
    if (rawValue == false) {
      newValue = false;
    } else if (_allowsInt) {
      newValue = 0;
    } else if (_allowsString) {
      newValue = '';
    } else {
      newValue = true;
    }
    await _updatePreference(newValue);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<PreferencesModel>();
    final value = preference.get('value');
    final isFalse = value == false;
    final withOtherTypes = _allowsInt || _allowsString;
    final showSwitch = widget.showSwitch;
    final showField = widget.showField;

    if (!showSwitch && !showField) {
      return const SizedBox.shrink();
    }

    final maxFieldWidth = _allowsString
        ? LayoutBreakpoints.switchStringFieldMaxWidth
        : _allowsInt
        ? LayoutBreakpoints.switchIntFieldMaxWidth
        : LayoutBreakpoints.switchDefaultFieldMaxWidth;

    Widget? buildHybridField() {
      if (!showField || !withOtherTypes || isFalse) {
        return null;
      }
      return PreferenceTextFieldControl(
        preference: preference,
        suggestions: textPlaceholder[preference.key],
        keyboardType: _allowsInt && !_allowsString
            ? TextInputType.number
            : TextInputType.text,
        allowFolder: folderOptions.contains(preference.key),
        fieldKey: 'control_${preference.key}',
        maxWidth: maxFieldWidth,
      );
    }

    final hybridField = buildHybridField();
    final switchWidget = showSwitch
        ? Switch(
            key: ValueKey('control_${preference.key}_switch'),
            value: !isFalse,
            onChanged: (flag) => _changeBoolean(flag ? true : false),
            thumbIcon: const WidgetStateProperty<Icon>.fromMap({
              WidgetState.selected: Icon(Icons.check),
              WidgetState.any: Icon(Icons.close),
            }),
          )
        : null;

    if (hybridField == null && switchWidget == null) {
      return const SizedBox.shrink();
    }

    if (hybridField == null && switchWidget != null) {
      return switchWidget;
    }

    if (switchWidget == null && hybridField != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxFieldWidth),
          child: hybridField,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackLayout =
            constraints.maxWidth < LayoutBreakpoints.switchStackThreshold;

        return FractionallySizedBox(
          widthFactor: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: stackLayout
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: switchWidget!,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxFieldWidth),
                  child: hybridField!,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
