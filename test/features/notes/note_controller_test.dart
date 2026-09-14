import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/features/notes/note_controller.dart';

void main() {
  late Directory vault;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('scrapnote_note_controller_');
  });

  tearDown(() async {
    if (await vault.exists()) await vault.delete(recursive: true);
  });

  test('creates, saves, closes, and reopens a Note', () async {
    final controller = NoteController();
    await controller.connect(vault.path);

    expect(controller.folders.single.name, 'Unfiled');
    final document = controller.newDocument();
    controller.updateBody('# Working note');
    expect(controller.activeDocument!.dirty, isTrue);
    expect(await controller.saveActive(), isTrue);
    expect(controller.notes.single.firstLineTitle, 'Working note');

    expect(controller.close(document.sessionId), isTrue);
    expect(controller.activeDocument, isNull);
    controller.openNote(controller.notes.single.id);
    expect(controller.activeDocument!.body, '# Working note');
  });

  test('creates a selected folder for new notes', () async {
    final controller = NoteController();
    await controller.connect(vault.path);

    expect(await controller.createFolder('Journal'), isTrue);
    final document = controller.newDocument();
    expect(document.folder, 'Journal');
  });
}
