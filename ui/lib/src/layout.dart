import 'package:flutter/widgets.dart';

/// Coarse screen classes shared by both apps.
enum ScreenSize {
  /// Phones in portrait and narrow windows: one column, tab bar at the bottom.
  compact,

  /// Tablets, phones in landscape, medium windows: two columns, navigation rail.
  medium,

  /// Large windows: full sidebar and roomy grids.
  expanded;

  bool get isCompact => this == ScreenSize.compact;
  bool get isExpanded => this == ScreenSize.expanded;
}

ScreenSize screenSizeFor(double width) {
  if (width < 720) return ScreenSize.compact;
  if (width < 1000) return ScreenSize.medium;
  return ScreenSize.expanded;
}

/// Builds with the [ScreenSize] of the space it is given (not of the whole screen).
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});
  final Widget Function(
    BuildContext context,
    ScreenSize size,
    BoxConstraints constraints,
  )
  builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (c, box) => builder(c, screenSizeFor(box.maxWidth), box),
  );
}

/// Keeps content readable on big screens: centred, never wider than [maxWidth].
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.maxWidth = 720});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Space to keep clear at the bottom of scrolling content so the floating tab bar (compact
/// screens only) never covers it.
double bottomNavPadding(BuildContext context) =>
    screenSizeFor(MediaQuery.sizeOf(context).width).isCompact ? 130 : 24;
