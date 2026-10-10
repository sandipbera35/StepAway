import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../strings.dart';
import '../uninstall.dart';

/// Full-screen "removing StepAway" view: pulsing signal rings while it works, a progress bar,
/// a checklist that ticks off, and a drawn check mark when it is done.
class UninstallScreen extends StatefulWidget {
  const UninstallScreen({
    super.key,
    required this.controller,
    required this.onClose,
  });
  final UninstallController controller;
  final VoidCallback onClose;

  @override
  State<UninstallScreen> createState() => _UninstallScreenState();
}

class _UninstallScreenState extends State<UninstallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final AnimationController _done = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  UninstallController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _pulse.repeat();
    _c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.start());
  }

  void _onChange() {
    if (_c.finished && _pulse.isAnimating) {
      _pulse.stop();
      if (_c.succeeded) _done.forward();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _pulse.dispose();
    _done.dispose();
    super.dispose();
  }

  String get _title {
    if (_c.failed) return S.uninstallFailedTitle;
    return _c.finished ? S.uninstallDoneTitle : S.uninstallingTitle;
  }

  String get _subtitle {
    if (_c.failed) return _c.error ?? '';
    if (!_c.finished) {
      return _c.uninstaller.needsAdmin
          ? S.uninstallingSubtitleAdmin
          : S.uninstallingSubtitle;
    }
    return _c.removeData ? S.uninstallDoneData : S.uninstallDoneKept;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    key: const Key('uninstall-hero'),
                    width: 220,
                    height: 220,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_pulse, _done]),
                      builder: (context, _) => CustomPaint(
                        painter: _HeroPainter(
                          pulse: _pulse.value,
                          done: Curves.easeOutCubic.transform(_done.value),
                          progress: _c.progress,
                          failed: _c.failed,
                          colors: c,
                        ),
                        child: Center(
                          child: Opacity(
                            opacity: _c.failed
                                ? 0.0
                                : (1 - _done.value * 1.4).clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale:
                                  (1 - 0.25 * _c.progress) *
                                  (1 - 0.5 * _done.value),
                              child: const StepAwayLogo(size: 84),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Text(
                      _title,
                      key: ValueKey(_title),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _subtitle,
                    key: const Key('uninstall-subtitle'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _c.failed ? c.danger : null,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _Bar(value: _c.progress, colors: c, failed: _c.failed),
                  const SizedBox(height: 22),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _c.steps.length; i++)
                          Reveal(
                            index: i,
                            child: _StepRow(
                              label: S.uninstallStep(_c.steps[i]),
                              status: _c.status[_c.steps[i]]!,
                              colors: c,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_c.succeeded) ...[
                    const SizedBox(height: 16),
                    Reveal(
                      child: Text(
                        _c.uninstaller.deletesAfterExit
                            ? '${S.uninstallPhoneHint} ${S.uninstallDeferredHint}'
                            : S.uninstallPhoneHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                  if (_c.finished) ...[
                    const SizedBox(height: 22),
                    Reveal(
                      child: GradientButton(
                        key: const Key('uninstall-close'),
                        label: S.close,
                        icon: Icons.close_rounded,
                        onPressed: widget.onClose,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.colors, required this.failed});
  final double value;
  final AppColors colors;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 8,
          color: colors.glassFillStrong,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: failed ? null : colors.accentGradient,
                color: failed ? colors.danger : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.status,
    required this.colors,
  });
  final String label;
  final StepStatus status;
  final AppColors colors;

  Widget _icon() {
    switch (status) {
      case StepStatus.pending:
        return Icon(
          Icons.circle_outlined,
          key: const ValueKey('p'),
          size: 20,
          color: colors.glassBorder,
        );
      case StepStatus.running:
        return const SizedBox(
          key: ValueKey('r'),
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        );
      case StepStatus.done:
        return Icon(
          Icons.check_circle_rounded,
          key: const ValueKey('d'),
          size: 22,
          color: colors.success,
        );
      case StepStatus.skipped:
        return Icon(
          Icons.remove_circle_outline_rounded,
          key: const ValueKey('s'),
          size: 20,
          color: colors.warning,
        );
      case StepStatus.failed:
        return Icon(
          Icons.error_rounded,
          key: const ValueKey('f'),
          size: 22,
          color: colors.danger,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dim = status == StepStatus.pending;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, a) => ScaleTransition(
                  scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                  child: FadeTransition(opacity: a, child: child),
                ),
                child: _icon(),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: dim ? 0.5 : 1,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rings that ripple outwards from the logo while working, then collapse into a drawn check
/// mark (or a cross when something failed).
class _HeroPainter extends CustomPainter {
  _HeroPainter({
    required this.pulse,
    required this.done,
    required this.progress,
    required this.failed,
    required this.colors,
  });
  final double pulse;
  final double done;
  final double progress;
  final bool failed;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    final accent = failed ? colors.danger : colors.accent[1];

    // Ripples: three rings, offset in time, growing and fading.
    final ringStrength = failed ? 0.0 : (1 - done);
    if (ringStrength > 0) {
      for (var i = 0; i < 3; i++) {
        final t = (pulse + i / 3) % 1.0;
        final r = maxR * (0.45 + 0.55 * t);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = accent.withValues(alpha: (1 - t) * 0.5 * ringStrength);
        canvas.drawCircle(center, r, paint);
      }
    }

    // Progress arc around the logo.
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..color = accent.withValues(alpha: 0.9 * (1 - done));
    if (done < 1) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: maxR * 0.5),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        arcPaint,
      );
    }

    // Completion badge: circle that grows in, with the mark drawn on top.
    if (done > 0 || failed) {
      final k = failed ? 1.0 : done;
      final badge = failed ? colors.danger : colors.success;
      final r = maxR * 0.5 * Curves.easeOutBack.transform(k.clamp(0.0, 1.0));
      canvas.drawCircle(
        center,
        r,
        Paint()..color = badge.withValues(alpha: 0.18),
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = badge,
      );
      final mark = Path();
      if (failed) {
        final d = r * 0.38;
        mark
          ..moveTo(center.dx - d, center.dy - d)
          ..lineTo(center.dx + d, center.dy + d)
          ..moveTo(center.dx + d, center.dy - d)
          ..lineTo(center.dx - d, center.dy + d);
      } else {
        mark
          ..moveTo(center.dx - r * 0.42, center.dy + r * 0.02)
          ..lineTo(center.dx - r * 0.1, center.dy + r * 0.34)
          ..lineTo(center.dx + r * 0.46, center.dy - r * 0.30);
      }
      final draw = failed ? 1.0 : ((k - 0.35) / 0.65).clamp(0.0, 1.0);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 7
        ..color = badge;
      for (final m in mark.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * draw), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_HeroPainter old) =>
      old.pulse != pulse ||
      old.done != done ||
      old.progress != progress ||
      old.failed != failed;
}
