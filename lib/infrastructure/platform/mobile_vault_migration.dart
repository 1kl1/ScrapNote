import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../sync/capture_sync_engine.dart';
import '../sync/sync_manifest.dart';
import '../drafts/editor_recovery_snapshot.dart';

/// Keep the old mobile Supabase Vault intact while restoring the new server.
/// The desktop Vault is rebound only by the verified local migration tool.
Future<Directory> resolveMobileVaultDirectory(Directory support) async {
  final legacy = Directory(path.join(support.path, 'vault'));
  final state = File(path.join(legacy.path, '.sync', 'state.json'));
  var directory = legacy;
  if (await state.exists()) {
    try {
      final decoded = jsonDecode(await state.readAsString());
      final identity = decoded is Map ? decoded['identity'] : null;
      final host = identity is String ? Uri.tryParse(identity)?.host : null;
      if (host != null && host.endsWith('.supabase.co')) {
        directory = Directory(path.join(support.path, 'vault-oracle'));
      }
    } on FormatException {
      // A damaged old state must never make existing local documents disappear.
    }
  }
  await directory.create(recursive: true);
  return directory;
}

/// A separate capture outbox prevents downloaded desktop documents from being
/// mistaken for documents created by this phone. Keep the original vault intact.
/// Only unsent creations, edits and deletions are copied, with their baseline.
Future<Directory> resolveMobileCaptureDirectory(Directory support) async {
  final target = Directory(path.join(support.path, 'capture-v1'));
  final marker = await CaptureSyncEngine.safeFile(
    target,
    '.capture/migrated',
    internal: true,
  );
  if (await marker.exists()) return target;
  final legacy = await resolveMobileVaultDirectory(support);
  final oldStateFile = await CaptureSyncEngine.safeFile(
    legacy,
    '.sync/state.json',
    internal: true,
  );
  var oldState = <String, dynamic>{};
  var baselineValid = true;
  try {
    if (await oldStateFile.exists()) {
      final decoded = jsonDecode(await oldStateFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid legacy state.');
      }
      oldState = decoded;
      SyncManifest(
        0,
        Map<String, String>.from(oldState['entries'] as Map? ?? {}),
      );
    }
  } on FormatException {
    baselineValid = false;
    oldState = {};
  } on TypeError {
    baselineValid = false;
    oldState = {};
  }
  final baseline = Map<String, String>.from(oldState['entries'] as Map? ?? {});
  final local = await CaptureSyncEngine.scan(legacy);
  final state = await CaptureSyncEngine.readState(target);
  final importedBase = Map<String, String?>.from(
    state['entries'] as Map? ?? {},
  );
  if (!baselineValid) {
    state['migration_notice'] =
        '이전 저장소의 전송 기록을 읽지 못해 과거 파일은 원래 위치에 보존했습니다. 확인 가능한 작성 중 초안만 가져왔습니다.';
  }
  final recoveryFile = File(path.join(support.path, 'editor-recovery.json'));
  final draftIds = <String>{};
  if (await recoveryFile.exists()) {
    try {
      final recovery = EditorRecoverySnapshot.fromJson(
        jsonDecode(await recoveryFile.readAsString()),
      );
      draftIds.addAll(
        recovery.documents
            .map((document) => document.scrapId)
            .whereType<String>(),
      );
    } on FormatException {
      /* The editor reports damaged recovery data. */
    }
  }
  for (final name in {
    ...local.keys,
    ...baseline.keys.where((name) => name.startsWith('scraps/')),
  }) {
    final digest = local[name]?['digest'];
    if (!baselineValid && !draftIds.contains(local[name]?['id'])) continue;
    if (digest == baseline[name] && !draftIds.contains(local[name]?['id'])) {
      continue;
    }
    if (digest != null) {
      final source = await CaptureSyncEngine.safeFile(legacy, name);
      final destination = await CaptureSyncEngine.safeFile(target, name);
      if (!await destination.exists()) {
        final bytes = await CaptureSyncEngine.checkedBytes(source);
        CaptureSyncEngine.verify(bytes, digest);
        for (final asset in CaptureSyncEngine.assetEntries(
          name,
          utf8.decode(bytes),
        ).entries) {
          final file = await CaptureSyncEngine.safeFile(legacy, asset.key);
          if (await CaptureSyncEngine.fileDigest(file) != asset.value) {
            throw const FormatException('이전 첨부 파일 검증에 실패했습니다. 원본은 보존됩니다.');
          }
          final targetAsset = await CaptureSyncEngine.safeFile(
            target,
            asset.key,
          );
          await targetAsset.parent.create(recursive: true);
          await file.copy('${targetAsset.path}.migration.tmp');
          await File(
            '${targetAsset.path}.migration.tmp',
          ).rename(targetAsset.path);
        }
        await CaptureSyncEngine.atomicWrite(destination, bytes);
      }
    }
    if (baseline[name] != null) importedBase[name] = baseline[name];
  }
  state['entries'] = importedBase;
  if (oldState['identity'] != null) state['identity'] = oldState['identity'];
  await CaptureSyncEngine.atomicWrite(
    await CaptureSyncEngine.safeFile(
      target,
      '.capture/state.json',
      internal: true,
    ),
    utf8.encode(jsonEncode(state)),
  );
  await CaptureSyncEngine.atomicWrite(marker, utf8.encode('1'));
  return target;
}
