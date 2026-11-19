import 'dart:typed_data';
import 'sync_client.dart';
import 'sync_manifest.dart';
import 'vault_sync_engine.dart';

class ApiSyncRemote implements SyncRemote {
  ApiSyncRemote(this.client) : userId = client.auth.currentUser!.id;
  final SyncClient client;
  final String userId;
  @override
  String get identity => '${client.serverUrl}/$userId';
  void _checkUser() {
    if (client.auth.currentUser?.id != userId) {
      throw const SyncAuthException('다시 로그인해 주세요.');
    }
  }

  @override
  Future<SyncManifest> readManifest() async {
    _checkUser();
    final row = await client.json('GET', '/v1/manifest');
    return SyncManifest(
      row['revision'] as int,
      Map<String, String>.from(row['entries'] as Map),
    );
  }

  @override
  Future<void> upload(
    String digest,
    Uint8List bytes, {
    required String path,
  }) async {
    _checkUser();
    await client.request(
      'PUT',
      '/v1/blobs/$digest',
      bytes: bytes,
      query: {'path': path},
    );
  }

  @override
  Future<Uint8List> download(String digest) {
    _checkUser();
    return client.request('GET', '/v1/blobs/$digest');
  }

  @override
  Future<void> commit(int expectedRevision, Map<String, String> entries) async {
    _checkUser();
    await client.json(
      'PUT',
      '/v1/manifest',
      body: {'expected_revision': expectedRevision, 'entries': entries},
    );
  }
}
