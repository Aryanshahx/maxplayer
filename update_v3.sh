#!/usr/bin/env bash
# ============================================================
#  update_v3.sh — MaxPlayer v0.4.0+4: THE HOME DROP
#
#  Home redesign (from your old-app screenshot) + feature pack:
#    • Gradient "Max Player" header + "Proudly Developed in India"
#      top icons: Search / Refresh / History / About
#    • Tiles: Folders, Playlists, Private Space, History
#    • Continue Watching row (resume points, tap to continue)
#    • Cards: resolution badge (720p/1080p/2K/4K), duration,
#      favorite heart, delete bin (system-consent delete),
#      file size; long-press -> Add to playlist / Private /
#      Properties / Delete
#    • Favorites filter chip, search-as-you-type
#    • Folders view, local Playlists (create/add/browse/play),
#      PIN-locked Private Space, History (last 25)
#    • 13 new pin tests (32 total)
#
#  USAGE (project folder with v1/v2 applied):
#    bash update_v3.sh
#    git add -A && git commit -m "v0.4: home drop" && git push
# ============================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f pubspec.yaml ] || { echo "ERROR: no project here - apply update_v1.sh first."; exit 1; }
echo ">> Writing v0.4 files ..."
mkdir -p "$(dirname "pubspec.yaml")"
cat > "pubspec.yaml" <<'MP_EOF_pubspec_yaml'
name: maxplayer
description: "MaxPlayer — local-first MPV video player."
# The following line prevents the package from being accidentally published to
# pub.dev using `flutter pub publish`. This is preferred for private packages.
publish_to: 'none' # Remove this line if you wish to publish to pub.dev

# The following defines the version and build number for your application.
# A version number is three numbers separated by dots, like 1.2.43
# followed by an optional build number separated by a +.
# Both the version and the builder number may be overridden in flutter
# build by specifying --build-name and --build-number, respectively.
# In Android, build-name is used as versionName while build-number used as versionCode.
# Read more about Android versioning at https://developer.android.com/studio/publish/versioning
# In iOS, build-name is used as CFBundleShortVersionString while build-number is used as CFBundleVersion.
# Read more about iOS versioning at
# https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
# In Windows, build-name is used as the major, minor, and patch parts
# of the product and file versions while build-number is used as the build suffix.
version: 0.4.0+4

environment:
  sdk: ^3.12.0

# Dependencies specify other packages that your package needs in order to work.
# To automatically upgrade your package dependencies to the latest versions
# consider running `flutter pub upgrade --major-versions`. Alternatively,
# dependencies can be manually updated by changing the version numbers below to
# the latest version available on pub.dev. To see which dependencies have newer
# versions available, run `flutter pub outdated`.
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  # Use with the CupertinoIcons class for iOS style icons.
  cupertino_icons: ^1.0.8
  media_kit: ^1.2.6
  media_kit_video: ^2.0.1
  media_kit_libs_video: ^1.0.7
  shared_preferences: ^2.5.5
  path_provider: ^2.1.6
  photo_manager: ^3.12.0
  wakelock_plus: ^1.8.0

dev_dependencies:
  flutter_test:
    sdk: flutter

  # The "flutter_lints" package below contains a set of recommended lints to
  # encourage good coding practices. The lint set provided by the package is
  # activated in the `analysis_options.yaml` file located at the root of your
  # package. See that file for information about deactivating specific lint
  # rules and activating additional ones.
  flutter_lints: ^6.0.0

# For information on the generic Dart part of this file, see the
# following page: https://dart.dev/tools/pub/pubspec

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
  #   - images/a_dot_ham.jpeg

  # An image asset can refer to one or more resolution-specific "variants", see
  # https://flutter.dev/to/resolution-aware-images

  # For details regarding adding assets from package dependencies, see
  # https://flutter.dev/to/asset-from-package

  # To add custom fonts to your application, add a fonts section here,
  # in this "flutter" section. Each entry in this list should have a
  # "family" key with the font family name, and a "fonts" key with a
  # list giving the asset and other descriptors for the font. For
  # example:
  # fonts:
  #   - family: Schyler
  #     fonts:
  #       - asset: fonts/Schyler-Regular.ttf
  #       - asset: fonts/Schyler-Italic.ttf
  #         style: italic
  #   - family: Trajan Pro
  #     fonts:
  #       - asset: fonts/TrajanPro.ttf
  #       - asset: fonts/TrajanPro_Bold.ttf
  #         weight: 700
  #
  # For details regarding fonts from package dependencies,
  # see https://flutter.dev/to/font-from-package
