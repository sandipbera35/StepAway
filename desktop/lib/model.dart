import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import 'ipc/rpc_client.dart';
import 'service.dart';
import 'uninstall.dart';

class Reading {
  const Reading(this.time, this.rssi, this.distance);
  final DateTime time;
  final double rssi;
  final double distance;
}

class AppItem {
  const AppItem(this.id, this.name, {this.running = false});
  final String id;
  final String name;
  final bool running;
}

class ServiceItem {
  const ServiceItem(this.id, this.name);
  final String id;
  final String name;
}

/// Kinds of device that can be paired. The value is what the daemon stores.
enum DeviceKind {
  phone('phone', 'Phone', Icons.smartphone_rounded),
  tablet('tablet', 'Tablet', Icons.tablet_android_rounded),
  watch('watch', 'Smartwatch', Icons.watch_rounded),
  other('other', 'Other', Icons.devices_other_rounded);

  const DeviceKind(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;

  static DeviceKind of(String? id) => DeviceKind.values.firstWhere(
    (k) => k.id == id,
    orElse: () => DeviceKind.phone,
  );
}

class PairedDevice {
  const PairedDevice(
    this.id,
    this.name,
    this.lastSeen, {
    this.kind = DeviceKind.phone,
    this.presenceOnly = false,
    this.address,
    this.calibrated = false,
  });
  final int id;
  final String name;
  final DateTime? lastSeen;
  final DeviceKind kind;

  /// Tracked by Bluetooth address only: can lock, can never unlock.
  final bool presenceOnly;
  final String? address;
  final bool calibrated;
}

class NearbyDevice {
  const NearbyDevice(this.address, this.name, this.rssi);
  final String address;
  final String? name;
  final int rssi;
}

/// Pairing by code (smartwatches): the user typed the code shown on the watch.
class CodePairing {
  CodePairing(this.expiresAt);
  final DateTime expiresAt;
  bool completed = false;
  String? error;
}

class PairingSession {
  PairingSession(this.uri, this.code, this.expiresAt);
  final String uri;
  final String code;
  final DateTime expiresAt;
  bool completed = false;
}

enum CalibPhase { idle, nearReady, measuring, farReady, done, failed }

class DaemonModel extends ChangeNotifier {
  DaemonModel(this.client, {this.service, this.uninstaller});

  final RpcClient client;
  final ServiceManager? service;
  final Uninstaller? uninstaller;
  bool autostart = false;
  bool _triedStart = false;
  bool connected = false;
  String state = 'UNKNOWN';
  bool paused = false;
  bool scanning = false;
  bool capMedia = false;
  bool capServices = false;
  bool capApps = false;
  bool capBeacon = false;
  Map<String, dynamic> config = {};
  List<PairedDevice> phones = [];
  List<int> present = [];
  final List<Reading> history = [];
  PairingSession? pairing;
  CodePairing? codePairing;
  CalibPhase calib = CalibPhase.idle;
  String calibStep = 'near';
  String? calibMessage;
  DateTime? calibEnds;
  DateTime? calibStarted;
  static const maxHistory = 240;

  StreamSubscription<Notification>? _notes;
  StreamSubscription<bool>? _conn;
  Timer? _poll;

  Reading? get latest => history.isEmpty ? null : history.last;
  bool get phoneNearby => present.isNotEmpty;
  double get lockDistance =>
      (config['lock_distance_m'] as num?)?.toDouble() ?? 3.0;
  double get returnDistance =>
      (config['return_distance_m'] as num?)?.toDouble() ?? 2.0;
  bool get unlockEnabled => config['unlock_enabled'] == true;
  bool get calibrated => config['calibrated'] == true;
  bool get beaconEnabled => config['beacon_enabled'] != false;
  String get presenceRule => config['presence_rule'] == 'all' ? 'all' : 'any';
  bool get lockPauseMedia => config['lock_pause_media'] == true;
  bool get unlockResumeMedia => config['unlock_resume_media'] == true;
  bool get unlockStartServices => config['unlock_start_services'] == true;
  bool get unlockReopenApps => config['unlock_reopen_apps'] == true;
  List<AppItem> get lockCloseApps => [
    for (final v in (config['lock_close_apps'] as List? ?? const []))
      if (v is Map) AppItem('${v['id']}', '${v['name'] ?? v['id']}'),
  ];
  List<String> get lockStopServices => [
    for (final v in (config['lock_stop_services'] as List? ?? const [])) '$v',
  ];

