import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../native.dart';
import '../strings.dart';

Future<void> _open(BuildContext context, Native native, String url) async {
  var ok = false;
  try {
    ok = await native.openUrl(url);
  } catch (_) {
    // fall back to copying the link
  }
  if (!ok && context.mounted) await copyLink(context, url);
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

Widget _body(BuildContext context, String title, Widget child) {
  return Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(backgroundColor: Colors.transparent, title: Text(title)),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

/// About page: version, links, license. Opened from Settings.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.native});
  final Native native;

  @override
  Widget build(BuildContext context) {
    return _body(
      context,
      S.about,
      AboutContent(
        onOpenLink: (u) => _open(context, native, u),
        onShowPrivacy: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PrivacyPage(native: native)),
        ),
        onShowLicenses: () => _showLicenses(context),
      ),
    );
  }
}

/// The full privacy policy.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key, required this.native});
  final Native native;

  @override
  Widget build(BuildContext context) {
    return _body(
      context,
      S.privacyPolicy,
      PrivacyContent(onOpenLink: (u) => _open(context, native, u)),
    );
  }
}
