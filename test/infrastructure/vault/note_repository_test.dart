import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/infrastructure/vault/note_repository.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scrapnote_notes_');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'creates folders and persists Markdown notes with local images',
    () async {
      var tick = 0;
      final repository = NoteRepository(
        sandbox,
        idGenerator: () => 'note-1',
        now: () => DateTime.utc(2026, 9, 12, 10, tick++),
      );
      final image = File('${sandbox.path}/sample.png');
      await image.writeAsBytes(base64Decode(_pixel));

      final folder = await repository.createFolder('Trips');
      final note = await repository.createNote(
        '# California',
        folder: folder.id,
        attachmentPaths: <String>[image.path],
      );

      expect(note.filePath, contains('/notes/Trips/'));
      expect(note.body, contains('![sample.png]'));
      expect(note.assets, hasLength(1));
      expect(await File(note.filePath).exists(), isTrue);
      expect(
        (await repository.listNotes()).single.firstLineTitle,
        'California',
      );
    },
  );

  test('sorts and updates notes by modified time', () async {
    var now = DateTime.utc(2026, 9, 12, 10);
    var id = 0;
    final repository = NoteRepository(
      sandbox,
      idGenerator: () => 'note-${id++}',
      now: () => now,
    );
    final first = await repository.createNote('first', folder: '');
    now = now.add(const Duration(minutes: 1));
    await repository.createNote('second', folder: '');
    now = now.add(const Duration(minutes: 1));
    await repository.updateNote(first, 'first revised');

    final notes = await repository.listNotes();
    expect(notes.first.body, 'first revised');
    expect(notes.first.updatedAt, now);
  });
}

const _pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
