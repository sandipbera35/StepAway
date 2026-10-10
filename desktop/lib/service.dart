import 'dart:io';

/// Locates and starts the daemon that ships inside the app bundle, and registers it to start
/// at login. Users install the desktop app only; this is how the daemon comes along.
abstract class ServiceManager {
  Future<bool> startDaemon();
  Future<bool> autostartEnabled();
  Future<void> setAutostart(bool enabled);

  /// Enables autostart once, the first time the app runs.
  Future<void> ensureDefaultAutostart();
}

String daemonName() => Platform.isWindows ? 'stepawayd.exe' : 'stepawayd';

/// Candidate locations for the bundled daemon, best first.
List<String> daemonCandidates(String appExecutable, {String? separator}) {
  final sep = separator ?? Platform.pathSeparator;
  final dir = File(appExecutable).parent.path;
  return ['$dir$sep${daemonName()}', '$dir${sep}bin$sep${daemonName()}'];
}

/// Contents of the XDG autostart entry for the daemon.
String autostartDesktopEntry(String daemonPath) {
  final quoted =
      '"${daemonPath.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  return '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=StepAway\n'
      'Comment=Locks this computer when your phone moves away\n'
      'Exec=$quoted\n'
      'Terminal=false\n'
      'NoDisplay=true\n'
      'X-GNOME-Autostart-enabled=true\n';
}

class SystemServiceManager implements ServiceManager {
  SystemServiceManager({String? executable, Map<String, String>? env})
    : _exe = executable ?? Platform.resolvedExecutable,
      _env = env ?? Platform.environment;

  final String _exe;
  final Map<String, String> _env;

  String? _bundledDaemon() {
    for (final c in daemonCandidates(_exe)) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  @override
  Future<bool> startDaemon() async {
    final path =
        _bundledDaemon() ?? daemonName(); // fall back to PATH (development)
    try {
      await Process.start(path, const [], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- autostart ----

  File get _linuxEntry {
    final cfg = _env['XDG_CONFIG_HOME'] ?? '${_env['HOME'] ?? ''}/.config';
    return File(
      '$cfg/autostart/io.github.sandipbera35.StepAway.Daemon.desktop',
    );
  }

  File get _marker {
    if (Platform.isWindows) {
      return File('${_env['APPDATA'] ?? ''}\\StepAway\\ui-first-run');
    }
    final cfg = _env['XDG_CONFIG_HOME'] ?? '${_env['HOME'] ?? ''}/.config';
    return File('$cfg/stepaway/ui-first-run');
  }

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  @override
  Future<bool> autostartEnabled() async {
    if (Platform.isWindows) {
      final r = await Process.run('reg', ['query', _runKey, '/v', 'StepAway']);
      return r.exitCode == 0;
    }
    return _linuxEntry.existsSync();
  }

  @override
  Future<void> setAutostart(bool enabled) async {
    final daemon = _bundledDaemon();
    if (Platform.isWindows) {
      if (enabled && daemon != null) {
        await Process.run('reg', [
          'add',
          _runKey,
          '/v',
          'StepAway',
          '/t',
          'REG_SZ',
          '/d',
          '"$daemon"',
          '/f',
        ]);
      } else if (!enabled) {
        await Process.run('reg', ['delete', _runKey, '/v', 'StepAway', '/f']);
      }
      return;
    }
    final f = _linuxEntry;
    if (enabled && daemon != null) {
      await f.parent.create(recursive: true);
      await f.writeAsString(autostartDesktopEntry(daemon));
    } else if (!enabled && f.existsSync()) {
      await f.delete();
    }
  }

  @override
  Future<void> ensureDefaultAutostart() async {
    try {
      if (_marker.existsSync()) return;
      await setAutostart(true);
      await _marker.parent.create(recursive: true);
      await _marker.writeAsString('1');
    } catch (_) {
      // not fatal: the user can still turn it on in Settings
    }
  }
}
