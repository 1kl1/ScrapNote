import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrapnote/features/sync/sync_account_page.dart';
import 'package:scrapnote/infrastructure/sync/sync_vault_summary.dart';
import 'package:scrapnote/infrastructure/sync/sync_client.dart';

void main() {
  final user = {
    'id': 'test-user',
    'aud': 'authenticated',
    'email': 'person@example.com',
    'created_at': '2026-09-15T00:00:00Z',
    'last_sign_in_at': '2026-09-15T18:00:00Z',
    'app_metadata': <String, dynamic>{'provider': 'email'},
    'user_metadata': <String, dynamic>{},
  };

  Future<SyncClient> mount(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    String? vaultPath,
    SyncVaultSummary summary = SyncVaultSummary.empty,
  }) async {
    final client = SyncClient(
      'https://sync.example.com',
      httpClient: MockClient(handler),
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SyncAccountPage(
          client: client,
          onSync: (_) async => '동기화 완료',
          status: '',
          vaultPath: vaultPath ?? '/memory/test-vault',
          summaryLoader: (_) async => summary,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return client;
  }

  Future<void> press(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FButton, label);
    await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> email(WidgetTester tester) async {
    await tester.enterText(
      find.byType(EditableText).first,
      'person@example.com',
    );
  }

  testWidgets('private server login has no signup or confirmation mail', (
    tester,
  ) async {
    await mount(tester, (_) async => http.Response('{}', 500));
    expect(find.text('계정 만들기'), findsNothing);
    expect(find.text('인증 메일 다시 받기'), findsNothing);
    expect(find.text('개인 서버에 등록된 계정으로 로그인하세요.'), findsOneWidget);
  });

  testWidgets('login validates email and reports invalid credentials', (
    tester,
  ) async {
    var requests = 0;
    await mount(tester, (request) async {
      requests++;
      expect(request.url.path, '/v1/auth/login');
      return http.Response(jsonEncode({'code': 'invalid_credentials'}), 401);
    });
    await press(tester, '로그인');
    expect(requests, 0);
    await email(tester);
    await tester.enterText(find.byType(EditableText).last, 'wrong');
    await press(tester, '로그인');
    expect(requests, 1);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('이메일 또는 비밀번호가 맞지 않습니다.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('이메일 또는 비밀번호가 맞지 않습니다.'), findsOneWidget);
  });

  testWidgets('successful login updates the open account page', (tester) async {
    final client = await mount(
      tester,
      (_) async => http.Response(
        jsonEncode({
          'access_token': 'fixture-access',
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'expires_at': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
          'user': user,
        }),
        200,
      ),
    );
    // Login emits a state change to the open account page.
    await tester.runAsync(
      () => client.auth.signInWithPassword(
        email: 'person@example.com',
        password: 'fixture',
      ),
    );
    expect(client.auth.currentUser, isNotNull);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('저장하고 동기화'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('저장하고 동기화'), findsOneWidget);
    expect(find.text('인증 메일 다시 받기'), findsNothing);
  });

  testWidgets('signed-in view shows session and real Vault statistics', (
    tester,
  ) async {
    final vault = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('sync-dashboard-'),
    ))!;
    addTearDown(() => vault.delete(recursive: true));
    Future<void> write(String relative, String value) async {
      final file = File('${vault.path}/$relative');
      await file.parent.create(recursive: true);
      await file.writeAsString(value);
    }

    final summary = (await tester.runAsync(() async {
      await write('scraps/a.md', 'scrap');
      await write('notes/n.md', 'note');
      await write('assets/sha256/ab/hash.png', 'image');
      await write(
        '.sync/state.json',
        jsonEncode({
          'identity': 'server/test-user',
          'entries': {
            'scraps/a.md': List.filled(64, 'a').join(),
            'notes/n.md': List.filled(64, 'b').join(),
          },
          'synced_at': '2026-09-15T18:20:00Z',
        }),
      );
      return SyncVaultSummary.load(vault);
    }))!;
    final client = await mount(
      tester,
      (_) async => http.Response(
        jsonEncode({
          'access_token': 'fixture-access',
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'expires_at': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
          'user': user,
        }),
        200,
      ),
      vaultPath: vault.path,
      summary: summary,
    );

    await tester.runAsync(
      () => client.auth.signInWithPassword(
        email: 'person@example.com',
        password: 'fixture',
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('로그인 세션'), findsOneWidget);
    expect(find.text('person@example.com'), findsOneWidget);
    expect(find.text('이 Vault의 동기화 범위'), findsOneWidget);
    expect(find.text('Scrap'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('3개 파일 ·'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('3개 파일 ·'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('2개 파일'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('2개 파일'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('이 기기에서 로그아웃'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('이 기기에서 로그아웃'), findsOneWidget);
  });
  testWidgets('changes password after validation and reports server errors', (
    tester,
  ) async {
    var changes = 0;
    final client = await mount(tester, (request) async {
      if (request.url.path == '/v1/auth/login') {
        return http.Response(
          jsonEncode({
            'access_token': 'fixture-access',
            'expires_at': DateTime.now()
                .add(const Duration(days: 1))
                .toIso8601String(),
            'user': user,
          }),
          200,
        );
      }
      expect(request.url.path, '/v1/auth/password');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['current_password'], 'old password');
      expect(body['new_password'], 'a new long password');
      changes++;
      return changes == 1
          ? http.Response(jsonEncode({'code': 'incorrect_password'}), 400)
          : http.Response('{"ok":true}', 200);
    });
    await tester.runAsync(
      () => client.auth.signInWithPassword(
        email: 'person@example.com',
        password: 'fixture',
      ),
    );
    await tester.pumpAndSettle();
    await press(tester, '비밀번호 변경');
    Future<void> fill(String key, String value, {double delta = 120}) async {
      final field = find.byKey(ValueKey(key));
      await tester.scrollUntilVisible(
        field,
        delta,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(EditableText)),
        value,
      );
    }

    await fill('current-password', 'old password');
    await fill('new-password', 'a new long password');
    await fill('confirm-password', 'mismatch');
    await press(tester, '변경 저장');
    expect(changes, 0);
    await fill('confirm-password', 'a new long password', delta: -120);
    await press(tester, '변경 저장');
    expect(changes, 1);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(client.auth.currentUser, isNotNull);
    await press(tester, '변경 저장');
    expect(changes, 2);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(find.text('비밀번호 변경'), findsOneWidget);
  });
}
