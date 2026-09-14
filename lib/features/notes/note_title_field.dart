import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class NoteTitleField extends StatefulWidget {
  const NoteTitleField({
    required this.title,
    required this.onChanged,
    required this.enabled,
    super.key,
  });
  final String title;
  final ValueChanged<String> onChanged;
  final bool enabled;
  @override
  State<NoteTitleField> createState() => _NoteTitleFieldState();
}

class _NoteTitleFieldState extends State<NoteTitleField> {
  late final _controller = TextEditingController(text: widget.title);
  @override
  void didUpdateWidget(covariant NoteTitleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.title) _controller.text = widget.title;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
    child: FTextField(
      key: const ValueKey('note-title'),
      control: FTextFieldControl.managed(
        controller: _controller,
        onChange: (value) => widget.onChanged(value.text),
      ),
      label: const Text('Title'),
      hint: 'Enter a title',
      enabled: widget.enabled,
    ),
  );
}
