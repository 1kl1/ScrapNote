import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/features/editor/inline_image.dart';
import 'package:scrapnote/infrastructure/vault/note_repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/app/scrapnote_app.dart';
import 'package:scrapnote/app/scrapnote_shell.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/editor/editor_session_controller.dart';
import 'package:scrapnote/features/scraps/scrap_controller.dart';
import 'package:scrapnote/infrastructure/drafts/editor_recovery_store.dart';
import 'package:scrapnote/infrastructure/platform/window_close_guard.dart';
import 'package:scrapnote/infrastructure/vault/vault_repository.dart';

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
    ClipboardImageReader? readClipboard,
  }) async {
    tester.view.physicalSize = const Size(1200, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(scrapController.dispose);
    editorSession ??= EditorSessionController();
    addTearDown(editorSession.dispose);

    await tester.pumpWidget(
      ScrapnoteApp(
        controller: scrapController,
        noteController: notes,
        clipboardImageReader: readClipboard,
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

  testWidgets(
    'Ctrl+V inserts one image at the body cursor and ordinary text paste still works',
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
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final scrapController = controller(
        picker: () async => vaultDirectory.path,
      );

      await tester.runAsync(scrapController.chooseVault);

      final session = EditorSessionController()..newDocument();
      var reads = 0;
      String? clipboardImage = '${sandbox.path}/clipboard image.png';
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
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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
      clipboardImage = null;

      await Clipboard.setData(const ClipboardData(text: 'Pasted text'));

      await tester.tap(find.byType(EditableText).last);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(session.activeDocument!.body, contains('Pasted text'));
      expect(session.activeDocument!.pendingImagePaths, hasLength(1));
    },
  );

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
