import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only history, capped per category. Never use for PINs/URLs/passwords.
class RecentSearches {
  static const limit = 3;
  static const prefix = 'search.recent.v1.';
  static final revision = ValueNotifier<int>(0);
  static final Map<String, int> _cleared = {};
  static int generation(String scope) => _cleared[scope] ?? 0;
  static List<String> prepend(List<String> values, String query) {
    final text = query.trim();
    if (text.isEmpty || text.length > 128) return values.take(limit).toList();
    return [
      text,
      ...values.where((v) => v.toLowerCase() != text.toLowerCase()),
    ].take(limit).toList();
  }

  static Future<List<String>> load(String scope) async =>
      ((await SharedPreferences.getInstance()).getStringList('$prefix$scope') ??
              [])
          .take(limit)
          .toList();
  static Future<void> _write(String scope, List<String> values) async {
    await (await SharedPreferences.getInstance()).setStringList(
      '$prefix$scope',
      values.take(limit).toList(),
    );
    revision.value++;
  }

  static Future<void> save(String scope, List<String> values) =>
      _write(scope, values);
  static Future<void> record(
    String scope,
    String value,
    int generationAtEdit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (generationAtEdit != generation(scope) || value.trim().isEmpty) return;
    // Read and update the preferences cache without an await in between.
    // Concurrent fields therefore see each other's latest local value.
    final values = prefs.getStringList('$prefix$scope') ?? [];
    await prefs.setStringList('$prefix$scope', prepend(values, value));
    revision.value++;
  }

  static Future<void> clear(String scope) async {
    _cleared[scope] = generation(scope) + 1;
    await _write(scope, []);
  }
}
