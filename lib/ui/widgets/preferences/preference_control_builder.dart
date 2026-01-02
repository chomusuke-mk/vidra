import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/preferences/preference_options.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/models/preference.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/ui/models/preference_ui_models.dart';
import 'package:vidra/ui/widgets/preferences/preference_dropdown_control.dart';
import 'package:vidra/ui/widgets/preferences/preference_list_control.dart';
import 'package:vidra/ui/widgets/preferences/preference_map_control.dart';
import 'package:vidra/ui/widgets/preferences/preference_switch_control.dart';
import 'package:vidra/ui/widgets/preferences/preference_text_field_control.dart';

class PreferenceControlBuilder {
  const PreferenceControlBuilder();

  PreferenceControl build({
    required BuildContext context,
    required Preference preference,
    String? languageOverride,
  }) {
    final preferencesModel = context.read<PreferencesModel>();
    final languageValue =
        languageOverride ?? preferencesModel.effectiveLanguage;

    final bool allowNull = preference.isTypeAllowed(Null);
    final bool hasBool = preference.isTypeAllowed(bool);
    final bool hasInt = preference.isTypeAllowed(int);
    final bool hasString = preference.isTypeAllowed(String);
    final bool hasList = preference.isTypeAllowed(List);
    final bool hasMap = preference.isTypeAllowed(Map);

    if (dropdownOptions.containsKey(preference.key)) {
      return PreferenceControl(
        control: PreferenceDropdownControl(
          preference: preference,
          language: languageValue,
          writeable: preference.key == 'language',
        ),
        inline: true,
      );
    }

    if (hasMap) {
      final bool allowTextMode =
          hasString && !blockedMapTextModeKeys.contains(preference.key);
      final mapKey = GlobalObjectKey<PreferenceMapControlState>(preference);
      return PreferenceControl(
        control: PreferenceMapControl(
          key: mapKey,
          preference: preference,
          allowTextMode: allowTextMode,
        ),
        headerTrailing: allowTextMode
            ? PreferenceMapModeToggle(
                controllerKey: mapKey,
              )
            : null,
        fullLine: true,
      );
    }

    if (hasList) {
      final List<String>? options = autocompleteOptions[preference.key];
      final allowCustomCategories = allowCustomValues.contains(preference.key);
      final allowSelection = allowSelectionValues.contains(preference.key);
      final listKey = GlobalObjectKey<PreferenceListControlState>(preference);
      final joinDelimiter = preference.key == 'format' ? '/' : ',';
      final allowTextEditing =
          allowCustomCategories &&
          hasString &&
          !blockedListTextModeKeys.contains(preference.key);
      return PreferenceControl(
        control: PreferenceListControl(
          key: listKey,
          preference: preference,
          options: options,
          allowCustomCategories: allowCustomCategories,
          allowSelection: allowSelection,
          joinDelimiter: joinDelimiter,
          allowTextEditing: allowTextEditing,
        ),
        headerTrailing: allowTextEditing
            ? PreferenceListModeToggle(
                controllerKey: listKey,
              )
            : null,
        fullLine: allowCustomCategories || !allowSelection,
      );
    }

    if (hasBool && !hasList && !hasMap) {
      Future<void> toggleValue() async {
        final current = preference.get('value');
        if (current == false) {
          if (hasInt) {
            await preferencesModel.setPreferenceValue(preference, 0);
          } else if (hasString) {
            await preferencesModel.setPreferenceValue(preference, '');
          } else {
            await preferencesModel.setPreferenceValue(preference, true);
          }
        } else {
          await preferencesModel.setPreferenceValue(preference, false);
        }
      }

      final bool hasHybridField = hasString || hasInt;
      if (hasHybridField) {
        return PreferenceControl(
          control: PreferenceSwitchControl(
            preference: preference,
            language: languageValue,
            showSwitch: false,
            showField: true,
          ),
          headerTrailing: PreferenceSwitchControl(
            preference: preference,
            language: languageValue,
            showSwitch: true,
            showField: false,
          ),
          inline: false,
          fullLine: true,
          onTap: () async {
            await toggleValue();
          },
        );
      }

      return PreferenceControl(
        control: PreferenceSwitchControl(
          preference: preference,
          language: languageValue,
        ),
        inline: true,
        fullLine: hasHybridField,
        onTap: () async {
          await toggleValue();
        },
      );
    }

    if (hasString || hasInt || allowNull) {
      final bool isFfmpegLocation = preference.key == 'ffmpeg_location';
      bool? manualEntryOverride;
      if (isFfmpegLocation) {
        manualEntryOverride = Platform.isAndroid ? false : true;
      }
      return PreferenceControl(
        control: PreferenceTextFieldControl(
          preference: preference,
          language: languageValue,
          suggestions: textPlaceholder[preference.key],
          allowNull: allowNull,
          allowFolder: folderOptions.contains(preference.key),
          manualEntryOverride: manualEntryOverride,
        ),
        inline: true,
      );
    }

    final localizations = VidraLocalizations.of(context);
    return PreferenceControl(
      control: SizedBox(
        width: 150,
        child: Text(
          localizations.ui(AppStringKey.preferenceControlNotImplemented),
        ),
      ),
    );
  }
}
