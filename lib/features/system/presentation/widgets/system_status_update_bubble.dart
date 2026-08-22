import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/system/presentation/system_details_screen.dart';

class SystemStatusUpdateBubble extends StatefulWidget {
  final GlobalKey? anchorKey;
  final VoidCallback? onShow;
  final VoidCallback? onDismiss;

  const SystemStatusUpdateBubble({
    super.key,
    this.anchorKey,
    this.onShow,
    this.onDismiss,
  });

  static OverlayEntry? _currentEntry;

  static bool get isShowing => _currentEntry != null;

  static void show(BuildContext context, GlobalKey anchorKey) {
    if (_currentEntry != null) return;

    final overlayState = Overlay.maybeOf(context);
    if (overlayState == null) return;

    _currentEntry = OverlayEntry(
      builder: (ctx) => SystemStatusUpdateBubble(
        anchorKey: anchorKey,
        onDismiss: () => hide(),
      ),
    );

    overlayState.insert(_currentEntry!);
  }

  static void hide() {
    if (_currentEntry != null) {
      _currentEntry!.remove();
      _currentEntry = null;
    }
  }

  @override
  State<SystemStatusUpdateBubble> createState() =>
      _SystemStatusUpdateBubbleState();
}

class _SystemStatusUpdateBubbleState extends State<SystemStatusUpdateBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (widget.onDismiss != null) {
      widget.onDismiss!();
    } else {
      SystemStatusUpdateBubble.hide();
    }
  }

  Future<void> _handleShow(BuildContext context) async {
    if (widget.onShow != null) {
      widget.onShow!();
      return;
    }
    final targetContext = widget.anchorKey?.currentContext ?? context;
    final navigator = Navigator.maybeOf(targetContext);
    SystemStatusUpdateBubble.hide();
    if (targetContext.mounted) {
      showModalBottomSheet(
        context: targetContext,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const SystemDetailsScreen(),
      );
    } else if (navigator != null && navigator.context.mounted) {
      showModalBottomSheet(
        context: navigator.context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const SystemDetailsScreen(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);

    Widget bubbleCard(double bubbleWidth, double arrowOffset) {
      return Material(
        color: Colors.transparent,
        child: CustomPaint(
          painter: _BubbleTailPainter(
            arrowX: arrowOffset.clamp(16.0, bubbleWidth - 16.0),
            color: theme.colorScheme.surfaceContainerHigh,
            borderColor: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          child: Container(
            width: bubbleWidth,
            margin: const EdgeInsets.only(top: 8.0),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.system_update,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        locale.ssiBubbleTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  locale.ssiBubbleMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _handleDismiss,
                      child: Text(locale.ssiBubbleButtonDismiss),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _handleShow(context),
                      child: Text(locale.ssiBubbleButtonShow),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (widget.anchorKey == null) {
      return bubbleCard(320.0, 160.0);
    }

    final renderBox =
        widget.anchorKey!.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.of(context).size;

    Offset targetOffset = const Offset(16, 56);
    Size targetSize = const Size(40, 40);

    if (renderBox != null && renderBox.hasSize) {
      targetOffset = renderBox.localToGlobal(Offset.zero);
      targetSize = renderBox.size;
    }

    final double top = targetOffset.dy + targetSize.height + 8.0;
    final double bubbleWidth = min(screenSize.width - 32.0, 320.0);
    final double left = max(
      16.0,
      min(targetOffset.dx, screenSize.width - bubbleWidth - 16.0),
    );
    final double arrowOffset =
        (targetOffset.dx + targetSize.width / 2.0) - left;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _handleDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: top,
          left: left,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              alignment: Alignment(
                ((arrowOffset / bubbleWidth) * 2.0) - 1.0,
                -1.0,
              ),
              child: bubbleCard(bubbleWidth, arrowOffset),
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final double arrowX;
  final Color color;
  final Color borderColor;

  _BubbleTailPainter({
    required this.arrowX,
    required this.color,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const arrowWidth = 14.0;
    const arrowHeight = 8.0;

    final path = Path()
      ..moveTo(arrowX - arrowWidth / 2, arrowHeight)
      ..lineTo(arrowX, 0)
      ..lineTo(arrowX + arrowWidth / 2, arrowHeight)
      ..close();

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = borderColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, fillPaint);
    canvas.drawLine(
      Offset(arrowX - arrowWidth / 2, arrowHeight),
      Offset(arrowX, 0),
      strokePaint,
    );
    canvas.drawLine(
      Offset(arrowX, 0),
      Offset(arrowX + arrowWidth / 2, arrowHeight),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.arrowX != arrowX ||
        oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor;
  }
}
