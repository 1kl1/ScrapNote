import 'dart:convert';
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrapnote/features/sync/sync_account_page.dart';
import 'package:scrapnote/infrastructure/sync/sync_bootstrap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final user = {
    'id': 'test-user',
    'aud': 'authenticated',
    'email': 'person@example.com',
    'created_at': '2026-09-15T00:00:00Z',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
  };

  Future<SupabaseClient> mount(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'public-test-key',
      httpClient: MockClient(handler),
      isolate: _InlineJson(),
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: _MemoryStorage(),
      ),
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SyncAccountPage(
          client: client,
          onSync: (_) async => '동기화 완료',
          status: '',
        ),
      ),
    );
    await tester.pumpAndSettle();
    return client;
  }

  Future<void> press(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FButton, label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> email(WidgetTester tester) async {
    await tester.enterText(
      find.byType(EditableText).first,
      'person@example.com',
    );
  }

  test('only the registered callback location is accepted', () {
    expect(
      SyncBootstrap.isAuthCallback(
        Uri.parse('${SyncBootstrap.authRedirectUrl}?code=test'),
      ),
      isTrue,
    );
    for (final url in [
      'https://auth-callback/?code=test',
      'com.scrapnote.app://other?code=test',
      'com.scrapnote.app://auth-callback/other?code=test',
      'com.scrapnote.app://user@auth-callback?code=test',
      'com.scrapnote.app://auth-callback:99?code=test',
    ]) {
      expect(SyncBootstrap.isAuthCallback(Uri.parse(url)), isFalse);
    }
  });

  testWidgets('signup uses app callback and shows confirmation guidance', (
    tester,
  ) async {
    await mount(tester, (request) async {
      expect(request.url.path, '/auth/v1/signup');
      expect(
        request.url.queryParameters['redirect_to'],
        SyncBootstrap.authRedirectUrl,
      );
      return http.Response(jsonEncode(user), 200);
    });
    await email(tester);
    await tester.enterText(find.byType(EditableText).last, 'fixture-password');
    await press(tester, '계정 만들기');
    expect(find.textContaining('가장 최근 인증 메일의 링크를 이 기기에서'), findsOneWidget);
    expect(find.text('60초 후 재발송'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .controller
          .text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'resend validates email and prevents repeated sends during cooldown',
    (tester) async {
      var requests = 0;
      await mount(tester, (request) async {
        requests++;
        expect(request.url.path, '/auth/v1/resend');
        expect(
          request.url.queryParameters['redirect_to'],
          SyncBootstrap.authRedirectUrl,
        );
        expect(jsonDecode(request.body)['type'], 'signup');
        expect(jsonDecode(request.body)['email'], 'person@example.com');
        return http.Response('{}', 200);
      });
      await press(tester, '인증 메일 다시 받기');
      expect(requests, 0);
      expect(find.text('가입한 이메일 주소를 입력해 주세요.'), findsOneWidget);
      await email(tester);
      await press(tester, '인증 메일 다시 받기');
      expect(requests, 1);
      expect(
        tester
            .widget<FButton>(find.widgetWithText(FButton, '60초 후 재발송'))
            .onPress,
        isNull,
      );
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(find.text('인증 메일 다시 받기'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unconfirmed login explains resend and keeps the form usable', (
    tester,
  ) async {
    await mount(
      tester,
      (_) async => http.Response(
        jsonEncode({
          'error_code': 'email_not_confirmed',
          'msg': 'Email not confirmed',
        }),
        400,
      ),
    );
    await email(tester);
    await press(tester, '로그인');
    expect(
      find.text('이메일 인증이 필요합니다. 아래에서 인증 메일을 다시 받을 수 있습니다.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FButton>(find.widgetWithText(FButton, '인증 메일 다시 받기'))
          .onPress,
      isNotNull,
    );
  });

  testWidgets('external auth completion updates the open account page', (
    tester,
  ) async {
    final client = await mount(
      tester,
      (_) async => http.Response(
        jsonEncode({
          'access_token': 'fixture-access',
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': user,
        }),
        200,
      ),
    );
    // A deep-link exchange also emits signedIn through this same SDK stream.
    await tester.runAsync(
      () => client.auth.signInWithPassword(
        email: 'person@example.com',
        password: 'fixture',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('저장하고 동기화'), findsOneWidget);
    expect(find.text('인증 메일 다시 받기'), findsNothing);
  });
}

class _MemoryStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

// Avoid real isolate scheduling in widget tests; HTTP responses stay deterministic.
class _InlineJson extends YAJsonIsolate {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<dynamic> decode(String value) async => jsonDecode(value);
  @override
  Future<String> encode(Object? value) async => jsonEncode(value);
}
