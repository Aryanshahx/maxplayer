#!/usr/bin/env bash
# ============================================================
#  update_v5.sh — MaxPlayer v0.5.0+6: DISPLAY SETTINGS + GESTURES
#
#  • Home: three-dot menu -> Display settings / Statistics /
#    User manual / About / Privacy policy
#    (Continue Watching row + filter chips removed from home;
#    delete icon removed from cards - still in long-press menu)
#  • Display Settings (reference design): Grid/List view,
#    sorting (Name/Date/Size/Length w/ direction), group-by,
#    Playback action (Queue All), favourites-only switch,
#    THEME ACCENT COLOR wheel (6 colors, applies instantly)
#  • Responsive grid (2-6 cols by width) + compact List view
#  • Player gestures: vertical LEFT = brightness, RIGHT = volume,
#    horizontal = scrub seek w/ preview, pinch = zoom 1-4x
#    (+ existing tap / double-tap +-10s / long-press 2x)
#  • Queue All: next video auto-plays when one ends
#  • Statistics + User manual + Privacy policy screens
#  • 3 new pin tests (35 total)
#
#  USAGE:
#    bash update_v5.sh
#    git add -A && git commit -m "v0.5: display settings + full gestures" && git push
# ============================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f pubspec.yaml ] || { echo "ERROR: no project here - apply update_v1.sh first."; exit 1; }
echo ">> Writing v0.5 files ..."
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
version: 0.5.0+6

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
  screen_brightness: ^2.1.11
  volume_controller: ^3.6.1

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
mkdir -p "$(dirname "lib/main.dart")"
cat > "lib/main.dart" <<'MP_EOF_lib_main_dart'
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/library_screen.dart';
import 'theme.dart';
import 'utils/crash_log.dart';
import 'utils/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // MPV core
  await CrashLog.init(); // forensics armed before first frame
  await AppSettings.instance.load(); // display settings + accent
  CrashLog.crumb('app.start');
  runApp(const MaxPlayerApp());
}

class MaxPlayerApp extends StatelessWidget {
  const MaxPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds MaterialApp when accent changes (Display Settings wheel).
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        AppColors.accent = AppSettings.instance.accentColor;
        return MaterialApp(
          title: 'Max Player',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(accent: AppSettings.instance.accentColor),
          home: const LibraryScreen(),
        );
      },
    );
  }
}
MP_EOF_lib_main_dart
mkdir -p "$(dirname "lib/theme.dart")"
cat > "lib/theme.dart" <<'MP_EOF_lib_theme_dart'
import 'package:flutter/material.dart';

/// MaxPlayer dark design language — near-black slate surfaces,
/// hairline borders, cool blue accent. Dark-first, no light mode for v0.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0B0E14); // app canvas
  static const surface = Color(0xFF131826); // cards / inputs
  static const surfaceAlt = Color(0xFF181E2E); // raised elements
  static const border = Color(0xFF262E42); // 1px hairlines
  static const textPrimary = Color(0xFFF2F5FA);
  static const textSecondary = Color(0xFF8B94A7);
  /// Mutable — set from Display Settings accent wheel (AppSettings).
  static Color accent = const Color(0xFF3D6BFF); // default blue
  static const accentSoft = Color(0xFF2A3CFF);
  static const danger = Color(0xFFE5484D);
}

ThemeData buildAppTheme({Color? accent}) {
  final ac = accent ?? AppColors.accent;
  const radius = Radius.circular(16);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.dark(
      surface: AppColors.surface,
      primary: ac,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(radius),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.textPrimary),
      bodySmall: TextStyle(color: AppColors.textSecondary),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
  );
}
MP_EOF_lib_theme_dart
mkdir -p "$(dirname "lib/utils/settings.dart")"
cat > "lib/utils/settings.dart" <<'MP_EOF_lib_utils_settings_dart'
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display & behavior settings, persisted locally, reactive app-wide.

enum ViewMode { grid, list }

enum SortField { name, dateAdded, size, length }

enum GroupBy { none, folder }

/// Accent palette shown in Display Settings (order matches the design).
const accentPalette = <Color>[
  Color(0xFF8B5CF6), // purple
  Color(0xFF22D3EE), // cyan
  Color(0xFF34D399), // green
  Color(0xFFFB923C), // orange
  Color(0xFFF472B6), // pink
  Color(0xFF3D6BFF), // blue (default)
];

