import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_desktop/service.dart';

void main() {
  test('daemon is looked up next to the app, then in bin/', () {
    final c = daemonCandidates(
      '/opt/stepaway/stepaway_desktop',
      separator: '/',
    );
    expect(c, ['/opt/stepaway/stepawayd', '/opt/stepaway/bin/stepawayd']);
  });

  test('autostart entry quotes paths with spaces and hides itself', () {
    final e = autostartDesktopEntry('/home/u/My Apps/stepawayd');
    expect(e, contains('Exec="/home/u/My Apps/stepawayd"'));
    expect(e, contains('NoDisplay=true'));
    expect(e, startsWith('[Desktop Entry]'));
  });

  test('autostart is written once on first run and can be switched off', () async {
    if (Platform.isWindows) return; // registry based on Windows
    final dir = Directory.systemTemp.createTempSync('sa-svc');
    addTearDown(() => dir.deleteSync(recursive: true));
    final app = Directory('${dir.path}/app')..createSync();
    File('${app.path}/stepaway_desktop').writeAsStringSync('');
    File('${app.path}/stepawayd').writeAsStringSync('#!/bin/sh\n');
    final svc = SystemServiceManager(
      executable: '${app.path}/stepaway_desktop',
      env: {'HOME': dir.path, 'XDG_CONFIG_HOME': '${dir.path}/cfg'},
    );
    expect(await svc.autostartEnabled(), isFalse);
    await svc.ensureDefaultAutostart();
    expect(await svc.autostartEnabled(), isTrue);
    expect(
      File(
        '${dir.path}/cfg/autostart/io.github.sandipbera35.StepAway.Daemon.desktop',
      ).readAsStringSync(),
      contains('${app.path}/stepawayd'),
    );
    await svc.setAutostart(false);
    expect(await svc.autostartEnabled(), isFalse);
    await svc
        .ensureDefaultAutostart(); // the user opted out: must not come back
    expect(await svc.autostartEnabled(), isFalse);
  });
}
