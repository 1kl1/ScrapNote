import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_snapshot.dart';
import 'package:scrapnote/infrastructure/platform/mobile_vault_migration.dart';
import 'package:scrapnote/infrastructure/sync/capture_sync_engine.dart';

void main() {
  late Directory support;
  setUp(
    () async => support = await Directory.systemTemp.createTemp(
      'mobile-capture-migrate-',
    ),
  );
  tearDown(() async => support.delete(recursive: true));
  Future<File> write(String name, String body) async {
    final now = DateTime.utc(2026, 11, 20);
    final file = File('${support.path}/vault/scraps/$name.md');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      CaptureSyncEngine.codec.encode(
        Scrap(id: name, body: body, createdAt: now, updatedAt: now),
      ),
    );
    return file;
  }

  Future<void> baseline(Map<String, String> entries) async {
    final file = File('${support.path}/vault/.sync/state.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'identity': 'https://test.example/owner',
        'entries': entries,
      }),
    );
  }

  test(
    'imports unsent creations, edits and deletes while keeping downloaded documents and old vault intact',
    () async {
      final downloaded = await write('pc', 'downloaded');
      final edited = await write('edited', 'before');
      final deleted = await write('deleted', 'delete me');
      final editedBase = (await CaptureSyncEngine.fileDigest(edited))!;
      final deletedBase = (await CaptureSyncEngine.fileDigest(deleted))!;
      await baseline({
        'scraps/pc.md': (await CaptureSyncEngine.fileDigest(downloaded))!,
        'scraps/edited.md': editedBase,
        'scraps/deleted.md': deletedBase,
      });
      await write('edited', 'mobile edit');
      await write('new', 'mobile creation');
      await deleted.delete();
      final target = await resolveMobileCaptureDirectory(support);
      final scan = await CaptureSyncEngine.scan(target);
      expect(scan.keys, unorderedEquals(['scraps/edited.md', 'scraps/new.md']));
      final state = await CaptureSyncEngine.readState(target);
      expect(state['identity'], 'https://test.example/owner');
      expect(state['entries'], {
        'scraps/edited.md': editedBase,
        'scraps/deleted.md': deletedBase,
      });
      expect(await downloaded.exists(), isTrue);
      expect(await edited.readAsString(), contains('mobile edit'));
      await write('later', 'old vault must not get imported a second time');
      expect((await resolveMobileCaptureDirectory(support)).path, target.path);
      expect(
        (await CaptureSyncEngine.scan(target)).keys,
        isNot(contains('scraps/later.md')),
      );
    },
  );
  test(
    'keeps a recovered dirty document and its baseline even when the saved file is unchanged',
    () async {
      final file = await write('draft', 'saved body');
      final digest = (await CaptureSyncEngine.fileDigest(file))!;
      await baseline({'scraps/draft.md': digest});
      final snapshot = EditorRecoverySnapshot(
        capturedAt: DateTime.now(),
        activeSessionId: 'tab',
        documents: [
          EditorRecoveryDocument(
            sessionId: 'tab',
            scrapId: 'draft',
            body: 'unsaved body',
            savedBody: 'saved body',
            pendingImagePaths: [],
          ),
        ],
      );
      final recovery = File('${support.path}/editor-recovery.json');
      await recovery.writeAsString(jsonEncode(snapshot.toJson()));
      final target = await resolveMobileCaptureDirectory(support);
      expect((await CaptureSyncEngine.scan(target)).keys, ['scraps/draft.md']);
      expect((await CaptureSyncEngine.readState(target))['entries'], {
        'scraps/draft.md': digest,
      });
      expect(await recovery.readAsString(), contains('unsaved body'));
    },
  );
  test(
    'damaged old metadata starts a safe capture directory without reuploading downloaded data',
    () async {
      final original = await write('unknown', 'original');
      final state = File('${support.path}/vault/.sync/state.json');
      await state.parent.create(recursive: true);
      await state.writeAsString('broken');
      final target = await resolveMobileCaptureDirectory(support);
      expect(await CaptureSyncEngine.scan(target), isEmpty);
      expect(await original.exists(), isTrue);
      expect(
        (await CaptureSyncEngine.readState(target))['migration_notice'],
        isNotNull,
      );
    },
  );
  test(
    'migration can resume after copying a document but before finishing metadata',
    () async {
      final file = await write('edit', 'old');
      final digest = (await CaptureSyncEngine.fileDigest(file))!;
      await baseline({'scraps/edit.md': digest});
      await write('edit', 'new');
      final destination = File('${support.path}/capture-v1/scraps/edit.md');
      await destination.parent.create(recursive: true);
      await file.copy(destination.path);
      final target = await resolveMobileCaptureDirectory(support);
      expect((await CaptureSyncEngine.readState(target))['entries'], {
        'scraps/edit.md': digest,
      });
      expect(await destination.readAsString(), contains('new'));
    },
  );
}
