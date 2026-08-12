import 'package:flutter/material.dart';

import '../services/native_bridge.dart';

/// App-wide accent color state. A single global instance ([themeState]) is
/// fine here - main.dart rebuilds MaterialApp when it notifies, which
/// refreshes every screen. Widgets read [ThemeState.accent] directly so
/// no InheritedWidget plumbing is needed.
class ThemeState extends ChangeNotifier {
  /// Selectable accent colors (first = brand purple default).
  static const List<Color> swatches = [
    Color(0xFFA855F7), // purple (default)
    Color(0xFF22D3EE), // cyan
    Color(0xFF34D399), // green
    Color(0xFFFB923C), // orange
    Color(0xFFF472B6), // pink
    Color(0xFF60A5FA), // blue
  ];

  static const String _kAccentKey = 'theme.accent';

  Color _accent = swatches.first;
  Color get accent => _accent;

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
