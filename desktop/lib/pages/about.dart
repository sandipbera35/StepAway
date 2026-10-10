import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../model.dart';
import '../open_link.dart';
import '../strings.dart';
import '../widgets.dart';

Future<void> _open(BuildContext context, String url) async {
  if (await openLink(url)) return;
  if (context.mounted) await copyLink(context, url);
}

void _showLicenses(BuildContext context) {
  showLicensePage(
    context: context,
    applicationName: kAppName,
    applicationVersion: kAppVersion,
    applicationIcon: const Padding(
      padding: EdgeInsets.all(12),
      child: StepAwayLogo(size: 56),
    ),
    applicationLegalese: kCopyright,
  );
}

/// The About tab: version, links, license and the privacy policy.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.model});
  final DaemonModel model;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const PageHeader(title: S.about, subtitle: S.aboutSubtitle),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: AboutContent(
              details: [
                (
                  S.serviceVersion,
                  model.connected
                      ? (model.daemonVersion ?? S.serviceOlder)
                      : S.serviceNotRunning,
                ),
              ],
              onOpenLink: (u) => _open(context, u),
              onShowPrivacy: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PrivacyPage()),
              ),
              onShowLicenses: () => _showLicenses(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// The full privacy policy, reachable from the About tab.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(S.privacyPolicy),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: PrivacyContent(onOpenLink: (u) => _open(context, u)),
            ),
          ),
        ],
      ),
    );
  }
}
