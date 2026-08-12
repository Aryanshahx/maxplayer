import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/theme_state.dart';

/// Vector-drawn illustrations for the gesture guide in the user manual.
/// They are painted in code (CustomPaint) instead of bundled image files:
/// always crisp at any DPI, they follow the app's accent colour, and they
/// add zero weight to the APK.
enum GestureKind {
  singleTap,
  doubleTapSides,
  doubleTapMiddle,
  swipeBrightness,
  swipeVolume,
  swipeSeek,
  pinchZoom,
  holdSpeed,
}

class GestureIllustration extends StatelessWidget {
  final GestureKind kind;
  final double height;

  const GestureIllustration({
    super.key,
    required this.kind,
    this.height = 110,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _GesturePainter(kind, themeState.accent),
      ),
    );
  }
}

class _GesturePainter extends CustomPainter {
  final GestureKind kind;
  final Color accent;

  _GesturePainter(this.kind, this.accent);

  // ---------- helpers -------------------------------------------------------

  Paint get _thinWhite => Paint()
    ..color = Colors.white60
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  Paint get _accentPaint => Paint()
    ..color = accent
    ..strokeWidth = 2.4
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  RRect _phone(Size size) {
    final w = size.width * 0.86;
    final h = size.height * 0.72;
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2 + 4),
        width: w,
        height: h);
    return RRect.fromRectAndRadius(rect, const Radius.circular(14));
  }

  void _drawPhone(Canvas canvas, Size size) {
    final phone = _phone(size);
    // Body.
    canvas.drawRRect(
        phone,
        Paint()
          ..color = const Color(0xFF181824)
          ..style = PaintingStyle.fill);
    // Screen with a soft gradient.
    final screen = phone.deflate(3);
    final rect = screen.outerRect;
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF232838), Color(0xFF12141f)],
        ).createShader(rect),
    );
    // Border.
    canvas.drawRRect(
        phone,
        Paint()
          ..color = Colors.white30
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // A dim "play" triangle to suggest a video on the screen.
    final c = screen.center;
    final tri = Path()
      ..moveTo(c.dx - 7, c.dy - 10)
      ..lineTo(c.dx + 10, c.dy)
      ..lineTo(c.dx - 7, c.dy + 10)
      ..close();
    canvas.drawPath(
        tri,
        Paint()
          ..color = Colors.white10
          ..style = PaintingStyle.fill);
  }

  void _arrow(Canvas canvas, Offset from, Offset to, [Paint? paint]) {
    final p = paint ?? _thinWhite;
    canvas.drawLine(from, to, p);
    final angle = (to - from).direction;
    for (final delta in [2.55, -2.55]) {
      final a = angle + delta;
      canvas.drawLine(
          to,
          to + Offset(math.cos(a) * 8, math.sin(a) * 8),
          p);
    }
  }

  /// A "finger tap" ripple: small accent dot + two expanding rings.
  void _tapRipple(Canvas canvas, Offset at) {
    canvas.drawCircle(
        at,
        5,
        Paint()
          ..color = accent
          ..style = PaintingStyle.fill);
    for (final r in [11.0, 18.0]) {
      canvas.drawCircle(
          at,
          r,
          Paint()
            ..color = accent.withValues(alpha: r == 11.0 ? 0.5 : 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  /// A held fingertip: filled dot with white ring and soft halo.
  void _fingertip(Canvas canvas, Offset at) {
    canvas.drawCircle(
        at,
        13,
        Paint()
          ..color = accent.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        at,
        7,
        Paint()
          ..color = accent
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        at,
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  void _label(Canvas canvas, String text, Offset center,
      {double size = 10, Color color = Colors.white70}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color, fontSize: size, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _sunGlyph(Canvas canvas, Offset at, double r) {
    const amber = Color(0xFFFFC107);
    final p = Paint()
      ..color = amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(at, r, p);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawLine(
        at + Offset(math.cos(a) * (r + 3), math.sin(a) * (r + 3)),
        at + Offset(math.cos(a) * (r + 7), math.sin(a) * (r + 7)),
        p,
      );
    }
  }

  void _speakerGlyph(Canvas canvas, Offset at) {
    final p = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    // Cone.
    final path = Path()
      ..moveTo(at.dx - 9, at.dy - 4)
      ..lineTo(at.dx - 4, at.dy - 4)
      ..lineTo(at.dx + 1, at.dy - 9)
      ..lineTo(at.dx + 1, at.dy + 9)
      ..lineTo(at.dx - 4, at.dy + 4)
      ..lineTo(at.dx - 9, at.dy + 4)
      ..close();
    canvas.drawPath(path, p);
    // Sound waves.
    for (final r in [5.0, 9.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: at + const Offset(3, 0), radius: r),
        -0.9,
        1.8,
        false,
        p,
      );
    }
  }

  /// Tinted half of the screen (left or right) with up/down arrows in it.
  void _halfSwipe(Canvas canvas, Size size,
      {required bool leftHalf,
      required Color tint,
      required IconKindDoodle doodle}) {
    final phone = _phone(size);
    final screen = phone.deflate(3);
    final r = screen.outerRect;
    final half = leftHalf
        ? Rect.fromLTRB(r.left, r.top, r.center.dx, r.bottom)
        : Rect.fromLTRB(r.center.dx, r.top, r.right, r.bottom);
    canvas.save();
    canvas.clipRRect(screen);
    canvas.drawRect(
        half,
        Paint()
          ..color = tint.withValues(alpha: 0.14)
          ..style = PaintingStyle.fill);
    // Divider down the middle.
    canvas.drawLine(
        Offset(r.center.dx, r.top + 6),
        Offset(r.center.dx, r.bottom - 6),
        Paint()
          ..color = Colors.white24
          ..strokeWidth = 1);
    canvas.restore();

    final ax = half.center.dx;
    final cy = half.center.dy;
    _arrow(canvas, Offset(ax, cy - 8), Offset(ax, cy - 28), _accentPaint);
    _arrow(canvas, Offset(ax, cy + 8), Offset(ax, cy + 28), _accentPaint);
    if (doodle == IconKindDoodle.sun) {
      _sunGlyph(canvas, Offset(ax, r.top + 15), 5.5);
    } else {
      _speakerGlyph(canvas, Offset(ax, r.top + 17));
    }
  }

  // ---------- scene ---------------------------------------------------------

  @override
  void paint(Canvas canvas, Size size) {
    _drawPhone(canvas, size);
    final phone = _phone(size);
    final screen = phone.deflate(3);
    final c = screen.center;
    final r = screen.outerRect;

    switch (kind) {
      case GestureKind.singleTap:
        _tapRipple(canvas, c);
        break;

      case GestureKind.doubleTapSides:
        _tapRipple(canvas, Offset(r.left + r.width * 0.24, c.dy - 4));
        _tapRipple(canvas, Offset(r.right - r.width * 0.24, c.dy - 4));
        _label(canvas, '-10s',
            Offset(r.left + r.width * 0.24, r.bottom - 10));
        _label(canvas, '+10s',
            Offset(r.right - r.width * 0.24, r.bottom - 10));
        break;

      case GestureKind.doubleTapMiddle:
        _tapRipple(canvas, Offset(c.dx, c.dy - 2));
        // Pause bars (what the middle double-tap toggles).
        final p = Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.fill;
        canvas.drawRect(
            Rect.fromLTWH(c.dx - 6, c.dy + 14, 4, 12), p);
        canvas.drawRect(
            Rect.fromLTWH(c.dx + 2, c.dy + 14, 4, 12), p);
        break;

      case GestureKind.swipeBrightness:
        _halfSwipe(canvas, size,
            leftHalf: true,
            tint: const Color(0xFFFFC107),
            doodle: IconKindDoodle.sun);
        break;

      case GestureKind.swipeVolume:
        _halfSwipe(canvas, size,
            leftHalf: false,
            tint: accent,
            doodle: IconKindDoodle.speaker);
        break;

      case GestureKind.swipeSeek:
        // Fingertip sliding sideways across the screen, with the "+45s ·
        // 03:12" pill the real player shows while scrubbing.
        final fy = c.dy + 8;
        _fingertip(canvas, Offset(c.dx, fy));
        _arrow(canvas, Offset(c.dx - 16, fy), Offset(c.dx - 48, fy),
            _accentPaint);
        _arrow(canvas, Offset(c.dx + 16, fy), Offset(c.dx + 48, fy),
            _accentPaint);
        // Landing pill, like the indicator in the player.
        final pill = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, r.top + 13), width: 92, height: 18),
            const Radius.circular(9));
        canvas.drawRRect(
            pill,
            Paint()
              ..color = accent
              ..style = PaintingStyle.fill);
        _label(canvas, '+45s · 03:12', Offset(c.dx, r.top + 13),
            color: Colors.white, size: 9.5);
        _label(canvas, 'or the other way', Offset(c.dx, r.bottom - 9),
            size: 8.5);
        break;

      case GestureKind.pinchZoom:
        // Two fingertips spreading apart with outward arrows.
        final fa = Offset(c.dx - 26, c.dy + 14);
        final fb = Offset(c.dx + 26, c.dy + 14);
        _arrow(canvas, fa, Offset(fa.dx - 18, fa.dy - 18), _accentPaint);
        _arrow(canvas, fb, Offset(fb.dx + 18, fb.dy - 18), _accentPaint);
        _fingertip(canvas, fa);
        _fingertip(canvas, fb);
        _label(canvas, '1× → 4×', Offset(c.dx, r.bottom - 10));
        break;

      case GestureKind.holdSpeed:
        _fingertip(canvas, Offset(c.dx, c.dy + 10));
        // Persistent "2x" badge, like the one shown during a real boost.
        final badge = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, r.top + 13), width: 40, height: 18),
            const Radius.circular(9));
        canvas.drawRRect(
            badge,
            Paint()
              ..color = accent
              ..style = PaintingStyle.fill);
        _label(canvas, '2.0x', Offset(c.dx, r.top + 13),
            color: Colors.white, size: 10.5);
        break;
    }
  }

  @override
  bool shouldRepaint(_GesturePainter old) =>
      old.kind != kind || old.accent != accent;
}

enum IconKindDoodle { sun, speaker }
