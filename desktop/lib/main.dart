import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'ipc/rpc_client.dart';
import 'model.dart';
import 'pages/about.dart';
import 'pages/calibration.dart';
import 'pages/dashboard.dart';
import 'pages/devices.dart';
import 'pages/settings.dart';
import 'service.dart';
import 'strings.dart';
import 'theme_store.dart';
import 'title_bar.dart';
import 'uninstall.dart';
import 'window_frame.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerExtraLicenses({
    'StepAway background service (Rust crates)':
        'assets/THIRD_PARTY_LICENSES.txt',
  });
  if (Platform.isLinux || Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1180, 760),
        minimumSize: Size(420, 620),
        center: true,
        title: S.appName,
        titleBarStyle: TitleBarStyle.hidden,
        backgroundColor: Colors.transparent,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  final theme = ThemeController(store: FileThemeStore());
  await theme.init();
  runApp(
    StepAwayDesktop(
      model: DaemonModel(
        RpcClient(),
        service: SystemServiceManager(),
        uninstaller: createUninstaller(),
      )..init(),
      theme: theme,
    ),
  );
}

class StepAwayDesktop extends StatefulWidget {
  const StepAwayDesktop({super.key, required this.model, this.theme});
  final DaemonModel model;
  final ThemeController? theme;

  @override
  State<StepAwayDesktop> createState() => _StepAwayDesktopState();
}

class _StepAwayDesktopState extends State<StepAwayDesktop> {
  late final ThemeController _theme = widget.theme ?? ThemeController();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => MaterialApp(
        title: S.appName,
        debugShowCheckedModeBanner: false,
        theme: StepAwayTheme.light(),
        darkTheme: StepAwayTheme.dark(),
        themeMode: _theme.mode,
        scrollBehavior: const NoScrollbarBehavior(),
        builder: (context, child) => WindowFrame(
          child: GlassBackground(child: child ?? const SizedBox.shrink()),
        ),
        home: Shell(model: widget.model, theme: _theme),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.model, required this.theme});
  final DaemonModel model;
  final ThemeController theme;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _items = [
    (Key('nav-dashboard'), Icons.speed, S.dashboard),
    (Key('nav-phones'), Icons.devices_rounded, S.devices),
    (Key('nav-calibrate'), Icons.tune, S.calibrate),
    (Key('nav-settings'), Icons.settings, S.settings),
    (Key('nav-about'), Icons.info_outline_rounded, S.about),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final m = widget.model;
        final pages = [
          DashboardPage(
            model: m,
            onCalibrate: () => setState(() => _index = 2),
          ),
          DevicesPage(model: m),
          CalibrationPage(model: m),
          SettingsPage(model: m, theme: widget.theme),
          AboutPage(model: m),
        ];
        final body = Scaffold(
          body: Column(
            children: [
              TitleBar(connected: m.connected, theme: widget.theme),
              if (!m.connected) _ServiceBanner(model: m),
              if (m.connected && !m.scanning) const _Banner(text: S.noScanner),
              Expanded(
                child: ResponsiveBuilder(
                  builder: (context, size, box) {
                    final page = FadeSlideSwitcher(
                      pageKey: _index,
                      child: pages[_index],
                    );
                    if (size.isCompact) {
                      // narrow window: content on top, floating glass tab bar below
                      return Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                            child: page,
                          ),
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: GlassNavBar(
                              index: _index,
                              onSelect: (i) => setState(() => _index = i),
                              items: [
                                for (final it in _items)
                                  NavItem(it.$1, it.$2, it.$3),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Row(
                        children: [
                          _Sidebar(
                            index: _index,
                            onSelect: (i) => setState(() => _index = i),
                            items: _items,
                            compact: !size.isExpanded,
                          ),
                          SizedBox(width: size.isExpanded ? 16 : 12),
                          Expanded(child: page),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
        if (Platform.isLinux || Platform.isWindows) {
          return DragToResizeArea(child: body);
        }
        return body;
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.items,
    this.compact = false,
  });
  final bool compact;
  final int index;
  final ValueChanged<int> onSelect;
  final List<(Key, IconData, String)> items;

  static const _itemHeight = 48.0;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: compact ? 76 : 220,
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SizedBox(
              height: items.length * (_itemHeight + _gap),
              child: Stack(
                children: [
                  // one highlight that glides between the items
                  AnimatedPositioned(
                    key: const Key('nav-indicator'),
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutBack,
                    top: index * (_itemHeight + _gap),
                    left: 0,
                    right: 0,
                    height: _itemHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: c.accentGradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: c.accent[1].withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (var i = 0; i < items.length; i++)
                    Positioned(
                      top: i * (_itemHeight + _gap),
                      left: 0,
                      right: 0,
                      height: _itemHeight,
                      child: Pressable(
                        key: items[i].$1,
                        onTap: () => onSelect(i),
                        child: Tooltip(
                          message: compact ? items[i].$3 : '',
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 0 : 14,
                            ),
                            child: Row(
                              mainAxisAlignment: compact
                                  ? MainAxisAlignment.center
                                  : MainAxisAlignment.start,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  child: Icon(
                                    items[i].$2,
                                    key: ValueKey(i == index),
                                    size: 20,
                                    color: i == index
                                        ? Colors.white
                                        : onSurface.withValues(alpha: 0.75),
                                  ),
                                ),
                                if (!compact) ...[
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily:
                                            'packages/stepaway_ui/Inter',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: i == index
                                            ? Colors.white
                                            : onSurface.withValues(alpha: 0.85),
                                      ),
                                      child: Text(
                                        items[i].$3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
            if (!compact)
              Text(
                'v0.0.1',
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GlassCard(
        tint: c.danger,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        radius: 16,
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: c.danger),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _ServiceBanner extends StatelessWidget {
  const _ServiceBanner({required this.model});
  final DaemonModel model;

  @override
  Widget build(BuildContext context) => _Banner(
    text: S.serviceDown,
    action: TextButton(
      onPressed: () async {
        final ok = await model.startService();
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text(S.serviceStartFailed)));
        }
      },
      child: const Text(S.startService),
    ),
  );
}
