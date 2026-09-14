// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4
// design-system: DESIGN.md · designed-as-app · Index-First editor shell

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../core/design/scrapnote_tokens.dart';
import 'package:path/path.dart' as path;
import '../../domain/scrap.dart';
import '../editor/inline_document_editor.dart';
import '../editor/inline_image.dart';
import 'scrap_picker.dart';
import 'note_controller.dart';

class NotesWorkspace extends StatelessWidget {
  const NotesWorkspace({
    required this.noteController,
    required this.textController,
    required this.onCreateFolder,
    required this.onCreateNote,
    required this.onSave,
    required this.onCloseTab,
    required this.onChooseImages,
    required this.onPasteImage,
    required this.onImagesDropped,
    required this.onRemoveImage,
    this.scraps = const [],
    this.onInsertScrap,
    super.key,
  });

  final List<Scrap> scraps;
  final ValueChanged<Scrap>? onInsertScrap;
  final NoteController noteController;
  final TextEditingController textController;
  final VoidCallback onCreateFolder;
  final VoidCallback onCreateNote;
  final VoidCallback onSave;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onChooseImages;
  final VoidCallback onPasteImage;
  final ValueChanged<List<String>> onImagesDropped;
  final ValueChanged<String> onRemoveImage;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): onSave,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            onCreateNote,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            onCreateNote,
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (HardwareKeyboard.instance.isMetaPressed ||
                  HardwareKeyboard.instance.isControlPressed) &&
              event.logicalKey == LogicalKeyboardKey.keyV) {
            onPasteImage();
          }
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final editor = _NoteDocumentArea(
              scraps: scraps,
              onInsertScrap: onInsertScrap,
              noteController: noteController,
              textController: textController,
              onCreateNote: onCreateNote,
              onSave: onSave,
              onCloseTab: onCloseTab,
              onChooseImages: onChooseImages,
              onImagesDropped: onImagesDropped,
              onRemoveImage: onRemoveImage,
            );
            if (constraints.maxWidth < 700) return editor;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  key: const ValueKey<String>('notes-hierarchy-pane'),
                  width: ScrapnoteTokens.explorerPaneWidth,
                  child: _NotesHierarchy(
                    noteController: noteController,
                    onCreateFolder: onCreateFolder,
                    onCreateNote: onCreateNote,
                  ),
                ),
                const VerticalDivider(width: 1, color: ScrapnoteTokens.rule),
                Expanded(child: editor),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotesHierarchy extends StatefulWidget {
  const _NotesHierarchy({
    required this.noteController,
    required this.onCreateFolder,
    required this.onCreateNote,
  });
  final NoteController noteController;
  final VoidCallback onCreateFolder;
  final VoidCallback onCreateNote;
  @override
  State<_NotesHierarchy> createState() => _NotesHierarchyState();
}

class _NotesHierarchyState extends State<_NotesHierarchy> {
  final Set<String> _collapsed = {};
  NoteController get controller => widget.noteController;