MP_EOF_pubspec_yaml
mkdir -p "$(dirname "lib/utils/local_store.dart")"
cat > "lib/utils/local_store.dart" <<'MP_EOF_lib_utils_local_store_dart'
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

String _join(Set<String> s) => jsonEncode(s.toList());

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
MP_EOF_lib_utils_local_store_dart
mkdir -p "$(dirname "lib/utils/badges.dart")"
cat > "lib/utils/badges.dart" <<'MP_EOF_lib_utils_badges_dart'
/// Pure quality-badge mapping (unit-tested): from video dimensions to a
/// short label shown on cards. Uses the SHORT side so portrait 1080x1920
/// and landscape 1920x1080 both read "1080p".
String qualityBadge(int width, int height) {
  final s = width < height ? width : height;
  if (s >= 2160) return '4K';
  if (s >= 1440) return '2K';
  if (s >= 1080) return '1080p';
  if (s >= 720) return '720p';
  if (s >= 480) return '480p';
  return 'SD';
}
MP_EOF_lib_utils_badges_dart
mkdir -p "$(dirname "lib/widgets/video_grid.dart")"
cat > "lib/widgets/video_grid.dart" <<'MP_EOF_lib_widgets_video_grid_dart'
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../screens/player_screen.dart';
import '../theme.dart';
import '../utils/badges.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';
import '../utils/local_store.dart';
import '../utils/resume.dart';

/// Shared 2-column video card grid used by Home, Folders, Playlists,
/// Private Space and History. Cards carry: thumbnail, quality badge,
/// duration, favorite heart, delete bin, title, size.
class VideoGrid extends StatefulWidget {
  const VideoGrid({
    super.key,
    required this.videos,
    required this.onChanged,
    this.onOpen,
  });

  final List<AssetEntity> videos;

  /// Called after any mutating action (fav/private/delete) so parents can
  /// re-filter/refresh.
  final VoidCallback onChanged;

  /// Optional custom tap handler (defaults to guarded play).
  final void Function(AssetEntity asset)? onOpen;

