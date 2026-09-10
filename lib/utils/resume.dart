import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kResumeKey = 'resume.positions.v1';
const minPromptMs = 10000; // positions under 10s: not worth prompting
const endMarginMs = 10000; // last 10s of a video counts as "finished"

/// Pure resume decision (unit-tested).
///
/// Returns the position to offer resuming at, or null to start from 0.
/// [savedMs] was persisted earlier; [durationMs] may be 0 when unknown.
int? resumeTargetMs(int savedMs, int durationMs) {
  if (savedMs < minPromptMs) return null;
  if (durationMs > 0 && savedMs > durationMs - endMarginMs) return null;
  return savedMs;
}

/// Pure finish check (unit-tested): position within the end margin?
bool isFinishedMs(int posMs, int durationMs) {
  return durationMs > 0 && posMs > durationMs - endMarginMs;
}

/// Per-path last-watch positions, persisted in shared_preferences as a
/// JSON map. Survives process kill (written periodically + on pause +
/// on background + on player dispose).
class ResumeStore {
  Future<Map<String, int>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kResumeKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {}; // corrupt blob -> start empty, never crash
    }
  }

  Future<int?> readMs(String path) async => (await _readAll())[path];

  Future<void> writeMs(String path, int ms) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll();
    all[path] = ms;
    await prefs.setString(_kResumeKey, jsonEncode(all));
  }

  Future<void> clear(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll()..remove(path);
    await prefs.setString(_kResumeKey, jsonEncode(all));
  }
}
