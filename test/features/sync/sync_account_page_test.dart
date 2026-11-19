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
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      button,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(button);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
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
  testWidgets('resets forgotten password before login and then signs in', (
    tester,
  ) async {
    var requests = 0;
    var resets = 0;
    final client = await mount(tester, (request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.headers['Authorization'], isNull);
      expect(body['email'], 'person@example.com');
      if (request.url.path == '/v1/auth/password/reset/request') {
        requests++;
        return http.Response('{"ok":true}', 200);
      }
      if (request.url.path == '/v1/auth/login') {
        expect(body['password'], 'a new long password');
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
      expect(request.url.path, '/v1/auth/password/reset');
      expect(body['code'], 'a' * 32);
      expect(body['new_password'], 'a new long password');
      expect(body.containsKey('current_password'), isFalse);
      resets++;
      return resets == 1
          ? http.Response('{"code":"invalid_reset_code"}', 400)
          : http.Response('{"ok":true}', 200);
    });
    await press(tester, '비밀번호 재설정');
    expect(find.text('현재 비밀번호'), findsNothing);
    await press(tester, '재설정 코드 받기');
    expect(requests, 0);
    await email(tester);
    await press(tester, '재설정 코드 받기');
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(client.auth.currentUser, isNull);

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

    await press(tester, '새 비밀번호 저장');
    expect(resets, 0);
    await fill('reset-code', 'a' * 32, delta: -120);
    await fill('new-password', 'short');
    await fill('confirm-password', 'short');
    await press(tester, '새 비밀번호 저장');
    expect(resets, 0);
    await fill('new-password', 'a new long password', delta: -120);
    await fill('confirm-password', 'mismatch');
    await press(tester, '새 비밀번호 저장');
    expect(resets, 0);
    await fill('confirm-password', 'a new long password', delta: -120);
    await press(tester, '새 비밀번호 저장');
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(client.auth.currentUser, isNull);
    await tester.scrollUntilVisible(
      find.text('재설정 코드가 올바르지 않거나 만료되었습니다. 코드를 다시 받아 주세요.'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await press(tester, '코드 다시 받기');
    await tester.pumpAndSettle();
    expect(requests, 2);
    await fill('reset-code', 'a' * 32, delta: -120);
    await press(tester, '새 비밀번호 저장');
    await tester.pumpAndSettle();
    expect(resets, 2);
    expect(client.auth.currentUser, isNull);
    final loginPassword = find.byKey(const ValueKey('login-password'));
    await tester.scrollUntilVisible(
      loginPassword,
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.descendant(of: loginPassword, matching: find.byType(EditableText)),
      'a new long password',
    );
    await press(tester, '로그인');
    await tester.pumpAndSettle();
    expect(client.auth.currentUser, isNotNull);
    expect(find.text('비밀번호 재설정'), findsNothing);
  });

  testWidgets('returning to login clears reset and login passwords', (
    tester,
  ) async {
    await mount(tester, (_) async => http.Response('{"ok":true}', 200));
    await email(tester);
    await tester.enterText(find.byType(EditableText).last, 'stale password');
    await press(tester, '비밀번호 재설정');
    await press(tester, '재설정 코드 받기');
    await tester.pumpAndSettle();
    final code = find.byKey(const ValueKey('reset-code'));
    await tester.enterText(
      find.descendant(of: code, matching: find.byType(EditableText)),
      'private code',
    );
    await press(tester, '로그인으로 돌아가기');
    await tester.pumpAndSettle();
    final password = tester.widget<EditableText>(
      find.byType(EditableText).last,
    );
    expect(password.controller.text, isEmpty);
    await press(tester, '비밀번호 재설정');
    expect(find.byKey(const ValueKey('reset-code')), findsNothing);
    expect(find.text('재설정 코드 받기'), findsOneWidget);
  });

  testWidgets('missing mail configuration reports an actionable error', (
    tester,
  ) async {
    await mount(
      tester,
      (_) async => http.Response('{"code":"mail_unavailable"}', 503),
    );
    await email(tester);
    await press(tester, '비밀번호 재설정');
    await press(tester, '재설정 코드 받기');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reset-code')), findsNothing);
    expect(
      find.text('재설정 메일을 보낼 수 없습니다. 서버 관리자의 메일 발송 설정이 필요합니다.'),
      findsOneWidget,
    );
  });
}
