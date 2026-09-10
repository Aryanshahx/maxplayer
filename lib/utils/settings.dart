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

  ViewMode viewMode = ViewMode.grid;
  SortField sortField = SortField.name;
  bool sortAsc = true; // A → Z by default (design reference)
  GroupBy groupBy = GroupBy.none;
  bool queueAll = true; // "Queue All" playback action
  bool onlyFavs = false;
  int accentIndex = defaultAccentIndex;

  Color get accentColor => accentPalette[accentIndex];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    int clampIdx(int? v, int max, int fallback) =>
        (v ?? fallback).clamp(0, max).toInt();
    viewMode =
        ViewMode.values[clampIdx(p.getInt(_kViewMode), ViewMode.values.length - 1, 0)];
    sortField = SortField
        .values[clampIdx(p.getInt(_kSortField), SortField.values.length - 1, 0)];
    sortAsc = p.getBool(_kSortAsc) ?? true;
    groupBy = GroupBy
        .values[clampIdx(p.getInt(_kGroupBy), GroupBy.values.length - 1, 0)];
    queueAll = p.getBool(_kQueueAll) ?? true;
    onlyFavs = p.getBool(_kOnlyFavs) ?? false;
    accentIndex =
        clampIdx(p.getInt(_kAccent), accentPalette.length - 1, defaultAccentIndex);
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

  void setAccentIndex(int i) {
    accentIndex = i;
    _set((p) => p.setInt(_kAccent, i));
  }
}
