import 'package:flutter/material.dart';

import '../models/tx.dart';
import '../services/ledger_api.dart';
import '../state/ledger_store.dart';
import '../widgets/illustrations.dart';
import '../widgets/tx_tile.dart';

class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _ctrl = TextEditingController();
  final _turns = <(String, AskResult?, String?)>[]; // question, result, error
  bool _busy = false;

  // Rebuild when alerts are added elsewhere, so the input unlocks
  void _onStore() => setState(() {});

  @override
  void initState() {
    super.initState();
    LedgerStore.instance.addListener(_onStore);
  }

  @override
  void dispose() {
    LedgerStore.instance.removeListener(_onStore);
    _ctrl.dispose();
    super.dispose();
  }

  static const suggestions = [
    'How much did I spend on fuel in September?',
    'Show transfers to Emeka',
    'How much did I receive this month?',
    'Where did my money go last week?',
    'How many times did I buy suya?',
    'How much did I spend on light this month?',
  ];

  Future<void> _ask(String q) async {
    q = q.trim();
    if (q.isEmpty || _busy) return;
    _ctrl.clear();
    setState(() {
      _busy = true;
      _turns.insert(0, (q, null, null));
    });
    try {
      final r = await LedgerStore.instance.ask(q);
      setState(() => _turns[0] = (q, r, null));
    } catch (e) {
      setState(() => _turns[0] = (q, null, '$e'));
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final hasData = LedgerStore.instance.hasTransactions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask'),
        centerTitle: false,
        actions: [
          if (_turns.isNotEmpty)
            TextButton(onPressed: () => setState(_turns.clear), child: const Text('Clear')),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: _turns.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      const Center(child: AskArt()),
                      const SizedBox(height: 12),
                      Text('Ask about your money in plain English', style: t.titleLarge, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(
                        hasData
                            ? 'Answers come from the alerts you saved. Totals are added up exactly, and you can see every transaction behind them.'
                            : 'Add a few alerts first, then come back here. Until then there is nothing to search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      Text('Try one of these', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final s in suggestions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton(
                            onPressed: hasData ? () => _ask(s) : null,
                            style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16)),
                            child: Text(s),
                          ),
                        ),
                    ],
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _turns.length,
                    itemBuilder: (_, i) => _Turn(turn: _turns[i]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _ctrl,
              enabled: hasData,
              textInputAction: TextInputAction.send,
              onSubmitted: _ask,
              decoration: InputDecoration(
                hintText: hasData ? 'How much did I spend on food last week?' : 'Add alerts to start asking',
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton.filled(
                    tooltip: 'Ask',
                    icon: _busy
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                        : const Icon(Icons.arrow_upward),
                    onPressed: hasData ? () => _ask(_ctrl.text) : null,
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Turn extends StatelessWidget {
  const _Turn({required this.turn});
  final (String, AskResult?, String?) turn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (q, r, err) = turn;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(left: 64, right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(q, style: TextStyle(color: cs.onPrimary)),
          ),
        ),
        const SizedBox(height: 8),
        if (err != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(err, style: TextStyle(color: cs.error)))
        else if (r == null)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: LinearProgressIndicator())
        else
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 40),
            child: Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(r.answer, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(_explain(r.parsed), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ),
                if (r.items.isNotEmpty) const Divider(),
                for (final t in r.items.take(20)) TxTile(t, showMatch: true),
                if (r.items.length > 20)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('and ${r.items.length - 20} more', style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                const SizedBox(height: 6),
              ]),
            ),
          ),
      ]),
    );
  }

  /// How the question was understood, so every answer can be checked.
  String _explain(Map<String, dynamic> p) {
    final parts = <String>[
      if (p['direction'] != null) p['direction'] == 'debit' ? 'Money out' : 'Money in',
      if (p['from'] != null) 'from ${p['from']} to ${p['to']}',
      if (p['category'] != null) 'in ${Category.of(p['category'] as String).label}',
      if ((p['topic'] as String?)?.isNotEmpty == true) 'matching the meaning of "${p['topic']}"',
    ];
    return parts.isEmpty ? 'All transactions' : parts.join(', ');
  }
}
