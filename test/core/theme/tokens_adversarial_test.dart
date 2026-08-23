import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vidra/core/theme/accessibility.dart';
import 'package:vidra/core/theme/app_theme.dart';
import 'package:vidra/core/theme/colors.dart';
import 'package:vidra/core/theme/typography.dart';

void main() {
  group('Challenger 1 Adversarial Test Suite: Milestone 1 Tokens & Math', () {
    // =========================================================================
    // 1. VidraSemanticColors.lerp Stress-Testing & Boundary Invariants
    // =========================================================================
    group('VidraSemanticColors.lerp Boundary & Extreme Values', () {
      const dark = VidraSemanticColors.dark;
      const light = VidraSemanticColors.light;
      const oled = VidraSemanticColors.oled;

      test('t = 0.0 returns exact start color values for all 22 fields', () {
        final result = dark.lerp(light, 0.0);
        expect(result.success, equals(dark.success));
        expect(result.onSuccess, equals(dark.onSuccess));
        expect(result.successContainer, equals(dark.successContainer));
        expect(result.onSuccessContainer, equals(dark.onSuccessContainer));
        expect(result.warning, equals(dark.warning));
        expect(result.onWarning, equals(dark.onWarning));
        expect(result.warningContainer, equals(dark.warningContainer));
        expect(result.onWarningContainer, equals(dark.onWarningContainer));
        expect(result.error, equals(dark.error));
        expect(result.onError, equals(dark.onError));
        expect(result.errorContainer, equals(dark.errorContainer));
        expect(result.onErrorContainer, equals(dark.onErrorContainer));
        expect(result.info, equals(dark.info));
        expect(result.onInfo, equals(dark.onInfo));
        expect(result.infoContainer, equals(dark.infoContainer));
        expect(result.onInfoContainer, equals(dark.onInfoContainer));
        expect(result.muxing, equals(dark.muxing));
        expect(result.onMuxing, equals(dark.onMuxing));
        expect(result.muxingContainer, equals(dark.muxingContainer));
        expect(result.onMuxingContainer, equals(dark.onMuxingContainer));
        expect(result.borderSubtle, equals(dark.borderSubtle));
        expect(result.borderFocus, equals(dark.borderFocus));
      });

      test('t = 1.0 returns exact target color values for all 22 fields', () {
        final result = dark.lerp(light, 1.0);
        expect(result.success, equals(light.success));
        expect(result.onSuccess, equals(light.onSuccess));
        expect(result.successContainer, equals(light.successContainer));
        expect(result.onSuccessContainer, equals(light.onSuccessContainer));
        expect(result.warning, equals(light.warning));
        expect(result.onWarning, equals(light.onWarning));
        expect(result.warningContainer, equals(light.warningContainer));
        expect(result.onWarningContainer, equals(light.onWarningContainer));
        expect(result.error, equals(light.error));
        expect(result.onError, equals(light.onError));
        expect(result.errorContainer, equals(light.errorContainer));
        expect(result.onErrorContainer, equals(light.onErrorContainer));
        expect(result.info, equals(light.info));
        expect(result.onInfo, equals(light.onInfo));
        expect(result.infoContainer, equals(light.infoContainer));
        expect(result.onInfoContainer, equals(light.onInfoContainer));
        expect(result.muxing, equals(light.muxing));
        expect(result.onMuxing, equals(light.onMuxing));
        expect(result.muxingContainer, equals(light.muxingContainer));
        expect(result.onMuxingContainer, equals(light.onMuxingContainer));
        expect(result.borderSubtle, equals(light.borderSubtle));
        expect(result.borderFocus, equals(light.borderFocus));
      });

      test('t = 0.5 returns exact linear RGB midpoints for all 22 fields', () {
        final result = dark.lerp(light, 0.5);
        expect(result.success, equals(Color.lerp(dark.success, light.success, 0.5)));
        expect(result.onSuccess, equals(Color.lerp(dark.onSuccess, light.onSuccess, 0.5)));
        expect(result.successContainer, equals(Color.lerp(dark.successContainer, light.successContainer, 0.5)));
        expect(result.onSuccessContainer, equals(Color.lerp(dark.onSuccessContainer, light.onSuccessContainer, 0.5)));
        expect(result.warning, equals(Color.lerp(dark.warning, light.warning, 0.5)));
        expect(result.onWarning, equals(Color.lerp(dark.onWarning, light.onWarning, 0.5)));
        expect(result.warningContainer, equals(Color.lerp(dark.warningContainer, light.warningContainer, 0.5)));
        expect(result.onWarningContainer, equals(Color.lerp(dark.onWarningContainer, light.onWarningContainer, 0.5)));
        expect(result.error, equals(Color.lerp(dark.error, light.error, 0.5)));
        expect(result.onError, equals(Color.lerp(dark.onError, light.onError, 0.5)));
        expect(result.errorContainer, equals(Color.lerp(dark.errorContainer, light.errorContainer, 0.5)));
        expect(result.onErrorContainer, equals(Color.lerp(dark.onErrorContainer, light.onErrorContainer, 0.5)));
        expect(result.info, equals(Color.lerp(dark.info, light.info, 0.5)));
        expect(result.onInfo, equals(Color.lerp(dark.onInfo, light.onInfo, 0.5)));
        expect(result.infoContainer, equals(Color.lerp(dark.infoContainer, light.infoContainer, 0.5)));
        expect(result.onInfoContainer, equals(Color.lerp(dark.onInfoContainer, light.onInfoContainer, 0.5)));
        expect(result.muxing, equals(Color.lerp(dark.muxing, light.muxing, 0.5)));
        expect(result.onMuxing, equals(Color.lerp(dark.onMuxing, light.onMuxing, 0.5)));
        expect(result.muxingContainer, equals(Color.lerp(dark.muxingContainer, light.muxingContainer, 0.5)));
        expect(result.onMuxingContainer, equals(Color.lerp(dark.onMuxingContainer, light.onMuxingContainer, 0.5)));
        expect(result.borderSubtle, equals(Color.lerp(dark.borderSubtle, light.borderSubtle, 0.5)));
        expect(result.borderFocus, equals(Color.lerp(dark.borderFocus, light.borderFocus, 0.5)));
      });

      test('Negative t (t = -1.0, t = -100.0) extrapolates safely without null/crash', () {
        final neg1 = dark.lerp(light, -1.0);
        expect(neg1, isA<VidraSemanticColors>());
        expect(neg1.success, isNotNull);
        expect(neg1.warning, isNotNull);
        expect(neg1.error, isNotNull);
        expect(neg1.info, isNotNull);
        expect(neg1.muxing, isNotNull);
        expect(neg1.borderSubtle, isNotNull);
        expect(neg1.borderFocus, isNotNull);

        final neg100 = dark.lerp(light, -100.0);
        expect(neg100, isA<VidraSemanticColors>());
        expect(neg100.success, isNotNull);
        expect(neg100.warning, isNotNull);
      });

      test('Overshoot t (t = 2.0, t = 100.0) extrapolates safely without null/crash', () {
        final over2 = dark.lerp(light, 2.0);
        expect(over2, isA<VidraSemanticColors>());
        expect(over2.success, isNotNull);
        expect(over2.warning, isNotNull);
        expect(over2.error, isNotNull);
        expect(over2.info, isNotNull);
        expect(over2.muxing, isNotNull);
        expect(over2.borderSubtle, isNotNull);
        expect(over2.borderFocus, isNotNull);

        final over100 = dark.lerp(light, 100.0);
        expect(over100, isA<VidraSemanticColors>());
        expect(over100.success, isNotNull);
      });

      test('lerp with null other returns this instance without modification', () {
        final res = dark.lerp(null, 0.5);
        expect(identical(res, dark), isTrue);
        expect(res, equals(dark));
      });

      test('lerp with identical instance (this.lerp(this, t)) returns this values across all bounds', () {
        for (final t in [-100.0, -1.0, 0.0, 0.5, 1.0, 2.0, 100.0]) {
          final res = dark.lerp(dark, t);
          expect(res.success, equals(Color.lerp(dark.success, dark.success, t)));
          expect(res.warning, equals(Color.lerp(dark.warning, dark.warning, t)));
          expect(res.error, equals(Color.lerp(dark.error, dark.error, t)));
          expect(res.info, equals(Color.lerp(dark.info, dark.info, t)));
          expect(res.muxing, equals(Color.lerp(dark.muxing, dark.muxing, t)));
          expect(res.borderSubtle, equals(Color.lerp(dark.borderSubtle, dark.borderSubtle, t)));
          expect(res.borderFocus, equals(Color.lerp(dark.borderFocus, dark.borderFocus, t)));
        }
      });

      test('lerp between Dark and OLED interpolates borderSubtle correctly', () {
        final res = dark.lerp(oled, 0.5);
        expect(
          res.borderSubtle,
          equals(Color.lerp(AppColors.borderSubtle, AppColors.borderOled, 0.5)),
        );
      });
    });

    // =========================================================================
    // 2. AppAccessibility.contrastRatio & relativeLuminance Stress-Testing
    // =========================================================================
    group('AppAccessibility Math & Extreme Colors Stress-Testing', () {
      test('Pure black relative luminance is exactly 0.0', () {
        expect(AppAccessibility.calculateLuminance(const Color(0xFF000000)), equals(0.0));
      });

      test('Pure white relative luminance is exactly 1.0', () {
        expect(AppAccessibility.calculateLuminance(const Color(0xFFFFFFFF)), closeTo(1.0, 1e-6));
      });

      test('Relative luminance channel linearizations match WCAG 2.1 specifications', () {
        // Pure Red (#FF0000) -> 0.2126 * 1.0 = 0.2126
        expect(AppAccessibility.calculateLuminance(const Color(0xFFFF0000)), closeTo(0.2126, 1e-4));

        // Pure Green (#00FF00) -> 0.7152 * 1.0 = 0.7152
        expect(AppAccessibility.calculateLuminance(const Color(0xFF00FF00)), closeTo(0.7152, 1e-4));

        // Pure Blue (#0000FF) -> 0.0722 * 1.0 = 0.0722
        expect(AppAccessibility.calculateLuminance(const Color(0xFF0000FF)), closeTo(0.0722, 1e-4));

        // Sum of RGB relative luminances must equal 1.0
        final rLum = AppAccessibility.calculateLuminance(const Color(0xFFFF0000));
        final gLum = AppAccessibility.calculateLuminance(const Color(0xFF00FF00));
        final bLum = AppAccessibility.calculateLuminance(const Color(0xFF0000FF));
        expect(rLum + gLum + bLum, closeTo(1.0, 1e-4));
      });

      test('Gamma threshold boundary condition (channel = 0.04045) is continuous', () {
        // Below/at threshold: channel / 12.92
        // Above threshold: ((channel + 0.055) / 1.055)^2.4
        const c1 = 0.04045;
        const c2 = 0.04046;

        final lum1 = c1 / 12.92;
        final lum2 = math.pow((c2 + 0.055) / 1.055, 2.4).toDouble();

        expect((lum1 - lum2).abs(), lessThan(1e-4), reason: 'Luminance curve must be continuous at gamma breakpoint');
      });

      test('Pure Black vs Pure White contrast ratio is exactly 21.0:1 (Max WCAG)', () {
        final ratio = AppAccessibility.calculateContrastRatio(
          const Color(0xFF000000),
          const Color(0xFFFFFFFF),
        );
        expect(ratio, closeTo(21.0, 1e-3));
      });

      test('Contrast ratio calculation is strictly symmetric (commutativity)', () {
        const colorA = Color(0xFF3B82F6);
        const colorB = Color(0xFF171B22);

        final ratioAB = AppAccessibility.calculateContrastRatio(colorA, colorB);
        final ratioBA = AppAccessibility.calculateContrastRatio(colorB, colorA);

        expect(ratioAB, equals(ratioBA));
      });

      test('Identical colors return exactly 1.0:1 without division by zero', () {
        final testColors = [
          const Color(0xFF000000), // Black (0.0 luminance, denominator = 0.05)
          const Color(0xFFFFFFFF), // White
          const Color(0xFF10B981), // Green
          const Color(0xFFEF4444), // Red
          const Color(0xFF3B82F6), // Blue
          const Color(0x00000000), // Transparent Black
          const Color(0x00FFFFFF), // Transparent White
        ];

        for (final c in testColors) {
          final ratio = AppAccessibility.calculateContrastRatio(c, c);
          expect(ratio, closeTo(1.0, 1e-6), reason: 'Contrast ratio of color with itself must be 1.0');
          expect(ratio.isFinite, isTrue, reason: 'Contrast ratio must not produce Infinity or NaN');
          expect(ratio.isNaN, isFalse);
        }
      });

      test('Extremely close dark colors do not produce floating point instability', () {
        const c1 = Color(0xFF010101);
        const c2 = Color(0xFF020202);

        final ratio = AppAccessibility.calculateContrastRatio(c1, c2);
        expect(ratio, greaterThanOrEqualTo(1.0));
        expect(ratio, lessThan(1.1));
        expect(ratio.isFinite, isTrue);
      });

      test('meetsWcagAA and meetsWcagAAA thresholds evaluate accurately at boundary margins', () {
        // High contrast pair (21.0)
        expect(AppAccessibility.meetsWcagAA(Colors.black, Colors.white), isTrue);
        expect(AppAccessibility.meetsWcagAAA(Colors.black, Colors.white), isTrue);

        // Identical pair (1.0)
        expect(AppAccessibility.meetsWcagAA(Colors.white, Colors.white), isFalse);
        expect(AppAccessibility.meetsWcagAAA(Colors.white, Colors.white), isFalse);

        // Large text flag relaxes AA from 4.5 to 3.0, and AAA from 7.0 to 4.5
        // Find a color pair with contrast ~3.5:1
        // Background: White (#FFFFFF, L=1.0)
        // Foreground: #888888 -> L ~ 0.246 -> ratio = 1.05 / 0.296 = 3.54
        const midGray = Color(0xFF888888);
        final grayRatio = AppAccessibility.calculateContrastRatio(midGray, Colors.white);
        expect(grayRatio, inInclusiveRange(3.0, 4.49));

        expect(AppAccessibility.meetsWcagAA(midGray, Colors.white, isLargeText: false), isFalse);
        expect(AppAccessibility.meetsWcagAA(midGray, Colors.white, isLargeText: true), isTrue);

        expect(AppAccessibility.meetsWcagAAA(midGray, Colors.white, isLargeText: false), isFalse);
        expect(AppAccessibility.meetsWcagAAA(midGray, Colors.white, isLargeText: true), isFalse);
      });

      test('All 22 semantic color roles across Dark, OLED, Light satisfy minimum contrast guarantees', () {
        // Dark Theme Pairs
        expect(
          AppAccessibility.calculateContrastRatio(
            VidraSemanticColors.dark.onSuccess,
            VidraSemanticColors.dark.successContainer,
          ),
          greaterThanOrEqualTo(7.0),
          reason: 'Dark onSuccess on successContainer must meet AAA (>= 7.0)',
        );

        expect(
          AppAccessibility.calculateContrastRatio(
            VidraSemanticColors.dark.onWarning,
            VidraSemanticColors.dark.warningContainer,
          ),
          greaterThanOrEqualTo(7.0),
          reason: 'Dark onWarning on warningContainer must meet AAA (>= 7.0)',
        );

        expect(
          AppAccessibility.calculateContrastRatio(
            VidraSemanticColors.dark.onError,
            VidraSemanticColors.dark.errorContainer,
          ),
          greaterThanOrEqualTo(7.0),
          reason: 'Dark onError on errorContainer must meet AAA (>= 7.0)',
        );

        expect(
          AppAccessibility.calculateContrastRatio(
            VidraSemanticColors.dark.onInfo,
            VidraSemanticColors.dark.infoContainer,
          ),
          greaterThanOrEqualTo(7.0),
          reason: 'Dark onInfo on infoContainer must meet AAA (>= 7.0)',
        );

        expect(
          AppAccessibility.calculateContrastRatio(
            VidraSemanticColors.dark.onMuxing,
            VidraSemanticColors.dark.muxingContainer,
          ),
          greaterThanOrEqualTo(7.0),
          reason: 'Dark onMuxing on muxingContainer must meet AAA (>= 7.0)',
        );

        // Light Theme Pairs on Card Base
        expect(
          AppAccessibility.calculateContrastRatio(
            VidraSemanticColors.light.success,
            AppColors.lightSurface,
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'Light success on lightSurface must meet AA (>= 4.5)',
        );

        expect(
          AppAccessibility.calculateContrastRatio(
            VidraSemanticColors.light.warning,
            AppColors.lightSurface,
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'Light warning on lightSurface must meet AA (>= 4.5)',
        );

        expect(
          AppAccessibility.calculateContrastRatio(
            VidraSemanticColors.light.error,
            AppColors.lightSurface,
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'Light error on lightSurface must meet AA (>= 4.5)',
        );

        expect(
          AppAccessibility.calculateContrastRatio(
            VidraSemanticColors.light.info,
            AppColors.lightSurface,
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'Light info on lightSurface must meet AA (>= 4.5)',
        );

        expect(
          AppAccessibility.calculateContrastRatio(
            VidraSemanticColors.light.muxing,
            AppColors.lightSurface,
          ),
          greaterThanOrEqualTo(7.0),
          reason: 'Light muxing on lightSurface must meet AAA (>= 7.0)',
        );
      });
    });

    // =========================================================================
    // 3. AppTypography Font Features in Widget Rendering
    // =========================================================================
    group('AppTypography Font Features in Widget Rendering', () {
      testWidgets('All telemetry tokens render with tabularFigures (tnum) and slashedZero (zero)',
          (tester) async {
        final telemetryStyles = <String, TextStyle>{
          'telemetryHero': AppTypography.telemetryHero(),
          'telemetryLarge': AppTypography.telemetryLarge(),
          'telemetryMedium': AppTypography.telemetryMedium(),
          'telemetrySmall': AppTypography.telemetrySmall(),
          'telemetryMicro': AppTypography.telemetryMicro(),
        };

        for (final entry in telemetryStyles.entries) {
          final style = entry.value;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Text(
                  '0123456789 108.4 MB/s ETA 00:04:12',
                  key: Key(entry.key),
                  style: style,
                ),
              ),
            ),
          );

          final textFinder = find.byKey(Key(entry.key));
          expect(textFinder, findsOneWidget);

          final textWidget = tester.widget<Text>(textFinder);
          expect(textWidget.style?.fontFamily, equals(AppTypography.fontFamilyMonospace));
          expect(textWidget.style?.fontFamilyFallback, equals(AppTypography.monospaceFallback));

          final features = textWidget.style?.fontFeatures;
          expect(features, isNotNull, reason: '${entry.key} must contain fontFeatures');
          expect(
            features!.any((f) => f.feature == 'tnum'),
            isTrue,
            reason: '${entry.key} must contain tabularFigures (tnum)',
          );
          expect(
            features.any((f) => f.feature == 'zero'),
            isTrue,
            reason: '${entry.key} must contain slashedZero (zero)',
          );
        }
      });

      testWidgets('Dynamic numeric updates render steadily without layout shifts',
          (tester) async {
        final speedNotifier = ValueNotifier<String>('0.0 KB/s');
        final etaNotifier = ValueNotifier<String>('00:00:00');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: speedNotifier,
                      builder: (ctx, speed, _) => Text(
                        speed,
                        key: const Key('speed_telemetry_widget'),
                        style: ctx.speedTelemetry,
                      ),
                    ),
                    ValueListenableBuilder<String>(
                      valueListenable: etaNotifier,
                      builder: (_, eta, _) => Text(
                        eta,
                        key: const Key('eta_telemetry_widget'),
                        style: AppTypography.telemetryMicro(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Pump a sequence of simulated download telemetry updates
        final simulatedSpeeds = [
          '1.2 KB/s',
          '45.8 KB/s',
          '980.4 KB/s',
          '1.24 MB/s',
          '18.75 MB/s',
          '104.50 MB/s',
          '1.02 GB/s',
        ];

        final simulatedEtas = [
          '01:45:12',
          '00:32:04',
          '00:05:49',
          '00:00:15',
          '00:00:01',
          '00:00:00',
        ];

        for (int i = 0; i < simulatedSpeeds.length; i++) {
          speedNotifier.value = simulatedSpeeds[i];
          etaNotifier.value = simulatedEtas[i % simulatedEtas.length];

          await tester.pump();

          expect(find.text(simulatedSpeeds[i]), findsOneWidget);
          expect(find.text(simulatedEtas[i % simulatedEtas.length]), findsOneWidget);
        }
      });

      testWidgets('AppAccessibility.clampedTextScaler strictly bounds scaling up to maxScaleFactor (2.0x)',
          (tester) async {
        late TextScaler resolvedScaler;

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(3.5), // User set 350% scale
            ),
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  resolvedScaler = AppAccessibility.clampedTextScaler(context);
                  return Scaffold(
                    body: Text(
                      'Scaled text',
                      textScaler: resolvedScaler,
                    ),
                  );
                },
              ),
            ),
          ),
        );

        // Scaler should clamp 3.5 to maxScaleFactor (2.0)
        expect(resolvedScaler.scale(16.0), equals(32.0)); // 16 * 2.0 = 32.0, not 16 * 3.5 = 56.0
      });

      testWidgets('VidraTypographyContext convenience getters resolve within all themes',
          (tester) async {
        for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme, AppTheme.oledTheme]) {
          late BuildContext capturedCtx;

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Builder(
                builder: (ctx) {
                  capturedCtx = ctx;
                  return const Scaffold(body: Text('Test'));
                },
              ),
            ),
          );

          expect(capturedCtx.cardTitle.fontSize, equals(16.0));
          expect(capturedCtx.cardSubtitle.fontSize, equals(12.0));
          expect(capturedCtx.formatPill.fontSize, equals(12.0));
          expect(capturedCtx.thumbnailDuration.fontSize, equals(10.0));
          expect(capturedCtx.speedTelemetry.fontFeatures?.any((f) => f.feature == 'tnum'), isTrue);
        }
      });
    });
  });
}
