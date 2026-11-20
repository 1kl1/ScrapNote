import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/infrastructure/sync/capture_remote.dart';
import 'package:scrapnote/infrastructure/sync/capture_sync_engine.dart';
import 'package:scrapnote/infrastructure/sync/sync_client.dart';
import 'package:scrapnote/infrastructure/sync/sync_manifest.dart';
import 'package:scrapnote/infrastructure/sync/vault_sync_engine.dart';

class CaptureTestRemote implements CaptureRemote {
  @override
  String identity = 'https://test.example/owner';
  final entries = <String, String>{};
  final blobs = <String, Uint8List>{};
  final receipts = <String, String>{};
  final queried = <String>[];
  final downloaded = <String>[];
  final uploaded = <String>[];
  int revision = 0;
  bool loseResponse = false;
  String? failedUpload;
  bool offline = false;
  bool corrupt = false;
  Future<void> Function()? beforeCommit;
  @override
  Future<Map<String, String?>> status(List<String> paths) async {
    if (offline) throw const SocketException('offline');
    expect(paths.length, lessThanOrEqualTo(100));
    queried.addAll(paths);
    return {for (final path in paths) path: entries[path]};
  }

  @override
  Future<void> upload(String path, String digest, Uint8List bytes) async {
    uploaded.add(path);
    if (failedUpload == path || offline) {
      throw const SocketException('upload failed');
    }
    blobs[digest] = bytes;
  }

  @override
  Future<Uint8List> download(String digest) async {
    downloaded.add(digest);
    return corrupt ? Uint8List(0) : blobs[digest]!;
  }

  @override
  Future<void> commit(Map<String, dynamic> operation) async {
    if (offline) throw const SocketException('offline');
    final id = operation['operation_id'] as String;
    if (receipts.containsKey(id)) return;
    await beforeCommit?.call();
    final path = operation['path'] as String;
    if (entries[path] != operation['base']) {
      throw const SyncAuthException('conflict', code: 'capture_conflict');
    }
    for (final digest in [
      operation['digest'],
      ...(operation['assets'] as Map).values,
    ].whereType<String>()) {
      if (!blobs.containsKey(digest)) {
        throw const SyncAuthException('missing blob', code: 'missing_blob');
      }
    }
    entries.addAll(Map<String, String>.from(operation['assets'] as Map));
    if (operation['digest'] case final String digest) {
      entries[path] = digest;
    } else {
      entries.remove(path);
    }
    receipts[id] = path;
    revision++;
    if (loseResponse) {
      loseResponse = false;
      throw const SocketException('response lost');
    }
  }
}

class DesktopRemote implements SyncRemote {
  DesktopRemote(this.capture);
  final CaptureTestRemote capture;
  @override
  String get identity => capture.identity;
  @override
  Future<SyncManifest> readManifest() async =>
      SyncManifest(capture.revision, capture.entries);
  @override
  Future<void> upload(String digest, Uint8List bytes, {required String path}) =>
      capture.upload(path, digest, bytes);
  @override
  Future<Uint8List> download(String digest) => capture.download(digest);
  @override
  Future<void> commit(int expectedRevision, Map<String, String> entries) async {
    if (expectedRevision != capture.revision) throw StateError('stale');
    capture.entries
      ..clear()
      ..addAll(entries);
    capture.revision++;
  }
}

