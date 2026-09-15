import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_shell.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/core/design/scrapnote_tokens.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required Size size,
    required ValueChanged<ScrapnoteSection> onSectionChanged,
    VoidCallback? onChooseVault,
    String? vaultPath,
    Widget body = const Center(child: Text('Workbench body')),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ScrapnoteTheme.materialTheme,
        home: ScrapnoteShell(
          section: ScrapnoteSection.scraps,
          onSectionChanged: onSectionChanged,
          vaultPath: vaultPath,
          onChooseVault: onChooseVault,
          body: body,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('uses an icon-only activity rail without product chrome', (
    tester,
  ) async {
    ScrapnoteSection? selected;
    await pumpShell(
      tester,
      size: const Size(1280, 800),
      vaultPath: '/Users/test/Scrapnote',
      onSectionChanged: (section) => selected = section,
    );

    expect(find.byType(FTheme), findsOneWidget);
    expect(find.text('SCRAPNOTE'), findsNothing);
    expect(find.text('Scraps'), findsNothing);
    expect(find.text('Notes'), findsNothing);
    expect(find.text('Timeline'), findsNothing);
    expect(find.text('/Users/test/Scrapnote'), findsNothing);
    expect(find.text('Workbench body'), findsOneWidget);
    expect(find.byKey(ScrapnoteShell.scrapsNavigationKey), findsOneWidget);
    expect(find.byKey(ScrapnoteShell.notesNavigationKey), findsOneWidget);
    expect(find.byKey(ScrapnoteShell.timelineNavigationKey), findsOneWidget);

    await tester.tap(find.byKey(ScrapnoteShell.notesNavigationKey));
    await tester.pumpAndSettle();

    expect(selected, ScrapnoteSection.notes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rail reserves exactly 48 pixels before the workbench body', (
    tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(1280, 800),
      onSectionChanged: (_) {},
    );

    final rail = tester.getRect(find.byKey(ScrapnoteShell.activityRailKey));
    final body = tester.getRect(find.byKey(ScrapnoteShell.bodyKey));

    expect(rail.left, 0);
    expect(rail.width, ScrapnoteTokens.activityRailWidth);
    expect(body.left, rail.right);
    expect(body.right, 1280);
    expect(rail.intersect(body).isEmpty, isTrue);
  });

  testWidgets('vault icon exposes its path and delegates selection', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var chooseCount = 0;
    await pumpShell(
      tester,
      size: const Size(1280, 800),
      vaultPath: '/Users/test/Scrapnote',
      onSectionChanged: (_) {},
      onChooseVault: () => chooseCount += 1,
    );

    final vaultSemanticsFinder = find.bySemanticsLabel(
      'Change local vault. Current path: /Users/test/Scrapnote',
    );
    expect(vaultSemanticsFinder, findsOneWidget);
    final vaultSemantics = tester
        .getSemantics(vaultSemanticsFinder)
        .getSemanticsData();
    expect(vaultSemantics.label, contains('Change local vault'));
    expect(vaultSemantics.label, contains('/Users/test/Scrapnote'));
    expect(vaultSemantics.tooltip, contains('/Users/test/Scrapnote'));

    await tester.tap(find.byKey(ScrapnoteShell.vaultActionKey));
    await tester.pumpAndSettle();

    expect(chooseCount, 1);
    semantics.dispose();
  });

  testWidgets('Cmd and Ctrl number shortcuts select destinations', (
    tester,
  ) async {
    ScrapnoteSection? selected;
    await pumpShell(
      tester,
      size: const Size(900, 600),
      onSectionChanged: (section) => selected = section,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(selected, ScrapnoteSection.expenses);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(selected, ScrapnoteSection.timeline);

    selected = null;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(selected, ScrapnoteSection.notes);
    expect(tester.takeException(), isNull);
  });
}
