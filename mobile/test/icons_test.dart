// Renders the StepAway logo to the Android launcher PNGs (and a store icon).
// Run: SA_ICONS=1 flutter test test/icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

void main() {
  final enabled = Platform.environment['SA_ICONS'] != null;
  const sizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  Future<void> render(WidgetTester t, int px, String path) async {
    t.view.physicalSize = Size(px.toDouble(), px.toDouble());
    t.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: StepAwayTheme.dark(),
          home: Material(
            color: Colors.transparent,
            child: StepAwayLogo(size: px.toDouble(), shadow: false),
          ),
        ),
      ),
    );
    await t.pump();
    await t.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(path).create(recursive: true);
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  for (final e in sizes.entries) {
    testWidgets('launcher icon ${e.key}', (t) async {
      await render(
        t,
        e.value,
        'android/app/src/main/res/mipmap-${e.key}/ic_launcher.png',
      );
    }, skip: !enabled);
  }
  testWidgets('store icon 512', (t) async {
    await render(t, 512, '../packaging/icon-512.png');
  }, skip: !enabled);
}
