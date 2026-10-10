import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';
import 'glass.dart';
import 'motion.dart';

/// Floating glass tab bar with a highlight that glides to the selected tab.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.items,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final List<NavItem> items;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GlassCard(
      strong: true,
      radius: 30,
      blur: 28,
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / items.length;
          return SizedBox(
            height: 58,
            child: Stack(
              children: [
                AnimatedPositioned(
                  key: const Key('tab-indicator'),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  left: index * w,
                  width: w,
                  top: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: c.accentGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: c.accent[1].withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < items.length; i++)
                  Positioned(
                    left: i * w,
                    width: w,
                    top: 0,
                    bottom: 0,
                    child: Pressable(
                      key: items[i].key,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onSelect(i);
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: i == index ? 1.12 : 1,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutBack,
                            child: Icon(
                              items[i].icon,
                              size: 22,
                              color: i == index
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 2),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 240),
                            style: TextStyle(
                              fontFamily: 'packages/stepaway_ui/Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: i == index
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                            ),
                            child: Text(items[i].label),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class NavItem {
  const NavItem(this.key, this.icon, this.label);
  final Key key;
  final IconData icon;
  final String label;
}

/// Vertical glass navigation rail for tablets and landscape: same look as [GlassNavBar].
class GlassNavRail extends StatelessWidget {
  const GlassNavRail({
    super.key,
    required this.index,
    required this.onSelect,
    required this.items,
    this.width = 84,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final List<NavItem> items;
  final double width;

  static const _itemHeight = 68.0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: width,
      child: GlassCard(
        strong: true,
        radius: 28,
        blur: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: SizedBox(
          height: items.length * _itemHeight,
          child: Stack(
            children: [
              AnimatedPositioned(
                key: const Key('rail-indicator'),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                top: index * _itemHeight,
                left: 0,
                right: 0,
                height: _itemHeight - 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: c.accentGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: c.accent[1].withValues(alpha: 0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                ),
              ),
              for (var i = 0; i < items.length; i++)
                Positioned(
                  top: i * _itemHeight,
                  left: 0,
                  right: 0,
                  height: _itemHeight - 6,
                  child: Pressable(
                    key: items[i].key,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelect(i);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[i].icon,
                          size: 22,
                          color: i == index
                              ? Colors.white
                              : onSurface.withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'packages/stepaway_ui/Inter',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: i == index
                                ? Colors.white
                                : onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
