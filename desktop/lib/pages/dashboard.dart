import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../health.dart';
import '../model.dart';
import '../strings.dart';
import '../widgets.dart';

String stateLabel(String s) => switch (s) {
  'NEAR' => 'Near',
  'LEAVING' => 'Moving away',
  'LOCKED' => 'Locked by StepAway',
  'AWAY' => 'Away',
  'OVERRIDE' => 'Unlocked manually',
  _ => 'Waiting for your device',
};

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.model, this.onCalibrate});
  final DaemonModel model;
  final VoidCallback? onCalibrate;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final r = model.latest;
    final fresh =
        r != null &&
        DateTime.now().difference(r.time) < const Duration(seconds: 10);
    final distance = fresh ? r.distance : null;
    final zone = DistanceGauge.zoneColor(
      c,
      distance,
      model.lockDistance,
      model.returnDistance,
    );
    final stateColor = switch (model.state) {
      'NEAR' => c.success,
      'LEAVING' => c.warning,
      'LOCKED' || 'AWAY' => c.danger,
      _ => c.textMuted,
    };

    Widget gauge(double gaugeSize) => GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DistanceGauge(
            distance: distance,
            lockAt: model.lockDistance,
            returnAt: model.returnDistance,
            size: gaugeSize,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (fresh)
                  AnimatedNumber(
                    value: r.distance,
                    builder: (context, v) => Text(
                      '${v.toStringAsFixed(1)} m',
                      key: const Key('distance-text'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall
                          ?.copyWith(color: zone),
                    ),
                  )
                else
                  Text(
                    S.noSignal,
                    key: const Key('distance-text'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (fresh)
                  Text(
                    '${r.rssi.toStringAsFixed(0)} dBm',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(
                scale: Tween(begin: 0.92, end: 1.0).animate(a),
                child: child,
              ),
            ),
            child: Container(
              key: ValueKey(
                'state-chip-${model.paused ? 'paused' : model.state}',
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: stateColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: stateColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(color: stateColor, size: 8),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      model.paused ? S.paused : stateLabel(model.state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${S.lockAt} ${model.lockDistance.toStringAsFixed(1)} m  ·  ${S.returnAt} ${model.returnDistance.toStringAsFixed(1)} m',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    final tiles = [
      StatTile(
        icon: Icons.network_cell_rounded,
        label: S.signal,
        value: fresh ? '${r.rssi.toStringAsFixed(0)} dBm' : '—',
      ),
      StatTile(
        icon: Icons.devices_rounded,
        label: S.device,
        value: model.phones.length > 1
            ? '${model.present.length} of ${model.phones.length} ${S.detectedCount}'
            : (model.phoneNearby ? S.detected : S.notDetected),
        color: model.phoneNearby ? c.success : c.textMuted,
      ),
      StatTile(
        icon: Icons.shield_rounded,
        label: S.protectionLabel,
        value: model.paused ? S.paused : S.active,
        color: model.paused ? c.warning : c.success,
      ),
    ];

    Widget tileRow(bool threeAcross) {
      if (threeAcross) {
        // equal width AND equal height, whatever the text inside
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: Reveal(index: 1 + i, child: tiles[i]),
                ),
              ],
            ],
          ),
        );
      }
      return Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Reveal(index: 1 + i, child: tiles[i]),
          ],
        ],
      );
    }

    Widget graph({required bool fill}) => GlassCard(
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            S.distanceOverTime,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 14),
          if (fill)
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 180),
                child: DistanceGraph(
                  distances: [for (final r in model.history) r.distance],
                  lockAt: model.lockDistance,
                  returnAt: model.returnDistance,
                ),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: DistanceGraph(
                distances: [for (final r in model.history) r.distance],
                lockAt: model.lockDistance,
                returnAt: model.returnDistance,
              ),
            ),
        ],
      ),
    );

    final banner =
        model.connected && model.phones.isNotEmpty && !model.calibrated
        ? Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GlassCard(
              key: const Key('calibrate-banner'),
              tint: c.warning,
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, box) {
                  final text = const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.notCalibratedTitle,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 2),
                      Text(S.notCalibratedBody),
                    ],
                  );
                  final button = FilledButton(
                    onPressed: onCalibrate,
                    child: const Text(S.calibrateNow),
                  );
                  if (box.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.tune, color: c.warning),
                            const SizedBox(width: 14),
                            Expanded(child: text),
                          ],
                        ),
                        const SizedBox(height: 12),
                        button,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Icon(Icons.tune, color: c.warning),
                      const SizedBox(width: 14),
                      Expanded(child: text),
                      const SizedBox(width: 12),
                      button,
                    ],
                  );
                },
              ),
            ),
          )
        : null;

    return ResponsiveBuilder(
      builder: (context, size, box) {
        final header = PageHeader(
          title: S.dashboard,
          subtitle: S.dashboardSubtitle,
          trailing: OutlinedButton.icon(
            key: const Key('pause-button'),
            onPressed: model.connected
                ? () => model.setPaused(!model.paused)
                : null,
            icon: Icon(
              model.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
            label: Text(model.paused ? S.resume : S.pause),
          ),
        );
        // two columns only when there is room for the gauge plus a useful right-hand side
        final twoColumns = box.maxWidth >= 640;
        final body = twoColumns
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: box.maxWidth >= 900 ? 330 : 290,
                      child: Reveal(
                        index: 0,
                        child: gauge(box.maxWidth >= 900 ? 260 : 220),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          tileRow(box.maxWidth >= 860),
                          const SizedBox(height: 16),
                          Expanded(
                            child: Reveal(index: 4, child: graph(fill: true)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Reveal(
                    index: 0,
                    child: gauge(box.maxWidth < 380 ? 200 : 240),
                  ),
                  const SizedBox(height: 14),
                  tileRow(false),
                  const SizedBox(height: 14),
                  Reveal(index: 4, child: graph(fill: false)),
                ],
              );
        return ListView(
          padding: EdgeInsets.only(bottom: size.isCompact ? 96 : 0),
          children: [
            header,
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: HealthCard(model: model),
            ),
            ?banner,
            body,
          ],
        );
      },
    );
  }
}
