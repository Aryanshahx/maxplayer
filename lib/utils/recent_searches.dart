import 'package:shared_preferences/shared_preferences.dart';

/// Local-only, separate contexts. Never use for passwords, URLs or Private Space.
class RecentSearches {
  static const limit = 3;
  static const prefix = 'search.recent.v1.';
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
  static Future<void> save(String scope, List<String> values) async {
    await (await SharedPreferences.getInstance()).setStringList(
      '$prefix$scope',
      values.take(limit).toList(),
    );
  }
}
