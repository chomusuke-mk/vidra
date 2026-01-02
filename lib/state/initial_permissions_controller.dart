import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Tracks the runtime permission status for the onboarding screen.
class InitialPermissionsController extends ChangeNotifier {
  InitialPermissionsController() {
    _refreshStatuses();
  }

  final Map<InitialPermissionType, PermissionCardState> _states = {
    for (final type in InitialPermissionType.values)
      type: PermissionCardState.initial(type),
  };

  bool _dismissed = false;
  bool _isLoading = true;
  Future<void>? _refreshTask;
  int? _androidSdkInt;

  bool get isLoading => _isLoading;
  bool get isDismissed => _dismissed;

  List<PermissionCardState> get permissions => InitialPermissionType.values
      .map((type) => _states[type] ?? PermissionCardState.initial(type))
      .toList(growable: false);

  bool get hasPendingRecommended =>
      permissions.any((state) => state.needsAttention);

  bool get shouldPrompt =>
      Platform.isAndroid && !_dismissed && hasPendingRecommended;

  void dismissForSession() {
    if (_dismissed) {
      return;
    }
    _dismissed = true;
    notifyListeners();
  }

  Future<void> refreshStatuses() => _refreshStatuses(force: true);

  Future<void> performAction(InitialPermissionType type) async {
    final state = _states[type];
    if (state == null || state.action == PermissionAction.none) {
      return;
    }
    if (state.action == PermissionAction.settings) {
      await openAppSettings();
      await _refreshStatuses(force: true);
      return;
    }
    final permission = _resolvePermission(type);
    if (permission == null) {
      return;
    }
    _setRequesting(type, true);
    try {
      await permission.request();
    } catch (_) {
      // Swallow and re-check below.
    } finally {
      _setRequesting(type, false);
      await _refreshStatuses(force: true);
    }
  }

  Future<void> _refreshStatuses({bool force = false}) async {
    if (!Platform.isAndroid) {
      _isLoading = false;
      for (final type in InitialPermissionType.values) {
        _states[type] = PermissionCardState.initial(type).copyWith(
          availability: PermissionAvailability.notRequired,
          isRecommended: false,
          action: PermissionAction.none,
        );
      }
      notifyListeners();
      return;
    }
    if (!force && _refreshTask != null) {
      return _refreshTask!;
    }
    final task = _hydrateStates();
    _refreshTask = task;
    await task;
    _refreshTask = null;
  }

