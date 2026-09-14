import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/core/design/scrapnote_tokens.dart';
import 'package:scrapnote/features/notes/notes_view.dart';

void main() {
  testWidgets('uses a full-height explorer and a 38px document tab strip', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NotesView(vaultPath: '/Users/test/Scrapnote')),
      ),
    );

    expect(
      tester.getSize(find.byKey(NotesView.hierarchyPaneKey)),
      const Size(ScrapnoteTokens.explorerPaneWidth, 800),
    );
    expect(
      tester.getSize(find.byKey(NotesView.tabStripKey)).height,
      ScrapnoteTokens.tabStripHeight,
    );
    expect(find.text('No folders yet'), findsOneWidget);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(
      find.text(
        'Note editing is not available yet. This view does not load or save note files.',
      ),
      findsOneWidget,
    );
    expect(find.text('AVAILABLE SCRAPS'), findsNothing);
    expect(find.text('Arrange scraps into lasting documents'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('collapses the hierarchy before the editor below 760px', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NotesView(vaultPath: '/Users/test/Scrapnote')),
      ),
    );

    expect(find.byKey(NotesView.hierarchyPaneKey), findsNothing);
    expect(find.byKey(NotesView.tabStripKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(NotesView.tabStripKey)).height,
      ScrapnoteTokens.tabStripHeight,
    );
    expect(find.text('No open notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows one vault setup prompt instead of workspace chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NotesView())),
    );

    expect(find.text('Choose a local vault'), findsOneWidget);
    expect(
      find.text('Notes can open after a vault folder is selected.'),
      findsOneWidget,
    );
    expect(find.byKey(NotesView.hierarchyPaneKey), findsNothing);
    expect(find.byKey(NotesView.tabStripKey), findsNothing);
  });
}
