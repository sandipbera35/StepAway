import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../model.dart';
import '../strings.dart';
import '../widgets.dart';

String _measuringLabel(DaemonModel m) {
  final started = m.calibStarted;
  if (started == null) return S.measuring;
  final elapsed = DateTime.now().difference(started).inMilliseconds;
  if (elapsed < 5000) {
    return '${S.getReady} ${((5000 - elapsed) / 1000).ceil()}${S.seconds}';
  }
  return S.measuring;
}

class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key, required this.model});
  final DaemonModel model;

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (widget.model.calib == CalibPhase.measuring && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final c = AppColors.of(context);
    final step = m.calibStep == 'near' ? 0 : 1;
    final running =
        m.calib == CalibPhase.nearReady ||
        m.calib == CalibPhase.farReady ||
        m.calib == CalibPhase.measuring;

    final List<Widget> body = switch (m.calib) {
      CalibPhase.idle => [
        const Text(S.calibrationIntro),
        const SizedBox(height: 24),
        GradientButton(
          label: S.calibrate,
          icon: Icons.tune_rounded,
          onPressed: m.connected ? m.beginCalibration : null,
        ),
      ],
      CalibPhase.nearReady || CalibPhase.farReady => [
        Text(m.calibStep == 'near' ? S.calibNear : S.calibFar),
        const SizedBox(height: 24),
        GradientButton(
          key: const Key('calib-start'),
          label: S.startMeasure,
          icon: Icons.play_arrow_rounded,
          onPressed: m.runCalibrationStep,
        ),
      ],
      CalibPhase.measuring => [
        Text(
          _measuringLabel(m),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: m.calibStarted == null
                ? null
                : (DateTime.now().difference(m.calibStarted!).inMilliseconds /
                          15000)
                      .clamp(0.0, 1.0),
          ),
        ),
      ],
      CalibPhase.done => [
        Center(
          child: Icon(Icons.check_circle_rounded, color: c.success, size: 72),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            S.calibDone,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton(
            onPressed: m.beginCalibration,
            child: const Text(S.again),
          ),
        ),
      ],
      CalibPhase.failed => [
        Text(
          m.calibMessage ?? 'Calibration failed',
          style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        GradientButton(label: S.again, onPressed: m.beginCalibration),
      ],
    };

    return ListView(
      children: [
        const PageHeader(title: S.calibrate, subtitle: S.calibrateSubtitle),
        const SizedBox(height: 20),
        if (m.phones.length > 1 &&
            (m.calib == CalibPhase.idle ||
                m.calib == CalibPhase.done ||
                m.calib == CalibPhase.failed)) ...[
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.devices_rounded),
                    const SizedBox(width: 14),
                    const Text(
                      S.calibrateWhich,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    DropdownButton<int>(
                      key: const Key('calib-device'),
                      value: m.phones.any((p) => p.id == m.calibDevice)
                          ? m.calibDevice
                          : m.phones.first.id,
                      underline: const SizedBox.shrink(),
                      onChanged: m.selectCalibDevice,
                      items: [
                        for (final p in m.phones)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: GlassCard(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (running) ...[
                    Row(
                      children: [
                        _StepDot(
                          number: 1,
                          label: S.step1,
                          active: step == 0,
                          done: step > 0,
                        ),
                        Expanded(
                          child: Container(
                            height: 2,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            color: c.glassBorder,
                          ),
                        ),
                        _StepDot(
                          number: 2,
                          label: S.step2,
                          active: step == 1,
                          done: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                  ],
                  ...body,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.number,
    required this.label,
    required this.active,
    required this.done,
  });
  final int number;
  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: active || done ? c.accentGradient : null,
            color: active || done ? null : c.glassFill,
            shape: BoxShape.circle,
            border: Border.all(color: c.glassBorder),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text(
                    '$number',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : c.textMuted,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: active ? null : c.textMuted,
          ),
        ),
      ],
    );
  }
}
