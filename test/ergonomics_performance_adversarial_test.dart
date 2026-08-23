import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// =============================================================================
// EMPIRICAL ADVERSARIAL TEST SUITE (CHALLENGER 1: ERGONOMICS & PERFORMANCE)
// =============================================================================

/// DualLineGraphPainter reproduction from tarjetas_y_componentes.md line 1010
class BuggyDualLineGraphPainter extends CustomPainter {
  final List<double> history;
  final Color networkColor;
  final Color diskColor;

  BuggyDualLineGraphPainter({
    required this.history,
    required this.networkColor,
    required this.diskColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final paintNetwork = Paint()
      ..color = networkColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    // VULNERABILITY 3.3: Division by zero when history.length == 1
    final step = size.width / (history.length - 1);

    for (int i = 0; i < history.length; i++) {
      final x = i * step;
      final y = size.height - (history[i] * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paintNetwork);
  }

  @override
  bool shouldRepaint(covariant BuggyDualLineGraphPainter oldDelegate) => true;
}

/// Fixed DualLineGraphPainter with 1-element safety and disk speed rendering
class FixedDualLineGraphPainter extends CustomPainter {
  final List<double> networkHistory;
  final List<double> diskHistory;
  final Color networkColor;
  final Color diskColor;

  FixedDualLineGraphPainter({
    required this.networkHistory,
    required this.diskHistory,
    required this.networkColor,
    required this.diskColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (networkHistory.isEmpty) return;

    final paintNetwork = Paint()
      ..color = networkColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintDisk = Paint()
      ..color = diskColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    _drawHistoryPath(canvas, size, networkHistory, paintNetwork);
    if (diskHistory.isNotEmpty) {
      _drawHistoryPath(canvas, size, diskHistory, paintDisk);
    }
  }

  void _drawHistoryPath(Canvas canvas, Size size, List<double> history, Paint paint) {
    if (history.length == 1) {
      final y = size.height - (history[0].clamp(0.0, 1.0) * size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }

    final path = Path();
    final step = size.width / (history.length - 1);

    for (int i = 0; i < history.length; i++) {
      final x = i * step;
      final y = size.height - (history[i].clamp(0.0, 1.0) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant FixedDualLineGraphPainter oldDelegate) {
    return oldDelegate.networkHistory != networkHistory ||
        oldDelegate.diskHistory != diskHistory;
  }
}

/// Mock QuickSettingsBottomSheet from tarjetas_y_componentes.md line 729
class MockUnscrollableQuickSettingsSheet extends StatelessWidget {
  const MockUnscrollableQuickSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 8)),
          ),
          const SizedBox(height: 12),
          const Text('Download Preferences', style: TextStyle(fontSize: 22)),
          const SizedBox(height: 16),
          Container(height: 48, color: Colors.blue),
          const SizedBox(height: 16),
          const Text('Max Video Resolution', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          Container(height: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Container(height: 56, color: Colors.grey),
          const SizedBox(height: 20),
          Container(height: 48, color: Colors.green),
        ],
      ),
    );
  }
}

/// Mock DesktopDataTable from tarjetas_y_componentes.md line 358
class MockHoverTable extends StatefulWidget {
  final int rowCount;
  final Function(int rebuildCount)? onTableRebuild;

  const MockHoverTable({
    super.key,
    required this.rowCount,
    this.onTableRebuild,
  });

  @override
  State<MockHoverTable> createState() => _MockHoverTableState();
}

class _MockHoverTableState extends State<MockHoverTable> {
  String? _hoveredId;
  int _rebuildCounter = 0;

  @override
  Widget build(BuildContext context) {
    _rebuildCounter++;
    widget.onTableRebuild?.call(_rebuildCounter);

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.rowCount,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final id = 'item_$index';
        final isHovered = _hoveredId == id;
        return MouseRegion(
          key: Key('mouse_region_$index'),
          onEnter: (_) => setState(() => _hoveredId = id),
          onExit: (_) => setState(() => _hoveredId = null),
          child: Container(
            height: 36,
            color: isHovered ? Colors.blue : Colors.transparent,
            child: Text('Row $index'),
          ),
        );
      },
    );
  }
}

