// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4
// design-system: DESIGN.md · designed-as-app · Index-First editor shell

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../core/design/scrapnote_tokens.dart';
import '../../core/layout/adaptive_workspace.dart';
import 'package:path/path.dart' as path;
import '../../domain/scrap.dart';
import '../editor/inline_document_editor.dart';
import '../editor/inline_image.dart';
import '../editor/scrap_embed.dart';
import '../editor/local_markdown_view.dart';
import 'scrap_picker.dart';
import 'note_controller.dart';
import 'note_tree.dart';
import 'note_title_field.dart';

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
    this.onExportNaverBlog,
    this.scraps = const [],
    this.onInsertScrap,
    this.onEmbeddedImageAdded,
    super.key,
  });

  final ValueChanged<String>? onEmbeddedImageAdded;
  final List<Scrap> scraps;
  final ValueChanged<Scrap>? onInsertScrap;
  final NoteController noteController;
  final TextEditingController textController;
  final VoidCallback onCreateFolder;
  final VoidCallback onCreateNote;
  final VoidCallback onSave;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onChooseImages;
  final Future<bool> Function() onPasteImage;
  final ValueChanged<List<String>> onImagesDropped;
  final ValueChanged<String> onRemoveImage;
  final VoidCallback? onExportNaverBlog;

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final editor = _NoteDocumentArea(
              scraps: scraps,
              onInsertScrap: onInsertScrap,
              onEmbeddedImageAdded: onEmbeddedImageAdded,
              noteController: noteController,
              textController: textController,
              onCreateNote: onCreateNote,
              onSave: onSave,
              onCloseTab: onCloseTab,
              onChooseImages: onChooseImages,
              onImagesDropped: onImagesDropped,
              onRemoveImage: onRemoveImage,
              onPasteImage: onPasteImage,
              onExportNaverBlog: onExportNaverBlog,
            );
            return AdaptiveWorkspace(
              selection: noteController.activeSessionId,
              saving: noteController.saving,
              onSave: onSave,
              onCreate: onCreateNote,
              onChooseImages: onChooseImages,
              listBuilder: (showEditor) => NoteTree(
                key: const ValueKey<String>('notes-hierarchy-pane'),
                controller: noteController,
                onCreateFolder: onCreateFolder,
                onCreateNote: () {
                  onCreateNote();
                  showEditor();
                },
                onOpenNote: showEditor,
              ),
              editor: editor,
            );
          },
        ),
      ),
    );
  }
}

class _NoteDocumentArea extends StatefulWidget {
  const _NoteDocumentArea({
    required this.scraps,
    required this.onInsertScrap,
    required this.onEmbeddedImageAdded,
    required this.noteController,
    required this.textController,
    required this.onCreateNote,
    required this.onSave,
    required this.onCloseTab,
    required this.onChooseImages,
    required this.onImagesDropped,
    required this.onRemoveImage,
    required this.onPasteImage,
    required this.onExportNaverBlog,
  });

  final ValueChanged<String>? onEmbeddedImageAdded;
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
  final Future<bool> Function() onPasteImage;
  final VoidCallback? onExportNaverBlog;

  @override
  State<_NoteDocumentArea> createState() => _NoteDocumentAreaState();
}

class _NoteDocumentAreaState extends State<_NoteDocumentArea> {
  bool _showPicker = false;
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
                _IconAction(
                  tooltip: '스크랩 삽입',
                  icon: FLucideIcons.inbox,
                  onPressed: () => setState(() => _showPicker = !_showPicker),
                ),
                if (active?.preview == true)
                  FButton(
                    variant: FButtonVariant.ghost,
                    onPress: noteController.editActive,
                    prefix: const Icon(FLucideIcons.pencil, size: 14),
                    child: const Text('Edit'),
                  ),
                _IconAction(
                  tooltip: '네이버 블로그로 내보내기',
                  icon: FLucideIcons.send,
                  onPressed: active == null ? null : widget.onExportNaverBlog,
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
        if (active != null)
          active.preview
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                  child: Text(
                    active.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                )
              : NoteTitleField(
                  key: ValueKey('title-${active.sessionId}'),
                  title: active.draftTitle,
                  enabled: !noteController.saving,
                  onChanged: noteController.updateTitle,
                ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final directory = active?.note == null
                  ? path.join(
                      noteController.vaultPath ?? '',
                      'notes',
                      active?.folder ?? '',
                    )
                  : path.dirname(active!.note!.filePath);
              final editor = active == null
                  ? _NoOpenNote(onCreate: onCreateNote)
                  : active.preview
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: LocalMarkdownView(
                        data: active.body,
                        imageDirectory: directory,
                      ),
                    )
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
                        imageDirectory: directory,
                        onRemoveImage: onRemoveImage,
                        onAddImage: widget.onEmbeddedImageAdded,
                        onPasteImage: widget.onPasteImage,
                      ),
                    );
              final picker = ScrapPicker(
                scraps: widget.scraps,
                usedIds: ScrapEmbed.usedIds(active?.body ?? ''),
                imageDirectory: path.join(
                  noteController.vaultPath ?? '',
                  'scraps',
                ),
                onInsert: (scrap) {
                  noteController.editActive();
                  widget.onInsertScrap?.call(scrap);
                  setState(() => _showPicker = false);
                },
              );
              if (constraints.maxWidth < 470) {
                return _showPicker ? picker : editor;
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: editor),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: constraints.maxWidth < 700 ? 190 : 250,
                    child: picker,
                  ),
                ],
              );
            },
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
