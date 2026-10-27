import 'package:flutter/foundation.dart';

import '../models/tx.dart';
import '../services/ledger_api.dart';

/// App-wide state. Plain ChangeNotifier, no extra packages.
class LedgerStore extends ChangeNotifier {
  LedgerStore._();
  static final instance = LedgerStore._();

  final api = LedgerApi.instance;

  List<Tx> transactions = [];
  bool loading = true;
  Object? error;
  Map<String, dynamic> _prefs = {};

  // ---- Getting-started progress ----
  bool get hasTransactions => transactions.isNotEmpty;
  bool get hasAsked => _prefs['asked'] == true;
  bool get hasFixedCategory => _prefs['fixed'] == true || transactions.any((t) => t.categorySource == 'user');
  bool get guideDismissed => _prefs['guideDismissed'] == true;
  int get stepsDone => [hasTransactions, hasAsked, hasFixedCategory].where((d) => d).length;
  bool get showGuide => !guideDismissed && stepsDone < 3;

  Future<void> start() async {
    await api.ensureSession();
    await Future.wait([load(), _loadPrefs()]);
  }

  Future<void> _loadPrefs() async {
    try {
      _prefs = await api.prefs();
      notifyListeners();
    } catch (_) {/* progress is a nicety; never block the app on it */}
  }

  Future<void> _mark(String key) async {
    if (_prefs[key] == true) return;
    _prefs = {..._prefs, key: true};
    notifyListeners();
    try {
      await api.setPref(key, true);
    } catch (_) {}
  }

  Future<void> dismissGuide() => _mark('guideDismissed');

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      transactions = await api.transactions();
      error = null;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<IngestSummary> ingest(List<String> alerts) async {
    final r = await api.ingest(alerts);
    await load();
    return r;
  }

  Future<AskResult> ask(String question) async {
    final r = await api.ask(question);
    _mark('asked');
    return r;
  }

  Future<RecategorizeResult> recategorize(Tx tx, String category, {bool applyToSimilar = false}) async {
    final r = await api.recategorize(tx.id, category, applyToSimilar: applyToSimilar);
    _mark('fixed');
    await load();
    return r;
  }

  Future<void> delete(Tx tx) async {
    final before = transactions;
    transactions = transactions.where((t) => t.id != tx.id).toList();
    notifyListeners();
    try {
      await api.delete(tx.id);
    } catch (e) {
      transactions = before; // put it back if the server said no
      notifyListeners();
      rethrow;
    }
  }

  // ---- Month summaries ----

  List<Tx> inMonth(DateTime month) =>
      transactions.where((t) => t.date.year == month.year && t.date.month == month.month).toList();

  MonthSummary summary(DateTime month) {
    final txs = inMonth(month);
    int sum(bool debit) => txs.where((t) => t.isDebit == debit).fold(0, (s, t) => s + t.amountKobo);
    final byCat = <String, int>{};
    for (final t in txs.where((t) => t.isDebit)) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amountKobo;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return MonthSummary(month, sum(true), sum(false), cats, txs.length);
  }

  /// Months that have data, newest first. Always includes the current month.
  List<DateTime> get months {
    final now = DateTime.now();
    final set = <DateTime>{DateTime(now.year, now.month)};
    for (final t in transactions) {
      set.add(DateTime(t.date.year, t.date.month));
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
  }
}

class MonthSummary {
  MonthSummary(this.month, this.spentKobo, this.receivedKobo, this.categories, this.count);
  final DateTime month;
  final int spentKobo;
  final int receivedKobo;
  final List<MapEntry<String, int>> categories;
  final int count;
}
