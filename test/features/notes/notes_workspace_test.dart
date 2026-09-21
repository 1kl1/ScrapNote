import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/features/notes/notes_workspace.dart';

void main() {
  testWidgets('nested folders expand with their documents in one tree', (
    tester,
  ) async {
    final vault = Directory.systemTemp.createTempSync('notes_tree_');
    addTearDown(() => vault.deleteSync(recursive: true));
    final controller = NoteController();
    addTearDown(controller.dispose);
    await tester.runAsync(() async {
      await controller.connect(vault.path);
      await controller.createFolder('Trips');
      await controller.createFolder('Seoul');
      controller.newDocument();
      controller.updateBody('Travel diary');
      await controller.saveActive();
    });
    final text = TextEditingController();
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => NotesWorkspace(
                noteController: controller,
                textController: text,
                onCreateFolder: () {},
                onCreateNote: () {},
                onSave: () {},
                onCloseTab: (_) {},
                onChooseImages: () {},
                onPasteImage: () async => false,
                onImagesDropped: (_) {},
                onRemoveImage: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('FOLDERS'), findsNothing);
    expect(find.text('DOCUMENTS'), findsNothing);
    expect(find.text('Seoul'), findsOneWidget);
    final diary = find.text('Travel diary').first;
    expect(
      tester.getTopLeft(diary).dx,
      greaterThan(tester.getTopLeft(find.text('Seoul')).dx),
    );
    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    expect(find.text('Seoul'), findsNothing);
    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    expect(find.text('Seoul'), findsOneWidget);
    expect(find.text('SCRAPS'), findsOneWidget);
    expect(find.text('Notes'), findsNothing);
    expect(find.byTooltip('Attach image · ⇧⌘I'), findsNothing);
  });

  testWidgets('offers a working new-note editor in the hierarchy', (
    tester,
  ) async {
    final vault = Directory.systemTemp.createTempSync('notes_workspace_');
    addTearDown(() => vault.deleteSync(recursive: true));
    final controller = NoteController();
    await tester.runAsync(() => controller.connect(vault.path));
    final textController = TextEditingController();
    var exportRequested = false;
    addTearDown(textController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ScrapnoteTheme.materialTheme,
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => NotesWorkspace(
                noteController: controller,
                textController: textController,
                onCreateFolder: () {},
                onCreateNote: controller.newDocument,
                onSave: () {},
                onCloseTab: (_) {},
                onChooseImages: () {},
                onPasteImage: () async => false,
                onImagesDropped: (_) {},
                onRemoveImage: (_) {},
                onExportNaverBlog: () => exportRequested = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('New note').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('note-editor')), findsOneWidget);
    expect(find.text('Untitled'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('note-title')),
      'My title',
    );
    await tester.pumpAndSettle();
    expect(controller.activeDocument!.draftTitle, 'My title');
    expect(controller.activeDocument!.dirty, isTrue);
    expect(find.text('My title'), findsNWidgets(2));
    await tester.tap(find.byTooltip('네이버 블로그로 내보내기'));
    expect(exportRequested, isTrue);
  });
}
