import 'dart:io';
import 'package:flutter/services.dart';
import 'editor_formatting.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/design/scrapnote_tokens.dart';
import 'inline_image.dart';
import 'numbered_text_area.dart';
import 'scrap_embed.dart';
import 'scrap_edit_dialog.dart';

/// One consistent numbered editor. Images and captured Scraps each occupy one
/// logical line; surrounding text retains ordinary soft wrapping and editing.
class InlineDocumentEditor extends StatefulWidget {
  const InlineDocumentEditor({
    required this.controller,
    required this.imageDirectory,
    this.enabled = true,
    this.onRemoveImage,
    this.onAddImage,
    this.onPasteImage,
    this.scrollController,
    this.editorKey,
    super.key,
  });
  final TextEditingController controller;
  final String imageDirectory;
  final bool enabled;
  final ValueChanged<String>? onRemoveImage;
  final ValueChanged<String>? onAddImage;
  final Future<bool> Function()? onPasteImage;
  final ScrollController? scrollController;

  final Key? editorKey;
  @override
  State<InlineDocumentEditor> createState() => _InlineDocumentEditorState();
}

enum _Kind { text, image, imageRow, scrap }

class _Block {
  _Block(this.content, this.kind, {this.virtual = false})
    : controller = TextEditingController(text: content);
  String content;
  final _Kind kind;
  final bool virtual;
  final TextEditingController controller;
  final FocusNode focus = FocusNode();
  final Key key = UniqueKey();
  int get lines => kind == _Kind.text ? '\n'.allMatches(content).length + 1 : 1;
  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

/// Retain Flutter's normal text deletion except for an empty object separator,
/// which belongs to the document rather than to the individual text field.
class _DeleteObjectGapAction extends ContextAction<DeleteCharacterIntent> {
  _DeleteObjectGapAction(this.removeGap);

  final bool Function() removeGap;

  @override
  Object? invoke(DeleteCharacterIntent intent, [BuildContext? context]) {
    if (removeGap()) return null;
    final action = callingAction;
    return action is ContextAction<DeleteCharacterIntent>
        ? action.invoke(intent, context)
        : action?.invoke(intent);
  }
}

class _InlineDocumentEditorState extends State<InlineDocumentEditor> {
  List<_Block> _blocks = [];
  _Block? _lastFocused;
  bool _pasting = false;
  bool _writing = false;
  String _lastBody = '';
  static final _objects = RegExp(
    '${InlineImageRow.pattern.pattern}|${ScrapEmbed.pattern.pattern}|${InlineImage.pattern.pattern}',
  );

  @override
  void initState() {
    super.initState();
    _parse();
    _restoreCaret();
    widget.controller.addListener(_externalChange);
  }

