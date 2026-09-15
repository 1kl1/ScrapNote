import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_store.dart';
import 'package:scrapnote/infrastructure/vault/note_repository.dart';

void main() {
  test(
    'unsaved note title and body recover only for their original vault',
    () async {
      final root = await Directory.systemTemp.createTemp('note-recovery-');
      final first = NoteController();
      final restored = NoteController();
      final store = EditorRecoveryStore(
        pathProvider: () async => p.join(root.path, 'recovery.json'),
      );
      try {
        await first.connect(p.join(root.path, 'vault'));
        first.newDocument();
        first.updateTitle('여행 기록');
        first.updateBody('오프라인에서 작성한 본문');
        await store.saveNotes(first.vaultPath!, first.recoveryDocuments());
        expect(
          await store.loadNotes(p.join(root.path, 'different-vault')),
          isEmpty,
        );
        await restored.connect(first.vaultPath!);
        restored.restoreRecovery(await store.loadNotes(first.vaultPath!));
        expect(restored.activeDocument!.draftTitle, '여행 기록');
        expect(restored.activeDocument!.body, '오프라인에서 작성한 본문');
        expect(restored.hasDirtyDocuments, isTrue);
        await restored.saveActive();
        await store.saveNotes(first.vaultPath!, restored.recoveryDocuments());
        expect(await store.loadNotes(first.vaultPath!), isEmpty);
      } finally {
        first.dispose();
        restored.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test('synced clean tabs refresh and dirty tabs retain their draft', () async {
    final root = await Directory.systemTemp.createTemp('note-sync-refresh-');
    final controller = NoteController();
    try {
      await controller.connect(root.path);
      controller.newDocument();
      controller.updateBody('base');
      await controller.saveActive();
      final repository = NoteRepository(root);
      final note = controller.activeDocument!.note!;
      await repository.updateNote(note, 'remote');
      await controller.reloadAfterSync();
      expect(controller.activeDocument!.body, 'remote');
      controller.updateBody('unsaved');
      await repository.updateNote(
        controller.activeDocument!.note!,
        'new remote',
      );
      await controller.reloadAfterSync();
      expect(controller.activeDocument!.body, 'unsaved');
      expect(controller.hasDirtyDocuments, isTrue);
    } finally {
      controller.dispose();
      await root.delete(recursive: true);
    }
  });
}
