import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Watch-time statistics, tracked exactly like the old app's player state:
/// a 5-second tick while a video plays is added to (a) a per-day bucket and
/// (b) a per-video total, both persisted locally. The Statistics screen
/// reads these back for the week chart, stat cards and "Most watched" list.

/// One day of watch time for the stats screen (old app's `WatchDay`).
@immutable
class WatchDay {
  final DateTime day;
  final int seconds;
  const WatchDay(this.day, this.seconds);
}

/// Pure persisted key for a day bucket, e.g. `stats.20260912`.
String statsKeyFor(DateTime d) =>
    'stats.${d.year * 10000 + d.month * 100 + d.day}';

/// The 7 day-buckets ending today (index 0 = 6 days ago, last = today).
/// Pure so the screen and the store agree on the window.
List<(DateTime, String)> weekBucketsFor(DateTime now) => [
      for (var i = 6; i >= 0; i--)
        (() {
          final d = now.subtract(Duration(days: i));
          return (DateTime(d.year, d.month, d.day), statsKeyFor(d));
        })(),
    ];

/// Compact watch-time totals for the stats screen ("2h 15m", "45m", "30s").
String formatWatchTime(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${m % 60}m';
}

/// A single "Most watched" entry: video path, accumulated seconds, and the
/// best-known display title (the title of the last session that played it).
@immutable
class WatchedVideo {
  final String path;
  final int seconds;
  final String title;
  const WatchedVideo(this.path, this.seconds, this.title);
}

class WatchStatsStore {
  WatchStatsStore._();

  static final WatchStatsStore instance = WatchStatsStore._();

  static const _kDay = 'watch.day.v1.'; // prefix + statsKeyFor(day)
  static const _kByVideo = 'watch.byvideo.v1';
  static const _kByVideoMax = 200;

  /// Add [seconds] of playback to today's bucket and to [path]'s total
  /// (remembering [title] for the "Most watched" list). Cheap: the day
  /// bucket is one int, the video map is trimmed to the heaviest entries.
  Future<void> recordPlay(int seconds,
      {required String path, String? title}) async {
    if (seconds <= 0 || path.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final dayKey = '$_kDay${statsKeyFor(now)}';
    final dayTotal = (prefs.getInt(dayKey) ?? 0) + seconds;
    await prefs.setInt(dayKey, dayTotal);

    final raw = prefs.getString(_kByVideo);
    var map = <String, int>{};
    if (raw != null) {
      try {
        map = (jsonDecode(raw) as Map).map(
            (k, v) => MapEntry(k as String, (v as num).toInt()));
      } catch (_) {
        map = {};
      }
    }
    map[path] = (map[path] ?? 0) + seconds;
    if (map.length > _kByVideoMax) {
      final sorted = map.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      map = {
        for (final e in sorted.take(_kByVideoMax)) e.key: e.value,
      };
    }
    await prefs.setString(_kByVideo, jsonEncode(map));

    if (title != null && title.isNotEmpty) {
      final tKey = '$_kByVideo.titles';
      var titles = <String, String>{};
      final rawT = prefs.getString(tKey);
      if (rawT != null) {
        try {
          titles = (jsonDecode(rawT) as Map)
              .map((k, v) => MapEntry(k as String, v as String));
        } catch (_) {
          titles = {};
        }
      }
      titles[path] = title;
      await prefs.setString(tKey, jsonEncode(titles));
    }
  }

  /// Last 7 days of watch time (index 0 = 6 days ago, last = today).
  Future<List<WatchDay>> weekStats() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    return [
      for (final (d, key) in weekBucketsFor(now))
        WatchDay(d, prefs.getInt('$_kDay$key') ?? 0),
    ];
  }

  /// Total watch seconds over the last [days] days (inclusive of today).
  Future<int> lastNDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    var total = 0;
    for (var i = days - 1; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      total += prefs.getInt('$_kDay${statsKeyFor(d)}') ?? 0;
    }
    return total;
  }

  /// Days IN A ROW with something watched (today counts when non-zero; the
  /// chain may start yesterday and still count).
  Future<int> streakDays() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    final todaySecs = prefs.getInt('$_kDay$todayKey') ?? 0;
    var streak = 0;
    var offset = todaySecs > 0 ? 0 : 1;
    while (true) {
      final d = now.subtract(Duration(days: offset));
      final secs = prefs.getInt('$_kDay${statsKeyFor(d)}') ?? 0;
      if (secs <= 0) break;
      streak++;
      offset++;
      if (offset > 3650) break;
    }
    return streak;
  }

  /// The [limit] most-watched videos (heaviest first).
  Future<List<WatchedVideo>> topWatched({int limit = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kByVideo);
    if (raw == null) return const [];
    Map<String, int> map;
    try {
      map = (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {
      return const [];
    }
    Map<String, String> titles = const {};
    final rawT = prefs.getString('$_kByVideo.titles');
    if (rawT != null) {
      try {
        titles = (jsonDecode(rawT) as Map)
            .map((k, v) => MapEntry(k as String, v as String));
      } catch (_) {
        titles = const {};
      }
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in entries.take(limit))
        WatchedVideo(e.key, e.value,
            titles[e.key] ?? e.key.split('/').last),
    ];
  }
}
