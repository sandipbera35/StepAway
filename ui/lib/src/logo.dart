import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'colors.dart';

/// App mark: a gradient tile with signal arcs radiating from a point (someone stepping away).
class StepAwayLogo extends StatelessWidget {
  const StepAwayLogo({super.key, this.size = 32, this.shadow = true});
  final double size;

  /// Soft glow under the tile; switch off when rendering launcher icons.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: c.accentGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: c.accent[1].withValues(alpha: 0.4),
                  blurRadius: size * 0.5,
                  offset: Offset(0, size * 0.15),
                ),
              ]
            : null,
      ),
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * 0.30, size.height * 0.70);
    final stroke = size.width * 0.075;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i <= 3; i++) {
      final r = size.width * 0.17 * i;
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: r),
        -math.pi / 2 + 0.15,
        math.pi / 2 - 0.3,
        false,
        paint..color = Colors.white.withValues(alpha: 1.1 - i * 0.28),
      );
    }
    canvas.drawCircle(origin, stroke * 1.25, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => false;
}
