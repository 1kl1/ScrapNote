import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/features/timeline/timeline_dial.dart';

void main() {
  group('TimelineDial', () {
    testWidgets('paints a custom date scale', (tester) async {
      await tester.pumpWidget(
        _DialHarness(
          initialDate: DateTime(2026, 9, 4),
          markedDates: {DateTime(2026, 9, 4)},
        ),
      );

      final customPaintFinder = find.descendant(
        of: find.byType(TimelineDial),
        matching: find.byType(CustomPaint),
      );
      expect(customPaintFinder, findsOneWidget);
      final customPaint = tester.widget<CustomPaint>(customPaintFinder);
      expect(customPaint.painter, isA<TimelineDialPainter>());
      expect(find.text('2026-09-04'), findsOneWidget);
    });

    testWidgets('scrubs dates with a horizontal drag', (tester) async {
      await tester.pumpWidget(
        _DialHarness(initialDate: DateTime(2026, 9, 4), markedDates: const {}),
      );

      await tester.drag(find.byType(TimelineDial), const Offset(-60, 0));
      await tester.pump();

      expect(find.text('2026-09-05'), findsOneWidget);
    });

    testWidgets('accepts both vertical and horizontal wheel input', (
      tester,
    ) async {
      await tester.pumpWidget(
        _DialHarness(initialDate: DateTime(2026, 9, 4), markedDates: const {}),
      );
      final center = tester.getCenter(find.byType(TimelineDial));

      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, 20)),
      );
      await tester.pump();
      expect(find.text('2026-09-05'), findsOneWidget);

      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(-20, 0)),
      );
      await tester.pump();
      expect(find.text('2026-09-04'), findsOneWidget);
    });

    testWidgets('supports arrows, shifted arrows, Home, and End', (
      tester,
    ) async {
      await tester.pumpWidget(
        _DialHarness(
          initialDate: DateTime(2026, 9, 4),
          markedDates: {DateTime(2026, 8, 20), DateTime(2026, 10, 2)},
        ),
      );
      await tester.tap(find.byType(TimelineDial));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('2026-09-05'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.text('2026-09-12'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(find.text('2026-08-20'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(find.text('2026-10-02'), findsOneWidget);
    });

    testWidgets('exposes semantic increment and decrement actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _DialHarness(initialDate: DateTime(2026, 9, 4), markedDates: const {}),
      );

      final node = tester.getSemantics(find.byType(TimelineDial));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );

      final dialSemantics = find.semantics.byLabel('Timeline date');
      tester.semantics.increase(dialSemantics);
      await tester.pump();
      expect(find.text('2026-09-05'), findsOneWidget);

      tester.semantics.decrease(dialSemantics);
      await tester.pump();
      expect(find.text('2026-09-04'), findsOneWidget);
    });
  });
}

class _DialHarness extends StatefulWidget {
  const _DialHarness({required this.initialDate, required this.markedDates});

  final DateTime initialDate;
  final Set<DateTime> markedDates;

  @override
  State<_DialHarness> createState() => _DialHarnessState();
}

class _DialHarnessState extends State<_DialHarness> {
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_formatDate(selectedDate)),
            TimelineDial(
              selectedDate: selectedDate,
              markedDates: widget.markedDates,
              onChanged: (value) => setState(() => selectedDate = value),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
