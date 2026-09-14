import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../../domain/scrap.dart';

class ScrapPicker extends StatefulWidget {
  const ScrapPicker({required this.scraps, required this.onInsert, super.key});
  final List<Scrap> scraps;
  final ValueChanged<Scrap> onInsert;
  @override
  State<ScrapPicker> createState() => _ScrapPickerState();
}

class _ScrapPickerState extends State<ScrapPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final matches = widget.scraps
        .where((s) => s.body.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return FCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            hint: 'Search scraps…',
            control: FTextFieldControl.managed(
              onChange: (value) => setState(() => _query = value.text),
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? const Center(
                    child: Text('No scraps found. Save a Scrap first.'),
                  )
                : ListView(
                    children: [
                      for (final scrap in matches)
                        FButton(
                          variant: FButtonVariant.ghost,
                          onPress: () => widget.onInsert(scrap),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              scrap.firstLineTitle.isEmpty
                                  ? 'Untitled scrap'
                                  : scrap.firstLineTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
