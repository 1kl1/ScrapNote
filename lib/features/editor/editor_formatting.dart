import 'package:flutter/widgets.dart';

abstract final class EditorFormatting {
  static void toggleBold(TextEditingController controller) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : start;
    final selected = text.substring(start, end);
    late String replacement;
    late int from;
    late int to;
    late int selectedStart;
    late int selectedEnd;
    if (start >= 2 &&
        end + 2 <= text.length &&
        text.substring(start - 2, start) == '**' &&
        text.substring(end, end + 2) == '**') {
      from = start - 2;
      to = end + 2;
      replacement = selected;
      selectedStart = from;
      selectedEnd = from + selected.length;
    } else if (selected.length >= 4 &&
        selected.startsWith('**') &&
        selected.endsWith('**')) {
      from = start;
      to = end;
      replacement = selected.substring(2, selected.length - 2);
      selectedStart = start;
      selectedEnd = start + replacement.length;
    } else {
      from = start;
      to = end;
      replacement = '**$selected**';
      selectedStart = start + 2;
      selectedEnd = end + 2;
    }
    controller.value = TextEditingValue(
      text: text.replaceRange(from, to, replacement),
      selection: TextSelection(
        baseOffset: selectedStart,
        extentOffset: selectedEnd,
      ),
    );
  }
}
