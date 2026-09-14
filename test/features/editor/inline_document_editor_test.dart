import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/features/editor/inline_document_editor.dart';
import 'package:scrapnote/features/editor/inline_image.dart';

void main() {
  test('inserts an encoded image at the selection, between text', () {
    final controller = TextEditingController(text: 'BeforeAfter')
      ..selection = const TextSelection.collapsed(offset: 6);
    InlineImage.insert(controller, InlineImage.markdown('/tmp/a (1).png'));
    expect(
      controller.text,
      'Before\n![Image](file:///tmp/a%20%281%29.png)\nAfter',
    );
    expect(
      InlineImage.pattern.firstMatch(controller.text)?.group(2),
      'file:///tmp/a%20%281%29.png',
    );
    controller.dispose();
  });

  testWidgets('edits text around an image, aligns, moves, and removes it', (
    tester,
  ) async {
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
    expect(controller.text, contains('"right"'));
    await tester.tap(find.byTooltip('Move image up'));
    await tester.pumpAndSettle();
    expect(
      controller.text.indexOf('![Image]'),
      lessThan(controller.text.indexOf('Before')),
    );
    await tester.tap(find.byTooltip('Remove image'));
    await tester.pumpAndSettle();
    expect(controller.text, isNot(contains('![Image]')));
    expect(controller.text, contains('Edited after'));
    expect(removed, '/tmp/missing.png');
    expect(tester.takeException(), isNull);
  });
}
