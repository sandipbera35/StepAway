import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../controller.dart';
import '../strings.dart';

/// First-run introduction. Its logo orb flies into place on the home screen (a Hero).
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.app, required this.onDone});
  final AppController app;
  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pages = PageController();
  int _page = 0;
  static const _count = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    HapticFeedback.selectionClick();
    if (_page < _count - 1) {
      await _pages.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final last = _page == _count - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: last ? 0 : 1,
                  child: TextButton(
                    key: const Key('onboarding-skip'),
                    onPressed: last ? null : widget.onDone,
                    child: const Text(S.skip),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Slide(
                    visual: Hero(
                      tag: 'orb',
                      child: StatusOrb(
                        color: c.accent[1],
                        icon: Icons.shield_rounded,
                        size: 160,
                        pulse: false,
                      ),
                    ),
                    title: S.ob1Title,
                    body: S.ob1Body,
                  ),
                  _StepsSlide(),
                  _Slide(
                    visual: const PopIn(
                      child: StatusOrb(
                        color: Color(0xFF22D3EE),
                        icon: Icons.bluetooth_rounded,
                        size: 140,
                      ),
                    ),
                    title: S.ob3Title,
                    body: S.ob3Body,
                    action: GradientButton(
                      key: const Key('onboarding-allow'),
                      label: S.allowAccess,
                      icon: Icons.lock_open_rounded,
                      onPressed: widget.app.requestPermissions,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: i == _page ? c.accentGradient : null,
                      color: i == _page ? null : c.glassBorder,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
              child: GradientButton(
                key: const Key('onboarding-next'),
                label: last ? S.getStarted : S.next,
                icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                expanded: true,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.visual,
    required this.title,
    required this.body,
    this.action,
  });
  final Widget visual;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          visual,
          const SizedBox(height: 36),
          Reveal(
            index: 1,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 12),
          Reveal(
            index: 2,
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: AppColors.of(context).textMuted),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 26),
            Reveal(index: 3, child: action!),
          ],
        ],
      ),
    );
  }
}

class _StepsSlide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const steps = [
      (Icons.bluetooth_rounded, S.ob2a),
      (Icons.social_distance_rounded, S.ob2b),
      (Icons.lock_rounded, S.ob2c),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Reveal(
            child: Text(
              S.ob2Title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 28),
          for (final (i, s) in steps.indexed)
            Reveal(
              index: i + 1,
              child: GlassCard(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: c.accentGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(s.$1, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        s.$2,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
