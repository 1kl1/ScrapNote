import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrapnote/infrastructure/sync/sync_manifest.dart';
import 'package:scrapnote/infrastructure/sync/vault_sync_engine.dart';

class MemoryRemote implements SyncRemote {
  @override
  String identity = 'test-server/test-user';
  SyncManifest manifest = SyncManifest(0, {});
  final blobs = <String, Uint8List>{};
  bool offline = false;
  bool race = false;
  bool corrupt = false;
  @override
  Future<SyncManifest> readManifest() async {
    if (offline) throw const SocketException('offline');
    return manifest;
  }

  @override
  Future<void> upload(String digest, Uint8List bytes) async {
    blobs[digest] = bytes;
  }

  @override
  Future<Uint8List> download(String digest) async =>
      corrupt ? Uint8List(0) : blobs[digest]!;
  @override
  Future<void> commit(int expectedRevision, Map<String, String> entries) async {
    if (race || expectedRevision != manifest.revision) {
      throw StateError('stale revision');
    }
    manifest = SyncManifest(expectedRevision + 1, entries);
  }
}

void main() {
  late Directory desktop, phone;
  late MemoryRemote remote;
  late VaultSyncEngine a, b;
  setUp(() async {
    desktop = await Directory.systemTemp.createTemp('sync-desktop-');
    phone = await Directory.systemTemp.createTemp('sync-phone-');
    remote = MemoryRemote();
    a = VaultSyncEngine(desktop, remote);
    b = VaultSyncEngine(phone, remote);
  });
  tearDown(() async {
    await desktop.delete(recursive: true);
    await phone.delete(recursive: true);
  });
  Future<File> write(Directory root, String name, String body) async {
    final file = File(p.join(root.path, name));
    await file.parent.create(recursive: true);
    return file.writeAsString(body);
  }

  test('syncs all data and empty folders, excludes drafts and trash', () async {
    for (final name in [
      'scraps/a.md',
      'notes/trip/n.md',
      'assets/sha256/ab/abc.png',
      'expenses/a.json',
      'expenses/.settings/summary.json',
    ]) {
      await write(desktop, name, 'contents of $name');
    }
    await Directory(
      p.join(desktop.path, 'notes/empty'),
    ).create(recursive: true);
    await write(desktop, '.trash/a.md', 'private trash');
    await write(desktop, 'notes/.draft.md', 'private draft');
    await a.synchronize();
    await b.synchronize();
    expect(await b.scan(), await a.scan());
    expect(remote.manifest.entries, hasLength(7));
    expect(await File(p.join(phone.path, '.trash/a.md')).exists(), isFalse);
  });

  test('two devices merge independent edits and propagate deletion', () async {
    await write(desktop, 'scraps/a.md', 'first');
    await a.synchronize();
    await b.synchronize();
    await write(desktop, 'notes/n.md', 'desktop note');
    await write(phone, 'expenses/a.json', 'phone expense');
    await a.synchronize();
    await b.synchronize();
    await a.synchronize();
    expect(await a.scan(), await b.scan());
    await File(p.join(phone.path, 'scraps/a.md')).delete();
    await b.synchronize();
    await a.synchronize();
    expect(await File(p.join(desktop.path, 'scraps/a.md')).exists(), isFalse);
    expect(
      await Directory(
        p.join(desktop.path, '.trash/sync'),
      ).list(recursive: true).where((e) => e is File).length,
      1,
    );
  });

  test(
    'conflicting changes preserve both versions until explicitly resolved',
    () async {
      await write(desktop, 'scraps/a.md', 'base');
      await a.synchronize();
      await b.synchronize();
      await write(desktop, 'scraps/a.md', 'desktop');
      await write(phone, 'scraps/a.md', 'phone');
      await a.synchronize();
      SyncConflict? conflict;
      try {
        await b.synchronize();
      } on SyncConflicts catch (e) {
        conflict = e.files.single;
      }
      expect(conflict, isNotNull);
      expect(
        await File(p.join(phone.path, 'scraps/a.md')).readAsString(),
        'phone',
      );
      await b.synchronize(
        resolutions: {
          'scraps/a.md': SyncResolution(conflict!, useLocal: false),
        },
      );
      expect(
        await File(p.join(phone.path, 'scraps/a.md')).readAsString(),
        'desktop',
      );
      final backups = await Directory(
        p.join(phone.path, '.trash/sync'),
      ).list(recursive: true).where((f) => f is File).cast<File>().toList();
      expect(await backups.single.readAsString(), 'phone');
    },
  );

  test(
    'delete versus edit is a conflict and stale decisions are rejected',
    () async {
      await write(desktop, 'notes/n.md', 'base');
      await a.synchronize();
      await b.synchronize();
      await File(p.join(desktop.path, 'notes/n.md')).delete();
      await a.synchronize();
      await write(phone, 'notes/n.md', 'edited');
      await expectLater(b.synchronize(), throwsA(isA<SyncConflicts>()));
      await expectLater(
        b.synchronize(
          resolutions: {
            'notes/n.md': const SyncResolution(
              SyncConflict('notes/n.md', 'stale', null),
              useLocal: false,
            ),
          },
        ),
        throwsA(isA<SyncConflicts>()),
      );
      expect(
        await File(p.join(phone.path, 'notes/n.md')).readAsString(),
        'edited',
      );
    },
  );

  test('offline edits are retried without losing files', () async {
    await write(desktop, 'scraps/a.md', 'offline');
    remote.offline = true;
    await expectLater(a.synchronize(), throwsA(isA<SocketException>()));
    remote.offline = false;
    await a.synchronize();
    await b.synchronize();
    expect(
      await File(p.join(phone.path, 'scraps/a.md')).readAsString(),
      'offline',
    );
  });

  test('failed concurrent commit does not apply downloaded changes', () async {
    await write(desktop, 'scraps/a.md', 'remote');
    await a.synchronize();
    await write(phone, 'notes/n.md', 'local');
    remote.race = true;
    await expectLater(b.synchronize(), throwsStateError);
    expect(await File(p.join(phone.path, 'scraps/a.md')).exists(), isFalse);
    expect(
      await File(p.join(phone.path, 'notes/n.md')).readAsString(),
      'local',
    );
  });

  test('corrupt downloads fail before writing to the vault', () async {
    await write(desktop, 'scraps/a.md', 'remote');
    await a.synchronize();
    remote.corrupt = true;
    await expectLater(b.synchronize(), throwsFormatException);
    expect(await File(p.join(phone.path, 'scraps/a.md')).exists(), isFalse);
  });

  test('an already bound vault cannot upload to another account', () async {
    await write(desktop, 'scraps/a.md', 'private');
    await a.synchronize();
    remote.identity = 'test-server/other-user';
    await expectLater(a.synchronize(), throwsFormatException);
  });

  test(
    'remote paths cannot escape the vault or follow local symlinks',
    () async {
      expect(
        () => SyncManifest(0, {'notes/../../secret': directoryDigest}),
        throwsFormatException,
      );
      expect(
        () => SyncManifest(0, {'/tmp/secret': directoryDigest}),
        throwsFormatException,
      );
      await write(desktop, 'notes/linked/n.md', 'remote');
      await a.synchronize();
      await Directory(p.join(phone.path, 'notes')).create();
      await Link(p.join(phone.path, 'notes/linked')).create(desktop.path);
      await expectLater(b.synchronize(), throwsA(isA<FileSystemException>()));
      expect(await File(p.join(desktop.path, 'n.md')).exists(), isFalse);
    },
  );

  test('new child survives another devices empty folder deletion', () async {
    final base = {'notes/trip': directoryDigest};
    final child = sha256.convert([1, 2]).toString();
    expect(
      mergeManifests(base, {}, {
        'notes/trip': directoryDigest,
        'notes/trip/n.md': child,
      }),
      {'notes/trip': directoryDigest, 'notes/trip/n.md': child},
    );
  });
}
