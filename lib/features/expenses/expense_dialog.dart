import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/scrapnote_theme.dart';
import 'expense_record.dart';
import 'expense_merchant_field.dart';

class ExpenseDialog extends StatefulWidget {
  const ExpenseDialog({
    this.record,
    required this.onSave,
    this.merchantHistory = const [],
    super.key,
  });
  final ExpenseRecord? record;
  final List<String> merchantHistory;
  final Future<bool> Function(ExpenseRecord) onSave;
  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  late final _merchant = FAutocompleteController(text: widget.record?.merchant);
  late final _amount = TextEditingController(
    text: widget.record == null
        ? ''
        : (widget.record!.amount / widget.record!.currency.scale)
              .toStringAsFixed(widget.record!.currency.decimals),
  );
  late final _memo = TextEditingController(text: widget.record?.memo);
  late DateTime _date = widget.record?.date ?? DateTime.now();
  late ExpenseCurrency _currency =
      widget.record?.currency ?? ExpenseCurrency.krw;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    final amount = parseExpenseAmount(_amount.text, _currency);
    if (_merchant.text.trim().isEmpty || amount == null) {
      setState(
        () => _error = _merchant.text.trim().isEmpty
            ? 'Enter where you spent the money.'
            : 'Enter a positive amount${_currency == ExpenseCurrency.krw ? ' in whole won' : ' with up to two decimal places'}.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final record = ExpenseRecord(
      id: widget.record?.id ?? const Uuid().v4(),
      date: DateTime(_date.year, _date.month, _date.day),
      merchant: _merchant.text.trim(),
      amount: amount,
      currency: _currency,
      memo: _memo.text.trim(),
    );
    final saved = await widget.onSave(record);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error =
            'Could not save. Your entries are still here; please try again.';
      });
    }
  }

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FTheme(
    data: ScrapnoteTheme.forContext(context),
    child: PopScope(
      canPop: !_saving,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
        },
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          title: Text(widget.record == null ? 'New expense' : 'Edit expense'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FDateField.calendar(
                    key: const ValueKey('expense-date'),
                    label: const Text('Date'),
                    enabled: !_saving,
                    selectionControl: FDateSelectionControl.liftedSingle(
                      value: DateTime.utc(_date.year, _date.month, _date.day),
                      toggleable: false,
                      onChange: (value) {
                        if (value != null) setState(() => _date = value);
                      },
                    ),
                    format: (_, value, _) =>
                        DateFormat('yyyy-MM-dd').format(value),
                  ),
                  const SizedBox(height: 16),
                  ExpenseMerchantField(
                    fieldKey: const ValueKey('expense-merchant'),
                    controller: _merchant,
                    history: widget.merchantHistory,
                    label: const Text('Where'),
                    hint: 'Store, restaurant, service…',
                    autofocus: true,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    runSpacing: 8,
                    children: [
                      for (final currency in ExpenseCurrency.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FButton(
                            mainAxisSize: MainAxisSize.min,
                            variant: _currency == currency
                                ? FButtonVariant.outline
                                : FButtonVariant.ghost,
                            onPress: _saving
                                ? null
                                : () => setState(() => _currency = currency),
                            child: Text(currency.code),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FTextField(
                    key: const ValueKey('expense-amount'),
                    control: FTextFieldControl.managed(controller: _amount),
                    label: Text('Amount · ${_currency.code}'),
                    hint: _currency == ExpenseCurrency.krw ? '0' : '0.00',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_saving,
                    onSubmit: (_) => _save(),
                  ),
                  const SizedBox(height: 16),
                  FTextField(
                    key: const ValueKey('expense-memo'),
                    control: FTextFieldControl.managed(controller: _memo),
                    label: const Text('Memo · optional'),
                    enabled: !_saving,
                    maxLines: 2,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            FButton(
              variant: FButtonVariant.ghost,
              onPress: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FButton(
              key: const ValueKey('save-expense'),
              onPress: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save expense'),
            ),
          ],
        ),
      ),
    ),
  );
}
