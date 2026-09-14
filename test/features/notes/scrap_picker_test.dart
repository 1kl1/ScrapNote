import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/core/design/scrapnote_tokens.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/notes/scrap_picker.dart';

void main() {
  testWidgets('used Scraps are marked and hover previews close on exit', (
    tester,
  ) async {
    final scrap = Scrap(
      id: 'source',
      body: '# Original title\n\nPreview detail',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    var insertions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 250,
                child: ScrapPicker(
                  scraps: [scrap],
                  usedIds: const {'source'},
                  onInsert: (_) => insertions++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('scrap-choice-source'));
    expect(
      tester.widget<ColoredBox>(row).color,
      ScrapnoteTokens.signalOrangeWash,
    );
    expect(find.text('Preview detail'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();
    expect(find.text('Preview detail'), findsOneWidget);
    await mouse.moveTo(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Preview detail'), findsNothing);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(insertions, 1);
    await mouse.removePointer();
  });
}
