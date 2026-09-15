import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/features/expenses/expense_controller.dart';
import 'package:scrapnote/features/expenses/expense_record.dart';
import 'package:scrapnote/features/expenses/expense_repository.dart';
import 'package:scrapnote/features/expenses/expense_settings.dart';

void main() {
  test('amounts use exact minor units and reject invalid formats', () {
    expect(parseExpenseAmount('1,250', ExpenseCurrency.krw), 1250);
    expect(parseExpenseAmount('12.34', ExpenseCurrency.usd), 1234);
    expect(parseExpenseAmount('0.01', ExpenseCurrency.usd), 1);
    for (final input in ['0', '-10', '1,2', '1.234', 'abc']) {
      expect(parseExpenseAmount(input, ExpenseCurrency.usd), isNull);
    }
    expect(parseExpenseAmount('1.50', ExpenseCurrency.krw), isNull);
  });

  test('calendar month/week boundaries include leap day and cross years', () {
    final leap = ExpenseRange(DateTime(2024, 2, 29), ExpensePeriod.monthly);
    expect(leap.start, DateTime(2024, 2));
    expect(leap.end, DateTime(2024, 3));
    expect(leap.contains(DateTime(2024, 2, 29)), isTrue);
    expect(leap.contains(DateTime(2024, 3)), isFalse);
    final week = ExpenseRange(DateTime(2026, 1, 1), ExpensePeriod.weekly);
    expect(week.start, DateTime(2025, 12, 29));
    expect(week.end, DateTime(2026, 1, 5));
  });

  test(
    'save, edit, reload, filter, currency totals and trash deletion',
    () async {
      final vault = await Directory.systemTemp.createTemp('expenses-');
      addTearDown(() => vault.delete(recursive: true));
      final controller = ExpenseController(today: DateTime(2026, 9, 14));
      addTearDown(controller.dispose);
      await controller.connect(vault.path);
      await controller.save(
        ExpenseRecord(
          id: 'a',
          date: DateTime(2026, 8, 30),
          merchant: 'Previous',
          amount: 1000,
        ),
      );
      await controller.save(
        ExpenseRecord(
          id: 'b',
          date: DateTime(2026, 9, 14),
          merchant: 'Cafe',
          amount: 4500,
        ),
      );
      await controller.save(
        ExpenseRecord(
          id: 'c',
          date: DateTime(2026, 9, 15),
          merchant: 'Books',
          amount: 1234,
          currency: ExpenseCurrency.usd,
        ),
      );
      expect(controller.visible, hasLength(2));
      expect(controller.total(ExpenseCurrency.krw), 4500);
      expect(controller.total(ExpenseCurrency.usd), 1234);
      expect(controller.previousTotal(ExpenseCurrency.krw), 1000);
      await controller.save(
        ExpenseRecord(
          id: 'b',
          date: DateTime(2026, 9, 14),
          merchant: 'Cafe revised',
          amount: 6000,
          memo: 'With a friend',
        ),
      );
      expect(controller.records, hasLength(3));
      expect(controller.merchants(ExpenseCurrency.krw), {'Cafe revised': 6000});
      final reloaded = await ExpenseRepository(vault).load();
      expect(reloaded.singleWhere((r) => r.id == 'b').memo, 'With a friend');
      expect(reloaded.singleWhere((r) => r.id == 'c').amount, 1234);
      controller.setPeriod(ExpensePeriod.weekly);
      expect(controller.visible, hasLength(2));
      controller.shift(-1);
      expect(controller.visible, isEmpty);
      controller.shift(1);
      await controller.delete(controller.visible.first);
      expect(await ExpenseRepository(vault).load(), hasLength(2));
      expect(await Directory('${vault.path}/.trash/expenses').list().length, 1);
    },
  );

  test(
    'conversion, graph aggregation and settings survive reconnect',
    () async {
      final vault = await Directory.systemTemp.createTemp('expenses-settings-');
      addTearDown(() => vault.delete(recursive: true));
      final controller = ExpenseController(today: DateTime(2026, 9, 14));
      addTearDown(controller.dispose);
      await controller.connect(vault.path);
      expect(controller.settings.krwPerUsd, 1380);
      expect(controller.settings.displayCurrency, ExpenseCurrency.krw);
      for (final record in [
        ExpenseRecord(
          id: 'previous',
          date: DateTime(2026, 8, 15),
          merchant: 'Cafe',
          amount: 200,
          currency: ExpenseCurrency.usd,
        ),
        ExpenseRecord(
          id: 'won',
          date: DateTime(2026, 9, 14),
          merchant: 'Cafe',
          amount: 1380,
        ),
        ExpenseRecord(
          id: 'dollar',
          date: DateTime(2026, 9, 15),
          merchant: 'Cafe',
          amount: 100,
          currency: ExpenseCurrency.usd,
        ),
      ]) {
        await controller.save(record);
      }
      expect(controller.convertedTotal, 2760);
      expect(controller.convertedPreviousTotal, 2760);
      expect(controller.dailySpending, hasLength(30));
      expect(controller.dailySpending[DateTime(2026, 9, 14)], 1380);
      expect(controller.dailySpending[DateTime(2026, 9, 16)], 0);
      expect(controller.spendingByMerchant, {'Cafe': 2760});
      expect(
        await controller.updateSettings(
          const ExpenseSettings(
            krwPerUsd: 1500,
            displayCurrency: ExpenseCurrency.usd,
          ),
        ),
        isTrue,
      );
      expect(controller.convertedTotal, 192);
      expect(controller.convertedPreviousTotal, 200);
      expect(controller.dailySpending.values.reduce((a, b) => a + b), 192);
      expect(controller.spendingByMerchant, {'Cafe': 192});
      for (final rate in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          await controller.updateSettings(ExpenseSettings(krwPerUsd: rate)),
          isFalse,
        );
      }
      expect(controller.settings.krwPerUsd, 1500);
      final reloaded = ExpenseController(today: DateTime(2026, 9, 14));
      addTearDown(reloaded.dispose);
      await reloaded.connect(vault.path);
      expect(reloaded.settings.krwPerUsd, 1500);
      expect(reloaded.settings.displayCurrency, ExpenseCurrency.usd);
      expect(reloaded.convertedTotal, 192);
      expect(reloaded.records.singleWhere((r) => r.id == 'won').amount, 1380);
      expect(reloaded.records.singleWhere((r) => r.id == 'dollar').amount, 100);
      reloaded.setPeriod(ExpensePeriod.weekly);
      expect(reloaded.dailySpending, hasLength(7));
      expect(reloaded.convertedTotal, 192);
      reloaded.shift(1);
      expect(reloaded.convertedTotal, 0);
      expect(reloaded.convertedPreviousTotal, 192);
    },
  );

  test(
    'corrupt data surfaces an error rather than allowing an overwrite',
    () async {
      final vault = await Directory.systemTemp.createTemp('expenses-corrupt-');
      addTearDown(() => vault.delete(recursive: true));
      await Directory('${vault.path}/expenses').create();
      await File('${vault.path}/expenses/bad.json').writeAsString('broken');
      final controller = ExpenseController();
      addTearDown(controller.dispose);
      await controller.connect(vault.path);
      expect(controller.error, isNotNull);
      expect(
        await controller.save(
          ExpenseRecord(
            id: 'new',
            date: DateTime.now(),
            merchant: 'Test',
            amount: 1,
          ),
        ),
        isFalse,
      );
    },
  );
}
