import 'package:intl/intl.dart';

enum ExpensePeriod { monthly, weekly }

enum ExpenseCurrency {
  krw('KRW', 0),
  usd('USD', 2);

  const ExpenseCurrency(this.code, this.decimals);
  final String code;
  final int decimals;
  int get scale => this == usd ? 100 : 1;
}

int? parseExpenseAmount(String input, ExpenseCurrency currency) {
  final value = input.trim();
  if (!RegExp(
    r'^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$',
  ).hasMatch(value)) {
    return null;
  }
  final parts = value.replaceAll(',', '').split('.');
  if (currency == ExpenseCurrency.krw && parts.length > 1) return null;
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 900000000000) return null;
  final fraction = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
  final amount = whole * currency.scale + fraction;
  return amount > 0 ? amount : null;
}

class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.date,
    required this.merchant,
    required this.amount,
    this.currency = ExpenseCurrency.krw,
    this.memo = '',
  });

  final String id;
  final DateTime date;
  final String merchant;

  /// Whole won or USD cents; integer arithmetic keeps totals exact.
  final int amount;
  final ExpenseCurrency currency;
  final String memo;

  Map<String, Object> toJson() => {
    'schema': 'scrapnote/expense-v1',
    'id': id,
    'date': DateFormat('yyyy-MM-dd').format(date),
    'merchant': merchant,
    'amount': amount,
    'currency': currency.code,
    'memo': memo,
  };

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 'scrapnote/expense-v1' ||
        !ExpenseCurrency.values.any((c) => c.code == json['currency']) ||
        json['id'] is! String ||
        json['merchant'] is! String ||
        json['date'] is! String ||
        json['memo'] is! String ||
        json['amount'] is! int ||
        (json['amount'] as int) <= 0) {
      throw const FormatException('Invalid expense record.');
    }
    final date = DateFormat('yyyy-MM-dd').parseStrict(json['date'] as String);
    return ExpenseRecord(
      id: json['id'] as String,
      date: date,
      merchant: json['merchant'] as String,
      amount: json['amount'] as int,
      currency: ExpenseCurrency.values.firstWhere(
        (c) => c.code == json['currency'],
      ),
      memo: json['memo'] as String,
    );
  }
}

class ExpenseRange {
  ExpenseRange(DateTime anchor, ExpensePeriod period)
    : start = period == ExpensePeriod.monthly
          ? DateTime(anchor.year, anchor.month)
          : DateTime(
              anchor.year,
              anchor.month,
              anchor.day - anchor.weekday + 1,
            ),
      end = period == ExpensePeriod.monthly
          ? DateTime(anchor.year, anchor.month + 1)
          : DateTime(
              anchor.year,
              anchor.month,
              anchor.day - anchor.weekday + 8,
            );
  final DateTime start;
  final DateTime end;
  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
}

String expenseMoney(num minorUnits, ExpenseCurrency currency) =>
    NumberFormat.currency(
      locale: 'en_US',
      symbol: currency == ExpenseCurrency.krw ? '₩' : '\$',
      decimalDigits: currency.decimals,
    ).format(minorUnits / currency.scale);
