import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What the uninstaller does, in the order the user sees it.
enum UninstallStep { stopService, appFiles, autostart, shortcuts, data }

enum StepStatus { pending, running, done, skipped, failed }

class UninstallException implements Exception {
  const UninstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> args,
);
typedef SpawnDetached = Future<void> Function(
  String executable,
  List<String> args,
);

Future<ProcessResult> _run(String exe, List<String> args) =>
    Process.run(exe, args);

Future<void> _spawnDetached(String exe, List<String> args) async {
  await Process.start(exe, args, mode: ProcessStartMode.detached);
}

/// Removes StepAway from this computer. Same steps on every platform; each platform decides how.
abstract class Uninstaller {
  /// Steps to run, in order. Anything that could fail on a permission prompt comes first, so
  /// cancelling it leaves the installation untouched.
  List<UninstallStep> plan({required bool removeData});

  /// Runs one step. Returns [StepStatus.done] or [StepStatus.skipped]; throws
  /// [UninstallException] when the step failed.
  Future<StepStatus> run(UninstallStep step);

  /// True when removing the app asks for an administrator password.
  bool get needsAdmin;

  /// True when the app folder can only be deleted after this app has exited.
  bool get deletesAfterExit;

  /// True for a development run (`flutter run`): the app files are left alone.
  bool get isDevelopmentCopy;
}

/// Only deletes folders that are clearly StepAway's own, whatever the environment says.
bool _safeToDelete(String path, String lastSegment) {
  final norm = path.replaceAll('\\', '/');
  final parts = norm.split('/').where((p) => p.isNotEmpty).toList();
  return parts.length >= 2 &&
      parts.last.toLowerCase() == lastSegment.toLowerCase();
}

Future<void> _deleteDir(String path, String lastSegment) async {
  if (!_safeToDelete(path, lastSegment)) {
    throw UninstallException('Refusing to delete an unexpected folder: $path');
  }
  final d = Directory(path);
  try {
    if (d.existsSync()) await d.delete(recursive: true);
  } on FileSystemException catch (e) {
    throw UninstallException(
      'Could not delete $path (${e.osError?.message ?? e.message})',
    );
  }
}

Future<void> _deleteFile(String path) async {
  try {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  } on FileSystemException catch (e) {
    throw UninstallException(
      'Could not delete $path (${e.osError?.message ?? e.message})',
    );
  }
}

const _appId = 'io.github.sandipbera35.StepAway';

enum LinuxInstallKind { user, system, development }

class LinuxUninstaller implements Uninstaller {
  LinuxUninstaller({
    String? executable,
    Map<String, String>? env,
    RunProcess? run,
  }) : _exe = executable ?? Platform.resolvedExecutable,
       _env = env ?? Platform.environment,
       _runProcess = run ?? _run;

  final String _exe;
  final Map<String, String> _env;
  final RunProcess _runProcess;

  String get _home => _env['HOME'] ?? '';
  String get _config => _env['XDG_CONFIG_HOME'] ?? '$_home/.config';
  String get _share => _env['XDG_DATA_HOME'] ?? '$_home/.local/share';
  String get _dataDir => '$_share/stepaway';
  String get _userApp => '$_dataDir/app';

  LinuxInstallKind get kind {
    if (_exe.startsWith('/opt/stepaway/') || _exe.startsWith('/usr/')) {
      return LinuxInstallKind.system;
    }
    if (_exe.startsWith('$_userApp/')) return LinuxInstallKind.user;
    return LinuxInstallKind.development;
  }

  @override
  bool get needsAdmin => kind == LinuxInstallKind.system;
  @override
  bool get deletesAfterExit => false;
  @override
  bool get isDevelopmentCopy => kind == LinuxInstallKind.development;

  @override
  List<UninstallStep> plan({required bool removeData}) => [
    if (kind == LinuxInstallKind.system) UninstallStep.appFiles,
    UninstallStep.stopService,
    UninstallStep.autostart,
    UninstallStep.shortcuts,
    if (removeData) UninstallStep.data,
    if (kind != LinuxInstallKind.system) UninstallStep.appFiles,
  ];

