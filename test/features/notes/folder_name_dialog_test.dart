import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/features/notes/folder_name_dialog.dart';

void main() {
  testWidgets(
    'Enter closes the dialog once and controller survives route animation',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: ScrapnoteTheme.foruiTheme,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<String>(
                      context: context,
                      builder: (_) => const FolderNameDialog(),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'New folder');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, 'New folder');
      expect(find.byType(FolderNameDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
