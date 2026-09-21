import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'sync_manifest.dart';
import '../vault/oversized_image_migrator.dart';

abstract interface class SyncRemote {
  /// Includes the server and authenticated user; prevents cross-account uploads.
  String get identity;
  Future<SyncManifest> readManifest();
  Future<void> upload(String digest, Uint8List bytes);
  Future<Uint8List> download(String digest);
  Future<void> commit(int expectedRevision, Map<String, String> entries);
}

class SyncBusy implements Exception {
  const SyncBusy();
}

class VaultSyncEngine {
  VaultSyncEngine(
    this.root,
    this.remote, {
    this.maxFileBytes = 25 * 1024 * 1024,
    this.imageMaxDimension = 4096,
  });
  final Directory root;
  final SyncRemote remote;
  final int maxFileBytes;
  final int imageMaxDimension;
  bool _running = false;
  File get _state => File(p.join(root.path, '.sync', 'state.json'));

  Future<void> synchronize({
    Map<String, SyncResolution> resolutions = const {},
  }) async {
    if (_running) throw const SyncBusy();
    _running = true;
    try {
      final base = await _baseline();
      final remoteManifest = await remote.readManifest();
      // The user explicitly requested sync. Prepare old over-limit photos only
      // after the server is reachable, before taking the local manifest.
      await OversizedImageMigrator(
        root,
        maxBytes: maxFileBytes,
        maxDimension: imageMaxDimension,
      ).migrate();
      final local = await scan();
      final merged = mergeManifests(
        base,
        local,
        remoteManifest.entries,
        resolutions: resolutions,
      );
      // Validate before any download or mutation, including directory/file ancestry.
      SyncManifest(0, merged);
      for (final name in merged.keys) {
        var parent = p.posix.dirname(name);
        while (parent != '.') {
          if (merged[parent] != null && merged[parent] != directoryDigest) {
            throw const FormatException(
              'A synchronized file is also used as a folder.',
            );
          }
          parent = p.posix.dirname(parent);
        }
      }
      final staged = <String, Uint8List>{};
      for (final entry in merged.entries) {
        if (entry.value == directoryDigest) continue;
        if (remoteManifest.entries[entry.key] != entry.value) {
          final bytes = await (await _safeFile(entry.key)).readAsBytes();
          if (bytes.length > maxFileBytes ||
              sha256.convert(bytes).toString() != entry.value) {
            throw const FileSystemException(
              'File changed during sync or exceeds 25 MB.',
            );
          }
          await remote.upload(entry.value, bytes);
        }
        if (local[entry.key] != entry.value) {
          final bytes = await remote.download(entry.value);
          if (bytes.length > maxFileBytes ||
              sha256.convert(bytes).toString() != entry.value) {
            throw const FormatException(
              'Downloaded file failed integrity verification.',
            );
          }
          staged[entry.key] = bytes;
        }
      }
      if (!sameManifest(local, await scan())) {
        throw const FileSystemException(
          'Local files changed. Please retry sync.',
        );
      }
      if (!sameManifest(merged, remoteManifest.entries)) {
        await remote.commit(remoteManifest.revision, merged);
      }
      // Recheck after the network commit as an external editor can still write.
      if (!sameManifest(local, await scan())) {
        throw const FileSystemException(
          'Local files changed. Please retry sync.',
        );
      }
      await _safeInternalDirectory('.trash');
      await _safeInternalDirectory('.trash/sync');
      final backupId = DateTime.now().microsecondsSinceEpoch.toString();
      for (final name in {...local.keys, ...merged.keys}) {
        if (local[name] == merged[name]) continue;
        final target = await _safeFile(name);
        if (local[name] != null && local[name] != directoryDigest) {
          if (!await target.exists() ||
              (await sha256.bind(target.openRead()).first).toString() !=
                  local[name]) {
            throw const FileSystemException(
              'A file changed while applying sync. Retry after saving.',
            );
          }
          final backup = File(
            p.join(root.path, '.trash', 'sync', backupId, name),
          );
          await backup.parent.create(recursive: true);
          await target.copy(backup.path);
        }
        if (merged[name] == directoryDigest) {
          if (await target.exists()) await target.delete();
          await Directory(target.path).create(recursive: true);
        } else if (staged[name] case final bytes?) {
          await target.parent.create(recursive: true);
          final temp = File('${target.path}.$backupId.sync.tmp');
          await temp.writeAsBytes(bytes, flush: true);
          await temp.rename(target.path);
        } else if (merged[name] == null &&
            local[name] != directoryDigest &&
            await target.exists()) {
          await target.delete();
        }
      }
      // Remove empty directories deepest-first; never recursively remove user files.
      final removed =
          local.keys
              .where((n) => local[n] == directoryDigest && merged[n] == null)
              .toList()
            ..sort((a, b) => b.length.compareTo(a.length));
      for (final name in removed) {
        final directory = Directory((await _safeFile(name)).path);
        if (await directory.exists() && await directory.list().isEmpty) {
          await directory.delete();
        }
      }
      await _writeState(merged, syncedAt: DateTime.now().toUtc());
    } finally {
      _running = false;
    }
  }

  Future<Map<String, String>> _baseline() async {
    await _safeInternalDirectory('.sync');
    if (!await _state.exists()) {
      // Bind before upload, including failed first attempts.
      await _writeState({});
      return {};
    }
    if (await FileSystemEntity.type(_state.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('Sync state must not be a symlink.');
    }
    final state =
        jsonDecode(await _state.readAsString()) as Map<String, dynamic>;
    if (state['identity'] != remote.identity) {
      throw const FormatException(
        '이 저장소는 다른 서버 또는 계정에 연결되어 있습니다. 별도 저장소를 사용해 주세요.',
      );
    }
    return SyncManifest(
      0,
      Map<String, String>.from(state['entries'] as Map),
    ).entries;
  }

  Future<void> _writeState(
    Map<String, String> entries, {
    DateTime? syncedAt,
  }) async {
    final temporary = File(
      '${_state.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsString(
      jsonEncode({
        'identity': remote.identity,
        'entries': entries,
        'synced_at': syncedAt?.toIso8601String(),
      }),
      flush: true,
    );
    await temporary.rename(_state.path);
  }

  Future<void> _safeInternalDirectory(String name) async {
    final directory = Directory(p.join(root.path, name));
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException(
        'Symlinks are not allowed in sync metadata.',
      );
    }
    await directory.create(recursive: true);
  }

  Future<File> _safeFile(String name) async {
    validateSyncPath(name);
    var current = root.path;
    for (final component in name.split('/')) {
      current = p.join(current, component);
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException('Symlinks are not synchronized.');
      }
    }
    return File(current);
  }

  Future<Map<String, String>> scan() async {
    final entries = <String, String>{};
    for (final folder in ['scraps', 'notes', 'assets', 'expenses']) {
      final directory = Directory(p.join(root.path, folder));
      if (await FileSystemEntity.type(directory.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException(
          'Vault directories must not be symlinks.',
        );
      }
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        final name = p
            .relative(entity.path, from: root.path)
            .split(p.separator)
            .join('/');
        try {
          validateSyncPath(name);
        } on FormatException {
          continue;
        }
        if (entity is Directory && name.startsWith('notes/')) {
          entries[name] = directoryDigest;
        } else if (entity is File &&
            (folder != 'notes' || name.endsWith('.md'))) {
          if (await entity.length() > maxFileBytes) {
            throw FileSystemException('동기화 가능한 파일 크기는 25 MB 이하입니다.', name);
          }
          entries[name] = (await sha256.bind(entity.openRead()).first)
              .toString();
        }
      }
    }
    return entries;
  }
}