  List<Widget> _children(String parent, int depth) {
    final folders = controller.folders.where(
      (folder) =>
          folder.id.isNotEmpty &&
          (path.dirname(folder.id) == '.' ? '' : path.dirname(folder.id)) ==
              parent,
    );
    final notes =
        controller.notes.where((note) => note.folder == parent).toList()..sort(
          (a, b) => a.firstLineTitle.toLowerCase().compareTo(
            b.firstLineTitle.toLowerCase(),
          ),
        );
    return [
      for (final folder in folders) ...[
        Padding(
          padding: EdgeInsets.only(left: depth * 16),
          child: _HierarchyRow(
            selected: folder.id == controller.selectedFolder,
            icon: _collapsed.contains(folder.id)
                ? FLucideIcons.chevronRight
                : FLucideIcons.chevronDown,
            title: folder.name,
            onPressed: () {
              setState(() {
                if (!_collapsed.add(folder.id)) _collapsed.remove(folder.id);
              });
              controller.selectFolder(folder.id);
            },
          ),
        ),
        if (!_collapsed.contains(folder.id)) ..._children(folder.id, depth + 1),
      ],
      for (final note in notes)
        Padding(
          padding: EdgeInsets.only(left: depth * 16),
          child: _HierarchyRow(
            selected: note.id == controller.activeDocument?.note?.id,
            icon: FLucideIcons.fileText,
            title: note.firstLineTitle.isEmpty
                ? 'Untitled'
                : note.firstLineTitle,
            subtitle: _timestamp(note.updatedAt),
            onPressed: () {
              controller.selectFolder(note.folder);
              controller.openNote(note.id);
            },
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ScrapnoteTokens.paperRaised,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HierarchyHeader(
          label: 'NOTES',
          action: Row(
            children: [
              _IconAction(
                tooltip: 'New folder',
                icon: FLucideIcons.folderPlus,
                onPressed: widget.onCreateFolder,
              ),
              _IconAction(
                tooltip: 'New note · ⌘N',
                icon: FLucideIcons.filePlus2,
                onPressed: widget.onCreateNote,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: ScrapnoteTokens.rule),
        Expanded(
          child: controller.loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView(
                  children: [
                    _HierarchyRow(
                      selected: controller.selectedFolder.isEmpty,
                      icon: FLucideIcons.folderOpen,
                      title: 'Notes',
                      onPressed: () => controller.selectFolder(''),
                    ),
                    ..._children('', 1),
                    if (controller.notes.isEmpty)
                      _EmptyNotes(onCreate: widget.onCreateNote),
                  ],
                ),
        ),
      ],
    ),
  );
}

class _NoteDocumentArea extends StatefulWidget {
  const _NoteDocumentArea({
    required this.scraps,
    required this.onInsertScrap,
    required this.noteController,
    required this.textController,
    required this.onCreateNote,
    required this.onSave,
    required this.onCloseTab,
    required this.onChooseImages,
    required this.onImagesDropped,
    required this.onRemoveImage,
  });

  final List<Scrap> scraps;
  final ValueChanged<Scrap>? onInsertScrap;
  final NoteController noteController;
  final TextEditingController textController;
  final VoidCallback onCreateNote;
  final VoidCallback onSave;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onChooseImages;
  final ValueChanged<List<String>> onImagesDropped;
  final ValueChanged<String> onRemoveImage;

  @override
  State<_NoteDocumentArea> createState() => _NoteDocumentAreaState();
}

class _NoteDocumentAreaState extends State<_NoteDocumentArea> {
  bool _showScraps = false;
  NoteController get noteController => widget.noteController;
  TextEditingController get textController => widget.textController;
  VoidCallback get onCreateNote => widget.onCreateNote;
  ValueChanged<String> get onCloseTab => widget.onCloseTab;
  ValueChanged<List<String>> get onImagesDropped => widget.onImagesDropped;
  ValueChanged<String> get onRemoveImage => widget.onRemoveImage;

  @override
  Widget build(BuildContext context) {
    final active = noteController.activeDocument;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          key: const ValueKey<String>('notes-tab-strip'),
          height: ScrapnoteTokens.tabStripHeight,
          child: ColoredBox(
            color: ScrapnoteTokens.paperSunken,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      for (final document in noteController.documents)
                        _NoteTab(
                          title: document.title,
                          dirty: document.dirty,
                          selected:
                              document.sessionId ==
                              noteController.activeSessionId,
                          onSelected: () =>
                              noteController.activate(document.sessionId),
                          onClosed: () => onCloseTab(document.sessionId),
                        ),
                    ],
                  ),
                ),
                FButton(
                  variant: FButtonVariant.ghost,
                  prefix: const Icon(FLucideIcons.notebookTabs, size: 16),
                  onPress: () => setState(() => _showScraps = !_showScraps),
                  child: const Text('Insert Scrap'),
                ),
                _IconAction(
                  tooltip: 'New note · ⌘N',
                  icon: FLucideIcons.plus,
                  onPressed: onCreateNote,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: ScrapnoteTokens.rule),
        if (_showScraps)
          SizedBox(
            height: 220,
            child: ScrapPicker(
              scraps: widget.scraps,
              onInsert: (scrap) {
                widget.onInsertScrap?.call(scrap);
                setState(() => _showScraps = false);
              },
            ),
          ),
        Expanded(
          child: active == null
              ? _NoOpenNote(onCreate: onCreateNote)
              : DropTarget(
                  enable: !noteController.saving,
                  onDragDone: (detail) {
                    InlineImage.placeCaret(context, detail.globalPosition);
                    onImagesDropped(
                      detail.files.map((file) => file.path).toList(),
                    );
                  },
                  child: InlineDocumentEditor(
                    key: ValueKey(active.sessionId),
                    editorKey: const ValueKey<String>('note-editor'),
                    controller: textController,
                    enabled: !noteController.saving,
                    imageDirectory: active.note == null
                        ? path.join(
                            noteController.vaultPath ?? '',
                            'notes',
                            active.folder,
                          )
                        : path.dirname(active.note!.filePath),
                    onRemoveImage: onRemoveImage,
                  ),
                ),
        ),
        if (noteController.saving)
          const LinearProgressIndicator(
            minHeight: 2,
            color: ScrapnoteTokens.signalOrange,
            backgroundColor: ScrapnoteTokens.paperSunken,
          ),
      ],
    );
  }
}

