import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/design/scrapnote_tokens.dart';
import '../../app/scrapnote_theme.dart';
import 'inline_image.dart';

/// Text and image blocks edit the same Markdown controller, so save, recovery,
/// clipboard insertion, and tab switching all share one document value.
class InlineDocumentEditor extends StatefulWidget {
  const InlineDocumentEditor({
    required this.controller,
    required this.imageDirectory,
    this.enabled = true,
    this.onRemoveImage,
    this.editorKey,
    super.key,
  });
  final TextEditingController controller;
  final String imageDirectory;
  final bool enabled;
  final ValueChanged<String>? onRemoveImage;
  final Key? editorKey;

  @override
  State<InlineDocumentEditor> createState() => _InlineDocumentEditorState();
}

class _Block {
  _Block(this.content, {this.image = false})
    : controller = TextEditingController(text: content);
  String content;
  final bool image;
  final TextEditingController controller;
  final FocusNode focus = FocusNode();
  final Key key = UniqueKey();
  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

class _InlineDocumentEditorState extends State<InlineDocumentEditor> {
  List<_Block> _blocks = [];
  bool _writing = false;
  String _lastBody = '';

  @override
  void initState() {
    super.initState();
    _parse();
    _restoreCaret();
    widget.controller.addListener(_externalChange);
  }

  @override
  void didUpdateWidget(covariant InlineDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_externalChange);
      widget.controller.addListener(_externalChange);
      _parse();
    }
  }

  void _parse() {
    final previous = _blocks;
    _blocks = [];
    final body = widget.controller.text;
    var start = 0;
    for (final match in InlineImage.pattern.allMatches(body)) {
      _blocks.add(_Block(body.substring(start, match.start)));
      _blocks.add(_Block(match.group(0)!, image: true));
      start = match.end;
    }
    _blocks.add(_Block(body.substring(start)));
    _lastBody = body;
    for (final block in _blocks.where((b) => !b.image)) {
      block.controller.addListener(() => _textChanged(block));
    }
    // EditableText may still use the old controllers until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final block in previous) {
        block.dispose();
      }
    });
  }

  void _externalChange() {
    if (_writing || _lastBody == widget.controller.text) return;
    setState(_parse);
    _restoreCaret();
  }

  void _restoreCaret() {
    final caret = widget.controller.selection.isValid
        ? widget.controller.selection.extentOffset
        : widget.controller.text.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var offset = 0;
      for (final block in _blocks) {
        if (!block.image &&
            caret >= offset &&
            caret <= offset + block.content.length) {
          block.controller.selection = TextSelection.collapsed(
            offset: caret - offset,
          );
          block.focus.requestFocus();
          break;
        }
        offset += block.content.length;
      }
    });
  }

  void _textChanged(_Block block) {
    if (!_blocks.contains(block)) return;
    block.content = block.controller.text;
    final offset = _blocks
        .takeWhile((b) => b != block)
        .fold(0, (n, b) => n + b.content.length);
    final selection = block.controller.selection;
    _write(
      selection.isValid
          ? TextSelection(
              baseOffset: offset + selection.baseOffset,
              extentOffset: offset + selection.extentOffset,
            )
          : null,
    );
  }

  void _write([TextSelection? selection]) {
    _writing = true;
    _lastBody = _blocks.map((b) => b.content).join();
    widget.controller.value = TextEditingValue(
      text: _lastBody,
      selection: selection ?? TextSelection.collapsed(offset: _lastBody.length),
    );
    _writing = false;
  }

  void _move(int oldIndex, int newIndex) {
    if (!widget.enabled) return;
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final block = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, block);
      // Keep Markdown images on their own lines after block reordering.
      for (final b in _blocks.where((b) => b.image)) {
        b.content = '\n${b.content.trim()}\n';
      }
      _write();
    });
  }

  void _align(_Block block, String alignment) {
    final match = InlineImage.pattern.firstMatch(block.content)!;
    setState(() {
      block.content =
          '\n![${match.group(1)}](${match.group(2)} "$alignment")\n';
      _write();
    });
  }

  void _remove(_Block block) {
    final uri = Uri.tryParse(
      InlineImage.pattern.firstMatch(block.content)!.group(2)!,
    );
    setState(() {
      _blocks.remove(block);
      _write();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => block.dispose());
    if (uri?.scheme == 'file' && !_lastBody.contains(uri.toString())) {
      widget.onRemoveImage?.call(uri!.toFilePath());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalChange);
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReorderableListView.builder(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 80),
    buildDefaultDragHandles: false,
    onReorderItem: (oldIndex, newIndex) =>
        _move(oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex),
    itemCount: _blocks.length,
    itemBuilder: (context, index) {
      final block = _blocks[index];
      return Row(
        key: block.key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableDragStartListener(
            index: index,
            enabled: widget.enabled,
            child: const Padding(
              padding: EdgeInsets.only(top: 12, right: 8),
              child: Icon(
                FLucideIcons.gripVertical,
                size: 16,
                color: ScrapnoteTokens.mutedInk,
              ),
            ),
          ),
          Expanded(
            child: block.image
                ? _image(block, index)
                : FTextField.multiline(
                    key: index == 0 ? widget.editorKey : null,
                    style: ScrapnoteTheme.editorTextFieldStyle,
                    control: FTextFieldControl.managed(
                      controller: block.controller,
                    ),
                    focusNode: block.focus,
                    autofocus: false,
                    enabled: widget.enabled,
                    minLines: 1,
                    maxLines: null,
                    hint: 'Write here…',
                  ),
          ),
        ],
      );
    },
  );

  Widget _image(_Block block, int index) {
    final match = InlineImage.pattern.firstMatch(block.content)!;
    final uri = Uri.directory(widget.imageDirectory).resolve(match.group(2)!);
    final alignment = switch (match.group(3)) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.center,
    };
    Widget error(BuildContext context, Object error, StackTrace? stack) =>
        const SizedBox(
          height: 80,
          child: Center(child: Text('Image unavailable')),
        );
    final image = uri.scheme == 'http' || uri.scheme == 'https'
        ? Image.network(
            uri.toString(),
            fit: BoxFit.contain,
            errorBuilder: error,
          )
        : uri.scheme == 'file'
        ? Image.file(
            File.fromUri(uri),
            fit: BoxFit.contain,
            errorBuilder: error,
          )
        : const Text('Image unavailable');
    return Column(
      key: ValueKey('inline-image-$index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360, maxWidth: 560),
            child: image,
          ),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            for (final item in [
              ('left', FLucideIcons.alignLeft),
              ('center', FLucideIcons.alignCenter),
              ('right', FLucideIcons.alignRight),
            ])
              _action(
                'Align image ${item.$1}',
                item.$2,
                () => _align(block, item.$1),
              ),
            _action(
              'Move image up',
              FLucideIcons.arrowUp,
              index > 0 ? () => _move(index, index - 1) : null,
            ),
            _action(
              'Move image down',
              FLucideIcons.arrowDown,
              index < _blocks.length - 1 ? () => _move(index, index + 2) : null,
            ),
            _action('Remove image', FLucideIcons.trash2, () => _remove(block)),
          ],
        ),
      ],
    );
  }

  Widget _action(String label, IconData icon, VoidCallback? action) => Tooltip(
    message: label,
    child: FButton.icon(
      variant: FButtonVariant.ghost,
      onPress: widget.enabled ? action : null,
      semanticsLabel: label,
      child: Icon(icon, size: 14),
    ),
  );
}
