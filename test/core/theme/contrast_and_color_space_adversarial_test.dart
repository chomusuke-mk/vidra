import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vidra/core/theme/accessibility.dart';
import 'package:vidra/core/theme/app_theme.dart';
import 'package:vidra/core/theme/colors.dart';
import 'package:vidra/core/theme/typography.dart';

void main() {
  group('Challenger 2 Empirical Verification: Milestone 1 Contrast & Color Space Harness', () {
    final themes = <String, ThemeData>{
      'Light': AppTheme.lightTheme,
      'Dark': AppTheme.darkTheme,
      'OLED': AppTheme.oledTheme,
    };

    // =========================================================================
    // 1. Task 2: Telemetry Typography vs Surface Hierarchy
    // =========================================================================
    group('Task 2: Telemetry Typography vs Surfaces Verification', () {
      for (final themeEntry in themes.entries) {
        final themeName = themeEntry.key;
        final theme = themeEntry.value;
        final cs = theme.colorScheme;

        final surfaces = <String, Color>{
          'surface': cs.surface,
          'surfaceContainer': cs.surfaceContainer,
          'surfaceContainerHigh': cs.surfaceContainerHigh,
          'scaffoldBackgroundColor': theme.scaffoldBackgroundColor,
        };

        testWidgets('[$themeName] Telemetry styles meet WCAG contrast across surfaces',
            (tester) async {
          late BuildContext capturedCtx;

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Builder(
                builder: (ctx) {
                  capturedCtx = ctx;
                  return const Scaffold(body: SizedBox.shrink());
                },
              ),
            ),
          );

          final telemetryStyles = <String, TextStyle>{
            'telemetryHero': capturedCtx.telemetryHero,
            'telemetryLarge': capturedCtx.telemetryLarge,
            'telemetryMedium': capturedCtx.telemetryMedium,
            'telemetrySmall': capturedCtx.telemetrySmall,
            'telemetryMicro': capturedCtx.telemetryMicro,
            'consoleLog': capturedCtx.consoleLog,
            'speedTelemetry': capturedCtx.speedTelemetry,
          };

          debugPrint('=== $themeName Theme Telemetry Contrast Ratios ===');
          for (final telEntry in telemetryStyles.entries) {
            final telName = telEntry.key;
            final textStyle = telEntry.value;
            final textColor = textStyle.color!;

            for (final surfEntry in surfaces.entries) {
              final surfName = surfEntry.key;
              final surfColor = surfEntry.value;

              final ratio = AppAccessibility.calculateContrastRatio(textColor, surfColor);
              debugPrint('[$themeName] $telName on $surfName: ${ratio.toStringAsFixed(2)}:1 (Color: $textColor on $surfColor)');

              // telemetryHero is 24pt bold (Large text): WCAG AA >= 3.0:1, AAA >= 4.5:1
              final isLarge = telName == 'telemetryHero';
              final minRequired = isLarge ? 3.0 : 4.5;

              expect(
                ratio,
                greaterThanOrEqualTo(minRequired),
                reason: '[$themeName] $telName on $surfName failed: $ratio < $minRequired',
              );
            }
          }
        });
      }
    });

    // =========================================================================
    // 2. Task 3: Light Theme All Text Elements Contrast (>= 4.5:1 AA)
    // =========================================================================
    group('Task 3: Light Theme All Text Elements Contrast Verification', () {
      final lightTheme = AppTheme.lightTheme;
      final cs = lightTheme.colorScheme;

      final lightSurfaces = <String, Color>{
        'surface': cs.surface,
        'surfaceContainerLowest': cs.surfaceContainerLowest,
        'surfaceContainerLow': cs.surfaceContainerLow,
        'surfaceContainer': cs.surfaceContainer,
        'surfaceContainerHigh': cs.surfaceContainerHigh,
        'surfaceContainerHighest': cs.surfaceContainerHighest,
        'scaffoldBackgroundColor': lightTheme.scaffoldBackgroundColor,
      };

      testWidgets('Light Theme all 15 TextTheme tiers achieve >= 4.5:1 AA on light surfaces',
          (tester) async {
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            theme: lightTheme,
            home: Builder(
              builder: (c) {
                ctx = c;
                return const Scaffold(body: SizedBox.shrink());
              },
            ),
          ),
        );

        final textTheme = ctx.textTheme;
        final textStyles = <String, TextStyle?>{
          'displayLarge': textTheme.displayLarge,
          'displayMedium': textTheme.displayMedium,
          'displaySmall': textTheme.displaySmall,
          'headlineLarge': textTheme.headlineLarge,
          'headlineMedium': textTheme.headlineMedium,
          'headlineSmall': textTheme.headlineSmall,
          'titleLarge': textTheme.titleLarge,
          'titleMedium': textTheme.titleMedium,
          'titleSmall': textTheme.titleSmall,
          'bodyLarge': textTheme.bodyLarge,
          'bodyMedium': textTheme.bodyMedium,
          'bodySmall': textTheme.bodySmall,
          'labelLarge': textTheme.labelLarge,
          'labelMedium': textTheme.labelMedium,
          'labelSmall': textTheme.labelSmall,
        };

        debugPrint('=== Light Theme Material 3 TextTheme Contrast ===');
        for (final styleEntry in textStyles.entries) {
          final styleName = styleEntry.key;
          final style = styleEntry.value!;
          final color = style.color ?? cs.onSurface;
          final isLarge = (style.fontSize ?? 14.0) >= 18.0 ||
              ((style.fontSize ?? 14.0) >= 14.0 && (style.fontWeight?.value ?? 0) >= FontWeight.w700.value);
          final requiredMin = isLarge ? 3.0 : 4.5;

          for (final surfEntry in lightSurfaces.entries) {
            final surfName = surfEntry.key;
            final surfColor = surfEntry.value;

            final ratio = AppAccessibility.calculateContrastRatio(color, surfColor);
            debugPrint('[Light TextTheme] $styleName on $surfName: ${ratio.toStringAsFixed(2)}:1 (Req: $requiredMin:1)');

            expect(
              ratio,
              greaterThanOrEqualTo(requiredMin),
              reason: 'Light textTheme.$styleName on $surfName has contrast $ratio < $requiredMin',
            );
          }
        }
      });

      testWidgets('Light Theme Convenience Typography Getters meet AA contrast',
          (tester) async {
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            theme: lightTheme,
            home: Builder(
              builder: (c) {
                ctx = c;
                return const Scaffold(body: SizedBox.shrink());
              },
            ),
          ),
        );

        final convenienceMap = <String, TextStyle>{
          'cardTitle': ctx.cardTitle,
          'cardSubtitle': ctx.cardSubtitle,
          'formatPill': ctx.formatPill,
          'thumbnailDuration': ctx.thumbnailDuration,
          'speedTelemetry': ctx.speedTelemetry,
        };

        debugPrint('=== Light Theme Convenience Typography Contrast ===');
        for (final surfEntry in lightSurfaces.entries) {
          final surfName = surfEntry.key;
          final surfColor = surfEntry.value;

          for (final entry in convenienceMap.entries) {
            final name = entry.key;
            final style = entry.value;
            final color = style.color ?? ctx.colors.onSurface;
            final isLarge = (style.fontSize ?? 14.0) >= 18.0;
            final threshold = isLarge ? 3.0 : 4.5;

            final ratio = AppAccessibility.calculateContrastRatio(color, surfColor);
            debugPrint('[Light Convenience] $name on $surfName: ${ratio.toStringAsFixed(2)}:1');

            expect(
              ratio,
              greaterThanOrEqualTo(threshold),
              reason: 'context.$name on $surfName has contrast $ratio < $threshold',
            );
          }
        }
      });
    });

    // =========================================================================
    // 3. Task 4: Button and Input Component Contrast (Light and Dark)
    // =========================================================================
    group('Task 4: Button and Input Component Contrast Verification', () {
      for (final themeEntry in [
        MapEntry('Light', AppTheme.lightTheme),
        MapEntry('Dark', AppTheme.darkTheme),
        MapEntry('OLED', AppTheme.oledTheme),
      ]) {
        final themeName = themeEntry.key;
        final theme = themeEntry.value;
        final cs = theme.colorScheme;

        test('[$themeName] FilledButton foreground/background and fill/scaffold contrast', () {
          final buttonStyle = theme.filledButtonTheme.style!;
          final bg = buttonStyle.backgroundColor?.resolve({}) ?? cs.primary;
          final fg = buttonStyle.foregroundColor?.resolve({}) ?? cs.onPrimary;

          final fgRatio = AppAccessibility.calculateContrastRatio(fg, bg);
          final bgRatio = AppAccessibility.calculateContrastRatio(bg, theme.scaffoldBackgroundColor);

          debugPrint('[$themeName] FilledButton: fg on bg = ${fgRatio.toStringAsFixed(2)}:1, bg on scaffold = ${bgRatio.toStringAsFixed(2)}:1');

          expect(fgRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] FilledButton text on fill');
          expect(bgRatio, greaterThanOrEqualTo(3.0), reason: '[$themeName] FilledButton fill on scaffold');
        });

        test('[$themeName] ElevatedButton foreground on surfaceContainerHigh meets AA', () {
          final buttonStyle = theme.elevatedButtonTheme.style!;
          final bg = buttonStyle.backgroundColor?.resolve({}) ?? cs.surfaceContainerHigh;
          final fg = buttonStyle.foregroundColor?.resolve({}) ?? cs.primary;

          final ratio = AppAccessibility.calculateContrastRatio(fg, bg);
          debugPrint('[$themeName] ElevatedButton: fg on bg = ${ratio.toStringAsFixed(2)}:1');

          expect(ratio, greaterThanOrEqualTo(4.5), reason: '[$themeName] ElevatedButton fg on bg');
        });

        test('[$themeName] OutlinedButton & TextButton foreground meets AA on surfaces', () {
          final outlinedFg = theme.outlinedButtonTheme.style?.foregroundColor?.resolve({}) ?? cs.primary;
          final textFg = theme.textButtonTheme.style?.foregroundColor?.resolve({}) ?? cs.primary;

          for (final surf in [cs.surface, cs.surfaceContainer, cs.surfaceContainerHigh]) {
            final oRatio = AppAccessibility.calculateContrastRatio(outlinedFg, surf);
            final tRatio = AppAccessibility.calculateContrastRatio(textFg, surf);

            debugPrint('[$themeName] OutlinedButton on $surf = ${oRatio.toStringAsFixed(2)}:1, TextButton = ${tRatio.toStringAsFixed(2)}:1');

            expect(oRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] OutlinedButton on $surf');
            expect(tRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] TextButton on $surf');
          }
        });

        test('[$themeName] FloatingActionButton foreground on background meets AA', () {
          final fab = theme.floatingActionButtonTheme;
          final bg = fab.backgroundColor ?? cs.primary;
          final fg = fab.foregroundColor ?? cs.onPrimary;

          final ratio = AppAccessibility.calculateContrastRatio(fg, bg);
          debugPrint('[$themeName] FAB: fg on bg = ${ratio.toStringAsFixed(2)}:1');

          expect(ratio, greaterThanOrEqualTo(4.5), reason: '[$themeName] FAB fg on bg');
        });

        test('[$themeName] SegmentedButton selected and unselected states meet AA contrast', () {
          final segStyle = theme.segmentedButtonTheme.style!;

          final selBg = segStyle.backgroundColor?.resolve({WidgetState.selected}) ?? cs.primaryContainer;
          final selFg = segStyle.foregroundColor?.resolve({WidgetState.selected}) ?? cs.onPrimaryContainer;
          final selRatio = AppAccessibility.calculateContrastRatio(selFg, selBg);

          final unselBg = segStyle.backgroundColor?.resolve({}) ?? cs.surfaceContainerHigh;
          final unselFg = segStyle.foregroundColor?.resolve({}) ?? cs.onSurfaceVariant;
          final unselRatio = AppAccessibility.calculateContrastRatio(unselFg, unselBg);

          debugPrint('[$themeName] SegmentedButton: selected = ${selRatio.toStringAsFixed(2)}:1, unselected = ${unselRatio.toStringAsFixed(2)}:1');

          expect(selRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] SegmentedButton selected');
          expect(unselRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] SegmentedButton unselected');
        });

        test('[$themeName] ChipTheme selected and unselected labels meet AA contrast', () {
          final chip = theme.chipTheme;

          final unselBg = chip.backgroundColor ?? cs.surfaceContainerHigh;
          final unselFg = chip.labelStyle?.color ?? cs.onSurface;
          final unselRatio = AppAccessibility.calculateContrastRatio(unselFg, unselBg);

          final selBg = chip.selectedColor ?? cs.primaryContainer;
          final selFg = chip.secondaryLabelStyle?.color ?? cs.onPrimaryContainer;
          final selRatio = AppAccessibility.calculateContrastRatio(selFg, selBg);

          debugPrint('[$themeName] Chip: unselected = ${unselRatio.toStringAsFixed(2)}:1, selected = ${selRatio.toStringAsFixed(2)}:1');

          expect(unselRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] Chip unselected');
          expect(selRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] Chip selected');
        });

        test('[$themeName] InputDecorationTheme labels and focus ring meet WCAG requirements', () {
          final input = theme.inputDecorationTheme;
          final rawFill = input.fillColor ?? cs.surfaceContainerHighest;
          final effectiveFill = Color.alphaBlend(rawFill, theme.scaffoldBackgroundColor);

          final labelColor = input.labelStyle?.color ?? cs.onSurfaceVariant;
          final labelRatio = AppAccessibility.calculateContrastRatio(labelColor, effectiveFill);

          debugPrint('[$themeName] InputDecoration: label on fill = ${labelRatio.toStringAsFixed(2)}:1');
          expect(labelRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] Input label on fill');

          final focusedBorder = input.focusedBorder as OutlineInputBorder?;
          if (focusedBorder != null) {
            final focusColor = focusedBorder.borderSide.color;
            final focusRatio = AppAccessibility.calculateContrastRatio(focusColor, theme.scaffoldBackgroundColor);
            debugPrint('[$themeName] InputDecoration: focus ring on scaffold = ${focusRatio.toStringAsFixed(2)}:1');
            expect(focusRatio, greaterThanOrEqualTo(3.0), reason: '[$themeName] Focus ring on scaffold');
          }
        });
      }
    });

    // =========================================================================
    // 4. Task 5: Semantic Status Roles & Container Pairs
    // =========================================================================
    group('Task 5: Semantic Status Roles & Container Pairs Stress Test', () {
      for (final themeEntry in themes.entries) {
        final themeName = themeEntry.key;
        final theme = themeEntry.value;
        final sem = theme.extension<VidraSemanticColors>()!;
        final cardBase = theme.colorScheme.surfaceContainer;

        test('[$themeName] on<Status>Container on <Status>Container meets AA (>= 4.5:1)', () {
          final successContainerRatio = AppAccessibility.calculateContrastRatio(sem.onSuccessContainer, sem.successContainer);
          final warningContainerRatio = AppAccessibility.calculateContrastRatio(sem.onWarningContainer, sem.warningContainer);
          final errorContainerRatio = AppAccessibility.calculateContrastRatio(sem.onErrorContainer, sem.errorContainer);
          final infoContainerRatio = AppAccessibility.calculateContrastRatio(sem.onInfoContainer, sem.infoContainer);
          final muxingContainerRatio = AppAccessibility.calculateContrastRatio(sem.onMuxingContainer, sem.muxingContainer);

          debugPrint('[$themeName] onStatusContainer on Container: Success=${successContainerRatio.toStringAsFixed(2)}:1, Warning=${warningContainerRatio.toStringAsFixed(2)}:1, Error=${errorContainerRatio.toStringAsFixed(2)}:1, Info=${infoContainerRatio.toStringAsFixed(2)}:1, Muxing=${muxingContainerRatio.toStringAsFixed(2)}:1');

          expect(successContainerRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] onSuccessContainer on successContainer');
          expect(warningContainerRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] onWarningContainer on warningContainer');
          expect(errorContainerRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] onErrorContainer on errorContainer');
          expect(infoContainerRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] onInfoContainer on infoContainer');
          expect(muxingContainerRatio, greaterThanOrEqualTo(4.5), reason: '[$themeName] onMuxingContainer on muxingContainer');
        });

        test('[$themeName] Primary semantic status indicators on card base meet graphical/UI standard (>= 3.0:1)', () {
          final successRatio = AppAccessibility.calculateContrastRatio(sem.success, cardBase);
          final warningRatio = AppAccessibility.calculateContrastRatio(sem.warning, cardBase);
          final errorRatio = AppAccessibility.calculateContrastRatio(sem.error, cardBase);
          final infoRatio = AppAccessibility.calculateContrastRatio(sem.info, cardBase);
          final muxingRatio = AppAccessibility.calculateContrastRatio(sem.muxing, cardBase);

          debugPrint('[$themeName] Status on cardBase: Success=${successRatio.toStringAsFixed(2)}:1, Warning=${warningRatio.toStringAsFixed(2)}:1, Error=${errorRatio.toStringAsFixed(2)}:1, Info=${infoRatio.toStringAsFixed(2)}:1, Muxing=${muxingRatio.toStringAsFixed(2)}:1');

          expect(successRatio, greaterThanOrEqualTo(3.0), reason: '[$themeName] status success on card');
          expect(warningRatio, greaterThanOrEqualTo(3.0), reason: '[$themeName] status warning on card');
          expect(errorRatio, greaterThanOrEqualTo(3.0), reason: '[$themeName] status error on card');
          expect(infoRatio, greaterThanOrEqualTo(3.0), reason: '[$themeName] status info on card');
          expect(muxingRatio, greaterThanOrEqualTo(3.0), reason: '[$themeName] status muxing on card');
        });
      }
    });
  });
}
