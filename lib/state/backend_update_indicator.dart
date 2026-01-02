import 'package:flutter/foundation.dart';

/// Tracks high-level backend update states that impact the home indicator.
class BackendUpdateIndicator {
  BackendUpdateIndicator._();

  static final BackendUpdateIndicator instance = BackendUpdateIndicator._();

  final ValueNotifier<BackendUpdateStatus> _state =
      ValueNotifier<BackendUpdateStatus>(BackendUpdateStatus.idle);

  ValueListenable<BackendUpdateStatus> get state => _state;

  void setState(BackendUpdateStatus next) {
    if (_state.value == next) {
      return;
    }
    _state.value = next;
  }
}

/// Describes the extra update-centric layers that can override the indicator
/// visuals even when the backend is running.
enum BackendUpdateStatus { idle, downloadingUpdate, installReady }
