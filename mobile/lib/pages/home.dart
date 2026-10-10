import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../controller.dart';
import 'distance_card.dart';
import '../strings.dart';
import '../widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.app, required this.onOpenComputers});
  final AppController app;
  final VoidCallback onOpenComputers;

  ({Color color, IconData icon, String title, String subtitle, bool pulse})
  _hero(AppColors c) {
    final s = app.status;
    if (s.pairings.isEmpty) {
      return (
        color: const Color(0xFF6366F1),
        icon: Icons.link_rounded,
        title: S.heroNoPair,
        subtitle: S.heroNoPairSub,
        pulse: false,
      );
    }
    if (!s.protection) {
      return (
        color: c.textMuted,
        icon: Icons.shield_outlined,
        title: S.heroOff,
        subtitle: S.protectionOff,
        pulse: false,
      );
    }
    if (s.advertising) {
      return (
        color: c.success,
        icon: Icons.shield_rounded,
        title: S.heroOn,
        subtitle: S.protectionOn,
        pulse: true,
      );
    }
    return (
      color: c.warning,
      icon: Icons.error_outline_rounded,
      title: S.heroError,
      subtitle: s.error ?? S.idle,
      pulse: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = app.status;
    final c = AppColors.of(context);
    final hero = _hero(c);

    Widget heroCard(double orbArea) => Reveal(
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(
          children: [
            Ripples(
              color: hero.color,
              active: hero.pulse,
              size: orbArea,
              child: Hero(
                tag: 'orb',
                child: StatusOrb(
                  color: hero.color,
                  icon: hero.icon,
                  pulse: hero.pulse,
                  size: orbArea * 0.45,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.15),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(hero.title),
                children: [
                  Text(
                    hero.title,
                    key: const Key('hero-title'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hero.subtitle,
                    key: const Key('advert-status'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              key: const Key('protection-switch'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text(
                S.protection,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              secondary: Icon(
                Icons.shield_moon_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              value: s.protection,
              onChanged: s.pairings.isEmpty
                  ? null
                  : (v) {
                      HapticFeedback.mediumImpact();
                      app.setProtection(v);
                    },
            ),
          ],
        ),
      ),
    );

    final details = <Widget>[
      DistanceCard(app: app),
      const SizedBox(height: 14),
      Reveal(
        index: 1,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            StatusChip(
              icon: Icons.bluetooth_rounded,
              label: S.chipBluetooth,
              value: s.bluetoothOn ? S.chipOn : S.chipOff,
              color: s.bluetoothOn ? c.success : c.danger,
            ),
            StatusChip(
              icon: Icons.cell_tower_rounded,
              label: S.chipBroadcast,
              value: s.advertising ? S.chipOn : S.chipOff,
              color: s.advertising ? c.success : c.textMuted,
            ),
            StatusChip(
              icon: Icons.battery_charging_full_rounded,
              label: S.chipBattery,
              value: s.batteryUnrestricted ? S.chipOk : S.chipLimited,
              color: s.batteryUnrestricted ? c.success : c.warning,
            ),
          ],
        ),
      ),
      if (!s.bluetoothOn)
        Notice(
          icon: Icons.bluetooth_disabled_rounded,
          color: c.danger,
          text: S.bluetoothOff,
        ),
      if (!s.permissionsGranted)
        Notice(
          icon: Icons.security_rounded,
          color: c.warning,
          text: S.permissionsHelp,
          actionLabel: S.grant,
          onAction: app.requestPermissions,
        ),
      if (s.protection && !s.batteryUnrestricted)
        Notice(
          icon: Icons.battery_alert_rounded,
          color: c.warning,
          title: S.battery,
          text: S.batteryHelp,
          actionLabel: S.openSettings,
          onAction: app.native.batterySettings,
        ),
      const SizedBox(height: 14),
      Reveal(
        index: 2,
        child: GlassCard(
          onTap: onOpenComputers,
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
                child: const Icon(Icons.computer_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.computers,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.pairings.isEmpty
                          ? S.summaryNone
                          : s.pairings.map((p) => p.name).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final twoColumns = box.maxWidth >= 640;
        final pad = EdgeInsets.fromLTRB(20, 8, 20, bottomNavPadding(context));
        if (twoColumns) {
          return ListView(
            padding: pad,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 340, child: heroCard(250)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: details,
                    ),
                  ),
                ],
              ),
            ],
          );
        }
        // phones: the orb shrinks on very narrow screens so nothing is squeezed
        final orb = (box.maxWidth - 80).clamp(180.0, 250.0);
        return ListView(
          padding: pad,
          children: [heroCard(orb), const SizedBox(height: 14), ...details],
        );
      },
    );
  }
}
