import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/tx.dart';
import '../state/ledger_store.dart';
import '../theme.dart';

/// Transaction detail: fix the category, see the original alert, delete.
Future<void> showTxSheet(BuildContext context, Tx tx) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _TxSheet(tx: tx),
    );

class _TxSheet extends StatefulWidget {
  const _TxSheet({required this.tx});
  final Tx tx;

  @override
  State<_TxSheet> createState() => _TxSheetState();
}

class _TxSheetState extends State<_TxSheet> {
  late Tx tx = widget.tx;
  String? _saving; // category key being saved
  bool _deleting = false;

  final store = LedgerStore.instance;

  Future<void> _setCategory(String key) async {
    if (key == tx.category || _saving != null) return;
    setState(() => _saving = key);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await store.recategorize(tx, key);
      if (!mounted) return;
      setState(() => tx = tx.copyWith(category: key, categorySource: 'user'));
      final label = Category.of(key).label;
      messenger.showSnackBar(SnackBar(
        content: Text(r.similar > 0
            ? 'Moved to $label. ${r.similar} more from ${tx.title} ${r.similar == 1 ? 'is' : 'are'} elsewhere.'
            : 'Moved to $label. Similar alerts will go here too.'),
        action: r.similar > 0
            ? SnackBarAction(
                label: 'Move all',
                onPressed: () => store.recategorize(tx, key, applyToSimilar: true),
              )
            : null,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: const Text('It will be removed from your ledger and from search. You can paste the alert again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.delete(tx);
      nav.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Transaction deleted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tx.title, style: t.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            '${tx.isDebit ? '−' : '+'}${formatNaira(tx.amountKobo)}',
            style: t.headlineMedium?.copyWith(color: tx.isDebit ? cs.onSurface : (dark ? Palette.darkGreen : Palette.credit)),
          ),
          const SizedBox(height: 4),
          Text(
            [
              DateFormat('EEEE d MMMM y').format(tx.date),
              tx.bankLabel,
              if (tx.balanceKobo != null) 'Balance after ${formatNaira(tx.balanceKobo!)}',
            ].join('\n'),
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 20),
          Text('Category', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            switch (tx.categorySource) {
              'vector' => 'Sorted by AI from similar merchants. Tap another one if it\'s wrong and the app will learn.',
              'user' => 'You picked this. Future alerts like it will follow.',
              'none' => 'The app wasn\'t sure. Pick one and it will remember.',
              _ => 'Wrong? Tap the right one and the app will learn.',
            },
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in Category.all)
                ChoiceChip(
                  avatar: _saving == c.key
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(c.icon, size: 16),
                  label: Text(c.label),
                  selected: tx.category == c.key,
                  showCheckmark: false,
                  onSelected: (_) => _setCategory(c.key),
                ),
            ],
          ),
          if (tx.raw.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Original alert', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            // Clip instead of borderRadius: Flutter rejects rounded corners on a one-sided border
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  border: const Border(left: BorderSide(color: Palette.amber, width: 3)),
                ),
                child: SelectableText(tx.raw, style: TextStyle(fontSize: 13, height: 1.45, color: cs.onSurfaceVariant)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _deleting ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: cs.error),
            icon: _deleting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_outline),
            label: const Text('Delete transaction'),
          ),
        ],
      ),
    );
  }
}
