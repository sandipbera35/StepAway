// Renders each screen to a PNG so the design can be reviewed without a display.
// Run: SA_SCREENSHOTS=/some/dir flutter test test/screenshots_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_desktop/ipc/rpc_client.dart';
import 'package:stepaway_desktop/ipc/transport.dart';
import 'package:stepaway_desktop/main.dart';
import 'package:stepaway_desktop/model.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

class _Daemon implements Transport {
  final _in = StreamController<String>();
  @override
  Stream<String> get lines => _in.stream;
  @override
  Future<void> close() async {}
  @override
  void send(String line) {
    final req = jsonDecode(line) as Map<String, dynamic>;
    final result = switch (req['method']) {
      'status' => {
        'state': 'NEAR',
        'paused': false,
        'scanning': true,
        'devices_present': [7],
      },
      'listDevices' => [
        {
          'device_id': 7,
          'name': 'Motorola edge 30',
          'paired_at': 1,
          'last_seen': 1791609000,
        },
        {'device_id': 8, 'name': 'Pixel 8', 'paired_at': 1, 'last_seen': null},
      ],
      'getConfig' => {
        'lock_distance_m': 3.0,
        'return_distance_m': 2.0,
        'lock_grace_s': 10,
        'return_grace_s': 3,
        'unlock_enabled': true,
        'calibrated': false,
      },
      _ => {'ok': true},
    };
    scheduleMicrotask(
      () => _in.add(
        jsonEncode({'jsonrpc': '2.0', 'id': req['id'], 'result': result}),
      ),
    );
  }

  void note(String m, Map<String, dynamic> p) =>
      _in.add(jsonEncode({'jsonrpc': '2.0', 'method': m, 'params': p}));
}

Future<void> _loadFonts() async {
  Future<ByteData> read(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());
  final inter = FontLoader('packages/stepaway_ui/Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(read('../ui/assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/development/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      read(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  await icons.load();
}

void main() {
  final dir = Platform.environment['SA_SCREENSHOTS'];
  setUpAll(() async {
    if (dir != null) await _loadFonts();
  });
  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    for (final page in [
      'nav-dashboard',
      'nav-phones',
      'nav-calibrate',
      'nav-settings',
    ]) {
      testWidgets('screenshot ${mode.name} $page', (t) async {
        t.view.physicalSize = Size(
          page == 'nav-dashboard' && mode == ThemeMode.light ? 520 : 1180,
          760,
        );
        t.view.devicePixelRatio = 1;
        final d = _Daemon();
        final model = DaemonModel(RpcClient(factory: () async => d));
        final theme = ThemeController();
        await theme.setMode(mode);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: StepAwayDesktop(model: model, theme: theme),
          ),
        );
        await model.init();
        for (var i = 0; i < 60; i++) {
          final dist =
              1.2 +
              1.3 * (0.5 + 0.5 * math.sin(i / 7)) +
              (i > 45 ? (i - 45) * 0.08 : 0);
          d.note('rssiUpdate', {
            'device_id': 7,
            'rssi': -55,
            'filtered_rssi': -55.0,
            'distance_m': dist,
            't': i,
          });
        }
        await t.pumpAndSettle();
        await t.tap(find.byKey(Key(page)));
        await t.pumpAndSettle();
        if (dir != null) {
          await t.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$dir/${mode.name}-$page.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        model.dispose();
      }, skip: dir == null);
    }
  }
}
