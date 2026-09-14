// Run with: flutter test tool/review_workspace.dart
// Writes review screenshots to build/review without accessing the user's Vault.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/app/scrapnote_shell.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/features/notes/note_controller.dart';
import 'package:scrapnote/features/notes/notes_workspace.dart';
import 'package:scrapnote/features/editor/inline_image.dart';

void main() {
  testWidgets('capture the hierarchical Notes workspace with an inline image', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final folder = Directory.systemTemp.createTempSync('scrapnote-review-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final notes = NoteController();
    addTearDown(notes.dispose);
    await tester.runAsync(() async {
      for (final family in ['.AppleSystemUIFont', 'monospace', 'Roboto']) {
        final loader = FontLoader(family)
          ..addFont(
            File(
              '/System/Library/Fonts/Supplemental/Arial.ttf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
        await loader.load();
      }
      final config = File('.dart_tool/package_config.json').absolute;
      final packages =
          (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
      final assets = packages.cast<Map>().singleWhere(
        (p) => p['name'] == 'forui_assets',
      );
      final font = config.uri
          .resolve(assets['rootUri'] as String)
          .resolve('assets/lucide.ttf');
      final icons = FontLoader('packages/forui_assets/ForuiLucideIcons')
        ..addFont(
          File.fromUri(font).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await icons.load();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 560, 240),
        Paint()..color = const Color(0xffc8d7d1),
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, 240)
          ..lineTo(180, 85)
          ..lineTo(300, 240)
          ..close(),
        Paint()..color = const Color(0xff607b73),
      );
      canvas.drawPath(
        Path()
          ..moveTo(200, 240)
          ..lineTo(380, 65)
          ..lineTo(560, 240)
          ..close(),
        Paint()..color = const Color(0xff839c87),
      );
      canvas.drawCircle(
        const Offset(100, 55),
        24,
        Paint()..color = const Color(0xffeed5a2),
      );
      final image = await recorder.endRecording().toImage(560, 240);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final imageFile = File('${folder.path}/mountains.png');
      await imageFile.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      await notes.connect(folder.path);
      await notes.createFolder('Travel');
      await notes.createFolder('Seoul');
      notes.newDocument();
      notes.updateBody(
        'Morning walk\n\nA quiet path above the city.\n${InlineImage.markdown(imageFile.path, label: 'Mountain view')}\n\nKeep this view beside the observations from today.',
      );
      notes.addAttachment(imageFile.path);
      await notes.saveActive();
    });
    final text = TextEditingController(text: notes.activeDocument!.body);
    addTearDown(text.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ScrapnoteTheme.materialTheme,
        home: RepaintBoundary(
          key: boundary,
          child: ScrapnoteShell(
            section: ScrapnoteSection.notes,
            onSectionChanged: (_) {},
            vaultPath: folder.path,
            onChooseVault: () {},
            body: NotesWorkspace(
              noteController: notes,
              textController: text,
              onCreateFolder: () {},
              onCreateNote: () {},
              onSave: () {},
              onCloseTab: (_) {},
              onChooseImages: () {},
              onPasteImage: () {},
              onImagesDropped: (_) {},
              onRemoveImage: (_) {},
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('build/review/notes-inline.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