void main() {
  late Directory root;
  late CaptureTestRemote remote;
  final now = DateTime.utc(2026, 11, 20);
  Future<File> write(
    String path,
    String body, {
    List<ScrapAsset> assets = const [],
  }) async {
    final file = File(p.join(root.path, path));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      CaptureSyncEngine.codec.encode(
        Scrap(
          id: path,
          body: body,
          createdAt: now,
          updatedAt: now,
          assets: assets,
        ),
      ),
    );
    return file;
  }

  Future<String> serverWrite(String path, String body) async {
    final bytes = Uint8List.fromList(
      utf8.encode(
        CaptureSyncEngine.codec.encode(
          Scrap(id: path, body: body, createdAt: now, updatedAt: now),
        ),
      ),
    );
    final digest = sha256.convert(bytes).toString();
    remote.blobs[digest] = bytes;
    remote.entries[path] = digest;
    remote.revision++;
    return digest;
  }

  CaptureSyncEngine engine({bool Function()? apply}) =>
      CaptureSyncEngine(root, remote, canApplyRemote: apply);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('capture-sync-');
    remote = CaptureTestRemote();
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'queries only own paths and uploads only their attachments, without full download',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final hash = sha256.convert(bytes).toString();
      final assetPath = 'assets/sha256/${hash.substring(0, 2)}/$hash.png';
      final asset = File(p.join(root.path, assetPath));
      await asset.parent.create(recursive: true);
      await asset.writeAsBytes(bytes);
      await write(
        'scraps/phone.md',
        'phone',
        assets: [
          ScrapAsset(
            hash: hash,
            relativePath: '../$assetPath',
            originalName: 'photo',
            mimeType: 'image/png',
          ),
        ],
      );
      await File(p.join(asset.parent.path, 'unrelated.png')).writeAsBytes([9]);
      final pc = await serverWrite('scraps/pc.md', 'pc');
      remote.entries['notes/pc.md'] = pc;
      remote.entries['expenses/pc.json'] = pc;
      await engine().synchronize();
      expect(remote.queried, ['scraps/phone.md']);
      expect(remote.downloaded, isEmpty);
      expect(remote.entries['notes/pc.md'], pc);
      expect(remote.entries['expenses/pc.json'], pc);
      expect(remote.entries[assetPath], hash);
      expect(
        remote.entries.keys.any((key) => key.contains('unrelated')),
        isFalse,
      );
      expect(
        (await CaptureSyncEngine.items(root)).single.phase,
        CapturePhase.complete,
      );
    },
  );

  test(
    'phone create/edit/delete round-trips through the unchanged desktop engine',
    () async {
      final desktop = await Directory.systemTemp.createTemp('capture-desktop-');
      addTearDown(() => desktop.delete(recursive: true));
      final pc = VaultSyncEngine(desktop, DesktopRemote(remote));
      await write('scraps/phone.md', 'created');
      await engine().synchronize();
      await pc.synchronize();
      expect(
        await File(p.join(desktop.path, 'scraps/phone.md')).exists(),
        isTrue,
      );
      await write('scraps/phone.md', 'edited');
      await engine().synchronize();
      await pc.synchronize();
      expect(
        await File(p.join(desktop.path, 'scraps/phone.md')).readAsString(),
        contains('edited'),
      );
      await File(p.join(root.path, 'scraps/phone.md')).delete();
      expect((await CaptureSyncEngine.items(root)).single.label, '삭제 전송 대기');
      await engine().synchronize();
      await pc.synchronize();
      expect(
        await File(p.join(desktop.path, 'scraps/phone.md')).exists(),
        isFalse,
      );
      expect((await CaptureSyncEngine.items(root)).single.label, '서버에서 삭제됨');
    },
  );

  test(
    'PC changes and deletes own scrap; unsaved editor blocks remote replacement',
    () async {
      final file = await write('scraps/a.md', 'base');
      await engine().synchronize();
      await serverWrite('scraps/a.md', 'PC change');
      await engine(apply: () => false).synchronize();
      expect(await file.readAsString(), contains('base'));
      await engine().synchronize();
      expect(await file.readAsString(), contains('PC change'));
      remote.entries.remove('scraps/a.md');
      await engine().synchronize();
      expect(await file.exists(), isFalse);
      final backups = await Directory(
        p.join(root.path, '.trash/capture'),
      ).list(recursive: true).where((entity) => entity is File).toList();
      expect(backups, hasLength(2));
    },
  );

  test(
    'lost create response then PC deletion is acknowledged without resurrection',
    () async {
      final file = await write('scraps/a.md', 'phone');
      remote.loseResponse = true;
      await engine().synchronize();
      expect(
        (await CaptureSyncEngine.items(root)).single.phase,
        CapturePhase.failed,
      );
      remote.entries.remove('scraps/a.md');
      await engine().synchronize();
      expect(remote.entries.containsKey('scraps/a.md'), isFalse);
      expect(await file.exists(), isFalse);
      expect(remote.receipts.length, 1);
    },
  );

  test(
    'lost response retains snapshot while newer local edit is sent next',
    () async {
      await write('scraps/a.md', 'first');
      remote.loseResponse = true;
      await engine().synchronize();
      await write('scraps/a.md', 'second');
      await engine().synchronize();
      expect(
        utf8.decode(remote.blobs[remote.entries['scraps/a.md']]!),
        contains('second'),
      );
      expect(remote.receipts, hasLength(2));
    },
  );

  test(
    'one failed upload does not block another scrap and retry survives restart',
    () async {
      await write('scraps/a.md', 'a');
      await write('scraps/b.md', 'b');
      remote.failedUpload = 'scraps/a.md';
      await engine().synchronize();
      expect(remote.entries.keys, contains('scraps/b.md'));
      expect(remote.entries.keys, isNot(contains('scraps/a.md')));
      remote.failedUpload = null;
      await engine().synchronize();
      expect(remote.entries.keys, containsAll(['scraps/a.md', 'scraps/b.md']));
    },
  );

  test(
    'edit/delete conflicts preserve local data and reject stale choices',
    () async {
      final file = await write('scraps/a.md', 'base');
      await engine().synchronize();
      await write('scraps/a.md', 'local');
      remote.entries.remove('scraps/a.md');
      SyncConflict? conflict;
      try {
        await engine().synchronize();
      } on SyncConflicts catch (error) {
        conflict = error.files.single;
      }
      expect(conflict, isNotNull);
      expect(await file.readAsString(), contains('local'));
      await write('scraps/a.md', 'new local');
      await expectLater(
        engine().synchronize(
          resolutions: {
            'scraps/a.md': SyncResolution(conflict!, useLocal: false),
          },
        ),
        throwsA(isA<SyncConflicts>()),
      );
      final fresh = SyncConflict(
        'scraps/a.md',
        await CaptureSyncEngine.fileDigest(file),
        null,
      );
      await engine().synchronize(
        resolutions: {fresh.path: SyncResolution(fresh, useLocal: true)},
      );
      expect(remote.entries.containsKey(fresh.path), isTrue);
    },
  );

  test('remote changed between status and commit is not overwritten', () async {
    final file = await write('scraps/a.md', 'base');
    await engine().synchronize();
    await write('scraps/a.md', 'phone');
    remote.beforeCommit = () async {
      remote.beforeCommit = null;
      await serverWrite('scraps/a.md', 'concurrent PC');
    };
    await engine().synchronize();
    expect(await file.readAsString(), contains('phone'));
    await expectLater(engine().synchronize(), throwsA(isA<SyncConflicts>()));
    expect(
      utf8.decode(remote.blobs[remote.entries['scraps/a.md']]!),
      contains('concurrent PC'),
    );
  });

  test(
    'bad downloads and changed accounts leave the local document intact',
    () async {
      final file = await write('scraps/a.md', 'base');
      await engine().synchronize();
      await serverWrite('scraps/a.md', 'PC');
      remote.corrupt = true;
      await engine().synchronize();
      expect(await file.readAsString(), contains('base'));
      expect(
        (await CaptureSyncEngine.items(root)).single.phase,
        CapturePhase.failed,
      );
      remote.identity = 'https://test.example/other';
      await expectLater(engine().synchronize(), throwsFormatException);
      expect(await file.readAsString(), contains('base'));
    },
  );

  test('status batches more than 100 own documents', () async {
    for (var index = 0; index < 101; index++) {
      await write('scraps/$index.md', 'item $index');
    }
    await engine().synchronize();
    expect(remote.queried, hasLength(101));
    expect(remote.entries, hasLength(101));
  });
  test(
    'an offline status request marks pending captures failed and retries after restart',
    () async {
      await write('scraps/offline.md', 'keep me');
      remote.offline = true;
      await expectLater(
        engine().synchronize(),
        throwsA(isA<SocketException>()),
      );
      expect(
        (await CaptureSyncEngine.items(root)).single.phase,
        CapturePhase.failed,
      );
      remote.offline = false;
      await engine().synchronize();
      expect(
        (await CaptureSyncEngine.items(root)).single.phase,
        CapturePhase.complete,
      );
    },
  );
  test(
    'acknowledged photos survive edit retries and recover if server blobs are restored away',
    () async {
      final bytes = Uint8List.fromList([5, 6, 7]);
      final digest = sha256.convert(bytes).toString();
      final path = 'assets/sha256/${digest.substring(0, 2)}/$digest.png';
      final photo = File(p.join(root.path, path));
      await photo.parent.create(recursive: true);
      await photo.writeAsBytes(bytes);
      final assets = [
        ScrapAsset(
          hash: digest,
          relativePath: '../$path',
          originalName: 'photo',
          mimeType: 'image/png',
        ),
      ];
      await write('scraps/a.md', 'first', assets: assets);
      await engine().synchronize();
      await write('scraps/a.md', 'edited', assets: assets);
      remote.loseResponse = true;
      await engine().synchronize();
      await engine().synchronize();
      expect(remote.uploaded.where((name) => name == path), hasLength(1));
      remote.blobs.remove(digest);
      await write('scraps/a.md', 'after server recovery', assets: assets);
      await engine().synchronize();
      expect(
        (await CaptureSyncEngine.items(root)).single.phase,
        CapturePhase.failed,
      );
      await engine().synchronize();
      expect(remote.uploaded.where((name) => name == path), hasLength(2));
      expect(
        (await CaptureSyncEngine.items(root)).single.phase,
        CapturePhase.complete,
      );
    },
  );
}
