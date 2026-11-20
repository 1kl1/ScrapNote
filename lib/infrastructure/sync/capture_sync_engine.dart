import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../vault/front_matter_codec.dart';
import 'capture_remote.dart';
import 'sync_client.dart';
import 'sync_manifest.dart';

enum CapturePhase { pending, uploading, complete, failed, conflict }

class CaptureWriteLock {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }
}

class CaptureItem {
  const CaptureItem(
    this.path,
    this.id,
    this.title,
    this.phase, {
    this.deleted = false,
    this.error,
  });
  final String path;
  final String id;
  final String title;
  final CapturePhase phase;
  final bool deleted;
  final String? error;
  String get label => switch (phase) {
    CapturePhase.pending => deleted ? '삭제 전송 대기' : '전송 대기',
    CapturePhase.uploading => '전송 중',
    CapturePhase.complete => deleted ? '서버에서 삭제됨' : '업로드 완료',
    CapturePhase.failed => '전송 실패',
    CapturePhase.conflict => '충돌 · 내용 선택 필요',
  };
}

/// Owns only documents in the separate mobile capture directory. Files are the
/// durable outbox; baselines retain deletions. Pending operation snapshots and
/// server receipts make a lost HTTP response safe even after later PC edits.
class CaptureSyncEngine {
  CaptureSyncEngine(
    this.root,
    this.remote, {
    this.canApplyRemote,
    this.onProgress,
    CaptureWriteLock? writeLock,
  }) : writeLock = writeLock ?? CaptureWriteLock();
  final Directory root;
  final CaptureRemote remote;
  final bool Function()? canApplyRemote;
  final void Function(String path, String status)? onProgress;
  final CaptureWriteLock writeLock;
  bool remoteChangesDeferred = false;
  static const maxBytes = 25 * 1024 * 1024;
  static const codec = ScrapFileCodec();
  Map<String, dynamic> _state = {};
  Map<String, String?> get _base =>
      Map<String, String?>.from(_state['entries'] as Map? ?? {});
  Map<String, dynamic> get _operations =>
      Map<String, dynamic>.from(_state['operations'] as Map? ?? {});

  static Future<Map<String, dynamic>> readState(Directory root) async {
    final file = await safeFile(root, '.capture/state.json', internal: true);
    return await file.exists()
        ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
        : {};
  }

  static Future<List<CaptureItem>> items(Directory root) async {
    final state = await readState(root);
    final base = Map<String, String?>.from(state['entries'] as Map? ?? {});
    final local = await scan(root);
    final labels = state['labels'] as Map? ?? {};
    final errors = state['errors'] as Map? ?? {};
    final operations = state['operations'] as Map? ?? {};
    return [
      for (final path in {
        ...local.keys,
        ...base.keys,
        ...operations.keys.cast<String>(),
      })
        () {
          final entry = local[path];
          final meta = entry ?? labels[path] as Map?;
          final pending =
              entry?['digest'] != base[path] || operations.containsKey(path);
          final error = errors[path] as String?;
          return CaptureItem(
            path,
            meta?['id'] as String? ?? path,
            meta?['title'] as String? ?? '삭제한 scrap',
            error == 'conflict'
                ? CapturePhase.conflict
                : error != null
                ? CapturePhase.failed
                : pending
                ? CapturePhase.pending
                : CapturePhase.complete,
            deleted: entry == null,
            error: error == 'conflict' ? null : error,
          );
        }(),
    ];
  }

  static Future<Map<String, Map<String, String>>> scan(Directory root) async {
    final folder = Directory(
      (await safeFile(root, 'scraps/placeholder.md')).parent.path,
    );
    final result = <String, Map<String, String>>{};
    if (!await folder.exists()) return result;
    await for (final entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final path = p
          .relative(entity.path, from: root.path)
          .split(p.separator)
          .join('/');
      final file = await safeFile(root, path);
      final bytes = await checkedBytes(file);
      final scrap = codec.decode(utf8.decode(bytes));
      result[path] = {
        'digest': sha256.convert(bytes).toString(),
        'id': scrap.id,
        'title': scrap.firstLineTitle.isEmpty
            ? '제목 없는 scrap'
            : scrap.firstLineTitle,
      };
    }
    return result;
  }

