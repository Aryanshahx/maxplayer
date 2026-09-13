import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../app_info.dart';
import '../theme.dart';
import '../utils/collections.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../utils/privacy_policy.dart';
import '../utils/settings.dart';
import '../utils/sort.dart';
import '../widgets/about_sheet.dart';
import '../widgets/discover_banner.dart';
import '../widgets/user_manual_sheet.dart';
import '../widgets/video_grid.dart';
import 'cloud_storage_screen.dart';
import 'discover_screen.dart';
import 'display_settings_screen.dart';
import 'file_manager_screen.dart';
import 'folders_screen.dart';
import 'history_screen.dart';
import 'network_storage_screen.dart';
import 'open_stream_screen.dart';
import 'playlists_screen.dart';
import 'private_screen.dart';
import 'quick_share_screen.dart';
import 'search_screen.dart';
import 'statistics_screen.dart';

/// Home — compact gradient header, two slideable 2x2 quick-tile grids
/// (old-player look, hide-on-scroll), Discover (TMDB), scan progress, and
/// the full library grid. Pull down anywhere to rescan the WHOLE device.
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
  int? _scanTotal; // asset count for the scan progress bar (null = unknown)
  int _page = 0;
  bool _exhausted = false;
  bool _loadingMore = false;
  bool _draining = false;
  int _scanToken = 0; // cancels stale background drains on rescan

  Set<String> _favs = {};
  Set<String> _priv = {};

  /// v28-old: the quick-tile grids tuck away while scrolling DOWN through
  /// the videos and slide back when scrolling up / reaching the top.
  final ScrollController _listScroll = ScrollController();
  double _lastListOffset = 0;
  bool _tilesVisible = true;

  void _onListScroll() {
    final offset = _listScroll.offset;
    final goingDown = offset > _lastListOffset + 6;
    final goingUp = offset < _lastListOffset - 6;
    if (_tilesVisible && goingDown && offset > 24) {
      setState(() => _tilesVisible = false);
    } else if (!_tilesVisible && (goingUp || offset <= 24)) {
      setState(() => _tilesVisible = true);
    }
    _lastListOffset = offset;
  }

  @override
  void initState() {
    super.initState();
    _listScroll.addListener(_onListScroll);
    _load();
    AppSettings.instance.addListener(_onSettings);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettings);
    _listScroll.dispose();
    _tilePager.dispose();
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
      _scanTotal = null;
      final path = _allPath;
      if (path != null) {
        try {
          _scanTotal = await path.assetCountAsync;
        } catch (_) {
          _scanTotal = null;
        }
      }
      _page = 0;
      _exhausted = false;
      // Keep the current grid/list on screen during a rescan: the first
      // _loadMore below atomically swaps in the fresh first page, so
      // deleted videos disappear without blanking the whole screen.
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
      final firstPage = _page == 0;
      _page++;
      final vids = batch.where((a) => a.type == AssetType.video).toList();
      if (firstPage) {
        // First fresh page of a scan: swap the visible list in one go so
        // removed videos vanish, WITHOUT clearing during the async fetch
        // (that is what blanked the screen on rescan).
        _videos
          ..clear()
          ..addAll(vids);
      } else {
        final merged = appendUnique(_videos, vids, (a) => a.id);
        if (merged.length != _videos.length) {
          _videos
            ..clear()
            ..addAll(merged);
        }
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

  /// True while the device is being scanned (initial load or background
  /// drain) — drives the old-style scan progress bar.
  bool get _isScanning => _loading || _draining;

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
    switch (a) {
      case _MenuAction.display:
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => const DisplaySettingsScreen()))
            .then((_) => _refresh());
        break;
      case _MenuAction.stats:
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => const StatisticsScreen()))
            .then((_) => _refresh());
        break;
      case _MenuAction.manual:
        UserManualSheet.show(context);
        break;
      case _MenuAction.about:
        AboutSheet.show(context);
        break;
      case _MenuAction.privacy:
        showPrivacyPolicyDialog(context);
        break;
    }
  }

  Future<void> _refresh() async {
    await _loadMeta();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _denied && _videos.isEmpty
            ? _PermissionHint(onRetry: _load)
            : _loading && _videos.isEmpty
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.accent))
                : _buildHome(),
      ),
    );
  }

  Widget _buildHome() {
    final videos = _visibleVideos;
    final s = AppSettings.instance;
    final content = videos.isEmpty
        ? ListView(
            controller: _listScroll,
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
                controller: _listScroll,
              )
            : VideoGrid(
                key: ValueKey('${s.viewMode}_${videos.length}'),
                videos: videos,
                listMode: s.viewMode == ViewMode.list,
                onChanged: _refresh,
                controller: _listScroll,
              );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: DiscoverBanner(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DiscoverScreen(videos: videos),
              ),
            ),
          ),
        ),
        // v28-old: the quick tiles slide away when scrolling down.
        ClipRect(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            heightFactor: _tilesVisible ? 1.0 : 0.0,
            alignment: Alignment.topCenter,
            child: _buildTiles(),
          ),
        ),
        if (_isScanning)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: (_scanTotal != null && _scanTotal! > 0)
                      ? (_videos.length / _scanTotal!).clamp(0.0, 1.0)
                      : null,
                  color: AppColors.accent,
                  backgroundColor: Colors.white10,
                ),
                const SizedBox(height: 6),
                Text(
                  _scanTotal != null
                      ? 'Scanning ${_videos.length}/$_scanTotal'
                      : 'Scanning ${_videos.length}…',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 2, 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    // Old app's exact brand gradient (purple -> violet ->
                    // cyan), fixed and never theme-tinted.
                    colors: [
                      Color(0xFFA78BFA),
                      Color(0xFF8B5CF6),
                      Color(0xFF22D3EE),
                    ],
                  ).createShader(bounds),
                  child: const Text(
                    'Max Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.white, // ShaderMask paints over this
                    ),
                  ),
                ),
                const Text(
                  'Proudly Developed in India 🇮🇳',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 9.5, color: AppColors.textSecondary),
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
            iconSize: 24,
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert_rounded, color: AppColors.accent),
            color: const Color(0xFF1a1a24),
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            onSelected: _openMenu,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _MenuAction.display,
                height: 44,
                child: _MenuRow(
                    icon: Icons.tune_rounded, label: 'Display settings'),
              ),
              PopupMenuItem(
                value: _MenuAction.stats,
                height: 44,
                child: _MenuRow(
                    icon: Icons.bar_chart_rounded, label: 'Watch statistics'),
              ),
              PopupMenuItem(
                value: _MenuAction.manual,
                height: 44,
                child: _MenuRow(
                    icon: Icons.menu_book_outlined, label: 'User manual'),
              ),
              PopupMenuItem(
                value: _MenuAction.about,
                height: 44,
                child: _MenuRow(
                    icon: Icons.info_outline_rounded, label: 'About Max Player'),
              ),
              PopupMenuItem(
                value: _MenuAction.privacy,
                height: 44,
                child: _MenuRow(
                    icon: Icons.privacy_tip_outlined, label: 'Privacy policy'),
              ),
              const PopupMenuDivider(height: 1),
              const PopupMenuItem(
                value: _MenuAction.display,
                enabled: false,
                height: 30,
                padding: EdgeInsets.zero,
                child: Center(
                  child: Text(
                    'Version $kAppVersion',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headIcon(IconData icon, String tip, VoidCallback onTap) =>
      IconButton(
        tooltip: tip,
        // Old app uses the stock IconButton metrics: 24px glyphs on the
        // default 48px tap target.
        iconSize: 24,
        icon: Icon(icon, color: AppColors.accent),
        onPressed: onTap,
      );

  // ---------------- quick tiles (old 2x2 grids) ----------------

  final PageController _tilePager = PageController();
  int _tilePage = 0;

  Widget _buildTiles() {
    void push(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page))
        .then((_) => _refresh());

    final page1 = [
      (Icons.lock_outline_rounded, 'Private Space',
          () => push(PrivateScreen(libraryVideos: _videos))),
      (Icons.queue_music_outlined, 'Playlists',
          () => push(const PlaylistsScreen())),
      (Icons.folder_outlined, 'Folders', () => push(const FoldersScreen())),
      (Icons.cloud_queue_outlined, 'Cloud Storage',
          () => push(const CloudStorageScreen())),
    ];
    final page2 = [
      (Icons.dns_outlined, 'Network Storage',
          () => push(const NetworkStorageScreen())),
      (Icons.folder_shared_outlined, 'File Manager',
          () => push(const FileManagerScreen())),
      (Icons.link, 'Open Stream(iptv)', () => push(const OpenStreamScreen())),
      (Icons.ios_share, 'Quick Share', () => push(const QuickShareScreen())),
    ];

    Widget grid(List<(IconData, String, void Function())> items) => Column(
          children: [
            Row(
              children: [
                Expanded(child: _Tile(items[0].$1, items[0].$2, items[0].$3)),
                const SizedBox(width: 8),
                Expanded(child: _Tile(items[1].$1, items[1].$2, items[1].$3)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _Tile(items[2].$1, items[2].$2, items[2].$3)),
                const SizedBox(width: 8),
                Expanded(child: _Tile(items[3].$1, items[3].$2, items[3].$3)),
              ],
            ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 106,
            child: PageView(
              controller: _tilePager,
              onPageChanged: (i) => setState(() => _tilePage = i),
              children: [grid(page1), grid(page2)],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var dot = 0; dot < 2; dot++) ...[
                if (dot > 0) const SizedBox(width: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _tilePage == dot ? 14 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _tilePage == dot
                        ? AppColors.accent
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Tile(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    // Old frosted-glass tile (backdrop blur over the shared canvas).
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: accent.withValues(alpha: 0.25),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.11),
                    accent.withValues(alpha: 0.04),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14), width: 1),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(icon, color: accent, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}

class _GroupedView extends StatelessWidget {
  const _GroupedView({
    required this.videos,
    required this.listMode,
    required this.onChanged,
    this.controller,
  });

  final List<AssetEntity> videos;
  final bool listMode;
  final VoidCallback onChanged;
  final ScrollController? controller;

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
      controller: controller,
      itemCount: names.length,
      itemBuilder: (context, i) {
        final name = names[i];
        final items = groups[name]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: Text('$name  ·  ${items.length}',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
            ),
            // Old grid geometry (maxCrossAxisExtent 200, 8px gaps, 1.18
            // ratio): size the non-scrolling inner grid exactly so it never
            // clips or scrolls on its own.
            LayoutBuilder(
              builder: (context, c) {
                const hPad = 16.0; // 8 + 8
                const vPad = 16.0; // 4 + 12
                const spacing = 8.0;
                final gridW = c.maxWidth - hPad;
                final cols = (gridW / 200).ceil().clamp(2, 6);
                final cellW = (gridW - (cols - 1) * spacing) / cols;
                final cellH = cellW / 1.18;
                final height = listMode
                    ? items.length * 68.0 + vPad
                    : ((items.length + cols - 1) ~/ cols) * (cellH + spacing) -
                        spacing +
                        vPad;
                return SizedBox(
                  height: height,
                  child: VideoGrid(
                    videos: items,
                    listMode: listMode,
                    onChanged: onChanged,
                  ),
                );
              },
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
                foregroundColor: AppColors.onAccent,
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
