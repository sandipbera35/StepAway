import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

/// Remembers the chosen theme in the user's config folder.
class FileThemeStore implements ThemeStore {
  FileThemeStore([File? file]) : _file = file ?? _defaultFile();

  final File _file;

  static File _defaultFile() {
    final env = Platform.environment;
    final dir = Platform.isWindows
        ? '${env['APPDATA'] ?? ''}\\StepAway'
        : '${env['XDG_CONFIG_HOME'] ?? '${env['HOME'] ?? ''}/.config'}/stepaway';
    return File('$dir${Platform.pathSeparator}ui.json');
  }

  @override
  Future<ThemeMode?> load() async {
    if (!_file.existsSync()) return null;
    final json = jsonDecode(await _file.readAsString());
    return json is Map
        ? ThemeController.decode(json['theme'] as String?)
        : null;
  }

  @override
  Future<void> save(ThemeMode mode) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({'theme': ThemeController.encode(mode)}),
    );
  }
}
