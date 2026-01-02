import 'package:flutter/widgets.dart';
import 'package:vidra/models/preference.dart';

enum PreferenceInputMode { text, list, map }

class PreferenceControl {
  const PreferenceControl({
    required this.control,
    this.inline = false,
    this.onTap,
    this.headerTrailing,
    this.fullLine = false,
  });

  final Widget control;
  final bool inline;
  final Future<void> Function()? onTap;
  final Widget? headerTrailing;
  final bool fullLine;
}

class PreferenceSection {
  const PreferenceSection({required this.titleKey, required this.preferences});

  final String titleKey;
  final List<Preference> preferences;
}
