import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_mobile/distance.dart';

void main() {
  group('DistanceModel', () {
    test('1 m at the reference power and +20 dB per decade for n = 2', () {
      const m = DistanceModel();
      expect(m.distanceM(-59), closeTo(1.0, 1e-9));
      expect(m.distanceM(-79), closeTo(10.0, 1e-9));
      expect(m.distanceM(-69), greaterThan(m.distanceM(-60)));
    });

    test(
      'a reading taken at 0.5 m reproduces 0.5 m (one-point calibration)',
      () {
        final m = const DistanceModel().calibratedAt(-50);
        expect(m.distanceM(-50), closeTo(0.5, 1e-9));
        expect(m.txPower1m, closeTo(-50 - 6.0206, 1e-3));
      },
    );
  });

  group('RssiFilter', () {
    test('first sample passes through and a single spike is rejected', () {
      final f = RssiFilter();
      expect(f.push(-60), -60);
      for (var i = 0; i < 5; i++) {
        f.push(-60);
      }
      expect(f.push(-95), closeTo(-60, 1e-9));
    });

    test('a real level change is followed within a few samples', () {
      final f = RssiFilter();
      for (var i = 0; i < 7; i++) {
        f.push(-55);
      }
      late double last;
      for (var i = 0; i < 12; i++) {
        last = f.push(-75)!;
      }
      expect(last, lessThan(-70));
    });

    test('non-finite samples are ignored', () {
      final f = RssiFilter();
      expect(f.push(double.nan), isNull);
      f.push(-60);
      expect(f.push(double.infinity), -60);
    });
  });

  group('DistanceTracker', () {
    test('zones use hysteresis between the return and lock distances', () {
      final t = DistanceTracker();
      for (var i = 0; i < 12; i++) {
        t.add(-55); // ~0.6 m
      }
      expect(t.zone, Zone.near);
      // ~2.5 m (between 2 and 3): stays "near" until it really passes 3 m
      for (var i = 0; i < 25; i++) {
        t.add(-67);
      }
      expect(t.zone, Zone.near);
      for (var i = 0; i < 25; i++) {
        t.add(-75); // ~6 m
      }
      expect(t.zone, Zone.far);
      for (var i = 0; i < 25; i++) {
        t.add(-67); // back to ~2.5 m: still "far" until under 2 m
      }
      expect(t.zone, Zone.far);
    });

    test('the distance goes stale when the beacon is not heard', () {
      var now = DateTime(2026, 1, 1);
      final t = DistanceTracker(clock: () => now);
      expect(t.distance, isNull);
      t.add(-60);
      expect(t.distance, isNotNull);
      now = now.add(const Duration(seconds: 11));
      expect(t.distance, isNull);
      expect(t.isFresh, isFalse);
    });

    test('history is capped and calibration needs a fresh signal', () {
      var now = DateTime(2026, 1, 1);
      final t = DistanceTracker(clock: () => now);
      expect(t.calibrateHere(), isFalse, reason: 'nothing heard yet');
      for (var i = 0; i < 200; i++) {
        t.add(-60);
      }
      expect(t.history.length, DistanceTracker.maxHistory);
      expect(t.calibrateHere(), isTrue);
      expect(t.distance, closeTo(0.5, 0.05));
      now = now.add(const Duration(minutes: 1));
      expect(t.calibrateHere(), isFalse, reason: 'stale signals are not used');
    });
  });
}
