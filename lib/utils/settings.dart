import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display & behavior settings, persisted locally, reactive app-wide.

enum ViewMode { grid, list }

enum SortField { name, dateAdded, size, length }

enum GroupBy { none, folder }

/// Accent palette shown in Display Settings (order matches the design).
const accentPalette = <Color>[
  Color(0xFFFFFFFF), // white (default)
  Color(0xFF8B5CF6), // purple
  Color(0xFF22D3EE), // cyan
  Color(0xFF34D399), // green
  Color(0xFFFB923C), // orange
  Color(0xFFF472B6), // pink
  Color(0xFF3D6BFF), // blue
];

const defaultAccentIndex = 0;

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const _kViewMode = 'disp.viewMode';
  static const _kSortField = 'disp.sortField';
  static const _kSortAsc = 'disp.sortAsc';
  static const _kGroupBy = 'disp.groupBy';
  static const _kQueueAll = 'disp.queueAll';
  static const _kOnlyFavs = 'disp.onlyFavs';
  static const _kAccent = 'disp.accent';
  static const _kCustomAccent = 'disp.customAccent.v1';
  Color? customAccent;
  static const _kThemeMode = 'disp.themeMode.v1';
  ThemeMode themeMode = ThemeMode.system;

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    await _set((p) => p.setString(_kThemeMode, value.name));
  }

  ViewMode viewMode = ViewMode.grid;
  SortField sortField = SortField.name;
  bool sortAsc = true; // A → Z by default (design reference)
  GroupBy groupBy = GroupBy.none;
  bool queueAll = true; // "Queue All" playback action
  bool onlyFavs = false;
  int accentIndex = defaultAccentIndex;

  Color get accentColor => customAccent ?? accentPalette[accentIndex];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final savedColor = p.getInt(_kCustomAccent);
    customAccent = savedColor == null ? null : Color(savedColor | 0xFF000000);
    final savedTheme = p.getString(_kThemeMode);
    themeMode =
        ThemeMode.values.where((v) => v.name == savedTheme).firstOrNull ??
        ThemeMode.system;
    int clampIdx(int? v, int max, int fallback) =>
        (v ?? fallback).clamp(0, max).toInt();
    viewMode = ViewMode
        .values[clampIdx(p.getInt(_kViewMode), ViewMode.values.length - 1, 0)];
    sortField =
        SortField.values[clampIdx(
          p.getInt(_kSortField),
          SortField.values.length - 1,
          0,
        )];
    sortAsc = p.getBool(_kSortAsc) ?? true;
    groupBy = GroupBy
        .values[clampIdx(p.getInt(_kGroupBy), GroupBy.values.length - 1, 0)];
    queueAll = p.getBool(_kQueueAll) ?? true;
    onlyFavs = p.getBool(_kOnlyFavs) ?? false;
    accentIndex = clampIdx(
      p.getInt(_kAccent),
      accentPalette.length - 1,
      defaultAccentIndex,
    );
  }

  Future<void> _set(Future<bool> Function(SharedPreferences p) write) async {
    await write(await SharedPreferences.getInstance());
    notifyListeners();
  }

  void setViewMode(ViewMode v) {
    viewMode = v;
    _set((p) => p.setInt(_kViewMode, v.index));
  }

  void setSortField(SortField f) {
    sortField = f;
    _set((p) => p.setInt(_kSortField, f.index));
  }

  void setSortAsc(bool a) {
    sortAsc = a;
    _set((p) => p.setBool(_kSortAsc, a));
  }

  void setGroupBy(GroupBy g) {
    groupBy = g;
    _set((p) => p.setInt(_kGroupBy, g.index));
  }

  void setQueueAll(bool q) {
    queueAll = q;
    _set((p) => p.setBool(_kQueueAll, q));
  }

  void setOnlyFavs(bool o) {
    onlyFavs = o;
    _set((p) => p.setBool(_kOnlyFavs, o));
  }

  Future<void> setCustomAccent(Color color) async {
    final opaque = color.withValues(alpha: 1);
    customAccent = opaque;
    notifyListeners();
    await _set((p) => p.setInt(_kCustomAccent, opaque.toARGB32()));
  }

  void setAccentIndex(int i) {
    accentIndex = i.clamp(0, accentPalette.length - 1);
    customAccent = null;
    _set((p) async {
      await p.remove(_kCustomAccent);
      return p.setInt(_kAccent, accentIndex);
    });
  }
}
