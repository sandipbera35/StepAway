// Renders the phone screens to PNG so the design can be reviewed without a device.
// Run: SA_SCREENSHOTS=/some/dir flutter test test/screenshots_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_mobile/main.dart';
import 'package:stepaway_mobile/native.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import 'test_fonts.dart';

class _Fake implements Native {
  _Fake(this.s, {this.onboarded = true});
  final AppStatus s;
  final bool onboarded;
  final _beacon = StreamController<BeaconSample>.broadcast();
  final prefs = <String, String>{};
  bool scanRequested = false;
  void emit(int rssi) => _beacon.add(BeaconSample(1, rssi));
  @override
  Future<AppStatus> status() async => s;
  @override
  Future<String?> initialLink() async => null;
  @override
  Future<PairingPreview> previewPairing(String uri) async =>
      const PairingPreview('fedora', '508027');
  @override
  Future<void> savePairing(String uri) async {}
  @override
  Future<void> removePairing(int id) async {}
  @override
  Future<void> setProtection(bool on) async {}
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<String?> scanQr() async => null;
  @override
  Future<void> batterySettings() async {}
  @override
  Stream<BeaconSample> beaconEvents() => _beacon.stream;
  @override
  Future<void> requestScanPermission() async {
    scanRequested = true;
  }

  @override
  Future<String?> getPref(String key) async => prefs[key];
  @override
  Future<void> setPref(String key, String value) async => prefs[key] = value;
  @override
  Future<bool> getOnboarded() async => onboarded;
  @override
  Future<void> setOnboarded(bool done) async {}
  @override
  Future<String?> getTheme() async => 'system';
  @override
  Future<void> setTheme(String mode) async {}
  @override
  void onDeepLink(void Function(String uri) handler) {}
}

void main() {
  final dir = Platform.environment['SA_SCREENSHOTS'];
  setUpAll(() async {
    if (dir != null) await loadTestFonts();
  });
  const paired = AppStatus(
    protection: true,
    advertising: true,
    batteryUnrestricted: false,
    scanGranted: true,
    pairings: [PairingInfo(1, 'fedora'), PairingInfo(2, 'Work laptop')],
  );
  // name -> (status, tab key to open or null, onboarding pages to advance)
  final shots = <String, (AppStatus, String?, int?)>{
    'shield': (paired, null, null),
    'computers': (paired, 'nav-computers', null),
    'settings': (paired, 'nav-settings', null),
    'unpaired': (const AppStatus(), null, null),
    'onboarding1': (const AppStatus(), null, 0),
    'onboarding2': (const AppStatus(), null, 1),
    'onboarding3': (const AppStatus(), null, 2),
  };
  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    for (final e in shots.entries) {
      testWidgets('screenshot ${mode.name} ${e.key}', (t) async {
        t.view.physicalSize = const Size(1080, 2400);
        t.view.devicePixelRatio = 2.75;
        final theme = ThemeController();
        await theme.setMode(mode);
        final key = GlobalKey();
        final fake = _Fake(e.value.$1, onboarded: e.value.$3 == null);
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: StepAwayApp(native: fake, theme: theme),
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        await t.pump(const Duration(milliseconds: 900));
        for (var i = 0; i < 14; i++) {
          fake.emit(-62 + (i.isEven ? 1 : -1));
        }
        await t.pump(const Duration(milliseconds: 700));
        final tab = e.value.$2;
        if (tab != null) {
          await t.tap(find.byKey(Key(tab)));
          await t.pump(const Duration(milliseconds: 100));
          await t.pump(const Duration(milliseconds: 1200));
        }
        for (var i = 0; i < (e.value.$3 ?? 0); i++) {
          await t.tap(find.byKey(const Key('onboarding-next')));
          await t.pumpAndSettle();
        }
        await t.pump(const Duration(milliseconds: 900));
        await t.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await b.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/phone-${mode.name}-${e.key}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      }, skip: dir == null);
    }
  }
}
