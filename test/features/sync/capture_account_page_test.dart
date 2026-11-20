import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrapnote/features/sync/sync_account_page.dart';
import 'package:scrapnote/infrastructure/sync/sync_client.dart';
import 'package:scrapnote/infrastructure/sync/sync_manifest.dart';

void main() {
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var tick = 0; tick < 100 && !done(); tick++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pump();
  }

  testWidgets(
    'mobile login automatically sends the saved outbox and shows device history',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('capture-account-'),
      ))!;
      final client = SyncClient(
        'https://capture.example',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'access_token': 'fixture',
              'expires_at': DateTime.now()
                  .add(const Duration(days: 1))
                  .toIso8601String(),
              'user': {'id': 'owner', 'email': 'owner@example.com'},
            }),
            200,
          ),
        ),
      );
      var uploads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SyncAccountPage(
            captureOnly: true,
            client: client,
            vaultPath: root.path,
            status: '기기에 저장됨',
            summaryLoader: (_) async =>
                throw StateError('Mobile must not load full-vault summary'),
            onSync: (_) async =>
                throw StateError('Login must not request saving drafts'),
            onSignedIn: () async {
              uploads++;
              return '업로드 확인 완료';
            },
          ),
        ),
      );
      await until(tester, () => find.text('로그인').evaluate().isNotEmpty);
      await tester.enterText(
        find.byType(EditableText).first,
        'owner@example.com',
      );
      await tester.enterText(
        find.byType(EditableText).last,
        'fixture password',
      );
      await tester.ensureVisible(find.text('로그인'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('로그인'));
      await until(
        tester,
        () => uploads == 1 && find.text('업로드 확인 완료').evaluate().isNotEmpty,
      );
      expect(uploads, 1);
      expect(find.text('이 휴대폰의 작성·전송 내역'), findsOneWidget);
      expect(find.text('이 Vault의 동기화 범위'), findsNothing);
      expect(find.text('아직 이 휴대폰에서 저장한 Scrap이 없습니다.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 250));
      await client.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
  testWidgets(
    'mobile edit/delete conflict offers both versions and requires explicit selection',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('capture-conflict-ui-'),
      ))!;
      final client = SyncClient(
        'https://capture.example',
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
      client.auth.currentSession = SyncSession.fromJson({
        'access_token': 'fixture',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
        'user': {'id': 'owner', 'email': 'owner@example.com'},
      });
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SyncAccountPage(
            captureOnly: true,
            client: client,
            vaultPath: root.path,
            status: '충돌 확인',
            onSync: (resolutions) async {
              calls++;
              if (resolutions.isEmpty) {
                throw const SyncConflicts([
                  SyncConflict(
                    'scraps/deleted.md',
                    null,
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  ),
                ]);
              }
              expect(resolutions['scraps/deleted.md']!.useLocal, isTrue);
              return '삭제 반영 완료';
            },
          ),
        ),
      );
      await until(
        tester,
        () => find.text('아직 이 휴대폰에서 저장한 Scrap이 없습니다.').evaluate().isNotEmpty,
      );
      await tester.ensureVisible(find.text('저장하고 업로드'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장하고 업로드'));
      await until(
        tester,
        () =>
            calls == 1 &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      // A remote preview may be unavailable; the explicit deletion choice remains.
      final localChoice = find.text('이 기기에서 삭제됨');
      await tester.scrollUntilVisible(localChoice, 160);
      await until(tester, () {
        final buttons = find.ancestor(
          of: localChoice,
          matching: find.byType(FButton),
        );
        return buttons.evaluate().isNotEmpty &&
            tester.widget<FButton>(buttons.first).onPress != null;
      });
      await Scrollable.ensureVisible(
        tester.element(localChoice),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(localChoice);
      await tester.pump();
      final sync = find.text('선택한 내용으로 동기화');
      await tester.scrollUntilVisible(sync, -160);
      await tester.pumpAndSettle();
      await tester.tap(sync);
      await until(tester, () => calls == 2);
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 250));
      await client.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}