  /// Guarded open used everywhere a video starts (non-negotiable #2):
  /// resolves the file, records history, navigates — or says why not.
  static Future<void> openVideo(BuildContext context, AssetEntity asset,
      {LocalStore? store, ResumeStore? resumeStore}) async {
    CrashLog.crumb('video.tap', {'id': asset.id, 'title': asset.title});
    try {
      final file = await asset.file;
      if (!context.mounted) return;
      if (file == null || !file.existsSync()) {
        throw StateError('video file unavailable: ${asset.title}');
      }
      unawaited((store ?? LocalStore()).addRecent(RecentItem(
        id: asset.id,
        title: asset.title ?? 'Video',
        path: file.path,
        ts: DateTime.now().millisecondsSinceEpoch,
      )));
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
              path: file.path, title: asset.title ?? 'Video'),
        ),
      );
    } catch (e) {
      CrashLog.error('video.open_failed', e, {'id': asset.id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this video')),
        );
      }
    }
  }

  /// Delete with system consent (MediaStore delete dialog on Android 11+),
  /// then scrub the id from every local store + resume point.
  static Future<bool> deleteWithConsent(AssetEntity asset,
      {LocalStore? store, ResumeStore? resumeStore}) async {
    CrashLog.crumb('video.delete_request', {'id': asset.id});
    try {
      final path = (await asset.file)?.path;
      final deleted = await PhotoManager.editor.deleteWithIds([asset.id]);
      final ok = deleted.isNotEmpty;
      if (ok) {
        await (store ?? LocalStore()).scrubId(asset.id);
        if (path != null) await (resumeStore ?? ResumeStore()).clear(path);
        CrashLog.crumb('video.deleted', {'id': asset.id});
      }
      return ok;
    } catch (e) {
      CrashLog.error('video.delete_failed', e, {'id': asset.id});
      return false;
    }
  }

  @override
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  final _store = LocalStore();
  Set<String> _favs = {};
  Set<String> _priv = {};

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    final favs = await _store.favorites();
    final priv = await _store.privateIds();
    if (mounted) {
      setState(() {
        _favs = favs;
        _priv = priv;
      });
    }
  }

  Future<void> _toggleFav(AssetEntity a) async {
    await _store.toggleFavorite(a.id);
    await _loadFlags();
    widget.onChanged();
  }

  Future<void> _togglePrivate(AssetEntity a) async {
    final nowPrivate = await _store.togglePrivate(a.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nowPrivate ? 'Moved to Private Space' : 'Removed from Private Space'),
      ));
    }
    await _loadFlags();
    widget.onChanged();
  }

  Future<void> _confirmDelete(AssetEntity a) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Delete video?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Text(
          '"${a.title ?? 'This video'}" will be deleted from your device. '
          'Android will ask you to confirm.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final ok = await VideoGrid.deleteWithConsent(a, store: _store);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Deleted' : 'Delete cancelled or failed'),
      ));
    }
    widget.onChanged();
  }

  Future<void> _addToPlaylist(AssetEntity a) async {
    final pls = await _store.playlists();
    if (!mounted) return;
    if (pls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No playlists yet — create one from the Playlists tile')));
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Add to playlist',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            for (final name in pls.keys)
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded,
                    color: AppColors.accent),
                title: Text(name,
                    style: const TextStyle(color: AppColors.textPrimary)),
                trailing: Icon(
                  pls[name]!.contains(a.id)
                      ? Icons.check_circle_rounded
                      : Icons.add_circle_outline_rounded,
                  color: pls[name]!.contains(a.id)
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
                onTap: () => Navigator.of(context).pop(name),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final added = await _store.toggleInPlaylist(chosen, a.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added
              ? 'Added to "$chosen"'
              : 'Removed from "$chosen"')));
    }
    widget.onChanged();
  }

  void _properties(AssetEntity a) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(a.title ?? 'Video',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _prop('Resolution', '${a.width}×${a.height} (${qualityBadge(a.width, a.height)})'),
            _prop('Duration', formatDuration(Duration(seconds: a.duration))),
            _prop('Modified',
                '${a.modifiedDateTime.year}-${a.modifiedDateTime.month.toString().padLeft(2, '0')}-${a.modifiedDateTime.day.toString().padLeft(2, '0')}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _prop(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('$k:  $v',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );

  void _showActions(AssetEntity a) {
    final isPriv = _priv.contains(a.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(a.title ?? 'Video',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
            ),
            _sheetAction(Icons.playlist_add_rounded, 'Add to playlist', () {
              Navigator.of(context).pop();
              _addToPlaylist(a);
            }),
            _sheetAction(
              isPriv ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
              isPriv ? 'Remove from Private Space' : 'Move to Private Space',
              () {
                Navigator.of(context).pop();
                _togglePrivate(a);
              },
            ),
            _sheetAction(Icons.info_outline_rounded, 'Properties', () {
              Navigator.of(context).pop();
              _properties(a);
            }),
            _sheetAction(Icons.delete_outline_rounded, 'Delete', () {
              Navigator.of(context).pop();
              _confirmDelete(a);
            }, danger: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  ListTile _sheetAction(IconData icon, String label, VoidCallback onTap,
          {bool danger = false}) =>
      ListTile(
        leading: Icon(icon, color: danger ? AppColors.danger : AppColors.accent),
        title: Text(label,
            style: TextStyle(
                color: danger ? AppColors.danger : AppColors.textPrimary)),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.78,
      ),
      itemCount: widget.videos.length,
      itemBuilder: (context, i) {
        final a = widget.videos[i];
        return _VideoCard(
          asset: a,
          isFav: _favs.contains(a.id),
          onTap: () => (widget.onOpen ?? (x) => VideoGrid.openVideo(context, x, store: _store))(a),
          onLongPress: () => _showActions(a),
          onToggleFav: () => _toggleFav(a),
          onDelete: () => _confirmDelete(a),
        );
      },
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.asset,
    required this.isFav,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFav,
    required this.onDelete,
  });

  static final Map<String, Future<int>> _sizeCache = {};

  final AssetEntity asset;
  final bool isFav;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFav;
  final VoidCallback onDelete;

  Future<int> _sizeBytes() => _sizeCache.putIfAbsent(
      asset.id, () async => (await asset.file)?.length() ?? 0);

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: asset.thumbnailDataWithSize(
                        const ThumbnailSize(480, 480)),
                    builder: (context, snap) => snap.data == null
                        ? const ColoredBox(color: AppColors.surfaceAlt)
                        : Image.memory(snap.data!, fit: BoxFit.cover),
                  ),
                  // quality badge
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _Pill(
                      text: qualityBadge(asset.width, asset.height),
                      color: Colors.black.withValues(alpha: 0.65),
                      textColor: AppColors.textPrimary,
                    ),
                  ),
                  // duration
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _Pill(
                      text: formatDuration(Duration(seconds: asset.duration)),
                      color: Colors.black.withValues(alpha: 0.65),
                      textColor: AppColors.textPrimary,
                    ),
                  ),
                  // favorite
                  Positioned(
                    right: 4,
                    top: 4,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isFav ? AppColors.danger : Colors.white,
                        size: 20,
                      ),
                      onPressed: onToggleFav,
                    ),
                  ),
                  // delete
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.white, size: 20),
                      onPressed: onDelete,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.title ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  FutureBuilder<int>(
                    future: _sizeBytes(),
                    builder: (context, snap) => Text(
                      snap.hasData && snap.data! > 0
                          ? formatBytes(snap.data!)
                          : ' ',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.text, required this.color, required this.textColor});

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, color: textColor, fontWeight: FontWeight.w600)),
    );
  }
}
MP_EOF_lib_widgets_video_grid_dart
mkdir -p "$(dirname "lib/screens/library_screen.dart")"
cat > "lib/screens/library_screen.dart" <<'MP_EOF_lib_screens_library_screen_dart'
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../utils/resume.dart';
import '../widgets/video_grid.dart';
import 'folders_screen.dart';
import 'history_screen.dart';
import 'playlists_screen.dart';
import 'private_screen.dart';

