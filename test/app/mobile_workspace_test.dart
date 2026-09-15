import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrapnote/app/scrapnote_app.dart';
import 'package:scrapnote/app/scrapnote_shell.dart';
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/features/expenses/expense_repository.dart';
import 'package:scrapnote/features/expenses/expense_controller.dart';
import 'package:scrapnote/features/expenses/expense_record.dart';
import 'package:scrapnote/features/scraps/scrap_controller.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_MOBILE');
  if (capture) {
    setUpAll(() async {
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
  }
  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets(
      'real mobile workspaces at $width retain drafts and fit keyboard',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        late Directory root;
        late ScrapController controller;
        final notes = NoteController();
        final expenses = ExpenseController();
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp('mobile-workspace-');
          controller = ScrapController(
            directoryPicker: () async => p.join(root.path, 'vault'),
            directoryRestorer: () async => null,
            supportDirectoryProvider: () async => root,
            locationProvider: () async => null,
          );
          await controller.chooseVault();
          await controller.saveDocument('서울에서 모은 생각\n\n작은 메모를 노트로 이어 갑니다.');
          await notes.connect(controller.vaultPath!);
          await ExpenseRepository(Directory(controller.vaultPath!)).save(
            ExpenseRecord(
              id: 'sample',
              date: DateTime.now(),
              merchant: '동네 카페',
              amount: 5500,
              currency: ExpenseCurrency.krw,
              memo: '산책 후 커피',
            ),
          );
          await expenses.connect(controller.vaultPath!);
        });
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ScrapnoteApp(
              controller: controller,
              noteController: notes,
              expenseController: expenses,
              initializeController: false,
              installWindowCloseGuard: false,
              recoveryStore: EditorRecoveryStore(
                pathProvider: () async => p.join(root.path, 'recovery.json'),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        if (width < 700) {
          await tester.tap(find.byKey(const ValueKey('workspace-list-toggle')));
          await tester.pumpAndSettle();
        }
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
              'docs/screenshots/mobile-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(ScrapnoteShell.notesNavigationKey));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          notes.newDocument();
        });
        await tester.pumpAndSettle();
        notes.updateBody('접었다 펼쳐도 남아 있는 노트');
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ScrapnoteShell.expensesNavigationKey));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (width < 700) {
          await tester.tap(find.byKey(const ValueKey('mobile-new-expense')));
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(ScrapnoteShell.timelineNavigationKey));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        controller.dispose();
        notes.dispose();
        expenses.dispose();
        await tester.runAsync(() => root.delete(recursive: true));
      },
    );
  }
}
