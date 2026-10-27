import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_shell.dart';
import '../models/tx.dart';
import '../services/ledger_api.dart';
import '../state/ledger_store.dart';
import '../theme.dart';
import '../widgets/guide_card.dart';
import '../widgets/illustrations.dart';
import '../widgets/tx_tile.dart';
import 'activity_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final store = LedgerStore.instance;
  int _monthIndex = 0; // 0 = newest month
  bool _pingingAppwrite = false;

  Future<void> _pingAppwrite() async {
    if (_pingingAppwrite) return;
    setState(() => _pingingAppwrite = true);
    try {
      final response = await LedgerApi.instance.client.ping();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Appwrite connected: $response')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Appwrite ping failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _pingingAppwrite = false);
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _openCategory(String key) {
    ActivityScreen.categoryFilter.value = key;
    AppShell.tab.value = 1;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final months = store.months;
        final month = months[_monthIndex.clamp(0, months.length - 1)];
        final s = store.summary(month);

        return RefreshIndicator(
          onRefresh: store.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_greeting, style: TextStyle(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text(
                            store.hasTransactions ? 'Here is where your money went' : 'Your alerts, finally organised',
                            style: t.headlineSmall,
                          ),
                        ]),
                      ),
                      const AlertsToLedgerArt(height: 92),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _pingingAppwrite ? null : _pingAppwrite,
                    icon: _pingingAppwrite
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: Text(_pingingAppwrite ? 'Pinging...' : 'Ping Appwrite'),
                  ),
                ),
              ),

              if (store.showGuide)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: GuideCard(
                    onAdd: () => AppShell.openAddAlerts(context),
                    onAsk: () => AppShell.tab.value = 2,
                    onFix: () => AppShell.tab.value = 1,
                  ),
                ),

              if (store.loading && !store.hasTransactions)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (store.error != null && !store.hasTransactions)
                _Message(
                  title: "Couldn't load your ledger",
                  body: 'Pull down to try again.',
                )
              else if (!store.hasTransactions)
                _EmptyHome(onAdd: () => AppShell.openAddAlerts(context))
              else ...[
                // ---- Month summary ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 8, 18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(DateFormat('MMMM y').format(month), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                          IconButton(
                            tooltip: 'Earlier month',
                            onPressed: _monthIndex < months.length - 1 ? () => setState(() => _monthIndex++) : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          IconButton(
                            tooltip: 'Later month',
                            onPressed: _monthIndex > 0 ? () => setState(() => _monthIndex--) : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ]),
                        Row(children: [
                          Expanded(child: _Stat(label: 'Money out', kobo: s.spentKobo)),
                          Expanded(child: _Stat(label: 'Money in', kobo: s.receivedKobo, credit: true)),
                        ]),
                        if (s.categories.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _Insight(summary: s),
                          const SizedBox(height: 14),
                          for (final e in s.categories.take(5))
                            _CategoryBar(category: e.key, kobo: e.value, total: s.spentKobo, onTap: () => _openCategory(e.key)),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(top: 12, right: 10),
                            child: Text('No spending recorded this month yet.', style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                      ]),
                    ),
                  ),
                ),

                // ---- Ask nudge ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Material(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => AppShell.tab.value = 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          Icon(Icons.chat_bubble_outline, color: cs.onPrimaryContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Ask anything, like "how much did I spend on food last week?"',
                              style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
                        ]),
                      ),
                    ),
                  ),
                ),

                // ---- Recent ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 8, 4),
                  child: Row(children: [
                    Expanded(child: Text('Recent', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                    TextButton(
                      onPressed: () {
                        ActivityScreen.categoryFilter.value = null;
                        AppShell.tab.value = 1;
                      },
                      child: const Text('See all'),
                    ),
                  ]),
                ),
                for (final tx in store.transactions.take(6)) TxTile(tx),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.kobo, this.credit = false});
  final String label;
  final int kobo;
  final bool credit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          formatNaira(kobo),
          style: display(Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: credit ? (dark ? Palette.darkGreen : Palette.credit) : cs.onSurface,
              )),
        ),
      ),
    ]);
  }
}

/// One plain-language sentence about the month, so the numbers mean something.
class _Insight extends StatelessWidget {
  const _Insight({required this.summary});
  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = summary.categories.first;
    final share = summary.spentKobo == 0 ? 0 : (top.value * 100 / summary.spentKobo).round();
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.lightbulb_outline, size: 18, color: Palette.amber),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${Category.of(top.key).label} took $share% of your spending, ${formatNaira(top.value)}.',
            style: TextStyle(color: cs.onSurface, fontSize: 13.5),
          ),
        ),
      ]),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.category, required this.kobo, required this.total, required this.onTap});
  final String category;
  final int kobo;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = Category.of(category);
    final frac = total == 0 ? 0.0 : kobo / total;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 7, 10, 7),
        child: Row(children: [
          Icon(c.icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(width: 104, child: Text(c.label, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: frac, minHeight: 8, color: cs.primary, backgroundColor: cs.surfaceContainerHigh),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(formatNairaShort(kobo), textAlign: TextAlign.right, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ]),
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(children: [
        const EmptyLedgerArt(),
        const SizedBox(height: 16),
        Text('Your ledger is empty', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Every debit and credit alert your bank sends is a line in your budget. Paste a few to begin.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add alerts')),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center),
        ]),
      );
}
