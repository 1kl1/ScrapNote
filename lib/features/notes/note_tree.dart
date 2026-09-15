import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import '../../core/design/scrapnote_tokens.dart';
import 'note_controller.dart';

class NoteTreeEntry {
  const NoteTreeEntry(this.id, {required this.folder});
  final String id;
  final bool folder;
}

class NoteTree extends StatefulWidget {
  const NoteTree({
    required this.controller,
    required this.onCreateFolder,
    required this.onCreateNote,
    this.onOpenNote,
    super.key,
  });
  final VoidCallback? onOpenNote;
  final NoteController controller;
  final VoidCallback onCreateFolder;
  final VoidCallback onCreateNote;
  @override
  State<NoteTree> createState() => _NoteTreeState();
}

class _NoteTreeState extends State<NoteTree> {
  final _collapsed = <String>{};
  NoteController get controller => widget.controller;
  bool _accept(NoteTreeEntry entry, String parent) =>
      !controller.saving &&
      (!entry.folder ||
          (entry.id != parent && !path.isWithin(entry.id, parent)));
  Future<void> _move(NoteTreeEntry entry, String parent) async {
    final moved = entry.folder
        ? await controller.moveFolder(entry.id, parent)
        : await controller.moveNote(entry.id, parent);
    if (mounted && moved) setState(() => _collapsed.remove(parent));
  }

  Widget _destination(String folder, Widget child) => DragTarget<NoteTreeEntry>(
    onWillAcceptWithDetails: (details) => _accept(details.data, folder),
    onAcceptWithDetails: (details) => _move(details.data, folder),
    builder: (context, candidates, rejected) => ColoredBox(
      color: candidates.isNotEmpty
          ? ScrapnoteTokens.signalOrangeWash
          : Colors.transparent,
      child: child,
    ),
  );

  Widget _entry(NoteTreeEntry entry, String title, Widget row) =>
      Draggable<NoteTreeEntry>(
        data: entry,
        maxSimultaneousDrags: controller.saving ? 0 : 1,
        feedback: Material(
          color: ScrapnoteTokens.paperRaised,
          child: Padding(padding: const EdgeInsets.all(12), child: Text(title)),
        ),
        childWhenDragging: Opacity(opacity: .4, child: row),
        child: FContextMenu(
          secondaryPress: true,
          menuBuilder: (context, menu, _) => [
            FItemGroup(
              children: [
                FItem(
                  title: Text(entry.folder ? 'Delete folder' : 'Delete note'),
                  prefix: const Icon(FLucideIcons.trash2),
                  onPress: controller.saving
                      ? null
                      : () {
                          menu.hide();
                          if (entry.folder) {
                            controller.deleteFolder(entry.id);
                          } else {
                            controller.deleteNote(entry.id);
                          }
                        },
                ),
              ],
            ),
          ],
          child: row,
        ),
      );

  List<Widget> _children(String parent, int depth) {
    final folders = controller.folders.where(
      (f) =>
          f.id.isNotEmpty &&
          (path.dirname(f.id) == '.' ? '' : path.dirname(f.id)) == parent,
    );
    final notes = controller.notes.where((n) => n.folder == parent).toList()
      ..sort(
        (a, b) => a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        ),
      );
    return [
      for (final folder in folders) ...[
        _destination(
          folder.id,
          _entry(
            NoteTreeEntry(folder.id, folder: true),
            folder.name,
            _row(
              key: ValueKey('folder-${folder.id}'),
              depth: depth,
              selected: controller.selectedFolder == folder.id,
              title: folder.name,
              icon: _collapsed.contains(folder.id)
                  ? FLucideIcons.chevronRight
                  : FLucideIcons.chevronDown,
              onPress: () {
                controller.selectFolder(folder.id);
                setState(() {
                  if (!_collapsed.add(folder.id)) _collapsed.remove(folder.id);
                });
              },
            ),
          ),
        ),
        if (!_collapsed.contains(folder.id)) ..._children(folder.id, depth + 1),
      ],
      for (final note in notes)
        _entry(
          NoteTreeEntry(note.id, folder: false),
          note.displayTitle,
          _row(
            key: ValueKey('note-${note.id}'),
            depth: depth,
            selected: controller.activeDocument?.note?.id == note.id,
            title: note.displayTitle.isEmpty ? 'Untitled' : note.displayTitle,
            subtitle: DateFormat(
              'yyyy-MM-dd HH:mm',
            ).format(note.updatedAt.toLocal()),
            icon: FLucideIcons.fileText,
            onPress: () {
              controller.selectFolder(note.folder);
              controller.openNote(note.id);
              widget.onOpenNote?.call();
            },
          ),
        ),
    ];
  }

  Widget _row({
    required Key key,
    required int depth,
    required bool selected,
    required String title,
    String? subtitle,
    required IconData icon,
    required VoidCallback onPress,
  }) => Container(
    key: key,
    padding: EdgeInsets.only(left: depth * 16),
    decoration: BoxDecoration(
      color: selected ? ScrapnoteTokens.paperSunken : null,
      border: Border(
        left: BorderSide(
          width: 2,
          color: selected ? ScrapnoteTokens.signalOrange : Colors.transparent,
        ),
      ),
    ),
    child: FButton(
      variant: FButtonVariant.ghost,
      onPress: controller.saving ? null : onPress,
      child: Expanded(
        child: Row(
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: ScrapnoteTokens.mutedInk,
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ColoredBox(
      color: ScrapnoteTokens.paperRaised,
      child: _destination(
        '',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: ScrapnoteTokens.tabStripHeight,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => controller.selectFolder(''),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'NOTES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _action(
                    'New folder',
                    FLucideIcons.folderPlus,
                    widget.onCreateFolder,
                  ),
                  _action(
                    'New note · ⌘N',
                    FLucideIcons.filePlus2,
                    widget.onCreateNote,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => controller.selectFolder(''),
                child: ListView(children: _children('', 0)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _action(String label, IconData icon, VoidCallback action) => Tooltip(
    message: label,
    child: FButton.icon(
      variant: FButtonVariant.ghost,
      onPress: controller.saving ? null : action,
      child: Icon(icon, size: 15),
    ),
  );
}
