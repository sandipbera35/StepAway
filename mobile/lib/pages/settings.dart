import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../controller.dart';
import '../strings.dart';
import '../widgets.dart';
import 'about.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.app, required this.theme});
  final AppController app;
  final ThemeController theme;

  Widget _card(
    BuildContext context,
    int index,
    String title,
    List<Widget> children,
  ) {
    return Reveal(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _permission(
    BuildContext context,
    IconData icon,
    String label,
    bool granted,
  ) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, a) =>
                ScaleTransition(scale: a, child: child),
            child: Row(
              key: ValueKey(granted),
              children: [
                Icon(
                  granted
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 20,
                  color: granted ? c.success : c.warning,
                ),
                const SizedBox(width: 6),
                Text(
                  granted ? S.allowed : S.notAllowed,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: granted ? c.success : c.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = app.status;
    return MaxWidth(
      maxWidth: 640,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, bottomNavPadding(context)),
        children: [
          const Reveal(
            child: TabHeader(title: S.tabSettings, subtitle: S.settingsSub),
          ),
          const SizedBox(height: 20),
          _card(context, 1, S.theme, [
            ListenableBuilder(
              listenable: theme,
              builder: (context, _) => GlassSegmented<ThemeMode>(
                value: theme.mode,
                onChanged: theme.setMode,
                options: const [
                  GlassSegment(
                    ThemeMode.system,
                    S.themeSystem,
                    Icons.brightness_auto_rounded,
                  ),
                  GlassSegment(
                    ThemeMode.light,
                    S.themeLight,
                    Icons.light_mode_rounded,
                  ),
                  GlassSegment(
                    ThemeMode.dark,
                    S.themeDark,
                    Icons.dark_mode_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ]),
          _card(context, 2, S.permissionsSection, [
            _permission(
              context,
              Icons.bluetooth_rounded,
              S.permBluetooth,
              s.permissionsGranted,
            ),
            _permission(
              context,
              Icons.notifications_rounded,
              S.permNotifications,
              s.permissionsGranted,
            ),
            if (!s.permissionsGranted)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton(
                  onPressed: app.requestPermissions,
                  child: const Text(S.grant),
                ),
              ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.battery_charging_full_rounded, size: 22),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    S.battery,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: app.native.batterySettings,
                  child: const Text(S.openSettings),
                ),
              ],
            ),
          ]),
          _card(context, 3, S.speedSection, [
            Text(S.speedHelp, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            GlassSegmented<String>(
              value: app.signalSpeed,
              onChanged: app.setSignalSpeed,
              options: const [
                GlassSegment(
                  'low_power',
                  S.speedSaver,
                  Icons.battery_saver_rounded,
                ),
                GlassSegment(
                  'balanced',
                  S.speedBalanced,
                  Icons.balance_rounded,
                ),
                GlassSegment('low_latency', S.speedFast, Icons.bolt_rounded),
              ],
            ),
            const SizedBox(height: 6),
          ]),
          _card(context, 4, S.about, [
            const Text(S.aboutBody),
            const SizedBox(height: 10),
            Text(
              'Version $kAppVersion',
              key: const Key('settings-version'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('open-about'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AboutPage(native: app.native),
                      ),
                    ),
                    icon: const Icon(Icons.info_outline_rounded),
                    label: const Text(S.about),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('open-privacy'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PrivacyPage(native: app.native),
                      ),
                    ),
                    icon: const Icon(Icons.privacy_tip_outlined),
                    label: const Text(S.privacyPolicy),
                  ),
                ),
              ],
            ),
          ]),
        ],
      ),
    );
  }
}
