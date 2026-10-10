// Real-process check of the uninstaller against a real installation. Skipped unless
// SA_E2E_EXE points at the installed stepaway_desktop. pkexec needs a desktop password dialog,
// so when SA_E2E_SUDO_PW is set the test runs the same command through `sudo -S` instead.
//   SA_E2E_EXE=/opt/stepaway/stepaway_desktop SA_E2E_SUDO_PW=... flutter test test/e2e_uninstall_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_desktop/uninstall.dart';

Future<ProcessResult> _run(String exe, List<String> args) async {
  final pw = Platform.environment['SA_E2E_SUDO_PW'];
  if (exe == 'pkexec' && pw != null) {
    final p = await Process.start('sudo', ['-S', ...args]);
    p.stdin.writeln(pw);
    await p.stdin.close();
    final out = await p.stdout.transform(utf8.decoder).join();
    final err = await p.stderr.transform(utf8.decoder).join();
    return ProcessResult(p.pid, await p.exitCode, out, err);
  }
  return Process.run(exe, args);
}

void main() {
  final exe = Platform.environment['SA_E2E_EXE'];
  test(
    'uninstalls a real installation',
    () async {
      final u = LinuxUninstaller(executable: exe, run: _run);
      final c = UninstallController(
        u,
        removeData: true,
        minStepTime: Duration.zero,
      );
      await c.start();
      expect(c.error, isNull);
      expect(c.succeeded, isTrue);
      for (final s in c.steps) {
        // ignore: avoid_print
        print('${s.name}: ${c.status[s]!.name}');
      }
    },
    skip: exe == null ? 'set SA_E2E_EXE' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
