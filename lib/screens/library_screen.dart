import 'home_menu_screen.dart';
import 'appearance_screen.dart';
import 'language_screen.dart';
import '../utils/app_language.dart';
import '../services/app_analytics.dart';
import '../services/push_service.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/config.dart';

import '../theme.dart';
import '../utils/collections.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../utils/onboarding.dart';

import '../utils/quick_tiles.dart';
import '../utils/privacy_policy.dart';
import '../utils/settings.dart';
import '../utils/sort.dart';
import '../widgets/about_sheet.dart';
import '../widgets/discover_banner.dart';
import '../widgets/remote_tap.dart';
import '../widgets/user_manual_sheet.dart';
import '../widgets/video_grid.dart';
import '../services/native_bridge.dart';
import 'player_screen.dart';
import 'audio_screen.dart';
import 'discover_screen.dart';
import 'cloud_storage_screen.dart';
import 'display_settings_screen.dart';
import 'folders_screen.dart';
import 'history_screen.dart';
import 'network_storage_screen.dart';
import 'onboarding_flow.dart';
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
  static final _pageSize = 100;

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
    _wireOpenWith();
    _listScroll.addListener(_onListScroll);
    _load();
    AppSettings.instance.addListener(_onSettings);
    // First-run onboarding: Welcome → How to use → Video player guide.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboarding());
  }

  // v1.0.15 "Open with RunX Player": Gallery/Files ACTION_VIEW arrives
  // either parked on the cold-start intent (polled once below) or pushed
  // over the channel while the app runs. Both land in [_openSharedVideo].
  void _wireOpenWith() {
    NativeBridge.openWithVideoListener = (uri) {
      unawaited(_openSharedVideo(uri));
    };
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uri = await NativeBridge.getInitialVideo();
      if (uri != null) await _openSharedVideo(uri);
    });
  }

  Future<void> _openSharedVideo(String uri) async {
    if (!PlayerScreen.isOpen && mounted) {
      final played = await NativeBridge.resolveSharedVideo(uri);
      if (played == null || !mounted) return;
      final path = played['path'] as String?;
      if (path == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => played['stream'] == true
              ? PlayerScreen.stream(
                  path: path,
                  title: played['title'] as String? ?? 'Stream',
                )
              : PlayerScreen(
                  path: path,
                  title: played['title'] as String? ?? 'Video',
                ),
        ),
      );
    }
  }

  Future<void> _maybeShowOnboarding() async {
    final seen = await Onboarding.hasSeen();
    if (!seen && mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => OnboardingFlow()));
    }
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
      final ps = await PhotoManager.requestPermissionExtend().whenComplete(
        PushService.instance.mediaPermissionSettled,
      );
      if (!ps.isAuth && !ps.hasAccess) {
        CrashLog.crumb('library.permission_denied');
        // Always ask Android first. Permanent denial cannot be overridden;
        // never redirect to app settings automatically.
        if (mounted) {
          setState(() {
            _loading = false;
            _denied = true;
          });
        }
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: true,
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LText('Could not scan videos on this device')),
        );
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
      final batch = await path.getAssetListPaged(page: _page, size: _pageSize);
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
        warmVideoThumbs(_videos); // +47: pre-decode the first screenful
      } else {
        warmVideoThumbs(vids); // keep later pages warm too
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
    if (mounted) setState(() {}); // show the progress strip
    try {
      while (mounted && !_exhausted && token == _scanToken) {
        await _loadMore();
        await Future.delayed(Duration(milliseconds: 40));
      }
      if (token == _scanToken) {
        CrashLog.crumb('library.drained', {'count': _videos.length});
      }
    } finally {
      _draining = false;
      // v1.0.1+40: the flag flipped silently before, so the "Scanning x/y"
      // strip stayed on screen until something else rebuilt (stuck UI on
      // tablets, where the user rarely triggers extra rebuilds).
      if (mounted) setState(() {});
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
          return cmpNum(
            x.modifiedDateTime.millisecondsSinceEpoch,
            y.modifiedDateTime.millisecondsSinceEpoch,
            s.sortAsc,
          );
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

  bool _menuOpening = false;
  Future<void> _showHomeMenu() async {
    if (_menuOpening) return;
    _menuOpening = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => HomeMenuScreen(
            onSelected: (menuContext, action) =>
                _openMenu(_MenuAction.values.byName(action), from: menuContext),
          ),
        ),
      );
    } finally {
      _menuOpening = false;
    }
  }

  Future<void> _openMenu(_MenuAction a, {required BuildContext from}) async {
    final context = from;
    switch (a) {
      case _MenuAction.appearance:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => AppearanceScreen()));
        break;
      case _MenuAction.language:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => LanguageScreen()));
        break;
      case _MenuAction.display:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => DisplaySettingsScreen()))
            .then((_) => _refresh());
        break;
      case _MenuAction.stats:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => StatisticsScreen()))
            .then((_) => _refresh());
        break;
      case _MenuAction.manual:
        await UserManualSheet.show(context);
        break;
      case _MenuAction.about:
        await AboutSheet.show(context);
        break;
      case _MenuAction.privacy:
        await showPrivacyPolicyDialog(context);
        break;
      case _MenuAction.report:
        await launchUrl(
          Uri.parse(
            'mailto:$kMaxReportEmail'
            '?subject=${Uri.encodeComponent('RunX Player — report & feedback')}',
          ),
          mode: LaunchMode.externalApplication,
        );
        break;
      case _MenuAction.instagram:
        await launchUrl(
          Uri.parse(kMaxInstagramUrl),
          mode: LaunchMode.externalApplication,
        );
        break;
      case _MenuAction.telegram:
        await launchUrl(
          Uri.parse(kMaxTelegramUrl),
          mode: LaunchMode.externalApplication,
        );
        break;
    }
  }

  Future<void> _refresh() async {
    await _loadMeta();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: _denied && _videos.isEmpty
            ? Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _PermissionHint(onRetry: _load),
                          _buildTiles(),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: DiscoverBanner(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DiscoverScreen(videos: _videos),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : _loading && _videos.isEmpty
            ? Center(child: CircularProgressIndicator(color: AppColors.accent))
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
            children: [SizedBox(height: 140), _EmptyHint()],
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
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: DiscoverBanner(
            onTap: () {
              AppAnalytics.instance.trackFeatureOpen('discover');
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DiscoverScreen(videos: videos),
                ),
              );
            },
          ),
        ),
        // v28-old: the quick tiles slide away when scrolling down.
        ClipRect(
          child: AnimatedAlign(
            duration: Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            heightFactor: NativeBridge.isTelevision || _tilesVisible
                ? 1.0
                : 0.0,
            alignment: Alignment.topCenter,
            child: _buildTiles(),
          ),
        ),
        if (_isScanning)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: (_scanTotal != null && _scanTotal! > 0)
                      ? (_videos.length / _scanTotal!).clamp(0.0, 1.0)
                      : null,
                  color: AppColors.accent,
                  backgroundColor: AppColors.border,
                ),
                SizedBox(height: 6),
                Text(
                  _scanTotal != null
                      ? 'Scanning ${_videos.length}/$_scanTotal'
                      : 'Scanning ${_videos.length}…',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                SizedBox(height: 6),
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
        // v1.0.1+54: home banner — docks at the very bottom in REAL
        // layout space (nothing can ever overlap it). Zero-height until
        // an ad loads; stays collapsed on failure.
      ],
    );
  }

  // ---------------- header ----------------

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 12, 2, 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => LinearGradient(
                    // Exact old-app brand gradient from the supplied old app.
                    colors: [
                      Color(0xFFA78BFA),
                      Color(0xFF8B5CF6),
                      Color(0xFF22D3EE),
                    ],
                  ).createShader(bounds),
                  child: LText(
                    'RunX Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors
                          .white, // Opaque mask: retain the brand gradient in both themes
                    ),
                  ),
                ),
                LText(
                  'Proudly Developed in India 🇮🇳',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9.5,
                    letterSpacing: 0.3,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          _headIcon(
            Icons.search,
            'Search',
            () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => SearchScreen())),
          ),
          _headIcon(Icons.sync, 'Refresh', _load),
          _headIcon(
            Icons.history,
            'History',
            () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => HistoryScreen()))
                .then((_) => _refresh()),
          ),
          IconButton(
            tooltip: 'Settings and more',
            icon: Icon(Icons.more_vert, color: AppColors.accent),
            onPressed: _showHomeMenu,
          ),
        ],
      ),
    );
  }

  Widget _headIcon(IconData icon, String tip, VoidCallback onTap) => IconButton(
    tooltip: tip,
    // Stock old-app IconButton metrics: 24px glyph and 48px tap target.
    iconSize: 24,
    icon: Icon(icon, color: AppColors.accent),
    onPressed: onTap,
  );

  // ---------------- quick tiles (old 2x2 grids) ----------------

  final PageController _tilePager = PageController();
  int _tilePage = 0;

  Widget _buildTiles() {
    void push(Widget page, [String? feature]) {
      if (feature != null) AppAnalytics.instance.trackFeatureOpen(feature);
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => page)).then((_) => _refresh());
    }

    // v1.0.20: tiles are DATA-DRIVEN (lib/utils/quick_tiles.dart) — the
    // File Manager tile was replaced by Audio, and the positions of Cloud
    // Storage and Audio were interchanged. Ordering is unit-tested.
    final actions = <String, VoidCallback>{
      'privateSpace': () =>
          push(PrivateScreen(libraryVideos: _videos), 'private'),
      'playlists': () => push(PlaylistsScreen(), 'playlists'),
      'folders': () => push(FoldersScreen(), 'folders'),
      'audio': () => push(AudioScreen(), 'audio'),
      'networkStorage': () => push(NetworkStorageScreen(), 'network'),
      'cloudStorage': () => push(const CloudStorageScreen()),
      'openStream': () => push(OpenStreamScreen()),
      'quickShare': () => push(QuickShareScreen(), 'quickShare'),
    };

    Widget tileAt(QuickTileSpec spec) =>
        _Tile(spec.icon, spec.label, actions[spec.id] ?? () {});

    Widget grid(List<QuickTileSpec> items) => Column(
      children: [
        Row(
          children: [
            Expanded(child: tileAt(items[0])),
            SizedBox(width: 8),
            Expanded(child: tileAt(items[1])),
          ],
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: tileAt(items[2])),
            SizedBox(width: 8),
            Expanded(child: tileAt(items[3])),
          ],
        ),
      ],
    );

    if (NativeBridge.isTelevision || MediaQuery.sizeOf(context).width >= 900) {
      final tiles = [...kQuickTilesPage1, ...kQuickTilesPage2];
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Column(
          children: [
            for (var row = 0; row < 2; row++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    for (var col = 0; col < 4; col++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: tileAt(tiles[row * 4 + col]),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 106,
            child: PageView(
              controller: _tilePager,
              onPageChanged: (i) => setState(() => _tilePage = i),
              children: [grid(kQuickTilesPage1), grid(kQuickTilesPage2)],
            ),
          ),
          SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var dot = 0; dot < 2; dot++) ...[
                if (dot > 0) SizedBox(width: 6),
                AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  width: _tilePage == dot ? 14 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _tilePage == dot
                        ? AppColors.accent
                        : AppColors.border,
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
    Theme.of(context);
    final accent = AppColors.accent;
    // Old frosted-glass tile (backdrop blur over the shared canvas).
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(12),
      child: RemoteTap(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.surfaceAlt, AppColors.surface],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.textPrimary.withValues(alpha: 0.14),
                width: 1,
              ),
            ),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, color: accent, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: LText(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
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
    );
  }
}

enum _MenuAction {
  appearance,
  language,
  display,
  stats,
  manual,
  about,
  privacy,
  report,
  instagram,
  telegram,
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
    Theme.of(context);
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
              padding: EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: Text(
                '$name  ·  ${items.length}',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            // Old grid geometry (maxCrossAxisExtent 200, 8px gaps, 1.18
            // ratio): size the non-scrolling inner grid exactly so it never
            // clips or scrolls on its own.
            LayoutBuilder(
              builder: (context, c) {
                final hPad = 16.0; // 8 + 8
                final vPad = 16.0; // 4 + 12
                final spacing = 8.0;
                final gridW = c.maxWidth - hPad;
                final cols = (gridW / (c.maxWidth >= 900 ? 300 : 200))
                    .ceil()
                    .clamp(1, 100);
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
    Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 52,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 16),
            LText(
              'Permission needed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            LText(
              'RunX Player needs access to your videos to show the library.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onRetry,
              child: LText('Grant access'),
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
    Theme.of(context);
    return Center(
      child: LText(
        'No videos found. Pull down to rescan.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
