import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/infrastructure/vault/note_repository.dart';

void main() {
  test(
    'title and Scrap ownership survive save/reopen; discard and delete release usage',
    () async {
      final root = await Directory.systemTemp.createTemp('note-usage-');
      addTearDown(() => root.delete(recursive: true));
      final controller = NoteController();
      addTearDown(controller.dispose);
      await controller.connect(root.path);
      controller.newDocument();
      controller.updateTitle('My explicit title');
      controller.updateBody(
        '<!-- scrapnote:begin:s1 -->\nCaptured text\n<!-- scrapnote:end -->',
      );
      expect(controller.activeDocument!.dirty, isTrue);
      expect(controller.usedScrapIds(), {'s1'});
      expect(controller.usedScrapIds(excludingActive: true), isEmpty);
      expect(await controller.saveActive(), isTrue);
      final saved = controller.notes.single;
      expect(saved.title, 'My explicit title');
      expect(
        (await NoteRepository(root).listNotes()).single.title,
        saved.title,
      );
      expect(controller.activeDocument!.dirty, isFalse);
      controller.newDocument();
      expect(controller.usedScrapIds(excludingActive: true), {'s1'});
      controller.openNote(saved.id);
      controller.updateBody('Removed');
      expect(controller.usedScrapIds(), isEmpty);
      controller.discard(controller.activeSessionId!);
      expect(controller.usedScrapIds(), {'s1'});
      controller.openNote(saved.id);
      controller.updateTitle('Renamed');
      expect(controller.activeDocument!.dirty, isTrue);
      await controller.saveActive();
      expect(
        (await NoteRepository(root).listNotes()).single.displayTitle,
        'Renamed',
      );
      await controller.deleteNote(saved.id);
      expect(controller.usedScrapIds(), isEmpty);
    },
  );
}
