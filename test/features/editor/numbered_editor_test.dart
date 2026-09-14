import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/editor/inline_document_editor.dart';
import 'package:scrapnote/features/editor/scrap_embed.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    TextEditingController controller, {
    double width = 420,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: InlineDocumentEditor(
              controller: controller,
              imageDirectory: '/tmp',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hard-line numbers follow actual wrapping and resize', (
    tester,
  ) async {
    final body = '${'wrapped text ' * 14}\nSecond line';
    final controller = TextEditingController(text: body);
    await mount(tester, controller);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final lineStart = body.indexOf('\n') + 1;
    final expected =
        editable
            .localToGlobal(
              editable
                  .getLocalRectForCaret(TextPosition(offset: lineStart))
                  .topLeft,
            )
            .dy +
        3;
    final number = find.byKey(const ValueKey('line-number-2'));
    expect(tester.getTopLeft(number).dy, closeTo(expected, .5));
    expect(
      tester.getTopLeft(number).dy -
          tester.getTopLeft(find.byKey(const ValueKey('line-number-1'))).dy,
      greaterThan(48),
    );
    final before = tester.getTopLeft(number).dy;
    tester.view.physicalSize = const Size(800, 800);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(number).dy, lessThan(before));
    expect(find.byKey(const ValueKey('line-number-3')), findsNothing);
  });

  testWidgets('images and Scrap objects each occupy exactly one numbered line', (
    tester,
  ) async {
    final scrap = Scrap(
      id: 'source',
      body: 'Title\nDetail\nMore detail',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final controller = TextEditingController(
      text:
          'Before\n![Image](file:///tmp/not-here.png "left:50")\n${ScrapEmbed.wrap(scrap, scrap.body)}\nAfter',
    );
    await mount(tester, controller, width: 900);
    for (var i = 1; i <= 4; i++) {
      expect(find.byKey(ValueKey('line-number-$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('line-number-5')), findsNothing);
    expect(find.byKey(const ValueKey('scrap-object-source')), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
    expect(find.text('Detail'), findsNothing);
    await tester.tap(find.byTooltip('Remove Scrap'));
    await tester.pumpAndSettle();
    expect(ScrapEmbed.usedIds(controller.text), isEmpty);
    expect(controller.text, contains('After'));
  });
}
