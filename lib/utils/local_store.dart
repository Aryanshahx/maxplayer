import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Unified local preference store: favorites, private-space ids & PIN,
/// playlists, and watch history. All device-local (local-first rule).

class RecentItem {
  const RecentItem({
    required this.id,
    required this.title,
    required this.path,
    required this.ts,
  });

  final String id;
  final String title;
  final String path;
  final int ts; // epoch millis

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'path': path, 'ts': ts};

  static RecentItem fromJson(Map<String, dynamic> j) => RecentItem(
        id: j['id'] as String,
        title: (j['title'] ?? 'Video') as String,
        path: (j['path'] ?? '') as String,
        ts: (j['ts'] as num).toInt(),
      );
}

/// Pure history upsert (unit-tested): newest first, dedupe by id, capped.
List<RecentItem> upsertRecent(List<RecentItem> list, RecentItem item,
    {int cap = 25}) {
  final out = [item, ...list.where((e) => e.id != item.id)];
  if (out.length > cap) out.removeRange(cap, out.length);
  return out;
}

/// Pure playlist toggle (unit-tested): returns new list.
List<String> toggleId(List<String> ids, String id) {
  final out = [...ids];
  out.contains(id) ? out.remove(id) : out.add(id);
  return out;
}

/// Pure playlist add (unit-tested): idempotent append.
List<String> addId(List<String> ids, String id) {
  if (ids.contains(id)) return [...ids];
  return [...ids, id];
}

String _join(Set<String> s) => jsonEncode(s.toList());

/// A named remote link (network share / cloud direct-link / stream URL).
class SavedLink {
  const SavedLink({required this.name, required this.url});

  final String name;
  final String url;

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory SavedLink.fromJson(Map<String, dynamic> m) => SavedLink(
      name: (m['name'] ?? 'Link') as String, url: (m['url'] ?? '') as String);
}

class LocalStore {
  static const _kFavorites = 'favorites.v1';
  static const _kPrivate = 'private.ids.v1';
  static const _kPin = 'private.pin.v1';
  static const _kPlaylists = 'playlists.v1';
  static const _kRecent = 'recent.v1';

  // ---------------- favorites ----------------

