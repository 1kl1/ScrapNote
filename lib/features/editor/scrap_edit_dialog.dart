import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../app/scrapnote_theme.dart';
import '../../infrastructure/platform/image_clipboard.dart';
import 'inline_document_editor.dart';
import 'inline_image.dart';

class ScrapEditResult {
  const ScrapEditResult(this.body, this.imagePaths);
  final String body;
  final List<String> imagePaths;
}

/// Edits the captured copy. The source Scrap remains available for recovery.
class ScrapEditDialog extends StatefulWidget {
  const ScrapEditDialog({
    required this.body,
    required this.imageDirectory,
    this.allowImagePaste = true,
    super.key,
  });
  final String body;
  final String imageDirectory;
  final bool allowImagePaste;
  @override
  State<ScrapEditDialog> createState() => _ScrapEditDialogState();
}

class _ScrapEditDialogState extends State<ScrapEditDialog> {
  late final _controller = TextEditingController(text: widget.body);
  final _images = <String>[];
  bool _reading = false;
  bool _submitted = false;

  Future<void> _paste() async {
    if (_reading || !widget.allowImagePaste) return;
    setState(() => _reading = true);
    final selection = _controller.selection;
    final body = _controller.text;
    try {
      final imagePath = await ImageClipboard.readImagePath();
      if (imagePath == null) return;
      if (!mounted) {
        await File(imagePath).delete();
        return;
      }
      _images.add(imagePath);
      if (_controller.text == body) _controller.selection = selection;
      InlineImage.insert(_controller, InlineImage.markdown(imagePath));
    } on PlatformException {
      // Ordinary text paste remains handled by the focused text field.
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _save() {
    if (_reading || _submitted) return;
    _submitted = true;
    final used = _images
        .where((p) => _controller.text.contains(InlineImage.fileUri(p)))
        .toList();
    _images.removeWhere(used.contains);
    Navigator.of(context).pop(ScrapEditResult(_controller.text, used));
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final image in _images) {
      File(image).delete().catchError((Object _) => File(image));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FTheme(
    data: ScrapnoteTheme.foruiTheme,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyV &&
              (HardwareKeyboard.instance.isMetaPressed ||
                  HardwareKeyboard.instance.isControlPressed)) {
            _paste();
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          title: const Text('Edit Scrap'),
          content: SizedBox(
            width: 760,
            height: 460,
            child: InlineDocumentEditor(
              controller: _controller,
              imageDirectory: widget.imageDirectory,
              editorKey: const ValueKey('scrap-dialog-editor'),
            ),
          ),
          actions: [
            FButton(
              variant: FButtonVariant.ghost,
              onPress: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FButton(
              onPress: _reading ? null : _save,
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    ),
  );
}
