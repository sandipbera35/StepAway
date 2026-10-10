import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_desktop/ipc/rpc_client.dart';
import 'package:stepaway_desktop/ipc/transport.dart';
import 'package:stepaway_desktop/main.dart';
import 'package:stepaway_desktop/model.dart';
import 'package:stepaway_desktop/strings.dart';
import 'package:stepaway_desktop/title_bar.dart';
import 'package:stepaway_desktop/uninstall.dart';
import 'package:stepaway_desktop/window_frame.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

/// A scripted daemon: answers RPC calls and lets tests push notifications.
class FakeDaemon implements Transport {
  final _in = StreamController<String>();
  final calls = <String>[];
  List<Map<String, dynamic>> devices = [
    {
      'device_id': 7,
      'name': 'Moto',
      'kind': 'phone',
      'paired_at': 1,
      'last_seen': 1700000000,
      'presence_only': false,
    },
  ];
  List<Map<String, dynamic>> nearby = [
    {'address': 'AA:BB:CC:DD:EE:01', 'name': 'Mi Band', 'rssi': -58},
    {'address': 'AA:BB:CC:DD:EE:02', 'name': null, 'rssi': -80},
  ];
  final requests = <Map<String, dynamic>>[];
  Map<String, dynamic> config = {
    'lock_distance_m': 3.0,
    'return_distance_m': 2.0,
    'lock_grace_s': 10,
    'return_grace_s': 3,
    'unlock_enabled': false,
    'presence_rule': 'any',
    'beacon_enabled': true,
    'lock_pause_media': false,
    'unlock_resume_media': false,
    'lock_close_apps': <dynamic>[],
    'unlock_reopen_apps': false,
    'lock_stop_services': <dynamic>[],
    'unlock_start_services': false,
  };
  @override
  Stream<String> get lines => _in.stream;
  @override
  Future<void> close() async {}

  @override
  void send(String line) {
    final req = jsonDecode(line) as Map<String, dynamic>;
    final m = req['method'] as String;
    calls.add(m);
    requests.add({
      'method': m,
      ...((req['params'] as Map?)?.cast<String, dynamic>() ?? {}),
    });
    final p = (req['params'] as Map?)?.cast<String, dynamic>() ?? {};
    dynamic result = {'ok': true};
    switch (m) {
      case 'status':
        result = {
          'state': 'NEAR',
          'paused': false,
          'scanning': true,
          'devices_present': [7],
          'capabilities': {
            'media': true,
            'services': true,
            'apps': true,
            'beacon': true,
          },
        };
      case 'listServices':
        result = [
          {'id': 'syncthing.service', 'name': 'syncthing'},
          {'id': 'backup.service', 'name': 'backup'},
          {'id': 'dbus.service', 'name': 'dbus'},
        ];
      case 'listApps':
        result = [
          {'id': 'firefox.desktop', 'name': 'Firefox', 'running': true},
          {'id': 'spotify.desktop', 'name': 'Spotify', 'running': false},
        ];
      case 'listDevices':
        result = devices;
      case 'listNearby':
        result = nearby;
      case 'addPresenceDevice':
        devices = [
          ...devices,
          {
            'device_id': 9,
            'name': p['name'],
            'kind': p['kind'],
            'paired_at': 2,
            'last_seen': null,
            'presence_only': true,
            'address': p['address'],
          },
        ];
        result = {'device_id': 9};
      case 'updateDevice':
        devices = [
          for (final d in devices)
            if (d['device_id'] == p['device_id'])
              {
                ...d,
                if (p['name'] != null) 'name': p['name'],
                if (p['kind'] != null) 'kind': p['kind'],
              }
            else
              d,
        ];
      case 'getConfig':
        result = config;
      case 'setConfig':
        config = {...config, ...p};
        result = config;
      case 'startPairing':
        result = {
          'qr_uri': 'stepaway://pair?v=1&id=0001&s=AAAA',
          'verification_code': '424242',
          'expires_at': 4000000000,
        };
    }
    if (m == 'startCodePairing') {
      final text = '${p['code']}'.replaceAll('-', '').replaceAll(' ', '');
      if (text.length != 16) {
        scheduleMicrotask(
          () => _in.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': req['id'],
              'error': {
                'code': -32602,
                'message': 'that code does not look right',
              },
            }),
          ),
        );
        return;
      }
      result = {'expires_at': 4000000000};
    }
    scheduleMicrotask(
      () => _in.add(
        jsonEncode({'jsonrpc': '2.0', 'id': req['id'], 'result': result}),
      ),
    );
  }

  void notify(String method, Map<String, dynamic> params) => _in.add(
    jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
  );
}

