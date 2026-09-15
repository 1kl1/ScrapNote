import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'expense_controller.dart';
import 'expense_record.dart';

class ExpenseCharts extends StatelessWidget {
  const ExpenseCharts({required this.controller, super.key});
  final ExpenseController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final daily = _DailyChart(controller: controller);
      final places = _PlacesChart(controller: controller);
      return constraints.maxWidth < 650
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [daily, const SizedBox(height: 24), places],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: daily),
                const SizedBox(width: 32),
                Expanded(flex: 2, child: places),
              ],
            );
    },
  );
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.controller});
  final ExpenseController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.dailySpending.entries.toList();
    final currency = controller.settings.displayCurrency;
    final maximum = entries.fold(0.0, (n, e) => math.max(n, e.value));
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Daily spending · ${currency.code}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          maximum == 0
              ? 'No spending in this period'
              : 'Peak ${expenseMoney(maximum, currency)}',
          style: TextStyle(fontSize: 11, color: colors.mutedForeground),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final entry in entries)
                Expanded(
                  child: Tooltip(
                    message:
                        '${DateFormat('MMM d').format(entry.key)} · ${expenseMoney(entry.value, currency)}',
                    child: Semantics(
                      label:
                          '${DateFormat('yyyy-MM-dd').format(entry.key)}: ${expenseMoney(entry.value, currency)}',
                      child: Container(
                        height: maximum == 0 || entry.value == 0
                            ? 1
                            : math.max(2, entry.value / maximum * 110),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: entry.value == 0
                            ? colors.border
                            : colors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < entries.length; i++)
              Expanded(
                child: Text(
                  entries.length == 7
                      ? DateFormat('E').format(entries[i].key)
                      : i == 0 || (i + 1) % 5 == 0 || i == entries.length - 1
                      ? '${entries[i].key.day}'
                      : '',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: colors.mutedForeground),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Period comparison · ${currency.code}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        _ValueBars(
          values: {
            'This ${controller.period == ExpensePeriod.monthly ? 'month' : 'week'}':
                controller.convertedTotal,
            'Previous ${controller.period == ExpensePeriod.monthly ? 'month' : 'week'}':
                controller.convertedPreviousTotal,
          },
          currency: currency,
        ),
      ],
    );
  }
}

class _PlacesChart extends StatelessWidget {
  const _PlacesChart({required this.controller});
  final ExpenseController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.spendingByMerchant.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = {for (final e in entries.take(5)) e.key: e.value};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Spending by place · ${controller.settings.displayCurrency.code}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Add a record to see your top places.',
              style: TextStyle(
                fontSize: 12,
                color: context.theme.colors.mutedForeground,
              ),
            ),
          )
        else ...[
          _ValueBars(
            values: top,
            currency: controller.settings.displayCurrency,
          ),
          if (entries.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${entries.length - 5} more places · ${expenseMoney(entries.skip(5).fold(0.0, (n, e) => n + e.value), controller.settings.displayCurrency)}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _ValueBars extends StatelessWidget {
  const _ValueBars({required this.values, required this.currency});
  final Map<String, double> values;
  final ExpenseCurrency currency;

  @override
  Widget build(BuildContext context) {
    final maximum = values.values.fold(0.0, math.max);
    final colors = context.theme.colors;
    return Column(
      children: [
        for (final entry in values.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      expenseMoney(entry.value, currency),
                      style: const TextStyle(
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                SizedBox(
                  height: 6,
                  child: ColoredBox(
                    color: colors.border,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: maximum == 0 ? 0 : entry.value / maximum,
                        child: ColoredBox(
                          color: colors.primary,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
