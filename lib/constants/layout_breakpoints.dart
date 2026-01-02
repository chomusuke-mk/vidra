/// Centralized layout metrics for preference UI elements.
class LayoutBreakpoints {
  const LayoutBreakpoints._();

  // Preference switch layout
  static const double switchStackThreshold = 220;
  static const double switchStringFieldMaxWidth = 800;
  static const double switchIntFieldMaxWidth = 200;
  static const double switchDefaultFieldMaxWidth = 400;

  // Preference list layout
  static const double listTextEditorMaxWidth = 360;
  static const double listCustomFieldMaxWidth = 320;
  static const double listCustomStackThreshold = 260;
  static const double listAutocompleteMaxWidth = 320;
  static const double listAutocompleteMaxHeight = 240;
  static const double listCompactFieldMaxWidth = 80;

  // Preference map layout
  static const double mapStackThreshold = 560;
  static const double mapKeyFieldMaxWidth = 320;
  static const double mapValueFieldMaxWidth = 360;
  static const double mapFullTextMaxWidth = 560;
  static const double mapDefaultTextMaxWidth = 520;
}
