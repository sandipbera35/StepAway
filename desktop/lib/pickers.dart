import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import 'model.dart';
import 'strings.dart';

/// Looks like a service name we would accept (mirrors the daemon's rules; the daemon re-checks).
String? serviceNameProblem(String name, {bool? windows}) {
  final n = name.trim();
  final win = windows ?? Platform.isWindows;
  if (win) {
    if (n.isEmpty ||
        n.length > 256 ||
        n.startsWith('-') ||
        n.startsWith(' ') ||
        n.endsWith(' ') ||
        n.contains(RegExp(r'[^A-Za-z0-9_.$@ -]'))) {
      return S.invalidServiceWindows;
    }
    const core = [
      'rpcss',
      'rpceptmapper',
      'dcomlaunch',
      'lsm',
      'samss',
      'winmgmt',
      'eventlog',
      'bfe',
      'mpssvc',
      'cryptsvc',
      'dhcp',
      'dnscache',
      'nsi',
      'plugplay',
      'power',
      'profsvc',
      'usermanager',
      'staterepository',
      'trustedinstaller',
      'windefend',
      'wuauserv',
      'themes',
      'audiosrv',
      'audioendpointbuilder',
      'lanmanserver',
      'lanmanworkstation',
      'netlogon',
      'schedule',
      'sens',
      'shellhwdetection',
      'wlansvc',
      'netprofm',
      'nlasvc',
      'termservice',
      'wpnservice',
      'gpsvc',
      'sysmain',
      'tokenbroker',
      'brokerinfrastructure',
      'keyiso',
      'stepaway',
      'stepawayd',
    ];
    final lower = n.toLowerCase();
    return core.contains(lower) || core.contains(lower.split('_').first)
        ? S.protectedService
        : null;
  }
  if (!n.endsWith('.service') ||
      n.length <= '.service'.length ||
      n.startsWith('-') ||
      n.contains(RegExp(r'[^A-Za-z0-9._:@\\-]'))) {
    return S.invalidService;
  }
  final lower = n.toLowerCase();
  const protectedPrefixes = [
    'dbus',
    'systemd',
    'gnome-shell',
    'gnome-session',
    'plasma',
    'kwin',
    'org.gnome.shell',
    'org.kde',
    'gdm',
    'sddm',
    'lightdm',
    'graphical-session',
    'xdg-desktop-portal',
    'pipewire',
    'wireplumber',
    'stepawayd',
  ];
  return protectedPrefixes.any(lower.startsWith) ? S.protectedService : null;
}

/// Searchable list of the applications installed on this computer (running ones first).
class AppPickerDialog extends StatefulWidget {
  const AppPickerDialog({super.key, required this.model});
  final DaemonModel model;

  @override
  State<AppPickerDialog> createState() => _AppPickerDialogState();
}

class _AppPickerDialogState extends State<AppPickerDialog> {
  final _ctl = TextEditingController();
  late final Future<List<AppItem>> _apps = widget.model.availableApps();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final already = widget.model.lockCloseApps.map((a) => a.id).toSet();
    return AlertDialog(
      title: const Text(S.pickApp),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('app-field'),
              controller: _ctl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: S.searchApps,
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<AppItem>>(
                future: _apps,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final q = _ctl.text.trim().toLowerCase();
                  final list = [
                    for (final a in snap.data ?? const <AppItem>[])
                      if (!already.contains(a.id) &&
                          (q.isEmpty ||
                              a.name.toLowerCase().contains(q) ||
                              a.id.toLowerCase().contains(q)))
                        a,
                  ];
                  if (list.isEmpty) {
                    return Center(
                      child: Text(
                        S.noAppsFound,
                        style: TextStyle(color: c.textMuted),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final a = list[i];
                      return ListTile(
                        key: Key('pick-app-${a.id}'),
                        dense: true,
                        leading: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: c.accentGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            a.name.isEmpty
                                ? '?'
                                : a.name.characters.first.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(a.name),
                        trailing: a.running
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StatusDot(color: c.success, size: 8),
                                  const SizedBox(width: 6),
                                  Text(
                                    S.runningNow,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: c.success,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            : null,
                        onTap: () => Navigator.pop(context, a),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(S.cancel),
        ),
      ],
    );
  }
}

/// Searchable list of running services, with manual entry for ones that are not running.
class ServicePickerDialog extends StatefulWidget {
  const ServicePickerDialog({super.key, required this.model});
  final DaemonModel model;

  @override
  State<ServicePickerDialog> createState() => _ServicePickerDialogState();
}

class _ServicePickerDialogState extends State<ServicePickerDialog> {
  final _ctl = TextEditingController();
  late final Future<List<ServiceItem>> _running = widget.model
      .availableServices();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final problem = _ctl.text.isEmpty ? null : serviceNameProblem(_ctl.text);
    final already = widget.model.lockStopServices;
    return AlertDialog(
      title: const Text(S.pickService),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              key: const Key('service-field'),
              controller: _ctl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_ctl.text.isNotEmpty && problem == null) {
                  Navigator.pop(context, _ctl.text.trim());
                }
              },
              decoration: InputDecoration(
                hintText: Platform.isWindows
                    ? S.searchServicesWindows
                    : S.searchServices,
                errorText: problem,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<ServiceItem>>(
                future: _running,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final q = _ctl.text.trim().toLowerCase();
                  final list = [
                    for (final u in snap.data ?? const <ServiceItem>[])
                      if (!already.contains(u.id) &&
                          serviceNameProblem(u.id) == null &&
                          (q.isEmpty ||
                              u.id.toLowerCase().contains(q) ||
                              u.name.toLowerCase().contains(q)))
                        u,
                  ];
                  if (list.isEmpty) {
                    return Center(
                      child: Text(
                        S.noRunning,
                        style: TextStyle(color: c.textMuted),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) => ListTile(
                      key: Key('pick-${list[i].id}'),
                      dense: true,
                      leading: const Icon(Icons.dns_outlined),
                      title: Text(list[i].name),
                      subtitle: list[i].name == list[i].id
                          ? null
                          : Text(list[i].id),
                      onTap: () => Navigator.pop(context, list[i].id),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(S.cancel),
        ),
        FilledButton(
          key: const Key('service-add-manual'),
          onPressed: _ctl.text.isEmpty || problem != null
              ? null
              : () => Navigator.pop(context, _ctl.text.trim()),
          child: const Text(S.addManually),
        ),
      ],
    );
  }
}