class FakeUninstaller implements Uninstaller {
  final ran = <UninstallStep>[];
  @override
  bool get needsAdmin => false;
  @override
  bool get deletesAfterExit => false;
  @override
  bool get isDevelopmentCopy => false;
  @override
  List<UninstallStep> plan({required bool removeData}) => [
    UninstallStep.stopService,
    if (removeData) UninstallStep.data,
    UninstallStep.appFiles,
  ];
  @override
  Future<StepStatus> run(UninstallStep step) async {
    ran.add(step);
    return StepStatus.done;
  }
}

Future<(DaemonModel, FakeDaemon)> boot(
  WidgetTester t, {
  Uninstaller? uninstaller,
}) async {
  final d = FakeDaemon();
  final model = DaemonModel(
    RpcClient(factory: () async => d),
    uninstaller: uninstaller,
  );
  await t.binding.setSurfaceSize(const Size(1100, 800));
  await t.pumpWidget(StepAwayDesktop(model: model));
  await model.init();
  await t.pumpAndSettle();
  return (model, d);
}

void main() {
  beaconTests();
  deviceTests();
  lockListTests();
  trafficLightTests();
  testWidgets('dashboard shows state and live distance from notifications', (
    t,
  ) async {
    final (model, d) = await boot(t);
    expect(find.text('Near'), findsOneWidget);
    expect(find.text(S.noSignal), findsOneWidget);
    d.notify('rssiUpdate', {
      'device_id': 7,
      'rssi': -60,
      'filtered_rssi': -61.2,
      'distance_m': 1.3,
      't': 1,
    });
    await t.pumpAndSettle();
    expect(find.text('1.3 m'), findsOneWidget);
    d.notify('stateChanged', {'from': 'NEAR', 'to': 'LOCKED'});
    await t.pumpAndSettle();
    expect(find.text('Locked by StepAway'), findsOneWidget);
    model.dispose();
  });

  testWidgets('pairing dialog shows QR and code, closes on devicePaired', (
    t,
  ) async {
    final (model, d) = await boot(t);
    await t.tap(find.byKey(const Key('nav-phones')));
    await t.pumpAndSettle();
    expect(find.text('Moto'), findsOneWidget);
    await t.tap(find.byKey(const Key('pair-button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-phone')));
    await t.pump(
      const Duration(milliseconds: 500),
    ); // the spinner never settles
    expect(find.byKey(const Key('pairing-qr')), findsOneWidget);
    expect(find.text('424242'), findsOneWidget);
    d.notify('devicePaired', {'device_id': 9, 'name': 'Phone'});
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text(S.paired), findsOneWidget);
    await t.tap(find.text(S.done));
    await t.pumpAndSettle();
    expect(d.calls, contains('cancelPairing'));
    model.dispose();
  });

  testWidgets('enabling unlock needs confirmation', (t) async {
    final (model, d) = await boot(t);
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('unlock-switch')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('unlock-switch')));
    await t.pumpAndSettle();
    expect(find.text(S.unlockWarningTitle), findsOneWidget);
    await t.tap(find.text(S.cancel));
    await t.pumpAndSettle();
    expect(d.config['unlock_enabled'], false);
    await t.ensureVisible(find.byKey(const Key('unlock-switch')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('unlock-switch')));
    await t.pumpAndSettle();
    await t.tap(find.text(S.turnOn));
    await t.pumpAndSettle();
    expect(d.config['unlock_enabled'], true);
    model.dispose();
  });

  testWidgets('uninstall warns first, and only runs after confirming', (
    t,
  ) async {
    final fake = FakeUninstaller();
    final (model, _) = await boot(t, uninstaller: fake);
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('uninstall-button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('uninstall-button')));
    await t.pumpAndSettle();
    expect(find.text(S.uninstallDialogTitle), findsOneWidget);
    expect(find.text(S.uninstallWarning), findsOneWidget);
    await t.tap(find.text(S.cancel));
    await t.pumpAndSettle();
    expect(fake.ran, isEmpty);

    await t.tap(find.byKey(const Key('uninstall-button')));
    await t.pumpAndSettle();
    await t.tap(
      find.byKey(const Key('uninstall-data-checkbox')),
    ); // keep my data
    await t.pump();
    await t.tap(find.byKey(const Key('uninstall-confirm')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.text(S.uninstallingTitle), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 2));
    expect(find.text(S.uninstallDoneTitle), findsOneWidget);
    expect(find.text(S.uninstallDoneKept), findsOneWidget);
    expect(fake.ran, [UninstallStep.stopService, UninstallStep.appFiles]);
    model.dispose();
  });

  testWidgets('no uninstall section when the platform has no uninstaller', (
    t,
  ) async {
    final (model, _) = await boot(t);
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('uninstall-button')), findsNothing);
    model.dispose();
  });

  testWidgets('prompts to calibrate until the daemon reports calibrated', (
    t,
  ) async {
    final (model, d) = await boot(t);
    expect(find.byKey(const Key('calibrate-banner')), findsOneWidget);
    await t.tap(find.text(S.calibrateNow));
    await t.pumpAndSettle();
    expect(find.text(S.calibrationIntro), findsOneWidget);
    d.config = {...d.config, 'calibrated': true};
    await model.refresh();
    await t.tap(find.byKey(const Key('nav-dashboard')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('calibrate-banner')), findsNothing);
    model.dispose();
  });

  testWidgets('theme can be switched from settings and is remembered', (
    t,
  ) async {
    final store = _MemThemeStore();
    final theme = ThemeController(store: store);
    final d = FakeDaemon();
    final model = DaemonModel(RpcClient(factory: () async => d));
    await t.binding.setSurfaceSize(const Size(1100, 800));
    await t.pumpWidget(StepAwayDesktop(model: model, theme: theme));
    await model.init();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('segment-Dark')));
    await t.pumpAndSettle();
    expect(theme.mode, ThemeMode.dark);
    expect(store.saved, ThemeMode.dark);
    expect(
      Theme.of(t.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    await t.tap(find.byKey(const Key('segment-Light')));
    await t.pumpAndSettle();
    expect(
      Theme.of(t.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );
    // the title bar toggle cycles System -> Light -> Dark -> System
    await t.tap(find.byKey(const Key('theme-toggle')));
    await t.pumpAndSettle();
    expect(theme.mode, ThemeMode.dark);
    model.dispose();
  });

  testWidgets(
    'custom title bar shows the connection state and window buttons',
    (t) async {
      final (model, _) = await boot(t);
      expect(find.byKey(const Key('connection-pill')), findsOneWidget);
      expect(find.text(S.connected), findsOneWidget);
      expect(find.byKey(const Key('traffic-close')), findsOneWidget);
      expect(find.byKey(const Key('traffic-minimize')), findsOneWidget);
      expect(find.byKey(const Key('traffic-maximize')), findsOneWidget);
      expect(
        find.byIcon(Icons.close),
        findsNothing,
      ); // no right-hand window buttons any more
      model.dispose();
    },
  );

  testWidgets('shows a banner when the service is down', (t) async {
    final model = DaemonModel(
      RpcClient(
        factory: () async => throw StateError('down'),
        retryDelay: const Duration(hours: 1),
      ),
    );
    await t.binding.setSurfaceSize(const Size(1100, 800));
    await t.pumpWidget(StepAwayDesktop(model: model));
    await model.init();
    await t.pumpAndSettle();
    expect(find.text(S.serviceDown), findsOneWidget);
    expect(find.text(S.startService), findsOneWidget);
    model.dispose();
  });
}

