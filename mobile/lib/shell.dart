import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import 'controller.dart';
import 'native.dart';
import 'pages/computers.dart';
import 'pages/home.dart';
import 'pages/onboarding.dart';
import 'pages/settings.dart';
import 'pairing_flow.dart';
import 'strings.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.native,
    required this.theme,
    this.clock,
  });

  /// Replaced in tests to control when the beacon counts as stale.
  final DateTime Function()? clock;
  final Native native;
  final ThemeController theme;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late final AppController _app = AppController(
    widget.native,
    clock: widget.clock,
  );
  int _tab = 0;
  bool _resumed = true;

  /// The distance dashboard is on the first tab: scan for the beacon only while it is visible.
  bool get _wantsBeacon => _resumed && _tab == 0;

  void _syncBeacon() {
    if (_wantsBeacon) {
      _app.startBeacon();
    } else if (_app.beaconRunning) {
      _app.stopBeacon();
    }
  }

  static const _items = [
    NavItem(Key('nav-shield'), Icons.shield_rounded, S.tabHome),
    NavItem(Key('nav-computers'), Icons.computer_rounded, S.tabComputers),
    NavItem(Key('nav-settings'), Icons.tune_rounded, S.tabSettings),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.native.onDeepLink(_onLink);
    _app.start();
    _app.addListener(_syncBeacon);
    widget.native.initialLink().then((l) {
      if (l != null && mounted) _onLink(l);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOnboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.removeListener(_syncBeacon);
    _app.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) _app.refresh();
    _syncBeacon();
  }

  Future<void> _maybeOnboard() async {
    bool done;
    try {
      done = await widget.native.getOnboarded();
    } catch (_) {
      done = true;
    }
    if (done || !mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (c, _, _) => GlassBackgroundHost(
          child: OnboardingPage(
            app: _app,
            onDone: () {
              widget.native.setOnboarded(true);
              Navigator.of(c).pop();
            },
          ),
        ),
        transitionsBuilder: (c, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  void _onLink(String uri) {
    if (mounted) runPairingFlow(context, _app, uri);
  }

  Future<void> _scan() async {
    final uri = await widget.native.scanQr();
    if (uri != null && mounted) await runPairingFlow(context, _app, uri);
  }

  Future<void> _paste() async {
    final ctl = TextEditingController();
    final uri = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(S.pairPaste),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(hintText: S.pasteHint),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctl.text.trim()),
            child: const Text(S.pair),
          ),
        ],
      ),
    );
    if (uri != null && uri.isNotEmpty && mounted) {
      await runPairingFlow(context, _app, uri);
    }
  }

  void _openPairSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) {
        final colors = AppColors.of(c);
        Widget option(
          int i,
          IconData icon,
          String title,
          String sub,
          VoidCallback onTap, {
          Key? key,
        }) => Reveal(
          index: i,
          child: GlassCard(
            key: key,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            onTap: () {
              Navigator.pop(c);
              onTap();
            },
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: colors.accentGradient,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(sub, style: Theme.of(c).textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        );
        return Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            strong: true,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.pairHow, style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 16),
                option(
                  0,
                  Icons.qr_code_scanner_rounded,
                  S.pairQr,
                  S.pairQrSub,
                  _scan,
                  key: const Key('sheet-scan'),
                ),
                option(
                  1,
                  Icons.link_rounded,
                  S.pairPaste,
                  S.pairLinkSub,
                  _paste,
                  key: const Key('sheet-link'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  ThemeMode _nextTheme(ThemeMode m) => switch (m) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_app, widget.theme]),
      builder: (context, _) {
        final pages = [
          HomePage(
            app: _app,
            onOpenComputers: () => setState(() {
              _tab = 1;
              _syncBeacon();
            }),
          ),
          ComputersPage(app: _app, onPair: _openPairSheet),
          SettingsPage(app: _app, theme: widget.theme),
        ];
        Widget header() => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
          child: Row(
            children: [
              const StepAwayLogo(size: 36),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  S.appName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              IconButton(
                key: const Key('theme-button'),
                tooltip: S.theme,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  widget.theme.setMode(_nextTheme(widget.theme.mode));
                },
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (c, a) => RotationTransition(
                    turns: Tween(begin: 0.75, end: 1.0).animate(a),
                    child: ScaleTransition(scale: a, child: c),
                  ),
                  child: Icon(switch (widget.theme.mode) {
                    ThemeMode.system => Icons.brightness_auto_rounded,
                    ThemeMode.light => Icons.light_mode_rounded,
                    ThemeMode.dark => Icons.dark_mode_rounded,
                  }, key: ValueKey(widget.theme.mode)),
                ),
              ),
            ],
          ),
        );
        final page = FadeSlideSwitcher(pageKey: _tab, child: pages[_tab]);
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: ResponsiveBuilder(
              builder: (context, size, box) {
                if (size.isCompact) {
                  // portrait phone: tab bar floats at the bottom
                  return Stack(
                    children: [
                      Column(
                        children: [
                          header(),
                          Expanded(child: page),
                        ],
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: MediaQuery.paddingOf(context).bottom + 14,
                        child: GlassNavBar(
                          index: _tab,
                          onSelect: (i) => setState(() {
                            _tab = i;
                            _syncBeacon();
                          }),
                          items: _items,
                        ),
                      ),
                    ],
                  );
                }
                // tablet / landscape: navigation rail on the left, content centred
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        12,
                        0,
                        MediaQuery.paddingOf(context).bottom + 12,
                      ),
                      child: GlassNavRail(
                        index: _tab,
                        onSelect: (i) => setState(() {
                          _tab = i;
                          _syncBeacon();
                        }),
                        items: _items,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          header(),
                          Expanded(child: MaxWidth(maxWidth: 980, child: page)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Re-applies the app background for routes pushed above the home screen.
class GlassBackgroundHost extends StatelessWidget {
  const GlassBackgroundHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
