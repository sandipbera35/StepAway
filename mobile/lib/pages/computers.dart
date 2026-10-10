import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../controller.dart';
import '../strings.dart';
import '../widgets.dart';

class ComputersPage extends StatelessWidget {
  const ComputersPage({super.key, required this.app, required this.onPair});
  final AppController app;
  final VoidCallback onPair;

  Future<bool> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(S.removeTitle),
        content: const Text(S.removeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text(S.remove),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final pairings = app.status.pairings;
    return MaxWidth(
      maxWidth: 640,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, bottomNavPadding(context)),
        children: [
          const Reveal(
            child: TabHeader(title: S.tabComputers, subtitle: S.computersSub),
          ),
          const SizedBox(height: 20),
          if (pairings.isEmpty)
            Reveal(
              index: 1,
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                  vertical: 36,
                  horizontal: 20,
                ),
                child: Column(
                  children: [
                    const PopIn(
                      child: StatusOrb(
                        color: Color(0xFF6366F1),
                        icon: Icons.computer_rounded,
                        size: 96,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      S.emptyComputersTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      S.emptyComputersBody,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          for (final (i, p) in pairings.indexed)
            Reveal(
              key: ValueKey('computer-${p.id}'),
              index: i + 1,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Dismissible(
                  key: ValueKey('dismiss-${p.id}'),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmRemove(context),
                  onDismissed: (_) {
                    HapticFeedback.mediumImpact();
                    app.removePairing(p.id);
                  },
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: ShapeDecoration(
                      color: c.danger.withValues(alpha: 0.85),
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_rounded,
                      color: Colors.white,
                    ),
                  ),
                  child: GlassCard(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: c.accentGradient,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(
                            Icons.computer_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  StatusDot(color: c.success, size: 7),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Paired',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: S.remove,
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: c.danger,
                          ),
                          onPressed: () async {
                            if (await _confirmRemove(context)) {
                              await app.removePairing(p.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Reveal(
            index: pairings.length + 2,
            child: GradientButton(
              key: const Key('scan-button'),
              label: S.pairComputer,
              icon: Icons.add_rounded,
              expanded: true,
              onPressed: onPair,
            ),
          ),
        ],
      ),
    );
  }
}
