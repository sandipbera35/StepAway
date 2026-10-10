import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

String _pubspecVersion(String path) {
  final m = RegExp(
    r'^version:\s*([0-9.]+)',
    multiLine: true,
  ).firstMatch(File(path).readAsStringSync());
  return m!.group(1)!;
}

void main() {
  test('the version shown in the apps matches every pubspec', () {
    expect(_pubspecVersion('../desktop/pubspec.yaml'), kAppVersion);
  });

  test(
    'the build number follows major*10000+minor*100+patch and the pubspecs',
    () {
      final p = kAppVersion.split('.').map(int.parse).toList();
      expect(kBuildNumber, p[0] * 10000 + p[1] * 100 + p[2]);
      for (final f in ['../desktop/pubspec.yaml']) {
        expect(
          RegExp(
            r'^version:\s*[0-9.]+\+(\d+)',
            multiLine: true,
          ).firstMatch(File(f).readAsStringSync())!.group(1),
          '$kBuildNumber',
          reason: f,
        );
      }
    },
  );

  test('the privacy policy covers what the stores and laws require', () {
    final text = [
      privacySummary,
      for (final s in privacySections) ...[s.title, ...s.paragraphs],
    ].join('\n').toLowerCase();
    for (final needle in [
      'does not collect',
      'no internet',
      'children',
      'delete',
      'bluetooth',
      'camera',
      'keystore',
      'third',
      'changes to this policy',
      'gdpr',
    ]) {
      expect(text, contains(needle), reason: 'policy should mention "$needle"');
    }
    for (final s in privacySections) {
      expect(s.paragraphs, isNotEmpty, reason: s.title);
    }
  });

  test('the repository PRIVACY.md is generated from the in-app text', () {
    final md = File('../PRIVACY.md').readAsStringSync();
    expect(md, contains(privacySummary));
    for (final s in privacySections) {
      expect(md, contains(s.title));
    }
    expect(md, contains(kPrivacyUpdated));
  });

  testWidgets('About can show other license terms and hide the source link', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(800, 1400));
    await t.pumpWidget(
      MaterialApp(
        theme: StepAwayTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AboutContent(
              onOpenLink: (_) async {},
              onShowPrivacy: () {},
              onShowLicenses: () {},
              licenseName: 'Proprietary',
              warrantyNotice: 'All rights reserved.',
              trademarkNotice: null,
              licenseUrl: null,
              sourceUrl: null,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Proprietary'), findsOneWidget);
    expect(find.text('All rights reserved.'), findsOneWidget);
    expect(find.textContaining('WITHOUT ANY WARRANTY'), findsNothing);
    expect(find.text('Source code'), findsNothing);
    expect(find.text('Read the full license'), findsNothing);
    expect(find.text('Name and logo policy'), findsNothing);
  });

  testWidgets('About shows version, license and the links', (t) async {
    final opened = <String>[];
    var privacy = 0;
    var licenses = 0;
    await t.binding.setSurfaceSize(const Size(800, 1400));
    await t.pumpWidget(
      MaterialApp(
        theme: StepAwayTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AboutContent(
              onOpenLink: (u) async => opened.add(u),
              onShowPrivacy: () => privacy++,
              onShowLicenses: () => licenses++,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Version $kAppVersion'), findsOneWidget);
    expect(find.text('$kBuildNumber'), findsOneWidget);
    expect(find.textContaining('WITHOUT ANY WARRANTY'), findsOneWidget);
    await t.tap(find.text('Privacy policy'));
    await t.tap(find.text('Open-source licenses'));
    await t.tap(find.text('Source code'));
    expect(privacy, 1);
    expect(licenses, 1);
    expect(opened, [kHomepageUrl]);
  });
}
