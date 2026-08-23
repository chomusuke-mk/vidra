import 'package:flutter/material.dart';

/// Vidra Master Typography System
/// Standardizes Material 3 TextTheme and Monospace Tabular Telemetry tokens.
abstract class AppTypography {
  // Font Families
  static const String fontFamilyPrimary = 'Inter';
  static const String fontFamilyMonospace = 'JetBrainsMono';

  static const List<String> primaryFallback = [
    '-apple-system',
    'BlinkMacSystemFont',
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  static const List<String> monospaceFallback = [
    'Roboto Mono',
    'Menlo',
    'Monaco',
    'Consolas',
    'Liberation Mono',
    'monospace',
  ];

  // Font Features for Anti-Jitter Telemetry
  static const List<FontFeature> telemetryFeatures = [
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  /// Material 3 Standardized 15-Tier TextTheme Builder
  static TextTheme createTextTheme([Color? textColor]) {
    final color = textColor ?? const Color(0xFFF1F5F9);

    return TextTheme(
      // Display Scale
      displayLarge: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 57.0,
        fontWeight: FontWeight.w400,
        height: 1.12,
        letterSpacing: -0.25,
        color: color,
      ),
      displayMedium: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 45.0,
        fontWeight: FontWeight.w400,
        height: 1.16,
        letterSpacing: 0.0,
        color: color,
      ),
      displaySmall: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 36.0,
        fontWeight: FontWeight.w400,
        height: 1.22,
        letterSpacing: 0.0,
        color: color,
      ),

      // Headline Scale
      headlineLarge: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 32.0,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0.0,
        color: color,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 28.0,
        fontWeight: FontWeight.w600,
        height: 1.29,
        letterSpacing: 0.0,
        color: color,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 24.0,
        fontWeight: FontWeight.w600,
        height: 1.33,
        letterSpacing: 0.0,
        color: color,
      ),

      // Title Scale
      titleLarge: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 22.0,
        fontWeight: FontWeight.w600,
        height: 1.27,
        letterSpacing: 0.0,
        color: color,
      ),
      titleMedium: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 16.0,
        fontWeight: FontWeight.w600,
        height: 1.25, // Tight leading to prevent card ballooning on 2 lines
        letterSpacing: 0.15,
        color: color,
      ),
      titleSmall: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 14.0,
        fontWeight: FontWeight.w600,
        height: 1.29,
        letterSpacing: 0.10,
        color: color,
      ),

      // Body Scale
      bodyLarge: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 16.0,
        fontWeight: FontWeight.w400,
        height: 1.50,
        letterSpacing: 0.50,
        color: color,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 14.0,
        fontWeight: FontWeight.w400,
        height: 1.43,
        letterSpacing: 0.25,
        color: color,
      ),
      bodySmall: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 12.0,
        fontWeight: FontWeight.w400,
        height: 1.33,
        letterSpacing: 0.40,
        color: color.withValues(alpha: 0.75),
      ),

      // Label Scale
      labelLarge: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 14.0,
        fontWeight: FontWeight.w600,
        height: 1.43,
        letterSpacing: 0.10,
        color: color,
      ),
      labelMedium: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 12.0,
        fontWeight: FontWeight.w500,
        height: 1.33,
        letterSpacing: 0.50,
        color: color,
      ),
      labelSmall: TextStyle(
        fontFamily: fontFamilyPrimary,
        fontFamilyFallback: primaryFallback,
        fontSize: 10.0,
        fontWeight: FontWeight.w700,
        height: 1.20,
        letterSpacing: 0.50,
        color: color,
      ),
    );
  }

  // ===========================================================================
  // MONOSPACE TABULAR TELEMETRY TOKENS
  // ===========================================================================

  /// Hero Speed Throughput (e.g. "48.2 MB/s" in Steam Hero Card)
  static TextStyle telemetryHero({Color? color}) => TextStyle(
        fontFamily: fontFamilyMonospace,
        fontFamilyFallback: monospaceFallback,
        fontSize: 24.0,
        fontWeight: FontWeight.w700,
        height: 1.20,
        letterSpacing: -0.5,
        fontFeatures: telemetryFeatures,
        color: color,
      );

  /// Status Footer Throughput (e.g. "↓ 18.4 MB/s • ↑ 1.2 MB/s" in Desktop Footer)
  static TextStyle telemetryLarge({Color? color}) => TextStyle(
        fontFamily: fontFamilyMonospace,
        fontFamilyFallback: monospaceFallback,
        fontSize: 16.0,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0.0,
        fontFeatures: telemetryFeatures,
        color: color,
      );

  /// Card Progress Subtitle (e.g. "142.5 MB / 1.80 GB")
  static TextStyle telemetryMedium({Color? color}) => TextStyle(
        fontFamily: fontFamilyMonospace,
        fontFamilyFallback: monospaceFallback,
        fontSize: 13.0,
        fontWeight: FontWeight.w500,
        height: 1.30,
        letterSpacing: 0.0,
        fontFeatures: telemetryFeatures,
        color: color,
      );

  /// Card Telemetry Row (e.g. "ETA 00:04:12 • 8 Conns")
  static TextStyle telemetrySmall({Color? color}) => TextStyle(
        fontFamily: fontFamilyMonospace,
        fontFamilyFallback: monospaceFallback,
        fontSize: 11.0,
        fontWeight: FontWeight.w500,
        height: 1.27,
        letterSpacing: 0.0,
        fontFeatures: telemetryFeatures,
        color: color,
      );

  /// Compact Table / Duration Badge (e.g. "98.4%", "14:20")
  static TextStyle telemetryMicro({Color? color}) => TextStyle(
        fontFamily: fontFamilyMonospace,
        fontFamilyFallback: monospaceFallback,
        fontSize: 10.0,
        fontWeight: FontWeight.w700,
        height: 1.20,
        letterSpacing: 0.2,
        fontFeatures: telemetryFeatures,
        color: color,
      );

  /// Terminal / yt-dlp Console Drawer Output
  static TextStyle consoleLog({Color? color}) => TextStyle(
        fontFamily: fontFamilyMonospace,
        fontFamilyFallback: monospaceFallback,
        fontSize: 12.0,
        fontWeight: FontWeight.w400,
        height: 1.40,
        letterSpacing: 0.0,
        color: color,
      );
}

/// Extension for convenient context-based typography access
extension VidraTypographyContext on BuildContext {
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get _colors => Theme.of(this).colorScheme;

  // High-frequency widget convenience getters
  TextStyle get cardTitle => textTheme.titleMedium!;
  TextStyle get cardSubtitle => textTheme.bodySmall!;
  TextStyle get formatPill => textTheme.labelMedium!;
  TextStyle get thumbnailDuration => textTheme.labelSmall!;
  TextStyle get speedTelemetry => AppTypography.telemetrySmall(color: _colors.primary);

  // Dynamic Telemetry Tokens (WCAG AA/AAA Verified across Light, Dark, OLED)
  TextStyle get telemetryHero => AppTypography.telemetryHero(color: _colors.onSurface);
  TextStyle get telemetryLarge => AppTypography.telemetryLarge(color: _colors.onSurface);
  TextStyle get telemetryMedium => AppTypography.telemetryMedium(color: _colors.onSurfaceVariant);
  TextStyle get telemetrySmall => AppTypography.telemetrySmall(color: _colors.onSurfaceVariant);
  TextStyle get telemetryMicro => AppTypography.telemetryMicro(color: _colors.onSurfaceVariant);
  TextStyle get consoleLog => AppTypography.consoleLog(color: _colors.onSurface);
}
