import 'package:flutter/material.dart';

import '../state/ledger_store.dart';
import '../theme.dart';

/// "Getting started" checklist on the home screen. Each step is done when the
/// user has actually done it (data in the ledger, a question asked, a category
/// fixed), so it can't drift out of sync.
class GuideCard extends StatelessWidget {
  const GuideCard({super.key, required this.onAdd, required this.onAsk, required this.onFix});
  final VoidCallback onAdd;
  final VoidCallback onAsk;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final store = LedgerStore.instance;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final steps = [
      _Step(
        done: store.hasTransactions,
        title: 'Add your bank alerts',
        body: 'Copy a few alerts from your SMS or email and paste them in. No sample handy? Load ours.',
        action: 'Add alerts',
        onTap: onAdd,
      ),
      _Step(
        done: store.hasAsked,
        title: 'Ask a question',
        body: 'Try "How much did I spend on fuel this month?" or "Show transfers to Emeka".',
        action: 'Ask now',
        onTap: onAsk,
      ),
      _Step(
        done: store.hasFixedCategory,
        title: 'Teach it one merchant',
        body: 'Open a transaction with the wrong category and pick the right one. Alerts like it follow.',
        action: 'Open activity',
        onTap: onFix,
      ),
    ];
    final next = steps.indexWhere((s) => !s.done);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Getting started', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              Text('${store.stepsDone} of 3', style: TextStyle(color: cs.onSurfaceVariant)),
              IconButton(
                tooltip: 'Hide guide',
                icon: const Icon(Icons.close, size: 20),
                onPressed: store.dismissGuide,
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: store.stepsDone / 3,
                  minHeight: 6,
                  color: Palette.amber,
                  backgroundColor: cs.surfaceContainerHigh,
                ),
              ),
            ),
            for (var i = 0; i < steps.length; i++) _StepRow(index: i + 1, step: steps[i], isNext: i == next),
          ],
        ),
      ),
    );
  }
}

class _Step {
  _Step({required this.done, required this.title, required this.body, required this.action, required this.onTap});
  final bool done;
  final String title;
  final String body;
  final String action;
  final VoidCallback onTap;
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step, required this.isNext});
  final int index;
  final _Step step;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 10, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: step.done ? cs.primary : (isNext ? Palette.amber : cs.surfaceContainerHigh),
            ),
            child: step.done
                ? Icon(Icons.check, size: 16, color: cs.onPrimary)
                : Text('$index', style: TextStyle(fontWeight: FontWeight.w700, color: isNext ? Palette.ink : cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: step.done ? TextDecoration.lineThrough : null,
                    color: step.done ? cs.onSurfaceVariant : cs.onSurface,
                  ),
                ),
                if (isNext) ...[
                  const SizedBox(height: 2),
                  Text(step.body, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4)),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: step.onTap,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                    child: Text(step.action),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