/// Home — the Max Player face: gradient header + tagline, tool tiles
/// (Folders / Playlists / Private Space / History), Continue Watching row,
/// searchable, favorite-filterable video grid.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _Filter { all, favorites }

class _LibraryScreenState extends State<LibraryScreen> {
  static const _pageSize = 60;

  final _store = LocalStore();
  final _resume = ResumeStore();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _denied = false;
  bool _searching = false;
  String _query = '';
  _Filter _filter = _Filter.all;

  final List<AssetEntity> _videos = [];
  AssetPathEntity? _allPath;
  int _page = 0;
  bool _exhausted = false;

  Set<String> _favs = {};
  Set<String> _priv = {};
  List<RecentItem> _recent = [];
  Map<String, int> _resumePoints = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) {
        CrashLog.crumb('library.permission_denied');
        setState(() {
          _loading = false;
          _denied = true;
        });
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
          type: RequestType.video, onlyAll: true);
      _allPath = paths.isEmpty ? null : paths.first;
      _page = 0;
      _videos.clear();
      _exhausted = false;
      await _loadMore();
      await _loadMeta();
      CrashLog.crumb('library.scanned', {'count': _videos.length});
    } catch (e) {
      CrashLog.error('library.scan_failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not scan videos on this device')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMeta() async {
    final favs = await _store.favorites();
    final priv = await _store.privateIds();
    final recent = await _store.recent();
    // resume points for the continue-watching row
    final points = <String, int>{};
    for (final r in recent) {
      final ms = await _resume.readMs(r.path);
      if (ms != null && ms >= minPromptMs) points[r.id] = ms;
    }
    if (mounted) {
      setState(() {
        _favs = favs;
        _priv = priv;
        _recent = recent;
        _resumePoints = points;
      });
    }
  }

  Future<void> _loadMore() async {
    final path = _allPath;
    if (path == null || _exhausted) return;
    final batch = await path.getAssetListPaged(page: _page, size: _pageSize);
    if (batch.length < _pageSize) _exhausted = true;
    _page++;
    _videos.addAll(batch.where((a) => a.type == AssetType.video));
    if (mounted) setState(() {});
  }

  List<AssetEntity> get _visibleVideos {
    final q = _query.trim().toLowerCase();
    return _videos.where((a) {
      if (_priv.contains(a.id)) return false; // hidden in main grid
      if (_filter == _Filter.favorites && !_favs.contains(a.id)) return false;
      if (q.isNotEmpty && !(a.title ?? '').toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  List<RecentItem> get _continueWatching =>
      _recent.where((r) => _resumePoints.containsKey(r.id)).take(10).toList();

  void _openAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Max Player',
      applicationVersion: '0.4.0',
      applicationLegalese: 'Local-first. Ad-free. Proudly Developed in India.',
      children: const [
        Text('MPV (libmpv + FFmpeg) engine.\nNo accounts. No tracking.',
            style: TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent))
            : _denied
                ? _PermissionHint(onRetry: _load)
                : _buildHome(),
      ),
    );
  }

  Widget _buildHome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        if (_searching) _buildSearchBar(),
        _buildTiles(),
        if (_continueWatching.isNotEmpty && !_searching)
          _buildContinueWatching(),
        _buildFilterRow(),
        Expanded(
          child: _visibleVideos.isEmpty
              ? const _EmptyHint()
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: VideoGrid(
                    key: ValueKey('${_filter}_${_query}_${_videos.length}'),
                    videos: _visibleVideos,
                    onChanged: () async {
                      await _loadMeta();
                      setState(() {});
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ---------------- header ----------------

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF3D6BFF), Color(0xFF22D3EE)],
                  ).createShader(r),
                  child: const Text(
                    'Max Player',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const Text(
                  'Proudly Developed in India 🇮🇳',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          _headIcon(Icons.search_rounded, 'Search', () {
            setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchCtrl.clear();
              }
            });
          }),
          _headIcon(Icons.refresh_rounded, 'Refresh', _load),
          _headIcon(Icons.history_rounded, 'History', () =>
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const HistoryScreen()))),
          _headIcon(Icons.more_vert_rounded, 'About', _openAbout),
        ],
      ),
    );
  }

  Widget _headIcon(IconData icon, String tip, VoidCallback onTap) =>
      IconButton(
        tooltip: tip,
        icon: Icon(icon, color: AppColors.textPrimary, size: 22),
        onPressed: onTap,
      );

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search videos…',
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon:
              const Icon(Icons.search_rounded, color: AppColors.textSecondary),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
        ),
      ),
    );
  }

  // ---------------- tiles ----------------

  Widget _buildTiles() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 3.1,
        children: [
          _Tile(
            icon: Icons.folder_outlined,
            label: 'Folders',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FoldersScreen())),
          ),
          _Tile(
            icon: Icons.playlist_play_rounded,
            label: 'Playlists',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlaylistsScreen())),
          ),
          _Tile(
            icon: Icons.lock_outline_rounded,
            label: 'Private Space',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivateScreen())),
          ),
          _Tile(
            icon: Icons.history_rounded,
            label: 'History',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
        ],
      ),
    );
  }

  // ---------------- continue watching ----------------

  Widget _buildContinueWatching() {
    final items = _continueWatching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text('Continue Watching',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) =>
                _ContinueCard(item: items[i], resumeMs: _resumePoints[items[i].id]!),
          ),
        ),
      ],
    );
  }

  // ---------------- filter row ----------------

  Widget _buildFilterRow() {
    ChoiceChip chip(String label, bool sel, VoidCallback onTap) => ChoiceChip(
          label: Text(label),
          selected: sel,
          onSelected: (_) => onTap(),
          backgroundColor: AppColors.surface,
          selectedColor: AppColors.accent.withValues(alpha: 0.25),
          labelStyle: TextStyle(
              color: sel ? AppColors.accent : AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600),
          side: BorderSide(color: sel ? AppColors.accent : AppColors.border),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(
        children: [
          chip('All videos', _filter == _Filter.all,
              () => setState(() => _filter = _Filter.all)),
          const SizedBox(width: 8),
          chip('♥ Favorites', _filter == _Filter.favorites,
              () => setState(() => _filter = _Filter.favorites)),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.accent, size: 20),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.resumeMs});

  final RecentItem item;
  final int resumeMs;

  Future<AssetEntity?> _entity() => AssetEntity.fromId(item.id);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetEntity?>(
      future: _entity(),
      builder: (context, snap) {
        final asset = snap.data;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: asset == null
                ? null
                : () => VideoGrid.openVideo(context, asset),
            child: SizedBox(
              width: 150,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (asset != null)
                    FutureBuilder<Uint8List?>(
                      future: asset.thumbnailDataWithSize(
                          const ThumbnailSize(320, 200)),
                      builder: (context, t) => t.data == null
                          ? const ColoredBox(color: AppColors.surfaceAlt)
                          : Image.memory(t.data!, fit: BoxFit.cover),
                    )
                  else
                    const ColoredBox(color: AppColors.surfaceAlt),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.75),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 6,
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded,
                        color: Colors.white70, size: 30),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PermissionHint extends StatelessWidget {
  const _PermissionHint({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded,
                size: 52, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text('Permission needed',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text(
                'Max Player needs access to your videos to show the library.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onRetry,
              child: const Text('Grant access'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No videos match.',
          style: TextStyle(color: AppColors.textSecondary)),
    );
  }
}
MP_EOF_lib_screens_library_screen_dart
mkdir -p "$(dirname "lib/screens/folders_screen.dart")"
cat > "lib/screens/folders_screen.dart" <<'MP_EOF_lib_screens_folders_screen_dart'
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../widgets/video_grid.dart';

/// Folders: every storage folder containing videos, with counts.
class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<AssetPathEntity> _paths = [];
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final paths = await PhotoManager.getAssetPathList(
          type: RequestType.video, hasAll: false);
      final counts = <String, int>{};
      for (final p in paths) {
        counts[p.id] = await p.assetCountAsync;
      }
      if (mounted) {
        setState(() {
          _paths = paths;
          _counts = counts;
        });
      }
      CrashLog.crumb('folders.scanned', {'count': paths.length});
    } catch (e) {
      CrashLog.error('folders.scan_failed', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      body: _paths.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _paths.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = _paths[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_rounded,
                        color: AppColors.accent, size: 30),
                    title: Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text('${_counts[p.id] ?? 0} videos',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => FolderVideosScreen(path: p))),
                  ),
                );
              },
            ),
    );
  }
}

