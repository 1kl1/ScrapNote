import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'expense_charts.dart';
import 'expense_controller.dart';
import 'expense_record.dart';
import 'expense_summary_settings.dart';

class ExpenseDashboard extends StatelessWidget {
  const ExpenseDashboard({
    required this.controller,
    required this.expanded,
    required this.onToggle,
    super.key,
  });
  final ExpenseController controller;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final currency = controller.settings.displayCurrency;
    return ColoredBox(
      color: colors.muted,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        'TOTAL · ${currency.code}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${controller.visible.length} records',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                FButton(
                  key: const ValueKey('expand-expense-dashboard'),
                  variant: FButtonVariant.ghost,
                  mainAxisSize: MainAxisSize.min,
                  onPress: onToggle,
                  suffix: Icon(
                    expanded
                        ? FLucideIcons.chevronDown
                        : FLucideIcons.chevronUp,
                    size: 14,
                  ),
                  child: Text(expanded ? 'Collapse' : 'Expand'),
                ),
              ],
            ),
            Wrap(
              spacing: 20,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  expenseMoney(controller.convertedTotal, currency),
                  key: const ValueKey('expense-converted-total'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '1 USD = ${NumberFormat('#,##0.##').format(controller.settings.krwPerUsd)} KRW',
                  style: TextStyle(fontSize: 11, color: colors.mutedForeground),
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              ExpenseSummarySettings(controller: controller),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Totals and charts use this rate. Original amounts are preserved.',
                  style: TextStyle(fontSize: 11, color: colors.mutedForeground),
                ),
              ),
              ExpenseCharts(controller: controller),
            ],
          ],
        ),
      ),
    );
  }
}
