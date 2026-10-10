import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fades and slides its child in the first time it is shown. Give each item in a list a growing
/// [index] for a staggered entrance. Uses a single controller (no timers), so tests can settle.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 70),
    this.duration = const Duration(milliseconds: 520),
    this.offset = const Offset(0, 0.06),
  });

  final Widget child;
  final int index;
  final Duration stagger;
  final Duration duration;
  final Offset offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    final delay = widget.stagger * math.min(widget.index, 12);
    final total = delay + widget.duration;
    _ctl = AnimationController(vsync: this, duration: total);
    _curve = CurvedAnimation(
      parent: _ctl,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
    );
    _ctl.forward();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: widget.offset, end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Smoothly counts from the previous value to the new one.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 450),
  });

  final double value;
  final Widget Function(BuildContext context, double value) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => builder(context, v),
    );
  }
}

/// Cross-fades between pages with a short upward slide; pass a different [pageKey] per page.
class FadeSlideSwitcher extends StatelessWidget {
  const FadeSlideSwitcher({
    super.key,
    required this.pageKey,
    required this.child,
    this.duration = const Duration(milliseconds: 320),
  });
  final Object pageKey;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey(pageKey), child: child),
    );
  }
}

/// Scales its child in with a springy overshoot (success marks, confirmations).
class PopIn extends StatelessWidget {
  const PopIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 650),
  });
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(
        scale: v.clamp(0.0, 1.4),
        child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      ),
      child: child,
    );
  }
}

/// Expanding rings, like radar or a sonar ping. Runs only while [active].
class Ripples extends StatefulWidget {
  const Ripples({
    super.key,
    required this.color,
    required this.active,
    this.size = 240,
    this.rings = 3,
    required this.child,
  });
  final Color color;
  final bool active;
  final double size;
  final int rings;
  final Widget child;

  @override
  State<Ripples> createState() => _RipplesState();
}

class _RipplesState extends State<Ripples> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctl.repeat();
  }

  @override
  void didUpdateWidget(Ripples old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctl.isAnimating) {
      _ctl.repeat();
    } else if (!widget.active && _ctl.isAnimating) {
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
    // Own layer: the rings repaint every frame and must not drag the blurred glass around them.
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _ctl,
          builder: (context, child) => CustomPaint(
            painter: _RipplePainter(
              widget.active ? _ctl.value : 0,
              widget.color,
              widget.rings,
              widget.active,
            ),
            child: Center(child: child),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.t, this.color, this.rings, this.active);
  final double t;
  final Color color;
  final int rings;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    for (var i = 0; i < rings; i++) {
      final p = (t + i / rings) % 1.0;
      final radius = maxR * (0.35 + 0.65 * Curves.easeOut.transform(p));
      final alpha = (1 - p) * 0.35;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - p) + 0.5,
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.t != t || old.color != color || old.active != active;
}

/// Gives any tappable child a soft press-down scale.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