class FolderVideosScreen extends StatefulWidget {
  const FolderVideosScreen({super.key, required this.path});

  final AssetPathEntity path;

  @override
  State<FolderVideosScreen> createState() => _FolderVideosScreenState();
}

class _FolderVideosScreenState extends State<FolderVideosScreen> {
  static const _pageSize = 60;
  final List<AssetEntity> _videos = [];
  int _page = 0;
  bool _exhausted = false;
  Set<String> _priv = {};

  @override
  void initState() {
    super.initState();
    _loadMore();
    LocalStore().privateIds().then((s) {
      if (mounted) setState(() => _priv = s);
    });
  }

  Future<void> _loadMore() async {
    if (_exhausted) return;
    final batch =
        await widget.path.getAssetListPaged(page: _page, size: _pageSize);
    if (batch.length < _pageSize) _exhausted = true;
    _page++;
    _videos.addAll(batch.where((a) => a.type == AssetType.video));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final visible = _videos.where((a) => !_priv.contains(a.id)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.path.name)),
      body: visible.isEmpty
          ? const Center(
              child: Text('Empty folder',
                  style: TextStyle(color: AppColors.textSecondary)))
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                  _loadMore();
                }
                return false;
              },
              child: VideoGrid(
                videos: visible,
                onChanged: () async {
                  final s = await LocalStore().privateIds();
                  if (mounted) setState(() => _priv = s);
                },
              ),
            ),
    );
  }
}
MP_EOF_lib_screens_folders_screen_dart
mkdir -p "$(dirname "lib/screens/playlists_screen.dart")"
cat > "lib/screens/playlists_screen.dart" <<'MP_EOF_lib_screens_playlists_screen_dart'
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../widgets/video_grid.dart';

