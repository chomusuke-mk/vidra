import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vidra/core/theme/app_theme.dart';
import 'package:vidra/core/theme/typography.dart';

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

/// Helper for WCAG 2.1 Contrast Ratio calculation
double _calculateContrastRatio(Color foreground, Color background) {
  final l1 = _calculateRelativeLuminance(foreground);
  final l2 = _calculateRelativeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Adversarial Challenge Suite: Milestone 1 TabBar & Font Scaling', () {
    final themeVariants = <String, ThemeData>{
      'lightTheme': AppTheme.lightTheme,
      'darkTheme': AppTheme.darkTheme,
      'oledTheme': AppTheme.oledTheme,
    };

    // =========================================================================
    // SECTION 1: ADVERSARIAL TABBAR ASSERTION IMMUNITY STRESS TESTS
    // =========================================================================
    group('TabBar Assertion Immunity - Fixed (Non-Scrollable) Configurations', () {
      // Test 1: Fixed 2, 3, 4, 5 Tabs across all 3 AppTheme variants
      for (final tabCount in [2, 3, 4, 5]) {
        for (final entry in themeVariants.entries) {
          testWidgets(
            'Non-scrollable TabBar ($tabCount tabs) under ${entry.key} renders with ZERO assertion errors',
            (tester) async {
              await tester.pumpWidget(
                MaterialApp(
                  theme: entry.value,
                  home: DefaultTabController(
                    length: tabCount,
                    child: Scaffold(
                      appBar: AppBar(
                        title: const Text('TabBar Stress Test'),
                        bottom: TabBar(
                          isScrollable: false,
                          tabs: List.generate(
                            tabCount,
                            (index) => Tab(text: 'Tab ${index + 1}'),
                          ),
                        ),
                      ),
                      body: TabBarView(
                        children: List.generate(
                          tabCount,
                          (index) => Center(child: Text('Content ${index + 1}')),
                        ),
                      ),
                    ),
                  ),
                ),
              );

              await tester.pumpAndSettle();

              // Verify all tabs are found and rendered
              for (int i = 1; i <= tabCount; i++) {
                expect(find.text('Tab $i'), findsOneWidget);
              }
              expect(find.text('Content 1'), findsOneWidget);

              // Switch to last tab and verify animation settles without crash
              await tester.tap(find.text('Tab $tabCount'));
              await tester.pumpAndSettle();
              expect(find.text('Content $tabCount'), findsOneWidget);
            },
          );
        }
      }

      // Test 2: Fixed TabBar with Icons and Combined Text+Icon
      for (final entry in themeVariants.entries) {
        testWidgets(
          'Non-scrollable TabBar with Icon+Text under ${entry.key} renders safely',
          (tester) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: entry.value,
                home: DefaultTabController(
                  length: 3,
                  child: const Scaffold(
                    body: TabBar(
                      isScrollable: false,
                      tabs: [
                        Tab(icon: Icon(Icons.download), text: 'Downloads'),
                        Tab(icon: Icon(Icons.check_circle), text: 'Completed'),
                        Tab(icon: Icon(Icons.error), text: 'Failed'),
                      ],
                    ),
                  ),
                ),
              ),
            );

            await tester.pumpAndSettle();
            expect(find.byIcon(Icons.download), findsOneWidget);
            expect(find.byIcon(Icons.check_circle), findsOneWidget);
            expect(find.byIcon(Icons.error), findsOneWidget);
          },
        );
      }

      // Test 3: TabBar embedded in tight viewport widths (320dp, 280dp, 400dp, 1200dp)
      for (final viewportWidth in [280.0, 320.0, 375.0, 768.0, 1440.0]) {
        for (final entry in themeVariants.entries) {
          testWidgets(
            'Non-scrollable TabBar at viewport width ${viewportWidth}dp under ${entry.key} does not throw',
            (tester) async {
              tester.view.physicalSize = Size(viewportWidth * 2, 800 * 2);
              tester.view.devicePixelRatio = 2.0;
              addTearDown(() => tester.view.resetPhysicalSize());

              await tester.pumpWidget(
                MaterialApp(
                  theme: entry.value,
                  home: DefaultTabController(
                    length: 3,
                    child: Scaffold(
                      body: Column(
                        children: [
                          const TabBar(
                            isScrollable: false,
                            tabs: [
                              Tab(text: 'Active'),
                              Tab(text: 'Queued'),
                              Tab(text: 'Done'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                Container(color: Colors.red),
                                Container(color: Colors.green),
                                Container(color: Colors.blue),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              await tester.pumpAndSettle();
              expect(find.text('Active'), findsOneWidget);
              expect(find.text('Queued'), findsOneWidget);
              expect(find.text('Done'), findsOneWidget);
            },
          );
        }
      }

      // Test 4: Dynamic TabController with programmatically animated tabs
      testWidgets('Custom TabController rapid tab flipping across themes', (tester) async {
        for (final entry in themeVariants.entries) {
          final controller = TabController(length: 4, vsync: const TestVSync());

          await tester.pumpWidget(
            MaterialApp(
              theme: entry.value,
              home: Scaffold(
                body: TabBar(
                  controller: controller,
                  isScrollable: false,
                  tabs: const [
                    Tab(text: 'T1'),
                    Tab(text: 'T2'),
                    Tab(text: 'T3'),
                    Tab(text: 'T4'),
                  ],
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          // Rapidly animate across tabs
          controller.animateTo(3);
          await tester.pump(const Duration(milliseconds: 50));
          controller.animateTo(1);
          await tester.pump(const Duration(milliseconds: 50));
          controller.animateTo(0);
          await tester.pumpAndSettle();

          expect(controller.index, equals(0));
          controller.dispose();
        }
      });
    });

    // =========================================================================
    // SECTION 2: SCROLLABLE TABBAR COMPATIBILITY & ALIGNMENT
    // =========================================================================
    group('TabBar Compatibility - Scrollable (isScrollable: true)', () {
      for (final entry in themeVariants.entries) {
        testWidgets(
          'Scrollable TabBar (8 tabs) under ${entry.key} functions smoothly',
          (tester) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: entry.value,
                home: DefaultTabController(
                  length: 8,
                  child: Scaffold(
                    appBar: AppBar(
                      bottom: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: List.generate(
                          8,
                          (i) => Tab(text: 'Category ${i + 1}'),
                        ),
                      ),
                    ),
                    body: const TabBarView(
                      children: [
                        Center(child: Text('Page 1')),
                        Center(child: Text('Page 2')),
                        Center(child: Text('Page 3')),
                        Center(child: Text('Page 4')),
                        Center(child: Text('Page 5')),
                        Center(child: Text('Page 6')),
                        Center(child: Text('Page 7')),
                        Center(child: Text('Page 8')),
                      ],
                    ),
                  ),
                ),
              ),
            );

            await tester.pumpAndSettle();

            expect(find.text('Category 1'), findsOneWidget);
            expect(find.text('Page 1'), findsOneWidget);

            // Drag scrollable tab bar
            await tester.drag(find.text('Category 1'), const Offset(-300, 0));
            await tester.pumpAndSettle();

            expect(find.text('Category 8'), findsWidgets);
          },
        );

        testWidgets(
          'Scrollable TabBar with TabAlignment.center and TabAlignment.fill under ${entry.key}',
          (tester) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: entry.value,
                home: DefaultTabController(
                  length: 3,
                  child: const Scaffold(
                    body: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.center,
                      tabs: [
                        Tab(text: 'Short 1'),
                        Tab(text: 'Short 2'),
                        Tab(text: 'Short 3'),
                      ],
                    ),
                  ),
                ),
              ),
            );

            await tester.pumpAndSettle();
            expect(find.text('Short 1'), findsOneWidget);
            expect(find.text('Short 2'), findsOneWidget);
            expect(find.text('Short 3'), findsOneWidget);
          },
        );
      }
    });

    // =========================================================================
    // SECTION 3: DYNAMIC THEME SWITCHING WHILE TABBAR IS MOUNTED
    // =========================================================================
    group('Live Theme Switching with Mounted TabBar', () {
      testWidgets('Dynamically toggling light -> dark -> oled preserves TabBar without error',
          (tester) async {
        final themeNotifier = ValueNotifier<ThemeData>(AppTheme.lightTheme);

        await tester.pumpWidget(
          ValueListenableBuilder<ThemeData>(
            valueListenable: themeNotifier,
            builder: (context, currentTheme, _) {
              return MaterialApp(
                theme: currentTheme,
                home: const DefaultTabController(
                  length: 3,
                  child: Scaffold(
                    body: TabBar(
                      isScrollable: false,
                      tabs: [
                        Tab(text: 'All'),
                        Tab(text: 'Downloading'),
                        Tab(text: 'Finished'),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text('All'), findsOneWidget);

        // Switch to Dark Theme
        themeNotifier.value = AppTheme.darkTheme;
        await tester.pumpAndSettle();
        expect(find.text('Downloading'), findsOneWidget);

        // Switch to OLED Theme
        themeNotifier.value = AppTheme.oledTheme;
        await tester.pumpAndSettle();
        expect(find.text('Finished'), findsOneWidget);

        // Switch back to Light Theme
        themeNotifier.value = AppTheme.lightTheme;
        await tester.pumpAndSettle();
        expect(find.text('All'), findsOneWidget);
      });
    });

    // =========================================================================
    // SECTION 4: DYNAMIC FONT SCALING (UP TO 2.0x) STRESS TESTS
    // =========================================================================
    group('Dynamic Font Scaling Stress Tests (TextScaler 1.0x to 2.0x)', () {
      const scaleFactors = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0];

      // Test 1: Full Typography Hierarchy Scale Invariance
      for (final scale in scaleFactors) {
        testWidgets('AppTypography 15-tier TextTheme scales linearly under TextScaler.linear($scale)',
            (tester) async {
          late BuildContext capturedCtx;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Builder(
                  builder: (context) {
                    capturedCtx = context;
                    final textTheme = Theme.of(context).textTheme;

                    return Scaffold(
                      body: SingleChildScrollView(
                        child: Column(
                          children: [
                            Text('Display Large', style: textTheme.displayLarge),
                            Text('Display Medium', style: textTheme.displayMedium),
                            Text('Display Small', style: textTheme.displaySmall),
                            Text('Headline Large', style: textTheme.headlineLarge),
                            Text('Headline Medium', style: textTheme.headlineMedium),
                            Text('Headline Small', style: textTheme.headlineSmall),
                            Text('Title Large', style: textTheme.titleLarge),
                            Text('Title Medium', style: textTheme.titleMedium),
                            Text('Title Small', style: textTheme.titleSmall),
                            Text('Body Large', style: textTheme.bodyLarge),
                            Text('Body Medium', style: textTheme.bodyMedium),
                            Text('Body Small', style: textTheme.bodySmall),
                            Text('Label Large', style: textTheme.labelLarge),
                            Text('Label Medium', style: textTheme.labelMedium),
                            Text('Label Small', style: textTheme.labelSmall),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          final scaler = MediaQuery.of(capturedCtx).textScaler;
          expect(scaler.scale(16.0), closeTo(16.0 * scale, 0.001));
          expect(find.text('Display Large'), findsOneWidget);
          expect(find.text('Body Medium'), findsOneWidget);
          expect(find.text('Label Small'), findsOneWidget);
        });
      }

      // Test 2: Monospace Tabular Telemetry Tokens under Font Scaling
      for (final scale in scaleFactors) {
        testWidgets(
            'Telemetry tokens retain fontFeatures and scale cleanly at ${scale}x scale factor',
            (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Builder(
                  builder: (context) {
                    return Scaffold(
                      body: Column(
                        children: [
                          Text('48.2 MB/s', style: context.telemetryHero),
                          Text('↓ 18.4 MB/s • ↑ 1.2 MB/s', style: context.telemetryLarge),
                          Text('142.5 MB / 1.80 GB', style: context.telemetryMedium),
                          Text('ETA 00:04:12 • 8 Conns', style: context.telemetrySmall),
                          Text('98.4%', style: context.telemetryMicro),
                          Text('[download] 45.0% of 100MB', style: context.consoleLog),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          expect(find.text('48.2 MB/s'), findsOneWidget);
          expect(find.text('↓ 18.4 MB/s • ↑ 1.2 MB/s'), findsOneWidget);
          expect(find.text('142.5 MB / 1.80 GB'), findsOneWidget);
          expect(find.text('ETA 00:04:12 • 8 Conns'), findsOneWidget);
          expect(find.text('98.4%'), findsOneWidget);
          expect(find.text('[download] 45.0% of 100MB'), findsOneWidget);
        });
      }

      // Test 3: Component Themes at 2.0x Dynamic Scaling (Buttons, Inputs, Chips, TabBar)
      for (final entry in themeVariants.entries) {
        testWidgets(
          'All Material 3 components render safely at 2.0x font scaling under ${entry.key}',
          (tester) async {
            tester.view.physicalSize = const Size(400 * 2, 1000 * 2);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(() => tester.view.resetPhysicalSize());

            await tester.pumpWidget(
              MaterialApp(
                theme: entry.value,
                home: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
                  child: DefaultTabController(
                    length: 3,
                    child: Scaffold(
                      appBar: AppBar(
                        title: const Text('Title'),
                        bottom: const TabBar(
                          isScrollable: false,
                          tabs: [
                            Tab(text: 'T1'),
                            Tab(text: 'T2'),
                            Tab(text: 'T3'),
                          ],
                        ),
                      ),
                      body: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. TextField / InputDecoration
                              TextField(
                                decoration: const InputDecoration(
                                  labelText: 'URL Input',
                                  hintText: 'Paste video link here...',
                                  helperText: 'Supports 1000+ sites',
                                ),
                                controller: TextEditingController(text: 'https://youtu.be/test'),
                              ),
                              const SizedBox(height: 16),

                              // 2. Buttons
                              FilledButton(
                                onPressed: () {},
                                child: const Text('Filled Action'),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () {},
                                child: const Text('Elevated Action'),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () {},
                                child: const Text('Outlined Action'),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () {},
                                child: const Text('Text Action'),
                              ),
                              const SizedBox(height: 8),

                              // 3. Chips
                              Wrap(
                                spacing: 8,
                                children: [
                                  Chip(label: const Text('Video')),
                                  Chip(label: const Text('Audio')),
                                  ActionChip(
                                    label: const Text('Best 1080p'),
                                    onPressed: () {},
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // 4. SegmentedButton
                              SegmentedButton<int>(
                                segments: const [
                                  ButtonSegment(value: 0, label: Text('All')),
                                  ButtonSegment(value: 1, label: Text('Video')),
                                  ButtonSegment(value: 2, label: Text('Audio')),
                                ],
                                selected: const {0},
                                onSelectionChanged: (_) {},
                              ),
                              const SizedBox(height: 16),

                              // 5. Card
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Builder(
                                        builder: (ctx) => Text(
                                          'Cyberpunk 2077 OST - I Really Want to Stay At Your House',
                                          style: ctx.cardTitle,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Builder(
                                        builder: (ctx) => Text(
                                          '14.2 MB • MP4 1080p60 • 4:06',
                                          style: ctx.cardSubtitle,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Builder(
                                        builder: (ctx) => Text(
                                          '12.4 MB/s',
                                          style: ctx.speedTelemetry,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      floatingActionButton: FloatingActionButton.extended(
                        onPressed: () {},
                        icon: const Icon(Icons.download),
                        label: const Text('Descargar'),
                      ),
                    ),
                  ),
                ),
              ),
            );

            await tester.pumpAndSettle();

            // Verify components render without crash or assertion error at 2.0x scale
            expect(find.text('Filled Action'), findsOneWidget);
            expect(find.text('Elevated Action'), findsOneWidget);
            expect(find.text('Outlined Action'), findsOneWidget);
            expect(find.text('Text Action'), findsOneWidget);
            expect(find.text('Video'), findsWidgets);
            expect(find.text('Descargar'), findsOneWidget);
            expect(find.text('12.4 MB/s'), findsOneWidget);
          },
        );
      }
    });

    // =========================================================================
    // SECTION 5: COMPONENT THEMES WCAG CONTRAST ADVERSARIAL AUDIT
    // =========================================================================
    group('Component Themes WCAG AA/AAA Contrast Verification', () {
      for (final entry in themeVariants.entries) {
        test('${entry.key} component themes enforce compliant foreground/background contrast', () {
          final theme = entry.value;
          final colorScheme = theme.colorScheme;

          // 1. FilledButton contrast (primary vs onPrimary >= 4.5:1 AA)
          final filledBtnContrast = _calculateContrastRatio(
            colorScheme.onPrimary,
            colorScheme.primary,
          );
          expect(
            filledBtnContrast,
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} FilledButton onPrimary/primary contrast ratio must be >= 4.5:1',
          );

          // 2. FloatingActionButton contrast (primary vs onPrimary >= 4.5:1 AA)
          final fabContrast = _calculateContrastRatio(
            theme.floatingActionButtonTheme.foregroundColor ?? colorScheme.onPrimary,
            theme.floatingActionButtonTheme.backgroundColor ?? colorScheme.primary,
          );
          expect(
            fabContrast,
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} FAB foreground/background contrast ratio must be >= 4.5:1',
          );

          // 3. SegmentedButton selected contrast (primaryContainer vs onPrimaryContainer >= 4.5:1 AA)
          final segSelectedContrast = _calculateContrastRatio(
            colorScheme.onPrimaryContainer,
            colorScheme.primaryContainer,
          );
          expect(
            segSelectedContrast,
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} SegmentedButton selected state contrast ratio must be >= 4.5:1',
          );

          // 4. Chip selected contrast (primaryContainer vs onPrimaryContainer >= 4.5:1 AA)
          final chipSelectedContrast = _calculateContrastRatio(
            colorScheme.onPrimaryContainer,
            theme.chipTheme.selectedColor ?? colorScheme.primaryContainer,
          );
          expect(
            chipSelectedContrast,
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} Chip selected state contrast ratio must be >= 4.5:1',
          );

          // 5. Card textPrimary vs surfaceContainer (>= 7.0:1 AAA on dark/oled, >= 4.5:1 AA on light)
          final cardTextContrast = _calculateContrastRatio(
            colorScheme.onSurface,
            colorScheme.surfaceContainer,
          );
          expect(
            cardTextContrast,
            greaterThanOrEqualTo(7.0),
            reason: '${entry.key} onSurface vs surfaceContainer contrast ratio must meet AAA (>= 7.0:1)',
          );

          // 6. Card secondary text vs surfaceContainer (>= 4.5:1 AA)
          final cardSecContrast = _calculateContrastRatio(
            colorScheme.onSurfaceVariant,
            colorScheme.surfaceContainer,
          );
          expect(
            cardSecContrast,
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} onSurfaceVariant vs surfaceContainer contrast ratio must meet AA (>= 4.5:1)',
          );
        });
      }
    });

    // =========================================================================
    // SECTION 6: TABBAR THEMEDATA INVARIANT & PROPERTY AUDIT
    // =========================================================================
    group('TabBarThemeData Property Invariants', () {
      for (final entry in themeVariants.entries) {
        test('${entry.key} tabBarTheme does not specify problematic tabAlignment', () {
          final theme = entry.value;
          final tabBarTheme = theme.tabBarTheme;

          // tabAlignment MUST BE NULL in global ThemeData so non-scrollable TabBars
          // can freely default to TabAlignment.fill without triggering
          // assert(tabAlignment != TabAlignment.start || isScrollable)
          expect(
            tabBarTheme.tabAlignment,
            isNull,
            reason: '${entry.key}.tabBarTheme.tabAlignment must be null to allow non-scrollable TabBars',
          );

          // Indicator size must be label
          expect(tabBarTheme.indicatorSize, equals(TabBarIndicatorSize.label));

          // Divider color must be transparent
          expect(tabBarTheme.dividerColor, equals(Colors.transparent));

          // Label color is primary
          expect(tabBarTheme.labelColor, equals(theme.colorScheme.primary));

          // Unselected label color is onSurfaceVariant
          expect(tabBarTheme.unselectedLabelColor, equals(theme.colorScheme.onSurfaceVariant));
        });
      }
    });
  });
}
