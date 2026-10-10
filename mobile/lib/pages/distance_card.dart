import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../controller.dart';
import '../distance.dart';
import '../strings.dart';

/// Live distance to the computer, measured from its Bluetooth beacon.
class DistanceCard extends StatelessWidget {
  const DistanceCard({super.key, required this.app});
  final AppController app;

  static const lockAt = 3.0;
  static const returnAt = 2.0;

  String _zoneLabel(Zone z) => switch (z) {
    Zone.near => S.zoneNear,
    Zone.mid => S.zoneMid,
    Zone.far => S.zoneFar,
  };

  @override
  Widget build(BuildContext context) {
    final s = app.status;
    if (s.pairings.isEmpty) return const SizedBox.shrink();
    final c = AppColors.of(context);
    final tracker = app.primary;
    final distance = app.distanceM;

    final Widget content;
    if (!s.scanGranted) {
      content = _Message(
        key: const ValueKey('need-scan'),
        icon: Icons.radar_rounded,
        color: c.accent[1],
        title: S.distTitle,
        body: S.distNeedsScan,
        action: GradientButton(
          key: const Key('allow-scan'),
          label: S.distAllow,
          icon: Icons.bluetooth_searching_rounded,
          onPressed: app.requestScanPermission,
        ),
      );
    } else if (distance == null || tracker == null) {
      content = Column(
        key: const ValueKey('searching'),
        children: [
          Ripples(
            color: c.accent[0],
            active: app.beaconRunning,
            size: 150,
            child: Icon(Icons.computer_rounded, size: 40, color: c.accent[0]),
          ),
          const SizedBox(height: 8),
          Text(
            S.distSearching,
            key: const Key('dist-searching'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            app.beaconError ?? S.distHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    } else {
      final zone = DistanceGauge.zoneColor(c, distance, lockAt, returnAt);
      content = Column(
        key: const ValueKey('measured'),
        children: [
          DistanceGauge(
            distance: distance,
            lockAt: lockAt,
            returnAt: returnAt,
            size: 210,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedNumber(
                  value: distance,
                  builder: (context, v) => Text(
                    '${v.toStringAsFixed(1)} ${S.distanceUnit}',
                    key: const Key('distance-value'),
                    style: Theme.of(context).textTheme.displaySmall
                        ?.copyWith(color: zone),
                  ),
                ),
                Text(
                  _zoneLabel(tracker.zone),
                  key: const Key('distance-zone'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 80,
            width: double.infinity,
            child: DistanceGraph(
              distances: List.of(tracker.history),
              lockAt: lockAt,
              returnAt: returnAt,
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            key: const Key('calibrate-here'),
            onPressed: () async {
              HapticFeedback.selectionClick();
              final messenger = ScaffoldMessenger.of(context);
              final ok = await app.calibrateHere();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(ok ? S.distCalibrated : S.distCalibrateFailed),
                ),
              );
            },
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text(S.distCalibrate),
          ),
          Text(
            S.distCalibrateHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    return Reveal(
      index: 1,
      child: GlassCard(
        key: const Key('distance-card'),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.social_distance_rounded,
                  size: 20,
                  color: c.accent[1],
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    S.distTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PopIn(
          child: StatusOrb(color: color, icon: icon, size: 84),
        ),
        const SizedBox(height: 14),
        Text(
          body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    );
  }
}
