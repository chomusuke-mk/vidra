import 'package:flutter/material.dart';

/// Vidra Master Spacing & Layout Tokens (8pt Harmonic Grid)
abstract class AppSpacing {
  // 8pt Grid Constants
  static const double space2 = 2.0;   // Micro progress bar height, rim stroke
  static const double space4 = 4.0;   // Duration badge margin, micro inset
  static const double space6 = 6.0;   // Metadata pill inter-badge gap
  static const double space8 = 8.0;   // Chip spacing, inner card vertical gap
  static const double space12 = 12.0; // Thumbnail-to-title gap, card spacing
  static const double space16 = 16.0; // Screen edge padding, card padding
  static const double space20 = 20.0; // Bottom sheet horizontal inset
  static const double space24 = 24.0; // Section gaps, dialog padding
  static const double space32 = 32.0; // Desktop canvas padding, empty state gap
  static const double space48 = 48.0; // Minimum touch target, activity rail width
  static const double space64 = 64.0; // Header title spacing, collapsed rail

  // Maximum Layout Constraints
  static const double maxFormWidth = 540.0;
  static const double maxFormInputWidth = 540.0; // Ergonomic alias
  static const double minTouchTarget = 48.0;
  static const double maxModalWidth = 600.0;
  static const double maxOmniSearchWidth = 520.0;

  // Desktop Structural Dimensions
  static const double desktopHeaderHeight = 44.0;
  static const double desktopActivityRailWidth = 48.0;
  static const double desktopSidebarWidth = 220.0;
  static const double desktopInspectorWidth = 280.0;
  static const double desktopStatusBarHeight = 24.0;
}

/// Vidra Responsive Breakpoints Enum
enum VidraBreakpoint {
  compact,  // Mobile (< 600dp)
  medium,   // Tablet / Foldable (600dp - 1024dp)
  expanded, // Desktop / Ultrawide (> 1024dp)
}

/// Vidra Responsive Breakpoint Utilities
abstract class AppBreakpoints {
  static const double compactMax = 600.0;
  static const double mediumMax = 1024.0;

  /// Determine breakpoint category from numeric width
  static VidraBreakpoint fromWidth(double width) {
    if (width < compactMax) return VidraBreakpoint.compact;
    if (width <= mediumMax) return VidraBreakpoint.medium;
    return VidraBreakpoint.expanded;
  }

  /// Get current breakpoint from BuildContext
  static VidraBreakpoint of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  /// Check if viewport is compact (< 600dp)
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactMax;

  /// Check if viewport is medium (600dp - 1024dp)
  static bool isMedium(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= compactMax && w <= mediumMax;
  }

  /// Check if viewport is expanded (> 1024dp)
  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width > mediumMax;
}
