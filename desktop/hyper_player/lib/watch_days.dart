import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

String dayKey(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, "0")}-${value.day.toString().padLeft(2, "0")}';
String watchTime(int seconds) {
  if (seconds < 60) {
    return '${seconds}s';
  }
  if (seconds < 3600) {
    return '${seconds ~/ 60}m';
  }
  return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}

class WatchDays extends ChangeNotifier {
  final days = <String, int>{};
  final titles = <String, int>{};
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final root = jsonDecode(prefs.getString('hyper.watch.days.v1') ?? '{}');
      if (root is! Map) {
        return;
      }
      void read(dynamic value, Map<String, int> target) {
        if (value is Map) {
          for (final entry in value.entries) {
            if (entry.key is String &&
                entry.value is int &&
                (entry.value as int) >= 0) {
              target[entry.key as String] = entry.value as int;
            }
          }
        }
      }

      read(root['days'], days);
      read(root['titles'], titles);
    } catch (_) {/* Corrupt statistics do not prevent playback. */}
  }

  void record(DateTime now, String title) {
    final key = dayKey(now);
    days[key] = (days[key] ?? 0) + 1;
    titles[title] = (titles[title] ?? 0) + 1;
    if (days.length > 366) {
      final keys = days.keys.toList()..sort();
      for (final old in keys.take(keys.length - 366)) {
        days.remove(old);
      }
    }
    if (titles.length > 100) {
      final ordered = titles.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      titles.remove(ordered.first.key);
    }
    notifyListeners();
  }

  List<DateTime> dates(DateTime now, int count) => List.generate(
      count, (i) => DateTime(now.year, now.month, now.day - count + i + 1));
  int total(DateTime now, int count) =>
      dates(now, count).fold(0, (sum, day) => sum + (days[dayKey(day)] ?? 0));
  int streak(DateTime now) {
    var day = DateTime(now.year, now.month, now.day);
    if ((days[dayKey(day)] ?? 0) == 0) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    int count = 0;
    while ((days[dayKey(day)] ?? 0) > 0 && count < 366) {
      count++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return count;
  }

  Future<void> save() async {
    final snapshot = jsonEncode({'days': days, 'titles': titles});
    await (await SharedPreferences.getInstance())
        .setString('hyper.watch.days.v1', snapshot);
  }
}
