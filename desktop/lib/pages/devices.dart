import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import '../ipc/rpc_client.dart';
import '../model.dart';
import '../strings.dart';
import '../widgets.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key, required this.model});
  final DaemonModel model;

  Future<void> _pairWithApp(BuildContext context, DeviceKind kind) async {
    try {
      await model.startPairing(kind.label, kind: kind);
    } on RpcException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PairingDialog(model: model),
    );
    await model.endPairing();
  }

  Future<void> _add(BuildContext context) async {
    final choice = await showDialog<_AddChoice>(
      context: context,
      builder: (_) => const AddDeviceDialog(),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _AddChoice.phone:
        await _pairWithApp(context, DeviceKind.phone);
      case _AddChoice.tablet:
        await _pairWithApp(context, DeviceKind.tablet);
      case _AddChoice.watchApp:
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => CodePairingDialog(model: model),
        );
        await model.endPairing();
      case _AddChoice.watchBluetooth:
        await showDialog<void>(
          context: context,
          builder: (_) =>
              NearbyPickerDialog(model: model, kind: DeviceKind.watch),
        );
      case _AddChoice.other:
        await showDialog<void>(
          context: context,
          builder: (_) =>
              NearbyPickerDialog(model: model, kind: DeviceKind.other),
        );
    }
  }

  Future<void> _rename(BuildContext context, PairedDevice d) async {
    final ctl = TextEditingController(text: d.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(S.rename),
        content: TextField(
          key: const Key('rename-field'),
          controller: ctl,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctl.text),
            child: const Text(S.done),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await model.updateDevice(d.id, name: name);
    }
  }

  Future<void> _retype(BuildContext context, PairedDevice d) async {
    final kind = await showDialog<DeviceKind>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text(S.changeType),
        children: [
          for (final k in DeviceKind.values)
            SimpleDialogOption(
              key: Key('kind-${k.id}'),
              onPressed: () => Navigator.pop(c, k),
              child: Row(
                children: [
                  Icon(k.icon),
                  const SizedBox(width: 12),
                  Text(k.label),
                ],
              ),
            ),
        ],
      ),
    );
    if (kind != null) await model.updateDevice(d.id, kind: kind);
  }

  Future<void> _remove(BuildContext context, PairedDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(S.removeTitle),
        content: const Text(S.removeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text(S.remove),
          ),
        ],
      ),
    );
    if (ok == true) await model.removePhone(d.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListView(
      padding: EdgeInsets.only(bottom: bottomNavPadding(context)),
      children: [
        PageHeader(
          title: S.devices,
          subtitle: S.devicesSubtitle,
          trailing: GradientButton(
            key: const Key('pair-button'),
            label: S.pairPhone,
            icon: Icons.add_rounded,
            onPressed: model.connected ? () => _add(context) : null,
          ),
        ),
        const SizedBox(height: 20),
        if (model.phones.isEmpty)
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: const Center(
              child: Column(
                children: [
                  StatusOrb(
                    color: Color(0xFF6366F1),
                    icon: Icons.devices_rounded,
                    size: 88,
                  ),
                  SizedBox(height: 22),
                  Text(
                    S.noDevices,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        for (final (i, d) in model.phones.indexed)
          Reveal(
            index: i,
            child: GlassCard(
              key: Key('device-${d.id}'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: c.accentGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(d.kind.icon, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                d.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            StatusDot(
                              color: model.present.contains(d.id)
                                  ? c.success
                                  : c.textMuted,
                              size: 8,
                            ),
                            if (d.presenceOnly) ...[
                              const SizedBox(width: 10),
                              Container(
                                key: Key('lock-only-${d.id}'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: c.warning.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  S.lockOnlyBadge,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: c.warning,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${d.kind.label}  ·  ${S.lastSeen}: ${d.lastSeen == null ? S.never : d.lastSeen!.toLocal().toString().split('.').first}',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    key: Key('device-menu-${d.id}'),
                    tooltip: '',
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (v) {
                      switch (v) {
                        case 'rename':
                          _rename(context, d);
                        case 'type':
                          _retype(context, d);
                        case 'remove':
                          _remove(context, d);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text(S.rename),
                      ),
                      const PopupMenuItem(
                        value: 'type',
                        child: Text(S.changeType),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(
                          S.remove,
                          style: TextStyle(color: c.danger),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum _AddChoice { phone, tablet, watchApp, watchBluetooth, other }

/// First step of adding a device: what kind is it?
class AddDeviceDialog extends StatelessWidget {
  const AddDeviceDialog({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(
      Key key,
      IconData icon,
      String title,
      String sub,
      Object? result, {
      VoidCallback? onTap,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        key: key,
        padding: const EdgeInsets.all(14),
        onTap: onTap ?? () => Navigator.pop(context, result),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(sub, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
    return AlertDialog(
      title: const Text(S.addDeviceTitle),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile(
                const Key('add-phone'),
                Icons.smartphone_rounded,
                S.addPhone,
                S.addPhoneSub,
                _AddChoice.phone,
              ),
              tile(
                const Key('add-tablet'),
                Icons.tablet_android_rounded,
                S.addTablet,
                S.addTabletSub,
                _AddChoice.tablet,
              ),
              tile(
                const Key('add-watch'),
                Icons.watch_rounded,
                S.addWatch,
                S.addWatchSub,
                null,
                onTap: () async {
                  final nav = Navigator.of(context);
                  final r = await showDialog<_AddChoice>(
                    context: context,
                    builder: (_) => const _WatchChoiceDialog(),
                  );
                  if (r != null) nav.pop(r);
                },
              ),
              tile(
                const Key('add-other'),
                Icons.devices_other_rounded,
                S.addOther,
                S.addOtherSub,
                _AddChoice.other,
              ),
            ],
          ),
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

class _WatchChoiceDialog extends StatelessWidget {
  const _WatchChoiceDialog();

  @override
  Widget build(BuildContext context) {
    Widget option(
      Key key,
      IconData icon,
      String title,
      String sub,
      _AddChoice value,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        key: key,
        padding: const EdgeInsets.all(14),
        onTap: () => Navigator.pop(context, value),
        child: Row(
          children: [
            Icon(icon, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(sub, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return AlertDialog(
      title: const Text(S.watchChoiceTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(
              const Key('watch-app'),
              Icons.verified_user_rounded,
              S.watchApp,
              S.watchAppSub,
              _AddChoice.watchApp,
            ),
            option(
              const Key('watch-bluetooth'),
              Icons.bluetooth_searching_rounded,
              S.watchBluetooth,
              S.watchBluetoothSub,
              _AddChoice.watchBluetooth,
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

/// Lists the Bluetooth devices around (refreshing every 2 s) and adds the chosen one as lock-only.
class NearbyPickerDialog extends StatefulWidget {
  const NearbyPickerDialog({
    super.key,
    required this.model,
    required this.kind,
  });
  final DaemonModel model;
  final DeviceKind kind;

  @override
  State<NearbyPickerDialog> createState() => _NearbyPickerDialogState();
}

class _NearbyPickerDialogState extends State<NearbyPickerDialog> {
  List<NearbyDevice> _list = const [];
  Timer? _timer;
  NearbyDevice? _picked;
  late DeviceKind _kind = widget.kind;
  final _name = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final l = await widget.model.nearbyDevices();
      if (mounted) setState(() => _list = l);
    } on RpcException {
      // try again on the next tick
    }
  }

  Future<void> _add() async {
    final d = _picked;
    if (d == null) return;
    try {
      await widget.model.addPresenceDevice(d, _name.text, _kind);
      if (mounted) Navigator.pop(context);
    } on RpcException catch (e) {
      setState(() => _error = '$e');
    }
  }

  IconData _bars(int rssi) => rssi > -60
      ? Icons.signal_cellular_alt_rounded
      : rssi > -75
      ? Icons.signal_cellular_alt_2_bar_rounded
      : Icons.signal_cellular_alt_1_bar_rounded;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final picked = _picked;
    return AlertDialog(
      title: Text(picked == null ? S.nearbyTitle : S.addOther),
      content: SizedBox(
        width: 460,
        height: 420,
        child: picked == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.nearbyHelp,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _list.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  S.nearbyEmpty,
                                  style: TextStyle(color: c.textMuted),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _list.length,
                            itemBuilder: (context, i) {
                              final d = _list[i];
                              return ListTile(
                                key: Key('nearby-${d.address}'),
                                dense: true,
                                leading: Icon(_bars(d.rssi), color: c.success),
                                title: Text(d.name ?? S.unnamedDevice),
                                subtitle: Text(
                                  '${d.address}  ·  ${d.rssi} dBm',
                                ),
                                onTap: () => setState(() {
                                  _picked = d;
                                  _name.text = d.name ?? '';
                                }),
                              );
                            },
                          ),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      picked.address,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('presence-name'),
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: S.nameThisDevice,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      S.deviceType,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final k in DeviceKind.values)
                          ChoiceChip(
                            key: Key('presence-kind-${k.id}'),
                            avatar: Icon(k.icon, size: 18),
                            label: Text(k.label),
                            selected: _kind == k,
                            onSelected: (_) => setState(() => _kind = k),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: c.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            S.lockOnlyWarning,
                            style: TextStyle(fontSize: 12.5, color: c.warning),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: TextStyle(color: c.danger)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        if (picked != null)
          TextButton(
            onPressed: () => setState(() => _picked = null),
            child: const Text('Back'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(S.cancel),
        ),
        if (picked != null)
          FilledButton(
            key: const Key('presence-add'),
            onPressed: _add,
            child: const Text(S.add),
          ),
      ],
    );
  }
}

class PairingDialog extends StatelessWidget {
  const PairingDialog({super.key, required this.model});
  final DaemonModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final s = model.pairing;
        if (s == null) return const SizedBox.shrink();
        final c = AppColors.of(context);
        return AlertDialog(
          title: Text(s.completed ? S.paired : S.pairPhone),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.completed)
                  PopIn(
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: c.success,
                      size: 96,
                    ),
                  )
                else ...[
                  const Text(S.pairInstruction),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: c.accent[1].withValues(alpha: 0.35),
                          blurRadius: 30,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(14),
                    child: QrImageView(
                      data: s.uri,
                      size: 230,
                      key: const Key('pairing-qr'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.code,
                    key: const Key('pairing-code'),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(letterSpacing: 6),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          S.waitingForPhone,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.completed ? S.done : S.cancel),
            ),
          ],
        );
      },
    );
  }
}

/// Pairing for devices without a camera: the user types the code the device shows.
class CodePairingDialog extends StatefulWidget {
  const CodePairingDialog({super.key, required this.model});
  final DaemonModel model;

  @override
  State<CodePairingDialog> createState() => _CodePairingDialogState();
}

class _CodePairingDialogState extends State<CodePairingDialog> {
  final _ctl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.model.startCodePairing(
        _ctl.text.trim(),
        name: DeviceKind.watch.label,
      );
    } on RpcException {
      setState(() => _error = S.codeBad);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final c = AppColors.of(context);
        final p = widget.model.codePairing;
        final Widget body;
        if (p == null) {
          body = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(S.codeInstruction),
              const SizedBox(height: 16),
              TextField(
                key: const Key('code-field'),
                controller: _ctl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontSize: 22,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: S.codeHint,
                  errorText: _error,
                ),
                onSubmitted: (_) => _start(),
              ),
            ],
          );
        } else if (p.completed) {
          body = Center(
            child: PopIn(
              child: Icon(
                Icons.check_circle_rounded,
                color: c.success,
                size: 96,
              ),
            ),
          );
        } else if (p.error != null) {
          body = Row(
            children: [
              Icon(Icons.error_outline_rounded, color: c.danger),
              const SizedBox(width: 12),
              Expanded(child: Text(p.error!, key: const Key('code-error'))),
            ],
          );
        } else {
          body = const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 14),
              Expanded(child: Text(S.codeListening)),
            ],
          );
        }
        return AlertDialog(
          title: Text(p?.completed == true ? S.paired : S.codeTitle),
          content: SizedBox(width: 400, child: body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(p?.completed == true ? S.done : S.cancel),
            ),
            if (p == null)
              FilledButton(
                key: const Key('code-start'),
                onPressed: _busy ? null : _start,
                child: const Text(S.codeStart),
              ),
            if (p?.error != null)
              FilledButton(
                onPressed: () =>
                    setState(() => widget.model.codePairing = null),
                child: const Text('Try again'),
              ),
          ],
        );
      },
    );
  }
}
