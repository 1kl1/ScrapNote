import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrapnote/infrastructure/sync/capture_remote.dart';
import 'package:scrapnote/infrastructure/sync/sync_client.dart';

void main() {
  SyncSession session(String id) => SyncSession.fromJson({
    'access_token': 'fixture',
    'expires_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
    'user': {'id': id, 'email': '$id@example.com'},
  });
  test(
    'scoped API uses authenticated own-path requests and validates commit acknowledgement',
    () async {
      var invalidResult = false;
      final calls = <String>[];
      final client = SyncClient(
        'https://capture.example',
        httpClient: MockClient((request) async {
          calls.add(request.url.path);
          expect(request.headers['authorization'], 'Bearer fixture');
          if (request.url.path.endsWith('/status')) {
            expect(jsonDecode(request.body), {
              'paths': ['scraps/a.md'],
            });
            return http.Response(
              jsonEncode({
                'entries': {'scraps/a.md': null},
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode(invalidResult ? {} : {'digest': null}),
            200,
          );
        }),
      );
      addTearDown(client.dispose);
      client.auth.currentSession = session('owner');
      final remote = ApiCaptureRemote(client);
      expect(await remote.status(['scraps/a.md']), {'scraps/a.md': null});
      await remote.commit({'digest': null});
      invalidResult = true;
      await expectLater(remote.commit({'digest': null}), throwsFormatException);
      client.auth.currentSession = session('other');
      await expectLater(
        remote.status(['scraps/a.md']),
        throwsA(isA<SyncAuthException>()),
      );
      expect(calls, isNot(contains('/v1/manifest')));
    },
  );
  test(
    'old server and concurrent edits have distinct actionable errors',
    () async {
      var conflict = false;
      final client = SyncClient(
        'https://capture.example',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({'code': conflict ? 'capture_conflict' : 'not_found'}),
            conflict ? 409 : 404,
          ),
        ),
      );
      addTearDown(client.dispose);
      client.auth.currentSession = session('owner');
      final remote = ApiCaptureRemote(client);
      await expectLater(
        remote.status(['scraps/a.md']),
        throwsA(
          isA<SyncAuthException>().having(
            (error) => error.code,
            'code',
            'capture_unavailable',
          ),
        ),
      );
      conflict = true;
      await expectLater(
        remote.commit({}),
        throwsA(
          isA<SyncAuthException>().having(
            (error) => error.code,
            'code',
            'capture_conflict',
          ),
        ),
      );
      expect(client.auth.currentUser?.id, 'owner');
    },
  );
}
