import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_desktop/health.dart';
import 'package:stepaway_desktop/ipc/rpc_client.dart';
import 'package:stepaway_desktop/model.dart';
import 'package:stepaway_desktop/strings.dart';

DaemonModel _model({
  bool connected = true,
  bool scanning = true,
  bool paired = true,
  bool nearby = true,
  bool paused = false,
  bool calibrated = true,
  String? block,
}) {
  final m = DaemonModel(RpcClient());
  m.connected = connected;
  m.scanning = scanning;
  m.paused = paused;
  m.unlockBlock = block;
  m.config = {'calibrated': calibrated};
  if (paired) {
    m.phones = [PairedDevice(7, 'Moto', null)];
  }
  m.present = nearby && paired ? [7] : [];
  return m;
}

HealthCheck _find(List<HealthCheck> l, String id) =>
    l.firstWhere((h) => h.id == id);

void main() {
  test('everything fine: no warnings and unlock is ready', () {
    final l = healthChecks(_model());
    expect(l.where((h) => h.level == HealthLevel.warn), isEmpty);
    expect(_find(l, 'unlock').title, S.hUnlockReady);
  });

  test('service down: one clear message and nothing else to check', () {
    final l = healthChecks(_model(connected: false));
    expect(l, hasLength(1));
    expect(l.single.level, HealthLevel.warn);
  });

  test('no paired device is a warning with a fix', () {
    final l = healthChecks(_model(paired: false));
    expect(_find(l, 'paired').level, HealthLevel.warn);
    expect(_find(l, 'paired').fix, S.hPairedFix);
    expect(l.any((h) => h.id == 'signal'), isFalse);
  });

  test('paired but no signal, scanning off and paused are warnings', () {
    final l = healthChecks(
      _model(nearby: false, scanning: false, paused: true),
    );
    for (final id in ['signal', 'scan', 'active']) {
      expect(_find(l, id).level, HealthLevel.warn, reason: id);
    }
  });

  test('every unlock reason from the daemon has its own explanation', () {
    final titles = <String>{};
    for (final b in [
      'disabled',
      'first_login',
      'not_our_lock',
      'too_far',
      'return_grace',
      'needs_fresh_auth',
    ]) {
      final u = _find(healthChecks(_model(block: b)), 'unlock');
      expect(u.level, HealthLevel.info, reason: b);
      expect(u.fix, isNotNull, reason: b);
      titles.add(u.title);
    }
    expect(titles, hasLength(6));
  });

  test('"paused" and "no_signal" are not repeated as an unlock row', () {
    for (final b in ['paused', 'no_signal', 'something_new']) {
      expect(
        healthChecks(_model(block: b)).any((h) => h.id == 'unlock'),
        isFalse,
        reason: b,
      );
    }
  });

  test('calibration is a hint, not a warning', () {
    final l = healthChecks(_model(calibrated: false));
    expect(_find(l, 'calibrated').level, HealthLevel.info);
  });
}