  Future<void> synchronize({
    Map<String, SyncResolution> resolutions = const {},
  }) async {
    remoteChangesDeferred = false;
    _state = await readState(root);
    if (_state['identity'] != null && _state['identity'] != remote.identity) {
      throw const FormatException(
        '이 휴대폰 저장소는 다른 서버 또는 계정에 연결되어 있습니다. 기존 계정으로 로그인해 주세요.',
      );
    }
    _state['identity'] = remote.identity;
    await _save();
    final conflicts = <SyncConflict>[];
    final errors = <String, String>{};

    // Replay durable snapshots first, even if the user edited or deleted the
    // local document while an earlier request was awaiting its response.
    for (final entry in _operations.entries) {
      try {
        await _send(Map<String, dynamic>.from(entry.value as Map));
      } on SyncAuthException catch (error) {
        if (error.code == 'capture_conflict') {
          await _discardOperation(entry.key);
        } else {
          errors[entry.key] = error.message;
        }
      } on Exception catch (error) {
        errors[entry.key] = _message(error);
      }
    }
    final local = await scan(root);
    final labels = Map<String, dynamic>.from(_state['labels'] as Map? ?? {});
    for (final entry in local.entries) {
      labels[entry.key] = entry.value;
    }
    _state['labels'] = labels;
    await _save();
    final paths = {..._base.keys, ...local.keys}.toList();
    final server = <String, String?>{};
    try {
      for (var start = 0; start < paths.length; start += 100) {
        final batch = paths.sublist(
          start,
          (start + 100).clamp(0, paths.length),
        );
        final result = await remote.status(batch);
        for (final path in batch) {
          if (!result.containsKey(path)) {
            throw const FormatException('서버가 scrap 상태를 모두 반환하지 않았습니다.');
          }
          final digest = result[path];
          if (digest != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
            throw const FormatException('서버 파일 정보가 올바르지 않습니다.');
          }
          server[path] = digest;
        }
      }
    } on Exception catch (error) {
      for (final path in paths) {
        if (local[path]?['digest'] != _base[path] ||
            _operations.containsKey(path)) {
          errors[path] = _message(error);
        }
      }
      _state['errors'] = errors;
      await _save();
      rethrow;
    }
    for (final path in paths) {
      if (errors.containsKey(path)) continue;
      final l = local[path]?['digest'], b = _base[path], r = server[path];
      try {
        if (l == r) {
          await _ack(path, r);
        } else if (l == b) {
          await _receive(path, r, l);
        } else if (r == b) {
          await _publish(path, l, r);
        } else {
          final resolution = resolutions[path];
          if (resolution == null ||
              resolution.conflict.local != l ||
              resolution.conflict.remote != r) {
            conflicts.add(SyncConflict(path, l, r));
            errors[path] = 'conflict';
          } else if (resolution.useLocal) {
            await _publish(path, l, r);
          } else {
            await _receive(path, r, l);
          }
        }
      } on SyncAuthException catch (error) {
        if (error.code == 'capture_conflict') {
          // Never retry against a newer version without a fresh merge.
          await _discardOperation(path);
          errors[path] = '다른 기기에서 변경했습니다. 다시 시도해 내용을 확인하세요.';
        } else {
          errors[path] = error.message;
        }
      } on Exception catch (error) {
        errors[path] = _message(error);
      }
    }
    _state['errors'] = errors;
    _state['synced_at'] = errors.isEmpty
        ? DateTime.now().toUtc().toIso8601String()
        : _state['synced_at'];
    await _save();
    if (conflicts.isNotEmpty) throw SyncConflicts(conflicts);
  }

  Future<void> _publish(String path, String? digest, String? base) async {
    onProgress?.call(path, digest == null ? '삭제 전송 중' : '업로드 중');
    final operation = <String, dynamic>{
      'operation_id': const Uuid().v4(),
      'path': path,
      'base': base,
      'digest': digest,
      'assets': <String, String>{},
    };
    if (digest != null) {
      final bytes = await checkedBytes(await safeFile(root, path));
      verify(bytes, digest);
      operation['assets'] = assetEntries(path, utf8.decode(bytes));
      await atomicWrite(await _snapshot(operation), bytes);
    }
    final operations = _operations;
    operations[path] = operation;
    _state['operations'] = operations;
    await _save();
    await _send(operation);
  }

  Future<void> _send(Map<String, dynamic> operation) async {
    final path = operation['path'] as String;
    onProgress?.call(path, '전송 중');
    final assets = Map<String, String>.from(operation['assets'] as Map);
    final uploaded = Map<String, bool>.from(
      _state['uploaded_assets'] as Map? ?? {},
    );
    var index = 0;
    for (final entry in assets.entries) {
      onProgress?.call(path, '사진 ${++index}/${assets.length} 전송 중');
      if (uploaded[entry.value] == true) continue;
      final bytes = await checkedBytes(await safeFile(root, entry.key));
      verify(bytes, entry.value);
      await remote.upload(entry.key, entry.value, bytes);
      uploaded[entry.value] = true;
      _state['uploaded_assets'] = uploaded;
      await _save();
    }
    if (operation['digest'] case final String digest) {
      onProgress?.call(path, '본문 전송 중');
      final bytes = await checkedBytes(await _snapshot(operation));
      verify(bytes, digest);
      await remote.upload(path, digest, bytes);
    }
    onProgress?.call(path, '서버 저장 확인 중');
    try {
      await remote.commit(operation);
    } on SyncAuthException catch (error) {
      if (error.code == 'missing_blob') {
        // A restored server may have lost an acknowledged blob. Re-upload on
        // the next attempt instead of trusting a stale local checkpoint.
        _state['uploaded_assets'] = <String, bool>{};
        await _save();
      }
      rethrow;
    }
    await _ack(path, operation['digest'] as String?);
    await _discardOperation(path);
  }

