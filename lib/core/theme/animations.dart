import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vidra Master Animation Tokens & Curves
abstract class AppAnimations {
  // Duration Tokens
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration medium = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 450);

  // Curve Tokens
  static const Curve enterCurve = Curves.easeOutQuart;
  static const Curve standardCurve = Curves.fastOutSlowIn;
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve bounceCurve = Curves.easeOutBack;
  static const Curve linearCurve = Curves.linear;

  // Ergonomic Curve Aliases
  static const Curve enter = enterCurve;
  static const Curve standard = standardCurve;
  static const Curve exit = exitCurve;
  static const Curve bounce = bounceCurve;
  static const Curve linear = linearCurve;
}

/// Tactile Haptic Service for Vidra Multiplatform
abstract class AppHaptics {
  /// Subtle click for chips, tabs, switches, and format selectors
  static Future<void> selection() => HapticFeedback.selectionClick();

  /// Light notch for swipe gesture threshold crossings (30%)
  static Future<void> lightImpact() => HapticFeedback.lightImpact();
  static Future<void> light() => HapticFeedback.lightImpact();

  /// Medium pulse for completion, verification, and options apply
  static Future<void> mediumImpact() => HapticFeedback.mediumImpact();
  static Future<void> medium() => HapticFeedback.mediumImpact();

  /// Heavy warning for cancel, delete actions, or error states
  static Future<void> heavyImpact() => HapticFeedback.heavyImpact();
  static Future<void> heavy() => HapticFeedback.heavyImpact();

  /// Explicit error feedback method
  static Future<void> error() => HapticFeedback.heavyImpact();
}
