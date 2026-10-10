import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_desktop/ipc/rpc_client.dart';
import 'package:stepaway_desktop/main.dart';
import 'package:stepaway_desktop/model.dart';
import 'package:stepaway_desktop/strings.dart';
import 'package:stepaway_desktop/widgets.dart';

import 'ui_test.dart' show FakeDaemon;

Future<void> _loadFonts() async {
  Future<ByteData> read(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());
  final inter = FontLoader('packages/stepaway_ui/Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(read('../ui/assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/development/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      read(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  await icons.load();
}

Future<DaemonModel> open(
  WidgetTester t,
  double width, [
  double height = 800,
]) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  final model = DaemonModel(RpcClient(factory: () async => FakeDaemon()));
  await t.pumpWidget(StepAwayDesktop(model: model));
  await model.init();
  await t.pumpAndSettle();
  return model;
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('wide windows get the full sidebar with labels', (t) async {
    final m = await open(t, 1280);
    expect(find.byKey(const Key('nav-indicator')), findsOneWidget);
    expect(find.byKey(const Key('tab-indicator')), findsNothing);
    expect(find.text(S.calibrate), findsOneWidget, reason: 'sidebar label');
    m.dispose();
  });

  testWidgets('medium windows shrink the sidebar to an icon rail', (t) async {
    final m = await open(t, 820);
    expect(find.byKey(const Key('nav-indicator')), findsOneWidget);
    expect(
      find.text(S.calibrate),
      findsNothing,
      reason: 'labels are hidden in the rail',
    );
    expect(
      t.getSize(find.byKey(const Key('nav-dashboard'))).width,
      lessThan(100),
    );
    m.dispose();
  });

  testWidgets('narrow windows switch to the floating tab bar', (t) async {
    final m = await open(t, 480, 760);
    expect(find.byKey(const Key('tab-indicator')), findsOneWidget);
    expect(find.byKey(const Key('nav-indicator')), findsNothing);
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle();
    expect(find.text(S.appearance), findsOneWidget);
    m.dispose();
  });

  for (final w in [1280.0, 1000.0, 820.0, 640.0, 520.0, 420.0]) {
    testWidgets('every page lays out at $w px without overflow', (t) async {
      final m = await open(t, w, 760);
      for (final nav in [
        'nav-dashboard',
        'nav-phones',
        'nav-calibrate',
        'nav-settings',
      ]) {
        await t.tap(find.byKey(Key(nav)));
        await t.pumpAndSettle();
      }
      m.dispose();
    });
  }

  testWidgets(
    'dashboard cards line up: the three tiles share one height and width',
    (t) async {
      final m = await open(t, 1280);
      final tiles = find.byType(StatTile);
      expect(tiles, findsNWidgets(3));
      final sizes = [for (var i = 0; i < 3; i++) t.getSize(tiles.at(i))];
      expect(
        sizes.map((s) => s.height).toSet().length,
        1,
        reason: 'equal heights: $sizes',
      );
      expect(
        sizes.map((s) => s.width.round()).toSet().length,
        1,
        reason: 'equal widths: $sizes',
      );
      m.dispose();
    },
  );
}
