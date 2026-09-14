import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../../domain/scrap.dart';
import '../../core/design/scrapnote_tokens.dart';
import '../editor/local_markdown_view.dart';

class ScrapPicker extends StatefulWidget {
  const ScrapPicker({
    required this.scraps,
    required this.onInsert,
    this.usedIds = const {},
    this.imageDirectory = '',
    super.key,
  });
  final List<Scrap> scraps;
  final ValueChanged<Scrap> onInsert;
  final Set<String> usedIds;
  final String imageDirectory;
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
    return ColoredBox(
      color: ScrapnoteTokens.paperRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'SCRAPS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: FTextField(
              hint: 'Search scraps…',
              control: FTextFieldControl.managed(
                onChange: (value) => setState(() => _query = value.text),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: matches.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No scraps found. Save a Scrap first.'),
                    ),
                  )
                : ListView(
                    children: [
                      for (final scrap in matches)
                        FPopover(
                          autofocus: false,
                          hideRegion: FPopoverHideRegion.none,
                          childAnchor: Alignment.topLeft,
                          popoverAnchor: Alignment.topRight,
                          popoverBuilder: (context, controller) =>
                              IgnorePointer(
                                child: SizedBox(
                                  width: 360,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 360,
                                    ),
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.all(16),
                                      child: LocalMarkdownView(
                                        data: scrap.body,
                                        imageDirectory: widget.imageDirectory,
                                        selectable: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          builder: (context, controller, child) => MouseRegion(
                            onEnter: (_) => controller.show(),
                            onExit: (_) => controller.hide(),
                            child: ColoredBox(
                              key: ValueKey('scrap-choice-${scrap.id}'),
                              color: widget.usedIds.contains(scrap.id)
                                  ? ScrapnoteTokens.signalOrangeWash
                                  : Colors.transparent,
                              child: FButton(
                                variant: FButtonVariant.ghost,
                                onPress: () {
                                  controller.hide();
                                  widget.onInsert(scrap);
                                },
                                child: Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          scrap.firstLineTitle.isEmpty
                                              ? 'Untitled Scrap'
                                              : scrap.firstLineTitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (widget.usedIds.contains(scrap.id))
                                        const Icon(
                                          FLucideIcons.check,
                                          size: 14,
                                          semanticLabel: 'Used in this Note',
                                        ),
                                    ],
                                  ),
                                ),
                              ),
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
