import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_shell.dart';
import '../models/tx.dart';
import '../state/ledger_store.dart';
import '../widgets/illustrations.dart';
import '../widgets/tx_tile.dart';

enum _Flow { all, out, into }

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  /// Set from Home when a category bar is tapped.
  static final categoryFilter = ValueNotifier<String?>(null);

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final store = LedgerStore.instance;
  final _search = TextEditingController();
  _Flow _flow = _Flow.all;

  List<Tx> _filtered(String? category) {
    final q = _search.text.trim().toLowerCase();
    return store.transactions.where((t) {
      if (_flow == _Flow.out && !t.isDebit) return false;
      if (_flow == _Flow.into && t.isDebit) return false;
      if (category != null && t.category != category) return false;
      if (q.isNotEmpty && !('${t.title} ${t.description} ${t.cat.label} ${t.bankLabel}'.toLowerCase().contains(q))) return false;
      return true;
    }).toList();
  }

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(Icons.all_inclusive),
            title: const Text('All categories'),
            onTap: () => Navigator.pop(c, ''),
          ),
          for (final cat in Category.all)
            ListTile(leading: Icon(cat.icon), title: Text(cat.label), onTap: () => Navigator.pop(c, cat.key)),
        ]),
      ),
    );
    if (picked != null) ActivityScreen.categoryFilter.value = picked.isEmpty ? null : picked;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Activity'), centerTitle: false),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, ActivityScreen.categoryFilter]),
        builder: (context, _) {
          final category = ActivityScreen.categoryFilter.value;
          final items = _filtered(category);
          final out = items.where((t) => t.isDebit).fold(0, (s, t) => s + t.amountKobo);
          final into = items.where((t) => !t.isDebit).fold(0, (s, t) => s + t.amountKobo);

          // Group by day for headers
          final rows = <Widget>[];
          DateTime? day;
          for (final tx in items) {
            final d = DateTime(tx.date.year, tx.date.month, tx.date.day);
            if (d != day) {
              day = d;
              rows.add(Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(_dayLabel(d), style: t.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
              ));
            }
            rows.add(TxTile(tx));
          }

          return RefreshIndicator(
            onRefresh: store.load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Filter by name, merchant or bank',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    SegmentedButton<_Flow>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: _Flow.all, label: Text('All')),
                        ButtonSegment(value: _Flow.out, label: Text('Money out')),
                        ButtonSegment(value: _Flow.into, label: Text('Money in')),
                      ],
                      selected: {_flow},
                      onSelectionChanged: (s) => setState(() => _flow = s.first),
                    ),
                    const SizedBox(width: 8),
                    InputChip(
                      avatar: Icon(category == null ? Icons.filter_list : Category.of(category).icon, size: 18),
                      label: Text(category == null ? 'Category' : Category.of(category).label),
                      selected: category != null,
                      showCheckmark: false,
                      onPressed: _pickCategory,
                      onDeleted: category == null ? null : () => ActivityScreen.categoryFilter.value = null,
                    ),
                  ]),
                ),
                if (items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Text(
                      '${items.length} transaction${items.length == 1 ? '' : 's'}.'
                      '${out > 0 ? ' Out ${formatNaira(out)}.' : ''}'
                      '${into > 0 ? ' In ${formatNaira(into)}.' : ''}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
                if (store.loading && store.transactions.isEmpty)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else if (store.transactions.isEmpty)
                  _Empty(
                    title: 'Nothing here yet',
                    body: 'Transactions show up here as soon as you add your first alerts.',
                    action: FilledButton.icon(
                      onPressed: () => AppShell.openAddAlerts(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add alerts'),
                    ),
                  )
                else if (items.isEmpty)
                  const _Empty(title: 'No matches', body: 'Try a different filter, or clear the search.')
                else
                  ...rows,
              ],
            ),
          );
        },
      ),
    );
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat(d.year == now.year ? 'EEEE d MMMM' : 'd MMMM y').format(d);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body, this.action});
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
        child: Column(children: [
          const EmptyLedgerArt(size: 120),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}
