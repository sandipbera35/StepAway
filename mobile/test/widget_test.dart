import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_mobile/main.dart';
import 'package:stepaway_mobile/native.dart';
import 'package:stepaway_mobile/strings.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import 'test_fonts.dart';

class FakeNative implements Native {
  FakeNative({this.status_ = const AppStatus(), this.onboarded = true});
  AppStatus status_;
  bool onboarded;
  final saved = <String>[];
  final removed = <int>[];
  bool? protection;
  String theme = 'system';
  void Function(String)? deepLink;
  final _beacon = StreamController<BeaconSample>.broadcast();
  final prefs = <String, String>{};
  bool scanRequested = false;
  void emit(int rssi, {int id = 1}) => _beacon.add(BeaconSample(id, rssi));

  @override
  Future<AppStatus> status() async => status_;
  @override
  Future<String?> initialLink() async => null;
  @override
  Future<PairingPreview> previewPairing(String uri) async {
    if (!uri.startsWith('stepaway://')) throw Exception('bad');
    return const PairingPreview('My PC', '123456');
  }

  @override
  Future<void> savePairing(String uri) async {
    saved.add(uri);
    status_ = const AppStatus(
      protection: true,
      advertising: true,
      pairings: [PairingInfo(1, 'My PC')],
    );
  }

  @override
  Future<void> removePairing(int id) async {
    removed.add(id);
    status_ = const AppStatus();
  }

  @override
  Future<void> setProtection(bool on) async => protection = on;
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<String?> scanQr() async => null;
  @override
  Future<void> batterySettings() async {}

  @override
  Future<bool> openUrl(String url) async => false;
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
  Future<void> setOnboarded(bool done) async => onboarded = done;
  @override
  Future<String?> getTheme() async => theme;
  @override
  Future<void> setTheme(String mode) async => theme = mode;
  @override
  void onDeepLink(void Function(String uri) handler) => deepLink = handler;
}

const _paired = AppStatus(
  protection: true,
  advertising: true,
  pairings: [PairingInfo(1, 'My PC')],
);

Future<void> pumpApp(
  WidgetTester t,
  FakeNative n, {
  ThemeController? theme,
}) async {
  // tall enough that every card on a tab is built (lists only build what is on screen)
  t.view.physicalSize = const Size(1080, 4800);
  t.view.devicePixelRatio = 2.75;
  await t.pumpWidget(StepAwayApp(native: n, theme: theme));
  await t.pump(); // the first-run check and the status load are asynchronous
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 800));
}