class _MemThemeStore implements ThemeStore {
  ThemeMode? saved;
  @override
  Future<ThemeMode?> load() async => saved;
  @override
  Future<void> save(ThemeMode mode) async => saved = mode;
}

void lockListTests() {
  Future<(DaemonModel, FakeDaemon)> settings(WidgetTester t) async {
    final r = await boot(t);
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle();
    return r;
  }

  testWidgets('media options: resume is only available once pausing is on', (
    t,
  ) async {
    final (model, d) = await settings(t);
    Finder f(String k) => find.byKey(Key(k));
    await t.ensureVisible(f('pause-media-switch'));
    await t.pumpAndSettle();
    expect(
      t.widget<SwitchListTile>(f('resume-media-switch')).onChanged,
      isNull,
    );
    await t.tap(f('pause-media-switch'));
    await t.pumpAndSettle();
    expect(d.config['lock_pause_media'], true);
    expect(
      t.widget<SwitchListTile>(f('resume-media-switch')).onChanged,
      isNotNull,
    );
    await t.tap(f('resume-media-switch'));
    await t.pumpAndSettle();
    expect(d.config['unlock_resume_media'], true);
    model.dispose();
  });

  testWidgets('apps and services have separate sections', (t) async {
    final (model, _) = await settings(t);
    await t.ensureVisible(find.byKey(const Key('add-app')));
    await t.pumpAndSettle();
    expect(find.text(S.appsSection), findsOneWidget);
    expect(find.text(S.servicesSection), findsOneWidget);
    expect(find.byKey(const Key('add-app')), findsOneWidget);
    expect(find.byKey(const Key('add-service')), findsOneWidget);
    model.dispose();
  });

  testWidgets(
    'apps are chosen from the installed list (running first) and removed again',
    (t) async {
      final (model, d) = await settings(t);
      await t.ensureVisible(find.byKey(const Key('add-app')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<SwitchListTile>(find.byKey(const Key('reopen-apps-switch')))
            .onChanged,
        isNull,
        reason: 'nothing to reopen yet',
      );
      await t.tap(find.byKey(const Key('add-app')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pick-app-firefox.desktop')), findsOneWidget);
      expect(find.byKey(const Key('pick-app-spotify.desktop')), findsOneWidget);
      expect(find.text(S.runningNow), findsOneWidget);
      await t.enterText(find.byKey(const Key('app-field')), 'spot');
      await t.pump();
      expect(find.byKey(const Key('pick-app-firefox.desktop')), findsNothing);
      await t.tap(find.byKey(const Key('pick-app-spotify.desktop')));
      await t.pumpAndSettle();
      expect(d.config['lock_close_apps'], [
        {'id': 'spotify.desktop', 'name': 'Spotify'},
      ]);
      expect(find.byKey(const Key('app-spotify.desktop')), findsOneWidget);
      expect(
        t
            .widget<SwitchListTile>(find.byKey(const Key('reopen-apps-switch')))
            .onChanged,
        isNotNull,
      );
      await t.ensureVisible(find.byTooltip('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Delete'));
      await t.pumpAndSettle();
      expect(d.config['lock_close_apps'], isEmpty);
      model.dispose();
    },
  );

  testWidgets(
    'services can be picked from the running list and removed again',
    (t) async {
      final (model, d) = await settings(t);
      await t.ensureVisible(find.byKey(const Key('add-service')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('add-service')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pick-syncthing.service')), findsOneWidget);
      expect(
        find.byKey(const Key('pick-dbus.service')),
        findsNothing,
        reason: 'protected services are never offered',
      );
      await t.tap(find.byKey(const Key('pick-syncthing.service')));
      await t.pumpAndSettle();
      expect(d.config['lock_stop_services'], ['syncthing.service']);
      expect(
        find.byKey(const Key('service-syncthing.service')),
        findsOneWidget,
      );
      await t.ensureVisible(find.byTooltip('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Delete'));
      await t.pumpAndSettle();
      expect(d.config['lock_stop_services'], isEmpty);
      model.dispose();
    },
  );

  testWidgets('typed service names are checked before they can be added', (
    t,
  ) async {
    final (model, d) = await settings(t);
    await t.ensureVisible(find.byKey(const Key('add-service')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-service')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('service-field')), 'dbus.service');
    await t.pump();
    expect(find.text(S.protectedService), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('service-add-manual')))
          .onPressed,
      isNull,
    );
    await t.enterText(find.byKey(const Key('service-field')), 'rm -rf');
    await t.pump();
    expect(find.text(S.invalidService), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('service-field')),
      'my-sync.service',
    );
    await t.pump();
    await t.tap(find.byKey(const Key('service-add-manual')));
    await t.pumpAndSettle();
    expect(d.config['lock_stop_services'], ['my-sync.service']);
    model.dispose();
  });
}

void beaconTests() {
  testWidgets(
    'the beacon that lets devices show distance can be switched off',
    (t) async {
      final (model, d) = await boot(t);
      await t.tap(find.byKey(const Key('nav-settings')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('beacon-switch')));
      await t.pumpAndSettle();
      expect(
        t.widget<SwitchListTile>(find.byKey(const Key('beacon-switch'))).value,
        isTrue,
      );
      await t.tap(find.byKey(const Key('beacon-switch')));
      await t.pumpAndSettle();
      expect(d.config['beacon_enabled'], false);
      model.dispose();
    },
  );
}

void deviceTests() {
  Future<(DaemonModel, FakeDaemon)> devicesPage(WidgetTester t) async {
    final r = await boot(t);
    await t.tap(find.byKey(const Key('nav-phones')));
    await t.pumpAndSettle();
    return r;
  }

  testWidgets('adding a device first asks what kind it is', (t) async {
    final (model, d) = await devicesPage(t);
    await t.tap(find.byKey(const Key('pair-button')));
    await t.pumpAndSettle();
    for (final k in ['add-phone', 'add-tablet', 'add-watch', 'add-other']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    await t.tap(find.byKey(const Key('add-tablet')));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('pairing-qr')), findsOneWidget);
    final call = d.requests.firstWhere((r) => r['method'] == 'startPairing');
    expect(call['kind'], 'tablet');
    model.dispose();
  });

  testWidgets('a watch is paired by typing the code it shows', (t) async {
    final (model, d) = await devicesPage(t);
    await t.tap(find.byKey(const Key('pair-button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-watch')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('watch-app')), findsOneWidget);
    expect(find.byKey(const Key('watch-bluetooth')), findsOneWidget);
    await t.tap(find.byKey(const Key('watch-app')));
    await t.pumpAndSettle();
    // a code that is too short is refused before anything is listened for
    await t.enterText(find.byKey(const Key('code-field')), '1234');
    await t.tap(find.byKey(const Key('code-start')));
    await t.pumpAndSettle();
    expect(find.text(S.codeBad), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('code-field')),
      '000g-40r4-0m30-e209',
    );
    await t.tap(find.byKey(const Key('code-start')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(S.codeListening), findsOneWidget);
    final start = d.requests.lastWhere(
      (r) => r['method'] == 'startCodePairing',
    );
    expect(start['code'], '000g-40r4-0m30-e209');
    d.notify('devicePaired', {'device_id': 77, 'name': 'Smartwatch'});
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text(S.paired), findsOneWidget);
    await t.tap(find.text(S.done));
    await t.pumpAndSettle();
    expect(d.calls, contains('cancelPairing'));
    model.dispose();
  });

  testWidgets(
    'a code that did not match shows why and lets the user try again',
    (t) async {
      final (model, d) = await devicesPage(t);
      await t.tap(find.byKey(const Key('pair-button')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('add-watch')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('watch-app')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('code-field')),
        '0000-0000-0000-0000',
      );
      await t.tap(find.byKey(const Key('code-start')));
      await t.pump(const Duration(milliseconds: 300));
      d.notify('pairingFailed', {
        'reason':
            'the code did not match; check it on the device and try again',
      });
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('code-error')), findsOneWidget);
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('code-field')), findsOneWidget);
      model.dispose();
    },
  );

  testWidgets('a nearby Bluetooth device can be added as lock-only', (t) async {
    final (model, d) = await devicesPage(t);
    await t.tap(find.byKey(const Key('pair-button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-other')));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Mi Band'), findsOneWidget);
    expect(find.text(S.unnamedDevice), findsOneWidget);
    await t.tap(find.byKey(const Key('nearby-AA:BB:CC:DD:EE:01')));
    await t.pumpAndSettle();
    expect(
      find.text(S.lockOnlyWarning),
      findsOneWidget,
      reason: 'the lock-only limit is explained before adding',
    );
    expect(
      (t.widget<TextField>(find.byKey(const Key('presence-name'))).controller)!
          .text,
      'Mi Band',
    );
    await t.tap(find.byKey(const Key('presence-kind-watch')));
    await t.pump();
    await t.tap(find.byKey(const Key('presence-add')));
    await t.pumpAndSettle();
    final add = d.requests.firstWhere(
      (r) => r['method'] == 'addPresenceDevice',
    );
    expect(
      (add['address'], add['name'], add['kind']),
      ('AA:BB:CC:DD:EE:01', 'Mi Band', 'watch'),
    );
    expect(
      find.byKey(const Key('lock-only-9')),
      findsOneWidget,
      reason: 'shows the Lock only badge',
    );
    model.dispose();
  });

  testWidgets('a device can be renamed and given another type', (t) async {
    final (model, d) = await devicesPage(t);
    await t.tap(find.byKey(const Key('device-menu-7')));
    await t.pumpAndSettle();
    await t.tap(find.text(S.rename));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('rename-field')), "Sandip's phone");
    await t.tap(find.text(S.done));
    await t.pumpAndSettle();
    expect(find.text("Sandip's phone"), findsOneWidget);
    await t.tap(find.byKey(const Key('device-menu-7')));
    await t.pumpAndSettle();
    await t.tap(find.text(S.changeType));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('kind-watch')));
    await t.pumpAndSettle();
    expect(d.devices.first['kind'], 'watch');
    expect(find.textContaining('Smartwatch'), findsOneWidget);
    model.dispose();
  });

  testWidgets('the presence rule for several devices is chosen in settings', (
    t,
  ) async {
    final (model, d) = await boot(t);
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle();
    expect(find.text(S.ruleAnyHelp), findsOneWidget);
    await t.tap(find.byKey(const Key('segment-${S.ruleAll}')));
    await t.pumpAndSettle();
    expect(d.config['presence_rule'], 'all');
    expect(find.text(S.ruleAllHelp), findsOneWidget);
    model.dispose();
  });

  testWidgets(
    'with two devices the calibration page asks which one to calibrate',
    (t) async {
      final (model, d) = await boot(t);
      d.devices = [
        ...d.devices,
        {
          'device_id': 8,
          'name': 'Watch',
          'kind': 'watch',
          'paired_at': 1,
          'last_seen': null,
          'presence_only': false,
        },
      ];
      await model.refresh();
      await t.tap(find.byKey(const Key('nav-calibrate')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('calib-device')), findsOneWidget);
      await t.tap(find.byKey(const Key('calib-device')));
      await t.pumpAndSettle();
      await t.tap(find.text('Watch').last);
      await t.pumpAndSettle();
      await t.tap(find.text(S.calibrate).last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('calib-start')));
      await t.pump();
      final call = d.requests.firstWhere(
        (r) => r['method'] == 'startCalibration',
      );
      expect(call['device_id'], 8);
      model.dispose();
    },
  );
}

