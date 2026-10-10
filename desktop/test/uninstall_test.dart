import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_desktop/pages/uninstall_screen.dart';
import 'package:stepaway_desktop/strings.dart';
import 'package:stepaway_desktop/uninstall.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

const _id = 'io.github.sandipbera35.StepAway';

class _Calls {
  final log = <String>[];
  int pgrepLeft = 0; // how many pgrep calls still report a running daemon
  int pkexecExit = 0;
  Future<ProcessResult> run(String exe, List<String> args) async {
    log.add('$exe ${args.join(' ')}');
    if (exe == 'pgrep') {
      return ProcessResult(0, pgrepLeft-- > 0 ? 0 : 1, '', '');
    }
    if (exe == 'pkexec') return ProcessResult(0, pkexecExit, '', '');
    return ProcessResult(0, 0, '', '');
  }
}

Directory _linuxHome() {
  final home = Directory.systemTemp.createTempSync('sa-home');
  for (final p in [
    '.config/stepaway/config.toml',
    '.config/autostart/$_id.Daemon.desktop',
    '.local/share/stepaway/devices.json',
    '.local/share/stepaway/stepawayd.log',
    '.local/share/stepaway/app/stepaway_desktop',
    '.local/share/applications/$_id.desktop',
    '.local/share/icons/hicolor/scalable/apps/$_id.svg',
    '.config/keep/me.txt',
    '.local/share/other/keep.txt',
  ]) {
    File('${home.path}/$p')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
  }
  return home;
}

Future<UninstallController> _runAll(Uninstaller u, {bool data = true}) async {
  final c = UninstallController(
    u,
    removeData: data,
    minStepTime: Duration.zero,
  );
  await c.start();
  return c;
}