const defaultAccentIndex = 5;

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const _kViewMode = 'disp.viewMode';
  static const _kSortField = 'disp.sortField';
  static const _kSortAsc = 'disp.sortAsc';
  static const _kGroupBy = 'disp.groupBy';
  static const _kQueueAll = 'disp.queueAll';
  static const _kOnlyFavs = 'disp.onlyFavs';
  static const _kAccent = 'disp.accent';

  ViewMode viewMode = ViewMode.grid;
  SortField sortField = SortField.name;
  bool sortAsc = true; // A → Z by default (design reference)
  GroupBy groupBy = GroupBy.none;
  bool queueAll = true; // "Queue All" playback action
  bool onlyFavs = false;
  int accentIndex = defaultAccentIndex;

  Color get accentColor => accentPalette[accentIndex];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    int clampIdx(int? v, int max, int fallback) =>
        (v ?? fallback).clamp(0, max).toInt();
    viewMode =
        ViewMode.values[clampIdx(p.getInt(_kViewMode), ViewMode.values.length - 1, 0)];
    sortField = SortField
        .values[clampIdx(p.getInt(_kSortField), SortField.values.length - 1, 0)];
    sortAsc = p.getBool(_kSortAsc) ?? true;
    groupBy = GroupBy
        .values[clampIdx(p.getInt(_kGroupBy), GroupBy.values.length - 1, 0)];
    queueAll = p.getBool(_kQueueAll) ?? true;
    onlyFavs = p.getBool(_kOnlyFavs) ?? false;
    accentIndex =
        clampIdx(p.getInt(_kAccent), accentPalette.length - 1, defaultAccentIndex);
  }

  Future<void> _set(Future<bool> Function(SharedPreferences p) write) async {
    await write(await SharedPreferences.getInstance());
    notifyListeners();
  }

  void setViewMode(ViewMode v) {
    viewMode = v;
    _set((p) => p.setInt(_kViewMode, v.index));
  }

  void setSortField(SortField f) {
    sortField = f;
    _set((p) => p.setInt(_kSortField, f.index));
  }

  void setSortAsc(bool a) {
    sortAsc = a;
    _set((p) => p.setBool(_kSortAsc, a));
  }

  void setGroupBy(GroupBy g) {
    groupBy = g;
    _set((p) => p.setInt(_kGroupBy, g.index));
  }

  void setQueueAll(bool q) {
    queueAll = q;
    _set((p) => p.setBool(_kQueueAll, q));
  }

  void setOnlyFavs(bool o) {
    onlyFavs = o;
    _set((p) => p.setBool(_kOnlyFavs, o));
  }

  void setAccentIndex(int i) {
    accentIndex = i;
    _set((p) => p.setInt(_kAccent, i));
  }
}
MP_EOF_lib_utils_settings_dart
mkdir -p "$(dirname "lib/utils/sort.dart")"
cat > "lib/utils/sort.dart" <<'MP_EOF_lib_utils_sort_dart'
import 'settings.dart';

export 'settings.dart' show GroupBy, SortField, ViewMode;

/// Pure comparators for video sorting (unit-tested).

int cmpNum(num a, num b, bool asc) => asc ? a.compareTo(b) : b.compareTo(a);

int cmpStr(String a, String b, bool asc) =>
    asc ? a.toLowerCase().compareTo(b.toLowerCase())
        : b.toLowerCase().compareTo(a.toLowerCase());

/// Direction pill labels shown next to each sort field (design reference).
String sortDirectionLabel(SortField f, bool asc) => switch (f) {
      SortField.name => asc ? 'A → Z' : 'Z → A',
      SortField.dateAdded => asc ? 'Oldest first' : 'Newest first',
      SortField.size => asc ? 'Smallest first' : 'Largest first',
      SortField.length => asc ? 'Shortest first' : 'Longest first',
    };

String sortFieldLabel(SortField f) => switch (f) {
      SortField.name => 'Name',
      SortField.dateAdded => 'Date Added',
      SortField.size => 'File Size',
      SortField.length => 'Video Length',
    };

String groupByLabel(GroupBy g) => switch (g) {
      GroupBy.none => 'None',
      GroupBy.folder => 'Folder',
    };
MP_EOF_lib_utils_sort_dart
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
import '../utils/settings.dart';

/// Shared video card grid + compact list used by Home, Folders, Playlists,
/// Private Space and History. Responsive: column count adapts to width.
class VideoGrid extends StatefulWidget {
  const VideoGrid({
    super.key,
    required this.videos,
    required this.onChanged,
    this.onOpen,
    this.listMode = false,
  });

  final List<AssetEntity> videos;
  final VoidCallback onChanged;
  final void Function(AssetEntity asset)? onOpen;

  /// Compact rows instead of visual cards (Display Settings → List View).
  final bool listMode;

  /// Guarded open used everywhere a video starts (non-negotiable #2).
  /// Records history, hands off the queue when "Queue All" is enabled.
  static Future<void> openVideo(BuildContext context, AssetEntity asset,
      {LocalStore? store, List<AssetEntity>? queue}) async {
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
      List<String> queueIds = const [];
      var start = 0;
      if (AppSettings.instance.queueAll &&
          queue != null &&
          queue.isNotEmpty) {
        queueIds = queue.map((e) => e.id).toList();
        start = queueIds.indexOf(asset.id);
        if (start < 0) start = 0;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            path: file.path,
            title: asset.title ?? 'Video',
            queueIds: queueIds,
            queueStart: start,
          ),
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
        content: Text(nowPrivate
            ? 'Moved to Private Space'
            : 'Removed from Private Space'),
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
          content:
              Text('No playlists yet — create one from the Playlists tile')));
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Add to playlist',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            for (final name in pls.keys)
              ListTile(
                leading: Icon(Icons.playlist_play_rounded,
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
          content:
              Text(added ? 'Added to "$chosen"' : 'Removed from "$chosen"')));
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
            style:
                const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _prop('Resolution',
                '${a.width}×${a.height} (${qualityBadge(a.width, a.height)})'),
            _prop('Duration',
                formatDuration(Duration(seconds: a.duration))),
            _prop('Modified',
                '${a.modifiedDateTime.year}-${a.modifiedDateTime.month.toString().padLeft(2, '0')}-${a.modifiedDateTime.day.toString().padLeft(2, '0')}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _prop(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('$k:  $v',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
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
        leading:
            Icon(icon, color: danger ? AppColors.danger : AppColors.accent),
        title: Text(label,
            style: TextStyle(
                color: danger ? AppColors.danger : AppColors.textPrimary)),
        onTap: onTap,
      );

  void _open(AssetEntity a) => (widget.onOpen ??
      (x) => VideoGrid.openVideo(context, x,
          store: _store, queue: widget.videos))(a);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive: ~190dp per column — phones 2, tablets/foldables 4-6.
        final cols = (constraints.maxWidth / 190).floor().clamp(2, 6);
        if (widget.listMode) {
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: widget.videos.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final a = widget.videos[i];
              return _VideoRow(
                asset: a,
                isFav: _favs.contains(a.id),
                onTap: () => _open(a),
                onLongPress: () => _showActions(a),
                onToggleFav: () => _toggleFav(a),
              );
            },
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
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
              onTap: () => _open(a),
              onLongPress: () => _showActions(a),
              onToggleFav: () => _toggleFav(a),
            );
          },
        );
      },
    );
  }
}