/// Local playlists: create, delete, add videos (long-press a card
/// anywhere → "Add to playlist"), open to browse & play.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final _store = LocalStore();
  Map<String, List<String>> _playlists = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final pl = await _store.playlists();
    if (mounted) setState(() => _playlists = pl);
  }

  Future<void> _create() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('New playlist',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: AppColors.textSecondary),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final ok = await _store.createPlaylist(name);
    if (mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A playlist with that name exists')));
    }
    CrashLog.crumb('playlist.created', {'name': name});
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final names = _playlists.keys.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New', style: TextStyle(color: Colors.white)),
        onPressed: _create,
      ),
      body: names.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No playlists yet.\nCreate one, then long-press any video → "Add to playlist".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: names.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final name = names[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.playlist_play_rounded,
                        color: AppColors.accent, size: 30),
                    title: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text('${_playlists[name]!.length} videos',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.danger, size: 20),
                      onPressed: () async {
                        await _store.deletePlaylist(name);
                        _reload();
                      },
                    ),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                PlaylistVideosScreen(name: name))),
                  ),
                );
              },
            ),
    );
  }
}

class PlaylistVideosScreen extends StatefulWidget {
  const PlaylistVideosScreen({super.key, required this.name});

  final String name;

  @override
  State<PlaylistVideosScreen> createState() => _PlaylistVideosScreenState();
}

class _PlaylistVideosScreenState extends State<PlaylistVideosScreen> {
  final List<AssetEntity> _videos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() => _loading = true);
    final ids = (await LocalStore().playlists())[widget.name] ?? [];
    final list = <AssetEntity>[];
    for (final id in ids) {
      final a = await AssetEntity.fromId(id);
      if (a != null) list.add(a);
    }
    if (mounted) {
      setState(() {
        _videos
          ..clear()
          ..addAll(list);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : _videos.isEmpty
              ? const Center(
                  child: Text('Empty playlist',
                      style: TextStyle(color: AppColors.textSecondary)))
              : VideoGrid(videos: _videos, onChanged: _resolve),
    );
  }
}
MP_EOF_lib_screens_playlists_screen_dart
mkdir -p "$(dirname "lib/screens/private_screen.dart")"
cat > "lib/screens/private_screen.dart" <<'MP_EOF_lib_screens_private_screen_dart'
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../widgets/video_grid.dart';