  @override
  void didUpdateWidget(covariant InlineDocumentEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_externalChange);
      widget.controller.addListener(_externalChange);
      _parse();
      _restoreCaret();
    }
  }

  void _parse() {
    final previous = _blocks;
    _blocks = [];
    final body = widget.controller.text;
    var start = 0;
    for (final match in _objects.allMatches(body)) {
      var text = body.substring(start, match.start);
      if (text.isNotEmpty) {
        if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
        _blocks.add(_Block(text, _Kind.text));
      }
      final raw = match.group(0)!;
      _blocks.add(
        _Block(
          raw,
          raw.startsWith(InlineImageRow.begin)
              ? _Kind.imageRow
              : raw.startsWith('<!--')
              ? _Kind.scrap
              : _Kind.image,
        ),
      );
      start = match.end;
      if (start < body.length && body[start] == '\n') start++;
    }
    _blocks.add(
      _Block(
        body.substring(start),
        _Kind.text,
        virtual:
            start == body.length && _blocks.isNotEmpty && !body.endsWith('\n'),
      ),
    );
    _lastBody = body;
    for (final block in _blocks.where((b) => b.kind == _Kind.text)) {
      block.controller.addListener(() => _textChanged(block));
      block.focus.addListener(() {
        if (block.focus.hasFocus) _lastFocused = block;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final block in previous) {
        block.dispose();
      }
    });
  }

  int _offset(_Block block) => _blocks
      .takeWhile((b) => b != block)
      .fold(0, (n, b) => n + b.content.length + 1);

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
      final textBlocks = _blocks.where((b) => b.kind == _Kind.text).toList();
      final block =
          textBlocks
              .where(
                (b) =>
                    caret >= _offset(b) &&
                    caret <= _offset(b) + b.content.length,
              )
              .firstOrNull ??
          textBlocks.last;
      block.controller.selection = TextSelection.collapsed(
        offset: (caret - _offset(block)).clamp(0, block.content.length),
      );
      block.focus.requestFocus();
    });
  }

  void _textChanged(_Block block) {
    if (!_blocks.contains(block)) return;
    final changed = block.content != block.controller.text;
    block.content = block.controller.text;
    final selection = block.controller.selection;
    _write(
      selection.isValid
          ? TextSelection(
              baseOffset: _offset(block) + selection.baseOffset,
              extentOffset: _offset(block) + selection.extentOffset,
            )
          : null,
    );
    if (changed && mounted) setState(() {});
  }

  void _write([TextSelection? selection]) {
    _writing = true;
    final blocks = _blocks.where((b) => !(b.virtual && b.content.isEmpty));
    _lastBody = blocks.map((b) => b.content).join('\n');
    widget.controller.value = TextEditingValue(
      text: _lastBody,
      selection: selection == null
          ? TextSelection.collapsed(offset: _lastBody.length)
          : TextSelection(
              baseOffset: selection.baseOffset.clamp(0, _lastBody.length),
              extentOffset: selection.extentOffset.clamp(0, _lastBody.length),
            ),
    );
    _writing = false;
  }

  void _styleImage(_Block block, {String? alignment, String? size}) {
    final match = InlineImage.pattern.firstMatch(block.content)!;
    setState(() {
      block.content =
          '![${match.group(1)}](${match.group(2)} "${alignment ?? match.group(3) ?? 'center'}:${size ?? match.group(4) ?? '100'}")';
      _write();
    });
  }

  void _remove(_Block block) {
    final removedContent = block.content;
    final caret = _offset(block);
    setState(() {
      _blocks.remove(block);
      _write(TextSelection.collapsed(offset: caret));
      // Adjacent text must become one field so Backspace can cross the
      // former image boundary, rather than stopping at another text field.
      _parse();
    });
    _restoreCaret();
    WidgetsBinding.instance.addPostFrameCallback((_) => block.dispose());
    _releaseRemovedImages(removedContent);
  }

  void _removeImageFromRow(_Block block, int index) {
    final previousContent = block.content;
    final items = InlineImageRow.items(block.content).toList();
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    if (items.isEmpty) {
      _remove(block);
      return;
    }
    setState(() {
      block.content = items.length == 1
          ? items.single
          : InlineImageRow.wrap(items);
      _write();
      _parse();
    });
    _restoreCaret();
    _releaseRemovedImages(previousContent);
  }

  bool _deleteEmptyObjectGap(_Block block) {
    if (!widget.enabled || !block.focus.hasFocus) return false;
    final value = block.controller.value;
    if (value.text.isNotEmpty ||
        !value.selection.isValid ||
        !value.selection.isCollapsed ||
        !value.composing.isCollapsed) {
      return false;
    }
    final index = _blocks.indexOf(block);
    if (index <= 0 || index >= _blocks.length - 1) return false;
    if (_blocks[index - 1].kind == _Kind.text ||
        _blocks[index + 1].kind == _Kind.text) {
      return false;
    }
    // An empty field still contributes a blank line when blocks are joined.
    // Delete that separator, not either neighboring image/Scrap.
    _remove(block);
    return true;
  }

  void _releaseRemovedImages(String oldContent) {
    for (final match in InlineImage.pattern.allMatches(oldContent)) {
      final source = Uri.tryParse(match.group(2)!);
      if (source?.scheme == 'file' && !_lastBody.contains(source.toString())) {
        widget.onRemoveImage?.call(source!.toFilePath());
      }
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

  void _toggleBold() {
    if (!widget.enabled) return;
    final block = _blocks.contains(_lastFocused)
        ? _lastFocused!
        : _blocks.firstWhere((b) => b.kind == _Kind.text);
    EditorFormatting.toggleBold(block.controller);
    block.focus.requestFocus();
  }

  Future<void> _paste() async {
    if (_pasting || !widget.enabled) return;
    _pasting = true;
    final block = _blocks.contains(_lastFocused)
        ? _lastFocused!
        : _blocks.firstWhere((b) => b.kind == _Kind.text);
    final value = block.controller.value;
    try {
      if (await widget.onPasteImage?.call() == true) return;
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || !_blocks.contains(block) || clipboard?.text == null) {
        return;
      }
      // Ignore an outdated paste if the user edited or switched the field.
      if (block.controller.value != value) return;
      final selection = value.selection;
      final start = selection.isValid ? selection.start : value.text.length;
      final end = selection.isValid ? selection.end : start;
      block.controller.value = TextEditingValue(
        text: value.text.replaceRange(start, end, clipboard!.text!),
        selection: TextSelection.collapsed(
          offset: start + clipboard.text!.length,
        ),
      );
    } finally {
      _pasting = false;
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      PasteTextIntent: CallbackAction<PasteTextIntent>(
        onInvoke: (_) {
          _paste();
          return null;
        },
      ),
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _paste,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _paste,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): _toggleBold,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _toggleBold,
      },
      child: _buildLines(),
    ),
  );

  Widget _buildLines() {
    // This is one editable document, not a list of independent records. Lazy
    // slivers estimate unseen image heights and can correct the scroll offset
    // by an entire image when those blocks enter/leave the viewport. Keep all
    // blocks mounted and measure the complete document instead.
    return SingleChildScrollView(
      key: const ValueKey('inline-document-scroll'),
      controller: widget.scrollController,
      padding: const EdgeInsets.only(top: 14, bottom: 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final block in _blocks)
            Builder(
              key: block.key,
              builder: (context) {
                // Line positions are computed from preceding logical blocks.
                final line =
                    1 +
                    _blocks
                        .takeWhile((b) => b != block)
                        .fold<int>(0, (n, b) => n + b.lines);
                if (block.kind == _Kind.text) {
                  final key =
                      block == _blocks.firstWhere((b) => b.kind == _Kind.text)
                      ? widget.editorKey
                      : null;
                  return Actions(
                    actions: {
                      DeleteCharacterIntent: _DeleteObjectGapAction(
                        () => _deleteEmptyObjectGap(block),
                      ),
                    },
                    child: NumberedTextArea(
                      controller: block.controller,
                      focusNode: block.focus,
                      firstLine: line,
                      enabled: widget.enabled,
                      editorKey: key,
                    ),
                  );
                }
                // The gutter follows the measured object height without an
                // expensive intrinsic-size pass through the image and controls.
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 58,
                      child: Container(
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(top: 11, right: 14),
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(color: ScrapnoteTokens.rule),
                          ),
                        ),
                        child: Text(
                          '$line',
                          key: ValueKey('line-number-$line'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: ScrapnoteTokens.mutedInk,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 58),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 32, 8),
                        child: switch (block.kind) {
                          _Kind.image => _image(block),
                          _Kind.imageRow => _imageRow(block),
                          _ => _scrap(block),
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _editScrap(_Block block) async {
    final result = await showDialog<ScrapEditResult>(
      context: context,
      builder: (_) => ScrapEditDialog(
        body: ScrapEmbed.content(block.content),
        imageDirectory: widget.imageDirectory,
        allowImagePaste: widget.onAddImage != null,
      ),
    );
    if (!mounted || !_blocks.contains(block) || result == null) return;
    final previousContent = block.content;
    final match = ScrapEmbed.pattern.firstMatch(block.content)!;
    setState(() {
      block.content =
          '<!-- scrapnote:begin:${match.group(1)} -->\n${result.body}\n<!-- scrapnote:end -->';
      _write();
    });
    _releaseRemovedImages(previousContent);
    for (final image in result.imagePaths) {
      widget.onAddImage?.call(image);
    }
  }

  Widget _scrap(_Block block) => Container(
    key: ValueKey('scrap-object-${ScrapEmbed.usedIds(block.content).first}'),
    decoration: BoxDecoration(
      color: ScrapnoteTokens.signalOrangeWash,
      border: Border.all(color: ScrapnoteTokens.rule),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        const SizedBox(width: 12),
        const Icon(FLucideIcons.notebookTabs, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            ScrapEmbed.title(block.content),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _action('Edit Scrap', FLucideIcons.pencil, () => _editScrap(block)),
        _action('Remove Scrap', FLucideIcons.x, () => _remove(block)),
      ],
    ),
  );

  Widget _image(_Block block) {
    final match = InlineImage.pattern.firstMatch(block.content)!;
    final uri = Uri.directory(widget.imageDirectory).resolve(match.group(2)!);
    final alignment = switch (match.group(3)) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.center,
    };
    final size = match.group(4) ?? '100';
    Widget error(BuildContext context, Object error, StackTrace? stack) =>
        const SizedBox(
          height: 80,
          child: Center(child: Text('Image unavailable')),
        );
    final image = uri.scheme == 'http' || uri.scheme == 'https'
        ? Image.network(
            uri.toString(),
            fit: BoxFit.fitWidth,
            errorBuilder: error,
          )
        : uri.scheme == 'file'
        ? Image.file(
            File.fromUri(uri),
            fit: BoxFit.fitWidth,
            errorBuilder: error,
          )
        : const Text('Image unavailable');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FractionallySizedBox(
          widthFactor: int.parse(size) / 100,
          alignment: alignment,
          child: image,
        ),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final item in [
              ('left', FLucideIcons.alignLeft),
              ('center', FLucideIcons.alignCenter),
              ('right', FLucideIcons.alignRight),
            ])
              _action(
                'Align image ${item.$1}',
                item.$2,
                () => _styleImage(block, alignment: item.$1),
              ),
            for (final percent in ['100', '50', '33', '20'])
              FButton(
                mainAxisSize: MainAxisSize.min,
                variant: size == percent
                    ? FButtonVariant.outline
                    : FButtonVariant.ghost,
                onPress: widget.enabled
                    ? () => _styleImage(block, size: percent)
                    : null,
                child: Text('$percent%'),
              ),
            _action('Remove image', FLucideIcons.trash2, () => _remove(block)),
          ],
        ),
      ],
    );
  }

  Widget _imageRow(_Block block) {
    final items = InlineImageRow.items(block.content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 220,
          child: _HorizontalImageStrip(
            key: const ValueKey<String>('horizontal-image-row'),
            children: <Widget>[
              for (var index = 0; index < items.length; index++)
                _imageRowItem(items[index], index, block),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text(
              '사진 ${items.length}장 · 가로로 스크롤',
              style: const TextStyle(
                color: ScrapnoteTokens.mutedInk,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: ScrapnoteTokens.space2),
            _action(
              'Remove image row',
              FLucideIcons.trash2,
              () => _remove(block),
            ),
          ],
        ),
      ],
    );
  }

  Widget _imageRowItem(String markdown, int index, _Block block) {
    final match = InlineImage.pattern.firstMatch(markdown)!;
    final uri = Uri.directory(widget.imageDirectory).resolve(match.group(2)!);
    final label = match.group(1)!.replaceAll(r'\[', '[').replaceAll(r'\]', ']');
    Widget error(BuildContext context, Object error, StackTrace? stack) =>
        const Center(child: Text('Image unavailable'));
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
        : const Center(child: Text('Image unavailable'));
    return SizedBox(
      width: 230,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ScrapnoteTokens.paperSunken,
          border: Border.all(color: ScrapnoteTokens.rule),
          borderRadius: BorderRadius.circular(ScrapnoteTokens.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: ClipRect(child: image)),
            SizedBox(
              height: 38,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: ScrapnoteTokens.space2),
                  Expanded(
                    child: Text(
                      label.isEmpty ? '사진 ${index + 1}' : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ScrapnoteTokens.charcoalSoft,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  _action(
                    'Remove image ${index + 1} from row',
                    FLucideIcons.x,
                    () => _removeImageFromRow(block, index),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(String label, IconData icon, VoidCallback action) => Tooltip(
    message: label,
    child: FButton.icon(
      variant: FButtonVariant.ghost,
      onPress: widget.enabled ? action : null,
      semanticsLabel: label,
      child: Icon(icon, size: 14),
    ),
  );
}

class _HorizontalImageStrip extends StatefulWidget {
  const _HorizontalImageStrip({required this.children, super.key});

  final List<Widget> children;

  @override
  State<_HorizontalImageStrip> createState() => _HorizontalImageStripState();
}

class _HorizontalImageStripState extends State<_HorizontalImageStrip> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: true,
    child: ListView.separated(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      itemCount: widget.children.length,
      separatorBuilder: (_, _) => const SizedBox(width: ScrapnoteTokens.space3),
      itemBuilder: (_, index) => widget.children[index],
    ),
  );
}
