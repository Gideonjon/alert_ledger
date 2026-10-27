import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _naira = NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 2);
final _nairaShort = NumberFormat.compactCurrency(locale: 'en_NG', symbol: '₦', decimalDigits: 1);

String formatNaira(int kobo) => _naira.format(kobo / 100);
String formatNairaShort(int kobo) => kobo.abs() < 10000000 ? formatNaira(kobo) : _nairaShort.format(kobo / 100);

/// Categories, in the order they appear in pickers. Keys match functions/ledger/src/categories.js.
class Category {
  const Category(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;

  static const all = <Category>[
    Category('food', 'Food', Icons.restaurant_outlined),
    Category('groceries', 'Groceries', Icons.shopping_basket_outlined),
    Category('fuel', 'Fuel', Icons.local_gas_station_outlined),
    Category('transport', 'Transport', Icons.directions_car_outlined),
    Category('airtime_data', 'Airtime & data', Icons.phone_android_outlined),
    Category('utilities', 'Light & bills', Icons.bolt_outlined),
    Category('rent', 'Rent', Icons.home_outlined),
    Category('subscriptions', 'Subscriptions', Icons.autorenew),
    Category('shopping', 'Shopping', Icons.shopping_bag_outlined),
    Category('education', 'School', Icons.school_outlined),
    Category('health', 'Health', Icons.local_hospital_outlined),
    Category('bank_charges', 'Bank charges', Icons.account_balance_outlined),
    Category('transfer', 'Transfers', Icons.swap_horiz),
    Category('salary', 'Salary', Icons.work_outline),
    Category('income', 'Money in', Icons.south_west),
    Category('other', 'Other', Icons.receipt_long_outlined),
  ];

  static Category of(String key) => all.firstWhere((c) => c.key == key, orElse: () => all.last);
}

class Tx {
  Tx({
    required this.id,
    required this.direction,
    required this.amountKobo,
    required this.description,
    required this.counterparty,
    required this.category,
    required this.categorySource,
    required this.bank,
    required this.date,
    this.balanceKobo,
    this.raw = '',
    this.matchedBy,
    this.distance,
  });

  final String id;
  final String direction; // 'debit' | 'credit'
  final int amountKobo;
  final int? balanceKobo;
  final String description;
  final String counterparty;
  final String category;
  final String categorySource; // 'keyword' | 'vector' | 'user' | 'none'
  final String bank;
  final DateTime date;
  final String raw;

  // Only set on /ask results
  final String? matchedBy; // 'category' | 'meaning' | 'range'
  final double? distance;

  bool get isDebit => direction == 'debit';
  Category get cat => Category.of(category);

  String get title {
    if (counterparty.isNotEmpty) return titleCase(counterparty);
    if (description.isNotEmpty) return titleCase(description);
    return isDebit ? 'Money out' : 'Money in';
  }

  String get bankLabel => const {
        'gtbank': 'GTBank', 'access': 'Access Bank', 'zenith': 'Zenith Bank', 'firstbank': 'First Bank',
        'uba': 'UBA', 'opay': 'OPay', 'moniepoint': 'Moniepoint', 'kuda': 'Kuda', 'palmpay': 'PalmPay',
        'wema': 'Wema', 'fidelity': 'Fidelity', 'sterling': 'Sterling', 'fcmb': 'FCMB', 'stanbic': 'Stanbic',
        'union': 'Union Bank',
      }[bank] ??
      'Bank';

  Tx copyWith({String? category, String? categorySource}) => Tx(
        id: id,
        direction: direction,
        amountKobo: amountKobo,
        balanceKobo: balanceKobo,
        description: description,
        counterparty: counterparty,
        category: category ?? this.category,
        categorySource: categorySource ?? this.categorySource,
        bank: bank,
        date: date,
        raw: raw,
      );

  factory Tx.fromMap(Map<String, dynamic> m) => Tx(
        id: (m[r'$id'] ?? '') as String,
        direction: (m['direction'] ?? 'debit') as String,
        amountKobo: (m['amountKobo'] as num?)?.toInt() ?? 0,
        balanceKobo: (m['balanceKobo'] as num?)?.toInt(),
        description: (m['description'] ?? '') as String,
        counterparty: (m['counterparty'] ?? '') as String,
        category: (m['category'] ?? 'other') as String,
        categorySource: (m['categorySource'] ?? 'keyword') as String,
        bank: (m['bank'] ?? 'unknown') as String,
        date: DateTime.tryParse((m['txDate'] ?? '') as String)?.toLocal() ?? DateTime.now(),
        raw: (m['raw'] ?? '') as String,
        matchedBy: m['matchedBy'] as String?,
        distance: (m['distance'] as num?)?.toDouble(),
      );
}

String titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');
