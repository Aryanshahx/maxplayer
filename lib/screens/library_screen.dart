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
