import 'dart:ui';

import 'package:flutter/material.dart';

import 'colors.dart';

/// Full-screen gradient with soft colour blobs: the "scenery" that the glass blurs.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: c.bg,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        Positioned.fill(child: CustomPaint(painter: _BlobPainter(c.blobs))),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.colors);
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset f, double r, Color color) {
      final center = Offset(size.width * f.dx, size.height * f.dy);
      final radius = size.shortestSide * r;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    blob(const Offset(0.12, 0.10), 0.75, colors[0]);
    blob(const Offset(0.92, 0.30), 0.85, colors[1]);
    blob(const Offset(0.35, 0.98), 0.80, colors[2]);
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.colors != colors;
}

/// Frosted-glass surface: blurs what is behind it, with a translucent gradient fill,
/// a thin light border and a soft shadow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.radius = 24,
    this.blur = 22,
    this.strong = false,
    this.tint,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double blur;
  final bool strong;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final shape = BorderRadius.circular(radius);
    final border = RoundedSuperellipseBorder(
      borderRadius: shape,
      side: BorderSide(color: c.glassBorder),
    );
    final fill = strong ? c.glassFillStrong : c.glassFill;
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(customBorder: border, onTap: onTap, child: content),
      );
    }
    return Padding(
      padding: margin,
      child: CustomPaint(
        painter: _OuterShadow(radius, c.shadow),
        child: ClipRSuperellipse(
          borderRadius: shape,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: border,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      (tint ?? Colors.transparent).withValues(alpha: 0.10),
                      fill,
                    ),
                    fill.withValues(alpha: fill.a * 0.55),
                  ],
                ),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft drop shadow drawn only outside the card, so it never shows through the glass.
class _OuterShadow extends CustomPainter {
  _OuterShadow(this.radius, this.color);
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RSuperellipse.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(-120, -120, size.width + 240, size.height + 240))
      ..addRSuperellipse(shape);
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        (Offset.zero & size).shift(const Offset(0, 10)),
        Radius.circular(radius),
      ),
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadow old) =>
      old.radius != radius || old.color != color;
}

/// Accent-gradient button used for the main action on a screen.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expanded = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: c.accentGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: c.accent[1].withValues(alpha: 0.45),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A glass segmented control (used for System / Light / Dark).
class GlassSegmented<T> extends StatelessWidget {
  const GlassSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final T value;
  final List<GlassSegment<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in options)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: o.value == value,
                  label: o.label,
                  child: GestureDetector(
                    key: Key('segment-${o.label}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(o.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: o.value == value ? c.accentGradient : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            o.icon,
                            size: 18,
                            color: o.value == value
                                ? Colors.white
                                : scheme.onSurface.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              o.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: o.value == value
                                    ? Colors.white
                                    : scheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GlassSegment<T> {
  const GlassSegment(this.value, this.label, this.icon);
  final T value;
  final String label;
  final IconData icon;
}

/// Round status indicator: a glowing gradient disc with an icon. Optionally pulses.
class StatusOrb extends StatefulWidget {
  const StatusOrb({
    super.key,
    required this.color,
    required this.icon,
    this.size = 112,
    this.pulse = false,
  });
  final Color color;
  final IconData icon;
  final double size;
  final bool pulse;

  @override
  State<StatusOrb> createState() => _StatusOrbState();
}

class _StatusOrbState extends State<StatusOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _ctl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StatusOrb old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_ctl.isAnimating) {
      _ctl.repeat(reverse: true);
    } else if (!widget.pulse && _ctl.isAnimating) {
      _ctl.stop();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, _) {
        final glow = widget.pulse ? 0.25 + 0.25 * _ctl.value : 0.3;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                widget.color.withValues(alpha: 0.95),
                widget.color.withValues(alpha: 0.55),
              ],
              center: const Alignment(-0.3, -0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: glow),
                blurRadius: 50 + 30 * (widget.pulse ? _ctl.value : 0),
                spreadRadius: 4,
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Icon(
            widget.icon,
            size: widget.size * 0.42,
            color: Colors.white,
          ),
        );
      },
    );
  }
}

/// Small coloured dot with a soft glow.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 10});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
      ],
    ),
  );
}