void main() {
  group('Empirical Ergonomics & Performance Adversarial Suite', () {
    testWidgets('TEST 1: DualLineGraphPainter division by zero on history.length == 1',
        (tester) async {
      final painter = BuggyDualLineGraphPainter(
        history: [0.5],
        networkColor: Colors.blue,
        diskColor: Colors.green,
      );

      const size = Size(200, 60);
      final step = size.width / (painter.history.length - 1);
      expect(step, double.infinity,
          reason: 'Division by zero (1 - 1 = 0) results in double.infinity');

      final fixedPainter = FixedDualLineGraphPainter(
        networkHistory: [0.5],
        diskHistory: [0.3],
        networkColor: Colors.blue,
        diskColor: Colors.green,
      );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(() => fixedPainter.paint(canvas, size), returnsNormally);
    });

    testWidgets('TEST 2: QuickSettingsBottomSheet overflows on constrained height viewport',
        (tester) async {
      tester.view.physicalSize = const Size(360, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool hasOverflowError = false;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('A RenderFlex overflowed by')) {
          hasOverflowError = true;
        }
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MockUnscrollableQuickSettingsSheet(),
          ),
        ),
      );

      FlutterError.onError = originalOnError;
      expect(hasOverflowError, isTrue,
          reason: 'Unscrollable Column in QuickSettingsBottomSheet overflows constrained viewport');
    });

    test('TEST 3: Thumbnail RAM Footprint Proof (414MB vs 4MB)', () {
      const int fullWidth = 1920;
      const int fullHeight = 1080;
      const int bytesPerPixel = 4; // RGBA_8888
      const double fullRamPerImageMb = (fullWidth * fullHeight * bytesPerPixel) / (1024 * 1024);

      expect(fullRamPerImageMb, closeTo(7.91, 0.5),
          reason: 'A single 1080p uncompressed bitmap consumes ~8 MB in RAM');

      const double queue50RamMb = fullRamPerImageMb * 50;
      expect(queue50RamMb, greaterThan(390),
          reason: '50 items queue consumes >390 MB of memory if memCache is omitted');

      const int downsampledWidth = 192;
      const int downsampledHeight = 108;
      const double downsampledRamPerImageKb = (downsampledWidth * downsampledHeight * bytesPerPixel) / 1024;
      const double downsampled50RamMb = (downsampledRamPerImageKb * 50) / 1024;

      expect(downsampledRamPerImageKb, closeTo(81.0, 5.0),
          reason: 'Downsampled thumbnail consumes only ~81 KB');
      expect(downsampled50RamMb, closeTo(3.95, 0.5),
          reason: '50 items queue downsampled consumes < 4.5 MB in RAM (99% reduction)');
    });

    testWidgets('TEST 4: DesktopDataTable root setState rebuilds entire table on single row hover',
        (tester) async {
      int totalTableRebuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MockHoverTable(
              rowCount: 50,
              onTableRebuild: (count) => totalTableRebuilds = count,
            ),
          ),
        ),
      );

      expect(totalTableRebuilds, 1, reason: 'Initial render builds table once');

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final row0Finder = find.byKey(const Key('mouse_region_0'));
      await gesture.moveTo(tester.getCenter(row0Finder));
      await tester.pumpAndSettle();

      expect(totalTableRebuilds, 2,
          reason: 'Hovering row 0 triggers root setState, rebuilding all 50 rows');

      final row1Finder = find.byKey(const Key('mouse_region_1'));
      await gesture.moveTo(tester.getCenter(row1Finder));
      await tester.pumpAndSettle();

      expect(totalTableRebuilds, greaterThanOrEqualTo(3),
          reason: 'Hovering row 1 triggers root setState again, continuously rebuilding all rows in memory');
    });

    testWidgets('TEST 5: Dismissible card captures horizontal gesture and blocks TabBarView swipe navigation',
        (tester) async {
      bool dismissTriggered = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                bottom: const TabBar(tabs: [Tab(text: 'Tab 1'), Tab(text: 'Tab 2')]),
              ),
              body: TabBarView(
                children: [
                  ListView(
                    children: [
                      Dismissible(
                        key: const Key('dismissible_card'),
                        direction: DismissDirection.horizontal,
                        confirmDismiss: (direction) async {
                          dismissTriggered = true;
                          return false;
                        },
                        child: Container(
                          height: 120,
                          color: Colors.red,
                          child: const Text('Swipeable Card Content'),
                        ),
                      ),
                    ],
                  ),
                  const Center(child: Text('Tab 2 Body')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Swipeable Card Content'), findsOneWidget);
      expect(find.text('Tab 2 Body'), findsNothing);

      // Fling horizontally across the card
      await tester.fling(find.text('Swipeable Card Content'), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // Dismissible intercepted the drag and prevented TabBarView from switching tabs
      expect(dismissTriggered, isTrue,
          reason: 'Dismissible intercepted the horizontal fling gesture');
      expect(find.text('Tab 2 Body'), findsNothing,
          reason: 'TabBarView page switch was blocked by Dismissible gesture arena victory');
    });
  });
}
