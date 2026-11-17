import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DesktopStore {
  final favourites = <String>[];
  final history = <String>[];
  final playlists = <String, List<String>>{};
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final root = jsonDecode(prefs.getString('hyper.collections.v1') ?? '{}');
      if (root is! Map) { return; }
      List<String> strings(dynamic value) => value is List ? value.whereType<String>().toList() : [];
      favourites.addAll(strings(root['favourites']));
      history.addAll(strings(root['history']));
      final lists = root['playlists'];
      if (lists is Map) {
        for (final entry in lists.entries) {
          if (entry.key is String) { playlists[entry.key as String] = strings(entry.value); }
        }
      }
    } catch (_) { /* Invalid saved data must not prevent startup. */ }
  }
  Future<void> save() async {
    final json = jsonEncode({'favourites': favourites, 'history': history, 'playlists': playlists});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hyper.collections.v1', json);
  }
  Future<void> record(String source) async {
    history.remove(source);
    history.insert(0, source);
    if (history.length > 300) { history.removeRange(300, history.length); }
    await save();
  }
}

/// Parses plain M3U entries, resolving relative URLs/files against a base URI.
/// HLS manifests represent one stream, not a collection of channels.
List<String> parseM3u(String text, Uri base) {
  if (text.contains('#EXT-X-')) {
    throw const FormatException('This is an HLS manifest. Open its URL as one stream instead.');
  }
  final entries = <String>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.replaceFirst('\uFEFF', '').trim();
    if (line.isEmpty || line.startsWith('#')) { continue; }
    final Uri uri;
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(line)) {
      uri = Uri.file(line, windows: true);
    } else {
      uri = base.resolve(line);
    }
    if (!['http', 'https', 'file'].contains(uri.scheme)) { continue; }
    entries.add(uri.scheme == 'file' ? uri.toFilePath(windows: true) : uri.toString());
    if (entries.length >= 10000) { break; }
  }
  return entries;
}