  @override
  Future<StepStatus> run(UninstallStep step) async {
    if (_home.isEmpty) throw const UninstallException('HOME is not set.');
    switch (step) {
      case UninstallStep.stopService:
        await _runProcess('pkill', ['-x', 'stepawayd']);
        for (var i = 0; i < 15; i++) {
          final r = await _runProcess('pgrep', ['-x', 'stepawayd']);
          if (r.exitCode != 0) break; // no daemon left
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        return StepStatus.done;
      case UninstallStep.autostart:
        await _deleteFile('$_config/autostart/$_appId.Daemon.desktop');
        return StepStatus.done;
      case UninstallStep.shortcuts:
        await _deleteFile('$_share/applications/$_appId.desktop');
        await _deleteFile('$_share/icons/hicolor/scalable/apps/$_appId.svg');
        return StepStatus.done;
      case UninstallStep.data:
        await _deleteDir('$_config/stepaway', 'stepaway');
        // The app of a per-user install lives inside the data folder and is removed last.
        final dir = Directory(_dataDir);
        if (dir.existsSync()) {
          for (final e in dir.listSync()) {
            if (e.path == _userApp) continue; // removed by the appFiles step
            try {
              await e.delete(recursive: true);
            } on FileSystemException catch (err) {
              throw UninstallException(
                'Could not delete ${e.path} (${err.message})',
              );
            }
          }
        }
        return StepStatus.done;
      case UninstallStep.appFiles:
        switch (kind) {
          case LinuxInstallKind.development:
            return StepStatus.skipped;
          case LinuxInstallKind.user:
            await _deleteDir(_userApp, 'app');
            final dir = Directory(_dataDir);
            if (dir.existsSync() && dir.listSync().isEmpty) await dir.delete();
            return StepStatus.done;
          case LinuxInstallKind.system:
            return _removePackage();
        }
    }
  }

  Future<StepStatus> _removePackage() async {
    const script =
        'if dpkg -s stepaway >/dev/null 2>&1; then dpkg -r stepaway; '
        'elif rpm -q stepaway >/dev/null 2>&1; then rpm -e stepaway; '
        'else exit 3; fi';
    final ProcessResult r;
    try {
      r = await _runProcess('pkexec', ['sh', '-c', script]);
    } on ProcessException {
      throw const UninstallException(
        'Administrator access (pkexec) is not available. Remove it with: sudo apt remove stepaway  or  sudo dnf remove stepaway',
      );
    }
    switch (r.exitCode) {
      case 0:
        return StepStatus.done;
      case 126:
      case 127:
        throw const UninstallException(
          'The administrator password prompt was cancelled.',
        );
      case 3:
        return StepStatus.skipped; // not installed from a package
      default:
        throw UninstallException(
          'The package manager failed (exit ${r.exitCode}).',
        );
    }
  }
}

class WindowsUninstaller implements Uninstaller {
  WindowsUninstaller({
    String? executable,
    Map<String, String>? env,
    RunProcess? run,
    SpawnDetached? spawn,
  }) : _exe = executable ?? Platform.resolvedExecutable,
       _env = env ?? Platform.environment,
       _runProcess = run ?? _run,
       _spawn = spawn ?? _spawnDetached;

  final String _exe;
  final Map<String, String> _env;
  final RunProcess _runProcess;
  final SpawnDetached _spawn;

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  String get _sep => _exe.contains('\\') ? '\\' : '/';
  String _p(String base, List<String> parts) => [base, ...parts].join(_sep);

  String get _appData => _env['APPDATA'] ?? '';
  String get _appDir {
    final i = _exe.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? '' : _exe.substring(0, i);
  }

