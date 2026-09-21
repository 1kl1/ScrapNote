import 'dart:io';
import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/features/expenses/expense_controller.dart';
import 'package:scrapnote/features/editor/inline_image.dart';
import 'package:scrapnote/infrastructure/vault/note_repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrapnote/app/scrapnote_app.dart';
import 'package:scrapnote/app/scrapnote_shell.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/editor/editor_session_controller.dart';
import 'package:scrapnote/features/scraps/scrap_controller.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_store.dart';
import 'package:scrapnote/infrastructure/platform/window_close_guard.dart';
import 'package:scrapnote/infrastructure/sync/sync_vault_summary.dart';
import 'package:scrapnote/infrastructure/sync/vault_synchronizer.dart';
import 'package:scrapnote/infrastructure/vault/vault_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

void main() {
  late Directory sandbox;
  late Directory vaultDirectory;
  late Directory supportDirectory;
  late _MemoryRecoveryFileIo recoveryIo;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scrapnote_app_');
    vaultDirectory = Directory('${sandbox.path}/vault');
    supportDirectory = Directory('${sandbox.path}/support');
    recoveryIo = _MemoryRecoveryFileIo();
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  ScrapController controller({required Future<String?> Function() picker}) {
    return ScrapController(
      directoryPicker: picker,
      directoryRestorer: () async => null,
      supportDirectoryProvider: () async => supportDirectory,
      locationProvider: () async => null,
      repositoryFactory: _MemoryVaultRepository.new,
    );
  }

  EditorRecoveryStore recoveryStore() => EditorRecoveryStore(
    pathProvider: () async => '/memory/recovery.json',
    io: recoveryIo,
  );

  Future<void> pumpApp(
    WidgetTester tester, {
    required ScrapController scrapController,
    EditorSessionController? editorSession,
    WindowCloseGuard? closeGuard,
    NoteController? notes,
    ExpenseController? expenses,
    ClipboardImageReader? readClipboard,
    ImagePathPicker? pickImages,
    SupabaseClient? syncClient,
    VaultSynchronizer vaultSynchronizer = synchronizeVault,
    Size size = const Size(1200, 720),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(scrapController.dispose);
    editorSession ??= EditorSessionController();
    addTearDown(editorSession.dispose);

    await tester.pumpWidget(
      ScrapnoteApp(
        controller: scrapController,
        syncClient: syncClient,
        syncSummaryLoader: (_) async => SyncVaultSummary.empty,
        vaultSynchronizer: vaultSynchronizer,
        noteController: notes,
        expenseController: expenses,
        clipboardImageReader: readClipboard,
        imagePathPicker: pickImages,
        editorSessionController: editorSession,
        recoveryStore: recoveryStore(),
        windowCloseGuard: closeGuard,
        initializeController: false,
        installWindowCloseGuard: closeGuard != null,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets(
      '${modifier.keyLabel}+V inserts one image at the body cursor and ordinary text paste still works',
      (tester) async {
        String? clipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboardText = (call.arguments as Map)['text'] as String?;
                return null;
              }
              if (call.method == 'Clipboard.getData') {
                return clipboardText == null ? null : {'text': clipboardText};
              }
              if (call.method == 'Clipboard.hasStrings') {
                return {'value': clipboardText != null};
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final scrapController = controller(
          picker: () async => vaultDirectory.path,
        );

        await tester.runAsync(scrapController.chooseVault);

        final session = EditorSessionController()..newDocument();
        var reads = 0;
        String? clipboardImage = '${sandbox.path}/clipboard image.png';
        await tester.runAsync(
          () => File(clipboardImage!).writeAsBytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNomLDgPwAF9AKw7aBF7QAAAABJRU5ErkJggg==',
            ),
          ),
        );
        await pumpApp(
          tester,
          scrapController: scrapController,
          editorSession: session,
          readClipboard: () async {
            reads++;
            return clipboardImage;
          },
        );
        await tester.enterText(
          find.byKey(const ValueKey('scrap-editor')),
          'BeforeAfter',
        );
        tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .selection = const TextSelection.collapsed(
          offset: 6,
        );
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();

        expect(reads, 1);
        final focusedEditor = tester
            .widgetList<EditableText>(find.byType(EditableText))
            .singleWhere((field) => field.focusNode.hasFocus);
        expect(focusedEditor.controller.text, 'After');
        expect(focusedEditor.controller.selection.extentOffset, 0);
        expect(
          session.activeDocument!.body,
          startsWith('Before\n![clipboard image.png]'),
        );
        expect(session.activeDocument!.body, endsWith('\nAfter'));
        expect(session.activeDocument!.pendingImagePaths, hasLength(1));
        expect(find.byType(Image), findsOneWidget);
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump();
        }
        expect(tester.widget<RawImage>(find.byType(RawImage)).image?.width, 1);
        expect(find.text('Image unavailable'), findsNothing);
        clipboardImage = null;

        await Clipboard.setData(const ClipboardData(text: 'Pasted text'));

        await tester.tap(find.byType(EditableText).last);
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(session.activeDocument!.body, contains('Pasted text'));
        expect(session.activeDocument!.pendingImagePaths, hasLength(1));
      },
    );
  }
  testWidgets(
    'dropping an image inserts at the pointer position in the document',
    (tester) async {
      final scraps = controller(picker: () async => vaultDirectory.path);
      await tester.runAsync(scraps.chooseVault);
      final session = EditorSessionController()..newDocument();
      await pumpApp(tester, scrapController: scraps, editorSession: session);
      await tester.enterText(
        find.byKey(const ValueKey('scrap-editor')),
        'BeforeAfter',
      );
      await tester.pump();
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final pointer = render.localToGlobal(
        render.getLocalRectForCaret(const TextPosition(offset: 6)).center,
      );
      tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(
        DropDoneDetails(
          files: [DropItemFile('${sandbox.path}/dropped.png')],
          localPosition: Offset.zero,
          globalPosition: pointer,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        session.activeDocument!.body,
        startsWith('Before\n![dropped.png]'),
      );
      expect(session.activeDocument!.body, endsWith('\nAfter'));
      expect(session.activeDocument!.pendingImagePaths, hasLength(1));
    },
  );

  testWidgets(
    'choosing several images inserts one horizontally scrollable row',
    (tester) async {
      final scraps = controller(picker: () async => vaultDirectory.path);
      await tester.runAsync(scraps.chooseVault);
      final session = EditorSessionController()..newDocument();
      final images = <String>[
        '${sandbox.path}/first.png',
        '${sandbox.path}/second.png',
        '${sandbox.path}/third.png',
      ];
      await pumpApp(
        tester,
        scrapController: scraps,
        editorSession: session,
        pickImages: () async => images,
        size: const Size(500, 720),
      );

      await tester.tap(find.byKey(const ValueKey('workspace-image')));
      await tester.pumpAndSettle();

      expect(session.activeDocument!.pendingImagePaths, images);
      expect(session.activeDocument!.body, contains(InlineImageRow.begin));
      expect(
        InlineImage.pattern.allMatches(session.activeDocument!.body),
        hasLength(3),
      );
      expect(
        find.byKey(const ValueKey('horizontal-image-row')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Notes inserts a searched Scrap with working relative images and saves the result',
    (tester) async {
      final scraps = controller(picker: () async => vaultDirectory.path);
      final notes = NoteController();
      addTearDown(notes.dispose);
      await tester.runAsync(() async {
        await scraps.chooseVault();
        await scraps.saveDocument(
          'Source Scrap\n![Photo](../assets/shared.png)\nSource detail',
        );
        final image = File('${vaultDirectory.path}/assets/shared.png');
        await image.parent.create(recursive: true);
        await image.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNomLDgPwAF9AKw7aBF7QAAAABJRU5ErkJggg==',
          ),
        );
        await notes.connect(vaultDirectory.path);
        await notes.createFolder('Trips');
      });
      await pumpApp(tester, scrapController: scraps, notes: notes);
      await tester.tap(find.byKey(ScrapnoteShell.notesNavigationKey));
      await tester.pump();
      await tester.tap(find.text('New note').last);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('note-editor')),
        'BeforeAfter',
      );
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('note-editor')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .selection = const TextSelection.collapsed(
        offset: 6,
      );
      expect(find.text('SCRAPS'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).last, 'Source');
      await tester.pump();
      await tester.tap(find.text('Source Scrap'));
      await tester.pumpAndSettle();
      expect(
        notes.activeDocument!.body,
        startsWith('Before\n<!-- scrapnote:begin:'),
      );
      expect(
        find.byKey(const ValueKey('scrap-object-scrap-0')),
        findsOneWidget,
      );
      expect(
        notes.activeDocument!.body,
        contains('](../../assets/shared.png)'),
      );
      expect(notes.activeDocument!.body, endsWith('\nAfter'));
      expect(find.byType(Image), findsNothing);
      await tester.runAsync(() async {
        expect(await notes.saveActive(), isTrue);
        final saved = (await NoteRepository(vaultDirectory).listNotes()).single;
        final imagePath = InlineImage.pattern.firstMatch(saved.body)!.group(2)!;
        expect(
          await File.fromUri(
            Uri.file(saved.filePath).resolve(imagePath),
          ).exists(),
          isTrue,
        );
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('Source detail'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scrap-object-scrap-0')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Edit Scrap'));
      await tester.pumpAndSettle();
      final editField = find.descendant(
        of: find.byKey(const ValueKey('scrap-dialog-editor')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(editField, 'Revised capture');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(notes.activeDocument!.body, contains('Revised capture'));
      expect(scraps.scraps.single.body, startsWith('Source Scrap'));
      expect(notes.usedScrapIds(), {'scrap-0'});
      await tester.tap(find.byTooltip('Edit Scrap'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('scrap-dialog-editor')),
        'Cancelled change',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(notes.activeDocument!.body, isNot(contains('Cancelled change')));
      await tester.tap(find.byKey(ScrapnoteShell.scrapsNavigationKey));
      await tester.pumpAndSettle();
      expect(find.text('Source Scrap'), findsNothing);
      notes.newDocument();
      await tester.tap(find.byKey(ScrapnoteShell.notesNavigationKey));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scrap-choice-scrap-0')), findsNothing);
    },
  );

  testWidgets(
    'deleting an open Scrap closes its tab and removes it from the inbox',
    (tester) async {
      final scraps = controller(picker: () async => vaultDirectory.path);
      final session = EditorSessionController();
      await tester.runAsync(() async {
        await scraps.chooseVault();
        final saved = await scraps.saveDocument('Delete this document');
        session.openScrap(saved!);
      });
      await pumpApp(tester, scrapController: scraps, editorSession: session);
      await tester.tap(
        find.text('Delete this document').first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete scrap'));
      await tester.pumpAndSettle();
      expect(scraps.scraps, isEmpty);
      expect(session.documents, isEmpty);
      expect(find.text('Delete this document'), findsNothing);
    },
  );

  testWidgets('shows only the local-folder onboarding before vault setup', (
    tester,
  ) async {
    final scrapController = controller(picker: () async => null);
    await tester.runAsync(scrapController.initialize);
    await pumpApp(tester, scrapController: scrapController);

    expect(find.text('Choose a local folder'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('scrap-editor')), findsNothing);
    expect(find.text('INBOX'), findsNothing);
    expect(find.text('SCRAPNOTE'), findsNothing);
  });

  testWidgets('choosing a folder advances setup into the editor', (
    tester,
  ) async {
    final scrapController = controller(picker: () async => vaultDirectory.path);
    await tester.runAsync(scrapController.initialize);
    final editorSession = EditorSessionController();
    await pumpApp(
      tester,
      scrapController: scrapController,
      editorSession: editorSession,
    );

    expect(
      find.byKey(const ValueKey<String>('onboarding-choose-folder')),
      findsOneWidget,
    );
    await tester.runAsync(scrapController.chooseVault);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(scrapController.hasVault, isTrue);
    expect(find.text('INBOX'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('scrap-editor')), findsOneWidget);
  });

  testWidgets('places persistent sync status below the workspace', (
    tester,
  ) async {
    final scrapController = controller(picker: () async => vaultDirectory.path);
    await tester.runAsync(scrapController.chooseVault);
    final client = SupabaseClient(
      'https://example.supabase.co',
      'public-test-key',
      isolate: _InlineJson(),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);

    await pumpApp(tester, scrapController: scrapController, syncClient: client);
    await tester.pump(const Duration(milliseconds: 300));

    final status = find.byKey(const ValueKey<String>('sync-status-line'));
    expect(status, findsOneWidget);
    expect(
      tester.getTopLeft(status).dy,
      greaterThan(tester.getCenter(find.byKey(ScrapnoteShell.bodyKey)).dy),
    );
    final button = find.byKey(const ValueKey<String>('manual-sync-button'));
    expect(tester.getSize(status).height, 32);
    expect(tester.getSize(button).width, lessThanOrEqualTo(32));
    expect(tester.getSize(button).height, lessThanOrEqualTo(32));
    expect(
      find.descendant(of: button, matching: find.byType(Text)),
      findsNothing,
    );
    expect(tester.widget<FButton>(button).size, FButtonSizeVariant.xs);
    expect(tester.widget<FButton>(button).semanticsLabel, '동기화');
    expect(tester.getCenter(button).dx, greaterThan(1000));
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(720));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('계정 및 동기화'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
  });

  testWidgets('syncs only on click and saves drafts before syncing', (
    tester,
  ) async {
    final scrapController = controller(picker: () async => vaultDirectory.path);
    await tester.runAsync(scrapController.chooseVault);
    await tester.runAsync(() async {
      final state = File('${vaultDirectory.path}/.sync/state.json');
      await state.parent.create(recursive: true);
      await state.writeAsString('{}');
    });
    final client = SupabaseClient(
      'https://example.supabase.co',
      'public-test-key',
      isolate: _InlineJson(),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'fixture-access',
            'refresh_token': 'fixture-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'test-user',
              'aud': 'authenticated',
              'email': 'person@example.com',
              'created_at': '2026-09-15T00:00:00Z',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
            },
          }),
          200,
        ),
      ),
    );
    addTearDown(client.dispose);
    await tester.runAsync(
      () => client.auth.signInWithPassword(
        email: 'person@example.com',
        password: 'fixture-password',
      ),
    );
    final session = EditorSessionController();
    final notes = _SyncTestNoteController();
    final expenses = _SyncTestExpenseController();
    addTearDown(notes.dispose);
    addTearDown(expenses.dispose);
    final syncing = Completer<void>();
    var syncs = 0;
    await pumpApp(
      tester,
      scrapController: scrapController,
      editorSession: session,
      notes: notes,
      expenses: expenses,
      syncClient: client,
      vaultSynchronizer: (vaultPath, suppliedClient, resolutions) {
        expect(vaultPath, vaultDirectory.path);
        expect(suppliedClient, same(client));
        expect(session.hasDirtyDocuments, isFalse);
        expect(scrapController.scraps.single.body, 'manual draft');
        syncs += 1;
        return syncing.future;
      },
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('scrap-editor')),
      'saved locally',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('scrap-editor')),
      'manual draft',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 65));
    expect(syncs, 0);
    expect(session.hasDirtyDocuments, isTrue);

    final button = find.byKey(const ValueKey<String>('manual-sync-button'));
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(syncs, 1);
    expect(tester.widget<FButton>(button).onPress, isNull);
    await tester.pump(const Duration(seconds: 65));
    expect(syncs, 1);

    await tester.runAsync(() async {
      syncing.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.textContaining('동기화 완료'), findsOneWidget);
    expect(tester.widget<FButton>(button).onPress, isNotNull);
  });

  testWidgets('manual sync shows the specific image size error', (
    tester,
  ) async {
    final scrapController = controller(picker: () async => vaultDirectory.path);
    await tester.runAsync(scrapController.chooseVault);
    final client = SupabaseClient(
      'https://example.supabase.co',
      'public-test-key',
      isolate: _InlineJson(),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'fixture-access',
            'refresh_token': 'fixture-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'test-user',
              'aud': 'authenticated',
              'email': 'person@example.com',
              'created_at': '2026-09-15T00:00:00Z',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
            },
          }),
          200,
        ),
      ),
    );
    addTearDown(client.dispose);
    await tester.runAsync(
      () => client.auth.signInWithPassword(
        email: 'person@example.com',
        password: 'fixture-password',
      ),
    );
    final notes = _SyncTestNoteController();
    final expenses = _SyncTestExpenseController();
    addTearDown(notes.dispose);
    addTearDown(expenses.dispose);
    await pumpApp(
      tester,
      scrapController: scrapController,
      syncClient: client,
      notes: notes,
      expenses: expenses,
      vaultSynchronizer: (_, _, _) async =>
          throw const FileSystemException('동기화 가능한 파일 크기는 25 MiB 이하입니다.'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey<String>('manual-sync-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    final statusText = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('sync-status-line')),
            matching: find.byType(Text),
          ),
        )
        .map((widget) => widget.data)
        .join('|');
    expect(statusText, contains('25 MiB 이하'));
  });

  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('bottom-right sync button fits width $width', (tester) async {
      final scrapController = controller(
        picker: () async => vaultDirectory.path,
      );
      await tester.runAsync(scrapController.chooseVault);
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        isolate: _InlineJson(),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      await pumpApp(
        tester,
        scrapController: scrapController,
        syncClient: client,
        size: Size(width, 800),
      );
      final button = find.byKey(const ValueKey<String>('manual-sync-button'));
      expect(tester.getSize(button).width, lessThanOrEqualTo(32));
      expect(tester.getSize(button).height, lessThanOrEqualTo(32));
      expect(
        find.descendant(of: button, matching: find.byType(Text)),
        findsNothing,
      );
      expect(tester.getBottomRight(button).dx, lessThanOrEqualTo(width));
      expect(tester.getCenter(button).dx, greaterThan(width / 2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('marks edits dirty and saves the active document with Cmd+S', (
    tester,
  ) async {
    final scrapController = controller(picker: () async => vaultDirectory.path);
    await tester.runAsync(() async {
      await scrapController.initialize();
      await scrapController.chooseVault();
    });
    final editorSession = EditorSessionController();
    await pumpApp(
      tester,
      scrapController: scrapController,
      editorSession: editorSession,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('scrap-editor')),
      '# Quiet capture',
    );
    await tester.pump();
    expect(editorSession.activeDocument?.dirty, isTrue);
    expect(
      find.byKey(const ValueKey<String>('dirty-indicator')),
      findsOneWidget,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    expect(HardwareKeyboard.instance.isMetaPressed, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (scrapController.scraps.isNotEmpty) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      scrapController.scraps,
      isNotEmpty,
      reason: scrapController.errorMessage ?? 'Save shortcut did not run.',
    );
    expect(scrapController.scraps.single.firstLineTitle, 'Quiet capture');
    expect(editorSession.activeDocument?.dirty, isFalse);
    expect(find.byKey(const ValueKey<String>('dirty-indicator')), findsNothing);
  });

  testWidgets('dirty tab close offers Save, Don’t Save, and Cancel', (
    tester,
  ) async {
    final scrapController = controller(picker: () async => vaultDirectory.path);
    await tester.runAsync(() async {
      await scrapController.initialize();
      await scrapController.chooseVault();
    });
    final editorSession = EditorSessionController();
    await pumpApp(
      tester,
      scrapController: scrapController,
      editorSession: editorSession,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('scrap-editor')),
      'unsaved',
    );
    await tester.pump();
    final sessionId = editorSession.activeSessionId!;
    await tester.tap(find.byKey(ValueKey<String>('close-tab-$sessionId')));
    await tester.pump();

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Don’t Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Don’t Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(editorSession.documents, isEmpty);
    expect(scrapController.scraps, isEmpty);
  });

  testWidgets('Cmd+N opens and Cmd+W closes a Note document', (tester) async {
    final scrapController = controller(picker: () async => vaultDirectory.path);
    await tester.runAsync(() async {
      await scrapController.initialize();
      await scrapController.chooseVault();
    });
    await pumpApp(tester, scrapController: scrapController);

    await tester.tap(find.byKey(ScrapnoteShell.notesNavigationKey));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('note-editor')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('note-editor')), findsNothing);
    await tester.pump(const Duration(milliseconds: 120));
  });

  testWidgets('window close remains pending until the dirty prompt resolves', (
    tester,
  ) async {
    final scrapController = controller(picker: () async => vaultDirectory.path);
    await tester.runAsync(() async {
      await scrapController.initialize();
      await scrapController.chooseVault();
    });
    final closeGuard = _TestWindowCloseGuard();
    await pumpApp(
      tester,
      scrapController: scrapController,
      closeGuard: closeGuard,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('scrap-editor')),
      'unsaved',
    );
    await tester.pump();
    final closeResult = closeGuard.requestClose();
    await tester.pump();
    expect(find.text('Save the open change?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(await closeResult, isFalse);
  });
}

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

// This test exercises sync triggers, not unrelated repository filesystem I/O.
class _SyncTestNoteController extends NoteController {
  @override
  Future<void> connect(String vaultPath) async {}

  @override
  Future<void> reloadAfterSync() async {}
}

class _SyncTestExpenseController extends ExpenseController {
  @override
  Future<void> connect(String vaultPath) async {}

  @override
  Future<void> reloadAfterSync() async {}
}

class _TestWindowCloseGuard extends WindowCloseGuard {
  WindowCloseRequest? _handler;

  @override
  Future<void> start(WindowCloseRequest onCloseRequested) async {
    _handler = onCloseRequested;
  }

  @override
  Future<void> stop() async {
    _handler = null;
  }

  Future<bool> requestClose() => _handler!();
}

class _MemoryRecoveryFileIo implements RecoveryFileIo {
  final Map<String, String> _files = <String, String>{};

  @override
  Future<void> delete(String filePath) async {
    _files.remove(filePath);
  }

  @override
  Future<bool> exists(String filePath) async => _files.containsKey(filePath);

  @override
  Future<String> read(String filePath) async => _files[filePath]!;

  @override
  Future<void> writeAtomically(String filePath, String contents) async {
    _files[filePath] = contents;
  }
}

class _MemoryVaultRepository extends VaultRepository {
  _MemoryVaultRepository(super.root);

  final List<Scrap> _scraps = <Scrap>[];
  var _sequence = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Scrap>> listScraps() async => List<Scrap>.of(_scraps);

  @override
  Future<void> deleteScrap(String id) async =>
      _scraps.removeWhere((s) => s.id == id);

  @override
  Future<Scrap> createScrap(
    String body, {
    Iterable<String> attachmentPaths = const <String>[],
    ScrapLocation? location,
  }) async {
    final now = DateTime.utc(2026, 9, 9, 9, _sequence);
    final scrap = Scrap(
      id: 'scrap-${_sequence++}',
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    _scraps.insert(0, scrap);
    return scrap;
  }

  @override
  Future<Scrap> updateScrap(
    Scrap existing,
    String body, {
    Iterable<String> attachmentPaths = const <String>[],
  }) async {
    final updated = Scrap(
      id: existing.id,
      body: body,
      createdAt: existing.createdAt,
      updatedAt: DateTime.utc(2026, 9, 9, 10),
      localDate: existing.localDate,
      utcOffsetMinutes: existing.utcOffsetMinutes,
      timezoneName: existing.timezoneName,
      assets: existing.assets,
      location: existing.location,
    );
    _scraps
      ..removeWhere((scrap) => scrap.id == existing.id)
      ..insert(0, updated);
    return updated;
  }
}
