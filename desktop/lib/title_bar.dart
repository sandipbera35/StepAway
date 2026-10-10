import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'strings.dart';

/// Custom window title bar: macOS-style traffic lights, logo, drag area, connection pill and
/// theme toggle.
class TitleBar extends StatefulWidget {
  const TitleBar({super.key, required this.connected, required this.theme});
  final bool connected;
  final ThemeController theme;

  static const height = 52.0;

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> with WindowListener {
  bool _focused = true;
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() => setState(() => _focused = true);
  @override
  void onWindowBlur() => setState(() => _focused = false);
  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  IconData _themeIcon(ThemeMode m) => switch (m) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };

  ThemeMode _next(ThemeMode m) => switch (m) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  };

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 560;
        final tiny = box.maxWidth < 700;
        return SizedBox(
          height: TitleBar.height,
          child: Row(
            children: [
              const SizedBox(width: 20),
              TrafficLights(
                focused: _focused,
                maximized: _maximized,
                onClose: () => windowManager.close(),
                onMinimize: () => windowManager.minimize(),
                onMaximize: _toggleMaximize,
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _toggleMaximize,
                  child: DragToMoveArea(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: Row(
                        children: [
                          const StepAwayLogo(size: 26),
                          if (!narrow) const SizedBox(width: 10),
                          if (!narrow)
                            const Text(
                              S.appName,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: 0.2,
                              ),
                            ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _Pill(
                key: const Key('connection-pill'),
                color: widget.connected ? c.success : c.danger,
                label: tiny
                    ? ''
                    : (widget.connected ? S.connected : S.disconnected),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: widget.theme,
                builder: (context, _) => Tooltip(
                  message: '${S.theme}: ${widget.theme.mode.name}',
                  child: IconButton(
                    key: const Key('theme-toggle'),
                    onPressed: () =>
                        widget.theme.setMode(_next(widget.theme.mode)),
                    icon: Icon(_themeIcon(widget.theme.mode), size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }
}

/// The three macOS window dots: close (red), minimise (yellow), maximise (green). Symbols appear
/// when the pointer is over the group; the dots turn grey while the window is not focused.
class TrafficLights extends StatefulWidget {
  const TrafficLights({
    super.key,
    required this.onClose,
    required this.onMinimize,
    required this.onMaximize,
    this.focused = true,
    this.maximized = false,
  });

  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final bool focused;
  final bool maximized;

  @override
  State<TrafficLights> createState() => _TrafficLightsState();
}

class _TrafficLightsState extends State<TrafficLights> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final idle = dark ? const Color(0x40FFFFFF) : const Color(0x33000000);
    Color tone(Color active) => (widget.focused || _hover) ? active : idle;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(
            key: const Key('traffic-close'),
            semanticLabel: S.close,
            color: tone(const Color(0xFFFF5F57)),
            icon: Icons.close_rounded,
            showIcon: _hover,
            onTap: widget.onClose,
          ),
          const SizedBox(width: 8),
          _Dot(
            key: const Key('traffic-minimize'),
            semanticLabel: S.minimize,
            color: tone(const Color(0xFFFEBC2E)),
            icon: Icons.remove_rounded,
            showIcon: _hover,
            onTap: widget.onMinimize,
          ),
          const SizedBox(width: 8),
          _Dot(
            key: const Key('traffic-maximize'),
            semanticLabel: widget.maximized ? S.restore : S.maximize,
            color: tone(const Color(0xFF28C840)),
            icon: widget.maximized
                ? Icons.close_fullscreen_rounded
                : Icons.open_in_full_rounded,
            showIcon: _hover,
            onTap: widget.onMaximize,
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    super.key,
    required this.color,
    required this.icon,
    required this.showIcon,
    required this.onTap,
    required this.semanticLabel,
  });

  final Color color;
  final IconData icon;
  final bool showIcon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.12),
              width: 0.6,
            ),
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 100),
            opacity: showIcon ? 1 : 0,
            child: Icon(
              icon,
              size: 9,
              color: Colors.black.withValues(alpha: 0.62),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShapeDecoration(
        color: c.glassFill,
        shape: StadiumBorder(side: BorderSide(color: c.glassBorder)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(color: color, size: 8),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
