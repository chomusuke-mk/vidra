import 'package:flutter/material.dart';
import 'colors.dart';
import 'typography.dart';

/// Vidra Master Theme Configuration
/// Provides lightTheme, darkTheme, and oledTheme with Material 3 semantic containers,
/// typography scales, semantic color extensions, and standardized component themes.
abstract class AppTheme {
  /// Build Standard Light Theme
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primarySeed,
      brightness: Brightness.light,
      surface: AppColors.lightCanvas,
      surfaceContainerLowest: AppColors.lightSurfaceLowest,
      surfaceContainerLow: AppColors.lightSurfaceLow,
      surfaceContainer: AppColors.lightSurface,
      surfaceContainerHigh: AppColors.lightSurfaceHigh,
      surfaceContainerHighest: AppColors.lightSurfaceHighest,
      onSurface: const Color(0xFF0F172A),
      onSurfaceVariant: const Color(0xFF475569),
      outline: AppColors.borderLight,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      semanticColors: VidraSemanticColors.light,
      isLight: true,
    );
  }

  /// Build Standard Dark Theme
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primarySeed,
      brightness: Brightness.dark,
      surface: AppColors.darkCanvas,
      surfaceContainerLowest: AppColors.darkSurfaceLowest,
      surfaceContainerLow: AppColors.darkSurfaceLow,
      surfaceContainer: AppColors.darkSurface,
      surfaceContainerHigh: AppColors.darkSurfaceHigh,
      surfaceContainerHighest: AppColors.darkSurfaceHighest,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.borderSubtle,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      semanticColors: VidraSemanticColors.dark,
      isLight: false,
    );
  }

  /// Build True OLED Pure Black Theme (#000000 Canvas)
  static ThemeData get oledTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primarySeed,
      brightness: Brightness.dark,
      surface: AppColors.oledCanvas,
      surfaceContainerLowest: AppColors.oledSurfaceLowest,
      surfaceContainerLow: AppColors.oledSurfaceLow,
      surfaceContainer: AppColors.oledSurface,
      surfaceContainerHigh: AppColors.oledSurfaceHigh,
      surfaceContainerHighest: AppColors.oledSurfaceHighest,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.borderOled,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      semanticColors: VidraSemanticColors.oled,
      isLight: false,
    );
  }

  /// Master Theme Builder
  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required VidraSemanticColors semanticColors,
    required bool isLight,
  }) {
    final textTheme = AppTypography.createTextTheme(colorScheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      extensions: [semanticColors],

      // Component Theme 1: CardThemeData
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: semanticColors.borderSubtle, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // Component Theme 2: DialogThemeData
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: semanticColors.borderSubtle, width: 1),
        ),
        titleTextStyle: textTheme.headlineMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      // Component Theme 3: BottomSheetThemeData
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // Component Theme 4: AppBarTheme
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),

      // Component Theme 5: NavigationRailThemeData
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.primary, size: 24),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant, size: 24),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFamily: AppTypography.fontFamilyPrimary,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontFamily: AppTypography.fontFamilyPrimary,
        ),
      ),

      // Component Theme 6: TabBarThemeData (i18n safe)
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          fontFamily: AppTypography.fontFamilyPrimary,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: AppTypography.fontFamilyPrimary,
        ),
      ),

      // Component Theme 7: SegmentedButtonThemeData
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primary;
            }
            return colorScheme.surfaceContainerHigh;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onPrimary;
            }
            return colorScheme.onSurfaceVariant;
          }),
          textStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: AppTypography.fontFamilyPrimary,
              );
            }
            return const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFamily: AppTypography.fontFamilyPrimary,
            );
          }),
          side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(color: colorScheme.primary, width: 1.5);
            }
            return BorderSide(color: semanticColors.borderSubtle, width: 1);
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),

      // Component Theme 8: ProgressIndicatorThemeData
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),

      // Component Theme 9: InputDecorationTheme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: semanticColors.borderSubtle, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: semanticColors.borderSubtle, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: semanticColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: semanticColors.error, width: 1.5),
        ),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontFamily: AppTypography.fontFamilyPrimary,
        ),
        labelStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontFamily: AppTypography.fontFamilyPrimary,
        ),
        errorStyle: TextStyle(
          color: semanticColors.error,
          fontFamily: AppTypography.fontFamilyPrimary,
        ),
      ),

      // Component Theme 10: TextSelectionThemeData
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.3),
        selectionHandleColor: colorScheme.primary,
      ),

      // Component Theme 11: FilledButtonThemeData
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: AppTypography.fontFamilyPrimary,
          ),
        ),
      ),

      // Component Theme 12: ElevatedButtonThemeData
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.surfaceContainerHigh,
          foregroundColor: colorScheme.primary,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: semanticColors.borderSubtle, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: AppTypography.fontFamilyPrimary,
          ),
        ),
      ),

      // Component Theme 13: OutlinedButtonThemeData
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: semanticColors.borderSubtle, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: AppTypography.fontFamilyPrimary,
          ),
        ),
      ),

      // Component Theme 14: TextButtonThemeData
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: AppTypography.fontFamilyPrimary,
          ),
        ),
      ),

      // Component Theme 15: FloatingActionButtonThemeData
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 3,
        focusElevation: 4,
        hoverElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Component Theme 16: IconButtonThemeData
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          minimumSize: const Size(44, 44),
        ),
      ),

      // Component Theme 17: ChipThemeData
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        disabledColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        selectedColor: colorScheme.primaryContainer,
        secondarySelectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontFamily: AppTypography.fontFamilyPrimary,
        ),
        secondaryLabelStyle: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontFamily: AppTypography.fontFamilyPrimary,
        ),
        side: BorderSide(color: semanticColors.borderSubtle, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // Global Divider Theme
      dividerTheme: DividerThemeData(
        color: semanticColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
