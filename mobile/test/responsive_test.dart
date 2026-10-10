import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_mobile/main.dart';
import 'package:stepaway_mobile/native.dart';
import 'package:stepaway_mobile/strings.dart';

import 'test_fonts.dart';
import 'widget_test.dart' show FakeNative;

const _paired = AppStatus(
  protection: true,
  advertising: true,
  batteryUnrestricted: false,
  permissionsGranted: false,
  bluetoothOn: false,
  pairings: [
    PairingInfo(1, 'My very long computer name that keeps going'),
    PairingInfo(2, 'Work laptop'),
  ],
);

Future<void> open(
  WidgetTester t,
  double w,
  double h, {
  double textScale = 1,
}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(StepAwayApp(native: FakeNative(status_: _paired)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 900));
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('portrait phones use the floating tab bar', (t) async {
    await open(t, 393, 851);
    expect(find.byKey(const Key('tab-indicator')), findsOneWidget);
    expect(find.byKey(const Key('rail-indicator')), findsNothing);
  });

  testWidgets('tablets and landscape phones use the side rail', (t) async {
    await open(t, 851, 393);
    expect(find.byKey(const Key('rail-indicator')), findsOneWidget);
    expect(find.byKey(const Key('tab-indicator')), findsNothing);
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
    expect(find.text(S.permissionsSection), findsOneWidget);
  });

  final cases = {
    'small phone 320x568': (320.0, 568.0, 1.0),
    'phone 393x851': (393.0, 851.0, 1.0),
    'phone with large text': (393.0, 851.0, 1.6),
    'small phone with large text': (320.0, 640.0, 1.4),
    'landscape phone': (851.0, 393.0, 1.0),
    'tablet portrait': (800.0, 1280.0, 1.0),
    'tablet landscape': (1280.0, 800.0, 1.0),
  };
  for (final e in cases.entries) {
    testWidgets('every tab lays out on a ${e.key} without overflow', (t) async {
      final (w, h, scale) = e.value;
      await open(t, w, h, textScale: scale);
      for (final tab in ['nav-computers', 'nav-settings', 'nav-shield']) {
        await t.tap(find.byKey(Key(tab)));
        await t.pump(const Duration(milliseconds: 100));
        await t.pump(const Duration(milliseconds: 900));
      }
    });
  }
}
