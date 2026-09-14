import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:forui/forui.dart';

import '../../app/scrapnote_theme.dart';
import '../../core/design/scrapnote_tokens.dart';

/// Measures hard-line starts using the EditableText layout itself, including
/// soft wraps, font scaling and the actual width of this editor.
class NumberedTextArea extends StatefulWidget {
  const NumberedTextArea({
    required this.controller,
    required this.focusNode,
    required this.firstLine,
    required this.enabled,
    this.editorKey,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final int firstLine;
  final bool enabled;
  final Key? editorKey;
  @override
  State<NumberedTextArea> createState() => _NumberedTextAreaState();
}

class _NumberedTextAreaState extends State<NumberedTextArea> {
  final _field = GlobalKey();
  final _surface = GlobalKey();
  List<double> _tops = [8];
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant NumberedTextArea old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _measure() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      RenderEditable? editable;
      void visit(Element element) {
        if (element is StatefulElement && element.state is EditableTextState) {
          editable = (element.state as EditableTextState).renderEditable;
        }
        element.visitChildren(visit);
      }

      (_field.currentContext as Element?)?.visitChildren(visit);
      final render = editable;
      final surface = _surface.currentContext?.findRenderObject();
      if (render == null || surface == null || !render.hasSize) return;
      final origin = render.localToGlobal(Offset.zero, ancestor: surface);
      final starts = [
        0,
        for (final m in '\n'.allMatches(widget.controller.text)) m.end,
      ];
      final tops = [
        for (final offset in starts)
          origin.dy +
              render.getLocalRectForCaret(TextPosition(offset: offset)).top +
              3,
      ];
      if (tops.length != _tops.length ||
          List.generate(
            tops.length,
            (i) => (tops[i] - _tops[i]).abs() > 0.1,
          ).any((v) => v)) {
        setState(() => _tops = tops);
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _measure();
      return Stack(
        key: _surface,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 82, right: 32),
            child: KeyedSubtree(
              key: _field,
              child: FTextField.multiline(
                key: widget.editorKey,
                control: FTextFieldControl.managed(
                  controller: widget.controller,
                ),
                focusNode: widget.focusNode,
                enabled: widget.enabled,
                style: ScrapnoteTheme.editorTextFieldStyle,
                minLines: 1,
                maxLines: null,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 58,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: ScrapnoteTokens.rule),
                  ),
                ),
                child: Stack(
                  children: [
                    for (var i = 0; i < _tops.length; i++)
                      Positioned(
                        top: _tops[i],
                        right: 14,
                        child: Text(
                          '${widget.firstLine + i}',
                          key: ValueKey('line-number-${widget.firstLine + i}'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.5,
                            color: ScrapnoteTokens.mutedInk,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
