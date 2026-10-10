import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import 'model.dart';
import 'strings.dart';

enum HealthLevel { ok, warn, info }

/// One line of the health check: what is fine, or what is wrong and how to fix it.
class HealthCheck {
  const HealthCheck(this.id, this.level, this.title, [this.fix]);
  final String id;
  final HealthLevel level;
  final String title;
  final String? fix;
}

/// Turns the daemon's state into a checklist that explains why StepAway is not locking or
/// unlocking. Pure, so it is easy to test.
List<HealthCheck> healthChecks(DaemonModel m) {
  const ok = HealthLevel.ok;
  const warn = HealthLevel.warn;
  const info = HealthLevel.info;
  if (!m.connected) {
    return const [HealthCheck('service', warn, S.hServiceBad, S.hServiceFix)];
  }
  final c = <HealthCheck>[
    const HealthCheck('service', ok, S.hServiceOk),
    m.scanning
        ? const HealthCheck('scan', ok, S.hScanOk)
        : const HealthCheck('scan', warn, S.hScanBad, S.hScanFix),
    m.phones.isNotEmpty
        ? const HealthCheck('paired', ok, S.hPairedOk)
        : const HealthCheck('paired', warn, S.hPairedBad, S.hPairedFix),
  ];
  if (m.phones.isNotEmpty) {
    c.add(
      m.phoneNearby
          ? const HealthCheck('signal', ok, S.hSignalOk)
          : const HealthCheck('signal', warn, S.hSignalBad, S.hSignalFix),
    );
    c.add(
      m.calibrated
          ? const HealthCheck('calibrated', ok, S.hCalibOk)
          : const HealthCheck('calibrated', info, S.hCalibBad, S.hCalibFix),
    );
  }
  c.add(
    m.paused
        ? const HealthCheck('active', warn, S.hActiveBad, S.hActiveFix)
        : const HealthCheck('active', ok, S.hActiveOk),
  );
  // Why unlock is not happening. "paused" and "no_signal" are already shown above.
  final unlock = switch (m.unlockBlock) {
    null => const HealthCheck('unlock', ok, S.hUnlockReady),
    'disabled' => const HealthCheck(
      'unlock',
      info,
      S.hUnlockOff,
      S.hUnlockOffFix,
    ),
    'first_login' => const HealthCheck(
      'unlock',
      info,
      S.hUnlockFirstLogin,
      S.hUnlockFirstLoginFix,
    ),
    'not_our_lock' => const HealthCheck(
      'unlock',
      info,
      S.hUnlockNotOurLock,
      S.hUnlockNotOurLockFix,
    ),
    'too_far' => const HealthCheck(
      'unlock',
      info,
      S.hUnlockTooFar,
      S.hUnlockTooFarFix,
    ),
    'return_grace' => const HealthCheck(
      'unlock',
      info,
      S.hUnlockGrace,
      S.hUnlockGraceFix,
    ),
    'phone_locked' => const HealthCheck(
      'unlock',
      info,
      S.hUnlockPhoneLocked,
      S.hUnlockPhoneLockedFix,
    ),
    'needs_fresh_auth' => const HealthCheck(
      'unlock',
      info,
      S.hUnlockAuth,
      S.hUnlockAuthFix,
    ),
    _ => null, // 'paused' / 'no_signal' (or a newer reason) are covered by the rows above
  };
  if (unlock != null) c.add(unlock);
  return c;
}

/// Dashboard card: collapsed to one line when all is well, open with the fixes when not.
class HealthCard extends StatefulWidget {
  const HealthCard({super.key, required this.model});
  final DaemonModel model;

  @override
  State<HealthCard> createState() => _HealthCardState();
}

class _HealthCardState extends State<HealthCard> {
  bool? _userOpen; // null: follow whether there is something to fix

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final checks = healthChecks(widget.model);
    final issues = checks.where((h) => h.level == HealthLevel.warn).length;
    final open = _userOpen ?? (issues > 0);
    final color = issues > 0 ? c.warning : c.success;
    final summary = issues > 0 ? S.healthIssues(issues) : S.healthAllGood;
    return GlassCard(
      key: const Key('health-card'),
      tint: issues > 0 ? c.warning : null,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('health-toggle'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _userOpen = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    issues > 0
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_rounded,
                    color: color,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${S.healthTitle}: $summary',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [for (final h in checks) _Row(h: h, colors: c)],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.h, required this.colors});
  final HealthCheck h;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (h.level) {
      HealthLevel.ok => (Icons.check_circle_rounded, colors.success),
      HealthLevel.warn => (Icons.error_rounded, colors.warning),
      HealthLevel.info => (Icons.info_outline_rounded, colors.textMuted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.title, key: Key('health-${h.id}')),
                if (h.fix != null)
                  Text(
                    h.fix!,
                    style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
