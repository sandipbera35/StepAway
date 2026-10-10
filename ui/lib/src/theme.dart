import 'package:flutter/material.dart';

import 'colors.dart';

/// Light and dark themes. Scaffolds are transparent: the app paints [GlassBackground] behind them.
class StepAwayTheme {
  static const _family = 'packages/stepaway_ui/Inter';

  static ThemeData light() => _build(Brightness.light, AppColors.light);
  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness b, AppColors c) {
    final dark = b == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: b,
        ).copyWith(
          primary: dark ? const Color(0xFF8B8CFF) : const Color(0xFF4F46E5),
          surface: dark ? const Color(0xFF121734) : const Color(0xFFFFFFFF),
          onSurface: dark ? const Color(0xFFF3F5FF) : const Color(0xFF0F172A),
          error: c.danger,
        );
    final base = ThemeData(
      brightness: b,
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: _family,
    );
    final t = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      extensions: [c],
      textTheme: t.copyWith(
        displayLarge: t.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1.5,
        ),
        displayMedium: t.displayMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
        displaySmall: t.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        headlineMedium: t.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineSmall: t.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: t.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: t.bodyMedium?.copyWith(height: 1.4),
        bodySmall: t.bodySmall?.copyWith(color: c.textMuted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark
            ? const Color(0xE6141A3C)
            : const Color(0xF2FFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: c.glassBorder),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFF1E2447)
            : const Color(0xFF1E1B4B),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: _family,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 6,
        tickMarkShape: SliderTickMarkShape.noTickMark,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 10,
          elevation: 4,
        ),
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.12),
        thumbColor: Colors.white,
        overlayColor: scheme.primary.withValues(alpha: 0.15),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : (dark ? const Color(0xFFB7BFDD) : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurface.withValues(alpha: 0.18),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: _family,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: BorderSide(color: c.glassBorder, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: _family,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.glassBorder, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B4B),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: _family,
        ),
      ),
    );
  }
}
