import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'colors.dart';

/// Ring gauge: how far away the phone is relative to the lock distance.
class DistanceGauge extends StatelessWidget {
  const DistanceGauge({
    super.key,
    required this.distance,
    required this.lockAt,
    required this.returnAt,
    required this.child,
    this.size = 260,
  });

  final double? distance;
  final double lockAt;
  final double returnAt;
  final Widget child;
  final double size;

  static Color zoneColor(
    AppColors c,
    double? d,
    double lockAt,
    double returnAt,
  ) {
    if (d == null) return c.textMuted;
    if (d <= returnAt) return c.success;
    if (d <= lockAt) return c.warning;
    return c.danger;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final max = lockAt * 2;
    final target = distance == null ? 0.0 : (distance! / max).clamp(0.0, 1.0);
    final color = zoneColor(c, distance, lockAt, returnAt);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: target),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(
          painter: _GaugePainter(
            value,
            color,
            c.glassBorder,
            returnAt / max,
            lockAt / max,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(
    this.progress,
    this.color,
    this.track,
    this.returnFrac,
    this.lockFrac,
  );
  final double progress;
  final Color color;
  final Color track;
  final double returnFrac;
  final double lockFrac;

  static const _start = 3 * math.pi / 4;
  static const _sweep = 3 * math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - stroke,
    );
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    if (progress > 0.001) {
      final arc = Paint()
        ..shader = SweepGradient(
          startAngle: _start,
          endAngle: _start + _sweep,
          colors: [color.withValues(alpha: 0.55), color],
          transform: const GradientRotation(0),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        _start,
        _sweep * progress,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.7
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      canvas.drawArc(rect, _start, _sweep * progress, false, arc);
    }
    for (final f in [returnFrac, lockFrac]) {
      final a = _start + _sweep * f.clamp(0.0, 1.0);
      final r1 = rect.width / 2 - stroke * 0.9;
      final r2 = rect.width / 2 + stroke * 0.9;
      final c0 = rect.center;
      canvas.drawLine(
        c0 + Offset(math.cos(a), math.sin(a)) * r1,
        c0 + Offset(math.cos(a), math.sin(a)) * r2,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// Live distance line with a gradient fill and the lock / return thresholds.
class DistanceGraph extends StatelessWidget {
  const DistanceGraph({
    super.key,
    required this.distances,
    required this.lockAt,
    required this.returnAt,
  });
  final List<double> distances;
  final double lockAt;
  final double returnAt;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CustomPaint(
      painter: _GraphPainter(distances, lockAt, returnAt, c),
      size: Size.infinite,
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.h, this.lockAt, this.returnAt, this.c);
  final List<double> h;
  final double lockAt, returnAt;
  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    var maxY = lockAt * 2;
    for (final r in h) {
      if (r > maxY) maxY = r;
    }
    maxY = maxY.clamp(2.0, 20.0);
    double y(double d) => size.height - (d.clamp(0, maxY) / maxY) * size.height;

    void threshold(double d, Color color, String label) {
      final p = Paint()
        ..color = color.withValues(alpha: 0.8)
        ..strokeWidth = 1.2;
      const dash = 6.0;
      for (double x = 0; x < size.width; x += dash * 2) {
        canvas.drawLine(
          Offset(x, y(d)),
          Offset(math.min(x + dash, size.width), y(d)),
          p,
        );
      }
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'packages/stepaway_ui/Inter',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 4, y(d) - tp.height - 2));
    }

    threshold(lockAt, c.danger, '${lockAt.toStringAsFixed(1)} m lock');
    threshold(returnAt, c.success, '${returnAt.toStringAsFixed(1)} m back');
    if (h.length < 2) return;

    final line = Path();
    for (var i = 0; i < h.length; i++) {
      final x = size.width * i / (h.length - 1);
      final py = y(h[i]);
      i == 0 ? line.moveTo(x, py) : line.lineTo(x, py);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.accent[1].withValues(alpha: 0.35),
            c.accent[1].withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..shader = LinearGradient(
          colors: [c.accent[0], c.accent[2]],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
