import 'package:flutter/material.dart';

/// Where the chosen theme is remembered (a file on desktop, app preferences on Android).
abstract class ThemeStore {
  Future<ThemeMode?> load();
  Future<void> save(ThemeMode mode);
}

class ThemeController extends ChangeNotifier {
  ThemeController({this.store});

  final ThemeStore? store;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  Future<void> init() async {
    try {
      final saved = await store?.load();
      if (saved != null && saved != _mode) {
        _mode = saved;
        notifyListeners();
      }
    } catch (_) {
      // an unreadable preference just means "follow the system"
    }
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    try {
      await store?.save(m);
    } catch (_) {
      // not being able to remember the choice is not fatal
    }
  }

  static String encode(ThemeMode m) => m.name;

  static ThemeMode? decode(String? s) {
    for (final m in ThemeMode.values) {
      if (m.name == s) return m;
    }
    return null;
  }
}

/// Convenience labels so both apps show the same wording and icons.
class ThemeChoices {
  static const system = 'System';
  static const light = 'Light';
  static const dark = 'Dark';
}
