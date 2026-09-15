import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_manifest.dart';
import 'vault_sync_engine.dart';

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this.client, this.serverUrl)
    : userId = client.auth.currentUser!.id;
  final SupabaseClient client;
  final String serverUrl;
  final String userId;
  @override
  String get identity => '$serverUrl/$userId';
  void _checkUser() {
    if (client.auth.currentUser?.id != userId) {
      throw const AuthException('다시 로그인해 주세요.');
    }
  }

  @override
  Future<SyncManifest> readManifest() async {
    _checkUser();
    final row = await client
        .from('vault_manifests')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null
        ? SyncManifest(0, {})
        : SyncManifest(
            row['revision'] as int,
            Map<String, String>.from(row['entries'] as Map),
          );
  }

  @override
  Future<void> upload(String digest, Uint8List bytes) async {
    _checkUser();
    try {
      await client.storage
          .from('vault-blobs')
          .uploadBinary(
            '$userId/$digest',
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/octet-stream',
            ),
          );
    } on StorageException catch (error) {
      if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
    }
  }

  @override
  Future<Uint8List> download(String digest) {
    _checkUser();
    return client.storage.from('vault-blobs').download('$userId/$digest');
  }

  @override
  Future<void> commit(int expectedRevision, Map<String, String> entries) async {
    _checkUser();
    await client.rpc(
      'commit_vault_manifest',
      params: {'expected_revision': expectedRevision, 'new_entries': entries},
    );
  }
}