void trafficLightTests() {
  testWidgets(
    'traffic lights are red, yellow and green and call their handlers',
    (t) async {
      final calls = <String>[];
      await t.pumpWidget(
        MaterialApp(
          theme: StepAwayTheme.light(),
          home: Scaffold(
            body: Center(
              child: TrafficLights(
                onClose: () => calls.add('close'),
                onMinimize: () => calls.add('minimize'),
                onMaximize: () => calls.add('maximize'),
              ),
            ),
          ),
        ),
      );
      Color colorOf(String key) {
        final box = t.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (box.decoration! as BoxDecoration).color!;
      }

      expect(colorOf('traffic-close'), const Color(0xFFFF5F57));
      expect(colorOf('traffic-minimize'), const Color(0xFFFEBC2E));
      expect(colorOf('traffic-maximize'), const Color(0xFF28C840));
      await t.tap(find.byKey(const Key('traffic-close')));
      await t.tap(find.byKey(const Key('traffic-minimize')));
      await t.tap(find.byKey(const Key('traffic-maximize')));
      expect(calls, ['close', 'minimize', 'maximize']);
    },
  );

  testWidgets('traffic lights go grey when the window loses focus', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: StepAwayTheme.dark(),
        home: Scaffold(
          body: Center(
            child: TrafficLights(
              focused: false,
              onClose: () {},
              onMinimize: () {},
              onMaximize: () {},
            ),
          ),
        ),
      ),
    );
    final box = t.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const Key('traffic-close')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect((box.decoration! as BoxDecoration).color, const Color(0x40FFFFFF));
  });

  testWidgets('window frame rounds the corners only when enabled', (t) async {
    Widget framed(bool on) => MaterialApp(
      theme: StepAwayTheme.dark(),
      home: WindowFrame(enabled: on, child: const SizedBox.expand()),
    );
    await t.pumpWidget(framed(true));
    expect(find.byType(ClipRSuperellipse), findsOneWidget);
    await t.pumpWidget(framed(false));
    expect(find.byType(ClipRSuperellipse), findsNothing);
  });
}