/// PIN-gated Private Space. Videos marked private are hidden from the
/// main grid and folder views; they only appear here after the PIN.
class PrivateScreen extends StatefulWidget {
  const PrivateScreen({super.key});

  @override
  State<PrivateScreen> createState() => _PrivateScreenState();
}

class _PrivateScreenState extends State<PrivateScreen> {
  final _store = LocalStore();
  bool _unlocked = false;
  bool _checking = true;
  List<AssetEntity> _videos = [];

  @override
  void initState() {
    super.initState();
    _gate();
  }

  Future<void> _gate() async {
    final pin = await _store.pin();
    if (!mounted) return;
    if (pin == null) {
      final created = await _askPin(
          title: 'Create a PIN', hint: 'Choose a PIN for Private Space');
      if (created == null || created.length < 4) {
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      await _store.setPin(created);
      CrashLog.crumb('private.pin_created');
      _unlock();
    } else {
      final entered = await _askPin(title: 'Enter PIN', hint: 'PIN');
      if (entered == pin) {
        CrashLog.crumb('private.unlocked');
        _unlock();
      } else {
        CrashLog.crumb('private.wrong_pin');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Wrong PIN')));
          Navigator.of(context).maybePop();
        }
      }
    }
  }

  Future<String?> _askPin({required String title, required String hint}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(title,
            style:
                const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 12,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  Future<void> _unlock() async {
    await _reload();
    if (mounted) {
      setState(() {
        _unlocked = true;
        _checking = false;
      });
    }
  }

  Future<void> _reload() async {
    final ids = await _store.privateIds();
    final list = <AssetEntity>[];
    for (final id in ids) {
      final a = await AssetEntity.fromId(id);
      if (a != null) list.add(a);
    }
    _videos = list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Private Space')),
      body: _checking
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : !_unlocked
              ? const SizedBox.shrink()
              : _videos.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Nothing here yet.\nLong-press any video → "Move to Private Space".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : VideoGrid(videos: _videos, onChanged: () async {
                      await _reload();
                      setState(() {});
                    }),
    );
  }
}
MP_EOF_lib_screens_private_screen_dart
mkdir -p "$(dirname "lib/screens/history_screen.dart")"
cat > "lib/screens/history_screen.dart" <<'MP_EOF_lib_screens_history_screen_dart'
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/local_store.dart';
import '../widgets/video_grid.dart';

/// Watch history: last 25 opened videos, newest first.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _store = LocalStore();
  List<RecentItem> _items = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await _store.recent();
    if (mounted) setState(() => _items = items);
  }

  String _when(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                await _store.clearRecent();
                _reload();
              },
            ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(
              child: Text('Nothing watched yet.',
                  style: TextStyle(color: AppColors.textSecondary)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final item = _items[i];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    leading: _HistoryThumb(id: item.id),
                    title: Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(_when(item.ts),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    trailing: const Icon(Icons.play_circle_outline_rounded,
                        color: AppColors.accent),
                    onTap: () async {
                      final asset = await AssetEntity.fromId(item.id);
                      if (asset == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('This video no longer exists')));
                        }
                        return;
                      }
                      if (context.mounted) {
                        await VideoGrid.openVideo(context, asset, store: _store);
                      }
                      _reload();
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _HistoryThumb extends StatelessWidget {
  const _HistoryThumb({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 64,
        height: 44,
        child: FutureBuilder<AssetEntity?>(
          future: AssetEntity.fromId(id),
          builder: (context, snap) {
            final a = snap.data;
            if (a == null) {
              return const ColoredBox(color: AppColors.surfaceAlt);
            }
            return FutureBuilder<Uint8List?>(
              future:
                  a.thumbnailDataWithSize(const ThumbnailSize(160, 110)),
              builder: (context, t) => t.data == null
                  ? const ColoredBox(color: AppColors.surfaceAlt)
                  : Image.memory(t.data!, fit: BoxFit.cover),
            );
          },
        ),
      ),
    );
  }
}
MP_EOF_lib_screens_history_screen_dart
mkdir -p "$(dirname "test/widget_test.dart")"
cat > "test/widget_test.dart" <<'MP_EOF_test_widget_test_dart'
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/badges.dart';
import 'package:maxplayer/utils/format.dart';
import 'package:maxplayer/utils/local_store.dart';
import 'package:maxplayer/utils/resume.dart';

