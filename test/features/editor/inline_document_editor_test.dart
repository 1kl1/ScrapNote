import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/features/editor/inline_document_editor.dart';
import 'package:scrapnote/features/editor/inline_image.dart';

void main() {
  testWidgets('Backspace joins lines after an image is removed', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: 'Before\n![Image](file:///tmp/missing.png)\nAfter',
    );
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
    await tester.tap(find.byTooltip('Remove image'));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.controller.selection = const TextSelection.collapsed(offset: 7);
    field.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(controller.text, 'BeforeAfter');
    expect(tester.takeException(), isNull);
  });

  testWidgets('bold shortcut remains available without a toolbar button', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'First line\nSecond line');
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
    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.controller.selection = const TextSelection(
      baseOffset: 11,
      extentOffset: 17,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, 'First line\n**Second** line');
    expect(find.byTooltip('Bold · ⌘B / Ctrl+B'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(controller.text, 'First line\nSecond line');
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing an embedded Scrap releases pending images inside it', (
    tester,
  ) async {
    final controller = TextEditingController(
      text:
          '<!-- scrapnote:begin:s1 -->\n![Image](file:///tmp/pending.png "center:50")\n<!-- scrapnote:end -->',
    );
    addTearDown(controller.dispose);
    String? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: InlineDocumentEditor(
              controller: controller,
              imageDirectory: '/tmp',
              onRemoveImage: (p) => removed = p,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Scrap'));
    await tester.pumpAndSettle();
    expect(removed, '/tmp/pending.png');
    expect(controller.text, isEmpty);
  });

  test('inserts an encoded image at the selection, between text', () {
    final controller = TextEditingController(text: 'BeforeAfter')
      ..selection = const TextSelection.collapsed(offset: 6);
    InlineImage.insert(controller, InlineImage.markdown('/tmp/a (1).png'));
    expect(
      controller.text,
      'Before\n![Image](file:///tmp/a%20%281%29.png "center:50")\nAfter',
    );
    expect(
      InlineImage.pattern.firstMatch(controller.text)?.group(2),
      'file:///tmp/a%20%281%29.png',
    );
    controller.dispose();
  });

  testWidgets(
    'keeps numbered text around an image with size, alignment and removal',
    (tester) async {
      final controller = TextEditingController(
        text: 'Before\n![Image](file:///tmp/missing.png)\nAfter',
      );
      addTearDown(controller.dispose);
      String? removed;
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: ScrapnoteTheme.foruiTheme,
            child: Scaffold(
              body: InlineDocumentEditor(
                controller: controller,
                imageDirectory: '/tmp',
                onRemoveImage: (source) => removed = source,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final fields = find.byType(EditableText);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.last, '\nEdited after');
      expect(controller.text, contains('Edited after'));
      await tester.tap(find.byTooltip('Align image right'));
      await tester.pump();
      expect(controller.text, contains('"right:100"'));
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byTooltip('Move image up'), findsNothing);
      final fullWidth = tester.getSize(find.byType(Image)).width;
      for (final size in [50, 33, 20, 100]) {
        await tester.tap(find.text('$size%'));
        await tester.pumpAndSettle();
        expect(controller.text, contains('"right:$size"'));
        expect(
          tester.getSize(find.byType(Image)).width,
          closeTo(fullWidth * size / 100, 1),
        );
      }
      expect(find.byKey(const ValueKey('line-number-2')), findsOneWidget);
      await tester.tap(find.byTooltip('Remove image'));
      await tester.pumpAndSettle();
      expect(controller.text, isNot(contains('![Image]')));
      expect(controller.text, contains('Edited after'));
      expect(removed, '/tmp/missing.png');
      expect(tester.takeException(), isNull);
    },
  );
}
