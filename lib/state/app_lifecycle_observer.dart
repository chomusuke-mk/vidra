import 'package:flutter/widgets.dart';

/// Observes the application lifecycle to determine whether the UI is visible
/// in the foreground.
class AppLifecycleObserver extends ChangeNotifier with WidgetsBindingObserver {
  AppLifecycleObserver() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    final initialState = binding.lifecycleState;
    _isForeground =
        initialState == null || initialState == AppLifecycleState.resumed;
  }

  bool _isForeground = true;

  bool get isForeground => _isForeground;
  bool get isBackground => !_isForeground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nextIsForeground = state == AppLifecycleState.resumed;
    if (nextIsForeground == _isForeground) {
      return;
    }
    _isForeground = nextIsForeground;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
