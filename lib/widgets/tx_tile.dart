import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/tx.dart';
import '../theme.dart';
import 'tx_sheet.dart';

class TxTile extends StatelessWidget {
  const TxTile(this.tx, {super.key, this.showMatch = false});
  final Tx tx;
  final bool showMatch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final credit = dark ? Palette.darkGreen : Palette.credit;

    return InkWell(
      onTap: () => showTxSheet(context, tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(13)),
              child: Icon(tx.cat.icon, size: 20, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${tx.cat.label}, ${DateFormat('d MMM').format(tx.date)}',
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                      if (tx.categorySource == 'vector') const _Tag('Sorted by AI', Palette.amber),
                      if (showMatch && tx.matchedBy == 'meaning')
                        _Tag('${((1 - (tx.distance ?? 0)) * 100).round()}% match', cs.primary),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${tx.isDebit ? '−' : '+'}${formatNaira(tx.amountKobo)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: tx.isDebit ? cs.onSurface : credit,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
      );
}
