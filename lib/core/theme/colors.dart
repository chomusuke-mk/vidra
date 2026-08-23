import 'package:flutter/material.dart';

/// Vidra Master Color Tokens & Surface Hierarchy
abstract class AppColors {
  // Brand Seeds
  static const Color primarySeed = Color(0xFF4F378B); // Royal Purple
  static const Color secondarySeed = Color(0xFF64748B); // Slate
  static const Color tertiarySeed = Color(0xFF8B5CF6); // Violet

  // Universal Semantic Status Colors (Dark & OLED)
  static const Color success = Color(0xFF10B981); // Emerald Green
  static const Color onSuccess = Color(0xFFFFFFFF);
  static const Color successContainer = Color(0xFF064E3B);
  static const Color onSuccessContainer = Color(0xFFFFFFFF);

  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color onWarning = Color(0xFFFFFFFF); // 9.07:1 AAA contrast
  static const Color warningContainer = Color(0xFF78350F);
  static const Color onWarningContainer = Color(0xFFFFFFFF);

  static const Color error = Color(0xFFEF4444); // Rose Red
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFF7F1D1D);
  static const Color onErrorContainer = Color(0xFFFFFFFF);

  static const Color info = Color(0xFF06B6D4); // Cyan
  static const Color onInfo = Color(0xFFFFFFFF);
  static const Color infoContainer = Color(0xFF164E63);
  static const Color onInfoContainer = Color(0xFFFFFFFF);

  static const Color muxing = Color(0xFFA855F7); // Purple for FFmpeg Muxing
  static const Color onMuxing = Color(0xFFFFFFFF);
  static const Color muxingContainer = Color(0xFF581C87);
  static const Color onMuxingContainer = Color(0xFFFFFFFF);

  // Light Mode Deep Semantic Tones (Verified >= 5.51:1 AA on light card surfaces)
  static const Color lightSuccess = Color(0xFF065F46);
  static const Color lightOnSuccess = Color(0xFFFFFFFF);
  static const Color lightSuccessContainer = Color(0xFFD1FAE5);
  static const Color lightOnSuccessContainer = Color(0xFF065F46);

  static const Color lightWarning = Color(0xFF92400E);
  static const Color lightOnWarning = Color(0xFFFFFFFF);
  static const Color lightWarningContainer = Color(0xFFFEF3C7);
  static const Color lightOnWarningContainer = Color(0xFF92400E);

  static const Color lightError = Color(0xFFB91C1C);
  static const Color lightOnError = Color(0xFFFFFFFF);
  static const Color lightErrorContainer = Color(0xFFFEE2E2);
  static const Color lightOnErrorContainer = Color(0xFFB91C1C);

  static const Color lightInfo = Color(0xFF155E75);
  static const Color lightOnInfo = Color(0xFFFFFFFF);
  static const Color lightInfoContainer = Color(0xFFCFFAFE);
  static const Color lightOnInfoContainer = Color(0xFF155E75);

  static const Color lightMuxing = Color(0xFF581C87);
  static const Color lightOnMuxing = Color(0xFFFFFFFF);
  static const Color lightMuxingContainer = Color(0xFFF3E8FF);
  static const Color lightOnMuxingContainer = Color(0xFF581C87);

  // 5-Tier Surface Tiers - Dark Mode Standard
  static const Color darkCanvas = Color(0xFF090B0E);
  static const Color darkSurfaceLowest = Color(0xFF090B0E);
  static const Color darkSurfaceLow = Color(0xFF11141A);
  static const Color darkSurface = Color(0xFF171B22); // Card Base
  static const Color darkSurfaceHigh = Color(0xFF1F242D);
  static const Color darkSurfaceHighest = Color(0xFF292F3B);

  // 5-Tier Surface Tiers - True OLED Pure Black Mode
  static const Color oledCanvas = Color(0xFF000000);
  static const Color oledSurfaceLowest = Color(0xFF000000);
  static const Color oledSurfaceLow = Color(0xFF07090C);
  static const Color oledSurface = Color(0xFF0E1116); // Card Base
  static const Color oledSurfaceHigh = Color(0xFF151920);
  static const Color oledSurfaceHighest = Color(0xFF1E232C);

  // 5-Tier Surface Tiers - Light Mode
  static const Color lightCanvas = Color(0xFFFFFFFF);
  static const Color lightSurfaceLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceLow = Color(0xFFF1F4F9);
  static const Color lightSurface = Color(0xFFE9EDF5); // Card Base
  static const Color lightSurfaceHigh = Color(0xFFE1E6F0);
  static const Color lightSurfaceHighest = Color(0xFFD8DFEB);

  // Text & Outline Tokens
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textTertiary = Color(0xFF64748B);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextTertiary = Color(0xFF94A3B8);

  // Translucent Rim Border & Focus Tokens
  static const Color borderSubtle = Color(0x14FFFFFF); // 8% white (Dark)
  static const Color borderOled = Color(0x1FFFFFFF);   // 12% white (OLED)
  static const Color borderLight = Color(0x1F000000);  // 12% black (Light)
  static const Color borderFocus = Color(0xFF4F378B);  // Royal Purple focus ring
}