class _NoteTab extends StatelessWidget {
  const _NoteTab({
    required this.title,
    required this.dirty,
    required this.selected,
    required this.onSelected,
    required this.onClosed,
  });

  final String title;
  final bool dirty;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? ScrapnoteTokens.paper : ScrapnoteTokens.paperSunken,
      child: InkWell(
        onTap: onSelected,
        child: Container(
          width: 176,
          padding: const EdgeInsets.only(left: ScrapnoteTokens.space3),
          decoration: BoxDecoration(
            border: Border(
              right: const BorderSide(color: ScrapnoteTokens.rule),
              top: BorderSide(
                color: selected
                    ? ScrapnoteTokens.signalOrange
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                FLucideIcons.fileText,
                size: 14,
                color: ScrapnoteTokens.mutedInk,
              ),
              const SizedBox(width: ScrapnoteTokens.space2),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ScrapnoteTokens.charcoal,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: dirty ? 'Close unsaved note' : 'Close note',
                onPressed: onClosed,
                icon: dirty
                    ? const SizedBox.square(
                        key: ValueKey<String>('dirty-indicator'),
                        dimension: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: ScrapnoteTokens.charcoalSoft,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : const Icon(FLucideIcons.x, size: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HierarchyHeader extends StatelessWidget {
  const _HierarchyHeader({required this.label, required this.action});
  final String label;
  final Widget action;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: ScrapnoteTokens.tabStripHeight,
    child: Row(
      children: <Widget>[
        const SizedBox(width: ScrapnoteTokens.space4),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: ScrapnoteTokens.charcoal,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        action,
      ],
    ),
  );
}

class _HierarchyRow extends StatelessWidget {
  const _HierarchyRow({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onPressed,
    this.subtitle,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? ScrapnoteTokens.paperSunken : Colors.transparent,
    child: InkWell(
      onTap: onPressed,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: ScrapnoteTokens.minimumHitTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: ScrapnoteTokens.space4,
          vertical: ScrapnoteTokens.space2,
        ),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: selected
                  ? ScrapnoteTokens.signalOrange
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 14, color: ScrapnoteTokens.mutedInk),
            const SizedBox(width: ScrapnoteTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: ScrapnoteTokens.mutedInk,
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: TextButton.icon(
      onPressed: onCreate,
      icon: const Icon(FLucideIcons.filePlus2, size: 14),
      label: const Text('New note'),
    ),
  );
}

class _NoOpenNote extends StatelessWidget {
  const _NoOpenNote({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: FButton(
      variant: FButtonVariant.ghost,
      onPress: onCreate,
      prefix: const Icon(FLucideIcons.filePlus2, size: 16),
      child: const Text('New note'),
    ),
  );
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: ScrapnoteTokens.minimumHitTarget,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      color: ScrapnoteTokens.charcoalSoft,
    ),
  );
}

String _timestamp(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
