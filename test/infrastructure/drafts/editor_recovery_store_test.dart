import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_snapshot.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_store.dart';

void main() {
  late _MemoryRecoveryFileIo io;
  late EditorRecoveryStore store;

  setUp(() {
    io = _MemoryRecoveryFileIo();
    store = EditorRecoveryStore(
      pathProvider: () async => '/support/editor-recovery.json',
      io: io,
    );
  });

  test('saves and restores recovery JSON through injected I/O', () async {
    final snapshot = EditorRecoverySnapshot(
      capturedAt: DateTime.utc(2026, 9, 5, 12),
      activeSessionId: 'tab-1',
      documents: <EditorRecoveryDocument>[
        EditorRecoveryDocument(
          sessionId: 'tab-1',
          scrapId: 'scrap-1',
          body: 'Unsaved',
          savedBody: 'Saved',
          pendingImagePaths: const <String>['/tmp/image.png'],
        ),
      ],
    );

    await store.save(snapshot);
    final loaded = await store.load();

    expect(io.lastAtomicWritePath, '/support/editor-recovery.json');
    expect(loaded?.capturedAt, snapshot.capturedAt);
    expect(loaded?.activeSessionId, 'tab-1');
    expect(loaded?.documents.single.sessionId, 'tab-1');
    expect(loaded?.documents.single.scrapId, 'scrap-1');
    expect(loaded?.documents.single.body, 'Unsaved');
    expect(loaded?.documents.single.savedBody, 'Saved');
    expect(loaded?.documents.single.pendingImagePaths, <String>[
      '/tmp/image.png',
    ]);
  });

  test('an empty snapshot clears recovery data', () async {
    io.files['/support/editor-recovery.json'] = 'old data';
    final empty = EditorRecoverySnapshot(
      capturedAt: DateTime.utc(2026, 9, 5),
      activeSessionId: null,
      documents: const <EditorRecoveryDocument>[],
    );

    await store.save(empty);

    expect(await store.load(), isNull);
    expect(io.deletedPaths, <String>['/support/editor-recovery.json']);
  });

  test('rejects malformed recovery JSON', () async {
    io.files['/support/editor-recovery.json'] = '{"version": 99}';

    await expectLater(store.load(), throwsFormatException);
  });
}

class _MemoryRecoveryFileIo implements RecoveryFileIo {
  final Map<String, String> files = <String, String>{};
  final List<String> deletedPaths = <String>[];
  String? lastAtomicWritePath;

  @override
  Future<void> delete(String filePath) async {
    deletedPaths.add(filePath);
    files.remove(filePath);
  }

  @override
  Future<bool> exists(String filePath) async => files.containsKey(filePath);

  @override
  Future<String> read(String filePath) async => files[filePath]!;

  @override
  Future<void> writeAtomically(String filePath, String contents) async {
    lastAtomicWritePath = filePath;
    files[filePath] = contents;
  }
}
