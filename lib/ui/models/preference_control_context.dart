import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:vidra/models/preference.dart';
import 'package:vidra/models/preferences_model.dart';

class PreferenceControlContext {
  PreferenceControlContext({
    required this.context,
    required this.preferencesModel,
    required this.languageValue,
  });

  final BuildContext context;
  final PreferencesModel preferencesModel;
  final String languageValue;

  static PreferenceControlContext of(BuildContext context) {
    final model = context.read<PreferencesModel>();
    return PreferenceControlContext(
      context: context,
      preferencesModel: model,
      languageValue: model.effectiveLanguage,
    );
  }

  Future<void> setPreferenceValue(Preference preference, Object value) async {
    await preferencesModel.setPreferenceValue(preference, value);
  }
}
