import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/domain/note.dart';
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/features/notes/note_tree.dart';

class _Controller extends NoteController {
  String? moved;
  String? deleted;
  @override
  List<NoteFolder> get folders => const [
    NoteFolder(id: '', name: 'Unfiled'),
    NoteFolder(id: 'A', name: 'A'),
    NoteFolder(id: 'B', name: 'B'),
  ];
  @override
  List<Note> get notes => [
    Note(
      id: 'note',
      body: 'Document',
      folder: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      filePath: '/tmp/note.md',
    ),
  ];
  @override
  Future<bool> moveFolder(String folder, String parent) async {
    moved = '$folder>$parent';
    return true;
  }

  @override
  Future<bool> moveNote(String id, String folder) async {
    moved = '$id>$folder';
    return true;
  }

  @override
  Future<bool> deleteFolder(String folder) async {
    deleted = folder;
    return true;
  }

  @override
  Future<bool> deleteNote(String id) async {
    deleted = id;
    return true;
  }
}

void main() {
  testWidgets(
    'folder and Note dragging and secondary-click deletion are wired',
    (tester) async {
      final controller = _Controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: ScrapnoteTheme.foruiTheme,
            child: Scaffold(
              body: SizedBox(
                width: 250,
                child: NoteTree(
                  controller: controller,
                  onCreateFolder: () {},
                  onCreateNote: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notes'), findsNothing);
      final a = find.byKey(const ValueKey('folder-A'));
      final b = find.byKey(const ValueKey('folder-B'));
      await tester.drag(a, tester.getCenter(b) - tester.getCenter(a));
      await tester.pumpAndSettle();
      expect(controller.moved, 'A>B');
      final note = find.byKey(const ValueKey('note-note'));
      await tester.drag(note, tester.getCenter(b) - tester.getCenter(note));
      await tester.pumpAndSettle();
      expect(controller.moved, 'note>B');
      await tester.tap(a, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete folder'));
      await tester.pumpAndSettle();
      expect(controller.deleted, 'A');
      await tester.tap(note, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete note'));
      await tester.pumpAndSettle();
      expect(controller.deleted, 'note');
    },
  );
}
