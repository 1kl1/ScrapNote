import 'expense_record.dart';

/// Conversion affects summaries only; records retain their original currency.
class ExpenseSettings {
  const ExpenseSettings({
    this.krwPerUsd = 1380,
    this.displayCurrency = ExpenseCurrency.krw,
  });

  final double krwPerUsd;
  final ExpenseCurrency displayCurrency;

  static bool validRate(double value) =>
      value.isFinite && value > 0 && value <= 1000000000;

  double convert(ExpenseRecord record) {
    if (record.currency == displayCurrency) return record.amount.toDouble();
    return displayCurrency == ExpenseCurrency.krw
        ? record.amount / 100 * krwPerUsd
        : record.amount / krwPerUsd * 100;
  }

  Map<String, Object> toJson() => {
    'krwPerUsd': krwPerUsd,
    'displayCurrency': displayCurrency.code,
  };

  factory ExpenseSettings.fromJson(Map<String, dynamic> json) {
    final rate = json['krwPerUsd'];
    final currency = json['displayCurrency'];
    if (rate is! num ||
        !validRate(rate.toDouble()) ||
        !ExpenseCurrency.values.any((c) => c.code == currency)) {
      throw const FormatException('Invalid expense settings.');
    }
    return ExpenseSettings(
      krwPerUsd: rate.toDouble(),
      displayCurrency: ExpenseCurrency.values.firstWhere(
        (c) => c.code == currency,
      ),
    );
  }
}