  Future<void> init() async {
    _notes = client.notifications.listen(_onNote);
    _conn = client.connection.listen((c) {
      connected = c;
      if (c) refresh();
      notifyListeners();
    });
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (connected) refresh();
    });
    await client.start();
    connected = client.isConnected;
    if (connected) {
      await refresh();
    } else {
      await _startBundledDaemon();
    }
    final svc = service;
    if (svc != null) {
      await svc.ensureDefaultAutostart();
      autostart = await svc.autostartEnabled();
    }
    notifyListeners();
  }

  /// The daemon ships inside the app, so a missing service is started automatically (once).
  Future<void> _startBundledDaemon() async {
    final svc = service;
    if (svc == null || _triedStart) return;
    _triedStart = true;
    await svc.startDaemon();
  }

  Future<bool> startService() async {
    _triedStart = true;
    return await service?.startDaemon() ?? false;
  }

  Future<void> setAutostart(bool on) async {
    await service?.setAutostart(on);
    autostart = await service?.autostartEnabled() ?? false;
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      final s = await client.call('status') as Map<String, dynamic>;
      state = s['state'] as String? ?? 'UNKNOWN';
      paused = s['paused'] == true;
      scanning = s['scanning'] == true;
      final caps = (s['capabilities'] as Map?) ?? const {};
      capMedia = caps['media'] == true;
      capServices = caps['services'] == true;
      capApps = caps['apps'] == true;
      capBeacon = caps['beacon'] == true;
      present = [
        for (final v in (s['devices_present'] as List? ?? const []))
          (v as num).toInt(),
      ];
      final list = await client.call('listDevices') as List;
      phones = [
        for (final d in list)
          PairedDevice(
            (d['device_id'] as num).toInt(),
            d['name'] as String? ?? 'Device',
            d['last_seen'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    (d['last_seen'] as num).toInt() * 1000,
                  ),
            kind: DeviceKind.of(d['kind'] as String?),
            presenceOnly: d['presence_only'] == true,
            address: d['address'] as String?,
            calibrated: d['calibrated'] == true,
          ),
      ];
      config = Map<String, dynamic>.from(await client.call('getConfig') as Map);
      notifyListeners();
    } on RpcException {
      // connection hiccup: the next poll or reconnect refreshes
    }
  }

  double _lastRssi = -60;
  bool _hasPresence = false;

  void _addReading(double distance) {
    history.add(Reading(DateTime.now(), _lastRssi, distance));
    if (history.length > maxHistory) history.removeAt(0);
  }

  void _onNote(Notification n) {
    switch (n.method) {
      case 'rssiUpdate':
        _lastRssi = (n.params['filtered_rssi'] as num).toDouble();
        // once the daemon reports the combined distance, the graph follows that instead
        if (!_hasPresence) {
          _addReading((n.params['distance_m'] as num).toDouble());
        }
      case 'presenceUpdate':
        _hasPresence = true;
        _addReading((n.params['distance_m'] as num).toDouble());
      case 'stateChanged':
        state = n.params['to'] as String? ?? state;
      case 'devicePaired':
        pairing?.completed = true;
        codePairing?.completed = true;
      case 'pairingFailed':
        codePairing?.error = n.params['reason'] as String? ?? 'Pairing failed';
        refresh();
      case 'calibrationStep':
        if (calibStep == 'near') {
          calib = CalibPhase.farReady;
          calibStep = 'far';
        }
      case 'calibrationDone':
        calib = CalibPhase.done;
        calibMessage = null;
        refresh();
      case 'calibrationFailed':
        calib = CalibPhase.failed;
        calibMessage = n.params['reason'] as String?;
    }
    notifyListeners();
  }

  Future<PairingSession> startPairing(
    String name, {
    DeviceKind kind = DeviceKind.phone,
  }) async {
    final r = await client.call('startPairing', {
      'name': name,
      'kind': kind.id,
    }) as Map<String, dynamic>;
    final s = PairingSession(
      r['qr_uri'] as String,
      r['verification_code'] as String,
      DateTime.fromMillisecondsSinceEpoch(
        (r['expires_at'] as num).toInt() * 1000,
      ),
    );
    pairing = s;
    notifyListeners();
    return s;
  }

  /// Start listening for the offer of a device that shows [code]. Throws [RpcException] if the
  /// code does not look right.
  Future<CodePairing> startCodePairing(String code, {String? name}) async {
    final r = await client.call('startCodePairing', {
      'code': code,
      'name': ?name,
    }) as Map<String, dynamic>;
    final p = CodePairing(
      DateTime.fromMillisecondsSinceEpoch(
        (r['expires_at'] as num).toInt() * 1000,
      ),
    );
    codePairing = p;
    notifyListeners();
    return p;
  }

  Future<void> endPairing() async {
    codePairing = null;
    pairing = null;
    notifyListeners();
    try {
      await client.call('cancelPairing');
    } on RpcException {
      // daemon already gone
    }
  }

  Future<void> removePhone(int id) async {
    await client.call('removeDevice', {'device_id': id});
    await refresh();
  }

  Future<void> setConfig(Map<String, dynamic> patch) async {
    config = Map<String, dynamic>.from(
      await client.call('setConfig', patch) as Map,
    );
    notifyListeners();
  }

  /// Applications to offer in the picker (running ones first).
  Future<List<AppItem>> availableApps() async {
    final r = await client.call('listApps');
    return [
      for (final v in (r as List? ?? const []))
        if (v is Map)
          AppItem('${v['id']}', '${v['name']}', running: v['running'] == true),
    ];
  }

  /// Background services that are running now, to offer in the picker.
  Future<List<ServiceItem>> availableServices() async {
    final r = await client.call('listServices');
    return [
      for (final v in (r as List? ?? const []))
        if (v is Map) ServiceItem('${v['id']}', '${v['name']}'),
    ];
  }

  /// Bluetooth devices around that are not on the device list yet (for lock-only tracking).
  Future<List<NearbyDevice>> nearbyDevices() async {
    final r = await client.call('listNearby');
    return [
      for (final v in (r as List? ?? const []))
        if (v is Map)
          NearbyDevice(
            '${v['address']}',
            v['name'] as String?,
            (v['rssi'] as num).toInt(),
          ),
    ];
  }

  Future<void> addPresenceDevice(
    NearbyDevice d,
    String name,
    DeviceKind kind,
  ) async {
    await client.call('addPresenceDevice', {
      'address': d.address,
      'name': name,
      'kind': kind.id,
    });
    await refresh();
  }

  Future<void> updateDevice(int id, {String? name, DeviceKind? kind}) async {
    await client.call('updateDevice', {
      'device_id': id,
      'name': ?name,
      if (kind != null) 'kind': kind.id,
    });
    await refresh();
  }

  Future<void> addLockApp(AppItem app) async {
    if (lockCloseApps.any((a) => a.id == app.id)) return;
    await setConfig({
      'lock_close_apps': [
        for (final a in lockCloseApps) {'id': a.id, 'name': a.name},
        {'id': app.id, 'name': app.name},
      ],
    });
  }

  Future<void> removeLockApp(String id) => setConfig({
    'lock_close_apps': [
      for (final a in lockCloseApps)
        if (a.id != id) {'id': a.id, 'name': a.name},
    ],
  });

  Future<void> addLockService(String unit) async {
    if (lockStopServices.contains(unit)) return;
    await setConfig({
      'lock_stop_services': [...lockStopServices, unit],
    });
  }

  Future<void> removeLockService(String unit) => setConfig({
    'lock_stop_services': [
      for (final u in lockStopServices)
        if (u != unit) u,
    ],
  });

  Future<void> setPaused(bool p) async {
    await client.call(p ? 'pause' : 'resume');
    paused = p;
    notifyListeners();
  }

  void beginCalibration() {
    calib = CalibPhase.nearReady;
    calibStep = 'near';
    calibMessage = null;
    notifyListeners();
  }

  /// The device being calibrated; null means the first paired device / shared default.
  int? calibDevice;

  void selectCalibDevice(int? id) {
    calibDevice = id;
    notifyListeners();
  }

  Future<void> runCalibrationStep() async {
    await client.call('startCalibration', {
      'step': calibStep,
      if (calibDevice != null) 'device_id': calibDevice,
    });
    calib = CalibPhase.measuring;
    calibStarted = DateTime.now();
    calibEnds = calibStarted!.add(const Duration(seconds: 15));
    notifyListeners();
  }

  @override
  void dispose() {
    _notes?.cancel();
    _conn?.cancel();
    _poll?.cancel();
    client.stop();
    super.dispose();
  }
}
