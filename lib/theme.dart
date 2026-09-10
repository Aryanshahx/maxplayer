import 'package:flutter/material.dart';

/// MaxPlayer dark design language — near-black slate surfaces,
/// hairline borders, cool blue accent. Dark-first, no light mode for v0.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0B0E14); // app canvas
  static const surface = Color(0xFF131826); // cards / inputs
  static const surfaceAlt = Color(0xFF181E2E); // raised elements
  static const border = Color(0xFF262E42); // 1px hairlines
  static const textPrimary = Color(0xFFF2F5FA);
  static const textSecondary = Color(0xFF8B94A7);
  static const accent = Color(0xFF3D6BFF); // primary blue
  static const accentSoft = Color(0xFF2A3CFF);
  static const danger = Color(0xFFE5484D);
}

ThemeData buildAppTheme() {
  const radius = Radius.circular(16);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.accent,
      onPrimary: Colors.white,
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
