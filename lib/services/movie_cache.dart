/// v43 Discover: on-disk cache for movie JSON and poster images.
///
/// Two jobs:
///  1. **Instant + offline UI** - every rail is written to disk, so opening
///     Discover paints immediately from the cache and then quietly refreshes
///     (stale-while-revalidate). With no network at all, the last catalogue
///     still shows, marked "offline".
///  2. **Politeness + data saving** - a phone that opens the app ten times a
///     day makes at most one request per rail per TTL, not ten.
///
/// Everything lives in the app CACHE dir (`<cache>/movies/`), so Android may
/// evict it under storage pressure, the Cleaner can wipe it, and it is never
/// backed up.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/native_bridge.dart';
import '../utils/sha256.dart';

/// A cache hit plus its age, so callers can decide "fresh enough?".
class CachedJson {
  final Map<String, Object?> data;
  final DateTime savedAt;

  const CachedJson(this.data, this.savedAt);

  Duration ageFrom(DateTime now) => now.difference(savedAt);

  bool isFresh(Duration ttl, {DateTime? now}) =>
      ageFrom(now ?? DateTime.now()) < ttl;
}

/// Pure helper: should we hit the network for an entry saved [age] ago?
/// [force] (pull-to-refresh) always wins; a missing entry always fetches.
bool shouldRefresh({
  required Duration? age,
  required Duration ttl,
  bool force = false,
}) {
  if (force) return true;
  if (age == null) return true;
  return age >= ttl;
}

class MovieCache {
  static const String folder = 'movies';

  /// Hard cap for cached poster images; the oldest are dropped past this.
  static const int maxImageBytes = 80 * 1024 * 1024;

  Directory? _root;
  Future<Directory?>? _rootFuture;

  /// Serialises image downloads so a fast scroll cannot open 40 sockets on
  /// a budget phone. 4 at a time is plenty for a poster rail.
  static const int maxParallelImages = 4;
  int _inFlight = 0;
  final List<Completer<void>> _waiting = <Completer<void>>[];

  /// Overridable for tests (no method channel there).
  static Future<String?> Function() cacheDirProvider =
      NativeBridge.cacheDirPath;

  Future<Directory?> _ensureRoot() {
    final existing = _rootFuture;
    if (existing != null) return existing;
    final f = () async {
      try {
        final base = await cacheDirProvider();
        if (base == null || base.isEmpty) return null;
        final dir = Directory('$base/$folder');
        if (!await dir.exists()) await dir.create(recursive: true);
        final json = Directory('${dir.path}/json');
        if (!await json.exists()) await json.create(recursive: true);
        final img = Directory('${dir.path}/img');
        if (!await img.exists()) await img.create(recursive: true);
        _root = dir;
        return dir;
      } catch (_) {
        return null;
      }
    }();
    _rootFuture = f;
    return f;
  }

  /// Cache file name for a logical key ('rail:trending:1', an image URL...).
  static String fileNameFor(String key) => '${sha256Hex(key)}.json';

  Future<CachedJson?> readJson(String key) async {
    final root = await _ensureRoot();
    if (root == null) return null;
    try {
      final f = File('${root.path}/json/${fileNameFor(key)}');
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, Object?>();
      final savedMs = map['saved_at'];
      final payload = map['data'];
      if (payload is! Map) return null;
      final saved = DateTime.fromMillisecondsSinceEpoch(
        savedMs is int ? savedMs : 0,
      );
      return CachedJson(payload.cast<String, Object?>(), saved);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, Map<String, Object?> data) async {
    final root = await _ensureRoot();
    if (root == null) return;
    try {
      final f = File('${root.path}/json/${fileNameFor(key)}');
      await f.writeAsString(jsonEncode(<String, Object?>{
        'saved_at': DateTime.now().millisecondsSinceEpoch,
        'key': key,
        'data': data,
      }));
    } catch (_) {
      // A full disk must never break browsing.
    }
  }

  // -------------------------------------------------------------------
  // Images
  // -------------------------------------------------------------------

  /// Local file for an image URL - already downloaded or null.
  Future<File?> cachedImage(String url) async {
    final root = await _ensureRoot();
    if (root == null) return null;
    final f = File('${root.path}/img/${sha256Hex(url)}.img');
    try {
      if (await f.exists() && await f.length() > 0) return f;
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _acquireSlot() async {
    if (_inFlight < maxParallelImages) {
      _inFlight++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
    _inFlight++;
  }

  void _releaseSlot() {
    _inFlight--;
    if (_waiting.isNotEmpty) {
      final c = _waiting.removeAt(0);
      if (!c.isCompleted) c.complete();
    }
  }

  /// Downloads [url] into the cache (or returns the existing file).
  /// Never throws: a missing poster just renders the placeholder.
  Future<File?> downloadImage(String url) async {
    final hit = await cachedImage(url);
    if (hit != null) return hit;
    final root = await _ensureRoot();
    if (root == null) return null;

    await _acquireSlot();
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final bytes = await consolidateBytes(res);
      if (bytes.isEmpty) return null;
      final tmp = File('${root.path}/img/${sha256Hex(url)}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      final target = File('${root.path}/img/${sha256Hex(url)}.img');
      await tmp.rename(target.path);
      return target;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
      _releaseSlot();
    }
  }

  static Future<List<int>> consolidateBytes(Stream<List<int>> stream) async {
    final out = <int>[];
    await for (final chunk in stream) {
      out.addAll(chunk);
    }
    return out;
  }

  // -------------------------------------------------------------------
  // Housekeeping (wired into the Cleaner sheet)
  // -------------------------------------------------------------------

  Future<int> sizeBytes() async {
    final root = _root ?? await _ensureRoot();
    if (root == null) return 0;
    var total = 0;
    try {
      await for (final e in root.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {
            // File vanished mid-walk; ignore.
          }
        }
      }
    } catch (_) {
      return total;
    }
    return total;
  }

  /// Deletes every cached poster + JSON. Returns bytes freed.
  Future<int> clear() async {
    final root = _root ?? await _ensureRoot();
    if (root == null) return 0;
    final before = await sizeBytes();
    try {
      await root.delete(recursive: true);
    } catch (_) {
      return 0;
    }
    _root = null;
    _rootFuture = null;
    return before;
  }

  /// Drops the oldest images once the image cache passes [maxImageBytes].
  Future<void> pruneImages() async {
    final root = _root ?? await _ensureRoot();
    if (root == null) return;
    try {
      final dir = Directory('${root.path}/img');
      if (!await dir.exists()) return;
      final files = <File>[];
      await for (final e in dir.list(followLinks: false)) {
        if (e is File) files.add(e);
      }
      var total = 0;
      final sizes = <String, int>{};
      final stamps = <String, DateTime>{};
      for (final f in files) {
        try {
          final st = await f.stat();
          sizes[f.path] = st.size;
          stamps[f.path] = st.modified;
          total += st.size;
        } catch (_) {
          // ignore
        }
      }
      if (total <= maxImageBytes) return;
      files.sort((a, b) {
        final da = stamps[a.path] ?? DateTime(1970);
        final db = stamps[b.path] ?? DateTime(1970);
        return da.compareTo(db); // oldest first
      });
      for (final f in files) {
        if (total <= maxImageBytes) break;
        final size = sizes[f.path] ?? 0;
        try {
          await f.delete();
          total -= size;
        } catch (_) {
          // ignore
        }
      }
    } catch (_) {
      // Best effort only.
    }
  }
}

/// One cache for the whole app (mirrors `playlistStore` / `themeState`).
final MovieCache movieCache = MovieCache();