  Future<Set<String>> favorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFavorites);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// Returns true when now favorited.
  Future<bool> toggleFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = await favorites();
    final added = favs.add(id);
    if (!added) favs.remove(id);
    await prefs.setString(_kFavorites, _join(favs));
    return added;
  }

  // ---------------- private space ----------------

  Future<Set<String>> privateIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrivate);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// Returns true when now private.
  Future<bool> togglePrivate(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await privateIds();
    final added = ids.add(id);
    if (!added) ids.remove(id);
    await prefs.setString(_kPrivate, _join(ids));
    return added;
  }

  Future<String?> pin() async =>
      (await SharedPreferences.getInstance()).getString(_kPin);

  Future<void> setPin(String pin) async =>
      (await SharedPreferences.getInstance()).setString(_kPin, pin);

  /// Used by the device-password recovery flow (local_auth).
  Future<void> clearPin() async =>
      (await SharedPreferences.getInstance()).remove(_kPin);

  // ---- Private-folder vault PIN (SHA-256 hash, never the PIN itself) ----

  Future<String> vaultPinHash() async =>
      (await SharedPreferences.getInstance()).getString(_kPin) ?? '';

  Future<void> setVaultPinHash(String hash) async =>
      (await SharedPreferences.getInstance()).setString(_kPin, hash);

  Future<void> clearVaultPinHash() async =>
      (await SharedPreferences.getInstance()).remove(_kPin);

  // ---- raw string store (mirrors the old NativeBridge settings pair) ----

  /// Raw string under [key] ('' when absent / unreadable).
  Future<String> rawString(String key) async =>
      (await SharedPreferences.getInstance()).getString(key) ?? '';

  Future<void> setRawString(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  // ---------------- playlists ----------------

  Future<Map<String, List<String>>> playlists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPlaylists);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as List).cast<String>()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePlaylists(Map<String, List<String>> pl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPlaylists, jsonEncode(pl));
  }

  Future<bool> createPlaylist(String name) async {
    final pl = await playlists();
    if (pl.containsKey(name)) return false;
    pl[name] = [];
    await _savePlaylists(pl);
    return true;
  }

  Future<void> deletePlaylist(String name) async {
    final pl = await playlists()..remove(name);
    await _savePlaylists(pl);
  }

  /// Returns true when now present in the playlist.
  Future<bool> toggleInPlaylist(String name, String id) async {
    final pl = await playlists();
    if (!pl.containsKey(name)) return false;
    final before = pl[name]!.length;
    pl[name] = toggleId(pl[name]!, id);
    await _savePlaylists(pl);
    return pl[name]!.length > before;
  }

  /// Idempotent add: returns true only when [id] was newly appended.
  Future<bool> addToPlaylist(String name, String id) async {
    final pl = await playlists();
    if (!pl.containsKey(name)) return false;
    final before = pl[name]!.length;
    pl[name] = addId(pl[name]!, id);
    await _savePlaylists(pl);
    return pl[name]!.length > before;
  }

  // ---------------- history ----------------

  Future<List<RecentItem>> recent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRecent);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => RecentItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addRecent(RecentItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = upsertRecent(await recent(), item);
    await prefs.setString(
        _kRecent, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> clearRecent() async =>
      (await SharedPreferences.getInstance()).remove(_kRecent);

  // -------- saved links (Network Storage / Cloud Storage) --------

  static const _kNetworkLinks = 'network.links.v1';
  static const _kCloudLinks = 'cloud.links.v1';
  static const _kRecentStreams = 'streams.recent.v1';

  Future<List<SavedLink>> _links(String key) async {
    final raw =
        (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => SavedLink.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveLinks(String key, List<SavedLink> links) async =>
      (await SharedPreferences.getInstance())
          .setString(key, jsonEncode(links.map((e) => e.toJson()).toList()));

  Future<List<SavedLink>> networkLinks() => _links(_kNetworkLinks);
  Future<List<SavedLink>> cloudLinks() => _links(_kCloudLinks);

  Future<void> saveNetworkLink(SavedLink link) async {
    final list = await networkLinks()
      ..removeWhere((e) => e.url == link.url);
    await _saveLinks(_kNetworkLinks, [link, ...list]);
  }

  Future<void> saveCloudLink(SavedLink link) async {
    final list = await cloudLinks()
      ..removeWhere((e) => e.url == link.url);
    await _saveLinks(_kCloudLinks, [link, ...list]);
  }

  Future<void> deleteNetworkLink(String url) async {
    final list = await networkLinks()
      ..removeWhere((e) => e.url == url);
    await _saveLinks(_kNetworkLinks, list);
  }

  Future<void> deleteCloudLink(String url) async {
    final list = await cloudLinks()..removeWhere((e) => e.url == url);
    await _saveLinks(_kCloudLinks, list);
  }

  /// Recent direct-stream URLs (Open Stream / IPTV), newest first, max 20.
  Future<List<SavedLink>> recentStreams() => _links(_kRecentStreams);

  Future<void> addRecentStream(SavedLink link) async {
    final list = (await recentStreams()
      ..removeWhere((e) => e.url == link.url));
    await _saveLinks(_kRecentStreams, [link, ...list].take(20).toList());
  }

  Future<void> deleteRecentStream(String url) async {
    final list = (await recentStreams())
      ..removeWhere((e) => e.url == url);
    await _saveLinks(_kRecentStreams, list);
  }

  /// Remove an id from everywhere (used after system-consent delete).
  Future<void> scrubId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = await favorites()..remove(id);
    final priv = await privateIds()..remove(id);
    await prefs.setString(_kFavorites, _join(favs));
    await prefs.setString(_kPrivate, _join(priv));
    final pl = await playlists();
    for (final k in pl.keys.toList()) {
      pl[k] = pl[k]!..remove(id);
    }
    await _savePlaylists(pl);
    final rec = (await recent())..removeWhere((e) => e.id == id);
    await prefs.setString(
        _kRecent, jsonEncode(rec.map((e) => e.toJson()).toList()));
  }
}
