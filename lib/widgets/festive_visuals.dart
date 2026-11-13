import 'package:flutter/material.dart';
import '../services/remote_theme.dart';

String themeVisual(String key, String fallback) =>
    (RemoteTheme.instance.current?['visuals'] as Map?)?[key] as String? ??
    fallback;

/// Static, bounded vector details: no executable assets, timers or tap interception.
class FestiveBackdrop extends StatelessWidget {
  final Widget child;
  const FestiveBackdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      if (themeVisual('background', 'none') != 'none')
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _FestivePainter(
                  themeVisual('background', 'none'),
                  RemoteTheme.instance.colour('accent'),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class FestiveTile extends StatelessWidget {
  final Widget child;
  const FestiveTile({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final style = themeVisual('buttonStyle', 'plain');
    final card = themeVisual('cardStyle', 'plain');
    if (style == 'plain' && card == 'plain') return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _TilePainter(
                  style,
                  card,
                  RemoteTheme.instance.colour('accent'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TilePainter extends CustomPainter {
  final String style, card;
  final Color accent;
  _TilePainter(this.style, this.card, this.accent);
  @override
  void paint(Canvas canvas, Size s) {
    if (s.width < 24 || s.height < 20) return;
    if (card == 'goldOutline') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(12)),
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    if (card == 'ribbon') {
      final p = Path()
        ..moveTo(s.width - 26, 0)
        ..lineTo(s.width - 16, 0)
        ..lineTo(s.width, s.height.clamp(0, 26).toDouble() - 16)
        ..lineTo(s.width, 26)
        ..close();
      canvas.drawPath(p, Paint()..color = const Color(0xFFB52D41));
    }
    if (style == 'snowcap') {
      final p = Path()
        ..moveTo(9, 2)
        ..lineTo(s.width - 9, 2)
        ..quadraticBezierTo(s.width - 15, 10, s.width - 25, 5)
        ..quadraticBezierTo(s.width * .55, 13, s.width * .4, 5)
        ..quadraticBezierTo(15, 10, 9, 2)
        ..close();
      canvas.drawPath(p, Paint()..color = const Color(0xFFEAF8FF));
    } else if (style == 'lantern') {
      canvas.drawLine(
        Offset(s.width - 12, 0),
        Offset(s.width - 12, 7),
        Paint()
          ..color = accent
          ..strokeWidth = 1,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(s.width - 12, 10), width: 9, height: 10),
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TilePainter old) =>
      old.style != style || old.card != card || old.accent != accent;
}

class _FestivePainter extends CustomPainter {
  final String style;
  final Color accent;
  _FestivePainter(this.style, this.accent);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = accent.withValues(alpha: .17)
      ..strokeWidth = 1.2;
    // Sparse edge-only decoration, never obscures central content.
    for (var i = 0; i < 16; i++) {
      final x = i.isEven ? 5.0 + (i % 3) * 5 : s.width - 7 - (i % 3) * 5;
      final y = 20.0 + (i / 16) * s.height;
      final radius = style == 'snow' ? 3.0 : 4.0;
      canvas.drawLine(Offset(x - radius, y), Offset(x + radius, y), p);
      canvas.drawLine(Offset(x, y - radius), Offset(x, y + radius), p);
      if (style == 'snow') canvas.drawCircle(Offset(x, y), 1, p);
    }
  }

  @override
  bool shouldRepaint(covariant _FestivePainter old) =>
      old.style != style || old.accent != accent;
}
