import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../ipc/rpc_client.dart';
import '../model.dart';
import '../pickers.dart';
import '../strings.dart';
import '../widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.model, required this.theme});
  final DaemonModel model;
  final ThemeController theme;

  Future<void> _set(BuildContext context, Map<String, dynamic> patch) async {
    try {
      await model.setConfig(patch);
    } on RpcException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _slider(
    BuildContext context,
    String label,
    String key,
    double min,
    double max,
    int div,
    String unit,
  ) {
    final v = ((model.config[key] as num?)?.toDouble() ?? min).clamp(min, max);
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: c.glassFillStrong,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)} $unit',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Slider(
            key: Key('slider-$key'),
            value: v,
            min: min,
            max: max,
            divisions: div,
            onChanged: model.connected ? (x) => model.config[key] = x : null,
            onChangeEnd: model.connected
                ? (x) => _set(context, {key: unit == 's' ? x.round() : x})
                : null,
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    int index,
    String title,
    List<Widget> children,
  ) {
    return Reveal(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
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

  Widget _chips(
    BuildContext context, {
    required String empty,
    required List<Widget> chips,
  }) {
    final c = AppColors.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (chips.isEmpty) Text(empty, style: TextStyle(color: c.textMuted)),
          ...chips,
        ],
      ),
    );
  }

  Widget _appsBlock(BuildContext context) {
    final c = AppColors.of(context);
    if (!model.capApps) {
      return Text(
        S.appsUnavailable,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final apps = model.lockCloseApps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.appsSubtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: c.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                S.appsWarning,
                style: TextStyle(fontSize: 12, color: c.warning),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _chips(
          context,
          empty: S.noApps,
          chips: [
            for (final a in apps)
              InputChip(
                key: Key('app-${a.id}'),
                avatar: const Icon(Icons.apps_rounded, size: 18),
                label: Text(a.name),
                onDeleted: model.connected
                    ? () => model.removeLockApp(a.id)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const Key('add-app'),
          onPressed: model.connected
              ? () async {
                  final app = await showDialog<AppItem>(
                    context: context,
                    builder: (_) => AppPickerDialog(model: model),
                  );
                  if (app != null && context.mounted) {
                    try {
                      await model.addLockApp(app);
                    } on RpcException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  }
                }
              : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text(S.addApp),
        ),
        SwitchListTile(
          key: const Key('reopen-apps-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            S.reopenAppsTitle,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          value: model.unlockReopenApps,
          onChanged: model.connected && apps.isNotEmpty
              ? (v) => _set(context, {'unlock_reopen_apps': v})
              : null,
        ),
      ],
    );
  }

  Widget _servicesBlock(BuildContext context) {
    if (!model.capServices) {
      return Text(
        S.servicesUnavailable,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final units = model.lockStopServices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.servicesSubtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 14),
        _chips(
          context,
          empty: S.noServices,
          chips: [
            for (final u in units)
              InputChip(
                key: Key('service-$u'),
                avatar: const Icon(Icons.stop_circle_outlined, size: 18),
                label: Text(u),
                onDeleted: model.connected
                    ? () => model.removeLockService(u)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const Key('add-service'),
          onPressed: model.connected
              ? () async {
                  final unit = await showDialog<String>(
                    context: context,
                    builder: (_) => ServicePickerDialog(model: model),
                  );
                  if (unit != null && context.mounted) {
                    await _set(context, {
                      'lock_stop_services': [...units, unit],
                    });
                  }
                }
              : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text(S.addService),
        ),
        SwitchListTile(
          key: const Key('restart-services-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            S.restartServicesTitle,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          value: model.unlockStartServices,
          onChanged: model.connected && units.isNotEmpty
              ? (v) => _set(context, {'unlock_start_services': v})
              : null,
        ),
      ],
    );
  }

  Future<void> _toggleUnlock(BuildContext context, bool on) async {
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text(S.unlockWarningTitle),
          content: const Text(S.unlockWarningBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text(S.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text(S.turnOn),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (context.mounted) await _set(context, {'unlock_enabled': on});
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const PageHeader(title: S.settings, subtitle: S.settingsSubtitle),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                _section(context, 0, S.appearance, [
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
                  const SizedBox(height: 8),
                ]),
                _section(context, 1, S.multiDeviceTitle, [
                  GlassSegmented<String>(
                    value: model.presenceRule,
                    onChanged: model.connected
                        ? (v) => _set(context, {'presence_rule': v})
                        : (_) {},
                    options: const [
                      GlassSegment('any', S.ruleAny, Icons.looks_one_rounded),
                      GlassSegment('all', S.ruleAll, Icons.groups_rounded),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      model.presenceRule == 'all'
                          ? S.ruleAllHelp
                          : S.ruleAnyHelp,
                      key: ValueKey(model.presenceRule),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                ]),
                _section(context, 2, S.distanceSection, [
                  _slider(
                    context,
                    S.lockDistance,
                    'lock_distance_m',
                    1,
                    10,
                    18,
                    'm',
                  ),
                  _slider(
                    context,
                    S.returnDistance,
                    'return_distance_m',
                    0.5,
                    8,
                    15,
                    'm',
                  ),
                  _slider(context, S.lockDelay, 'lock_grace_s', 0, 60, 60, 's'),
                  _slider(
                    context,
                    S.returnDelay,
                    'return_grace_s',
                    0,
                    30,
                    30,
                    's',
                  ),
                ]),
                _section(context, 3, S.lockActions, [
                  SwitchListTile(
                    key: const Key('pause-media-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      S.pauseMediaTitle,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      model.capMedia
                          ? S.pauseMediaSubtitle
                          : S.mediaUnavailable,
                    ),
                    value: model.lockPauseMedia,
                    onChanged: model.connected && model.capMedia
                        ? (v) => _set(context, {'lock_pause_media': v})
                        : null,
                  ),
                  SwitchListTile(
                    key: const Key('resume-media-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      S.resumeMediaTitle,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(S.resumeMediaSubtitle),
                    value: model.unlockResumeMedia,
                    onChanged:
                        model.connected &&
                            model.capMedia &&
                            model.lockPauseMedia
                        ? (v) => _set(context, {'unlock_resume_media': v})
                        : null,
                  ),
                ]),
                _section(context, 4, S.appsSection, [_appsBlock(context)]),
                _section(context, 5, S.servicesSection, [
                  _servicesBlock(context),
                ]),
                _section(context, 6, S.behaviorSection, [
                  SwitchListTile(
                    key: const Key('beacon-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      S.beaconTitle,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      model.capBeacon ? S.beaconSubtitle : S.beaconUnavailable,
                    ),
                    value: model.beaconEnabled,
                    onChanged: model.connected
                        ? (v) => _set(context, {'beacon_enabled': v})
                        : null,
                  ),
                  SwitchListTile(
                    key: const Key('autostart-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      S.autostartTitle,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(S.autostartSubtitle),
                    value: model.autostart,
                    onChanged: model.service == null
                        ? null
                        : model.setAutostart,
                  ),
                  SwitchListTile(
                    key: const Key('unlock-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      S.unlockTitle,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(S.unlockSubtitle),
                    value: model.unlockEnabled,
                    onChanged: model.connected
                        ? (on) => _toggleUnlock(context, on)
                        : null,
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
