import 'package:flutter/material.dart';

import '../services/native_bridge.dart';

/// App-wide accent color state. A single global instance ([themeState]) is
/// fine here - main.dart rebuilds MaterialApp when it notifies, which
/// refreshes every screen. Widgets read [ThemeState.accent] directly so
/// no InheritedWidget plumbing is needed.
class ThemeState extends ChangeNotifier {
  /// Selectable accent colors (white added in v22).
  static const List<Color> swatches = [
    Color(0xFFA855F7), // purple
    Color(0xFF22D3EE), // cyan
    Color(0xFF34D399), // green
    Color(0xFFFB923C), // orange
    Color(0xFFF472B6), // pink
    Color(0xFF60A5FA), // blue
    Color(0xFFFFFFFF), // white (v22)
  ];

  /// v29: WHITE is the default theme colour (user request). Anyone who
  /// already picked a colour keeps it - the saved choice loads on top.
  static const Color defaultAccent = Color(0xFFFFFFFF);

  static const String _kAccentKey = 'theme.accent';

  Color _accent = defaultAccent;
  Color get accent => _accent;

  /// Text/icon color to paint ON TOP of the accent (light accents like
  /// white need dark ink, the rest use white).
  Color get onAccent => contrastColorFor(_accent);

  Future<void> load() async {
    final s = await NativeBridge.loadSettings();
    final v = int.tryParse(s[_kAccentKey] ?? '');
    if (v != null) {
      final match = swatches.where((c) => c.toARGB32() == v);
      _accent = match.isNotEmpty ? match.first : Color(v);
      notifyListeners();
    }
  }

  void setAccent(Color c) {
    _accent = c;
    notifyListeners();
    NativeBridge.saveSetting(_kAccentKey, '${c.toARGB32()}');
  }
}

/// The one app-wide instance.
final ThemeState themeState = ThemeState();

/// Text/icon color that stays readable ON a [c]-coloured surface. Pure +
/// unit-tested (v22: this is what keeps the speed badge visible on the
/// white accent).
Color contrastColorFor(Color c) {
  final argb = c.toARGB32();
  // Perceived luminance (WCAG-ish), cheap and fine for our swatches.
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final lum = 0.299 * r + 0.587 * g + 0.114 * b;
  return lum > 160 ? const Color(0xFF16161f) : Colors.white;
}