void main() {
  group('formatDuration', () {
    test('zero', () => expect(formatDuration(Duration.zero), '0:00'));
    test('seconds', () {
      expect(formatDuration(const Duration(seconds: 7)), '0:07');
    });
    test('minutes', () {
      expect(formatDuration(const Duration(minutes: 1, seconds: 5)), '1:05');
    });
    test('hours', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
    test('negative clamps to zero', () {
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
    });
  });

  group('formatBytes', () {
    test('bytes', () => expect(formatBytes(512), '512B'));
    test('kilobytes', () => expect(formatBytes(1536), '1.5 KB'));
    test('megabytes', () => expect(formatBytes(734003200), '700.0 MB'));
    test('negative clamps', () => expect(formatBytes(-1), '0B'));
  });

  group('resumeTargetMs (v0.3 resume)', () {
    test('under 10s saved -> no prompt', () {
      expect(resumeTargetMs(5000, 600000), isNull);
    });
    test('boundary: exactly 10s saved -> prompt', () {
      expect(resumeTargetMs(minPromptMs, 600000), minPromptMs);
    });
    test('mid-video -> prompt at saved spot', () {
      expect(resumeTargetMs(754000, 3600000), 754000);
    });
    test('inside end margin -> treated as finished, no prompt', () {
      expect(resumeTargetMs(3600000 - endMarginMs + 1, 3600000), isNull);
    });
    test('just outside end margin -> prompt', () {
      expect(resumeTargetMs(3600000 - endMarginMs, 3600000),
          3600000 - endMarginMs);
    });
    test('unknown duration (0) -> prompt for big save', () {
      expect(resumeTargetMs(60000, 0), 60000);
    });
  });

  group('isFinishedMs (v0.3 resume)', () {
    test('near end -> finished', () {
      expect(isFinishedMs(3595000, 3600000), isTrue);
    });
    test('mid -> not finished', () {
      expect(isFinishedMs(1800000, 3600000), isFalse);
    });
    test('unknown duration -> not finished', () {
      expect(isFinishedMs(999999, 0), isFalse);
    });
  });

  group('qualityBadge (v0.4)', () {
    test('4K landscape', () => expect(qualityBadge(3840, 2160), '4K'));
    test('2K', () => expect(qualityBadge(2560, 1440), '2K'));
    test('1080p landscape', () => expect(qualityBadge(1920, 1080), '1080p'));
    test('1080p portrait (short side rules)', () {
      expect(qualityBadge(1080, 1920), '1080p');
    });
    test('720p', () => expect(qualityBadge(1280, 720), '720p'));
    test('480p', () => expect(qualityBadge(854, 480), '480p'));
    test('SD', () => expect(qualityBadge(320, 240), 'SD'));
  });

  group('upsertRecent (v0.4 history)', () {
    RecentItem it(String id, int ts) =>
        RecentItem(id: id, title: 't$id', path: '/$id', ts: ts);

    test('newest first', () {
      final out = upsertRecent([it('a', 1)], it('b', 2));
      expect(out.map((e) => e.id).toList(), ['b', 'a']);
    });
    test('dedupes by id, moves to front', () {
      final out = upsertRecent([it('a', 1), it('b', 2)], it('a', 3));
      expect(out.map((e) => e.id).toList(), ['a', 'b']);
      expect(out.first.ts, 3);
    });
    test('caps at 25', () {
      var list = <RecentItem>[];
      for (var i = 0; i < 30; i++) {
        list = upsertRecent(list, it('$i', i));
      }
      expect(list.length, 25);
      expect(list.first.id, '29'); // newest kept
      expect(list.last.id, '5'); // oldest dropped
    });
  });

  group('toggleId (v0.4 playlists)', () {
    test('adds when missing', () {
      expect(toggleId(['a'], 'b'), ['a', 'b']);
    });
    test('removes when present', () {
      expect(toggleId(['a', 'b'], 'b'), ['a']);
    });
    test('does not mutate input', () {
      final input = ['a'];
      toggleId(input, 'x');
      expect(input, ['a']);
    });
  });

  testWidgets('theme applies dark design language', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: Text('ok')),
    ));
    expect(find.text('ok'), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('ok')));
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.brightness, Brightness.dark);
  });
}
MP_EOF_test_widget_test_dart
echo ">> Resolving packages ..."
flutter pub get > /dev/null
echo ">> Analyzer ..."
if dart analyze; then
  echo
  echo "==============================================="
  echo "  v0.4 applied cleanly (home drop)."
  echo "  Ship the APK:"
  echo "    git add -A"
  echo "    git commit -m \"v0.4: home drop\""
  echo "    git push"
  echo "  -> Actions tab -> Artifacts -> new APK"
  echo "==============================================="
else
  echo "v0.4 applied but analyzer reported issues - paste them in chat."
  exit 1
fi