  @override
  bool get isDevelopmentCopy =>
      _appDir.toLowerCase().replaceAll('/', '\\').contains(r'\build\windows\');
  @override
  bool get needsAdmin => false;
  @override
  bool get deletesAfterExit => !isDevelopmentCopy;

  @override
  List<UninstallStep> plan({required bool removeData}) => [
    UninstallStep.stopService,
    UninstallStep.autostart,
    UninstallStep.shortcuts,
    if (removeData) UninstallStep.data,
    UninstallStep.appFiles,
  ];

  @override
  Future<StepStatus> run(UninstallStep step) async {
    switch (step) {
      case UninstallStep.stopService:
        await _runProcess('taskkill', [
          '/F',
          '/IM',
          'stepawayd.exe',
        ]); // 128 = not running
        return StepStatus.done;
      case UninstallStep.autostart:
        await _runProcess('reg', [
          'delete',
          _runKey,
          '/v',
          'StepAway',
          '/f',
        ]); // 1 = no entry
        return StepStatus.done;
      case UninstallStep.shortcuts:
        if (_appData.isNotEmpty) {
          await _deleteFile(
            _p(_appData, [
              'Microsoft',
              'Windows',
              'Start Menu',
              'Programs',
              'StepAway.lnk',
            ]),
          );
        }
        return StepStatus.done;
      case UninstallStep.data:
        if (_appData.isEmpty) {
          throw const UninstallException('APPDATA is not set.');
        }
        await _deleteDir(_p(_appData, ['StepAway']), 'StepAway');
        return StepStatus.done;
      case UninstallStep.appFiles:
        if (isDevelopmentCopy) return StepStatus.skipped;
        // A running program cannot delete its own folder on Windows: a tiny script waits for
        // this app to exit, then deletes the folder and itself.
        if (!File(_p(_appDir, ['stepawayd.exe'])).existsSync() &&
            !File(_p(_appDir, ['stepaway_desktop.exe'])).existsSync()) {
          throw UninstallException(
            'This does not look like a StepAway folder: $_appDir',
          );
        }
        final tmp = _env['TEMP'] ?? _env['TMP'] ?? _appDir;
        final bat = _p(tmp, ['stepaway-uninstall.bat']);
        try {
          await File(bat).writeAsString(
            '@echo off\r\n'
            'ping -n 4 127.0.0.1 >nul\r\n'
            'rmdir /s /q "$_appDir"\r\n'
            'del "%~f0"\r\n',
          );
          await _spawn('cmd', ['/c', bat]);
        } on Object catch (e) {
          throw UninstallException(
            'Could not schedule the removal of $_appDir ($e)',
          );
        }
        return StepStatus.done;
    }
  }
}

/// The uninstaller for the platform this app runs on, or null where there is none.
Uninstaller? createUninstaller() {
  if (Platform.isLinux) return LinuxUninstaller();
  if (Platform.isWindows) return WindowsUninstaller();
  return null;
}

/// Runs an [Uninstaller] one step at a time and exposes progress for the animation. Each step
/// stays on screen for at least [minStepTime] so the user can follow what is happening.
class UninstallController extends ChangeNotifier {
  UninstallController(
    this.uninstaller, {
    required this.removeData,
    this.minStepTime = const Duration(milliseconds: 800),
  }) : steps = uninstaller.plan(removeData: removeData) {
    for (final s in steps) {
      status[s] = StepStatus.pending;
    }
  }

  final Uninstaller uninstaller;
  final bool removeData;
  final Duration minStepTime;
  final List<UninstallStep> steps;
  final Map<UninstallStep, StepStatus> status = {};
  String? error;
  bool finished = false;
  bool _started = false;

  bool get failed => error != null;
  bool get succeeded => finished && !failed;

  /// 0..1: finished steps plus half of the running one.
  double get progress {
    if (steps.isEmpty) return finished ? 1 : 0;
    var sum = 0.0;
    for (final s in steps) {
      switch (status[s]!) {
        case StepStatus.done || StepStatus.skipped:
          sum += 1;
        case StepStatus.running:
          sum += 0.5;
        default:
      }
    }
    return sum / steps.length;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (final s in steps) {
      status[s] = StepStatus.running;
      notifyListeners();
      final began = DateTime.now();
      try {
        status[s] = await uninstaller.run(s);
      } on Object catch (e) {
        status[s] = StepStatus.failed;
        error = e is UninstallException ? e.message : '$e';
        finished = true;
        notifyListeners();
        return;
      }
      final left = minStepTime - DateTime.now().difference(began);
      if (left > Duration.zero) await Future<void>.delayed(left);
      notifyListeners();
    }
    finished = true;
    notifyListeners();
  }
}
