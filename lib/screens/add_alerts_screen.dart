import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shell.dart';
import '../demo_alerts.dart';
import '../services/ledger_api.dart';
import '../state/ledger_store.dart';
import '../theme.dart';

class AddAlertsScreen extends StatefulWidget {
  const AddAlertsScreen({super.key});

  @override
  State<AddAlertsScreen> createState() => _AddAlertsScreenState();
}

class _AddAlertsScreenState extends State<AddAlertsScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  IngestSummary? _result;

  // Alerts are separated by a blank line or a line of dashes
  List<String> get _alerts => _ctrl.text
      .split(RegExp(r'\n\s*(?:-{3,}\s*)?\n'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your clipboard is empty. Copy an alert first, then tap Paste.')),
        );
      }
      return;
    }
    setState(() {
      _ctrl.text = [_ctrl.text.trim(), text].where((s) => s.isNotEmpty).join('\n\n');
      _result = null;
    });
  }

  Future<void> _save() async {
    final alerts = _alerts;
    if (alerts.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await LedgerStore.instance.ingest(alerts);
      setState(() {
        _result = r;
        // Keep only what didn't parse, so the user can fix or remove it
        _ctrl.text = r.unparsed.join('\n\n');
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = _alerts.length;
    final r = _result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add alerts'),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _ctrl.text = demoAlerts.join('\n\n');
                      _result = null;
                    }),
            child: const Text('Load sample alerts'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const _HowToCopy(),
                const SizedBox(height: 16),
                if (r != null) ...[
                  _ResultCard(result: r),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _ctrl,
                  minLines: 8,
                  maxLines: 16,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 14, height: 1.45),
                  decoration: InputDecoration(
                    hintText: 'Paste alerts here. Leave a blank line between two alerts.\n\n'
                        'Acct: 0123****89\nAmt: NGN15,000.00 DR\nDesc: POS PURCHASE TOTAL ENERGIES\nDate: 2026-10-05',
                    filled: true,
                    fillColor: cs.surfaceContainerLowest,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  count == 0 ? 'Nothing pasted yet' : '$count alert${count == 1 ? '' : 's'} ready to save',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _paste,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Paste'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy || count == 0 ? null : _save,
                      child: _busy
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                          : Text(count <= 1 ? 'Save alert' : 'Save $count alerts'),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No bank login needed. Only you can see your transactions.',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final IngestSummary result;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = result;
    final lines = <String>[
      if (r.created > 0) 'Saved ${r.created} transaction${r.created == 1 ? '' : 's'}.',
      if (r.duplicates > 0) '${r.duplicates} ${r.duplicates == 1 ? 'was' : 'were'} already in your ledger.',
      if (r.unparsed.isNotEmpty)
        "${r.unparsed.length} couldn't be read as a bank alert. They're left in the box below so you can check them.",
    ];
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(r.created > 0 ? Icons.check_circle : Icons.info_outline, color: cs.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(child: Text(lines.join(' '), style: TextStyle(color: cs.onPrimaryContainer, height: 1.4))),
          ]),
          if (r.created > 0) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              FilledButton(
                onPressed: () {
                  AppShell.tab.value = 2;
                  Navigator.pop(context);
                },
                child: const Text('Ask a question'),
              ),
              TextButton(
                onPressed: () {
                  AppShell.tab.value = 0;
                  Navigator.pop(context);
                },
                child: const Text('See my month'),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Short, platform-aware directions for getting an alert into the clipboard.
class _HowToCopy extends StatelessWidget {
  const _HowToCopy();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final platform = defaultTargetPlatform;
    final onIos = !kIsWeb && platform == TargetPlatform.iOS;
    final onAndroid = !kIsWeb && platform == TargetPlatform.android;

    final tips = [
      (Icons.android, 'Android', 'Open Messages, long-press the bank alert, tap Copy.', onAndroid),
      (Icons.phone_iphone, 'iPhone', 'Open Messages, touch and hold the alert, tap Copy.', onIos),
      (Icons.mail_outline, 'Email alerts', 'Select the alert text in the email and copy it.', kIsWeb),
    ]..sort((a, b) => (b.$4 ? 1 : 0) - (a.$4 ? 1 : 0)); // your platform first

    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: !LedgerStore.instance.hasTransactions,
          shape: const Border(),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Palette.amber.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: const Icon(Icons.help_outline, size: 20, color: Palette.amber),
          ),
          title: const Text('How to copy a bank alert', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('Works with GTBank, Access, Zenith, OPay, Moniepoint and more', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final t in tips)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(t.$1, size: 20, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${t.$2}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: t.$3),
                    ])),
                  ),
                ]),
              ),
            const SizedBox(height: 4),
            Text(
              'You can paste many alerts at once. Leave a blank line between them. Pasting the same alert twice is fine, it is only saved once.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