/// Static async size cache shared by cards and rows.
final Map<String, Future<int>> videoSizeCache = {};

Future<int> videoSize(AssetEntity asset) => videoSizeCache.putIfAbsent(
    asset.id, () async => (await asset.file)?.length() ?? 0);

class _VideoRow extends StatelessWidget {
  const _VideoRow({
    required this.asset,
    required this.isFav,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFav,
  });

  final AssetEntity asset;
  final bool isFav;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFav;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 72,
            height: 48,
            child: FutureBuilder<Uint8List?>(
              future: asset.thumbnailDataWithSize(
                  const ThumbnailSize(160, 110)),
              builder: (context, t) => t.data == null
                  ? const ColoredBox(color: AppColors.surfaceAlt)
                  : Image.memory(t.data!, fit: BoxFit.cover),
            ),
          ),
        ),
        title: Text(asset.title ?? 'Untitled',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
        subtitle: Text(
          '${qualityBadge(asset.width, asset.height)} · ${formatDuration(Duration(seconds: asset.duration))}',
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
        ),
        trailing: IconButton(
          icon: Icon(
            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: isFav ? AppColors.danger : AppColors.textSecondary,
            size: 20,
          ),
          onPressed: onToggleFav,
        ),
      ),
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
  });

  final AssetEntity asset;
  final bool isFav;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFav;

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
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _Pill(
                      text: qualityBadge(asset.width, asset.height),
                      color: Colors.black.withValues(alpha: 0.65),
                      textColor: AppColors.textPrimary,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _Pill(
                      text: formatDuration(Duration(seconds: asset.duration)),
                      color: Colors.black.withValues(alpha: 0.65),
                      textColor: AppColors.textPrimary,
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isFav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isFav ? AppColors.danger : Colors.white,
                        size: 20,
                      ),
                      onPressed: onToggleFav,
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
                    future: videoSize(asset),
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
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
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

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../utils/settings.dart';
import '../utils/sort.dart';
import '../widgets/video_grid.dart';
import 'display_settings_screen.dart';
import 'folders_screen.dart';
import 'history_screen.dart';
import 'info_screens.dart';
import 'playlists_screen.dart';
import 'private_screen.dart';
import 'statistics_screen.dart';

/// Home — gradient header + tagline, tool tiles (Folders / Playlists /
/// Private Space / History), searchable grid-or-list controlled entirely
/// from Display Settings (sort, view mode, grouping, favourites-only).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _pageSize = 60;

  final _store = LocalStore();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _denied = false;
  bool _searching = false;
  String _query = '';

  final List<AssetEntity> _videos = [];
  AssetPathEntity? _allPath;
  int _page = 0;
  bool _exhausted = false;

  Set<String> _favs = {};
  Set<String> _priv = {};

  @override
  void initState() {
    super.initState();
    _load();
    AppSettings.instance.addListener(_onSettings);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettings);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSettings() {
    if (AppSettings.instance.sortField == SortField.size) {
      unawaited(_ensureSizes());
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensureSizes() async {
    // fill the shared cache for what's loaded so size-sort is meaningful
    await Future.wait(_videos.map(videoSize));
    if (mounted) setState(() {});
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
    if (mounted) {
      setState(() {
        _favs = favs;
        _priv = priv;
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
    final s = AppSettings.instance;
    final q = _query.trim().toLowerCase();
    final list = _videos.where((a) {
      if (_priv.contains(a.id)) return false;
      if (s.onlyFavs && !_favs.contains(a.id)) return false;
      if (q.isNotEmpty && !(a.title ?? '').toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    list.sort((x, y) {
      switch (s.sortField) {
        case SortField.name:
          return cmpStr(x.title ?? '', y.title ?? '', s.sortAsc);
        case SortField.dateAdded:
          return cmpNum(x.modifiedDateTime.millisecondsSinceEpoch,
              y.modifiedDateTime.millisecondsSinceEpoch, s.sortAsc);
        case SortField.length:
          return cmpNum(x.duration, y.duration, s.sortAsc);
        case SortField.size:
          final sx = videoSizeCache[x.id];
          final sy = videoSizeCache[y.id];
          return cmpNum(sx == null ? 0 : 1, sy == null ? 0 : 1, s.sortAsc);
      }
    });
    return list;
  }

  void _openMenu(_MenuAction a) {
    Widget? page;
    switch (a) {
      case _MenuAction.display:
        page = const DisplaySettingsScreen();
      case _MenuAction.stats:
        page = const StatisticsScreen();
      case _MenuAction.manual:
        page = const UserManualScreen();
      case _MenuAction.privacy:
        page = const PrivacyPolicyScreen();
      case _MenuAction.about:
        showAboutDialog(
          context: context,
          applicationName: 'Max Player',
          applicationVersion: '0.5.0',
          applicationLegalese:
              'Local-first. Ad-free. Proudly Developed in India.',
          children: const [
            Text('MPV (libmpv + FFmpeg) engine.\nNo accounts. No tracking.',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        );
        return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? Center(
                child: CircularProgressIndicator(color: AppColors.accent))
            : _denied
                ? _PermissionHint(onRetry: _load)
                : _buildHome(),
      ),
    );
  }

  Widget _buildHome() {
    final videos = _visibleVideos;
    final s = AppSettings.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        if (_searching) _buildSearchBar(),
        _buildTiles(),
        const SizedBox(height: 6),
        Expanded(
          child: videos.isEmpty
              ? const _EmptyHint()
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: s.groupBy == GroupBy.folder
                      ? _GroupedView(
                          videos: videos,
                          listMode: s.viewMode == ViewMode.list,
                          onChanged: _refresh,
                        )
                      : VideoGrid(
                          key: ValueKey(
                              '${s.viewMode}_${videos.length}_$_query'),
                          videos: videos,
                          listMode: s.viewMode == ViewMode.list,
                          onChanged: _refresh,
                        ),
                ),
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    await _loadMeta();
    if (mounted) setState(() {});
  }

  // ---------------- header ----------------

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [
                      Color(0xFF8B5CF6),
                      Color(0xFF3D6BFF),
                      Color(0xFF22D3EE)
                    ],
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
          IconButton(
            tooltip: 'Search',
            icon:
                const Icon(Icons.search_rounded, color: AppColors.textPrimary),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchCtrl.clear();
              }
            }),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon:
                const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
            onPressed: _load,
          ),
          IconButton(
            tooltip: 'History',
            icon:
                const Icon(Icons.history_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          PopupMenuButton<_MenuAction>(
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.textPrimary),
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            onSelected: _openMenu,
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: _MenuAction.display,
                  child: _MenuRow(
                      icon: Icons.tune_rounded, label: 'Display settings')),
              PopupMenuItem(
                  value: _MenuAction.stats,
                  child:
                      _MenuRow(icon: Icons.bar_chart_rounded, label: 'Statistics')),
              PopupMenuItem(
                  value: _MenuAction.manual,
                  child: _MenuRow(
                      icon: Icons.menu_book_outlined, label: 'User manual')),
              PopupMenuItem(
                  value: _MenuAction.about,
                  child:
                      _MenuRow(icon: Icons.info_outline_rounded, label: 'About')),
              PopupMenuItem(
                  value: _MenuAction.privacy,
                  child: _MenuRow(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacy policy')),
            ],
          ),
        ],
      ),
    );
  }

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
            borderSide: BorderSide(color: AppColors.accent),
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
}

enum _MenuAction { display, stats, manual, about, privacy }

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppColors.accent),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      ],
    );
  }
}

