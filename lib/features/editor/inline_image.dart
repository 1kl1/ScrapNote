import 'package:flutter/widgets.dart';

/// Markdown remains the source of truth for the block editor and local files.
class InlineImage {
  static final pattern = RegExp(
    r'!\[((?:\\.|[^\]])*)\]\(([^\s)]+)(?: "(left|center|right)(?::(100|50|33|20))?")?\)',
  );

  static String markdown(String source, {String label = 'Image'}) =>
      '![${label.replaceAll('[', r'\[').replaceAll(']', r'\]')}](${fileUri(source)} "center:50")';

  static String fileUri(String source) =>
      Uri.file(source).toString().replaceAll('(', '%28').replaceAll(')', '%29');

  static String encodePath(String path) =>
      Uri(path: path).toString().replaceAll('(', '%28').replaceAll(')', '%29');

  static String selectionMarkdown(
    Iterable<String> sources, {
    String Function(String source)? labelFor,
  }) {
    final images = <String>[
      for (final source in sources)
        markdown(source, label: labelFor?.call(source) ?? 'Image'),
    ];
    if (images.isEmpty) return '';
    if (images.length == 1) return images.single;
    return InlineImageRow.wrap(images);
  }

  static void insert(TextEditingController controller, String content) {
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : start;
    final insertion = '\n$content\n';
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, end, insertion),
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
  }

  /// Position a drop in the nearest visible text block, using Flutter's text
  /// layout to translate the screen coordinate into a character offset.
  static void placeCaret(BuildContext context, Offset globalPosition) {
    EditableTextState? closest;
    var distance = double.infinity;
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        final state = element.state as EditableTextState;
        final render = state.renderEditable;
        if (render.attached && render.hasSize) {
          final rect = render.localToGlobal(Offset.zero) & render.size;
          final gap = globalPosition.dy < rect.top
              ? rect.top - globalPosition.dy
              : globalPosition.dy > rect.bottom
              ? globalPosition.dy - rect.bottom
              : 0.0;
          if (gap < distance) {
            distance = gap;
            closest = state;
          }
        }
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    final state = closest;
    if (state == null) return;
    state.widget.controller.selection = TextSelection.collapsed(
      offset: state.renderEditable.getPositionForPoint(globalPosition).offset,
    );
    state.widget.focusNode.requestFocus();
  }

  /// Resolves a pending file reference in place; legacy attachment-only callers
  /// still get an appended Markdown link.
  static String persist(
    String body,
    String source,
    String relativePath,
    String label,
  ) {
    final uri = fileUri(source);
    final target = encodePath(relativePath);
    var found = false;
    final result = body.replaceAllMapped(pattern, (match) {
      if (match.group(2) != uri) return match.group(0)!;
      found = true;
      return match.group(0)!.replaceFirst(uri, target);
    });
    if (found) return result;
    if (body.contains(']($target)') || body.contains(']($target "')) {
      return body;
    }
    return '${body.isEmpty ? '' : '$body\n\n'}![${label.replaceAll(']', r'\]')}]($target)';
  }
}

/// Delimits images chosen in one action while keeping every item valid,
/// portable Markdown on disk.
abstract final class InlineImageRow {
  static const begin = '<!-- scrapnote:image-row:begin -->';
  static const end = '<!-- scrapnote:image-row:end -->';

  static final pattern = RegExp('$begin\\n([\\s\\S]*?)\\n$end');

  static String wrap(Iterable<String> imageMarkdown) =>
      '$begin\n${imageMarkdown.join('\n')}\n$end';

  static List<String> items(String block) => InlineImage.pattern
      .allMatches(pattern.firstMatch(block)?.group(1) ?? block)
      .map((match) => match.group(0)!)
      .toList(growable: false);
}