  Future<void> _hydrateStates() async {
    _isLoading = true;
    notifyListeners();
    final sdkInt = await _resolveAndroidSdkInt();
    for (final type in InitialPermissionType.values) {
      final requiredNow = _isRequired(type, sdkInt);
      final recommended = _isRecommended(type, sdkInt);
      final permission = _resolvePermission(type);
      PermissionAvailability availability;
      if (!requiredNow) {
        availability = PermissionAvailability.notRequired;
      } else if (permission == null) {
        availability = PermissionAvailability.unsupported;
      } else {
        final status = await _safeStatus(permission);
        availability = _mapStatus(status);
      }
      final action = _resolveAction(availability, recommended);
      final previous = _states[type] ?? PermissionCardState.initial(type);
      _states[type] = previous.copyWith(
        availability: availability,
        isRecommended: recommended,
        action: action,
      );
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<int?> _resolveAndroidSdkInt() async {
    if (_androidSdkInt != null) {
      return _androidSdkInt;
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _androidSdkInt = info.version.sdkInt;
    } catch (_) {
      _androidSdkInt = null;
    }
    return _androidSdkInt;
  }

  Permission? _resolvePermission(InitialPermissionType type) {
    switch (type) {
      case InitialPermissionType.notifications:
        return Permission.notification;
      case InitialPermissionType.manageStorage:
        return Permission.manageExternalStorage;
      case InitialPermissionType.legacyStorage:
        return Permission.storage;
      case InitialPermissionType.overlay:
        return Permission.systemAlertWindow;
    }
  }

  Future<PermissionStatus?> _safeStatus(Permission permission) async {
    try {
      return await permission.status;
    } catch (_) {
      return null;
    }
  }

  PermissionAvailability _mapStatus(PermissionStatus? status) {
    if (status == null) {
      return PermissionAvailability.unsupported;
    }
    if (status.isGranted || status == PermissionStatus.limited) {
      return PermissionAvailability.granted;
    }
    switch (status) {
      case PermissionStatus.permanentlyDenied:
        return PermissionAvailability.permanentlyDenied;
      case PermissionStatus.denied:
        return PermissionAvailability.denied;
      case PermissionStatus.restricted:
        return PermissionAvailability.restricted;
      case PermissionStatus.provisional:
        return PermissionAvailability.denied;
      case PermissionStatus.limited:
        return PermissionAvailability.granted;
      case PermissionStatus.granted:
        return PermissionAvailability.granted;
    }
  }

  PermissionAction _resolveAction(
    PermissionAvailability availability,
    bool recommended,
  ) {
    if (!recommended) {
      return PermissionAction.none;
    }
    switch (availability) {
      case PermissionAvailability.denied:
      case PermissionAvailability.restricted:
        return PermissionAction.request;
      case PermissionAvailability.permanentlyDenied:
        return PermissionAction.settings;
      default:
        return PermissionAction.none;
    }
  }

  bool _isRequired(InitialPermissionType type, int? sdk) {
    if (sdk == null) {
      return true;
    }
    switch (type) {
      case InitialPermissionType.notifications:
        return sdk >= 33;
      case InitialPermissionType.manageStorage:
        return sdk >= 29;
      case InitialPermissionType.legacyStorage:
        return sdk < 29;
      case InitialPermissionType.overlay:
        return true;
    }
  }

  bool _isRecommended(InitialPermissionType type, int? sdk) {
    if (type == InitialPermissionType.overlay) {
      return true;
    }
    if (sdk == null) {
      return true;
    }
    return _isRequired(type, sdk);
  }

  void _setRequesting(InitialPermissionType type, bool requesting) {
    final previous = _states[type];
    if (previous == null) {
      return;
    }
    _states[type] = previous.copyWith(isRequesting: requesting);
    notifyListeners();
  }
}

enum InitialPermissionType {
  notifications,
  manageStorage,
  legacyStorage,
  overlay,
}

enum PermissionAvailability {
  unknown,
  granted,
  denied,
  permanentlyDenied,
  restricted,
  notRequired,
  unsupported,
}

enum PermissionAction { none, request, settings }

class PermissionCardState {
  const PermissionCardState({
    required this.type,
    required this.availability,
    required this.isRecommended,
    required this.isRequesting,
    required this.action,
  });

  factory PermissionCardState.initial(InitialPermissionType type) {
    return PermissionCardState(
      type: type,
      availability: PermissionAvailability.unknown,
      isRecommended: true,
      isRequesting: false,
      action: PermissionAction.none,
    );
  }

  final InitialPermissionType type;
  final PermissionAvailability availability;
  final bool isRecommended;
  final bool isRequesting;
  final PermissionAction action;

  bool get isGranted => availability == PermissionAvailability.granted;

  bool get satisfiesRequirement =>
      availability == PermissionAvailability.granted ||
      availability == PermissionAvailability.notRequired ||
      availability == PermissionAvailability.unsupported;

  bool get needsAttention =>
      isRecommended &&
      availability != PermissionAvailability.granted &&
      availability != PermissionAvailability.notRequired &&
      availability != PermissionAvailability.unsupported;

  PermissionCardState copyWith({
    PermissionAvailability? availability,
    bool? isRecommended,
    bool? isRequesting,
    PermissionAction? action,
  }) {
    return PermissionCardState(
      type: type,
      availability: availability ?? this.availability,
      isRecommended: isRecommended ?? this.isRecommended,
      isRequesting: isRequesting ?? this.isRequesting,
      action: action ?? this.action,
    );
  }
}
