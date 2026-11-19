import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrapnote/infrastructure/sync/api_sync_remote.dart';
import 'package:scrapnote/infrastructure/sync/sync_client.dart';

class MemorySessionStore implements SyncSessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

Map<String, dynamic> session({String id = 'owner'}) => {
  'access_token': 'test-access',
  'expires_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
  'user': {
    'id': id,
    'email': 'owner@example.com',
    'created_at': '2026-09-15T00:00:00Z',
  },
};
void main() {
  test(
    'restores secure session offline and routes typed blobs with authentication',
    () async {
      final store = MemorySessionStore()..value = jsonEncode(session());
      final requests = <http.Request>[];
      final client = SyncClient(
        'https://sync.example.com',
        sessionStore: store,
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.headers['Authorization'], 'Bearer test-access');
          expect(request.followRedirects, isFalse);
          if (request.url.path == '/v1/manifest') {
            if (request.method == 'GET') {
              return http.Response('{"revision":3,"entries":{}}', 200);
            }
            expect(jsonDecode(request.body), {
              'expected_revision': 3,
              'entries': <String, String>{},
            });
            return http.Response('{"revision":4}', 200);
          }
          if (request.method == 'PUT') {
            expect(
              request.url.queryParameters['path'],
              'assets/sha256/ab/photo.png',
            );
            expect(request.bodyBytes, [1, 2, 3]);
            return http.Response('', 204);
          }
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      addTearDown(client.dispose);
      await client.auth.restore();
      expect(requests, isEmpty);
      final remote = ApiSyncRemote(client);
      expect(remote.identity, 'https://sync.example.com/owner');
      expect((await remote.readManifest()).revision, 3);
      await remote.upload(
        'a' * 64,
        Uint8List.fromList([1, 2, 3]),
        path: 'assets/sha256/ab/photo.png',
      );
      expect(await remote.download('a' * 64), [1, 2, 3]);
      await remote.commit(3, {});
      expect(requests, hasLength(4));
    },
  );

  test('expired or revoked session clears saved credentials', () async {
    final store = MemorySessionStore()..value = jsonEncode(session());
    final client = SyncClient(
      'https://sync.example.com',
      sessionStore: store,
      httpClient: MockClient(
        (_) async => http.Response('{"code":"unauthorized"}', 401),
      ),
    );
    addTearDown(client.dispose);
    await client.auth.restore();
    await expectLater(
      ApiSyncRemote(client).readManifest(),
      throwsA(isA<SyncAuthException>()),
    );
    expect(client.auth.currentUser, isNull);
    expect(store.value, isNull);
    store.value = jsonEncode({
      ...session(),
      'expires_at': '2000-01-01T00:00:00Z',
    });
    await client.auth.restore();
    expect(client.auth.currentUser, isNull);
    expect(store.value, isNull);
  });

  test('a captured remote cannot be reused after switching accounts', () async {
    final store = MemorySessionStore()..value = jsonEncode(session());
    var calls = 0;
    final client = SyncClient(
      'https://sync.example.com',
      sessionStore: store,
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    await client.auth.restore();
    final remote = ApiSyncRemote(client);
    store.value = jsonEncode(session(id: 'another-owner'));
    await client.auth.restore();
    await expectLater(remote.readManifest(), throwsA(isA<SyncAuthException>()));
    expect(calls, 0);
  });

  test('stale revisions leave the session intact and report retry', () async {
    final store = MemorySessionStore()..value = jsonEncode(session());
    final client = SyncClient(
      'https://sync.example.com',
      sessionStore: store,
      httpClient: MockClient(
        (_) async => http.Response('{"code":"revision_conflict"}', 409),
      ),
    );
    addTearDown(client.dispose);
    await client.auth.restore();
    await expectLater(
      ApiSyncRemote(client).commit(0, {}),
      throwsFormatException,
    );
    expect(client.auth.currentUser?.id, 'owner');
  });

  test('rejects insecure URLs and corrupt local sessions', () async {
    expect(() => SyncClient('http://sync.example.com'), throwsFormatException);
    expect(
      () => SyncClient('https://token@sync.example.com'),
      throwsFormatException,
    );
    final store = MemorySessionStore()..value = '{broken';
    final client = SyncClient('https://sync.example.com', sessionStore: store);
    addTearDown(client.dispose);
    await client.auth.restore();
    expect(store.value, isNull);
  });
}
