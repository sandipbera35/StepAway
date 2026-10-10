import 'package:flutter/material.dart';

/// Colours that do not fit Material's ColorScheme: glass surfaces, background and status tones.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.blobs,
    required this.glassFill,
    required this.glassFillStrong,
    required this.glassBorder,
    required this.shadow,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.textMuted,
  });

  final List<Color> bg;
  final List<Color> blobs;
  final Color glassFill;
  final Color glassFillStrong;
  final Color glassBorder;
  final Color shadow;
  final List<Color> accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color textMuted;

  LinearGradient get accentGradient => LinearGradient(
    colors: accent,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _accent = [
    Color(0xFF22D3EE),
    Color(0xFF6366F1),
    Color(0xFF8B5CF6),
  ];

  static const dark = AppColors(
    bg: [Color(0xFF080B1A), Color(0xFF0F1530), Color(0xFF1A1140)],
    blobs: [Color(0x5922D3EE), Color(0x668B5CF6), Color(0x40EC4899)],
    glassFill: Color(0x14FFFFFF),
    glassFillStrong: Color(0x24FFFFFF),
    glassBorder: Color(0x24FFFFFF),
    shadow: Color(0x66000000),
    accent: _accent,
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    textMuted: Color(0xFF9AA4C4),
  );

  static const light = AppColors(
    bg: [Color(0xFFEEF2FF), Color(0xFFF5F3FF), Color(0xFFECFEFF)],
    blobs: [Color(0x8067E8F9), Color(0x80C4B5FD), Color(0x66FBCFE8)],
    glassFill: Color(0x99FFFFFF),
    glassFillStrong: Color(0xCCFFFFFF),
    glassBorder: Color(0xCCFFFFFF),
    shadow: Color(0x1A1E1B4B),
    accent: _accent,
    success: Color(0xFF059669),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    textMuted: Color(0xFF5B6486),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      t < 0.5 ? this : (other as AppColors? ?? this);
}
