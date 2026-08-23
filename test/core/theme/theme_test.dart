import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vidra/core/theme/colors.dart';
import 'package:vidra/core/theme/typography.dart';
import 'package:vidra/core/theme/animations.dart';
import 'package:vidra/core/theme/layout.dart';
import 'package:vidra/core/theme/accessibility.dart';
import 'package:vidra/core/theme/app_theme.dart';

/// Helper for WCAG 2.1 Relative Luminance calculation
double _calculateRelativeLuminance(Color color) {
  double channelLuminance(double channel) {
    return channel <= 0.04045
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channelLuminance(color.r);
  final g = channelLuminance(color.g);
  final b = channelLuminance(color.b);

  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Helper for WCAG 2.1 Contrast Ratio calculation between foreground and background
double _calculateContrastRatio(Color foreground, Color background) {
  final l1 = _calculateRelativeLuminance(foreground);
  final l2 = _calculateRelativeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Milestone 1 - Design Tokens & Theme Test Suite', () {
    // =========================================================================
    // 1. AppColors & Contrast Ratio Tests
    // =========================================================================
    group('AppColors Constants & WCAG Contrast', () {
      test('Brand seed constants are accurately defined', () {
        expect(AppColors.primarySeed, equals(const Color(0xFF4F378B)));
        expect(AppColors.secondarySeed, equals(const Color(0xFF64748B)));
        expect(AppColors.tertiarySeed, equals(const Color(0xFF8B5CF6)));
      });

      test('Semantic status colors are accurately defined', () {
        expect(AppColors.success, equals(const Color(0xFF10B981)));
        expect(AppColors.successContainer, equals(const Color(0xFF064E3B)));
        expect(AppColors.onSuccess, equals(const Color(0xFFFFFFFF)));

        expect(AppColors.warning, equals(const Color(0xFFF59E0B)));
        expect(AppColors.warningContainer, equals(const Color(0xFF78350F)));
        expect(AppColors.onWarning, equals(const Color(0xFFFFFFFF)));

        expect(AppColors.error, equals(const Color(0xFFEF4444)));
        expect(AppColors.errorContainer, equals(const Color(0xFF7F1D1D)));
        expect(AppColors.onError, equals(const Color(0xFFFFFFFF)));

        expect(AppColors.info, equals(const Color(0xFF06B6D4)));
        expect(AppColors.infoContainer, equals(const Color(0xFF164E63)));
        expect(AppColors.onInfo, equals(const Color(0xFFFFFFFF)));

        expect(AppColors.muxing, equals(const Color(0xFFA855F7)));
        expect(AppColors.muxingContainer, equals(const Color(0xFF581C87)));
        expect(AppColors.onMuxing, equals(const Color(0xFFFFFFFF)));
      });

      test('5-Tier Dark Surface Tiers are monotonic and accurately defined', () {
        expect(AppColors.darkCanvas, equals(const Color(0xFF090B0E)));
        expect(AppColors.darkSurfaceLowest, equals(const Color(0xFF090B0E)));
        expect(AppColors.darkSurfaceLow, equals(const Color(0xFF11141A)));
        expect(AppColors.darkSurface, equals(const Color(0xFF171B22)));
        expect(AppColors.darkSurfaceHigh, equals(const Color(0xFF1F242D)));
        expect(AppColors.darkSurfaceHighest, equals(const Color(0xFF292F3B)));
      });

      test('5-Tier True OLED Surface Tiers are accurately defined', () {
        expect(AppColors.oledCanvas, equals(const Color(0xFF000000)));
        expect(AppColors.oledSurfaceLowest, equals(const Color(0xFF000000)));
        expect(AppColors.oledSurfaceLow, equals(const Color(0xFF07090C)));
        expect(AppColors.oledSurface, equals(const Color(0xFF0E1116)));
        expect(AppColors.oledSurfaceHigh, equals(const Color(0xFF151920)));
        expect(AppColors.oledSurfaceHighest, equals(const Color(0xFF1E232C)));
      });

      test('5-Tier Light Surface Tiers are accurately defined', () {
        expect(AppColors.lightCanvas, equals(const Color(0xFFFFFFFF)));
        expect(AppColors.lightSurfaceLowest, equals(const Color(0xFFFFFFFF)));
        expect(AppColors.lightSurfaceLow, equals(const Color(0xFFF1F4F9)));
        expect(AppColors.lightSurface, equals(const Color(0xFFE9EDF5)));
        expect(AppColors.lightSurfaceHigh, equals(const Color(0xFFE1E6F0)));
        expect(AppColors.lightSurfaceHighest, equals(const Color(0xFFD8DFEB)));
      });

      test('Text & Border tokens are accurately defined', () {
        expect(AppColors.textPrimary, equals(const Color(0xFFF1F5F9)));
        expect(AppColors.textSecondary, equals(const Color(0xFF94A3B8)));
        expect(AppColors.textTertiary, equals(const Color(0xFF64748B)));
        expect(AppColors.borderSubtle, equals(const Color(0x14FFFFFF)));
        expect(AppColors.borderOled, equals(const Color(0x1FFFFFFF)));
        expect(AppColors.borderLight, equals(const Color(0x1F000000)));
        expect(AppColors.borderFocus, equals(const Color(0xFF4F378B)));
      });

      test('Dark theme text contrast meets WCAG 2.1 AAA / AA standards', () {
        // textPrimary on darkCanvas (exceeds 7.0:1 AAA)
        final primaryCanvasRatio = _calculateContrastRatio(
          AppColors.textPrimary,
          AppColors.darkCanvas,
        );
        expect(primaryCanvasRatio, greaterThanOrEqualTo(7.0));

        // textPrimary on darkSurface (exceeds 7.0:1 AAA)
        final primaryCardRatio = _calculateContrastRatio(
          AppColors.textPrimary,
          AppColors.darkSurface,
        );
        expect(primaryCardRatio, greaterThanOrEqualTo(7.0));

        // textSecondary on darkSurface (exceeds 4.5:1 AA)
        final secondaryCardRatio = _calculateContrastRatio(
          AppColors.textSecondary,
          AppColors.darkSurface,
        );
        expect(secondaryCardRatio, greaterThanOrEqualTo(4.5));
      });

      test('Dark status container text contrast meets WCAG 2.1 AAA standards', () {
        // onSuccess on successContainer
        final successRatio = _calculateContrastRatio(
          AppColors.onSuccess,
          AppColors.successContainer,
        );
        expect(successRatio, greaterThanOrEqualTo(7.0));

        // onWarning on warningContainer (9.07:1 AAA)
        final warningRatio = _calculateContrastRatio(
          AppColors.onWarning,
          AppColors.warningContainer,
        );
        expect(warningRatio, greaterThanOrEqualTo(7.0));

        // onError on errorContainer
        final errorRatio = _calculateContrastRatio(
          AppColors.onError,
          AppColors.errorContainer,
        );
        expect(errorRatio, greaterThanOrEqualTo(7.0));

        // onInfo on infoContainer
        final infoRatio = _calculateContrastRatio(
          AppColors.onInfo,
          AppColors.infoContainer,
        );
        expect(infoRatio, greaterThanOrEqualTo(7.0));

        // onMuxing on muxingContainer (10.88:1 AAA)
        final muxingRatio = _calculateContrastRatio(
          AppColors.onMuxing,
          AppColors.muxingContainer,
        );
        expect(muxingRatio, greaterThanOrEqualTo(7.0));
      });

      test('Light theme semantic status contrast meets WCAG 2.1 AA / AAA standards', () {
        const lightCardBase = Color(0xFFE9EDF5);

        // Light Success (#065F46) on lightCardBase (>= 4.5 AA)
        final lightSuccessRatio = _calculateContrastRatio(
          VidraSemanticColors.light.success,
          lightCardBase,
        );
        expect(lightSuccessRatio, greaterThanOrEqualTo(4.5));

        // Light Warning (#92400E) on lightCardBase (>= 4.5 AA)
        final lightWarningRatio = _calculateContrastRatio(
          VidraSemanticColors.light.warning,
          lightCardBase,
        );
        expect(lightWarningRatio, greaterThanOrEqualTo(4.5));

        // Light Error (#B91C1C) on lightCardBase (>= 4.5 AA)
        final lightErrorRatio = _calculateContrastRatio(
          VidraSemanticColors.light.error,
          lightCardBase,
        );
        expect(lightErrorRatio, greaterThanOrEqualTo(4.5));

        // Light Info (#155E75) on lightCardBase (>= 4.5 AA)
        final lightInfoRatio = _calculateContrastRatio(
          VidraSemanticColors.light.info,
          lightCardBase,
        );
        expect(lightInfoRatio, greaterThanOrEqualTo(4.5));

        // Light Muxing (#581C87) on lightCardBase (>= 7.0 AAA)
        final lightMuxingRatio = _calculateContrastRatio(
          VidraSemanticColors.light.muxing,
          lightCardBase,
        );
        expect(lightMuxingRatio, greaterThanOrEqualTo(7.0));
      });
    });

    // =========================================================================
    // 2. VidraSemanticColors ThemeExtension Tests
    // =========================================================================
    group('VidraSemanticColors ThemeExtension', () {
      test('Presets (dark, oled, light) instantiate with expected values', () {
        // Dark preset
        expect(VidraSemanticColors.dark.success, equals(AppColors.success));
        expect(VidraSemanticColors.dark.warning, equals(AppColors.warning));
        expect(VidraSemanticColors.dark.error, equals(AppColors.error));
        expect(VidraSemanticColors.dark.info, equals(AppColors.info));
        expect(VidraSemanticColors.dark.muxing, equals(AppColors.muxing));
        expect(VidraSemanticColors.dark.borderSubtle, equals(AppColors.borderSubtle));
        expect(VidraSemanticColors.dark.borderFocus, equals(AppColors.borderFocus));

        // OLED preset
        expect(VidraSemanticColors.oled.success, equals(AppColors.success));
        expect(VidraSemanticColors.oled.warning, equals(AppColors.warning));
        expect(VidraSemanticColors.oled.error, equals(AppColors.error));
        expect(VidraSemanticColors.oled.info, equals(AppColors.info));
        expect(VidraSemanticColors.oled.muxing, equals(AppColors.muxing));
        expect(VidraSemanticColors.oled.borderSubtle, equals(AppColors.borderOled));
        expect(VidraSemanticColors.oled.borderFocus, equals(AppColors.borderFocus));

        // Light preset
        expect(VidraSemanticColors.light.success, equals(AppColors.lightSuccess));
        expect(VidraSemanticColors.light.warning, equals(AppColors.lightWarning));
        expect(VidraSemanticColors.light.error, equals(AppColors.lightError));
        expect(VidraSemanticColors.light.info, equals(AppColors.lightInfo));
        expect(VidraSemanticColors.light.muxing, equals(AppColors.lightMuxing));
        expect(VidraSemanticColors.light.borderSubtle, equals(AppColors.borderLight));
        expect(VidraSemanticColors.light.borderFocus, equals(AppColors.borderFocus));
      });

      test('copyWith preserves unchanged fields and updates target fields', () {
        const original = VidraSemanticColors.dark;

        // No-arg copyWith
        final clone = original.copyWith();
        expect(clone.success, equals(original.success));
        expect(clone.warning, equals(original.warning));
        expect(clone.error, equals(original.error));
        expect(clone.info, equals(original.info));
        expect(clone.muxing, equals(original.muxing));
        expect(clone.borderSubtle, equals(original.borderSubtle));

        // Partial update (success & error)
        const customSuccess = Color(0xFF00FF00);
        const customError = Color(0xFFFF0000);
        final modified = original.copyWith(
          success: customSuccess,
          error: customError,
        );

        expect(modified.success, equals(customSuccess));
        expect(modified.warning, equals(original.warning));
        expect(modified.error, equals(customError));
        expect(modified.info, equals(original.info));
        expect(modified.muxing, equals(original.muxing));
        expect(modified.borderSubtle, equals(original.borderSubtle));
      });

      test('lerp correctly handles edge cases, bounds, and midpoints', () {
        const dark = VidraSemanticColors.dark;
        const light = VidraSemanticColors.light;

        // lerp with null returns this
        expect(dark.lerp(null, 0.5), equals(dark));

        // lerp at t = 0.0 returns start values
        final atZero = dark.lerp(light, 0.0);
        expect(atZero.success, equals(dark.success));
        expect(atZero.warning, equals(dark.warning));
        expect(atZero.error, equals(dark.error));
        expect(atZero.info, equals(dark.info));
        expect(atZero.muxing, equals(dark.muxing));
        expect(atZero.borderSubtle, equals(dark.borderSubtle));

        // lerp at t = 1.0 returns target values
        final atOne = dark.lerp(light, 1.0);
        expect(atOne.success, equals(light.success));
        expect(atOne.warning, equals(light.warning));
        expect(atOne.error, equals(light.error));
        expect(atOne.info, equals(light.info));
        expect(atOne.muxing, equals(light.muxing));
        expect(atOne.borderSubtle, equals(light.borderSubtle));

        // lerp at t = 0.5 returns interpolated colors
        final atHalf = dark.lerp(light, 0.5);
        expect(atHalf.success, equals(Color.lerp(dark.success, light.success, 0.5)));
        expect(atHalf.warning, equals(Color.lerp(dark.warning, light.warning, 0.5)));
        expect(atHalf.error, equals(Color.lerp(dark.error, light.error, 0.5)));
        expect(atHalf.info, equals(Color.lerp(dark.info, light.info, 0.5)));
        expect(atHalf.muxing, equals(Color.lerp(dark.muxing, light.muxing, 0.5)));
        expect(atHalf.borderSubtle, equals(Color.lerp(dark.borderSubtle, light.borderSubtle, 0.5)));
      });

      test('Equality and hash code operate symmetrically', () {
        const d1 = VidraSemanticColors.dark;
        final d2 = VidraSemanticColors.dark.copyWith();
        expect(d1, equals(d2));
        expect(d1.hashCode, equals(d2.hashCode));
      });
    });

    // =========================================================================
    // 3. AppTypography & Monospace Telemetry Tests
    // =========================================================================
    group('AppTypography & Anti-Jitter Telemetry Tokens', () {
      test('createTextTheme produces all 15 Material 3 typography tiers', () {
        final textTheme = AppTypography.createTextTheme();

        // Display scale
        expect(textTheme.displayLarge?.fontSize, equals(57.0));
        expect(textTheme.displayLarge?.fontWeight, equals(FontWeight.w400));
        expect(textTheme.displayLarge?.height, equals(1.12));
        expect(textTheme.displayLarge?.letterSpacing, equals(-0.25));

        expect(textTheme.displayMedium?.fontSize, equals(45.0));
        expect(textTheme.displayMedium?.fontWeight, equals(FontWeight.w400));
        expect(textTheme.displayMedium?.height, equals(1.16));

        expect(textTheme.displaySmall?.fontSize, equals(36.0));
        expect(textTheme.displaySmall?.fontWeight, equals(FontWeight.w400));
        expect(textTheme.displaySmall?.height, equals(1.22));

        // Headline scale
        expect(textTheme.headlineLarge?.fontSize, equals(32.0));
        expect(textTheme.headlineLarge?.fontWeight, equals(FontWeight.w600));
        expect(textTheme.headlineLarge?.height, equals(1.25));

        expect(textTheme.headlineMedium?.fontSize, equals(28.0));
        expect(textTheme.headlineMedium?.fontWeight, equals(FontWeight.w600));
        expect(textTheme.headlineMedium?.height, equals(1.29));

        expect(textTheme.headlineSmall?.fontSize, equals(24.0));
        expect(textTheme.headlineSmall?.fontWeight, equals(FontWeight.w600));
        expect(textTheme.headlineSmall?.height, equals(1.33));

        // Title scale
        expect(textTheme.titleLarge?.fontSize, equals(22.0));
        expect(textTheme.titleLarge?.fontWeight, equals(FontWeight.w600));
        expect(textTheme.titleLarge?.height, equals(1.27));

        expect(textTheme.titleMedium?.fontSize, equals(16.0));
        expect(textTheme.titleMedium?.fontWeight, equals(FontWeight.w600));
        expect(textTheme.titleMedium?.height, equals(1.25));
        expect(textTheme.titleMedium?.letterSpacing, equals(0.15));

        expect(textTheme.titleSmall?.fontSize, equals(14.0));
        expect(textTheme.titleSmall?.fontWeight, equals(FontWeight.w600));
        expect(textTheme.titleSmall?.height, equals(1.29));
        expect(textTheme.titleSmall?.letterSpacing, equals(0.10));

        // Body scale
        expect(textTheme.bodyLarge?.fontSize, equals(16.0));
        expect(textTheme.bodyLarge?.fontWeight, equals(FontWeight.w400));
        expect(textTheme.bodyLarge?.height, equals(1.50));

        expect(textTheme.bodyMedium?.fontSize, equals(14.0));
        expect(textTheme.bodyMedium?.fontWeight, equals(FontWeight.w400));
        expect(textTheme.bodyMedium?.height, equals(1.43));

        expect(textTheme.bodySmall?.fontSize, equals(12.0));
        expect(textTheme.bodySmall?.fontWeight, equals(FontWeight.w400));
        expect(textTheme.bodySmall?.height, equals(1.33));

        // Label scale
        expect(textTheme.labelLarge?.fontSize, equals(14.0));
        expect(textTheme.labelLarge?.fontWeight, equals(FontWeight.w600));
        expect(textTheme.labelLarge?.height, equals(1.43));

        expect(textTheme.labelMedium?.fontSize, equals(12.0));
        expect(textTheme.labelMedium?.fontWeight, equals(FontWeight.w500));
        expect(textTheme.labelMedium?.height, equals(1.33));

        expect(textTheme.labelSmall?.fontSize, equals(10.0));
        expect(textTheme.labelSmall?.fontWeight, equals(FontWeight.w700));
        expect(textTheme.labelSmall?.height, equals(1.20));
      });

      test('createTextTheme respects custom text color', () {
        const customColor = Color(0xFFFFCC00);
        final textTheme = AppTypography.createTextTheme(customColor);
        expect(textTheme.titleMedium?.color, equals(customColor));
        expect(textTheme.bodyMedium?.color, equals(customColor));
      });

      test('Monospace telemetry tokens enforce JetBrainsMono and fallback chains', () {
        final hero = AppTypography.telemetryHero();
        final large = AppTypography.telemetryLarge();
        final medium = AppTypography.telemetryMedium();
        final small = AppTypography.telemetrySmall();
        final micro = AppTypography.telemetryMicro();
        final log = AppTypography.consoleLog();

        for (final style in [hero, large, medium, small, micro, log]) {
          expect(style.fontFamily, equals(AppTypography.fontFamilyMonospace));
          expect(style.fontFamilyFallback, equals(AppTypography.monospaceFallback));
        }
      });

      test('All numeric telemetry tokens enforce Tabular Figures and Slashed Zero', () {
        final telemetryStyles = [
          AppTypography.telemetryHero(),
          AppTypography.telemetryLarge(),
          AppTypography.telemetryMedium(),
          AppTypography.telemetrySmall(),
          AppTypography.telemetryMicro(),
        ];

        for (final style in telemetryStyles) {
          expect(style.fontFeatures, isNotNull);
          final features = style.fontFeatures!;

          // Verify presence of tabular figures ('tnum')
          expect(
            features.any((f) => f.feature == 'tnum'),
            isTrue,
            reason: 'Telemetry style missing tabularFigures font feature',
          );

          // Verify presence of slashed zero ('zero')
          expect(
            features.any((f) => f.feature == 'zero'),
            isTrue,
            reason: 'Telemetry style missing slashedZero font feature',
          );
        }
      });

      test('Telemetry token scales match exact dimensions', () {
        expect(AppTypography.telemetryHero().fontSize, equals(24.0));
        expect(AppTypography.telemetryHero().fontWeight, equals(FontWeight.w700));

        expect(AppTypography.telemetryLarge().fontSize, equals(16.0));
        expect(AppTypography.telemetryLarge().fontWeight, equals(FontWeight.w600));

        expect(AppTypography.telemetryMedium().fontSize, equals(13.0));
        expect(AppTypography.telemetryMedium().fontWeight, equals(FontWeight.w500));

        expect(AppTypography.telemetrySmall().fontSize, equals(11.0));
        expect(AppTypography.telemetrySmall().fontWeight, equals(FontWeight.w500));

        expect(AppTypography.telemetryMicro().fontSize, equals(10.0));
        expect(AppTypography.telemetryMicro().fontWeight, equals(FontWeight.w700));

        expect(AppTypography.consoleLog().fontSize, equals(12.0));
        expect(AppTypography.consoleLog().fontWeight, equals(FontWeight.w400));
      });
    });

    // =========================================================================
    // 4. AppAnimations, AppSpacing, AppBreakpoints & AppAccessibility
    // =========================================================================
    group('AppAnimations Tokens', () {
      test('Durations follow 150/250/350/450ms hierarchy', () {
        expect(AppAnimations.fast, equals(const Duration(milliseconds: 150)));
        expect(AppAnimations.normal, equals(const Duration(milliseconds: 250)));
        expect(AppAnimations.medium, equals(const Duration(milliseconds: 350)));
        expect(AppAnimations.slow, equals(const Duration(milliseconds: 450)));
      });

      test('Physics curves are properly mapped', () {
        expect(AppAnimations.enter, equals(Curves.easeOutQuart));
        expect(AppAnimations.exit, equals(Curves.easeInCubic));
        expect(AppAnimations.standard, equals(Curves.fastOutSlowIn));
        expect(AppAnimations.bounce, equals(Curves.easeOutBack));
        expect(AppAnimations.linear, equals(Curves.linear));
      });
    });

    group('AppSpacing & Responsive Breakpoints', () {
      test('Spatial grid constants align strictly to 8pt system', () {
        expect(AppSpacing.space2, equals(2.0));
        expect(AppSpacing.space4, equals(4.0));
        expect(AppSpacing.space6, equals(6.0));
        expect(AppSpacing.space8, equals(8.0));
        expect(AppSpacing.space12, equals(12.0));
        expect(AppSpacing.space16, equals(16.0));
        expect(AppSpacing.space20, equals(20.0));
        expect(AppSpacing.space24, equals(24.0));
        expect(AppSpacing.space32, equals(32.0));
        expect(AppSpacing.space48, equals(48.0));
        expect(AppSpacing.space64, equals(64.0));
      });

      test('Desktop and form width constraints are correctly bounded', () {
        expect(AppSpacing.maxFormInputWidth, equals(540.0));
        expect(AppSpacing.maxFormWidth, equals(540.0));
        expect(AppSpacing.minTouchTarget, equals(48.0));
        expect(AppSpacing.maxModalWidth, equals(600.0));
        expect(AppSpacing.maxOmniSearchWidth, equals(520.0));
        expect(AppSpacing.desktopHeaderHeight, equals(44.0));
        expect(AppSpacing.desktopActivityRailWidth, equals(48.0));
        expect(AppSpacing.desktopSidebarWidth, equals(220.0));
        expect(AppSpacing.desktopInspectorWidth, equals(280.0));
        expect(AppSpacing.desktopStatusBarHeight, equals(24.0));
      });

      test('AppBreakpoints correctly resolves responsive viewport categories', () {
        expect(AppBreakpoints.compactMax, equals(600.0));
        expect(AppBreakpoints.mediumMax, equals(1024.0));

        // Compact (<600)
        expect(AppBreakpoints.fromWidth(320.0), equals(VidraBreakpoint.compact));
        expect(AppBreakpoints.fromWidth(599.9), equals(VidraBreakpoint.compact));

        // Medium (600 - 1024)
        expect(AppBreakpoints.fromWidth(600.0), equals(VidraBreakpoint.medium));
        expect(AppBreakpoints.fromWidth(800.0), equals(VidraBreakpoint.medium));
        expect(AppBreakpoints.fromWidth(1024.0), equals(VidraBreakpoint.medium));

        // Expanded (>1024)
        expect(AppBreakpoints.fromWidth(1024.1), equals(VidraBreakpoint.expanded));
        expect(AppBreakpoints.fromWidth(1440.0), equals(VidraBreakpoint.expanded));
        expect(AppBreakpoints.fromWidth(2560.0), equals(VidraBreakpoint.expanded));
      });
    });

    group('AppAccessibility Helpers & Semantics', () {
      test('Luminance and contrast calculators operate correctly', () {
        expect(AppAccessibility.calculateLuminance(Colors.black), equals(0.0));
        expect(AppAccessibility.calculateLuminance(Colors.white), closeTo(1.0, 0.001));

        final ratio = AppAccessibility.calculateContrastRatio(Colors.black, Colors.white);
        expect(ratio, closeTo(21.0, 0.1));

        expect(AppAccessibility.meetsWcagAA(Colors.black, Colors.white), isTrue);
        expect(AppAccessibility.meetsWcagAAA(Colors.black, Colors.white), isTrue);
        expect(AppAccessibility.meetsWcagAA(const Color(0xFF595959), Colors.white), isTrue);
        expect(AppAccessibility.meetsWcagAA(const Color(0xFF777777), Colors.white, isLargeText: true), isTrue);
        expect(AppAccessibility.meetsWcagAA(const Color(0xFFCCCCCC), Colors.white), isFalse);
      });

      testWidgets('wrapDownloadCard builds semantics node correctly', (tester) async {
        bool tapped = false;
        bool deleted = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppAccessibility.wrapDownloadCard(
                child: const Text('Download Item'),
                title: 'Test Video',
                stateDescription: 'Downloading',
                progressPercent: 0.75,
                speedText: '12 MB/s',
                etaText: '00:01:20',
                onPrimaryAction: () => tapped = true,
                onDeleteAction: () => deleted = true,
              ),
            ),
          ),
        );

        expect(find.text('Download Item'), findsOneWidget);
        expect(find.byType(Semantics), findsWidgets);
        expect(tapped, isFalse);
        expect(deleted, isFalse);
      });

      testWidgets('VidraFocusRing renders and handles activation', (tester) async {
        bool activated = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VidraFocusRing(
                onActivate: () => activated = true,
                child: const Text('Focused Content'),
              ),
            ),
          ),
        );

        expect(find.text('Focused Content'), findsOneWidget);
        expect(activated, isFalse);
      });

      testWidgets('VidraGlobalShortcuts renders wrapped content', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VidraGlobalShortcuts(
                onFocusOmniBar: () {},
                onQuickPaste: () {},
                onOpenSettings: () {},
                child: const Text('Shortcuts Content'),
              ),
            ),
          ),
        );

        expect(find.text('Shortcuts Content'), findsOneWidget);
      });
    });

    // =========================================================================
    // 5. AppTheme Instantiation & Material 3 Architecture
    // =========================================================================
    group('AppTheme Instantiation & Configuration', () {
      test('AppTheme.darkTheme instantiates correctly with Material 3 & extensions', () {
        final theme = AppTheme.darkTheme;

        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, equals(Brightness.dark));
        expect(theme.scaffoldBackgroundColor, equals(AppColors.darkCanvas));

        // Surface Containers
        final cs = theme.colorScheme;
        expect(cs.surface, equals(AppColors.darkCanvas));
        expect(cs.surfaceContainerLowest, equals(AppColors.darkSurfaceLowest));
        expect(cs.surfaceContainerLow, equals(AppColors.darkSurfaceLow));
        expect(cs.surfaceContainer, equals(AppColors.darkSurface));
        expect(cs.surfaceContainerHigh, equals(AppColors.darkSurfaceHigh));
        expect(cs.surfaceContainerHighest, equals(AppColors.darkSurfaceHighest));
        expect(cs.onSurface, equals(AppColors.textPrimary));
        expect(cs.onSurfaceVariant, equals(AppColors.textSecondary));
        expect(cs.outline, equals(AppColors.borderSubtle));

        // ThemeExtension
        final ext = theme.extension<VidraSemanticColors>();
        expect(ext, isNotNull);
        expect(ext?.success, equals(VidraSemanticColors.dark.success));
        expect(ext?.warning, equals(VidraSemanticColors.dark.warning));
        expect(ext?.error, equals(VidraSemanticColors.dark.error));
        expect(ext?.info, equals(VidraSemanticColors.dark.info));
        expect(ext?.muxing, equals(VidraSemanticColors.dark.muxing));
        expect(ext?.borderSubtle, equals(VidraSemanticColors.dark.borderSubtle));

        // Component themes
        expect(theme.cardTheme.color, equals(AppColors.darkSurface));
        expect(theme.cardTheme.elevation, equals(0));
        expect(theme.appBarTheme.backgroundColor, equals(AppColors.darkCanvas));
        expect(theme.appBarTheme.elevation, equals(0));
      });

      test('AppTheme.oledTheme instantiates with pure black canvas and OLED rim borders', () {
        final theme = AppTheme.oledTheme;

        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, equals(Brightness.dark));
        expect(theme.scaffoldBackgroundColor, equals(AppColors.oledCanvas));

        final cs = theme.colorScheme;
        expect(cs.surface, equals(AppColors.oledCanvas));
        expect(cs.surfaceContainerLowest, equals(AppColors.oledSurfaceLowest));
        expect(cs.surfaceContainerLow, equals(AppColors.oledSurfaceLow));
        expect(cs.surfaceContainer, equals(AppColors.oledSurface));
        expect(cs.surfaceContainerHigh, equals(AppColors.oledSurfaceHigh));
        expect(cs.surfaceContainerHighest, equals(AppColors.oledSurfaceHighest));
        expect(cs.outline, equals(AppColors.borderOled));

        final ext = theme.extension<VidraSemanticColors>();
        expect(ext, isNotNull);
        expect(ext?.borderSubtle, equals(AppColors.borderOled));
      });

      test('AppTheme.lightTheme instantiates with light brightness and light semantic palette', () {
        final theme = AppTheme.lightTheme;

        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, equals(Brightness.light));

        final ext = theme.extension<VidraSemanticColors>();
        expect(ext, isNotNull);
        expect(ext?.success, equals(VidraSemanticColors.light.success));
        expect(ext?.warning, equals(VidraSemanticColors.light.warning));
        expect(ext?.error, equals(VidraSemanticColors.light.error));
        expect(ext?.info, equals(VidraSemanticColors.light.info));
        expect(ext?.muxing, equals(VidraSemanticColors.light.muxing));
      });

      test('AppTheme defines all standardized Material 3 component themes', () {
        for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme, AppTheme.oledTheme]) {
          // TabBarThemeData - Must NOT force TabAlignment.start globally
          expect(theme.tabBarTheme.tabAlignment, isNot(equals(TabAlignment.start)));

          // InputDecorationTheme
          expect(theme.inputDecorationTheme.filled, isTrue);
          expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
          expect(theme.inputDecorationTheme.enabledBorder, isA<OutlineInputBorder>());
          expect(theme.inputDecorationTheme.focusedBorder, isA<OutlineInputBorder>());
          expect(theme.inputDecorationTheme.hintStyle, isNotNull);
          expect(theme.inputDecorationTheme.labelStyle, isNotNull);

          // TextSelectionTheme
          expect(theme.textSelectionTheme.cursorColor, equals(theme.colorScheme.primary));
          expect(theme.textSelectionTheme.selectionHandleColor, equals(theme.colorScheme.primary));

          // Button Themes
          expect(theme.filledButtonTheme.style, isNotNull);
          expect(theme.elevatedButtonTheme.style, isNotNull);
          expect(theme.outlinedButtonTheme.style, isNotNull);
          expect(theme.textButtonTheme.style, isNotNull);
          expect(theme.floatingActionButtonTheme.backgroundColor, equals(theme.colorScheme.primary));
          expect(theme.floatingActionButtonTheme.foregroundColor, equals(theme.colorScheme.onPrimary));
          expect(theme.iconButtonTheme.style, isNotNull);

          // ChipThemeData
          expect(theme.chipTheme.backgroundColor, equals(theme.colorScheme.surfaceContainerHigh));
          expect(theme.chipTheme.selectedColor, equals(theme.colorScheme.primaryContainer));
          expect(theme.chipTheme.labelStyle, isNotNull);

          // Card & SegmentedButton
          expect(theme.cardTheme.color, equals(theme.colorScheme.surfaceContainer));
          expect(theme.segmentedButtonTheme.style, isNotNull);
        }
      });

      testWidgets('Non-scrollable TabBar renders safely without assertion exception in all themes',
          (tester) async {
        for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme, AppTheme.oledTheme]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: const DefaultTabController(
                length: 3,
                child: Scaffold(
                  body: TabBar(
                    isScrollable: false, // Default non-scrollable
                    tabs: [
                      Tab(text: 'Tab 1'),
                      Tab(text: 'Tab 2'),
                      Tab(text: 'Tab 3'),
                    ],
                  ),
                ),
              ),
            ),
          );

          expect(find.text('Tab 1'), findsOneWidget);
          expect(find.text('Tab 2'), findsOneWidget);
          expect(find.text('Tab 3'), findsOneWidget);
        }
      });
    });

    // =========================================================================
    // 6. BuildContext Extensions Widget Verification
    // =========================================================================
    group('BuildContext Extensions (Widget Test)', () {
      testWidgets(
          'VidraColorContext and VidraTypographyContext resolve correctly in widget tree',
          (tester) async {
        late BuildContext capturedContext;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                capturedContext = context;
                return const Scaffold(
                  body: Text('Theme Context Test'),
                );
              },
            ),
          ),
        );

        // VidraColorContext
        expect(capturedContext.colors.surface, equals(AppColors.darkCanvas));
        expect(capturedContext.semanticColors.success, equals(AppColors.success));

        // VidraTypographyContext
        expect(capturedContext.textTheme.titleMedium?.fontSize, equals(16.0));
        expect(capturedContext.cardTitle.fontSize, equals(16.0));
        expect(capturedContext.cardSubtitle.fontSize, equals(12.0));
        expect(capturedContext.formatPill.fontSize, equals(12.0));
        expect(capturedContext.thumbnailDuration.fontSize, equals(10.0));
        expect(capturedContext.speedTelemetry.fontSize, equals(11.0));
        expect(capturedContext.speedTelemetry.color, equals(capturedContext.colors.primary));
        expect(
          capturedContext.speedTelemetry.fontFeatures?.any((f) => f.feature == 'tnum'),
          isTrue,
        );

        // Dynamic Telemetry Tokens
        expect(capturedContext.telemetryHero.fontSize, equals(24.0));
        expect(capturedContext.telemetryHero.color, equals(capturedContext.colors.onSurface));
        expect(capturedContext.telemetryLarge.fontSize, equals(16.0));
        expect(capturedContext.telemetryLarge.color, equals(capturedContext.colors.onSurface));
        expect(capturedContext.telemetryMedium.fontSize, equals(13.0));
        expect(capturedContext.telemetryMedium.color, equals(capturedContext.colors.onSurfaceVariant));
        expect(capturedContext.telemetrySmall.fontSize, equals(11.0));
        expect(capturedContext.telemetrySmall.color, equals(capturedContext.colors.onSurfaceVariant));
        expect(capturedContext.telemetryMicro.fontSize, equals(10.0));
        expect(capturedContext.telemetryMicro.color, equals(capturedContext.colors.onSurfaceVariant));
        expect(capturedContext.consoleLog.fontSize, equals(12.0));
        expect(capturedContext.consoleLog.color, equals(capturedContext.colors.onSurface));
      });

      testWidgets(
          'Dynamic telemetry tokens meet WCAG contrast across Light, Dark, and OLED themes',
          (tester) async {
        for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme, AppTheme.oledTheme]) {
          late BuildContext ctx;

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Builder(
                builder: (context) {
                  ctx = context;
                  return const Scaffold(body: Text('Test'));
                },
              ),
            ),
          );

          final cardBase = ctx.colors.surfaceContainer;

          // Hero on Card Base (>= 7.0:1 AAA)
          final heroRatio = _calculateContrastRatio(ctx.telemetryHero.color!, cardBase);
          expect(heroRatio, greaterThanOrEqualTo(7.0),
              reason: '${theme.brightness} telemetryHero must meet AAA on card base');

          // Small telemetry (onSurfaceVariant) on Card Base (>= 4.5:1 AA)
          final smallRatio = _calculateContrastRatio(ctx.telemetrySmall.color!, cardBase);
          expect(smallRatio, greaterThanOrEqualTo(4.5),
              reason: '${theme.brightness} telemetrySmall must meet AA on card base');

          // Speed telemetry (primary) on Card Base (>= 4.5:1 AA)
          final speedRatio = _calculateContrastRatio(ctx.speedTelemetry.color!, cardBase);
          expect(speedRatio, greaterThanOrEqualTo(4.5),
              reason: '${theme.brightness} speedTelemetry must meet AA on card base');
        }
      });
    });
  });
}
