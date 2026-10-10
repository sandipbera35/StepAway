import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

class PairingInfo {
  const PairingInfo(this.id, this.name);
  final int id;
  final String name;
}

class BeaconSample {
  const BeaconSample(this.id, this.rssi);
  final int id;
  final int rssi;
}

class AppStatus {
  const AppStatus({
    this.protection = false,
    this.advertising = false,
    this.error,
    this.bluetoothOn = true,
    this.permissionsGranted = true,
    this.scanGranted = false,
    this.batteryUnrestricted = true,
    this.pairings = const [],
  });

  final bool protection;
  final bool advertising;
  final String? error;
  final bool bluetoothOn;
  final bool permissionsGranted;
  final bool scanGranted;
  final bool batteryUnrestricted;
  final List<PairingInfo> pairings;

  factory AppStatus.fromMap(Map<dynamic, dynamic> m) {
    final perms = (m['permissions'] as Map?) ?? const {};
    final needed = [
      perms['advertise'],
      perms['connect'],
      perms['notifications'],
    ];
    return AppStatus(
      protection: m['protection'] == true,
      advertising: m['advertising'] == true,
      error: m['error'] as String?,
      bluetoothOn: m['bluetoothOn'] != false,
      permissionsGranted: needed.every((p) => p == true),
      scanGranted: perms['scan'] == true,
      batteryUnrestricted: m['batteryUnrestricted'] != false,
      pairings: [
        for (final p in (m['pairings'] as List? ?? const []))
          PairingInfo((p as Map)['id'] as int, p['name'] as String),
      ],
    );
  }
}

class PairingPreview {
  const PairingPreview(this.name, this.code);
  final String name;
  final String code;
}

/// Thin wrapper over the Kotlin side (token, secure storage, advertising service).
abstract class Native {
  Future<AppStatus> status();
  Future<String?> initialLink();
  Future<PairingPreview> previewPairing(String uri);
  Future<void> savePairing(String uri);
  Future<void> removePairing(int id);
  Future<void> setProtection(bool on);
  Future<void> requestPermissions();
  Future<String?> scanQr();
  Future<void> batterySettings();
  void onDeepLink(void Function(String uri) handler);
  Stream<BeaconSample> beaconEvents();
  Future<void> requestScanPermission();
  Future<String?> getPref(String key);
  Future<void> setPref(String key, String value);
  Future<bool> getOnboarded();
  Future<void> setOnboarded(bool done);
  Future<String?> getTheme();
  Future<void> setTheme(String mode);
}

class MethodChannelNative implements Native {
  static const _ch = MethodChannel('stepaway/native');

  @override
  Future<AppStatus> status() async =>
      AppStatus.fromMap(await _ch.invokeMethod<Map>('status') ?? const {});

  @override
  Future<String?> initialLink() => _ch.invokeMethod<String>('initialLink');

  @override
  Future<PairingPreview> previewPairing(String uri) async {
    final m = await _ch.invokeMethod<Map>('previewPairing', uri) ?? const {};
    return PairingPreview(
      m['name'] as String? ?? '',
      m['code'] as String? ?? '',
    );
  }

  @override
  Future<void> savePairing(String uri) => _ch.invokeMethod('savePairing', uri);

  @override
  Future<void> removePairing(int id) => _ch.invokeMethod('removePairing', id);

  @override
  Future<void> setProtection(bool on) => _ch.invokeMethod('setProtection', on);

  @override
  Future<void> requestPermissions() => _ch.invokeMethod('requestPermissions');

  @override
  Future<String?> scanQr() => _ch.invokeMethod<String>('scanQr');

  @override
  Future<void> batterySettings() => _ch.invokeMethod('batterySettings');

  static const _beacon = EventChannel('stepaway/beacon');

  @override
  Stream<BeaconSample> beaconEvents() => _beacon.receiveBroadcastStream().map((
    e,
  ) {
    final m = e as Map;
    return BeaconSample((m['id'] as num).toInt(), (m['rssi'] as num).toInt());
  });

  @override
  Future<void> requestScanPermission() =>
      _ch.invokeMethod('requestScanPermission');

  @override
  Future<String?> getPref(String key) =>
      _ch.invokeMethod<String>('getPref', key);

  @override
  Future<void> setPref(String key, String value) =>
      _ch.invokeMethod('setPref', [key, value]);

  @override
  Future<bool> getOnboarded() async =>
      await _ch.invokeMethod<bool>('getOnboarded') ?? true;

  @override
  Future<void> setOnboarded(bool done) =>
      _ch.invokeMethod('setOnboarded', done);

  @override
  Future<String?> getTheme() => _ch.invokeMethod<String>('getTheme');

  @override
  Future<void> setTheme(String mode) => _ch.invokeMethod('setTheme', mode);

  @override
  void onDeepLink(void Function(String uri) handler) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'deepLink') handler(call.arguments as String);
    });
  }
}

/// Remembers the theme in the Android app preferences.
class NativeThemeStore implements ThemeStore {
  NativeThemeStore(this._native);
  final Native _native;

  @override
  Future<ThemeMode?> load() async =>
      ThemeController.decode(await _native.getTheme());

  @override
  Future<void> save(ThemeMode mode) =>
      _native.setTheme(ThemeController.encode(mode));
}
