import 'package:flutter/material.dart';
import 'services/remote_theme.dart';
import 'widgets/festive_visuals.dart';

/// MaxPlayer dark design language — true-black neutral surfaces (no blue
/// tint), hairline borders, themable accent with automatic on-accent
/// contrast. Dark-first, no light mode for v0.
class AppColors {
  AppColors._();

  static Color get background =>
      RemoteTheme.instance.colour('background'); // app canvas — true black
  static Color get surface =>
      RemoteTheme.instance.colour('surface'); // cards / inputs
  static Color get surfaceAlt =>
      RemoteTheme.instance.colour('surfaceAlt'); // raised elements
  static Color get border =>
      RemoteTheme.instance.colour('border'); // 1px hairlines
  static Color get textPrimary => RemoteTheme.instance.colour('textPrimary');
  static Color get textSecondary =>
      RemoteTheme.instance.colour('textSecondary');

  /// Mutable — set from Display Settings accent wheel (AppSettings).
  static Color accent = const Color(0xFFFFFFFF); // default: white
  static Color get danger => RemoteTheme.instance.colour('danger');

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
  final radius = Radius.circular(
    themeVisual('rounded', 'soft') == 'pill' ? 28 : 16,
  );
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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(radius)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(radius)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(radius)),
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
