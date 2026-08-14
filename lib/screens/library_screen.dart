import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_info.dart';
import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/crash_log.dart';
import '../widgets/about_sheet.dart';
import '../widgets/display_settings_sheet.dart';
import '../state/private_vault.dart';
import '../widgets/mini_player.dart';
import '../widgets/user_manual_sheet.dart';
import 'private_screen.dart';
import '../widgets/video_list_item.dart';
import '../widgets/video_tile.dart';
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

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_onChange);
    // Automatically ask for storage permission and scan the whole device
    // the first time this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.library.folderName == null && !widget.library.isScanning) {
        widget.library.scanAllStorage();
      }
      // If the previous session died with an error, offer the recorded
      // crash report (copyable) so it can be sent for analysis.
      CrashLog.takeLast().then((report) {
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
                        'Crash report copied - send it to the developer'),
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
    // v22: moving a file out of public storage needs the same "All files
    // access" grant the scanner uses. Ask up-front instead of letting the
    // move fail with a cryptic snackbar.
    if (!await Permission.manageExternalStorage.isGranted) {
      final status = await Permission.manageExternalStorage.request();
      if (!mounted) return;
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Private folder needs "All files access": allow it, then '
              'long-press the video again',
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Move to Private folder?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          '"${track.title}" moves into the app\'s private folder - invisible '
          'to Gallery and file managers, visible here only after your PIN.\n\n'
          'Warning: uninstalling the app deletes hidden videos.',
          style:
              const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
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
                    SnackBar(
                      content:
                          Text('Could not hide: $why'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _onMenuChoice(String choice, VideoLibraryState lib) {
    switch (choice) {
      case 'stream':
        _openStreamDialog();
        break;
      case 'stats':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StatsScreen(player: widget.player)),
        );
        break;
      case 'rescan':
        _rescan(lib);
        break;
      case 'manual':
        UserManualSheet.show(context);
        break;
      case 'about':
        AboutSheet.show(context);
        break;
      case 'display':
        DisplaySettingsSheet.show(context, lib);
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

  /// Lets the user paste an http(s)/rtsp/rtmp URL and play it directly.
  Future<void> _openStreamDialog() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text(
          'Open stream URL',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'https:// or rtsp:// ...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: themeState.accent),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Play'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    const schemes = {'http', 'https', 'rtsp', 'rtmp', 'mms'};
    if (uri == null ||
        !schemes.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That does not look like a stream URL'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final title =
        uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
        ? Uri.decodeComponent(uri.pathSegments.last)
        : uri.host;
    await widget.player.playStream(url, title);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
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
          // v21: Private folder (PIN). v26: rescan on return ONLY when
          // something was actually hidden/unhidden inside (the revision
          // counter moves on every vault file move) - a plain visit used
          // to reload the whole grid every time.
          IconButton(
            tooltip: 'Private folder',
            icon: Icon(Icons.lock_outline, color: themeState.accent),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PrivateScreen(player: widget.player),
                ),
              );
              final rev = PrivateVault.revision;
              if (rev != _lastVaultRevision) {
                _lastVaultRevision = rev;
                lib.rescan();
              }
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_vert, color: themeState.accent),
            color: const Color(0xFF26262f),
            onSelected: (choice) => _onMenuChoice(choice, lib),
            // v26: menu icons follow the picked theme colour.
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'stream',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link, color: themeState.accent),
                  title: const Text('Open stream URL'),
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
                value: 'rescan',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh, color: themeState.accent),
                  title: const Text('Rescan library'),
                ),
              ),
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
                value: 'manual',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.menu_book_outlined, color: themeState.accent),
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: lib.setSearchQuery,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search ${lib.allVideosCount} videos...',
                hintStyle: const TextStyle(color: Colors.white38),
                // v26: theme-coloured like the other home buttons.
                prefixIcon: Icon(Icons.search, color: themeState.accent),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
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
    // AnimatedSwitcher above.
    return CustomScrollView(
      key: ValueKey(lib.viewMode),
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
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
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
