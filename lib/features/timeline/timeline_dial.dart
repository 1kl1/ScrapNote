// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4
// design-system: DESIGN.md · designed-as-app · linear instrument control

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrapnote/core/design/scrapnote_tokens.dart';

/// A desktop-first date scrubber inspired by a linear radio tuning scale.
///
/// The orange indicator remains fixed while drag, wheel, keyboard, and
/// accessibility actions move dates underneath it.
class TimelineDial extends StatefulWidget {
  const TimelineDial({
    super.key,
    required this.selectedDate,
    required this.markedDates,
    required this.onChanged,
  });

  final DateTime selectedDate;
  final Set<DateTime> markedDates;
  final ValueChanged<DateTime> onChanged;

  @override
  State<TimelineDial> createState() => _TimelineDialState();
}

class _TimelineDialState extends State<TimelineDial> {
  static const double _daySpacing = ScrapnoteTokens.space5;

  final FocusNode _focusNode = FocusNode(debugLabel: 'Timeline dial');
  double _dragRemainder = 0;
  bool _hasFocus = false;
  late DateTime _interactionDate;

  @override
  void initState() {
    super.initState();
    _interactionDate = _dateOnly(widget.selectedDate);
  }

  @override
  void didUpdateWidget(TimelineDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameDate(oldWidget.selectedDate, widget.selectedDate)) {
      _interactionDate = _dateOnly(widget.selectedDate);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _changeByDays(int days) {
    _emitDate(
      DateTime(
        _interactionDate.year,
        _interactionDate.month,
        _interactionDate.day + days,
      ),
    );
  }

  void _emitDate(DateTime value) {
    final nextDate = _dateOnly(value);
    if (_isSameDate(nextDate, _interactionDate)) {
      return;
    }

    _interactionDate = nextDate;
    widget.onChanged(nextDate);
  }

  void _handleDragStart(DragStartDetails details) {
    _focusNode.requestFocus();
    _dragRemainder = 0;
    _interactionDate = _dateOnly(widget.selectedDate);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _dragRemainder += details.primaryDelta ?? 0;
    final crossedTicks = (_dragRemainder / _daySpacing).truncate();
    if (crossedTicks == 0) {
      return;
    }

    _dragRemainder -= crossedTicks * _daySpacing;
    // Pulling the scale to the left reveals later dates under the cursor.
    _changeByDays(-crossedTicks);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }

    final delta = event.scrollDelta;
    final dominantDelta = delta.dx.abs() > delta.dy.abs() ? delta.dx : delta.dy;
    if (dominantDelta == 0) {
      return;
    }

    _focusNode.requestFocus();
    _interactionDate = _dateOnly(widget.selectedDate);
    _changeByDays(dominantDelta.isNegative ? -1 : 1);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final step = HardwareKeyboard.instance.isShiftPressed ? 7 : 1;
      _interactionDate = _dateOnly(widget.selectedDate);
      _changeByDays(key == LogicalKeyboardKey.arrowLeft ? -step : step);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
      _interactionDate = _dateOnly(widget.selectedDate);
      final markedDates = widget.markedDates.map(_dateOnly).toList()..sort();
      if (markedDates.isNotEmpty) {
        _emitDate(
          key == LogicalKeyboardKey.home ? markedDates.first : markedDates.last,
        );
      } else if (key == LogicalKeyboardKey.home) {
        _emitDate(
          DateTime(widget.selectedDate.year, widget.selectedDate.month),
        );
      } else {
        _emitDate(
          DateTime(widget.selectedDate.year, widget.selectedDate.month + 1, 0),
        );
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = _dateOnly(widget.selectedDate);

    return Semantics(
      container: true,
      slider: true,
      label: 'Timeline date',
      hint: 'Drag, scroll, or use the arrow keys to change the date.',
      value: _formatDate(selectedDate),
      increasedValue: _formatDate(
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day + 1),
      ),
      decreasedValue: _formatDate(
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day - 1),
      ),
      onIncrease: () {
        _interactionDate = selectedDate;
        _changeByDays(1);
      },
      onDecrease: () {
        _interactionDate = selectedDate;
        _changeByDays(-1);
      },
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (hasFocus) {
          if (_hasFocus != hasFocus) {
            setState(() => _hasFocus = hasFocus);
          }
        },
        onKeyEvent: _handleKeyEvent,
        child: DecoratedBox(
          decoration: _hasFocus
              ? const BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(
                      color: ScrapnoteTokens.focusHalo,
                      width: ScrapnoteTokens.hairline * 2,
                    ),
                  ),
                )
              : const BoxDecoration(),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: _handlePointerSignal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _focusNode.requestFocus(),
              onHorizontalDragStart: _handleDragStart,
              onHorizontalDragUpdate: _handleDragUpdate,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: ClipRect(
                  child: SizedBox(
                    height: ScrapnoteTokens.minimumHitTarget * 2,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: TimelineDialPainter(
                        selectedDate: selectedDate,
                        markedDates: widget.markedDates,
                        tickColor: ScrapnoteTokens.mutedInk,
                        labelColor: ScrapnoteTokens.mutedInk,
                        indicatorColor: ScrapnoteTokens.signalOrange,
                        textStyle: const TextStyle(
                          fontSize: 10,
                          fontFeatures: <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a moving calendar scale beneath a fixed center indicator.
class TimelineDialPainter extends CustomPainter {
  TimelineDialPainter({
    required this.selectedDate,
    required this.markedDates,
    required this.tickColor,
    required this.labelColor,
    required this.indicatorColor,
    required this.textStyle,
  });

  static const double _daySpacing = _TimelineDialState._daySpacing;

  final DateTime selectedDate;
  final Set<DateTime> markedDates;
  final Color tickColor;
  final Color labelColor;
  final Color indicatorColor;
  final TextStyle? textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final baseline = size.height - 16;
    final selected = _dateOnly(selectedDate);
    final markedDateKeys = markedDates.map(_dateKey).toSet();
    final visibleRadius = (size.width / _daySpacing / 2).ceil() + 2;
    final tickPaint = Paint()
      ..color = tickColor
      ..strokeCap = StrokeCap.square;
    final markPaint = Paint()
      ..color = indicatorColor
      ..style = PaintingStyle.fill;

    for (var offset = -visibleRadius; offset <= visibleRadius; offset++) {
      final date = DateTime(
        selected.year,
        selected.month,
        selected.day + offset,
      );
      final x = centerX + offset * _daySpacing;
      final startsMonth = date.day == 1;
      final tickHeight = startsMonth ? 28.0 : 12.0;
      tickPaint.strokeWidth = startsMonth ? 1.5 : 1;
      canvas.drawLine(
        Offset(x, baseline - tickHeight),
        Offset(x, baseline),
        tickPaint,
      );

      if (markedDateKeys.contains(_dateKey(date))) {
        canvas.drawCircle(Offset(x, baseline - tickHeight - 9), 3, markPaint);
      }

      if (startsMonth) {
        final monthLabel = TextPainter(
          text: TextSpan(
            text: '${date.year}.${date.month.toString().padLeft(2, '0')}',
            style: textStyle?.copyWith(color: labelColor),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        monthLabel.paint(
          canvas,
          Offset(x + 5, baseline - tickHeight - monthLabel.height),
        );
      }
    }

    final indicatorPaint = Paint()
      ..color = indicatorColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(centerX, 8),
      Offset(centerX, baseline + 6),
      indicatorPaint,
    );
  }

  @override
  bool shouldRepaint(covariant TimelineDialPainter oldDelegate) {
    return !_isSameDate(selectedDate, oldDelegate.selectedDate) ||
        !setEquals(
          markedDates.map(_dateKey).toSet(),
          oldDelegate.markedDates.map(_dateKey).toSet(),
        ) ||
        tickColor != oldDelegate.tickColor ||
        labelColor != oldDelegate.labelColor ||
        indicatorColor != oldDelegate.indicatorColor ||
        textStyle != oldDelegate.textStyle;
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

int _dateKey(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
