import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrapnote/app/scrapnote_app.dart';
import 'package:scrapnote/app/scrapnote_shell.dart';
import 'package:scrapnote/features/editor/editor_session_controller.dart';
import 'package:scrapnote/features/expenses/expense_controller.dart';
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/features/scraps/scrap_controller.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_store.dart';
import 'package:scrapnote/infrastructure/sync/sync_client.dart';

class UnusedNotes extends NoteController {
  @override
  Future<void> connect(String path) async => fail('Mobile must not load notes');
  @override
  Future<void> reloadAfterSync() async => fail('Mobile must not reload notes');
}

class UnusedExpenses extends ExpenseController {
  @override
  Future<void> connect(String path) async =>
      fail('Mobile must not load expenses');
  @override
  Future<void> reloadAfterSync() async =>
      fail('Mobile must not reload expenses');
}

void main() {
  const capture = bool.fromEnvironment('CAPTURE_MOBILE');
  setUpAll(() async {
    if (!capture) return;
    final icons = FontLoader('packages/forui_assets/ForuiLucideIcons')
      ..addFont(rootBundle.load('packages/forui_assets/assets/lucide.ttf'));
    await icons.load();
    for (final family in ['.AppleSystemUIFont', 'Roboto', 'monospace']) {
      final font = FontLoader(family)
        ..addFont(
          File(
            '/System/Library/Fonts/AppleSDGothicNeo.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await font.load();
    }
  });
  Future<void> settle(WidgetTester tester) async {
    for (var tick = 0; tick < 30; tick++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await tester.pump();
  }

  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets(
      'capture at $width keeps only scraps, fits keyboard and confirms deletion',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        late Directory root;
        late ScrapController controller;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp('mobile-capture-ui-');
          controller = ScrapController(
            directoryPicker: () async => '${root.path}/vault',
            directoryRestorer: () async => null,
            supportDirectoryProvider: () async => root,
            locationProvider: () async => null,
          );
          await controller.chooseVault();
        });
        final notes = UnusedNotes();
        final expenses = UnusedExpenses();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ScrapnoteApp(
              captureOnly: true,
              controller: controller,
              noteController: notes,
              expenseController: expenses,
              initializeController: false,
              installWindowCloseGuard: false,
              recoveryStore: EditorRecoveryStore(
                pathProvider: () async => '${root.path}/recovery.json',
              ),
            ),
          ),
        );
        await settle(tester);
        for (final key in [
          ScrapnoteShell.notesNavigationKey,
          ScrapnoteShell.expensesNavigationKey,
          ScrapnoteShell.timelineNavigationKey,
          ScrapnoteShell.activityRailKey,
        ]) {
          expect(find.byKey(key), findsNothing);
        }
        expect(find.byKey(const ValueKey('bottom-navigation')), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('scrap-editor')),
          '퇴근길에 떠오른 생각\n\n휴대폰에서 짧게 모으고 PC에서 이어 씁니다.',
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('workspace-save')));
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await settle(tester);
        expect(
          controller.scraps,
          hasLength(1),
          reason:
              'error=${controller.errorMessage}, saving=${controller.saving}, status=${find.textContaining("저장").evaluate().map((e) => e.widget).toList()}',
        );
        expect(find.text('전송 대기'), findsWidgets);
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        if (capture) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('docs/screenshots').create(recursive: true);
            await File(
              'docs/screenshots/capture-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        if (width < 700) {
          await tester.tap(find.byKey(const ValueKey('workspace-list-toggle')));
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(ValueKey('delete-capture-${controller.scraps.single.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Scrap을 삭제할까요?'), findsOneWidget);
        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
        expect(controller.scraps, hasLength(1));
        await tester.tap(
          find.byKey(ValueKey('delete-capture-${controller.scraps.single.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('삭제'));
        await settle(tester);
        expect(controller.scraps, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        controller.dispose();
        notes.dispose();
        expenses.dispose();
        await tester.runAsync(() => root.delete(recursive: true));
      },
    );
  }

  testWidgets(
    'saving automatically uploads only own scrap and editing stays available during upload',
    (tester) async {
      late Directory root;
      late ScrapController controller;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('mobile-auto-upload-');
        controller = ScrapController(
          directoryPicker: () async => '${root.path}/vault',
          supportDirectoryProvider: () async => root,
          locationProvider: () async => null,
        );
        await controller.chooseVault();
      });
      final hold = Completer<void>();
      final requests = <String>[];
      var commits = 0;
      final client = SyncClient(
        'https://capture.example',
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path == '/v1/capture/status') {
            final paths = (jsonDecode(request.body) as Map)['paths'] as List;
            return http.Response(
              jsonEncode({
                'entries': {for (final path in paths) path: null},
              }),
              200,
            );
          }
          if (request.url.path.startsWith('/v1/blobs/')) {
            return http.Response('', 204);
          }
          if (request.url.path == '/v1/capture') {
            commits++;
            await hold.future;
            return http.Response(
              jsonEncode({
                'digest': (jsonDecode(request.body) as Map)['digest'],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      client.auth.currentSession = SyncSession.fromJson({
        'access_token': 'fixture',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
        'user': {'id': 'owner', 'email': 'owner@example.com'},
      });
      final session = EditorSessionController();
      await tester.pumpWidget(
        ScrapnoteApp(
          captureOnly: true,
          controller: controller,
          syncClient: client,
          editorSessionController: session,
          initializeController: false,
          installWindowCloseGuard: false,
          recoveryStore: EditorRecoveryStore(
            pathProvider: () async => '${root.path}/recovery.json',
          ),
        ),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('scrap-editor')),
        'automatic capture',
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('workspace-save')));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      for (var tick = 0; tick < 200 && commits == 0; tick++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(
        commits,
        1,
        reason:
            'requests=$requests; saved=${controller.scraps.length}; lifecycle=${tester.binding.lifecycleState}',
      );
      expect(requests, isNot(contains('/v1/manifest')));
      await tester.enterText(
        find.byKey(const ValueKey('scrap-editor')),
        'still typing while uploading',
      );
      expect(session.activeDocument!.body, 'still typing while uploading');
      await tester.runAsync(() async {
        hold.complete();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await settle(tester);
      expect(session.activeDocument!.body, 'still typing while uploading');
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      controller.dispose();
      session.dispose();
      await client.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}
