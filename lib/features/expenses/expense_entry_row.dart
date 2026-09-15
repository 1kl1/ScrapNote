import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'expense_record.dart';
import 'expense_merchant_field.dart';

/// Shared column geometry keeps the input row aligned with the ledger.
class ExpenseTableRow extends StatelessWidget {
  const ExpenseTableRow({required this.cells, super.key});
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(
      children: [
        for (var i = 0; i < cells.length; i++)
          if (i == 1 || i == 4)
            Expanded(flex: i == 1 ? 3 : 4, child: _inset(cells[i]))
          else
            SizedBox(
              width: switch (i) {
                0 => 148,
                2 => 128,
                3 => 108,
                _ => 136,
              },
              child: _inset(cells[i]),
            ),
      ],
    ),
  );

  Widget _inset(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: child);
}

class ExpenseCurrencySelect extends StatelessWidget {
  const ExpenseCurrencySelect({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.label,
    super.key,
  });
  final ExpenseCurrency value;
  final ValueChanged<ExpenseCurrency> onChanged;
  final bool enabled;
  final Widget? label;

  @override
  Widget build(BuildContext context) => FSelect<ExpenseCurrency>(
    label: label,
    enabled: enabled,
    control: FSelectControl.lifted(
      value: value,
      onChange: (currency) {
        if (currency != null) onChanged(currency);
      },
    ),
    items: {
      for (final currency in ExpenseCurrency.values) currency.code: currency,
    },
  );
}

class ExpenseEntryRow extends StatefulWidget {
  const ExpenseEntryRow({
    required this.initialDate,
    required this.onSave,
    this.record,
    this.merchantHistory = const [],
    this.enabled = true,
    this.onCancel,
    super.key,
  });
  final List<String> merchantHistory;
  final DateTime initialDate;
  final ExpenseRecord? record;
  final bool enabled;
  final Future<bool> Function(ExpenseRecord) onSave;
  final VoidCallback? onCancel;

  @override
  State<ExpenseEntryRow> createState() => _ExpenseEntryRowState();
}

class _ExpenseEntryRowState extends State<ExpenseEntryRow> {
  late final _date = TextEditingController(
    text: DateFormat(
      'yyyy-MM-dd',
    ).format(widget.record?.date ?? widget.initialDate),
  );
  late final _merchant = FAutocompleteController(text: widget.record?.merchant);
  late final _amount = TextEditingController(
    text: widget.record == null
        ? ''
        : (widget.record!.amount / widget.record!.currency.scale)
              .toStringAsFixed(widget.record!.currency.decimals),
  );
  late final _memo = TextEditingController(text: widget.record?.memo);
  late ExpenseCurrency _currency =
      widget.record?.currency ?? ExpenseCurrency.krw;
  final _merchantFocus = FocusNode();
  bool _saving = false;
  String? _error;
  bool get _enabled => widget.enabled && !_saving;

  @override
  void didUpdateWidget(covariant ExpenseEntryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow period navigation only while the new row is still empty.
    if (widget.record == null &&
        _merchant.text.isEmpty &&
        _amount.text.isEmpty &&
        _memo.text.isEmpty &&
        oldWidget.initialDate != widget.initialDate) {
      _date.text = DateFormat('yyyy-MM-dd').format(widget.initialDate);
    }
  }

  Future<void> _save() async {
    if (!_enabled) return;
    DateTime? date;
    try {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_date.text.trim())) {
        date = DateFormat('yyyy-MM-dd').parseStrict(_date.text.trim());
      }
    } on FormatException {
      date = null;
    }
    final amount = parseExpenseAmount(_amount.text, _currency);
    final error = date == null
        ? 'Enter a valid date: YYYY-MM-DD.'
        : _merchant.text.trim().isEmpty
        ? 'Enter where you spent the money.'
        : amount == null
        ? 'Enter a positive amount${_currency == ExpenseCurrency.krw ? ' in whole won' : ' with up to two decimal places'}.'
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.onSave(
      ExpenseRecord(
        id: widget.record?.id ?? const Uuid().v4(),
        date: date!,
        merchant: _merchant.text.trim(),
        amount: amount!,
        currency: _currency,
        memo: _memo.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved && widget.record == null) {
        _merchant.clear();
        _amount.clear();
        _memo.clear();
      } else if (!saved) {
        _error =
            'Could not save. Your entries are still here; please try again.';
      }
    });
    if (saved && widget.record == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _merchantFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _merchant.dispose();
    _amount.dispose();
    _memo.dispose();
    _merchantFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      if (widget.onCancel != null)
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_enabled) widget.onCancel!();
        },
    },
    child: FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpenseTableRow(
            cells: [
              _field('date', _date, 'YYYY-MM-DD'),
              ExpenseMerchantField(
                fieldKey: ValueKey('${_prefix}merchant'),
                controller: _merchant,
                history: widget.merchantHistory,
                focusNode: _merchantFocus,
                enabled: _enabled,
                onSubmit: (_) => _save(),
              ),
              _field(
                'amount',
                _amount,
                _currency == ExpenseCurrency.krw ? '0' : '0.00',
                number: true,
              ),
              ExpenseCurrencySelect(
                key: ValueKey('${_prefix}currency'),
                value: _currency,
                enabled: _enabled,
                onChanged: (value) => setState(() => _currency = value),
              ),
              _field('memo', _memo, 'Memo (optional)'),
              Row(
                children: [
                  Expanded(
                    child: FButton(
                      key: ValueKey('${_prefix}save'),
                      onPress: _enabled ? _save : null,
                      child: Text(_saving ? '…' : 'Save'),
                    ),
                  ),
                  if (widget.onCancel != null)
                    FButton.icon(
                      variant: FButtonVariant.ghost,
                      semanticsLabel: 'Cancel editing',
                      onPress: _enabled ? widget.onCancel : null,
                      child: const Icon(FLucideIcons.x, size: 14),
                    ),
                ],
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _error!,
                style: TextStyle(
                  color: context.theme.colors.error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  String get _prefix => widget.record == null ? 'expense-' : 'edit-expense-';
  Widget _field(
    String name,
    TextEditingController controller,
    String hint, {
    FocusNode? focus,
    bool number = false,
  }) => Semantics(
    label: 'Expense $name',
    child: FTextField(
      key: ValueKey('$_prefix$name'),
      control: FTextFieldControl.managed(controller: controller),
      focusNode: focus,
      enabled: _enabled,
      hint: hint,
      textAlign: number ? TextAlign.right : TextAlign.left,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onSubmit: (_) => _save(),
    ),
  );
}
