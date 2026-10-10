import 'dart:io';

import 'package:flutter/services.dart';

/// Loads Inter and the Material icon font so tests lay text out like the real app does
/// (the default test font draws every letter as a wide square).
Future<void> loadTestFonts() async {
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
