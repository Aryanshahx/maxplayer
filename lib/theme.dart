import 'package:flutter/material.dart';

/// MaxPlayer adaptive design language — true-black neutral surfaces (no blue
/// tint), hairline borders, themable accent with automatic on-accent
/// contrast. Follows the saved System / Light / Dark preference.
class AppColors {
  AppColors._();

  static Brightness brightness = Brightness.dark;
  static bool get isDark => brightness == Brightness.dark;
  static Color get background =>
      isDark ? const Color(0xFF060608) : const Color(0xFFF7F8FA);
  static Color get surface =>
      isDark ? const Color(0xFF101013) : const Color(0xFFFFFFFF);
  static Color get surfaceAlt =>
      isDark ? const Color(0xFF18181C) : const Color(0xFFECEEF2);
  static Color get border =>
      isDark ? const Color(0xFF26262C) : const Color(0xFFD3D7DE);
  static Color get textPrimary =>
      isDark ? const Color(0xFFF5F6F8) : const Color(0xFF181A20);
  static Color get textSecondary =>
      isDark ? const Color(0xFF9296A0) : const Color(0xFF535965);
  static Color _accent = const Color(0xFFFFFFFF);
  static set accent(Color value) => _accent = value;
  // The default white accent becomes charcoal in light mode for contrast.
  static Color get accent => adaptiveAccent(_accent, brightness);
  // Video-overlay controls are white regardless of the app surface theme.
  static Color get playerForeground => Colors.white;
  static Color get playerMuted => Colors.white;
  static Color get playerChrome =>
      isDark ? const Color(0x99060608) : const Color(0x99FFFFFF);
  static Color get mediaAccent => _accent;
  static Color get mediaOnAccent => contrastForeground(_accent);
  static Color get danger =>
      isDark ? const Color(0xFFFF7A80) : const Color(0xFFB4232B);
  static Color get rating =>
      isDark ? const Color(0xFFFFD66B) : const Color(0xFF805000);

  /// Text/icon colour that stays readable ON TOP of [accent]
  /// (black for the white accent, white for colours).
  static Color get onAccent => contrastForeground(accent);
}

Color contrastForeground(Color background) {
  final luminance = background.computeLuminance();
  return (1.05 / (luminance + .05)) >= ((luminance + .05) / .05)
      ? Colors.white
      : Colors.black;
}

Color adaptiveAccent(Color raw, Brightness brightness) {
  if (brightness == Brightness.dark) {
    var hsl = HSLColor.fromColor(raw);
    final base = const Color(0xFF101013).computeLuminance();
    while ((hsl.toColor().computeLuminance() + .05) / (base + .05) < 4.5 &&
        hsl.lightness < .95) {
      hsl = hsl.withLightness((hsl.lightness + .025).clamp(0, 1));
    }
    return hsl.toColor();
  }
  if (raw == const Color(0xFFFFFFFF)) return const Color(0xFF252830);
  var hsl = HSLColor.fromColor(raw);
  while ((1.05 / (hsl.toColor().computeLuminance() + .05)) < 4.5 &&
      hsl.lightness > .1) {
    hsl = hsl.withLightness((hsl.lightness - .025).clamp(0, 1));
  }
  return hsl.toColor();
}

ThemeData buildAppTheme({
  Color? accent,
  Brightness brightness = Brightness.dark,
}) {
  final dark = brightness == Brightness.dark;
  final raw = accent ?? AppColors.accent;
  final ac = adaptiveAccent(raw, brightness);
  final onAc = contrastForeground(ac);
  final background = dark ? const Color(0xFF060608) : const Color(0xFFF7F8FA);
  final surface = dark ? const Color(0xFF101013) : Colors.white;
  final text = dark ? const Color(0xFFF5F6F8) : const Color(0xFF181A20);
  final border = dark ? const Color(0xFF26262C) : const Color(0xFFD3D7DE);
  final scheme = ColorScheme.fromSeed(seedColor: ac, brightness: brightness)
      .copyWith(
        primary: ac,
        onPrimary: onAc,
        surface: surface,
        onSurface: text,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: background,
        surfaceContainerLow: surface,
        surfaceContainer: dark
            ? const Color(0xFF18181C)
            : const Color(0xFFF0F1F4),
        surfaceContainerHigh: dark
            ? const Color(0xFF202024)
            : const Color(0xFFE8EAEE),
        surfaceContainerHighest: dark
            ? const Color(0xFF29292F)
            : const Color(0xFFE0E3E8),
        onSurfaceVariant: dark
            ? const Color(0xFFACAFB8)
            : const Color(0xFF535965),
        outline: dark ? const Color(0xFF777B85) : const Color(0xFF737986),
        outlineVariant: border,
        error: dark ? const Color(0xFFFF7A80) : const Color(0xFFB4232B),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    focusColor: ac.withValues(alpha: .25),
    hoverColor: ac.withValues(alpha: .10),
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    iconTheme: IconThemeData(color: text),
    listTileTheme: ListTileThemeData(textColor: text, iconColor: text),
    chipTheme: ChipThemeData(
      selectedColor: ac,
      backgroundColor: surface,
      checkmarkColor: onAc,
      side: BorderSide(color: border),
      labelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected) ? onAc : text,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: border),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(
        color: dark ? Colors.white54 : const Color(0xFF535965),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      textStyle: TextStyle(color: text),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface),
    dialogTheme: DialogThemeData(backgroundColor: surface),
    switchTheme: SwitchThemeData(
      // Explicit thumb/track/border states avoid Material seed tint leaking
      // through the transition, including disabled and keyboard-focus states.
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : scheme.outline,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? ac.withValues(alpha: .2)
            : Colors.transparent,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? text.withValues(alpha: .38)
            : states.contains(WidgetState.selected)
            ? onAc
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.surfaceContainerHighest
            : states.contains(WidgetState.selected)
            ? ac
            : scheme.surfaceContainerHighest,
      ),
    ),
  );
}
