import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/features/expenses/expense_controller.dart';
import 'package:scrapnote/features/expenses/expense_merchant_field.dart';
import 'package:scrapnote/features/expenses/expense_record.dart';

void main() {
  test(
    'all history is deduplicated case-insensitively and newest dates win',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'merchant-history-',
      );
      final controller = ExpenseController(today: DateTime(2026, 9, 1));
      try {
        await controller.connect(directory.path);
        for (final (index, name) in [
          ' Cafe ',
          'CAFE',
          '동네 카페',
          'Bookstore',
        ].indexed) {
          await controller.save(
            ExpenseRecord(
              id: 'record$index',
              date: DateTime(2026, 8, index + 1),
              merchant: name,
              amount: 1000,
              currency: ExpenseCurrency.krw,
              memo: '',
            ),
          );
        }
        controller.shift(1);
        expect(controller.visible, isEmpty);
        expect(controller.merchantHistory, ['Bookstore', '동네 카페', 'CAFE']);
        expect(filterMerchants(controller.merchantHistory, 'cAf'), ['CAFE']);
        expect(filterMerchants(controller.merchantHistory, '카페'), ['동네 카페']);
        expect(
          filterMerchants(controller.merchantHistory, 'new place'),
          isEmpty,
        );
      } finally {
        controller.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'tap completes a previous Where while arbitrary input stays editable',
    (tester) async {
      final controller = FAutocompleteController();
      addTearDown(controller.dispose);
      var submissions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: ScrapnoteTheme.foruiTheme,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: ExpenseMerchantField(
                    controller: controller,
                    fieldKey: const ValueKey('where'),
                    history: const ['동네 카페', 'Cafe Seoul', 'Bookstore'],
                    onSubmit: (_) => submissions++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('where')), '카페');
      await tester.pumpAndSettle();
      expect(find.text('동네 카페'), findsOneWidget);
      await tester.tap(find.text('동네 카페'));
      await tester.pumpAndSettle();
      expect(controller.text, '동네 카페');
      expect(submissions, 0);
      await tester.enterText(find.byKey(const ValueKey('where')), '새로운 식당');
      await tester.pumpAndSettle();
      expect(controller.text, '새로운 식당');
      expect(find.text('Bookstore'), findsNothing);
    },
  );

  testWidgets('keyboard suggestion navigation does not submit the record', (
    tester,
  ) async {
    final controller = FAutocompleteController();
    addTearDown(controller.dispose);
    var submissions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: ExpenseMerchantField(
                  controller: controller,
                  fieldKey: const ValueKey('where'),
                  history: const ['Cafe Seoul', 'Cafe West'],
                  onSubmit: (_) => submissions++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('where')), 'Cafe');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, anyOf('Cafe Seoul', 'Cafe West'));
    expect(submissions, 0);
  });
}
