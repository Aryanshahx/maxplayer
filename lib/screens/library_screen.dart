import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/crash_log.dart';
import '../utils/formatters.dart';
import '../utils/privacy_policy.dart';
import '../utils/storage_permission.dart';
import '../widgets/about_sheet.dart';
import '../widgets/display_settings_sheet.dart';
import '../state/private_vault.dart';
import '../widgets/mini_player.dart';
import '../services/resume_sync_service.dart';
import '../widgets/cleaner_sheet.dart';
import '../widgets/discover_banner.dart';
import '../widgets/video_search_delegate.dart';
import '../widgets/playlists_sheet.dart';
import '../widgets/user_manual_sheet.dart';
import '../widgets/cloud_storage_sheet.dart';
import '../widgets/network_storage_sheet.dart';
import '../widgets/open_stream_sheet.dart';
import 'file_manager_screen.dart';
import 'private_screen.dart';
import '../widgets/video_list_item.dart';
import '../widgets/video_tile.dart';
import 'discover_screen.dart';
import 'history_screen.dart';
import 'player_screen.dart';
import 'stats_screen.dart';

class LibraryScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;

  const LibraryScreen({super.key, required this.library, required this.player});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  /// v26: last known Private-vault change counter. Returning from the
  /// Private folder rescans ONLY when this differs (see below) - a plain
  /// look inside no longer reloads the library grid.
  int _lastVaultRevision = PrivateVault.revision;

  /// v28: the quick-tiles grid tucks away while scrolling DOWN through
  /// the videos and slides back when scrolling up / reaching the top.
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
    widget.library.addListener(_onChange);
    // Automatically ask for storage permission and scan the whole device
    // the first time this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.library.folderName == null && !widget.library.isScanning) {
        widget.library.scanAllStorage();
      }
      // If the previous session died with an error, offer the recorded
      // crash report (copyable) so it can be sent for analysis.
      CrashLog.takeLastIncludingNative().then((report) {
        if (report != null && mounted) _showCrashReport(report);
      });
    });
  }

  void _showCrashReport(String report) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Max Player closed unexpectedly',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            report,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: report));
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Crash report copied - send it to the developer',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _listScroll.dispose();
    widget.library.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  void _playVideo(VideoTrack track) {
    final lib = widget.library;
    if (lib.playbackAction == PlaybackAction.single) {
      // Queue only the tapped file.
      widget.player.setPlaylistAndPlay([track], 0);
    } else {
      // Queue every visible video, starting at the tapped one.
      final all = lib.videos;
      final idx = all.indexWhere((v) => v.id == track.id);
      widget.player.setPlaylistAndPlay(all, idx >= 0 ? idx : 0);
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  /// v21: long-press a video -> offer moving it into the Private folder.
  Future<void> _offerHide(VideoTrack track, VideoLibraryState lib) async {
    // v22: moving a file out of public storage needs the same grant the
    // scanner uses. Ask up-front instead of letting the move fail with a
    // cryptic snackbar. v40: version-aware via the shared helper - asking
    // ONLY "All files access" resolved denied FOREVER on Android 10 and
    // older, so those phones kept re-asking a permission already granted.
    if (!await ensureStorageAccess()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Private folder needs storage permission: allow it, then '
            'long-press the video again',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text(
          'Move to Private folder?',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Text(
          '"${track.title}" moves into the app\'s private folder - invisible '
          'to Gallery and file managers, visible here only after your PIN.\n\n'
          'Warning: uninstalling the app deletes hidden videos.',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('Hide'),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await PrivateVault().hide(track.path);
                widget.player.removeHistoryEntry(track.path);
                lib.rescan();
                // v26: the rescan above already reflects this move - keep
                // the stamp in sync so closing the Private folder later
                // doesn't rescan AGAIN for the same change.
                _lastVaultRevision = PrivateVault.revision;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Moved to Private folder')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  // v22: show WHY it failed (was a bare "Could not hide")
                  final why = e
                      .toString()
                      .replaceAll('FileSystemException: ', '')
                      .replaceAll('Exception: ', '');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not hide: $why')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// v28: the Private folder moved from the top bar into the quick-tiles
  /// grid. v26: rescan on return ONLY when something was actually
  /// hidden/unhidden inside (the revision counter moves on every vault
  /// file move) - a plain visit no longer reloads the grid.
  Future<void> _openPrivate(VideoLibraryState lib) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        // v29: the vault screen gets the library too (its "+" button
        // moves selected videos into the vault).
        builder: (_) => PrivateScreen(player: widget.player, library: lib),
      ),
    );
    final rev = PrivateVault.revision;
    if (rev != _lastVaultRevision) {
      _lastVaultRevision = rev;
      lib.rescan();
    }
  }

  /// v40 "Playlists" tile: NAMED, persistent playlists (create by name,
  /// add videos, play, rename, delete) - they survive app restarts.
  ///
  /// Replaces the v28-v30 design: one anonymous in-memory queue shown in a
  /// sheet with a Build-playlist button. That queue vanished on every
  /// restart ("playlists are not saving, they disappear after reopening"),
  /// and the button is gone now (requested: "remove build playlist button,
  /// add multiple playlists by names"). The player's own side panel still
  /// shows the now-playing queue inside the player screen.
  void _showPlaylists(VideoLibraryState lib) {
    PlaylistsSheet.show(context, library: lib, player: widget.player);
  }

  /// v28 "Folders" tile: show only one folder's videos (or everything).
  void _showFoldersSheet(VideoLibraryState lib) {
    final counts = lib.folderCounts;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: Icon(
                Icons.video_library_outlined,
                color: themeState.accent,
              ),
              title: const Text(
                'All videos',
                style: TextStyle(color: Colors.white),
              ),
              trailing: lib.folderFilter == null
                  ? Icon(Icons.check, color: themeState.accent)
                  : Text(
                      '${lib.allVideosCount}',
                      style: const TextStyle(color: Colors.white38),
                    ),
              onTap: () {
                lib.setFolderFilter(null);
                Navigator.of(sheetContext).pop();
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in counts.entries)
                    ListTile(
                      leading: Icon(
                        Icons.folder_outlined,
                        color: themeState.accent,
                      ),
                      title: Text(
                        e.key,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${e.value} ${e.value == 1 ? 'video' : 'videos'}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      trailing: lib.folderFilter == e.key
                          ? Icon(Icons.check, color: themeState.accent)
                          : null,
                      onTap: () {
                        lib.setFolderFilter(e.key);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _onMenuChoice(String choice, VideoLibraryState lib) {
    switch (choice) {
      case 'display':
        DisplaySettingsSheet.show(context, lib);
        break;
      case 'rescan':
        _rescan(lib);
        break;
      case 'stats':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StatsScreen(player: widget.player)),
        );
        break;
      case 'manual':
        UserManualSheet.show(context);
        break;
      case 'about':
        AboutSheet.show(context);
        break;
      case 'privacy':
        showPrivacyPolicyDialog(context);
        break;
    }
  }

  /// User-triggered rescan (top-bar ⟳ button or the ⋮ menu entry) with
  /// feedback so it's obvious something is happening.
  void _rescan(VideoLibraryState lib) {
    if (lib.isScanning) return;
    lib.rescan();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rescanning device for videos…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _playNetworkOrStream(String url, String title) async {
    await widget.player.playStream(url, title);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  /// v88: for files fetched via real Google sign-in - private Drive files
  /// need an Authorization header to stream, not just a URL.
  Future<void> _playAuthenticatedCloudStream(
    String url,
    String title,
    Map<String, String> headers,
  ) async {
    await widget.player.playCloudStream(url, title, headers);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  void _openStreamSheet() {
    OpenStreamSheet.show(context, onPlay: _playNetworkOrStream);
  }

  void _openNetworkStorage() {
    NetworkStorageSheet.show(context, onPlay: _playNetworkOrStream);
  }

  void _openCloudStorage() {
    CloudStorageSheet.show(
      context,
      onPlay: _playNetworkOrStream,
      onPlayAuthenticated: _playAuthenticatedCloudStream,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF22D3EE)],
          ).createShader(bounds),
          child: const Text(
            'Max Player',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        actions: [
          // v44: library search moved HERE - a full-screen search page,
          // so the home screen keeps room for the Discover banner.
          IconButton(
            tooltip: 'Search videos',
            icon: Icon(Icons.search, color: themeState.accent),
            onPressed: () => showSearch<void>(
              context: context,
              delegate: VideoSearchDelegate(
                videos: lib.allVideos,
                onOpen: _playVideo,
              ),
            ),
          ),
          // v26: all home-screen buttons follow the picked theme colour.
          // Prominent rescan button (new videos don't appear otherwise).
          IconButton(
            tooltip: 'Rescan library',
            onPressed: lib.isScanning ? null : () => _rescan(lib),
            icon: lib.isScanning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: themeState.accent,
                    ),
                  )
                : Icon(Icons.sync, color: themeState.accent),
          ),
          IconButton(
            tooltip: 'History',
            icon: Icon(Icons.history, color: themeState.accent),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryScreen(player: widget.player),
              ),
            ),
          ),

          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_vert, color: themeState.accent),
            color: const Color(0xFF26262f),
            onSelected: (choice) => _onMenuChoice(choice, lib),
            // v26: menu icons follow the picked theme colour.
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'display',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune, color: themeState.accent),
                  title: const Text('Display settings'),
                ),
              ),
              PopupMenuItem(
                value: 'rescan',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh, color: themeState.accent),
                  title: const Text('Rescan library'),
                ),
              ),
              PopupMenuItem(
                value: 'stats',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bar_chart, color: themeState.accent),
                  title: const Text('Statistics'),
                ),
              ),
              PopupMenuItem(
                value: 'manual',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.menu_book_outlined,
                    color: themeState.accent,
                  ),
                  title: const Text('User manual'),
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline, color: themeState.accent),
                  title: const Text('About'),
                ),
              ),
              PopupMenuItem(
                value: 'privacy',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.privacy_tip_outlined, color: themeState.accent),
                  title: const Text('Privacy policy'),
                ),
              ),
              // Footer: app version (not selectable).
              const PopupMenuItem(
                value: 'version',
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
      // Mini player sits at the bottom while something is loaded.
      bottomNavigationBar: MiniPlayer(player: widget.player),
      body: Column(
        children: [
          // v44: the search BOX became an app-bar icon (full-screen
          // search page). Its place now holds the Discover banner -
          // latest trending posters shine through behind the title.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: DiscoverBanner(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DiscoverScreen(library: lib, player: widget.player),
                ),
              ),
            ),
          ),
          // v69 C3: Wi-Fi Resume-Sync Banner
          ValueListenableBuilder<RemoteResumeBeacon?>(
            valueListenable: ResumeSyncService.instance.remoteBeacon,
            builder: (context, beacon, _) {
              if (beacon == null) return const SizedBox.shrink();
              final pos = formatDuration(Duration(seconds: beacon.positionSecs));
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: themeState.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: themeState.accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_tethering, color: themeState.accent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Playing on ${beacon.device}',
                              style: TextStyle(
                                color: themeState.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${beacon.title} ($pos)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: themeState.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          final ok = await ResumeSyncService.instance.resumeOnThisDevice(
                            beacon,
                            lib,
                            widget.player,
                          );
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not find this video in your local library.'),
                              ),
                            );
                          }
                        },
                        child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                        onPressed: () => ResumeSyncService.instance.remoteBeacon.value = null,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // v28: active folder filter chip (set from the Folders tile).
          if (lib.folderFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: themeState.accent,
                  ),
                  label: Text('Folder: ${lib.folderFilter}'),
                  labelStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  onDeleted: () => lib.setFolderFilter(null),
                  deleteIconColor: Colors.white54,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: themeState.accent.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
          // v28/v87: Two slideable 2x2 grids with 2 dots indicator.
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              heightFactor: _tilesVisible ? 1.0 : 0.0,
              alignment: Alignment.topCenter,
              child: _QuickTiles(
                accent: themeState.accent,
                onPrivate: () => _openPrivate(lib),
                onPlaylist: () => _showPlaylists(lib),
                onFolders: () => _showFoldersSheet(lib),
                onFileManager: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        FileManagerScreen(library: lib, player: widget.player),
                  ),
                ),
                onNetworkStorage: _openNetworkStorage,
                onCloudStorage: _openCloudStorage,
                onOpenStream: _openStreamSheet,
                onCleaner: () => CleanerSheet.show(
                  context,
                  player: widget.player,
                  library: lib,
                ),
              ),
            ),
          ),
          if (lib.isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: lib.scanProgress.total > 0
                        ? lib.scanProgress.processed / lib.scanProgress.total
                        : null,
                    color: themeState.accent,
                    backgroundColor: Colors.white10,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scanning ${lib.scanProgress.processed}/${lib.scanProgress.total}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          // Soft crossfade between grid/list/empty states.
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _buildBody(lib),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(VideoLibraryState lib) {
    // Single evaluation - the getter filters+sorts, so compute once per build.
    final groups = lib.groups;
    final visibleCount = groups.fold<int>(0, (sum, g) => sum + g.videos.length);

    if (visibleCount == 0) {
      return _EmptyState(
        key: const ValueKey('empty'),
        isScanning: lib.isScanning,
        permissionDenied: lib.permissionDenied,
        favoritesOnly: lib.favoritesOnly,
        onGrantAccess: lib.scanAllStorage,
      );
    }

    // Keyed by view mode so grid <-> list crossfades through the
    // AnimatedSwitcher above. v28: the controller drives the quick-tiles
    // auto-hide on downward scrolls.
    return CustomScrollView(
      key: ValueKey(lib.viewMode),
      controller: _listScroll,
      slivers: [
        for (final group in groups) ...[
          if (lib.groupMode != GroupMode.none)
            SliverToBoxAdapter(
              child: _GroupHeader(
                title: group.title,
                count: group.videos.length,
              ),
            ),
          if (lib.viewMode == ViewMode.grid)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.18,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final track = group.videos[i];
                  return GestureDetector(
                    // v21: long-press moves the video to the Private folder.
                    onLongPress: () => _offerHide(track, lib),
                    child: VideoTile(
                      track: track,
                      isFavorite: lib.isFavorite(track),
                      onTap: () => _playVideo(track),
                      onFavorite: () => lib.toggleFavorite(track),
                    ),
                  );
                }, childCount: group.videos.length),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final track = group.videos[i];
                  return GestureDetector(
                    // v21: long-press moves the video to the Private folder.
                    onLongPress: () => _offerHide(track, lib),
                    child: VideoListItem(
                      track: track,
                      isFavorite: lib.isFavorite(track),
                      onTap: () => _playVideo(track),
                      onFavorite: () => lib.toggleFavorite(track),
                    ),
                  );
                }, childCount: group.videos.length),
              ),
            ),
        ],
      ],
    );
  }
}

