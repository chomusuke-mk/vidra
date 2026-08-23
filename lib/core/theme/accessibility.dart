import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Vidra Accessibility Helper & WCAG Contrast Verification Suite
abstract class AppAccessibility {
  /// Maximum text scaling factor allowed before clamping
  static const double maxScaleFactor = 2.0;

  /// Returns a TextScaler clamped to a maximum scale factor
  static TextScaler clampedTextScaler(
    BuildContext context, {
    double max = maxScaleFactor,
  }) {
    return MediaQuery.textScalerOf(context).clamp(maxScaleFactor: max);
  }

  /// Compute relative luminance for WCAG 2.1 contrast calculation
  /// L = 0.2126 * R + 0.7152 * G + 0.0722 * B
  static double calculateLuminance(Color color) {
    double linearize(double channel) {
      return (channel <= 0.04045)
          ? channel / 12.92
          : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = linearize(color.r);
    final g = linearize(color.g);
    final b = linearize(color.b);

    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Calculate WCAG 2.1 contrast ratio between two colors
  /// Ratio = (L1 + 0.05) / (L2 + 0.05) where L1 is lighter and L2 is darker
  static double calculateContrastRatio(Color foreground, Color background) {
    final l1 = calculateLuminance(foreground);
    final l2 = calculateLuminance(background);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Verify if color pair satisfies WCAG 2.1 AA (4.5:1 for normal, 3.0:1 for large/UI)
  static bool meetsWcagAA(
    Color foreground,
    Color background, {
    bool isLargeText = false,
  }) {
    final ratio = calculateContrastRatio(foreground, background);
    return ratio >= (isLargeText ? 3.0 : 4.5);
  }

  /// Verify if color pair satisfies WCAG 2.1 AAA (7.0:1 for normal, 4.5:1 for large)
  static bool meetsWcagAAA(
    Color foreground,
    Color background, {
    bool isLargeText = false,
  }) {
    final ratio = calculateContrastRatio(foreground, background);
    return ratio >= (isLargeText ? 4.5 : 7.0);
  }

  /// Wrap download card with comprehensive screen reader semantics
  static Widget wrapDownloadCard({
    required Widget child,
    required String title,
    required String stateDescription,
    required double progressPercent,
    required String speedText,
    required String etaText,
    required VoidCallback onPrimaryAction,
    required VoidCallback onDeleteAction,
    VoidCallback? onOpenFolder,
  }) {
    final percentInt = (progressPercent * 100).toInt();
    final semanticLabel =
        '$title, $stateDescription, $percentInt percent complete, '
        'Speed: $speedText, ETA: $etaText';

    return Semantics(
      label: semanticLabel,
      container: true,
      button: true,
      enabled: true,
      onTap: onPrimaryAction,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Delete or Cancel'): onDeleteAction,
        const CustomSemanticsAction(label: 'Open Containing Folder'):
            ?onOpenFolder,
      },
      child: child,
    );
  }
}

/// Accessible Focus Ring Container Wrapper
class VidraFocusRing extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final VoidCallback? onActivate;

  const VidraFocusRing({
    super.key,
    required this.child,
    this.borderRadius,
    this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = borderRadius ?? BorderRadius.circular(12);

    return FocusableActionDetector(
      onShowFocusHighlight: (focused) {},
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => onActivate?.call(),
        ),
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;

          return Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: isFocused ? colors.primary : Colors.transparent,
                width: 2.0,
              ),
            ),
            child: child,
          );
        },
      ),
    );
  }
}

/// Global Keyboard Shortcut Listener for Desktop Workstations
class VidraGlobalShortcuts extends StatelessWidget {
  final Widget child;
  final VoidCallback onFocusOmniBar;
  final VoidCallback onQuickPaste;
  final VoidCallback onOpenSettings;

  const VidraGlobalShortcuts({
    super.key,
    required this.child,
    required this.onFocusOmniBar,
    required this.onQuickPaste,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Ctrl+K / Cmd+K -> Focus Search
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyK,
        ): const _FocusSearchIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.keyK,
        ): const _FocusSearchIntent(),

        // Ctrl+V / Cmd+V -> Quick Paste
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyV,
        ): const _QuickPasteIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.keyV,
        ): const _QuickPasteIntent(),

        // Ctrl+, -> Settings
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.comma,
        ): const _SettingsIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.comma,
        ): const _SettingsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) => onFocusOmniBar(),
          ),
          _QuickPasteIntent: CallbackAction<_QuickPasteIntent>(
            onInvoke: (_) => onQuickPaste(),
          ),
          _SettingsIntent: CallbackAction<_SettingsIntent>(
            onInvoke: (_) => onOpenSettings(),
          ),
        },
        child: FocusScope(
          autofocus: true,
          child: child,
        ),
      ),
    );
  }
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _QuickPasteIntent extends Intent {
  const _QuickPasteIntent();
}

class _SettingsIntent extends Intent {
  const _SettingsIntent();
}