void main() {
  group('LinuxUninstaller (per-user install)', () {
    late Directory home;
    late _Calls calls;
    late LinuxUninstaller u;
    setUp(() {
      home = _linuxHome();
      calls = _Calls()..pgrepLeft = 2;
      u = LinuxUninstaller(
        executable: '${home.path}/.local/share/stepaway/app/stepaway_desktop',
        env: {'HOME': home.path},
        run: calls.run,
      );
    });
    tearDown(() => home.deleteSync(recursive: true));

    test('removes everything of StepAway and nothing else', () async {
      final c = await _runAll(u);
      expect(c.succeeded, isTrue);
      expect(c.steps.last, UninstallStep.appFiles);
      bool exists(String p) =>
          FileSystemEntity.typeSync('${home.path}/$p') !=
          FileSystemEntityType.notFound;
      expect(exists('.config/stepaway'), isFalse);
      expect(exists('.local/share/stepaway'), isFalse);
      expect(exists('.config/autostart/$_id.Daemon.desktop'), isFalse);
      expect(exists('.local/share/applications/$_id.desktop'), isFalse);
      expect(
        exists('.local/share/icons/hicolor/scalable/apps/$_id.svg'),
        isFalse,
      );
      expect(exists('.config/keep/me.txt'), isTrue);
      expect(exists('.local/share/other/keep.txt'), isTrue);
      expect(calls.log.first, 'pkill -x stepawayd');
      expect(
        calls.log.where((l) => l.startsWith('pgrep')).length,
        3,
      ); // waited for exit
    });

    test('keeps paired devices and settings when asked', () async {
      final c = await _runAll(u, data: false);
      expect(c.succeeded, isTrue);
      expect(c.steps.contains(UninstallStep.data), isFalse);
      expect(
        File('${home.path}/.config/stepaway/config.toml').existsSync(),
        isTrue,
      );
      expect(
        File('${home.path}/.local/share/stepaway/devices.json').existsSync(),
        isTrue,
      );
      expect(
        Directory('${home.path}/.local/share/stepaway/app').existsSync(),
        isFalse,
      );
    });

    test('the app folder is removed last, after the data', () {
      expect(u.plan(removeData: true), [
        UninstallStep.stopService,
        UninstallStep.autostart,
        UninstallStep.shortcuts,
        UninstallStep.data,
        UninstallStep.appFiles,
      ]);
    });
  });

  group('LinuxUninstaller (system package)', () {
    late Directory home;
    setUp(() => home = _linuxHome());
    tearDown(() => home.deleteSync(recursive: true));

    LinuxUninstaller make(_Calls calls) => LinuxUninstaller(
      executable: '/opt/stepaway/stepaway_desktop',
      env: {'HOME': home.path},
      run: calls.run,
    );

    test('asks for the password first and removes the package', () async {
      final calls = _Calls();
      final u = make(calls);
      expect(u.needsAdmin, isTrue);
      expect(u.plan(removeData: true).first, UninstallStep.appFiles);
      final c = await _runAll(u);
      expect(c.succeeded, isTrue);
      expect(calls.log.first, startsWith('pkexec sh -c'));
      expect(calls.log.first, contains('dpkg -r stepaway'));
      expect(calls.log.first, contains('rpm -e stepaway'));
    });

    test('cancelling the password prompt changes nothing', () async {
      final calls = _Calls()..pkexecExit = 126;
      final c = await _runAll(make(calls));
      expect(c.failed, isTrue);
      expect(c.status[UninstallStep.appFiles], StepStatus.failed);
      expect(calls.log.length, 1); // nothing else ran
      expect(
        File('${home.path}/.config/stepaway/config.toml').existsSync(),
        isTrue,
      );
    });
  });

  test('a development copy keeps its app files', () async {
    final home = _linuxHome();
    addTearDown(() => home.deleteSync(recursive: true));
    final u = LinuxUninstaller(
      executable:
          '/work/desktop/build/linux/x64/release/bundle/stepaway_desktop',
      env: {'HOME': home.path},
      run: _Calls().run,
    );
    expect(u.isDevelopmentCopy, isTrue);
    final c = await _runAll(u);
    expect(c.status[UninstallStep.appFiles], StepStatus.skipped);
    expect(
      File('${home.path}/.local/share/stepaway/app/stepaway_desktop')
          .existsSync(),
      isTrue,
    );
  });

  test('refuses to delete a folder that is too shallow to be StepAway\'s', () {
    final u = LinuxUninstaller(
      executable: '/x/stepaway_desktop',
      env: {'HOME': '/home/x', 'XDG_CONFIG_HOME': '/'},
      run: _Calls().run,
    );
    expect(u.run(UninstallStep.data), throwsA(isA<UninstallException>()));
  });

  test('an unset HOME fails safely', () {
    final u = LinuxUninstaller(executable: '/x/y', env: {}, run: _Calls().run);
    expect(u.run(UninstallStep.autostart), throwsA(isA<UninstallException>()));
  });

  group('WindowsUninstaller', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('sa-win');
      for (final p in [
        'AppData/StepAway/devices.json',
        'Prog/StepAway/stepaway_desktop.exe',
        'Prog/StepAway/stepawayd.exe',
        'AppData/Microsoft/Windows/Start Menu/Programs/StepAway.lnk',
      ]) {
        File('${root.path}/$p')
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
    });
    tearDown(() => root.deleteSync(recursive: true));

    test(
      'runs the same steps and schedules the app folder for deletion',
      () async {
        final calls = _Calls();
        final spawned = <String>[];
        final appData = '${root.path}/AppData';
        final u = WindowsUninstaller(
          executable: '${root.path}/Prog/StepAway/stepaway_desktop.exe',
          env: {'APPDATA': appData, 'TEMP': root.path},
          run: calls.run,
          spawn: (e, a) async => spawned.add('$e ${a.join(' ')}'),
        );
        expect(u.deletesAfterExit, isTrue);
        final c = await _runAll(u);
        expect(c.succeeded, isTrue);
        expect(calls.log, contains('taskkill /F /IM stepawayd.exe'));
        expect(
          calls.log.any(
            (l) => l.startsWith('reg delete') && l.contains('StepAway'),
          ),
          isTrue,
        );
        expect(Directory('$appData/StepAway').existsSync(), isFalse);
        expect(
          File('$appData/Microsoft/Windows/Start Menu/Programs/StepAway.lnk')
              .existsSync(),
          isFalse,
        );
        expect(spawned.single, startsWith('cmd /c '));
        final bat = File('${root.path}/stepaway-uninstall.bat')
            .readAsStringSync();
        expect(bat, contains('rmdir /s /q'));
        // the folder itself is still there: it is deleted after this app exits
        expect(Directory('${root.path}/Prog/StepAway').existsSync(), isTrue);
      },
    );

    test('same step order as Linux', () {
      final u = WindowsUninstaller(
        executable: r'C:\Prog\StepAway\stepaway_desktop.exe',
        env: {},
      );
      expect(u.plan(removeData: true), [
        UninstallStep.stopService,
        UninstallStep.autostart,
        UninstallStep.shortcuts,
        UninstallStep.data,
        UninstallStep.appFiles,
      ]);
    });

    test('a build folder is treated as a development copy', () {
      final u = WindowsUninstaller(
        executable: r'C:\src\desktop\build\windows\x64\runner\Release\stepaway_desktop.exe',
        env: {},
      );
      expect(u.isDevelopmentCopy, isTrue);
      expect(u.deletesAfterExit, isFalse);
    });
  });

  group('UninstallScreen', () {
    Widget host(UninstallController c, VoidCallback onClose) => MaterialApp(
      theme: StepAwayTheme.dark(),
      home: GlassBackground(
        child: UninstallScreen(controller: c, onClose: onClose),
      ),
    );

    testWidgets('animates through the steps and offers Close at the end', (
      t,
    ) async {
      t.view.physicalSize = const Size(1000, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var closed = false;
      final home = _linuxHome();
      addTearDown(() => home.deleteSync(recursive: true));
      final c = UninstallController(
        LinuxUninstaller(
          executable: '${home.path}/.local/share/stepaway/app/stepaway_desktop',
          env: {'HOME': home.path},
          run: _Calls().run,
        ),
        removeData: true,
        minStepTime: const Duration(milliseconds: 300),
      );
      await t.pumpWidget(host(c, () => closed = true));
      await t.pump();
      expect(find.text(S.uninstallingTitle), findsOneWidget);
      expect(find.byKey(const Key('uninstall-close')), findsNothing);

      // run the clock until the controller finishes (real file I/O needs runAsync)
      for (var i = 0; i < 40 && !c.finished; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(c.succeeded, isTrue);
      await t.pump(const Duration(seconds: 2));
      expect(find.text(S.uninstallDoneTitle), findsOneWidget);
      expect(
        find.text(S.uninstallStep(UninstallStep.stopService)),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('uninstall-close')));
      expect(closed, isTrue);
    });
  });
}
