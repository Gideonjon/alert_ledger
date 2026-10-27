import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Hand-drawn vector illustrations. Painted in code so they're crisp on every
/// screen, follow light and dark theme, and need no asset files on any platform.
///
/// The recurring motif is the bank alert itself: a slip with an amber
/// notification dot, which turns into a tidy ledger.

class _Colors {
  _Colors(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    dark = Theme.of(context).brightness == Brightness.dark;
    green = cs.primary;
    paper = cs.surfaceContainerLowest;
    tint = cs.primaryContainer;
    line = cs.outlineVariant;
    ink = cs.onSurface.withValues(alpha: 0.18);
  }
  late final bool dark;
  late final Color green, paper, tint, line, ink;
  final amber = Palette.amber;
}

RRect _rr(double x, double y, double w, double h, double r) =>
    RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

void _slip(Canvas c, _Colors k, double x, double y, double w, {double lines = 2, bool dot = true}) {
  final h = 18.0 + lines * 9;
  c.drawRRect(_rr(x, y + 3, w, h, 10), Paint()..color = k.ink.withValues(alpha: 0.10));
  c.drawRRect(_rr(x, y, w, h, 10), Paint()..color = k.paper);
  c.drawRRect(_rr(x, y, w, h, 10), Paint()
    ..color = k.line
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2);
  if (dot) c.drawCircle(Offset(x + 14, y + 14), 4.5, Paint()..color = k.amber);
  final p = Paint()..color = k.ink;
  c.drawRRect(_rr(x + 26, y + 10, w * 0.42, 7, 3.5), Paint()..color = k.green.withValues(alpha: 0.8));
  for (var i = 0; i < lines; i++) {
    c.drawRRect(_rr(x + 12, y + 24 + i * 9, (w - 24) * (i.isEven ? 0.9 : 0.6), 5, 2.5), p);
  }
}

/// Alerts on a phone flowing into a ledger with a small chart.
class AlertsToLedgerArt extends StatelessWidget {
  const AlertsToLedgerArt({super.key, this.height = 150});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: height * 1.7,
        child: CustomPaint(painter: _AlertsToLedgerPainter(_Colors(context))),
      );
}

class _AlertsToLedgerPainter extends CustomPainter {
  _AlertsToLedgerPainter(this.k);
  final _Colors k;

  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 340, s.height / 200);

    // Soft ground blob
    c.drawOval(const Rect.fromLTWH(20, 150, 300, 44), Paint()..color = k.tint);

    // Phone
    c.drawRRect(_rr(28, 14, 116, 170, 22), Paint()..color = k.green);
    c.drawRRect(_rr(34, 26, 104, 150, 16), Paint()..color = k.tint);
    c.drawRRect(_rr(70, 18, 32, 4, 2), Paint()..color = k.paper.withValues(alpha: 0.5));
    _slip(c, k, 40, 36, 92, lines: 1);
    _slip(c, k, 40, 74, 92, lines: 2);
    _slip(c, k, 40, 121, 92, lines: 1);

    // Dashed curve from phone to ledger
    final path = Path()
      ..moveTo(146, 92)
      ..cubicTo(170, 60, 190, 60, 204, 84);
    final dash = Paint()
      ..color = k.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 10) {
        c.drawPath(m.extractPath(d, math.min(d + 5, m.length)), dash);
      }
    }
    // Arrow head
    final head = Path()
      ..moveTo(206, 88)
      ..lineTo(196, 84)
      ..lineTo(205, 77)
      ..close();
    c.drawPath(head, Paint()..color = k.amber);

    // Ledger card
    c.drawRRect(_rr(204, 46, 116, 132, 16).shift(const Offset(0, 4)), Paint()..color = k.ink.withValues(alpha: 0.12));
    c.drawRRect(_rr(204, 46, 116, 132, 16), Paint()..color = k.paper);
    c.drawRRect(_rr(204, 46, 116, 132, 16), Paint()
      ..color = k.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    // Bars
    final bars = [0.45, 0.8, 0.55, 0.95, 0.65];
    for (var i = 0; i < bars.length; i++) {
      final h = 46 * bars[i];
      c.drawRRect(_rr(218 + i * 19.0, 104 - h, 12, h, 4), Paint()..color = i == 3 ? k.amber : k.green.withValues(alpha: 0.85));
    }
    // Rows
    for (var i = 0; i < 3; i++) {
      final y = 116 + i * 18.0;
      c.drawCircle(Offset(222, y + 4), 5, Paint()..color = k.tint);
      c.drawRRect(_rr(232, y, 48, 7, 3.5), Paint()..color = k.ink);
      c.drawRRect(_rr(288, y, 22, 7, 3.5), Paint()..color = k.green.withValues(alpha: 0.7));
    }

    // Naira coin
    c.drawCircle(const Offset(304, 44), 18, Paint()..color = k.amber);
    final tp = TextPainter(
      text: TextSpan(text: '₦', style: TextStyle(color: k.dark ? Palette.darkBg : Palette.ink, fontSize: 20, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(304 - tp.width / 2, 44 - tp.height / 2));

    c.restore();
  }

  @override
  bool shouldRepaint(covariant _AlertsToLedgerPainter old) => old.k.dark != k.dark;
}

/// An open notebook waiting for its first entry. Used for empty states.
class EmptyLedgerArt extends StatelessWidget {
  const EmptyLedgerArt({super.key, this.size = 140});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _EmptyPainter(_Colors(context))));
}

class _EmptyPainter extends CustomPainter {
  _EmptyPainter(this.k);
  final _Colors k;

  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 160, s.height / 160);
    c.drawCircle(const Offset(80, 84), 66, Paint()..color = k.tint);
    // Notebook pages
    c.drawRRect(_rr(30, 50, 100, 74, 10), Paint()..color = k.green);
    c.drawRRect(_rr(34, 46, 44, 74, 8), Paint()..color = k.paper);
    c.drawRRect(_rr(82, 46, 44, 74, 8), Paint()..color = k.paper);
    for (var i = 0; i < 4; i++) {
      c.drawRRect(_rr(40, 58 + i * 13.0, 32, 4, 2), Paint()..color = k.line);
      c.drawRRect(_rr(88, 58 + i * 13.0, 32, 4, 2), Paint()..color = k.line);
    }
    // A slip about to land
    _slip(c, k, 52, 14, 66, lines: 1);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _EmptyPainter old) => old.k.dark != k.dark;
}

/// A question bubble answered by a ledger row. Used on the Ask screen.
class AskArt extends StatelessWidget {
  const AskArt({super.key, this.size = 120});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _AskPainter(_Colors(context))));
}

class _AskPainter extends CustomPainter {
  _AskPainter(this.k);
  final _Colors k;

  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 160, s.height / 160);
    c.drawCircle(const Offset(80, 80), 70, Paint()..color = k.tint);
    // Question bubble
    final q = Path()..addRRect(_rr(22, 30, 96, 40, 18));
    q.moveTo(96, 66);
    q.lineTo(110, 82);
    q.lineTo(84, 70);
    c.drawPath(q, Paint()..color = k.green);
    c.drawRRect(_rr(36, 44, 50, 6, 3), Paint()..color = k.paper.withValues(alpha: 0.85));
    c.drawRRect(_rr(36, 54, 34, 6, 3), Paint()..color = k.paper.withValues(alpha: 0.55));
    // Answer slip
    _slip(c, k, 44, 92, 96, lines: 1);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _AskPainter old) => old.k.dark != k.dark;
}
