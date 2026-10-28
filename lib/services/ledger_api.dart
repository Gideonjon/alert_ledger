import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';

import '../config.dart';
import '../models/tx.dart';

class AskResult {
  AskResult({required this.answer, required this.totalKobo, required this.items, required this.parsed});
  final String answer;
  final int totalKobo;
  final List<Tx> items;
  final Map<String, dynamic> parsed;
}

class IngestSummary {
  IngestSummary(this.created, this.duplicates, this.unparsed);
  final int created;
  final int duplicates;
  final List<String> unparsed;
}

class RecategorizeResult {
  RecategorizeResult(this.updated, this.similar);
  final int updated;
  final int similar; // other rows from the same counterparty still in a different category
}

/// Thin wrapper over Appwrite. The ledger is read straight from TablesDB on the
/// client (row permissions keep it per-user); anything that touches VectorsDB or
/// the Embeddings service goes through the `ledger` function.
class LedgerApi {
  LedgerApi._(this.client)
      : account = Account(client),
        tablesDB = TablesDB(client),
        functions = Functions(client);

  static final instance = LedgerApi._(
    Client().setEndpoint(AppConfig.endpoint).setProject(AppConfig.projectId),
  );

  final Client client;
  final Account account;
  final TablesDB tablesDB;
  final Functions functions;

  String? userId;

  /// Anonymous session keeps the first run friction-free on every platform.
  Future<void> ensureSession() async {
    try {
      userId = (await account.get()).$id;
    } on AppwriteException {
      await account.createAnonymousSession();
      userId = (await account.get()).$id;
    }
  }

  // ---- Account prefs: onboarding progress follows the user across devices ----

  Future<Map<String, dynamic>> prefs() async => (await account.getPrefs()).data;

  Future<void> setPref(String key, Object value) async {
    final current = await prefs();
    await account.updatePrefs(prefs: {...current, key: value});
  }

  // ---- TablesDB ----

  Future<List<Tx>> transactions({int max = 1000}) async {
    final out = <Tx>[];
    String? cursor;
    while (out.length < max) {
      final res = await tablesDB.listRows(
        databaseId: AppConfig.tablesDbId,
        tableId: AppConfig.transactionsTableId,
        queries: [
          Query.orderDesc('txDate'),
          Query.limit(100),
          if (cursor != null) Query.cursorAfter(cursor),
        ],
      );
      out.addAll(res.rows.map((r) => Tx.fromMap({r'$id': r.$id, ...r.data})));
      if (res.rows.length < 100) break;
      cursor = res.rows.last.$id;
    }
    return out;
  }

  // ---- Function routes ----


Future<Map<String, dynamic>> _call(
  String path,
  Map<String, dynamic> body,
) async {
  // Ensure an Appwrite session exists before invoking the function.
  await ensureSession();

  // Verify that the session is still available on this client.
  final accountInfo = await account.get();
  userId = accountInfo.$id;

  final exec = await functions.createExecution(
    functionId: AppConfig.functionId,
    path: path,
    method: ExecutionMethod.pOST,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  final data = exec.responseBody.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(exec.responseBody) as Map<String, dynamic>;

  if (exec.responseStatusCode >= 400) {
    throw LedgerException(
      data['error'] as String? ??
          'Something went wrong (${exec.responseStatusCode}). Try again.',
    );
  }

  return data;
}


  Future<IngestSummary> ingest(List<String> alerts) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final data = await _call('/ingest', {
      'alerts': [for (final a in alerts) {'text': a, 'receivedAt': now}],
    });
    final results = (data['results'] as List).cast<Map<String, dynamic>>();
    return IngestSummary(
      results.where((r) => r['status'] == 'created').length,
      results.where((r) => r['status'] == 'duplicate').length,
      [for (final r in results) if (r['status'] == 'unparsed') r['text'] as String],
    );
  }

  Future<AskResult> ask(String question) async {
    final data = await _call('/ask', {'question': question});
    return AskResult(
      answer: data['answer'] as String,
      totalKobo: (data['totalKobo'] as num).toInt(),
      parsed: (data['parsed'] as Map).cast<String, dynamic>(),
      items: (data['items'] as List).map((m) => Tx.fromMap((m as Map).cast<String, dynamic>())).toList(),
    );
  }

  Future<RecategorizeResult> recategorize(String rowId, String category, {bool applyToSimilar = false}) async {
    final data = await _call('/recategorize', {'rowId': rowId, 'category': category, 'applyToSimilar': applyToSimilar});
    return RecategorizeResult((data['updated'] as num).toInt(), (data['similar'] as num).toInt());
  }

  Future<void> delete(String rowId) => _call('/delete', {'rowId': rowId});
}

class LedgerException implements Exception {
  LedgerException(this.message);
  final String message;
  @override
  String toString() => message;
}