void main() {
  setUpAll(loadTestFonts);
  testWidgets(
    'without a computer the home screen invites pairing and protection is off',
    (t) async {
      await pumpApp(t, FakeNative());
      expect(find.text(S.heroNoPair), findsOneWidget);
      expect(
        t
            .widget<SwitchListTile>(find.byKey(const Key('protection-switch')))
            .onChanged,
        isNull,
      );
    },
  );

  testWidgets(
    'settings has the version, an About page and the privacy policy',
    (t) async {
      await pumpApp(t, FakeNative());
      await t.tap(find.byKey(const Key('nav-settings')));
      await t.pumpAndSettle();
      expect(find.text('Version $kAppVersion'), findsOneWidget);
      await t.tap(find.byKey(const Key('open-privacy')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('privacy-summary')), findsOneWidget);
      expect(
        find.textContaining('does not request the Internet'),
        findsOneWidget,
      );
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('open-about')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('about-version')), findsOneWidget);
      expect(find.textContaining('WITHOUT ANY WARRANTY'), findsOneWidget);
    },
  );

  testWidgets('tabs switch with the glass navigation bar', (t) async {
    await pumpApp(t, FakeNative());
    await t.tap(find.byKey(const Key('nav-computers')));
    await t.pumpAndSettle();
    expect(find.text(S.emptyComputersTitle), findsOneWidget);
    expect(find.byKey(const Key('scan-button')), findsOneWidget);
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle();
    expect(find.text(S.permissionsSection), findsOneWidget);
    await t.tap(find.byKey(const Key('nav-shield')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('protection-switch')), findsOneWidget);
  });

  testWidgets('a deep link shows the code, pairs on confirm and celebrates', (
    t,
  ) async {
    final n = FakeNative();
    await pumpApp(t, n);
    n.deepLink!('stepaway://pair?v=1&id=0001&s=x');
    await t.pump(const Duration(milliseconds: 800));
    expect(find.byKey(const Key('verification-code')), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    await t.tap(find.text(S.pair));
    await t.pump(const Duration(milliseconds: 900));
    expect(n.saved, hasLength(1));
    expect(find.text(S.pairedTitle), findsOneWidget);
    await t.tap(find.text(S.done));
    await t.pump(const Duration(seconds: 3));
    expect(find.text(S.heroOn), findsOneWidget);
  });

  testWidgets('an invalid link shows an error and nothing is saved', (t) async {
    final n = FakeNative();
    await pumpApp(t, n);
    n.deepLink!('https://evil.example');
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text(S.invalidLink), findsOneWidget);
    expect(n.saved, isEmpty);
  });

  testWidgets('home shows permission, battery and bluetooth notices', (
    t,
  ) async {
    final n = FakeNative(
      status_: const AppStatus(
        protection: true,
        permissionsGranted: false,
        batteryUnrestricted: false,
        bluetoothOn: false,
        pairings: [PairingInfo(1, 'My PC')],
      ),
    );
    await pumpApp(t, n);
    expect(find.text(S.permissionsHelp), findsOneWidget);
    expect(find.text(S.batteryHelp), findsOneWidget);
    expect(find.text(S.bluetoothOff), findsOneWidget);
  });

  testWidgets(
    'the hero reflects broadcasting and the protection switch calls the native side',
    (t) async {
      final n = FakeNative(status_: _paired);
      await pumpApp(t, n);
      expect(find.text(S.heroOn), findsOneWidget);
      await t.tap(find.byKey(const Key('protection-switch')));
      await t.pump(const Duration(milliseconds: 400));
      expect(n.protection, false);
    },
  );

  testWidgets('swiping a computer away asks for confirmation and removes it', (
    t,
  ) async {
    final n = FakeNative(status_: _paired);
    await pumpApp(t, n);
    await t.tap(find.byKey(const Key('nav-computers')));
    await t.pumpAndSettle();
    await t.fling(
      find.byKey(const ValueKey('dismiss-1')),
      const Offset(-700, 0),
      2000,
    );
    await t.pumpAndSettle();
    expect(find.text(S.removeTitle), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, S.remove));
    await t.pumpAndSettle();
    expect(n.removed, [1]);
  });

  testWidgets('the pair button opens the sheet with both ways to pair', (
    t,
  ) async {
    await pumpApp(t, FakeNative(status_: _paired));
    await t.tap(find.byKey(const Key('nav-computers')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('scan-button')));
    await t.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const Key('sheet-scan')), findsOneWidget);
    expect(find.byKey(const Key('sheet-link')), findsOneWidget);
  });

  testWidgets('theme: header toggle and settings selector both save natively', (
    t,
  ) async {
    final n = FakeNative();
    final theme = ThemeController(store: NativeThemeStore(n));
    await pumpApp(t, n, theme: theme);
    await t.tap(find.byKey(const Key('theme-button')));
    await t.pumpAndSettle();
    expect(theme.mode, ThemeMode.light);
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('segment-Dark')));
    await t.pumpAndSettle();
    expect(theme.mode, ThemeMode.dark);
    expect(n.theme, 'dark');
    expect(
      Theme.of(t.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    final restored = ThemeController(store: NativeThemeStore(n));
    await restored.init();
    expect(restored.mode, ThemeMode.dark);
  });

  testWidgets(
    'first run shows the introduction and finishing it is remembered',
    (t) async {
      final n = FakeNative(onboarded: false);
      await pumpApp(t, n);
      expect(find.text(S.ob1Title), findsOneWidget);
      await t.tap(find.byKey(const Key('onboarding-next')));
      await t.pumpAndSettle();
      expect(find.text(S.ob2Title), findsOneWidget);
      await t.tap(find.byKey(const Key('onboarding-next')));
      await t.pumpAndSettle();
      expect(find.text(S.ob3Title), findsOneWidget);
      await t.tap(find.byKey(const Key('onboarding-next')));
      await t.pumpAndSettle();
      expect(n.onboarded, isTrue);
      expect(find.byKey(const Key('protection-switch')), findsOneWidget);
    },
  );

  testWidgets('skipping the introduction also finishes it', (t) async {
    final n = FakeNative(onboarded: false);
    await pumpApp(t, n);
    await t.tap(find.byKey(const Key('onboarding-skip')));
    await t.pumpAndSettle();
    expect(n.onboarded, isTrue);
    expect(find.text(S.ob1Title), findsNothing);
  });

  group('distance dashboard', () {
    const granted = AppStatus(
      protection: true,
      advertising: true,
      scanGranted: true,
      pairings: [PairingInfo(1, 'My PC')],
    );

    Future<void> settle(WidgetTester t) async {
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('asks for the scan permission first', (t) async {
      final n = FakeNative(
        status_: const AppStatus(
          protection: true,
          pairings: [PairingInfo(1, 'My PC')],
        ),
      );
      await pumpApp(t, n);
      expect(find.byKey(const Key('allow-scan')), findsOneWidget);
      await t.tap(find.byKey(const Key('allow-scan')));
      await settle(t);
      expect(n.scanRequested, isTrue);
    });

    testWidgets(
      'shows that it is looking for the computer until the beacon is heard',
      (t) async {
        await pumpApp(t, FakeNative(status_: granted));
        expect(find.byKey(const Key('dist-searching')), findsOneWidget);
        expect(find.text(S.distHint), findsOneWidget);
      },
    );

    testWidgets('shows the measured distance and zone from beacon readings', (
      t,
    ) async {
      final n = FakeNative(status_: granted);
      await pumpApp(t, n);
      for (var i = 0; i < 10; i++) {
        n.emit(-59);
      }
      await settle(t);
      expect(find.byKey(const Key('distance-value')), findsOneWidget);
      expect(find.text('1.0 m'), findsOneWidget);
      expect(find.text(S.zoneNear), findsOneWidget);
      for (var i = 0; i < 40; i++) {
        n.emit(-80);
      }
      await settle(t);
      expect(find.text(S.zoneFar), findsOneWidget);
    });

    testWidgets('goes back to searching when the beacon stops', (t) async {
      var now = DateTime(2026, 1, 1);
      final n = FakeNative(status_: granted);
      t.view.physicalSize = const Size(1080, 4800);
      t.view.devicePixelRatio = 2.75;
      await t.pumpWidget(StepAwayApp(native: n, clock: () => now));
      await t.pump();
      await t.pump(const Duration(milliseconds: 900));
      n.emit(-60);
      await settle(t);
      expect(find.byKey(const Key('distance-value')), findsOneWidget);
      now = now.add(const Duration(seconds: 12));
      await t.pump(
        const Duration(seconds: 3),
      ); // the status poll rebuilds the card
      expect(find.byKey(const Key('dist-searching')), findsOneWidget);
    });

    testWidgets(
      'calibrating next to the computer sets 0.5 m and is remembered',
      (t) async {
        final n = FakeNative(status_: granted);
        await pumpApp(t, n);
        for (var i = 0; i < 20; i++) {
          n.emit(-50);
        }
        await settle(t);
        await t.tap(find.byKey(const Key('calibrate-here')));
        await settle(t);
        expect(find.text(S.distCalibrated), findsOneWidget);
        expect(find.text('0.5 m'), findsOneWidget);
        expect(double.parse(n.prefs['beacon_tx']!), closeTo(-56.02, 0.05));
      },
    );
  });
}
