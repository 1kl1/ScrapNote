import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../core/design/scrapnote_tokens.dart';
import 'expense_controller.dart';
import 'expense_dashboard.dart';
import 'expense_entry_row.dart';
import 'expense_record.dart';
import 'expense_dialog.dart';

class ExpensesView extends StatefulWidget {
  const ExpensesView({required this.controller, super.key});
  final ExpenseController controller;
  @override
  State<ExpensesView> createState() => _ExpensesViewState();
}

class _ExpensesViewState extends State<ExpensesView> {
  bool _expanded = false;
  String? _editingId;
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final _summaryScroll = ScrollController();
  ExpenseController get controller => widget.controller;

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    _summaryScroll.dispose();
    super.dispose();
  }

  void _shift(int direction) {
    if (_vertical.hasClients) _vertical.jumpTo(0);
    controller.shift(direction);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final range = controller.range;
      final last = DateTime(range.end.year, range.end.month, range.end.day - 1);
      final periodTitle = controller.period == ExpensePeriod.monthly
          ? DateFormat('MMMM yyyy').format(range.start)
          : '${DateFormat('MMM d').format(range.start)} – ${DateFormat('MMM d, yyyy').format(last)}';
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Expenses',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  for (final period in ExpensePeriod.values)
                    FButton(
                      key: ValueKey('expenses-${period.name}'),
                      mainAxisSize: MainAxisSize.min,
                      variant: controller.period == period
                          ? FButtonVariant.outline
                          : FButtonVariant.ghost,
                      onPress: () {
                        controller.setPeriod(period);
                        if (_vertical.hasClients) _vertical.jumpTo(0);
                      },
                      child: Text(
                        period == ExpensePeriod.monthly ? 'Monthly' : 'Weekly',
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  _icon(
                    'Previous period',
                    FLucideIcons.chevronLeft,
                    () => _shift(-1),
                  ),
                  Expanded(
                    child: Text(
                      periodTitle,
                      key: const ValueKey('expense-period-title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  _icon(
                    'Next period',
                    FLucideIcons.chevronRight,
                    () => _shift(1),
                  ),
                  const SizedBox(width: 12),
                  FButton(
                    mainAxisSize: MainAxisSize.min,
                    variant: FButtonVariant.ghost,
                    onPress: controller.today,
                    child: const Text('Today'),
                  ),
                ],
              ),
            ),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: controller.loading
                  ? const Center(child: CircularProgressIndicator())
                  : constraints.maxWidth < 700
                  ? _mobileList()
                  : _table(constraints.maxWidth),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * (_expanded ? 0.64 : 0.30),
              ),
              child: Scrollbar(
                controller: _summaryScroll,
                child: SingleChildScrollView(
                  controller: _summaryScroll,
                  primary: false,
                  child: ExpenseDashboard(
                    controller: controller,
                    expanded: _expanded,
                    onToggle: () => setState(() => _expanded = !_expanded),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _editMobile([ExpenseRecord? record]) => showDialog<void>(
    context: context,
    builder: (_) => ExpenseDialog(
      record: record,
      onSave: controller.save,
      merchantHistory: controller.merchantHistory,
    ),
  );

  Widget _mobileList() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: FButton(
          key: const ValueKey('mobile-new-expense'),
          onPress: controller.saving ? null : () => _editMobile(),
          prefix: const Icon(FLucideIcons.plus),
          child: const Text('지출 추가'),
        ),
      ),
      Expanded(
        child: controller.visible.isEmpty
            ? const Center(child: Text('지출을 추가해 기록을 시작하세요.'))
            : ListView.builder(
                key: const ValueKey('mobile-expense-list'),
                itemCount: controller.visible.length,
                itemBuilder: (context, index) {
                  final record = controller.visible[index];
                  return FItem(
                    onPress: controller.saving
                        ? null
                        : () => _editMobile(record),
                    title: Text(
                      record.merchant,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${DateFormat('MM/dd').format(record.date)} · ${expenseMoney(record.amount, record.currency)}'
                      '${record.memo.isEmpty ? '' : '\n${record.memo}'}',
                    ),
                    suffix: SizedBox.square(
                      dimension: 48,
                      child: _icon(
                        'Delete record',
                        FLucideIcons.trash2,
                        () => controller.delete(record),
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );

  Widget _table(double width) {
    final records = controller.visible;
    final clock = DateTime.now();
    final now = DateTime(clock.year, clock.month, clock.day);
    final initialDate = controller.range.contains(now)
        ? now
        : controller.range.start;
    return Scrollbar(
      controller: _horizontal,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(width, 1000),
          child: Column(
            children: [
              ColoredBox(
                color: ScrapnoteTokens.paperRaised,
                child: ExpenseTableRow(
                  cells: [
                    for (final title in [
                      'DATE',
                      'WHERE',
                      'AMOUNT',
                      'CURRENCY',
                      'MEMO',
                      '',
                    ])
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 10,
                          color: ScrapnoteTokens.mutedInk,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ExpenseEntryRow(
                merchantHistory: controller.merchantHistory,
                key: const ValueKey('expense-draft'),
                initialDate: initialDate,
                enabled: !controller.saving && !controller.loading,
                onSave: controller.save,
              ),
              const Divider(height: 1),
              Expanded(
                child: records.isEmpty
                    ? const Center(
                        child: Text(
                          'Start in the row above. Press Enter to save.\nTab moves between cells.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: ScrapnoteTokens.mutedInk,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : Scrollbar(
                        controller: _vertical,
                        child: ListView.builder(
                          key: const ValueKey('expense-records'),
                          controller: _vertical,
                          primary: false,
                          itemCount: records.length,
                          itemBuilder: (context, index) {
                            final record = records[index];
                            if (_editingId == record.id) {
                              return ExpenseEntryRow(
                                merchantHistory: controller.merchantHistory,
                                key: ValueKey('edit-${record.id}'),
                                initialDate: record.date,
                                record: record,
                                enabled: !controller.saving,
                                onCancel: () =>
                                    setState(() => _editingId = null),
                                onSave: (value) async {
                                  final saved = await controller.save(value);
                                  if (saved && mounted) {
                                    setState(() => _editingId = null);
                                  }
                                  return saved;
                                },
                              );
                            }
                            return Material(
                              key: ValueKey('expense-row-${record.id}'),
                              color: index.isEven
                                  ? ScrapnoteTokens.paper
                                  : ScrapnoteTokens.paperRaised,
                              child: InkWell(
                                onTap: controller.saving
                                    ? null
                                    : () => setState(
                                        () => _editingId = record.id,
                                      ),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 50,
                                  ),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: ScrapnoteTokens.rule,
                                      ),
                                    ),
                                  ),
                                  child: ExpenseTableRow(
                                    cells: [
                                      _cell(
                                        DateFormat(
                                          'yyyy-MM-dd',
                                        ).format(record.date),
                                      ),
                                      _cell(record.merchant),
                                      _cell(
                                        expenseMoney(
                                          record.amount,
                                          record.currency,
                                        ),
                                        right: true,
                                      ),
                                      _cell(record.currency.code),
                                      _cell(record.memo),
                                      Row(
                                        children: [
                                          _icon(
                                            'Edit record',
                                            FLucideIcons.pencil,
                                            () => setState(
                                              () => _editingId = record.id,
                                            ),
                                          ),
                                          _icon(
                                            'Delete record',
                                            FLucideIcons.trash2,
                                            () => controller.delete(record),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(String text, {bool right = false}) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: right ? TextAlign.right : TextAlign.left,
    style: const TextStyle(
      fontSize: 13,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );

  Widget _icon(String label, IconData icon, VoidCallback callback) => Tooltip(
    message: label,
    child: FButton.icon(
      variant: FButtonVariant.ghost,
      semanticsLabel: label,
      onPress: controller.saving ? null : callback,
      child: Icon(icon, size: 14),
    ),
  );
}
