import 'dart:async';

import 'package:flutter/foundation.dart';

import 'distance.dart';
import 'native.dart';

/// Shared app state: the status polled from the Android side plus the actions on it.
class AppController extends ChangeNotifier {
  AppController(this.native, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  final Native native;
  AppStatus status = const AppStatus();
  bool statusLoaded = false;
  Timer? _timer;

  // ---- distance to the computer (measured from its beacon) ----
  final Map<int, DistanceTracker> trackers = {};
  StreamSubscription<BeaconSample>? _beaconSub;
  DistanceModel _model = const DistanceModel();
  String? beaconError;
  bool get beaconRunning => _beaconSub != null;

  /// The computer to show: the nearest one heard recently, else the most recently heard.
  DistanceTracker? get primary {
    DistanceTracker? best;
    for (final t in trackers.values) {
      if (t.isFresh &&
          (best == null || (t.distance ?? 1e9) < (best.distance ?? 1e9))) {
        best = t;
      }
    }
    return best ?? (trackers.isEmpty ? null : trackers.values.first);
  }

  double? get distanceM => primary?.distance;

  Future<void> startBeacon() async {
    if (_beaconSub != null || !status.scanGranted) return;
    beaconError = null;
    _beaconSub = native.beaconEvents().listen(
      (s) {
        trackers
            .putIfAbsent(
              s.id,
              () => DistanceTracker(model: _model, clock: _clock),
            )
            .add(s.rssi);
        notifyListeners();
      },
      onError: (Object e) {
        beaconError = '$e';
        stopBeacon();
      },
    );
    notifyListeners();
  }

  void stopBeacon() {
    _beaconSub?.cancel();
    _beaconSub = null;
    notifyListeners();
  }

  Future<void> requestScanPermission() async {
    await native.requestScanPermission();
    await refresh();
    await startBeacon();
  }

  /// One-point calibration: hold the phone next to the computer (about 0.5 m) and call this.
  Future<bool> calibrateHere() async {
    final t = primary;
    if (t == null || !t.calibrateHere()) return false;
    _model = t.model;
    for (final o in trackers.values) {
      o.model = _model;
    }
    await native.setPref('beacon_tx', _model.txPower1m.toString());
    notifyListeners();
    return true;
  }

  Future<void> _loadCalibration() async {
    try {
      final v = double.tryParse(await native.getPref('beacon_tx') ?? '');
      if (v != null && v < 0 && v > -100) _model = DistanceModel(txPower1m: v);
    } catch (_) {
      // keep the default model
    }
  }

  /// Advertising speed: 'low_power', 'balanced' (default) or 'low_latency'. Applied by the service.
  String signalSpeed = 'balanced';

  Future<void> setSignalSpeed(String v) async {
    signalSpeed = v;
    notifyListeners();
    await native.setPref('advertise_mode', v);
  }

  Future<void> _loadSignalSpeed() async {
    try {
      final v = await native.getPref('advertise_mode');
      if (v == 'low_power' || v == 'low_latency') signalSpeed = v!;
    } catch (_) {
      // keep the default
    }
  }

  Future<void> start() async {
    await _loadCalibration();
    await _loadSignalSpeed();
    await refresh();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      status = await native.status();
      statusLoaded = true;
      notifyListeners();
    } catch (_) {
      // keep the last known status
    }
  }

  Future<void> setProtection(bool on) async {
    if (on && !status.permissionsGranted) await native.requestPermissions();
    await native.setProtection(on);
    await refresh();
  }

  Future<void> requestPermissions() async {
    await native.requestPermissions();
    await refresh();
  }

  Future<void> savePairing(String uri) async {
    if (!status.permissionsGranted) await native.requestPermissions();
    await native.savePairing(uri);
    await refresh();
  }

  Future<void> removePairing(int id) async {
    await native.removePairing(id);
    await refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _beaconSub?.cancel();
    super.dispose();
  }
}
