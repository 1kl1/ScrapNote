import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/features/editor/inline_image.dart';
import 'package:scrapnote/infrastructure/vault/vault_repository.dart';
import 'package:scrapnote/infrastructure/vault/note_repository.dart';

void main() {
  late Directory vault;
  late File image;
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('inline-assets-');
    image = File('${vault.path}/image (1).png');
    await image.writeAsBytes([1, 2, 3]);
  });
  tearDown(() => vault.delete(recursive: true));

  test(
    'Scrap image stays between paragraphs across save, reorder and deletion',
    () async {
      final repo = VaultRepository(vault);
      final body = 'Before\n${InlineImage.markdown(image.path)}\nAfter';
      final saved = await repo.createScrap(body, attachmentPaths: [image.path]);
      expect(saved.body.startsWith('Before\n![Image](../assets/'), isTrue);
      expect(saved.body.endsWith('\nAfter'), isTrue);
      expect(InlineImage.pattern.allMatches(saved.body).length, 1);
      final reordered = await repo.updateScrap(
        saved,
        '${saved.body.split('\n')[1]}\nBefore\nAfter',
      );
      expect((await repo.listScraps()).single.body, reordered.body);
      await repo.updateScrap(reordered, 'Before\nAfter');
      expect((await repo.listScraps()).single.body, 'Before\nAfter');
      await repo.deleteScrap(saved.id);
      expect(await repo.listScraps(), isEmpty);
      expect(Directory('${vault.path}/.trash/scraps').listSync(), hasLength(1));
      expect(
        File(
          Uri.directory(
            '${vault.path}/scraps',
          ).resolve(saved.assets.single.relativePath).toFilePath(),
        ).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'nested Notes keep inline images and existing image reuse has no duplicates',
    () async {
      final repo = NoteRepository(vault);
      await repo.createFolder('Trips');
      final nested = await repo.createFolder('Seoul', parent: 'Trips');
      expect(
        (await repo.listFolders()).map((f) => f.id),
        containsAll(['Trips', 'Trips/Seoul']),
      );
      final note = await repo.createNote(
        'Before\n${InlineImage.markdown(image.path)}\nAfter',
        folder: nested.id,
        attachmentPaths: [image.path],
      );
      expect(note.body, startsWith('Before\n![Image](../../../assets/'));
      final updated = await repo.updateNote(
        note,
        '${note.body}\n${InlineImage.markdown(image.path)}\nLast',
        attachmentPaths: [image.path],
      );
      expect(InlineImage.pattern.allMatches(updated.body), hasLength(2));
      expect(updated.body, isNot(contains('file:')));
      expect(updated.body, endsWith('\nLast'));
      expect(updated.assets, hasLength(1));
      await expectLater(
        repo.createFolder('escape', parent: '../outside'),
        throwsFormatException,
      );
    },
  );

  test(
    'Note attachment aliases with identical bytes share one stored asset',
    () async {
      final alias = File('${vault.path}/same-image.jpg');
      await alias.writeAsBytes(await image.readAsBytes());
      final repo = NoteRepository(vault);
      final note = await repo.createNote(
        '${InlineImage.markdown(image.path)}\n${InlineImage.markdown(alias.path)}',
        folder: '',
        attachmentPaths: [image.path, alias.path],
      );
      expect(note.assets, hasLength(1));
      expect(InlineImage.pattern.allMatches(note.body), hasLength(2));
      expect(note.body, isNot(contains('file:')));
      expect(note.body, isNot(contains('.jpg')));
    },
  );

  test('multi-image rows survive attachment import and reopen', () async {
    final second = File('${vault.path}/second.png');
    await second.writeAsBytes([4, 5, 6]);
    final repo = NoteRepository(vault);
    final body = InlineImage.selectionMarkdown([
      image.path,
      second.path,
    ], labelFor: (source) => Uri.file(source).pathSegments.last);

    final saved = await repo.createNote(
      body,
      folder: '',
      attachmentPaths: [image.path, second.path],
    );
    final reopened = (await repo.listNotes()).single;

    expect(saved.body, contains(InlineImageRow.begin));
    expect(reopened.body, saved.body);
    expect(InlineImageRow.items(reopened.body), hasLength(2));
    expect(reopened.body, isNot(contains('file:')));
    expect(reopened.assets, hasLength(2));
  });
}
