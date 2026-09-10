import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/collections.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../utils/settings.dart';
import '../utils/sort.dart';
import '../widgets/discover_section.dart';
import '../widgets/video_grid.dart';
import 'display_settings_screen.dart';
import 'folders_screen.dart';
import 'history_screen.dart';
import 'info_screens.dart';
import 'playlists_screen.dart';
import 'private_screen.dart';
import 'search_screen.dart';
import 'statistics_screen.dart';

/// Home — compact gradient header, tool tiles, Discover (TMDB), and the
/// full library grid/list. Pull down anywhere to rescan the WHOLE device
/// (all folders), with duplicate guards and background page draining.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _pageSize = 100;

  final _store = LocalStore();

  bool _loading = true;
  bool _denied = false;

  final List<AssetEntity> _videos = [];
  AssetPathEntity? _allPath;
  int _page = 0;
  bool _exhausted = false;
  bool _loadingMore = false;
  bool _draining = false;
  int _scanToken = 0; // cancels stale background drains on rescan

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
    super.dispose();
  }

  void _onSettings() {
    if (AppSettings.instance.sortField == SortField.size) {
      unawaited(_ensureSizes());
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensureSizes() async {
    await Future.wait(_videos.map(videoSize));
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final token = ++_scanToken;
    setState(() {
      _loading = true;
      _denied = false;
    });
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) {
        CrashLog.crumb('library.permission_denied');
        if (mounted) {
          setState(() {
            _loading = false;
            _denied = true;
          });
        }
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
      unawaited(_drainAll(token)); // background: fill in everything
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
    if (path == null || _exhausted || _loadingMore) return;
    _loadingMore = true;
    try {
      final batch =
          await path.getAssetListPaged(page: _page, size: _pageSize);
      if (batch.length < _pageSize) _exhausted = true;
      _page++;
      final vids = batch.where((a) => a.type == AssetType.video).toList();
      final merged = appendUnique(_videos, vids, (a) => a.id);
      if (merged.length != _videos.length) {
        _videos
          ..clear()
          ..addAll(merged);
      }
      if (mounted) setState(() {});
    } finally {
      _loadingMore = false;
    }
  }

  /// Background drain: after the first page is on screen, keep paging
  /// until EVERY video on the device is visible/counted.
  Future<void> _drainAll(int token) async {
    if (_draining) return;
    _draining = true;
    try {
      while (mounted && !_exhausted && token == _scanToken) {
        await _loadMore();
        await Future.delayed(const Duration(milliseconds: 40));
      }
      if (token == _scanToken) {
        CrashLog.crumb('library.drained', {'count': _videos.length});
      }
    } finally {
      _draining = false;
    }
  }

  List<AssetEntity> get _visibleVideos {
    final s = AppSettings.instance;
    final list = _videos.where((a) {
      if (_priv.contains(a.id)) return false;
      if (s.onlyFavs && !_favs.contains(a.id)) return false;
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
          applicationVersion: '0.6.0',
          applicationLegalese:
              'Local-first. Ad-free. Proudly Developed in India.',
          children: const [
            Text('MPV (libmpv + FFmpeg) engine.\nNo accounts. No tracking.',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        );
        return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page!))
        .then((_) => _refresh());
  }

  Future<void> _refresh() async {
    await _loadMeta();
    if (mounted) setState(() {});
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
    final content = videos.isEmpty
        ? ListView(
            // keeps pull-to-refresh usable on empty state
            children: const [
              SizedBox(height: 140),
              _EmptyHint(),
            ],
          )
        : s.groupBy == GroupBy.folder
            ? _GroupedView(
                videos: videos,
                listMode: s.viewMode == ViewMode.list,
                onChanged: _refresh,
              )
            : VideoGrid(
                key: ValueKey('${s.viewMode}_${videos.length}'),
                videos: videos,
                listMode: s.viewMode == ViewMode.list,
                onChanged: _refresh,
              );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        _buildTiles(),
        const DiscoverSection(),
        const SizedBox(height: 4),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            onRefresh: _load, // slide down = full device rescan
            child: content,
          ),
        ),
      ],
    );
  }

  // ---------------- header ----------------

  Widget _buildHeader() {
    final accent = AppColors.accent;
    final hsl = HSLColor.fromColor(accent);
    final g1 = hsl.withHue((hsl.hue + 40) % 360).toColor();
    final g3 =
        hsl.withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0)).toColor();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 2, 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (r) =>
                      LinearGradient(colors: [g1, accent, g3]).createShader(r),
                  child: const Text(
                    'Max Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const Text(
                  'Proudly Developed in India 🇮🇳',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          _headIcon(Icons.search_rounded, 'Search', () => Navigator.of(context)
              .push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()))),
          _headIcon(Icons.refresh_rounded, 'Refresh', _load),
          _headIcon(Icons.history_rounded, 'History', () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(
                      builder: (_) => const HistoryScreen()))
                  .then((_) => _refresh())),
          PopupMenuButton<_MenuAction>(
            iconSize: 21,
            padding: EdgeInsets.zero,
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
                  child: _MenuRow(
                      icon: Icons.bar_chart_rounded, label: 'Statistics')),
              PopupMenuItem(
                  value: _MenuAction.manual,
                  child: _MenuRow(
                      icon: Icons.menu_book_outlined, label: 'User manual')),
              PopupMenuItem(
                  value: _MenuAction.about,
                  child: _MenuRow(
                      icon: Icons.info_outline_rounded, label: 'About')),
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

  Widget _headIcon(IconData icon, String tip, VoidCallback onTap) =>
      IconButton(
        tooltip: tip,
        iconSize: 20,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        icon: Icon(icon, color: AppColors.textPrimary),
        onPressed: onTap,
      );

  // ---------------- tiles (fixed height, horizontal growth only) ----------------

  Widget _buildTiles() {
    Widget tile(IconData icon, String label, VoidCallback onTap) => SizedBox(
          height: 56,
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: AppColors.accent, size: 19),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        );

    void push(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page))
        .then((_) => _refresh());

    final tiles = [
      (Icons.folder_outlined, 'Folders', () => push(const FoldersScreen())),
      (Icons.playlist_play_rounded, 'Playlists',
          () => push(const PlaylistsScreen())),
      (Icons.lock_outline_rounded, 'Private Space',
          () => push(const PrivateScreen())),
      (Icons.history_rounded, 'History', () => push(const HistoryScreen())),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth >= 640) {
            // wide screens: one row of four, same height
            return Row(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: tile(tiles[i].$1, tiles[i].$2, tiles[i].$3)),
                ],
              ],
            );
          }
          return Column(
            children: [
              Row(children: [
                Expanded(child: tile(tiles[0].$1, tiles[0].$2, tiles[0].$3)),
                const SizedBox(width: 10),
                Expanded(child: tile(tiles[1].$1, tiles[1].$2, tiles[1].$3)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: tile(tiles[2].$1, tiles[2].$2, tiles[2].$3)),
                const SizedBox(width: 10),
                Expanded(child: tile(tiles[3].$1, tiles[3].$2, tiles[3].$3)),
              ]),
            ],
          );
        },
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
      child: Text('No videos found. Pull down to rescan.',
          style: TextStyle(color: AppColors.textSecondary)),
    );
  }
}