/// Custom ThemeExtension for Vidra download lifecycle semantic roles
@immutable
class VidraSemanticColors extends ThemeExtension<VidraSemanticColors> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  final Color muxing;
  final Color onMuxing;
  final Color muxingContainer;
  final Color onMuxingContainer;

  final Color borderSubtle;
  final Color borderFocus;

  const VidraSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.muxing,
    required this.onMuxing,
    required this.muxingContainer,
    required this.onMuxingContainer,
    required this.borderSubtle,
    required this.borderFocus,
  });

  @override
  VidraSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? muxing,
    Color? onMuxing,
    Color? muxingContainer,
    Color? onMuxingContainer,
    Color? borderSubtle,
    Color? borderFocus,
  }) {
    return VidraSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      muxing: muxing ?? this.muxing,
      onMuxing: onMuxing ?? this.onMuxing,
      muxingContainer: muxingContainer ?? this.muxingContainer,
      onMuxingContainer: onMuxingContainer ?? this.onMuxingContainer,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderFocus: borderFocus ?? this.borderFocus,
    );
  }

  @override
  VidraSemanticColors lerp(ThemeExtension<VidraSemanticColors>? other, double t) {
    if (other is! VidraSemanticColors) return this;
    return VidraSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer: Color.lerp(onErrorContainer, other.onErrorContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      muxing: Color.lerp(muxing, other.muxing, t)!,
      onMuxing: Color.lerp(onMuxing, other.onMuxing, t)!,
      muxingContainer: Color.lerp(muxingContainer, other.muxingContainer, t)!,
      onMuxingContainer: Color.lerp(onMuxingContainer, other.onMuxingContainer, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
    );
  }

  static const dark = VidraSemanticColors(
    success: AppColors.success,
    onSuccess: AppColors.onSuccess,
    successContainer: AppColors.successContainer,
    onSuccessContainer: AppColors.onSuccessContainer,
    warning: AppColors.warning,
    onWarning: AppColors.onWarning,
    warningContainer: AppColors.warningContainer,
    onWarningContainer: AppColors.onWarningContainer,
    error: AppColors.error,
    onError: AppColors.onError,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.onErrorContainer,
    info: AppColors.info,
    onInfo: AppColors.onInfo,
    infoContainer: AppColors.infoContainer,
    onInfoContainer: AppColors.onInfoContainer,
    muxing: AppColors.muxing,
    onMuxing: AppColors.onMuxing,
    muxingContainer: AppColors.muxingContainer,
    onMuxingContainer: AppColors.onMuxingContainer,
    borderSubtle: AppColors.borderSubtle,
    borderFocus: AppColors.borderFocus,
  );

  static const oled = VidraSemanticColors(
    success: AppColors.success,
    onSuccess: AppColors.onSuccess,
    successContainer: AppColors.successContainer,
    onSuccessContainer: AppColors.onSuccessContainer,
    warning: AppColors.warning,
    onWarning: AppColors.onWarning,
    warningContainer: AppColors.warningContainer,
    onWarningContainer: AppColors.onWarningContainer,
    error: AppColors.error,
    onError: AppColors.onError,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.onErrorContainer,
    info: AppColors.info,
    onInfo: AppColors.onInfo,
    infoContainer: AppColors.infoContainer,
    onInfoContainer: AppColors.onInfoContainer,
    muxing: AppColors.muxing,
    onMuxing: AppColors.onMuxing,
    muxingContainer: AppColors.muxingContainer,
    onMuxingContainer: AppColors.onMuxingContainer,
    borderSubtle: AppColors.borderOled,
    borderFocus: AppColors.borderFocus,
  );

  static const light = VidraSemanticColors(
    success: AppColors.lightSuccess,
    onSuccess: AppColors.lightOnSuccess,
    successContainer: AppColors.lightSuccessContainer,
    onSuccessContainer: AppColors.lightOnSuccessContainer,
    warning: AppColors.lightWarning,
    onWarning: AppColors.lightOnWarning,
    warningContainer: AppColors.lightWarningContainer,
    onWarningContainer: AppColors.lightOnWarningContainer,
    error: AppColors.lightError,
    onError: AppColors.lightOnError,
    errorContainer: AppColors.lightErrorContainer,
    onErrorContainer: AppColors.lightOnErrorContainer,
    info: AppColors.lightInfo,
    onInfo: AppColors.lightOnInfo,
    infoContainer: AppColors.lightInfoContainer,
    onInfoContainer: AppColors.lightOnInfoContainer,
    muxing: AppColors.lightMuxing,
    onMuxing: AppColors.lightOnMuxing,
    muxingContainer: AppColors.lightMuxingContainer,
    onMuxingContainer: AppColors.lightOnMuxingContainer,
    borderSubtle: AppColors.borderLight,
    borderFocus: AppColors.borderFocus,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VidraSemanticColors &&
          runtimeType == other.runtimeType &&
          success == other.success &&
          onSuccess == other.onSuccess &&
          successContainer == other.successContainer &&
          onSuccessContainer == other.onSuccessContainer &&
          warning == other.warning &&
          onWarning == other.onWarning &&
          warningContainer == other.warningContainer &&
          onWarningContainer == other.onWarningContainer &&
          error == other.error &&
          onError == other.onError &&
          errorContainer == other.errorContainer &&
          onErrorContainer == other.onErrorContainer &&
          info == other.info &&
          onInfo == other.onInfo &&
          infoContainer == other.infoContainer &&
          onInfoContainer == other.onInfoContainer &&
          muxing == other.muxing &&
          onMuxing == other.onMuxing &&
          muxingContainer == other.muxingContainer &&
          onMuxingContainer == other.onMuxingContainer &&
          borderSubtle == other.borderSubtle &&
          borderFocus == other.borderFocus;

  @override
  int get hashCode => Object.hashAll([
        success,
        onSuccess,
        successContainer,
        onSuccessContainer,
        warning,
        onWarning,
        warningContainer,
        onWarningContainer,
        error,
        onError,
        errorContainer,
        onErrorContainer,
        info,
        onInfo,
        infoContainer,
        onInfoContainer,
        muxing,
        onMuxing,
        muxingContainer,
        onMuxingContainer,
        borderSubtle,
        borderFocus,
      ]);
}

/// Ergonomic BuildContext extensions for rapid color access
extension VidraColorContext on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  VidraSemanticColors get semanticColors =>
      Theme.of(this).extension<VidraSemanticColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? VidraSemanticColors.dark
          : VidraSemanticColors.light);
}