class _GroupedView extends StatelessWidget {
  const _GroupedView(
      {required this.videos, required this.listMode, required this.onChanged});

  final List<AssetEntity> videos;
  final bool listMode;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AssetEntity>>{};
    for (final a in videos) {
      final rp = a.relativePath ?? 'Other';
      final parts = rp.split('/').where((e) => e.isNotEmpty).toList();
      groups.putIfAbsent(parts.isEmpty ? 'Other' : parts.last, () => []).add(a);
    }
    final names = groups.keys.toList()..sort();
    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (context, i) {
        final name = names[i];
        final items = groups[name]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
              child: Text('$name  ·  ${items.length}',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
            ),
            SizedBox(
              height: listMode
                  ? items.length * 68.0
                  : ((items.length + 1) ~/ 2) * 270.0,
              child: VideoGrid(
                videos: items,
                listMode: listMode,
                onChanged: onChanged,
              ),
            ),
          ],
        );
      },
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
mkdir -p "$(dirname "lib/screens/display_settings_screen.dart")"
cat > "lib/screens/display_settings_screen.dart" <<'MP_EOF_lib_screens_display_settings_screen_dart'
import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/settings.dart';
import '../utils/sort.dart';

/// Display Settings — layout & view mode, sorting, grouping & actions,
/// theme accent wheel. Design mirrors the reference screenshot.
class DisplaySettingsScreen extends StatelessWidget {
  const DisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: const Text('Display Settings'),
        leading: const BackButton(),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding:
              const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 32),
          children: [
            const _SectionTitle('LAYOUT & VIEW MODE'),
            Row(
              children: [
                Expanded(
                  child: _ModeCard(
                    icon: Icons.grid_view_rounded,
                    title: 'Grid View',
                    subtitle: 'Visual cards',
                    selected: s.viewMode == ViewMode.grid,
                    onTap: () => s.setViewMode(ViewMode.grid),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ModeCard(
                    icon: Icons.view_list_rounded,
                    title: 'List View',
                    subtitle: 'Compact rows',
                    selected: s.viewMode == ViewMode.list,
                    onTap: () => s.setViewMode(ViewMode.list),
                  ),
                ),
              ],
            ),
            const _SectionTitle('SORTING'),
            Card(
              child: Column(
                children: [
                  for (final f in SortField.values) ...[
                    _SortRow(field: f),
                    if (f != SortField.values.last)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                ],
              ),
            ),
            const _SectionTitle('GROUPING & ACTIONS'),
            Card(
              child: Column(
                children: [
                  _DropdownRow<GroupBy>(
                    icon: Icons.photo_library_outlined,
                    label: 'Group videos by',
                    value: s.groupBy,
                    values: GroupBy.values,
                    labelOf: groupByLabel,
                    onChanged: s.setGroupBy,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _DropdownRow<bool>(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Playback action',
                    value: s.queueAll,
                    values: const [true, false],
                    labelOf: (v) => v ? 'Queue All' : 'Play Single',
                    onChanged: s.setQueueAll,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.favorite_border_rounded,
                            color: AppColors.accent, size: 22),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text('Show only favourites',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14.5)),
                        ),
                        Switch(
                          value: s.onlyFavs,
                          activeThumbColor: AppColors.accent,
                          onChanged: s.setOnlyFavs,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const _SectionTitle('THEME ACCENT COLOR'),
            Wrap(
              spacing: 14,
              runSpacing: 12,
              children: [
                for (var i = 0; i < accentPalette.length; i++)
                  _AccentDot(
                    color: accentPalette[i],
                    selected: s.accentIndex == i,
                    onTap: () => s.setAccentIndex(i),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10, left: 4),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1)),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                  size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: selected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({required this.field});

  final SortField field;

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final selected = s.sortField == field;
    return InkWell(
      onTap: () {
        if (selected) {
          s.setSortAsc(!s.sortAsc); // tap again → flip direction
        } else {
          s.setSortField(field);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              switch (field) {
                SortField.name => Icons.sort_by_alpha_rounded,
                SortField.dateAdded => Icons.history_rounded,
                SortField.size => Icons.donut_small_rounded,
                SortField.length => Icons.timer_outlined,
              },
              color: selected ? AppColors.accent : AppColors.textSecondary,
              size: 21,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(sortFieldLabel(field),
                  style: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14.5,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
            ),
            if (selected)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(sortDirectionLabel(field, s.sortAsc),
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Icon(Icons.check_rounded, color: AppColors.accent, size: 14),
                  ],
                ),
              )
            else
              Text(sortDirectionLabel(field, s.sortAsc),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final void Function(T) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14.5)),
          ),
          DropdownButton<T>(
            value: value,
            dropdownColor: AppColors.surfaceAlt,
            underline: const SizedBox.shrink(),
            iconEnabledColor: AppColors.textSecondary,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600),
            items: [
              for (final v in values)
                DropdownMenuItem(value: v, child: Text(labelOf(v))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot(
      {required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: Colors.white, width: 3)
              : Border.all(color: Colors.transparent, width: 3),
          boxShadow: const [
            BoxShadow(
                color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}
MP_EOF_lib_screens_display_settings_screen_dart
mkdir -p "$(dirname "lib/screens/statistics_screen.dart")"
cat > "lib/screens/statistics_screen.dart" <<'MP_EOF_lib_screens_statistics_screen_dart'
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/format.dart';
import '../utils/local_store.dart';

/// Statistics — local library numbers. All computed on-device.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  Map<String, Object>? _stats;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    var videos = 0;
    var seconds = 0;
    try {
      final paths = await PhotoManager.getAssetPathList(
          type: RequestType.video, onlyAll: true);
      if (paths.isNotEmpty) {
        final all = paths.first;
        videos = await all.assetCountAsync;
        const pageSize = 200;
        for (var page = 0;; page++) {
          final batch =
              await all.getAssetListPaged(page: page, size: pageSize);
          if (batch.isEmpty) break;
          for (final a in batch) {
            if (a.type == AssetType.video) seconds += a.duration;
          }
          if (batch.length < pageSize) break;
        }
      }
    } catch (_) {/* stats are best-effort */}

    final store = LocalStore();
    final favs = (await store.favorites()).length;
    final priv = (await store.privateIds()).length;
    final playlists = await store.playlists();
    final playlistItems =
        playlists.values.fold<int>(0, (sum, v) => sum + v.length);
    final recent = (await store.recent()).length;

    if (mounted) {
      setState(() {
        _stats = {
          'Videos on device': videos,
          'Total runtime': formatDuration(Duration(seconds: seconds)),
          'Favourites': favs,
          'In Private Space': priv,
          'Playlists': playlists.length,
          'Items in playlists': playlistItems,
          'History entries': recent,
          'App version': '0.5.0+6',
          'Engine': 'MPV (libmpv + FFmpeg)',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: _stats == null
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _stats!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final k = _stats!.keys.elementAt(i);
                return Card(
                  child: ListTile(
                    title: Text(k,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    trailing: Text('${_stats![k]}',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                );
              },
            ),
    );
  }
}
MP_EOF_lib_screens_statistics_screen_dart
mkdir -p "$(dirname "lib/screens/info_screens.dart")"
cat > "lib/screens/info_screens.dart" <<'MP_EOF_lib_screens_info_screens_dart'
import 'package:flutter/material.dart';

import '../theme.dart';

/// Static info screens: User Manual & Privacy Policy. Bundled, offline.

class UserManualScreen extends StatelessWidget {
  const UserManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocScreen(
      title: 'User Manual',
      sections: {
        'Library': [
          'Videos on your device appear automatically after you grant media access.',
          'Tap the search icon to filter by name.',
          'Long-press any video for actions: add to playlist, private space, properties, delete.',
          'Delete is always confirmed by Android\u2019s own system dialog.',
        ],
        'Player gestures': [
          'Single tap — show or hide controls.',
          'Double tap left / right — jump back / forward 10 seconds.',
          'Long press and hold — 2\u00d7 speed; release to return to normal.',
          'Swipe up / down on the LEFT — screen brightness.',
          'Swipe up / down on the RIGHT — volume.',
          'Swipe left / right across the screen — seek through the video.',
          'Pinch with two fingers — zoom into the picture.',
        ],
        'Resume': [
          'Positions are saved continuously. Kill the app, reopen a video, and you\u2019re offered to resume where you left.',
          'Finishing a video clears its resume point automatically.',
        ],
        'Folders, Playlists, Private Space': [
          'Folders groups videos by storage folder.',
          'Playlists are yours: create, then long-press any video to add.',
          'Private Space hides videos behind your PIN \u2014 they disappear from the library and folders.',
          'History shows your last 25 opened videos.',
        ],
        'Display Settings': [
          'Grid or list layout, sorting, grouping, favourite-only view and the accent colour wheel \u2014 all from the \u22ee menu \u2192 Display settings.',
          'Playback action "Queue All" automatically plays the next video in your current view when one ends.',
        ],
      },
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocScreen(
      title: 'Privacy Policy',
      sections: {
        'The short version': [
          'Max Player works offline. Your videos, playlists, history, favourites and settings never leave your device. There are no accounts, no analytics, no tracking, and no ads.',
        ],
        'What we store': [
          'Media access permission is used only to list and play the videos already on your device.',
          'Playlists, favourites, private-space flags, watch history and resume points are stored locally in the app\u2019s private storage.',
          'The Private Space PIN is stored locally on-device only. Never share it.',
        ],
        'What we never do': [
          'No personal data is collected, sold or shared.',
          'No crash telemetry leaves the device \u2014 diagnostic logs stay in the app\u2019s documents folder for you alone.',
          'No internet connection is required for any core feature.',
        ],
        'Your control': [
          'Clear history any time from the History screen.',
          'Uninstalling the app removes all local data with it.',
        ],
      },
    );
  }
}

class _DocScreen extends StatelessWidget {
  const _DocScreen({required this.title, required this.sections});

  final String title;
  final Map<String, List<String>> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 32),
        children: [
          for (final entry in sections.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
              child: Text(entry.key.toUpperCase(),
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1)),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in entry.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('\u2022 ',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    height: 1.45)),
                            Expanded(
                              child: Text(line,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13.5,
                                      height: 1.45)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
MP_EOF_lib_screens_info_screens_dart
mkdir -p "$(dirname "lib/screens/player_screen.dart")"
cat > "lib/screens/player_screen.dart" <<'MP_EOF_lib_screens_player_screen_dart'
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';
import '../utils/resume.dart';

/// Single-engine player: MPV (libmpv + FFmpeg) via media_kit.
///
/// Gesture suite:
///   • single tap            → show/hide controls
///   • double tap L/R        → seek ±10s (flash pill)
///   • long press hold       → 2× speed, release restores
///   • vertical drag RIGHT   → volume
///   • vertical drag LEFT    → screen brightness (restored on exit)
///   • horizontal drag       → scrub seek with preview pill
///   • two-finger pinch      → zoom 1×–4× (anchored center)
///
/// Also: wakelock while playing, resume prompt (survives kill), and
/// "Queue All" auto-advance to the next video on completion.
/// Any open failure is crumbed, persisted, surfaced, and pops — never silent.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.path,
    required this.title,
    this.queueIds = const [],
    this.queueStart = 0,
  });

  final String path;
  final String title;
  final List<String> queueIds;
  final int queueStart;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _DragMode { none, brightness, volume, seek, zoom }

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  static const _seekStepSecs = 10;
  static const _boostRate = 2.0;
  static const _saveInterval = Duration(seconds: 5);

  late final Player _player;
  late final VideoController _controller;
  final ResumeStore _resume = ResumeStore();
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;

  late String _title;
  String _currentPath = '';
  int _queueIndex = 0;

  bool _ready = false;
  bool _failed = false;
  bool _controlsVisible = true;
  bool _boost = false;
  bool _buffering = false;

  Timer? _hideTimer;
  Timer? _flashTimer;
  Timer? _saveTimer;

  // gesture state
  _DragMode _drag = _DragMode.none;
  Offset _dragStart = Offset.zero;
  double _zoom = 1.0;
  double _zoomStart = 1.0;
  double _levelValue = 0; // brightness or volume 0..1
  Duration? _seekPreview;
  int? _seekFlash;
  bool _seekFlashLeft = false;

  StreamSubscription<bool>? _bufferingSub;

  // ---------------- lifecycle ----------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _title = widget.title;
    _currentPath = widget.path;
    _queueIndex = widget.queueStart;
    _player = Player();
    _controller = VideoController(_player);
    _open(_currentPath, offerResume: true);
    _playingSub = _player.stream.playing.listen((playing) {
      if (playing) {
        WakelockPlus.enable();
        _scheduleHide();
      } else {
        WakelockPlus.disable();
        unawaited(_savePosition());
      }
    });
    _bufferingSub = _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });
    _completedSub = _player.stream.completed.listen((done) {
      if (done) unawaited(_playNext());
    });
    _saveTimer = Timer.periodic(_saveInterval, (_) => _savePosition());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_savePosition());
    }
  }

  Future<void> _open(String path, {required bool offerResume}) async {
    CrashLog.crumb('player.open', {'path': path});
    try {
      await _player.open(Media(path), play: true);
      _player.stream.error.listen(_onError);
      if (mounted) setState(() => _ready = true);
      if (offerResume) unawaited(_offerResume());
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _playNext() async {
    if (!mounted) return;
    if (widget.queueIds.isEmpty || _queueIndex >= widget.queueIds.length - 1) {
      CrashLog.crumb('queue.end');
      await _resume.clear(_currentPath); // finished the tail
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    _queueIndex++;
    final id = widget.queueIds[_queueIndex];
    try {
      final asset = await AssetEntity.fromId(id);
      final file = await asset?.file;
      if (file == null || !file.existsSync()) {
        throw StateError('queue item unavailable: $id');
      }
      await _resume.clear(_currentPath);
      _currentPath = file.path;
      CrashLog.crumb('queue.next', {'id': id});
      setState(() => _title = asset!.title ?? 'Video');
      await _player.open(Media(file.path), play: true);
    } catch (e) {
      CrashLog.error('queue.next_failed', e, {'id': id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not play the next video in queue')));
      }
    }
  }

  // ---------------- resume ----------------

  Future<void> _offerResume() async {
    try {
      final saved = await _resume.readMs(_currentPath);
      if (saved == null || !mounted) return;
      var dur = _player.state.duration;
      if (dur <= Duration.zero) {
        dur = await _player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5),
                onTimeout: () => Duration.zero);
      }
      final targetMs = resumeTargetMs(saved, dur.inMilliseconds);
      if (targetMs == null || !mounted) return;
      CrashLog.crumb('resume.offer', {'path': _currentPath, 'ms': targetMs});
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Text('Resume playback?',
              style:
                  TextStyle(color: AppColors.textPrimary, fontSize: 17)),
          content: Text(
            'Continue from ${formatDuration(Duration(milliseconds: targetMs))}?',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Start over',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (resume == true) {
        _player.seek(Duration(milliseconds: targetMs));
      } else if (resume == false) {
        await _resume.clear(_currentPath);
      }
    } catch (e) {
      CrashLog.error('resume.offer_failed', e, {'path': _currentPath});
    }
  }

  Future<void> _savePosition() async {
    if (!_ready || _failed) return;
    try {
      final pos = _player.state.position;
      final dur = _player.state.duration;
      if (pos <= Duration.zero) return;
      if (isFinishedMs(pos.inMilliseconds, dur.inMilliseconds)) {
        await _resume.clear(_currentPath);
        return;
      }
      await _resume.writeMs(_currentPath, pos.inMilliseconds);
    } catch (e) {
      CrashLog.error('resume.save_failed', e, {'path': _currentPath});
    }
  }

  void _onError(Object e) {
    if (_failed) return;
    _failed = true;
    CrashLog.error('player.open_failed', e, {'path': _currentPath});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("This video can't be played by MPV")),
    );
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _saveTimer?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _completedSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    ScreenBrightness.instance.resetApplicationScreenBrightness();
    unawaited(_savePosition());
    CrashLog.crumb('player.close', {'path': _currentPath});
    unawaited(_player.dispose());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  // ---------------- gestures ----------------

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _onDoubleTap(TapDownDetails d) {
    final half = MediaQuery.of(context).size.width / 2;
    final left = d.globalPosition.dx < half;
    _seekRelative(left ? -_seekStepSecs : _seekStepSecs, flashLeft: left);
  }

  void _seekRelative(int seconds, {required bool flashLeft}) {
    final pos = _player.state.position;
    final dur = _player.state.duration;
    var target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    _player.seek(target);
    _flash(seconds, flashLeft);
  }

  void _flash(int seconds, bool flashLeft) {
    _flashTimer?.cancel();
    setState(() {
      _seekFlash = seconds;
      _seekFlashLeft = flashLeft;
    });
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFlash = null);
    });
  }

  void _setBoost(bool on) {
    if (_boost == on) return;
    setState(() => _boost = on);
    _player.setRate(on ? _boostRate : 1.0);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _dragStart = d.focalPoint;
    _zoomStart = _zoom;
    if (d.pointerCount >= 2) {
      _drag = _DragMode.zoom;
    } else {
      _drag = _DragMode.none;
    }
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails d) async {
    if (_drag == _DragMode.zoom) {
      setState(() {
        _zoom = (_zoomStart * d.scale).clamp(1.0, 4.0);
      });
      return;
    }
    final delta = d.focalPoint - _dragStart;
    if (_drag == _DragMode.none) {
      if (delta.distance < 14) return;
      final w = MediaQuery.of(context).size.width;
      if (delta.dx.abs() > delta.dy.abs() * 1.5) {
        _drag = _DragMode.seek;
        _seekPreview = _player.state.position;
      } else {
        _drag = _dragStart.dx < w / 2 ? _DragMode.brightness : _DragMode.volume;
        // capture starting level
        if (_drag == _DragMode.brightness) {
          _levelValue = await ScreenBrightness.instance.application;
        } else {
          _levelValue = await VolumeController.instance.getVolume();
        }
        _dragStart = d.focalPoint;
        return;
      }
    }
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    if (_drag == _DragMode.brightness || _drag == _DragMode.volume) {
      final change = -(d.focalPoint.dy - _dragStart.dy) / (h * 0.5);
      final v = (_levelValue + change).clamp(0.0, 1.0);
      setState(() {});
      if (_drag == _DragMode.brightness) {
        await ScreenBrightness.instance.setApplicationScreenBrightness(v);
        if (mounted) setState(() => _levelValue = v);
      } else {
        await VolumeController.instance.setVolume(v);
        if (mounted) setState(() => _levelValue = v);
      }
    } else if (_drag == _DragMode.seek) {
      final dur = _player.state.duration;
      if (dur <= Duration.zero) return;
      final frac = d.focalPoint.dx / w; // 0..1 across screen
      var target =
          Duration(milliseconds: (frac.clamp(0.0, 1.0) * dur.inMilliseconds).round());
      setState(() => _seekPreview = target);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_drag == _DragMode.seek && _seekPreview != null) {
      _player.seek(_seekPreview!);
      CrashLog.crumb('player.scrub', {'to_ms': _seekPreview!.inMilliseconds});
    }
    if (_drag == _DragMode.brightness ||
        _drag == _DragMode.volume ||
        _drag == _DragMode.seek) {
      // keep indicator for a beat
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _seekPreview = null);
      });
      if (_drag != _DragMode.seek) {
        Timer(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _drag = _DragMode.none);
        });
        return;
      }
    }
    setState(() {
      if (_drag == _DragMode.seek) _seekPreview = null;
      _drag = _DragMode.none;
    });
  }

  // ---------------- controls visibility ----------------

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _player.state.playing && !_boost) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: _onDoubleTap,
        onLongPressStart: (_) => _setBoost(true),
        onLongPressEnd: (_) => _setBoost(false),
        onLongPressCancel: () => _setBoost(false),
        onScaleStart: _onScaleStart,
        onScaleUpdate: (d) => unawaited(_onScaleUpdate(d)),
        onScaleEnd: _onScaleEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && !_failed)
              ClipRect(
                child: Transform.scale(
                  scale: _zoom,
                  child: Video(
                    controller: _controller,
                    controls: NoVideoControls,
                  ),
                ),
              )
            else
              Center(child: CircularProgressIndicator(color: AppColors.accent)),

            if (_buffering && _ready)
              Center(
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child:
                      CircularProgressIndicator(color: AppColors.accent),
                ),
              ),

            // double-tap flash
            if (_seekFlash != null)
              Align(
                alignment: _seekFlashLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: _SeekPill(seconds: _seekFlash!),
                ),
              ),

            // scrub preview
            if (_seekPreview != null)
              Align(
                alignment: const Alignment(0, -0.35),
                child: _InfoPill(
                  icon: Icons.swap_horizontal_circle_outlined,
                  text:
                      '${formatDuration(_seekPreview!)} / ${formatDuration(_player.state.duration)}',
                ),
              ),

            // brightness indicator
            if (_drag == _DragMode.brightness)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: _LevelPill(
                      icon: Icons.brightness_6_rounded, value: _levelValue),
                ),
              ),

            // volume indicator
            if (_drag == _DragMode.volume)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 28),
                  child: _LevelPill(
                      icon: _levelValue == 0
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      value: _levelValue),
                ),
              ),

            // zoom badge
            if (_zoom > 1.001)
              Align(
                alignment: const Alignment(0, -0.75),
                child: _InfoPill(
                    icon: Icons.zoom_in_rounded,
                    text: '${_zoom.toStringAsFixed(1)}×'),
              ),

            // speed boost badge
            if (_boost)
              const Align(alignment: Alignment(0, -0.55), child: _SpeedBadge()),

            if (_controlsVisible) ...[
              _TopBar(title: _title),
              _BottomBar(player: _player),
              _CenterControls(player: _player),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeekPill extends StatelessWidget {
  const _SeekPill({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final back = seconds < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            back ? Icons.replay_10_rounded : Icons.forward_10_rounded,
            color: Colors.white,
            size: 26,
          ),
          const SizedBox(width: 6),
          Text(
            '${back ? '' : '+'}${seconds}s',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.icon, required this.value});

  final IconData icon;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: RotatedBox(
              quarterTurns: 3,
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: Colors.white24,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('${(value * 100).round()}%',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        '2×',
        style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 4,
          right: 16,
          bottom: 12,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon:
                  const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterControls extends StatelessWidget {
  const _CenterControls({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: player.state.playing,
        builder: (context, snap) {
          final playing = snap.data ?? false;
          return IconButton(
            iconSize: 68,
            color: Colors.white,
            icon: Icon(playing
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_filled_rounded),
            onPressed: player.playOrPause,
          );
        },
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: player.stream.duration,
              initialData: player.state.duration,
              builder: (context, durSnap) {
                final duration = durSnap.data ?? Duration.zero;
                final maxMs =
                    duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
                final valueMs = position.inMilliseconds.clamp(0, maxMs);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: valueMs.toDouble(),
                        max: maxMs.toDouble(),
                        onChanged: (ms) => player
                            .seek(Duration(milliseconds: ms.round())),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(formatDuration(position),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          Text(formatDuration(duration),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
MP_EOF_lib_screens_player_screen_dart
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
          ? Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _paths.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = _paths[i];
                return Card(
                  child: ListTile(
                    leading: Icon(Icons.folder_rounded,
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
          ? Center(
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
          ? Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : !_unlocked
              ? const SizedBox.shrink()
              : _videos.isEmpty
                  ? Center(
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
                    trailing: Icon(Icons.play_circle_outline_rounded,
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
          ? Center(
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
                    leading: Icon(Icons.playlist_play_rounded,
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
          ? Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : _videos.isEmpty
              ? Center(
                  child: Text('Empty playlist',
                      style: TextStyle(color: AppColors.textSecondary)))
              : VideoGrid(videos: _videos, onChanged: _resolve),
    );
  }
}
MP_EOF_lib_screens_playlists_screen_dart
mkdir -p "$(dirname "test/widget_test.dart")"
cat > "test/widget_test.dart" <<'MP_EOF_test_widget_test_dart'
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/badges.dart';
import 'package:maxplayer/utils/format.dart';
import 'package:maxplayer/utils/local_store.dart';
import 'package:maxplayer/utils/resume.dart';
import 'package:maxplayer/utils/sort.dart';

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

  group('sort comparators (v0.5)', () {
    test('cmpNum asc/desc', () {
      expect(cmpNum(1, 2, true) < 0, isTrue);
      expect(cmpNum(1, 2, false) > 0, isTrue);
      expect(cmpNum(7, 7, true), 0);
    });
    test('cmpStr case-insensitive asc/desc', () {
      expect(cmpStr('Alpha', 'beta', true) < 0, isTrue);
      expect(cmpStr('Alpha', 'beta', false) > 0, isTrue);
    });
    test('direction labels match design', () {
      expect(sortDirectionLabel(SortField.name, true), 'A → Z');
      expect(sortDirectionLabel(SortField.name, false), 'Z → A');
      expect(sortDirectionLabel(SortField.dateAdded, false), 'Newest first');
      expect(sortDirectionLabel(SortField.size, true), 'Smallest first');
      expect(sortDirectionLabel(SortField.length, true), 'Shortest first');
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
  echo "  v0.5 applied cleanly (display+gestures)."
  echo "  Ship the APK:"
  echo "    git add -A"
  echo "    git commit -m \"v0.5: display settings + gestures\""
  echo "    git push"
  echo "==============================================="
else
  echo "applied but analyzer reported issues - paste them in chat."
  exit 1
fi
