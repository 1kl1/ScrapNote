import 'dart:typed_data';

import 'api_sync_remote.dart';
import 'sync_client.dart';

abstract interface class CaptureRemote {
  String get identity;
  Future<Map<String, String?>> status(List<String> paths);
  Future<void> upload(String path, String digest, Uint8List bytes);
  Future<Uint8List> download(String digest);
  Future<void> commit(Map<String, dynamic> operation);
}

class ApiCaptureRemote implements CaptureRemote {
  ApiCaptureRemote(this.client) : blobs = ApiSyncRemote(client);
  final SyncClient client;
  final ApiSyncRemote blobs;
  @override
  String get identity => blobs.identity;

  void _checkUser() {
    if (client.auth.currentUser?.id != blobs.userId) {
      throw const SyncAuthException('다시 로그인해 주세요.');
    }
  }

  @override
  Future<Map<String, String?>> status(List<String> paths) async {
    _checkUser();
    final result = await client.json(
      'POST',
      '/v1/capture/status',
      body: {'paths': paths},
      timeout: const Duration(seconds: 20),
    );
    return Map<String, String?>.from(result['entries'] as Map);
  }

  @override
  Future<void> upload(String path, String digest, Uint8List bytes) =>
      blobs.upload(digest, bytes, path: path);
  @override
  Future<Uint8List> download(String digest) => blobs.download(digest);
  @override
  Future<void> commit(Map<String, dynamic> operation) async {
    _checkUser();
    final result = await client.json(
      'POST',
      '/v1/capture',
      body: operation,
      timeout: const Duration(seconds: 30),
    );
    if (!result.containsKey('digest') ||
        result['digest'] != operation['digest']) {
      throw const FormatException('서버 저장 결과를 확인하지 못했습니다. 다시 시도해 주세요.');
    }
  }
}
