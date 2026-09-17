import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/features/editor/inline_document_editor.dart';
import 'package:scrapnote/features/editor/inline_image.dart';

void main() {
  for (final key in [LogicalKeyboardKey.backspace, LogicalKeyboardKey.delete]) {
    testWidgets('${key.keyLabel} removes blank lines between images', (
      tester,
    ) async {
      const first = '![First](file:///tmp/first-missing.png)';
      const second = '![Second](file:///tmp/second-missing.png)';
      final controller = TextEditingController(text: '$first\n\n\n$second')
        ..selection = TextSelection.collapsed(offset: first.length + 1);
      addTearDown(controller.dispose);
      final removed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: ScrapnoteTheme.foruiTheme,
            child: Scaffold(
              body: InlineDocumentEditor(
                controller: controller,
                imageDirectory: '/tmp',
                onRemoveImage: removed.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gap = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(gap.controller.text, '\n');
      gap.controller.selection = TextSelection.collapsed(
        offset: key == LogicalKeyboardKey.backspace ? 1 : 0,
      );
      gap.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(controller.text, '$first\n\n$second');
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(controller.text, '$first\n$second');
      expect(find.byType(Image), findsNWidgets(2));
      expect(removed, isEmpty);
      expect(find.byType(EditableText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('image-heavy documents keep their height and wheel offset stable', (
    tester,
  ) async {
    final directory = (await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('inline-scroll-');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNomLDgPwAF9AKw7aBF7QAAAABJRU5ErkJggg==',
      );
      for (var i = 0; i < 12; i++) {
        await File('${root.path}/image-$i.png').writeAsBytes(png);
      }
      return root;
    }))!;
    addTearDown(() => directory.delete(recursive: true));
    final controller = TextEditingController(
      text: [
        for (var i = 0; i < 12; i++) ...[
          List.generate(
            i % 4 + 1,
            (line) => 'Paragraph $i line $line',
          ).join('\n'),
          '![Image $i](image-$i.png "center:${[100, 20, 50, 33][i % 4]}")',
        ],
        'Document end',
      ].join('\n'),
    )..selection = const TextSelection.collapsed(offset: 0);
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    // Decode fixtures before mounting the editor: this isolates lazy extent
    // corrections from unrelated asynchronous file/decode scheduling.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold));
      await Future.wait([
        for (var i = 0; i < 12; i++)
          precacheImage(
            FileImage(File('${directory.path}/image-$i.png')),
            context,
          ),
      ]);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: InlineDocumentEditor(
              controller: controller,
              scrollController: scroll,
              imageDirectory: directory.path,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();

    final extent = scroll.position.maxScrollExtent;
    expect(extent, greaterThan(2000));
    final document = find.byKey(const ValueKey('inline-document-scroll'));
    final pointer = tester.getTopLeft(document) + const Offset(10, 100);
    for (var tick = 1; tick <= 30; tick++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: pointer, scrollDelta: const Offset(0, 60)),
      );
      await tester.pump();
      expect(scroll.offset, closeTo(tick * 60, 0.01));
      expect(scroll.position.maxScrollExtent, closeTo(extent, 0.01));
    }
    // Crossing all image boundaries in either direction does not change the
    // document extent or trigger a sliver scroll-offset correction.
    for (final offset in [extent - 10, extent / 2, 120.0, 0.0]) {
      scroll.jumpTo(offset);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, 0.01));
      expect(scroll.position.maxScrollExtent, closeTo(extent, 0.01));
    }
    // Even below the fold, blocks remain mounted with their measured heights.
    expect(find.byType(Image), findsNWidgets(12));
    expect(find.byType(EditableText), findsNWidgets(13));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Backspace joins lines after an image is removed', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: 'Before\n![Image](file:///tmp/missing.png)\nAfter',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: InlineDocumentEditor(
              controller: controller,
              imageDirectory: '/tmp',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove image'));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.controller.selection = const TextSelection.collapsed(offset: 7);
    field.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(controller.text, 'BeforeAfter');
    expect(tester.takeException(), isNull);
  });

  testWidgets('bold shortcut remains available without a toolbar button', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'First line\nSecond line');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: InlineDocumentEditor(
              controller: controller,
              imageDirectory: '/tmp',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.controller.selection = const TextSelection(
      baseOffset: 11,
      extentOffset: 17,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, 'First line\n**Second** line');
    expect(find.byTooltip('Bold · ⌘B / Ctrl+B'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(controller.text, 'First line\nSecond line');
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing an embedded Scrap releases pending images inside it', (
    tester,
  ) async {
    final controller = TextEditingController(
      text:
          '<!-- scrapnote:begin:s1 -->\n![Image](file:///tmp/pending.png "center:50")\n<!-- scrapnote:end -->',
    );
    addTearDown(controller.dispose);
    String? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: InlineDocumentEditor(
              controller: controller,
              imageDirectory: '/tmp',
              onRemoveImage: (p) => removed = p,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Scrap'));
    await tester.pumpAndSettle();
    expect(removed, '/tmp/pending.png');
    expect(controller.text, isEmpty);
  });

  test('inserts an encoded image at the selection, between text', () {
    final controller = TextEditingController(text: 'BeforeAfter')
      ..selection = const TextSelection.collapsed(offset: 6);
    InlineImage.insert(controller, InlineImage.markdown('/tmp/a (1).png'));
    expect(
      controller.text,
      'Before\n![Image](file:///tmp/a%20%281%29.png "center:50")\nAfter',
    );
    expect(
      InlineImage.pattern.firstMatch(controller.text)?.group(2),
      'file:///tmp/a%20%281%29.png',
    );
    controller.dispose();
  });

  testWidgets(
    'keeps numbered text around an image with size, alignment and removal',
    (tester) async {
      final controller = TextEditingController(
        text: 'Before\n![Image](file:///tmp/missing.png)\nAfter',
      );
      addTearDown(controller.dispose);
      String? removed;
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: ScrapnoteTheme.foruiTheme,
            child: Scaffold(
              body: InlineDocumentEditor(
                controller: controller,
                imageDirectory: '/tmp',
                onRemoveImage: (source) => removed = source,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final fields = find.byType(EditableText);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.last, '\nEdited after');
      expect(controller.text, contains('Edited after'));
      await tester.tap(find.byTooltip('Align image right'));
      await tester.pump();
      expect(controller.text, contains('"right:100"'));
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byTooltip('Move image up'), findsNothing);
      final fullWidth = tester.getSize(find.byType(Image)).width;
      for (final size in [50, 33, 20, 100]) {
        await tester.tap(find.text('$size%'));
        await tester.pumpAndSettle();
        expect(controller.text, contains('"right:$size"'));
        expect(
          tester.getSize(find.byType(Image)).width,
          closeTo(fullWidth * size / 100, 1),
        );
      }
      expect(find.byKey(const ValueKey('line-number-2')), findsOneWidget);
      await tester.tap(find.byTooltip('Remove image'));
      await tester.pumpAndSettle();
      expect(controller.text, isNot(contains('![Image]')));
      expect(controller.text, contains('Edited after'));
      expect(removed, '/tmp/missing.png');
      expect(tester.takeException(), isNull);
    },
  );
}
