import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class InlineTimePicker extends StatefulWidget {
  final int initialSeconds;
  final ValueChanged<int> onChanged;
  final String? label;
  final bool enabled;

  const InlineTimePicker({
    super.key,
    this.initialSeconds = 0,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  @override
  State<InlineTimePicker> createState() => _InlineTimePickerState();
}

class _InlineTimePickerState extends State<InlineTimePicker> {
  late final TextEditingController _hoursController;
  late final TextEditingController _minutesController;
  late final TextEditingController _secondsController;

  late final FocusNode _hoursFocus;
  late final FocusNode _minutesFocus;
  late final FocusNode _secondsFocus;

  int _currentTotalSeconds = 0;

  @override
  void initState() {
    super.initState();
    _currentTotalSeconds = widget.initialSeconds;
    final (h, m, s) = _splitSeconds(widget.initialSeconds);

    _hoursController = TextEditingController(
      text: h.toString().padLeft(2, '0'),
    );
    _minutesController = TextEditingController(
      text: m.toString().padLeft(2, '0'),
    );
    _secondsController = TextEditingController(
      text: s.toString().padLeft(2, '0'),
    );

    _hoursFocus = FocusNode()
      ..addListener(
        () => _handleFocusChange(_hoursFocus, _hoursController, 99),
      );
    _minutesFocus = FocusNode()
      ..addListener(
        () => _handleFocusChange(_minutesFocus, _minutesController, 59),
      );
    _secondsFocus = FocusNode()
      ..addListener(
        () => _handleFocusChange(_secondsFocus, _secondsController, 59),
      );
  }

  (int, int, int) _splitSeconds(int totalSec) {
    final clampedSec = totalSec < 0 ? 0 : totalSec;
    final h = (clampedSec ~/ 3600).clamp(0, 99);
    final m = ((clampedSec % 3600) ~/ 60).clamp(0, 59);
    final s = (clampedSec % 60).clamp(0, 59);
    return (h, m, s);
  }

  void _handleFocusChange(
    FocusNode node,
    TextEditingController controller,
    int maxVal,
  ) {
    if (node.hasFocus) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    } else {
      final parsed = int.tryParse(controller.text) ?? 0;
      final clamped = parsed.clamp(0, maxVal);
      controller.text = clamped.toString().padLeft(2, '0');
      _notifyChanged();
    }
  }

  void _notifyChanged() {
    final h = (int.tryParse(_hoursController.text) ?? 0).clamp(0, 99);
    final m = (int.tryParse(_minutesController.text) ?? 0).clamp(0, 59);
    final s = (int.tryParse(_secondsController.text) ?? 0).clamp(0, 59);
    final total = (h * 3600) + (m * 60) + s;
    if (total != _currentTotalSeconds) {
      _currentTotalSeconds = total;
      widget.onChanged(total);
    }
  }

  @override
  void didUpdateWidget(covariant InlineTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSeconds != oldWidget.initialSeconds &&
        widget.initialSeconds != _currentTotalSeconds) {
      _currentTotalSeconds = widget.initialSeconds;
      if (!_hoursFocus.hasFocus &&
          !_minutesFocus.hasFocus &&
          !_secondsFocus.hasFocus) {
        final (h, m, s) = _splitSeconds(widget.initialSeconds);
        _hoursController.text = h.toString().padLeft(2, '0');
        _minutesController.text = m.toString().padLeft(2, '0');
        _secondsController.text = s.toString().padLeft(2, '0');
      }
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _hoursFocus.dispose();
    _minutesFocus.dispose();
    _secondsFocus.dispose();
    super.dispose();
  }

  Widget _buildDigitField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required FocusNode? nextFocus,
    required int maxVal,
    required String hint,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hint,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
          TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 1.2,
            ),
            maxLength: 2,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              counterText: '',
              border: InputBorder.none,
            ),
            onChanged: (val) {
              if (val.length >= 2) {
                final parsed = int.tryParse(val) ?? 0;
                final clamped = parsed.clamp(0, maxVal);
                if (clamped != parsed) {
                  controller.text = clamped.toString().padLeft(2, '0');
                }
                if (nextFocus != null) {
                  nextFocus.requestFocus();
                } else {
                  focusNode.unfocus();
                }
              }
              _notifyChanged();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        enabled: widget.enabled,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildDigitField(
            controller: _hoursController,
            focusNode: _hoursFocus,
            nextFocus: _minutesFocus,
            maxVal: 99,
            hint: 'HH',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              ':',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _buildDigitField(
            controller: _minutesController,
            focusNode: _minutesFocus,
            nextFocus: _secondsFocus,
            maxVal: 59,
            hint: 'MM',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              ':',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _buildDigitField(
            controller: _secondsController,
            focusNode: _secondsFocus,
            nextFocus: null,
            maxVal: 59,
            hint: 'SS',
          ),
        ],
      ),
    );
  }
}
