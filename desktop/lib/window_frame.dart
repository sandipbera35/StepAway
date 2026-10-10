import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stepaway_ui/stepaway_ui.dart';
import 'package:window_manager/window_manager.dart';

/// Rounds the window like a macOS window (continuous "squircle" corners, thin light border).
/// The corners square off when the window is maximised or full screen. Windows 11 rounds frameless
/// windows itself, so only Linux needs the clip (the native window is transparent there).
class WindowFrame extends StatefulWidget {
  const WindowFrame({
    super.key,
    required this.child,
    this.radius = 18,
    this.enabled,
  });
  final Widget child;
  final double radius;

  /// Force rounding on or off; by default it is on for Linux.
  final bool? enabled;

  @override
  State<WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<WindowFrame> with WindowListener {
  bool _square = false;

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

  void _set(bool square) {
    if (square != _square) setState(() => _square = square);
  }

  @override
  void onWindowMaximize() => _set(true);
  @override
  void onWindowUnmaximize() => _set(false);
  @override
  void onWindowEnterFullScreen() => _set(true);
  @override
  void onWindowLeaveFullScreen() => _set(false);

  @override
  Widget build(BuildContext context) {
    final rounded = (widget.enabled ?? Platform.isLinux) && !_square;
    if (!rounded) return widget.child;
    final shape = BorderRadius.circular(widget.radius);
    final c = AppColors.of(context);
    return ClipRSuperellipse(
      borderRadius: shape,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: shape,
                    side: BorderSide(color: c.glassBorder),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
