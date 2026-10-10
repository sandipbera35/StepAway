import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';
import 'glass.dart';
import 'logo.dart';
import 'motion.dart';

/// App facts shown on the About page. Keep [kAppVersion] equal to the pubspec version
/// (a test checks this).
const kAppName = 'StepAway';
const kAppVersion = '0.1.2';

/// Build number: major*10000 + minor*100 + patch. Also the Android versionCode.
const kBuildNumber = 102;
const kLicenseName = 'GNU General Public License v3.0 or later';
const kCopyright = 'Copyright © 2026 sandipbera35 and contributors';
const kHomepageUrl = 'https://github.com/sandipbera35/StepAway';
const kIssuesUrl = 'https://github.com/sandipbera35/StepAway/issues';
const kSecurityUrl = 'https://github.com/sandipbera35/StepAway/security/policy';
const kPrivacyUrl =
    'https://github.com/sandipbera35/StepAway/blob/main/PRIVACY.md';
const kLicenseUrl = 'https://www.gnu.org/licenses/gpl-3.0.html';
const kPrivacyUpdated = '10 October 2026';

/// Adds licenses Flutter cannot discover by itself to the "Open-source licenses" page.
/// [assets] maps a display name (the package list heading) to a bundled text asset. The Inter
/// font's license from this package is always added.
void registerExtraLicenses(Map<String, String> assets) {
  final all = {
    'Inter font': 'packages/stepaway_ui/assets/fonts/OFL.txt',
    ...assets,
  };
  LicenseRegistry.addLicense(() async* {
    for (final e in all.entries) {
      try {
        final text = await rootBundle.loadString(e.value);
        yield LicenseEntryWithLineBreaks([e.key], text);
      } catch (_) {
        // a missing asset must never break the licenses page
      }
    }
  });
}

/// Opens [url] in the system browser, or copies it when that is not possible.
typedef OpenLink = Future<void> Function(String url);

class LegalSection {
  const LegalSection(this.title, this.paragraphs);
  final String title;
  final List<String> paragraphs;
}

/// The privacy policy. It describes what the code actually does; `PRIVACY.md` in the repository
/// is generated from this text by `tools/gen-privacy-md.py`, so the two cannot drift apart.
const privacySummary =
    'StepAway does not collect, send, sell or share any personal data. It has no accounts, no '
    'ads, no analytics, no crash reporting and makes no internet connections. Everything it '
    'needs stays on your own devices.';

const privacySections = <LegalSection>[
  LegalSection('Who is responsible', [
    'StepAway is free and open-source software published by sandipbera35 (an individual) and '
        'contributors. Because the developer never receives any of your data, the developer '
        'does not act as a processor or controller of your personal data. Questions can be '
        'asked in the issue tracker: $kIssuesUrl',
  ]),
  LegalSection('What StepAway stores on your computer', [
    'Pairing records: for each paired device a numeric ID, the name you gave it, a secret key '
        'shared with that device, and (only if you choose a "presence only" device) its '
        'Bluetooth address. The file is readable only by your user account.',
    'Settings: distances, delays and the lists of apps and services you chose to close or stop '
        'when locking.',
    'A diagnostic log of what the service did ("locking the session", "state changed"). It '
        'never contains secret keys or tokens.',
    'The list of apps and services on your computer is read locally only to let you pick '
        'which ones to close or stop. It is not saved beyond your choices and never leaves '
        'the computer.',
  ]),
  LegalSection('What StepAway stores on your phone', [
    'Pairing records: the name of your computer and the shared secret key. The key is '
        'encrypted with a key held in the Android Keystore.',
    'Small preferences (theme, the speed setting, calibration, onboarding done).',
    'Android backup is switched off for StepAway, so none of this is copied to a cloud backup.',
  ]),
  LegalSection('Bluetooth', [
    'Your phone or watch broadcasts a short Bluetooth Low Energy signal containing StepAway\'s '
        'service identifier and a signed token that changes every 10 seconds. The token '
        'contains no name, location or account information and cannot be used without the '
        'secret key. Anyone nearby with a Bluetooth scanner can see that a StepAway signal is '
        'present, and its signal strength, but cannot tell who you are.',
    'Your computer scans for these signals to estimate distance. It briefly sees the names '
        'and addresses of other nearby Bluetooth devices. These are held in memory for up to '
        '20 seconds so you can pick a device in the list, are never written to disk unless '
        'you choose one, and are never sent anywhere.',
    'The phone app scans for your computer\'s signal only while the app is open on its Home '
        'screen, to show the distance. It does not use Bluetooth to find your location.',
  ]),
  LegalSection('Android permissions', [
    'Bluetooth (advertise, scan, connect): to send and receive the signals above.',
    'Camera: only to scan the pairing QR code. Pictures are never saved or sent.',
    'Notifications and foreground service: to show the notice that protection is running and '
        'keep it running with the screen off.',
    'Run at start-up: to resume protection after the phone restarts.',
    'Location (Android 11 and older only): the old Android Bluetooth scan rules require it. '
        'StepAway does not read your location.',
    'The app does not request the Internet permission.',
  ]),
  LegalSection('Sharing and third parties', [
    'None. StepAway contains no advertising, analytics or tracking code, and no code from '
        'Google Play services or similar proprietary SDKs. The only open-source libraries it '
        'uses are listed under "Open-source licenses" on the About page.',
    'If you download StepAway from a website or app store, that store has its own privacy '
        'policy for the download itself.',
  ]),
  LegalSection('Keeping and deleting your data', [
    'You are in control. To stop a device from locking your computer, remove it in the '
        'Devices page (computer) or Computers page (phone).',
    'To erase everything: use Settings → Uninstall on the computer, which can delete all '
        'pairing records, settings and logs, or uninstall the app from your phone. If you '
        'delete files by hand, they are in ~/.config/stepaway and ~/.local/share/stepaway on '
        'Linux, and %APPDATA%\\StepAway on Windows.',
  ]),
  LegalSection('Security', [
    'Tokens are signed with a secret key using HMAC-SHA-256. Secret keys are never logged. '
        'When anything is uncertain, StepAway keeps the computer locked. Distance from '
        'Bluetooth signal strength is only an estimate, and no proximity lock can fully '
        'prevent someone who relays your phone\'s signal. Do not rely on StepAway as your '
        'only protection. Report vulnerabilities privately: $kSecurityUrl',
  ]),
  LegalSection('Children', [
    'StepAway is not directed at children and does not knowingly collect information from '
        'anyone, including children.',
  ]),
  LegalSection('Your rights', [
    'Because the developer holds no data about you, there is nothing to access, correct or '
        'delete on the developer\'s side. Under laws such as the GDPR and CCPA you may ask, but '
        'the answer will be that no personal data is held. All data StepAway keeps is on your '
        'own devices and you can inspect or delete it at any time.',
  ]),
  LegalSection('Changes to this policy', [
    'If StepAway ever changes what it does with data, this policy will be updated before the '
        'change ships, and the date above will change. The full history is public: '
        '$kPrivacyUrl',
  ]),
];

