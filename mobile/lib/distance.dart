import 'dart:collection';
import 'dart:math' as math;

/// Log-distance path-loss model: `d = 10 ^ ((tx_power_1m - rssi) / (10 n))`.
class DistanceModel {
  const DistanceModel({this.txPower1m = -59, this.n = 2});
  final double txPower1m;
  final double n;

  double distanceM(double rssi) =>
      math.pow(10, (txPower1m - rssi) / (10 * n)).toDouble();

  /// The model implied by a reading taken [atMeters] away (one-point calibration).
  DistanceModel calibratedAt(double rssi, {double atMeters = 0.5}) =>
      DistanceModel(
        txPower1m: rssi - 10 * n * math.log(1 / atMeters) / math.ln10,
        n: n,
      );
}

/// Median-based outlier rejection followed by an exponential moving average (same behaviour as
/// the computer's filter, so both sides agree on what "a spike" is).
class RssiFilter {
  RssiFilter({this.windowLen = 7, this.maxDevDb = 15, this.alpha = 0.3});
  final int windowLen;
  final double maxDevDb;
  final double alpha;
  final _window = Queue<double>();
  double? _ema;
  int _rejects = 0;

  double? get value => _ema;

  double? _median() {
    if (_window.isEmpty) return null;
    final v = _window.toList()..sort();
    return v[v.length ~/ 2];
  }

  /// Feed a raw sample; returns the filtered value. Non-finite samples are ignored.
  double? push(double rssi) {
    if (!rssi.isFinite) return _ema;
    final med = _median();
    if (med != null && (rssi - med).abs() > maxDevDb && _rejects < 3) {
      _rejects++;
      return _ema;
    }
    if (_rejects >= 3) {
      _window.clear(); // the level really changed: restart the window
    }
    _rejects = 0;
    if (_window.length == windowLen) _window.removeFirst();
    _window.add(rssi);
    final prev = _ema;
    return _ema = prev == null ? rssi : prev + alpha * (rssi - prev);
  }
}

enum Zone { near, mid, far }

/// Follows the computer's beacon: filtered RSSI, distance, zone with hysteresis, history.
class DistanceTracker {
  DistanceTracker({
    this.model = const DistanceModel(),
    this.lockAt = 3.0,
    this.returnAt = 2.0,
    this.staleAfter = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  DistanceModel model;
  final double lockAt;
  final double returnAt;
  final Duration staleAfter;
  final DateTime Function() _clock;
  final _filter = RssiFilter();
  final _raw = Queue<double>();
  final List<double> history = [];
  static const maxHistory = 120;

  DateTime? _lastAt;
  double? _distance;
  Zone _zone = Zone.mid;

  double? get filteredRssi => _filter.value;
  Zone get zone => _zone;

  /// The distance, or null when the beacon has not been heard recently.
  double? get distance => isFresh ? _distance : null;
  bool get isFresh =>
      _lastAt != null && _clock().difference(_lastAt!) <= staleAfter;

  void add(int rssi) {
    _lastAt = _clock();
    _raw.addLast(rssi.toDouble());
    if (_raw.length > 20) _raw.removeFirst();
    final f = _filter.push(rssi.toDouble());
    if (f == null) return;
    final d = model.distanceM(f);
    _distance = d;
    if (d > lockAt) {
      _zone = Zone.far;
    } else if (d <= returnAt) {
      _zone = Zone.near;
    } // in between: keep the previous zone (hysteresis)
    history.add(d);
    if (history.length > maxHistory) history.removeAt(0);
  }

  /// Median of the most recent raw readings, or null if there are none.
  double? get recentMedianRssi {
    if (_raw.isEmpty) return null;
    final v = _raw.toList()..sort();
    return v[v.length ~/ 2];
  }

  /// One-point calibration: the phone is about [atMeters] from the computer right now.
  bool calibrateHere({double atMeters = 0.5}) {
    final m = recentMedianRssi;
    if (m == null || !isFresh) return false;
    model = model.calibratedAt(m, atMeters: atMeters);
    final f = _filter.value;
    if (f != null) _distance = model.distanceM(f);
    history.clear();
    return true;
  }
}