  Future<void> _receive(String path, String? digest, String? local) async {
    onProgress?.call(path, '서버 변경 확인 중');
    if (canApplyRemote?.call() == false) {
      remoteChangesDeferred = true;
      return;
    }
    Uint8List? document;
    if (digest != null) {
      document = await remote.download(digest);
      verify(document, digest);
      final assets = assetEntries(path, utf8.decode(document));
      for (final entry in assets.entries) {
        final file = await safeFile(root, entry.key);
        if (await file.exists() && await fileDigest(file) == entry.value) {
          continue;
        }
        final bytes = await remote.download(entry.value);
        verify(bytes, entry.value);
        await atomicWrite(file, bytes);
      }
    }
    await writeLock.run(() async {
      final file = await safeFile(root, path);
      if (canApplyRemote?.call() == false || await fileDigest(file) != local) {
        remoteChangesDeferred = true;
        return;
      }
      if (await file.exists()) {
        final backup = await safeFile(
          root,
          '.trash/capture/${DateTime.now().microsecondsSinceEpoch}/$path',
          internal: true,
        );
        await backup.parent.create(recursive: true);
        await file.copy(backup.path);
      }
      if (document != null) {
        await atomicWrite(file, document);
      } else if (await file.exists()) {
        await file.delete();
      }
      await _ack(path, digest);
    });
  }

  Future<void> _ack(String path, String? digest) async {
    final base = _base;
    if (base.containsKey(path) && base[path] == digest) return;
    base[path] = digest;
    _state['entries'] = base;
    await _save();
  }

  Future<File> _snapshot(Map<String, dynamic> operation) => safeFile(
    root,
    '.capture/operations/${operation['operation_id']}.md',
    internal: true,
  );
  Future<void> _discardOperation(String path) async {
    final operations = _operations;
    final operation = operations.remove(path);
    _state['operations'] = operations;
    await _save();
    if (operation != null) {
      final file = await _snapshot(Map<String, dynamic>.from(operation as Map));
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _save() async => atomicWrite(
    await safeFile(root, '.capture/state.json', internal: true),
    utf8.encode(jsonEncode(_state)),
  );

  static Map<String, String> assetEntries(
    String documentPath,
    String contents,
  ) {
    final scrap = codec.decode(contents);
    final entries = <String, String>{};
    for (final asset in scrap.assets) {
      final path = p.posix.normalize(
        p.posix.join(p.posix.dirname(documentPath), asset.relativePath),
      );
      validateSyncPath(path);
      if (!path.startsWith('assets/')) {
        throw const FormatException('Scrap 첨부 경로가 올바르지 않습니다.');
      }
      if (entries[path] != null && entries[path] != asset.hash) {
        throw const FormatException('첨부 파일 정보가 중복되었습니다.');
      }
      entries[path] = asset.hash;
    }
    return entries;
  }

  static Future<File> safeFile(
    Directory root,
    String name, {
    bool internal = false,
  }) async {
    if (internal) {
      if (p.posix.isAbsolute(name) ||
          name
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..')) {
        throw const FormatException('Unsafe capture path.');
      }
    } else {
      validateSyncPath(name);
    }
    var current = root.path;
    for (final part in ['', ...name.split('/')]) {
      current = p.join(current, part);
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException('Symlinks are not synchronized.');
      }
    }
    return File(current);
  }

  static Future<Uint8List> checkedBytes(File file) async {
    if (await file.length() > maxBytes) {
      throw const FileSystemException('첨부 파일은 25 MB 이하로 저장해 주세요.');
    }
    return file.readAsBytes();
  }

  static void verify(List<int> bytes, String digest) {
    if (bytes.length > maxBytes || sha256.convert(bytes).toString() != digest) {
      throw const FormatException('파일 무결성 검증에 실패했습니다. 다시 시도해 주세요.');
    }
  }

  static Future<String?> fileDigest(File file) async => await file.exists()
      ? (await sha256.bind(file.openRead()).first).toString()
      : null;
  static Future<void> atomicWrite(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.${const Uuid().v4()}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  static String _message(Object error) => switch (error) {
    SyncAuthException(:final message) => message,
    FormatException(:final message) => message,
    FileSystemException(:final message) => message,
    _ => '연결하지 못했습니다. 기기에 저장됨 · 다시 시도해 주세요.',
  };
}
