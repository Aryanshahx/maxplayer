import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../services/native_bridge.dart';

/// Appends [added] paths to [existing], skipping duplicates and keeping the
/// original order. Never mutates the input list. Top-level + pure so the
/// widget test can pin the behavior.
List<String> mergePlaylistPaths(List<String> existing, Iterable<String> added) {
  final out = List<String>.of(existing);
  final seen = existing.toSet();
  for (final p in added) {
    if (seen.add(p)) out.add(p);
  }
  return out;
}

/// Validates a playlist name typed by the user; null means OK.
/// Top-level + pure for the widget test.
String? validatePlaylistName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return 'Enter a name';
  if (name.length > 40) return 'Name is too long (max 40 characters)';
  return null;
}

/// v40: the store of NAMED, persistent playlists.
///
/// Lives next to the anonymous play queue (MediaPlayerState.playlist is
/// still "what is playing right now"); playlists are the saved shelves the
/// user fills by name - "add multiple playlists by names". Persisted as one
/// JSON string in the app's settings store (the same SharedPreferences
/// channel every other setting uses - zero new dependencies), so they
/// survive app restarts, phone reboots and updates.
class PlaylistStore extends ChangeNotifier {
  /// Settings key for the JSON-encoded playlist list. v1: bump on a
  /// breaking format change.
  static const String settingsKey = 'playlists.v1';

  List<Playlist> _playlists = [];

  /// True once the first load from disk finished (the sheet reads this to
  /// avoid showing an empty state for a split second on app start).
  bool loaded = false;

  /// Set when the user edited before the first load returned - those edits
  /// win over the on-disk copy and are written back right away.
  bool _dirty = false;
  bool _disposed = false;

  List<Playlist> get playlists => List.unmodifiable(_playlists);

  PlaylistStore() {
    _load();
  }

  Playlist? byId(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _load() async {
    var parsed = <Playlist>[];
    try {
      final s = await NativeBridge.loadSettings();
      final raw = s[settingsKey];
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          parsed = [
            for (final e in list)
              if (e is Map) Playlist.fromJson(e.cast<String, Object?>()),
          ];
        }
      }
    } catch (_) {
      parsed = const [];
    }
    if (_dirty) {
      // User managed to edit before load finished - persist THEIR version.
      unawaited(_persist());
    } else {
      _playlists = parsed;
    }
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist() =>
      NativeBridge.saveSetting(settingsKey, jsonEncode([for (final p in _playlists) p.toJson()]));

  void _set(List<Playlist> next) {
    _dirty = true;
    _playlists = next;
    if (!_disposed) notifyListeners();
    unawaited(_persist());
  }

  /// Creates a new named playlist and returns it.
  Playlist create(String name) {
    final pl = Playlist(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      videoPaths: const [],
    );
    _set([..._playlists, pl]);
    return pl;
  }

  void rename(String id, String name) {
    _set([
      for (final p in _playlists)
        if (p.id == id) p.copyWith(name: name.trim()) else p,
    ]);
  }

  void delete(String id) {
    _set([for (final p in _playlists) if (p.id != id) p]);
  }

  /// Adds video paths to a playlist (duplicates skipped, order kept).
  void addVideos(String id, Iterable<String> paths) {
    _set([
      for (final p in _playlists)
        if (p.id == id) p.copyWith(videoPaths: mergePlaylistPaths(p.videoPaths, paths)) else p,
    ]);
  }

  void removeVideo(String id, String path) {
    _set([
      for (final p in _playlists)
        if (p.id == id)
          p.copyWith(videoPaths: [for (final v in p.videoPaths) if (v != path) v])
        else
          p,
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// App-wide singleton (mirrors `themeState` in theme_state.dart): one store
/// for the whole app, loading from disk as soon as the import is evaluated.
final playlistStore = PlaylistStore();
