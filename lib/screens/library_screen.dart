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
