import 'package:flutter/material.dart';

/// MaxPlayer dark design language — true-black neutral surfaces (no blue
/// tint), hairline borders, themable accent with automatic on-accent
/// contrast. Dark-first, no light mode for v0.
class AppColors {
  AppColors._();

  static const background = Color(0xFF060608); // app canvas — true black
  static const surface = Color(0xFF101013); // cards / inputs
  static const surfaceAlt = Color(0xFF18181C); // raised elements
  static const border = Color(0xFF26262C); // 1px hairlines
  static const textPrimary = Color(0xFFF5F6F8);
  static const textSecondary = Color(0xFF9296A0);

  /// Mutable — set from Display Settings accent wheel (AppSettings).
  static Color accent = const Color(0xFFFFFFFF); // default: white
  static const danger = Color(0xFFE5484D);

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
    appBarTheme: const AppBarTheme(
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
        borderRadius: const BorderRadius.all(radius),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.textPrimary),
      bodySmall: TextStyle(color: AppColors.textSecondary),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
  );
}
