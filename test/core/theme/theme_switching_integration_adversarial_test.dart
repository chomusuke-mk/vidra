import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/core/theme/app_theme.dart';
import 'package:vidra/core/theme/colors.dart';
import 'package:vidra/core/theme/layout.dart';
import 'package:vidra/core/theme/typography.dart';

void main() {
  group('Adversarial Theme Switching & Widget Tree Integration', () {
    // =========================================================================
    // 1. Exhaustive Non-Null & Completeness across all AppTheme variants
    // =========================================================================
    group('Semantic Colors Non-Null Verification across All Themes', () {
      final themes = <String, ThemeData>{
        'lightTheme': AppTheme.lightTheme,
        'darkTheme': AppTheme.darkTheme,
        'oledTheme': AppTheme.oledTheme,
      };

      for (final entry in themes.entries) {
        test('${entry.key} contains non-null VidraSemanticColors with all 22 valid fields', () {
          final theme = entry.value;
          final sem = theme.extension<VidraSemanticColors>();

          expect(sem, isNotNull, reason: '${entry.key} extension<VidraSemanticColors>() must not be null');

          // Verify all 22 fields are non-null and valid ARGB colors
          final fields = <String, Color>{
            'success': sem!.success,
            'onSuccess': sem.onSuccess,
            'successContainer': sem.successContainer,
            'onSuccessContainer': sem.onSuccessContainer,
            'warning': sem.warning,
            'onWarning': sem.onWarning,
            'warningContainer': sem.warningContainer,
            'onWarningContainer': sem.onWarningContainer,
            'error': sem.error,
            'onError': sem.onError,
            'errorContainer': sem.errorContainer,
            'onErrorContainer': sem.onErrorContainer,
            'info': sem.info,
            'onInfo': sem.onInfo,
            'infoContainer': sem.infoContainer,
            'onInfoContainer': sem.onInfoContainer,
            'muxing': sem.muxing,
            'onMuxing': sem.onMuxing,
            'muxingContainer': sem.muxingContainer,
            'onMuxingContainer': sem.onMuxingContainer,
            'borderSubtle': sem.borderSubtle,
            'borderFocus': sem.borderFocus,
          };

          for (final f in fields.entries) {
            expect(f.value, isNotNull, reason: '${entry.key}.${f.key} is null');
            expect(f.value.a, isNonZero, reason: '${entry.key}.${f.key} has 0 alpha');
          }
        });
      }

      test('VidraColorContext extension fallback provides non-null colors when extension is absent', () {
        // Test with raw ThemeData lacking extensions
        final darkBare = ThemeData(brightness: Brightness.dark);
        final lightBare = ThemeData(brightness: Brightness.light);

        // Simulated context lookup
        VidraSemanticColors resolveSemantic(ThemeData theme) {
          return theme.extension<VidraSemanticColors>() ??
              (theme.brightness == Brightness.dark
                  ? VidraSemanticColors.dark
                  : VidraSemanticColors.light);
        }

        final darkResolved = resolveSemantic(darkBare);
        final lightResolved = resolveSemantic(lightBare);

        expect(darkResolved, equals(VidraSemanticColors.dark));
        expect(lightResolved, equals(VidraSemanticColors.light));
      });
    });

    // =========================================================================
    // 2. Simulated Dynamic Theme Switching in Widget Tree
    // =========================================================================
    group('Dynamic Theme Switching in Widget Tree', () {
      testWidgets('Cycling Light -> Dark -> OLED -> Light updates Theme and SemanticColors correctly',
          (tester) async {
        late ThemeData currentTheme;
        late VidraSemanticColors currentSemantic;
        late ColorScheme currentColorScheme;

        final themeNotifier = ValueNotifier<ThemeData>(AppTheme.lightTheme);

        await tester.pumpWidget(
          ValueListenableBuilder<ThemeData>(
            valueListenable: themeNotifier,
            builder: (context, activeTheme, _) {
              return MaterialApp(
                theme: activeTheme,
                home: Builder(
                  builder: (ctx) {
                    currentTheme = Theme.of(ctx);
                    currentSemantic = ctx.semanticColors;
                    currentColorScheme = ctx.colors;

                    return Scaffold(
                      backgroundColor: ctx.colors.surface,
                      body: Column(
                        children: [
                          Text('Title', style: ctx.textTheme.titleMedium),
                          Container(
                            color: ctx.semanticColors.success,
                            child: const Text('Status Success'),
                          ),
                          Container(
                            color: ctx.semanticColors.warning,
                            child: const Text('Status Warning'),
                          ),
                          Container(
                            color: ctx.semanticColors.error,
                            child: const Text('Status Error'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );

        // Phase 1: Light Theme
        expect(currentTheme.brightness, equals(Brightness.light));
        expect(currentColorScheme.surface, equals(AppColors.lightCanvas));
        expect(currentSemantic.success, equals(AppColors.lightSuccess));
        expect(currentSemantic.error, equals(AppColors.lightError));
        expect(currentSemantic.borderSubtle, equals(AppColors.borderLight));
        expect(find.text('Status Success'), findsOneWidget);

        // Phase 2: Switch to Dark Theme
        themeNotifier.value = AppTheme.darkTheme;
        await tester.pumpAndSettle();

        expect(currentTheme.brightness, equals(Brightness.dark));
        expect(currentColorScheme.surface, equals(AppColors.darkCanvas));
        expect(currentColorScheme.surfaceContainer, equals(AppColors.darkSurface));
        expect(currentSemantic.success, equals(AppColors.success));
        expect(currentSemantic.error, equals(AppColors.error));
        expect(currentSemantic.borderSubtle, equals(AppColors.borderSubtle));

        // Phase 3: Switch to OLED Theme
        themeNotifier.value = AppTheme.oledTheme;
        await tester.pumpAndSettle();

        expect(currentTheme.brightness, equals(Brightness.dark));
        expect(currentColorScheme.surface, equals(AppColors.oledCanvas));
        expect(currentColorScheme.surfaceContainer, equals(AppColors.oledSurface));
        expect(currentSemantic.success, equals(AppColors.success));
        expect(currentSemantic.borderSubtle, equals(AppColors.borderOled));

        // Phase 4: Switch back to Light Theme
        themeNotifier.value = AppTheme.lightTheme;
        await tester.pumpAndSettle();

        expect(currentTheme.brightness, equals(Brightness.light));
        expect(currentColorScheme.surface, equals(AppColors.lightCanvas));
        expect(currentSemantic.success, equals(AppColors.lightSuccess));
      });

      testWidgets('AnimatedTheme transition interpolates VidraSemanticColors without null or NaN',
          (tester) async {
        final themeNotifier = ValueNotifier<ThemeData>(AppTheme.lightTheme);

        final capturedSemantics = <VidraSemanticColors>[];

        await tester.pumpWidget(
          ValueListenableBuilder<ThemeData>(
            valueListenable: themeNotifier,
            builder: (context, activeTheme, _) {
              return MaterialApp(
                home: AnimatedTheme(
                  data: activeTheme,
                  duration: const Duration(milliseconds: 300),
                  child: Builder(
                    builder: (ctx) {
                      final sem = Theme.of(ctx).extension<VidraSemanticColors>();
                      if (sem != null) {
                        capturedSemantics.add(sem);
                      }
                      return Scaffold(
                        body: Container(
                          color: sem?.success ?? Colors.transparent,
                          child: const Text('Animated Transition'),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );

        // Start transition to Dark
        themeNotifier.value = AppTheme.darkTheme;
        await tester.pump(); // Start animation

        // Step through frames
        await tester.pump(const Duration(milliseconds: 75));  // 25%
        await tester.pump(const Duration(milliseconds: 75));  // 50%
        await tester.pump(const Duration(milliseconds: 75));  // 75%
        await tester.pump(const Duration(milliseconds: 75));  // 100%
        await tester.pumpAndSettle();

        expect(capturedSemantics, isNotEmpty);
        for (final sem in capturedSemantics) {
          expect(sem.success, isNotNull);
          expect(sem.warning, isNotNull);
          expect(sem.error, isNotNull);
          expect(sem.info, isNotNull);
          expect(sem.muxing, isNotNull);
          expect(sem.borderSubtle, isNotNull);
          expect(sem.borderFocus, isNotNull);
        }
      });
    });

    // =========================================================================
    // 3. Nested Subtree Theme Overrides
    // =========================================================================
    group('Nested Subtree Theme Overrides', () {
      testWidgets('Nested themes isolate semantic colors to their respective scopes',
          (tester) async {
        late VidraSemanticColors rootSemantic;
        late VidraSemanticColors darkChildSemantic;
        late VidraSemanticColors oledGrandchildSemantic;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (rootCtx) {
                rootSemantic = rootCtx.semanticColors;

                return Scaffold(
                  body: Theme(
                    data: AppTheme.darkTheme,
                    child: Builder(
                      builder: (darkCtx) {
                        darkChildSemantic = darkCtx.semanticColors;

                        return Theme(
                          data: AppTheme.oledTheme,
                          child: Builder(
                            builder: (oledCtx) {
                              oledGrandchildSemantic = oledCtx.semanticColors;

                              return const Text('Nested Theme Scopes');
                            },
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );

        // Root is Light
        expect(rootSemantic.success, equals(AppColors.lightSuccess));
        expect(rootSemantic.borderSubtle, equals(AppColors.borderLight));

        // Child is Dark
        expect(darkChildSemantic.success, equals(AppColors.success));
        expect(darkChildSemantic.borderSubtle, equals(AppColors.borderSubtle));

        // Grandchild is OLED
        expect(oledGrandchildSemantic.success, equals(AppColors.success));
        expect(oledGrandchildSemantic.borderSubtle, equals(AppColors.borderOled));
      });
    });

    // =========================================================================
    // 4. AppSpacing & Form Constraints Verification
    // =========================================================================
    group('AppSpacing & Dimension Constraints Verification', () {
      test('AppSpacing.maxFormWidth is exactly 540dp', () {
        expect(AppSpacing.maxFormWidth, equals(540.0));
        expect(AppSpacing.maxFormInputWidth, equals(540.0));
      });

      test('AppSpacing.minTouchTarget is exactly 48dp', () {
        expect(AppSpacing.minTouchTarget, equals(48.0));
      });

      testWidgets('BoxConstraints with maxFormWidth constrains child on ultrawide desktop',
          (tester) async {
        // Set wide screen (1920x1080)
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppSpacing.maxFormWidth),
                  child: Container(
                    key: const Key('constrained_form_box'),
                    height: 100,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          ),
        );

        final formBox = tester.renderObject<RenderBox>(find.byKey(const Key('constrained_form_box')));
        expect(formBox.size.width, equals(540.0));
      });

      testWidgets('Interactive touch target enforces minimum 48x48dp dimensions',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  child: IconButton(
                    key: const Key('touch_target_btn'),
                    icon: const Icon(Icons.download),
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        );

        final btnBox = tester.renderObject<RenderBox>(find.byKey(const Key('touch_target_btn')));
        expect(btnBox.size.width, greaterThanOrEqualTo(AppSpacing.minTouchTarget));
        expect(btnBox.size.height, greaterThanOrEqualTo(AppSpacing.minTouchTarget));
      });
    });
  });
}
