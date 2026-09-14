import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/features/editor/editor_formatting.dart';

void main() {
  test(
    'bold wraps selected text and toggles it back without losing selection',
    () {
      final controller = TextEditingController(text: 'one two three')
        ..selection = const TextSelection(baseOffset: 4, extentOffset: 7);
      addTearDown(controller.dispose);
      EditorFormatting.toggleBold(controller);
      expect(controller.text, 'one **two** three');
      expect(controller.selection.textInside(controller.text), 'two');
      EditorFormatting.toggleBold(controller);
      expect(controller.text, 'one two three');
      expect(controller.selection.textInside(controller.text), 'two');
    },
  );
  test('bold at caret leaves insertion point between markers', () {
    final controller = TextEditingController(text: 'A ')
      ..selection = const TextSelection.collapsed(offset: 2);
    addTearDown(controller.dispose);
    EditorFormatting.toggleBold(controller);
    expect(controller.text, 'A ****');
    expect(controller.selection.baseOffset, 4);
  });
}
