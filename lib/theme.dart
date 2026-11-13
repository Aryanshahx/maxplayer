import 'package:flutter/material.dart';

/// MaxPlayer dark design language — true-black neutral surfaces (no blue
/// tint), hairline borders, themable accent with automatic on-accent
/// contrast. Dark-first, no light mode for v0.
class AppColors {
  AppColors._();

  static Color get background => const Color(0xFF060608);
  static Color get surface => const Color(0xFF101013);
  static Color get surfaceAlt => const Color(0xFF18181C);
  static Color get border => const Color(0xFF26262C);
  static Color get textPrimary => const Color(0xFFF5F6F8);
  static Color get textSecondary => const Color(0xFF9296A0);
  static Color accent = const Color(0xFFFFFFFF);
  static Color get danger => const Color(0xFFE5484D);

  /// Text/icon colour that stays readable ON TOP of [accent]
  /// (black for the white accent, white for colours).
  static Color get onAccent =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.light
      ? const Color(0xFF0B0B0E)
      : Colors.white;
}

ThemeData buildAppTheme({Color? accent}) {
  final ac = accent ?? AppColors.accent;
  final onAc = ThemeData.estimateBrightnessForColor(ac) == Brightness.light
      ? const Color(0xFF0B0B0E)
      : Colors.white;
  const radius = Radius.circular(16);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.dark(
      surface: AppColors.surface,
      primary: ac,
      onPrimary: onAc,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(radius),
        side: BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    iconTheme: IconThemeData(color: AppColors.textPrimary),
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: AppColors.textPrimary),
      bodySmall: TextStyle(color: AppColors.textSecondary),
    ),
    dividerTheme: DividerThemeData(color: AppColors.border, thickness: 1),
  );
}
