import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'expense_controller.dart';
import 'expense_entry_row.dart';
import 'expense_record.dart';
import 'expense_settings.dart';

class ExpenseSummarySettings extends StatefulWidget {
  const ExpenseSummarySettings({required this.controller, super.key});
  final ExpenseController controller;

  @override
  State<ExpenseSummarySettings> createState() => _ExpenseSummarySettingsState();
}

class _ExpenseSummarySettingsState extends State<ExpenseSummarySettings> {
  late final _rate = TextEditingController(text: _rateText);
  late ExpenseCurrency _currency = widget.controller.settings.displayCurrency;
  String? _error;
  String get _rateText {
    final rate = widget.controller.settings.krwPerUsd;
    return rate == rate.truncateToDouble()
        ? rate.toInt().toString()
        : rate.toString();
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final rate = double.tryParse(_rate.text.trim());
    if (rate == null || !ExpenseSettings.validRate(rate)) {
      setState(
        () => _error = 'Enter a rate greater than 0 and at most 1,000,000,000.',
      );
      return;
    }
    final saved = await widget.controller.updateSettings(
      ExpenseSettings(krwPerUsd: rate, displayCurrency: _currency),
    );
    if (mounted) {
      setState(
        () => _error = saved
            ? null
            : 'Could not save settings. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 180,
            child: FTextField(
              key: const ValueKey('expense-exchange-rate'),
              label: const Text('1 USD in KRW'),
              enabled: !widget.controller.saving,
              control: FTextFieldControl.managed(controller: _rate),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onSubmit: (_) => _apply(),
            ),
          ),
          SizedBox(
            width: 145,
            child: ExpenseCurrencySelect(
              key: const ValueKey('expense-display-currency'),
              label: const Text('Display currency'),
              value: _currency,
              enabled: !widget.controller.saving,
              onChanged: (value) => setState(() => _currency = value),
            ),
          ),
          FButton(
            key: const ValueKey('apply-expense-settings'),
            mainAxisSize: MainAxisSize.min,
            variant: FButtonVariant.outline,
            onPress: widget.controller.saving ? null : _apply,
            child: const Text('Apply'),
          ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _error!,
            style: TextStyle(color: context.theme.colors.error, fontSize: 12),
          ),
        ),
    ],
  );
}
