import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppDesignMode { android, compact, cinema }

/// App-level design system: inherited by every route/dialog, not a Home-only
/// toggle. Density, typography, control geometry and surface shapes all change.
class AppDesign extends ChangeNotifier {
  static final instance = AppDesign();
  AppDesignMode mode = AppDesignMode.android;
  double get mediaExtent => switch (mode) {
        AppDesignMode.android => 300,
        AppDesignMode.compact => 220,
        AppDesignMode.cinema => 420
      };
  double get contentWidth => switch (mode) {
        AppDesignMode.android => 1100,
        AppDesignMode.compact => 960,
        AppDesignMode.cinema => 1360
      };
  double get textScale => switch (mode) {
        AppDesignMode.android => 1,
        AppDesignMode.compact => .94,
        AppDesignMode.cinema => 1.08
      };
  String label(AppDesignMode value) => switch (value) {
        AppDesignMode.android => 'Android style',
        AppDesignMode.compact => 'Compact Desktop',
        AppDesignMode.cinema => 'Cinema'
      };
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('hyper.design.v1');
    mode = AppDesignMode.values.firstWhere((value) => value.name == stored,
        orElse: () => AppDesignMode.android);
    notifyListeners();
  }

  Future<void> select(AppDesignMode value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('hyper.design.v1', value.name)) {
      throw StateError('Design could not be saved.');
    }
    mode = value;
    notifyListeners();
  }

  ThemeData theme(ThemeData base) {
    if (mode == AppDesignMode.android) return base;
    final compact = mode == AppDesignMode.compact;
    final radius = compact ? 6.0 : 24.0;
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: Color(0xff303038)));
    return base.copyWith(
      visualDensity: compact
          ? VisualDensity.compact
          : const VisualDensity(horizontal: 1, vertical: 2),
      scaffoldBackgroundColor:
          compact ? const Color(0xff101013) : const Color(0xff050507),
      cardTheme: base.cardTheme.copyWith(
          shape: shape,
          margin: EdgeInsets.all(compact ? 2 : 8),
          elevation: compact ? 0 : 4),
      listTileTheme: ListTileThemeData(
          dense: compact,
          contentPadding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 24, vertical: compact ? 0 : 8),
          shape: shape),
      dialogTheme: DialogThemeData(shape: shape),
      bottomSheetTheme: BottomSheetThemeData(
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(radius))),
          showDragHandle: true),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              shape: shape,
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 28, vertical: compact ? 10 : 18))),
      inputDecorationTheme: InputDecorationTheme(
          filled: !compact,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(radius))),
    );
  }
}
