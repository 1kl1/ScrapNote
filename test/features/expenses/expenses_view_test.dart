import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/features/expenses/expense_controller.dart';
import 'package:scrapnote/features/expenses/expense_record.dart';
import 'package:scrapnote/features/expenses/expenses_view.dart';

Finder field(String name) => find.byKey(ValueKey(name));

Future<ExpenseController> setup(
  WidgetTester tester, {
  bool connect = true,
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final vault = Directory.systemTemp.createTempSync('expense-ui-');
  addTearDown(() => vault.deleteSync(recursive: true));
  final controller = ExpenseController(today: DateTime(2026, 9, 14));
  addTearDown(controller.dispose);
  if (connect) await tester.runAsync(() => controller.connect(vault.path));
  await tester.pumpWidget(
    MaterialApp(
      theme: ScrapnoteTheme.materialTheme,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      home: FTheme(
        data: ScrapnoteTheme.foruiTheme,
        child: Scaffold(body: ExpensesView(controller: controller)),
      ),
    ),
  );
  return controller;
}

Future<void> settleSave(
  WidgetTester tester,
  ExpenseController controller,
) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (!controller.saving) break;
  }
  await tester.pumpAndSettle();
}

Future<void> selectCurrency(
  WidgetTester tester,
  String key,
  String code,
) async {
  await tester.tap(
    find.descendant(of: field(key), matching: find.byType(EditableText)),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byWidgetPredicate(
      (widget) =>
          widget is FSelectItem<ExpenseCurrency> && widget.value.code == code,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'persistent cells save USD with Enter, preserve date/currency, and edit inline',
    (tester) async {
      final controller = await setup(tester);
      expect(find.text('New record'), findsNothing);
      expect(field('expense-merchant'), findsOneWidget);
      await tester.enterText(field('expense-date'), '2026-09-15');
      await tester.enterText(field('expense-merchant'), 'Bookstore');
      await selectCurrency(tester, 'expense-currency', 'USD');
      await tester.enterText(field('expense-amount'), '12.34');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.enterText(field('expense-memo'), 'A gift');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleSave(tester, controller);
      expect(controller.records, hasLength(1));
      final record = controller.records.single;
      expect(record.currency, ExpenseCurrency.usd);
      expect(record.amount, 1234);
      expect(record.date, DateTime(2026, 9, 15));
      expect(record.memo, 'A gift');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: field('expense-date'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '2026-09-15',
      );
      expect(find.text('12.34'), findsNothing);
      expect(
        tester
            .widget<FAutocomplete<String>>(field('expense-merchant'))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.enterText(field('expense-merchant'), 'Coffee');
      await tester.enterText(field('expense-amount'), '3.50');
      await tester.tap(field('expense-save'));
      await settleSave(tester, controller);
      expect(controller.records, hasLength(2));
      expect(controller.records.first.currency, ExpenseCurrency.usd);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bookstore'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(field('edit-expense-amount'), '20.50');
      await tester.tap(field('edit-expense-save'));
      await settleSave(tester, controller);
      expect(
        controller.records.singleWhere((r) => r.id == record.id).amount,
        2050,
      );
      expect(controller.records, hasLength(2));
      await tester.tap(find.byTooltip('Delete record').first);
      await settleSave(tester, controller);
      expect(controller.records, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid dates and amounts do not save; failed saves retain draft',
    (tester) async {
      final controller = await setup(tester, connect: false);
      await tester.enterText(field('expense-date'), '2026-02-30');
      await tester.enterText(field('expense-merchant'), 'Cafe');
      await tester.enterText(field('expense-amount'), '10');
      await tester.tap(field('expense-save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid date: YYYY-MM-DD.'), findsOneWidget);
      await tester.enterText(field('expense-date'), '2026-09-15');
      await tester.enterText(field('expense-amount'), '1.50');
      await tester.tap(field('expense-save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a positive amount in whole won.'),
        findsOneWidget,
      );
      await tester.enterText(field('expense-amount'), '10');
      await tester.tap(field('expense-save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not save. Your entries are still here; please try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cafe'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(controller.records, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('combined total, editable exchange rate, currency and charts', (
    tester,
  ) async {
    final controller = await setup(tester);
    await tester.runAsync(() async {
      await controller.save(
        ExpenseRecord(
          id: 'krw',
          date: DateTime(2026, 9, 15),
          merchant: 'Cafe',
          amount: 1380,
        ),
      );
      await controller.save(
        ExpenseRecord(
          id: 'usd',
          date: DateTime(2026, 9, 15),
          merchant: 'Books',
          amount: 100,
          currency: ExpenseCurrency.usd,
        ),
      );
    });
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(field('expense-converted-total')).data,
      '₩2,760',
    );
    await tester.tap(field('expand-expense-dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Daily spending · KRW'), findsOneWidget);
    expect(find.text('Spending by place · KRW'), findsOneWidget);
    expect(find.text('Period comparison · KRW'), findsOneWidget);
    await tester.enterText(field('expense-exchange-rate'), '0');
    await tester.tap(field('apply-expense-settings'));
    await tester.pumpAndSettle();
    expect(controller.settings.krwPerUsd, 1380);
    expect(find.textContaining('Enter a rate greater than 0'), findsOneWidget);
    await tester.enterText(field('expense-exchange-rate'), '1500');
    await selectCurrency(tester, 'expense-display-currency', 'USD');
    await tester.tap(field('apply-expense-settings'));
    await settleSave(tester, controller);
    expect(controller.settings.krwPerUsd, 1500);
    expect(controller.settings.displayCurrency, ExpenseCurrency.usd);
    expect(
      tester.widget<Text>(field('expense-converted-total')).data,
      '\$1.92',
    );
    expect(find.text('Daily spending · USD'), findsOneWidget);
    await tester.tap(field('expenses-weekly'));
    await tester.pumpAndSettle();
    expect(controller.period, ExpensePeriod.weekly);
    expect(controller.dailySpending, hasLength(7));
    expect(find.text('This week'), findsOneWidget);
    await tester.tap(field('expand-expense-dashboard'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(field('expense-converted-total')).data,
      '\$1.92',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout opens a touch form and expands an empty chart', (
    tester,
  ) async {
    await setup(tester, size: const Size(520, 800));
    await tester.tap(field('mobile-new-expense'));
    await tester.pumpAndSettle();
    expect(field('expense-merchant'), findsOneWidget);
    expect(field('save-expense').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(field('expand-expense-dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('No spending in this period'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
