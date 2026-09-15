import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:scrapnote/features/editor/inline_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/scraps/scraps_view.dart';

void main() {
  const tab = ScrapEditorTabData(
    id: 'session-1',
    title: 'Untitled',
    dirty: true,
  );

  Future<TextEditingController> pumpView(
    WidgetTester tester, {
    List<Scrap> scraps = const <Scrap>[],
    List<String> images = const <String>[],
    VoidCallback? onSave,
    VoidCallback? onNew,
    ValueChanged<String>? onScrapSelected,
    ValueChanged<String>? onTabSelected,
    ValueChanged<String>? onTabClosed,
    ValueChanged<String>? onRemove,
    ValueChanged<List<String>>? onDropped,
    Future<bool> Function()? onPaste,
    VoidCallback? onCloseActive,
    ValueChanged<String>? onDelete,
  }) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController(
      text:
          'first line\nsecond line${images.map((p) => '\n${InlineImage.markdown(p)}\n').join()}',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ScrapnoteTheme.materialTheme,
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: ScrapsView(
              scraps: scraps,
              onDeleteScrap: onDelete,
              tabs: const <ScrapEditorTabData>[tab],
              activeTabId: tab.id,
              activeScrapId: scraps.isEmpty ? null : scraps.first.id,
              controller: controller,
              pendingImagePaths: images,
              onSave: onSave ?? () {},
              onNewDocument: onNew ?? () {},
              onScrapSelected: onScrapSelected ?? (_) {},
              onTabSelected: onTabSelected ?? (_) {},
              onTabClosed: onTabClosed ?? (_) {},
              onCloseActive: onCloseActive ?? () {},
              onRemoveImage: onRemove,
              onImagesDropped: onDropped,
              onPasteImage: onPaste,
              onChooseImages: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('prioritizes the hierarchy, tabs, and line-number editor', (
    tester,
  ) async {
    await pumpView(tester);

    expect(find.text('INBOX'), findsOneWidget);
    expect(find.text('Untitled'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('scrap-editor')), findsOneWidget);
    expect(find.text('Save scrap'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Preview'), findsNothing);
  });

  testWidgets('uses the dirty indicator and delegates tab interactions', (
    tester,
  ) async {
    String? selected;
    String? closed;
    await pumpView(
      tester,
      onTabSelected: (id) => selected = id,
      onTabClosed: (id) => closed = id,
    );

    expect(
      find.byKey(const ValueKey<String>('dirty-indicator')),
      findsOneWidget,
    );
    await tester.tap(find.text('Untitled'));
    expect(selected, tab.id);

    await tester.tap(find.byKey(const ValueKey<String>('close-tab-session-1')));
    expect(closed, tab.id);
  });

  testWidgets('Cmd+S saves and Cmd+N creates without visible save chrome', (
    tester,
  ) async {
    var saves = 0;
    var newDocuments = 0;
    await pumpView(
      tester,
      onSave: () => saves += 1,
      onNew: () => newDocuments += 1,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(saves, 1);
    expect(newDocuments, 1);
    expect(find.textContaining('Save'), findsNothing);
  });

  testWidgets('Cmd+W closes the active scrap editor', (tester) async {
    var closes = 0;
    await pumpView(tester, onCloseActive: () => closes += 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(closes, 1);
  });

  testWidgets('keeps image drop and paste with inline image removal', (
    tester,
  ) async {
    var pasteCount = 0;
    String? removedPath;
    const imagePath = '/tmp/desk photo.png';
    await pumpView(
      tester,
      images: const <String>[imagePath],
      onDropped: (_) {},
      onPaste: () async {
        pasteCount += 1;
        return true;
      },
      onRemove: (value) => removedPath = value,
    );

    expect(tester.widget<DropTarget>(find.byType(DropTarget)).enable, isTrue);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('attach-image')), findsNothing);
    expect(find.byKey(const ValueKey('document-image-gallery')), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(pasteCount, 1);

    await tester.tap(find.byTooltip('Remove image'));
    await tester.pumpAndSettle();
    expect(removedPath, imagePath);
  });

  testWidgets('right click opens a delete action without selecting the Scrap', (
    tester,
  ) async {
    String? deleted;
    String? selected;
    final scrap = Scrap(
      id: 'delete-me',
      body: 'Delete me',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await pumpView(
      tester,
      scraps: [scrap],
      onDelete: (id) => deleted = id,
      onScrapSelected: (id) => selected = id,
    );
    await tester.tap(find.text('Delete me'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Delete scrap'));
    await tester.pumpAndSettle();
    expect(deleted, scrap.id);
  });

  testWidgets('selects a saved scrap from the modified-first hierarchy', (
    tester,
  ) async {
    final recentlyEdited = Scrap(
      id: 'recently-edited',
      body: '# Recently edited',
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 5),
    );
    final newlyCreated = Scrap(
      id: 'newly-created',
      body: '# Newly created',
      createdAt: DateTime.utc(2026, 9, 4),
      updatedAt: DateTime.utc(2026, 9, 4),
    );
    String? selected;
    await pumpView(
      tester,
      scraps: <Scrap>[newlyCreated, recentlyEdited],
      onScrapSelected: (id) => selected = id,
    );

    final editedCenter = tester.getCenter(find.text('Recently edited'));
    final createdCenter = tester.getCenter(find.text('Newly created'));
    expect(editedCenter.dy, lessThan(createdCenter.dy));

    await tester.tap(find.text('Recently edited'));
    expect(selected, recentlyEdited.id);
  });
}
