import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_snapshot.dart';

typedef RecoveryPathProvider = Future<String> Function();

/// Injectable I/O boundary used by [EditorRecoveryStore].
abstract interface class RecoveryFileIo {
  Future<bool> exists(String filePath);
  Future<String> read(String filePath);
  Future<void> writeAtomically(String filePath, String contents);
  Future<void> delete(String filePath);
}

class LocalRecoveryFileIo implements RecoveryFileIo {
  const LocalRecoveryFileIo();

  @override
  Future<bool> exists(String filePath) => File(filePath).exists();

  @override
  Future<String> read(String filePath) => File(filePath).readAsString();

  @override
  Future<void> writeAtomically(String filePath, String contents) async {
    final target = File(filePath);
    await target.parent.create(recursive: true);
    final temporary = File(
      '$filePath.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  Future<void> delete(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Persists crash-recovery state outside the user-selected Vault.
class EditorRecoveryStore {
  EditorRecoveryStore({RecoveryPathProvider? pathProvider, RecoveryFileIo? io})
    : _pathProvider = pathProvider ?? _defaultRecoveryPath,
      _io = io ?? const LocalRecoveryFileIo();

  final RecoveryPathProvider _pathProvider;
  final RecoveryFileIo _io;

  Future<EditorRecoverySnapshot?> load() async {
    final filePath = await _pathProvider();
    if (!await _io.exists(filePath)) {
      return null;
    }
    final decoded = jsonDecode(await _io.read(filePath));
    return EditorRecoverySnapshot.fromJson(decoded);
  }

  /// Saves dirty state, or removes recovery data when the snapshot is empty.
  Future<void> save(EditorRecoverySnapshot snapshot) async {
    if (snapshot.isEmpty) {
      await clear();
      return;
    }
    final filePath = await _pathProvider();
    await _io.writeAtomically(filePath, jsonEncode(snapshot.toJson()));
  }

  Future<void> clear() async {
    await _io.delete(await _pathProvider());
  }

  Future<List<Map<String, dynamic>>> loadNotes(String vaultPath) async {
    final filePath = await _notesPath(vaultPath);
    if (!await _io.exists(filePath)) return [];
    final data = jsonDecode(await _io.read(filePath));
    if (data is! List) {
      throw const FormatException('Invalid note recovery data.');
    }
    return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> saveNotes(
    String vaultPath,
    List<Map<String, Object?>> documents,
  ) async {
    final filePath = await _notesPath(vaultPath);
    if (documents.isEmpty) {
      await _io.delete(filePath);
    } else {
      await _io.writeAtomically(filePath, jsonEncode(documents));
    }
  }

  Future<String> _notesPath(String vaultPath) async =>
      '${await _pathProvider()}.${sha256.convert(utf8.encode(vaultPath))}.notes.json';

  static Future<String> _defaultRecoveryPath() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'editor-recovery.json');
  }
}
