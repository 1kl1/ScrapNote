import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../../app/scrapnote_theme.dart';

/// The route owns its text controller until the closing animation is finished.
class FolderNameDialog extends StatefulWidget {
  const FolderNameDialog({super.key});
  @override
  State<FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<FolderNameDialog> {
  final _controller = TextEditingController();
  bool _submitted = false;
  String? _error;
  void _submit() {
    if (_submitted) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a folder name.');
      return;
    }
    _submitted = true;
    Navigator.of(context).pop(name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FTheme(
    data: ScrapnoteTheme.foruiTheme,
    child: AlertDialog(
      title: const Text('New folder'),
      content: FTextField(
        control: FTextFieldControl.managed(controller: _controller),
        autofocus: true,
        label: const Text('Folder name'),
        error: _error == null ? null : Text(_error!),
        onSubmit: (_) => _submit(),
      ),
      actions: [
        FButton(
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FButton(onPress: _submit, child: const Text('Create')),
      ],
    ),
  );
}