/// No-warranty notice shown on the About page (a plain-language summary of GPL sections 15-16).
const kWarrantyNotice =
    'StepAway is free software: you can redistribute it and/or modify it under the terms of the '
    'GNU General Public License as published by the Free Software Foundation, either version 3 '
    'of the License, or (at your option) any later version. It is distributed in the hope that '
    'it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of '
    'MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.';

const kProximityNotice =
    'Distance is estimated from Bluetooth signal strength and can be wrong. StepAway is a '
    'convenience, not a security guarantee: do not rely on it as your only protection.';

/// Copies [url] when the platform cannot open it.
Future<void> copyLink(BuildContext context, String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Link copied: $url')));
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: c.textMuted)),
          ),
          SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

/// The About page body, shared by the desktop and Android apps.
class AboutContent extends StatelessWidget {
  const AboutContent({
    super.key,
    required this.onOpenLink,
    required this.onShowPrivacy,
    required this.onShowLicenses,
    this.details = const [],
  });

  /// Extra "label, value" rows for the version card (build number, service version, ...).
  final List<(String, String)> details;
  final OpenLink onOpenLink;
  final VoidCallback onShowPrivacy;
  final VoidCallback onShowLicenses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Center(child: StepAwayLogo(size: 84)),
              const SizedBox(height: 16),
              Text(
                kAppName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version $kAppVersion',
                key: const Key('about-version'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: 12),
              Text(
                'Locks your computer when your phone moves away.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Reveal(
          index: 1,
          child: GlassCard(
            key: const Key('about-details'),
            child: Column(
              children: [
                _DetailRow('Version', kAppVersion),
                _DetailRow('Build', '$kBuildNumber'),
                for (final d in details) _DetailRow(d.$1, d.$2),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Reveal(
          index: 1,
          child: GlassCard(
            child: Column(
              children: [
                _LinkRow(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy policy',
                  subtitle: 'No data collected, no internet access',
                  onTap: onShowPrivacy,
                ),
                _LinkRow(
                  icon: Icons.article_outlined,
                  label: 'Open-source licenses',
                  onTap: onShowLicenses,
                ),
                _LinkRow(
                  icon: Icons.code_rounded,
                  label: 'Source code',
                  subtitle: kHomepageUrl,
                  onTap: () => onOpenLink(kHomepageUrl),
                ),
                _LinkRow(
                  icon: Icons.bug_report_outlined,
                  label: 'Report a problem',
                  onTap: () => onOpenLink(kIssuesUrl),
                ),
                _LinkRow(
                  icon: Icons.shield_outlined,
                  label: 'Security policy',
                  onTap: () => onOpenLink(kSecurityUrl),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Reveal(
          index: 2,
          child: GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('License', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(kLicenseName),
                const SizedBox(height: 6),
                Text(kCopyright, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                Text(kWarrantyNotice, style: theme.textTheme.bodySmall),
                TextButton(
                  onPressed: () => onOpenLink(kLicenseUrl),
                  child: const Text('Read the full license'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Reveal(
          index: 3,
          child: GlassCard(
            child: Text(kProximityNotice, style: theme.textTheme.bodySmall),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The privacy policy body, shared by the desktop and Android apps.
class PrivacyContent extends StatelessWidget {
  const PrivacyContent({super.key, required this.onOpenLink});
  final OpenLink onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          child: GlassCard(
            strong: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_rounded, color: c.success, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    privacySummary,
                    key: const Key('privacy-summary'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Last updated: $kPrivacyUpdated',
            style: theme.textTheme.bodySmall,
          ),
        ),
        for (var i = 0; i < privacySections.length; i++)
          Reveal(
            index: i + 1,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}. ${privacySections[i].title}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final p in privacySections[i].paragraphs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SelectableText(p),
                      ),
                  ],
                ),
              ),
            ),
          ),
        TextButton.icon(
          onPressed: () => onOpenLink(kPrivacyUrl),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('Open the online version'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
