import 'dart:io';
import 'package:flutter/foundation.dart';
import 'expense_record.dart';
import 'expense_repository.dart';
import 'expense_settings.dart';

class ExpenseController extends ChangeNotifier {
  ExpenseController({DateTime? today}) : anchor = today ?? DateTime.now();
  DateTime anchor;
  ExpensePeriod period = ExpensePeriod.monthly;
  List<ExpenseRecord> _records = [];
  ExpenseRepository? _repository;
  bool loading = false;
  bool saving = false;
  String? error;
  int _generation = 0;
  ExpenseSettings settings = const ExpenseSettings();

  double get convertedTotal =>
      visible.fold(0.0, (sum, record) => sum + settings.convert(record));

  double get convertedPreviousTotal {
    final previous = ExpenseRange(
      period == ExpensePeriod.monthly
          ? DateTime(anchor.year, anchor.month - 1)
          : DateTime(anchor.year, anchor.month, anchor.day - 7),
      period,
    );
    return _records
        .where((r) => previous.contains(r.date))
        .fold(0.0, (sum, record) => sum + settings.convert(record));
  }

  Map<DateTime, double> get dailySpending {
    final current = range;
    final values = <DateTime, double>{};
    for (
      var date = current.start;
      date.isBefore(current.end);
      date = DateTime(date.year, date.month, date.day + 1)
    ) {
      values[date] = 0;
    }
    for (final record in visible) {
      final date = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      values[date] = values[date]! + settings.convert(record);
    }
    return values;
  }

  Map<String, double> get spendingByMerchant {
    final values = <String, double>{};
    for (final record in visible) {
      values.update(
        record.merchant,
        (n) => n + settings.convert(record),
        ifAbsent: () => settings.convert(record),
      );
    }
    return values;
  }

  Future<bool> updateSettings(ExpenseSettings value) {
    if (!ExpenseSettings.validRate(value.krwPerUsd)) return Future.value(false);
    return _mutate(() async {
      await _repository!.saveSettings(value);
      settings = value;
    });
  }

  /// Uses all history, including records outside the currently selected period.
  List<String> get merchantHistory {
    final recent = [..._records]
      ..sort((a, b) {
        final date = b.date.compareTo(a.date);
        return date == 0 ? b.id.compareTo(a.id) : date;
      });
    final seen = <String>{};
    return [
      for (final record in recent)
        if (record.merchant.trim().isNotEmpty &&
            seen.add(record.merchant.trim().toLowerCase()))
          record.merchant.trim(),
    ];
  }

  List<ExpenseRecord> get records => List.unmodifiable(_records);
  ExpenseRange get range => ExpenseRange(anchor, period);
  List<ExpenseRecord> get visible =>
      _records.where((r) => range.contains(r.date)).toList()..sort((a, b) {
        final date = b.date.compareTo(a.date);
        return date == 0 ? a.id.compareTo(b.id) : date;
      });
  int total(ExpenseCurrency currency) => visible
      .where((r) => r.currency == currency)
      .fold(0, (sum, record) => sum + record.amount);
  Map<String, int> merchants(ExpenseCurrency currency) {
    final result = <String, int>{};
    for (final record in visible.where((r) => r.currency == currency)) {
      result.update(
        record.merchant,
        (n) => n + record.amount,
        ifAbsent: () => record.amount,
      );
    }
    return result;
  }

  int previousTotal(ExpenseCurrency currency) {
    final previous = ExpenseRange(
      period == ExpensePeriod.monthly
          ? DateTime(anchor.year, anchor.month - 1)
          : DateTime(anchor.year, anchor.month, anchor.day - 7),
      period,
    );
    return _records
        .where((r) => r.currency == currency && previous.contains(r.date))
        .fold(0, (n, r) => n + r.amount);
  }

  Future<void> reloadAfterSync() async {
    final repository = _repository;
    if (repository == null) return;
    _records = await repository.load();
    settings = await repository.loadSettings();
    notifyListeners();
  }

  Future<void> connect(String vaultPath) async {
    if (_repository?.root.path == vaultPath) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    _records = [];
    settings = const ExpenseSettings();
    _repository = null;
    notifyListeners();
    final repository = ExpenseRepository(Directory(vaultPath));
    try {
      final loaded = await repository.load();
      final loadedSettings = await repository.loadSettings();
      if (generation != _generation) return;
      _repository = repository;
      _records = loaded;
      settings = loadedSettings;
    } catch (e) {
      if (generation == _generation) error = '지출 기록을 읽지 못했습니다. $e';
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void setPeriod(ExpensePeriod value) {
    period = value;
    notifyListeners();
  }

  void shift(int direction) {
    anchor = period == ExpensePeriod.monthly
        ? DateTime(anchor.year, anchor.month + direction)
        : DateTime(anchor.year, anchor.month, anchor.day + 7 * direction);
    notifyListeners();
  }

  void today() {
    anchor = DateTime.now();
    notifyListeners();
  }

  Future<bool> save(ExpenseRecord record) => _mutate(() async {
    await _repository!.save(record);
    _records = [record, ..._records.where((r) => r.id != record.id)];
    anchor = record.date;
  });
  Future<bool> delete(ExpenseRecord record) => _mutate(() async {
    await _repository!.delete(record);
    _records = _records.where((r) => r.id != record.id).toList();
  });
  Future<bool> _mutate(Future<void> Function() operation) async {
    if (saving || _repository == null) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await operation();
      return true;
    } catch (e) {
      error = '지출 기록을 저장하지 못했습니다. $e';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