/// v28/v87: Two slideable 2x2 grids with 2 dots page indicator.
/// Page 1: Private Space, Playlists, Folders, File Manager
/// Page 2: Network Storage, Cloud Storage, Open Stream, Cleaner
class _QuickTiles extends StatefulWidget {
  final Color accent;
  final VoidCallback onPrivate;
  final VoidCallback onPlaylist;
  final VoidCallback onFolders;
  final VoidCallback onFileManager;
  final VoidCallback onNetworkStorage;
  final VoidCallback onCloudStorage;
  final VoidCallback onOpenStream;
  final VoidCallback onCleaner;

  const _QuickTiles({
    required this.accent,
    required this.onPrivate,
    required this.onPlaylist,
    required this.onFolders,
    required this.onFileManager,
    required this.onNetworkStorage,
    required this.onCloudStorage,
    required this.onOpenStream,
    required this.onCleaner,
  });

  @override
  State<_QuickTiles> createState() => _QuickTilesState();
}

class _QuickTilesState extends State<_QuickTiles> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 106,
            child: PageView(
              controller: _pageCtrl,
              onPageChanged: (i) => setState(() => _currentPage = i),
              children: [
                // Page 1 (2x2 Grid): Private Space, Playlists, Folders, File Manager
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _Tile(
                            Icons.lock_outline,
                            'Private Space',
                            accent,
                            widget.onPrivate,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Tile(
                            Icons.queue_music_outlined,
                            'Playlists',
                            accent,
                            widget.onPlaylist,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _Tile(
                            Icons.folder_outlined,
                            'Folders',
                            accent,
                            widget.onFolders,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Tile(
                            Icons.folder_shared_outlined,
                            'File Manager',
                            accent,
                            widget.onFileManager,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Page 2 (2x2 Grid): Network Storage, Cloud Storage, Open Stream, Cleaner
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _Tile(
                            Icons.dns_outlined,
                            'Network Storage',
                            accent,
                            widget.onNetworkStorage,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Tile(
                            Icons.cloud_queue_outlined,
                            'Cloud Storage',
                            accent,
                            widget.onCloudStorage,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _Tile(
                            Icons.link,
                            'Open Stream',
                            accent,
                            widget.onOpenStream,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Tile(
                            Icons.cleaning_services_outlined,
                            'Cleaner',
                            accent,
                            widget.onCleaner,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Two Dots Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _currentPage == 0 ? 14 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: _currentPage == 0 ? accent : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _currentPage == 1 ? 14 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: _currentPage == 1 ? accent : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
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
  final Color accent;
  final VoidCallback onTap;

  const _Tile(this.icon, this.label, this.accent, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: accent.withValues(alpha: 0.25),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;

  const _GroupHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Text(
        '$title  ·  $count',
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isScanning;
  final bool permissionDenied;
  final bool favoritesOnly;
  final VoidCallback onGrantAccess;

  const _EmptyState({
    super.key,
    required this.isScanning,
    required this.permissionDenied,
    required this.favoritesOnly,
    required this.onGrantAccess,
  });

  @override
  Widget build(BuildContext context) {
    if (isScanning) {
      // Progress bar above already shows scan status - avoid a duplicate message.
      return const SizedBox.shrink();
    }

    // Library loaded, but the favourites filter hides everything.
    if (favoritesOnly && !permissionDenied) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 48, color: Colors.white24),
            SizedBox(height: 12),
            Text(
              'No favourites yet.\nTap the heart on any video to add it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: 48,
            color: Colors.white24,
          ),
          const SizedBox(height: 12),
          Text(
            permissionDenied
                ? 'Max Player needs storage access to find your videos'
                : 'No videos yet',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGrantAccess,
            icon: const Icon(Icons.folder_open),
            label: Text(permissionDenied ? 'Try again' : 'Scan device'),
          ),
        ],
      ),
    );
  }
}
