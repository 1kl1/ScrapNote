import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/features/editor/inline_image.dart';
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/infrastructure/vault/note_repository.dart';

void main() {
  late Directory vault;
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('note-tree-');
  });
  tearDown(() => vault.delete(recursive: true));

  test(
    'move folders recursively, reject cycles and preserve image targets',
    () async {
      final repo = NoteRepository(vault);
      await repo.createFolder('A');
      await repo.createFolder('Child', parent: 'A');
      await repo.createFolder('B');
      final image = File('${vault.path}/source.png')
        ..writeAsBytesSync([1, 2, 3]);
      final note = await repo.createNote(
        'Text\n${InlineImage.markdown(image.path)}',
        folder: 'A/Child',
        attachmentPaths: [image.path],
      );
      await expectLater(repo.moveFolder('A', 'A/Child'), throwsFormatException);
      await repo.moveFolder('A', 'B');
      var moved = (await repo.listNotes()).single;
      expect(moved.id, note.id);
      expect(moved.folder, 'B/A/Child');
      var reference = InlineImage.pattern.firstMatch(moved.body)!.group(2)!;
      expect(
        File.fromUri(Uri.file(moved.filePath).resolve(reference)).existsSync(),
        isTrue,
      );
      await repo.moveNote(note.id, '');
      moved = (await repo.listNotes()).single;
      expect(moved.folder, '');
      reference = InlineImage.pattern.firstMatch(moved.body)!.group(2)!;
      expect(
        File.fromUri(Uri.file(moved.filePath).resolve(reference)).existsSync(),
        isTrue,
      );
      await repo.deleteNote(note.id);
      expect(await repo.listNotes(), isEmpty);
    },
  );

  test(
    'deleting a folder removes descendants and closes dirty drafts; moves retain edits',
    () async {
      final notes = NoteController();
      addTearDown(notes.dispose);
      await notes.connect(vault.path);
      await notes.createFolder('A');
      notes.newDocument();
      notes.updateBody('Saved body');
      await notes.saveActive();
      final id = notes.activeDocument!.note!.id;
      notes.editActive();
      notes.updateBody('Unsaved change');
      notes.selectFolder('');
      await notes.createFolder('B');
      expect(await notes.moveFolder('A', 'B'), isTrue);
      expect(notes.activeDocument!.body, 'Unsaved change');
      expect(notes.activeDocument!.folder, 'B/A');
      expect(notes.activeDocument!.dirty, isTrue);
      expect(await notes.saveActive(), isTrue);
      expect(notes.notes.single.id, id);
      notes.selectFolder('B/A');
      await notes.createFolder('Child');
      notes.newDocument();
      notes.updateBody('Draft in child');
      expect(await notes.deleteFolder('B'), isTrue);
      expect(notes.notes, isEmpty);
      expect(notes.documents, isEmpty);
      expect(notes.selectedFolder, '');
      expect(
        (await NoteRepository(
          vault,
        ).listFolders()).where((f) => f.id.isNotEmpty),
        isEmpty,
      );
      expect(Directory('${vault.path}/.trash/notes').listSync(), hasLength(1));
    },
  );

  test('same-name destination does not overwrite an existing folder', () async {
    final repo = NoteRepository(vault);
    await repo.createFolder('A');
    await repo.createFolder('B');
    await repo.createFolder('A', parent: 'B');
    await expectLater(
      repo.moveFolder('A', 'B'),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory('${vault.path}/notes/A').existsSync(), isTrue);
    expect(Directory('${vault.path}/notes/B/A').existsSync(), isTrue);
  });
}
