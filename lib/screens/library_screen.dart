import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_info.dart';
import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/crash_log.dart';
import '../utils/formatters.dart';
import '../widgets/about_sheet.dart';
import '../widgets/display_settings_sheet.dart';
import '../state/private_vault.dart';
import '../widgets/mini_player.dart';
import '../widgets/playlist_panel.dart';
import '../widgets/video_picker_sheet.dart';
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

  /// v28: the Private folder moved from the top bar into the quick-tiles
  /// grid. v26: rescan on return ONLY when something was actually
  /// hidden/unhidden inside (the revision counter moves on every vault
  /// file move) - a plain visit no longer reloads the grid.
  Future<void> _openPrivate(VideoLibraryState lib) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        // v29: the vault screen gets the library too (its "+" button
        // moves selected videos into the vault).
        builder: (_) =>
            PrivateScreen(player: widget.player, library: lib),
      ),
    );
    final rev = PrivateVault.revision;
    if (rev != _lastVaultRevision) {
      _lastVaultRevision = rev;
      lib.rescan();
    }
  }

  /// v28 "Playlist" tile: the current play queue in a bottom sheet.
  /// v29: "Build playlist" creates a queue from videos you SELECT.
  void _showQueueSheet(VideoLibraryState lib) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _showPlaylistPicker(lib);
                    },
                    icon: Icon(Icons.playlist_add,
                        color: themeState.accent),
                    label: const Text('Build playlist'),
                  ),
                ),
                Expanded(
                  child: widget.player.playlist.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Text(
                              'The queue is empty - play any video and it '
                              'appears here, or tap "Build playlist" to '
                              'select videos.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white54, height: 1.4),
                            ),
                          ),
                        )
                      : PlaylistPanel(
                          playlist: widget.player.playlist,
                          currentIndex: widget.player.currentIndex,
                          onPlay: (i) {
                            widget.player.playTrack(i);
                            Navigator.of(sheetContext).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PlayerScreen(player: widget.player),
                              ),
                            );
                          },
                          onRemove: (i) {
                            widget.player.removeFromPlaylist(i);
                            setSheetState(() {});
                          },
                          onClose: () => Navigator.of(sheetContext).pop(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// v29: select videos -> they become the play queue and start playing.
  Future<void> _showPlaylistPicker(VideoLibraryState lib) async {
    final selected = await VideoPickerSheet.show(
      context,
      lib.videos,
      title: 'Build a playlist',
      actionLabel: 'Play',
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    widget.player.setPlaylistAndPlay(selected, 0);
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => PlayerScreen(player: widget.player)),
    );
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
              leading: Icon(Icons.video_library_outlined,
                  color: themeState.accent),
              title: const Text('All videos',
                  style: TextStyle(color: Colors.white)),
              trailing: lib.folderFilter == null
                  ? Icon(Icons.check, color: themeState.accent)
                  : Text('${lib.allVideosCount}',
                      style: const TextStyle(color: Colors.white38)),
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
                      leading: Icon(Icons.folder_outlined,
                          color: themeState.accent),
                      title: Text(e.key,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                          '${e.value} ${e.value == 1 ? 'video' : 'videos'}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
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

  /// v29: the Cleaner tile is a real device cleaner now - the app's own
  /// caches, the system gallery thumbnail cache, your LARGEST videos and
  /// DUPLICATE copies, each one tap away from freeing space. Deleting a
  /// video is permanent (confirm dialog) and never touches hidden files.
  Future<void> _showCleaner(VideoLibraryState lib) async {
    var report = await NativeBridge.storageReport();
    var deviceCache = await _deviceThumbCacheSize();
    if (!mounted) return;

    Future<void> deleteVideo(VideoTrack t) async {
      try {
        await File(t.path).delete();
        await NativeBridge.scanFile(t.path);
        widget.player.removeHistoryEntry(t.path);
        lib.removeVideo(t.path);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not delete the file')),
          );
        }
      }
    }

    Future<void> confirmDelete(
        VideoTrack t, void Function() refresh) async {
      final size = formatFileSize(t.sizeBytes);
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a24),
          title: const Text('Delete this video?',
              style: TextStyle(color: Colors.white, fontSize: 17)),
          content: Text(
            '"${t.title}" ($size) is deleted from the device storage - '
            'this cannot be undone.',
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent.shade700),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (yes == true) {
        await deleteVideo(t);
        refresh();
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final accent = themeState.accent;
          final thumbs =
              (report['thumbs'] ?? 0) + (report['strips'] ?? 0);
          final temp = report['temp'] ?? 0;
          final models = report['models'] ?? 0;
          final auto = thumbs + temp + models + deviceCache;
          final largest = lib.largestVideos(n: 8);
          final dupes = lib.duplicateGroups;

          Future<void> clearApp(String kind) async {
            final freed = await NativeBridge.clearStorage(kind);
            final fresh = await NativeBridge.storageReport();
            setSheetState(() => report = fresh);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Freed ${formatFileSize(freed)}'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }

          Future<void> clearDeviceCache() async {
            final freed = await _clearDeviceThumbCache();
            setSheetState(() => deviceCache = 0);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Freed ${formatFileSize(freed)}'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }

          Widget cacheRow(IconData icon, String title, String note,
              int bytes, VoidCallback onClear) {
            return ListTile(
              dense: true,
              leading: Icon(icon, color: accent),
              title: Text(title,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text(note,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11.5)),
              trailing: TextButton(
                onPressed: bytes > 0 ? onClear : null,
                child: Text(
                  bytes > 0 ? 'Clear ${formatFileSize(bytes)}' : 'Empty',
                ),
              ),
            );
          }

          Widget section(String title) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
                child: Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.78,
              child: Column(
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        auto > 0
                            ? 'Cleaner - ${formatFileSize(auto)} reclaimable now'
                            : 'Cleaner',
                        style: TextStyle(
                          color: accent,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 14),
                      children: [
                        section('Cache & app data'),
                        cacheRow(
                          Icons.image_outlined,
                          'App thumbnails & previews',
                          'Rebuild automatically as you browse and play',
                          thumbs,
                          () => clearApp('thumbs'),
                        ),
                        cacheRow(
                          Icons.mic_none_outlined,
                          'Temporary AI files',
                          'Leftovers from subtitle generation',
                          temp,
                          () => clearApp('temp'),
                        ),
                        cacheRow(
                          Icons.psychology_outlined,
                          'AI subtitle models',
                          'Downloaded again only when you generate subtitles',
                          models,
                          () => clearApp('models'),
                        ),
                        cacheRow(
                          Icons.cleaning_services_outlined,
                          'Device gallery cache (.thumbnails)',
                          'Android rebuilds it on its own - safe to clear',
                          deviceCache,
                          clearDeviceCache,
                        ),
                        if (largest.isNotEmpty) ...[
                          section('Largest videos - tap to delete'),
                          for (final t in largest)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                  Icons.video_file_outlined,
                                  color: accent),
                              title: Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                              subtitle: Text(
                                '${formatFileSize(t.sizeBytes)}  ·  '
                                '${t.folderName}',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11.5),
                              ),
                              trailing: IconButton(
                                tooltip: 'Delete this video',
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent, size: 20),
                                onPressed: () => confirmDelete(
                                    t, () => setSheetState(() {})),
                              ),
                            ),
                        ],
                        if (dupes.isNotEmpty) ...[
                          section(
                              'Duplicate videos - same size & duration'),
                          for (final g in dupes.take(6))
                            ListTile(
                              dense: true,
                              leading: Icon(Icons.copy_all_outlined,
                                  color: accent),
                              title: Text(
                                g.first.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                              subtitle: Text(
                                '${g.length} copies  ·  '
                                '${formatFileSize(g.first.sizeBytes)} each',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11.5),
                              ),
                              trailing: Text(
                                'open',
                                style: TextStyle(
                                    color: accent, fontSize: 12.5),
                              ),
                              onTap: () async {
                                await _showDuplicateGroup(
                                    g, (t) => confirmDelete(t, () {}));
                                setSheetState(() {});
                              },
                            ),
                        ],
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                          child: Text(
                            'Video deletion asks first and is permanent. '
                            'Cache cleaning never touches your videos.',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// One duplicate group: every copy's location, each deletable; you keep
  /// at least one copy.
  Future<void> _showDuplicateGroup(
    List<VideoTrack> group,
    Future<void> Function(VideoTrack) deleteOne,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final remaining =
              group.where((t) => File(t.path).existsSync()).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.5,
              child: Column(
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${remaining.length} identical copies - keep one, '
                        'delete the rest',
                        style: TextStyle(
                          color: themeState.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: remaining.length < 2
                        ? const Center(
                            child: Text(
                              'One copy left - nothing more to clean.',
                              style:
                                  TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final t in remaining)
                                ListTile(
                                  dense: true,
                                  leading: Icon(Icons.movie_outlined,
                                      color: themeState.accent),
                                  title: Text(
                                    t.path,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Delete this copy',
                                    icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                        size: 20),
                                    onPressed: () async {
                                      await deleteOne(t);
                                      setSheetState(() {});
                                    },
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
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
          // v28: active folder filter chip (set from the Folders tile).
          if (lib.folderFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: Icon(Icons.folder_outlined,
                      size: 16, color: themeState.accent),
                  label: Text('Folder: ${lib.folderFilter}'),
                  labelStyle:
                      const TextStyle(color: Colors.white, fontSize: 13),
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
          // v28: the 2x2 quick-tiles grid - slides away on scroll-down.
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              heightFactor: _tilesVisible ? 1.0 : 0.0,
              alignment: Alignment.topCenter,
              child: _QuickTiles(
                accent: themeState.accent,
                onPrivate: () => _openPrivate(lib),
                onCleaner: () => _showCleaner(lib),
                onPlaylist: () => _showQueueSheet(lib),
                onFolders: () => _showFoldersSheet(lib),
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

/// v28: the 2x2 quick-tiles grid under the search bar. Tucks away while
/// scrolling down through the videos (see [_LibraryScreenState]) and
/// returns on scroll-up. Private folder lives here now (was a top-bar
/// icon).
class _QuickTiles extends StatelessWidget {
  final Color accent;
  final VoidCallback onPrivate;
  final VoidCallback onCleaner;
  final VoidCallback onPlaylist;
  final VoidCallback onFolders;

  const _QuickTiles({
    required this.accent,
    required this.onPrivate,
    required this.onCleaner,
    required this.onPlaylist,
    required this.onFolders,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Tile(
                    Icons.lock_outline, 'Private folder', accent, onPrivate),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(Icons.cleaning_services_outlined, 'Cleaner',
                    accent, onCleaner),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Tile(
                    Icons.queue_music_outlined, 'Playlist', accent, onPlaylist),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                    Icons.folder_outlined, 'Folders', accent, onFolders),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
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

// ---------------------------------------------------------------------------
// v29 Cleaner: the system gallery thumbnail cache (safe to clear - Android
// simply rebuilds it when a gallery app is opened again).
// ---------------------------------------------------------------------------

const List<String> _deviceThumbDirs = [
  '/storage/emulated/0/DCIM/.thumbnails',
  '/storage/emulated/0/.thumbnails',
];

Future<int> _pathSizeBytes(String path) async {
  var total = 0;
  try {
    final dir = Directory(path);
    if (!dir.existsSync()) return 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

Future<int> _deviceThumbCacheSize() async {
  var total = 0;
  for (final p in _deviceThumbDirs) {
    total += await _pathSizeBytes(p);
  }
  return total;
}

/// Deletes the CONTENTS of the gallery-cache folders (the folders
/// themselves stay). Returns freed bytes.
Future<int> _clearDeviceThumbCache() async {
  var freed = 0;
  for (final p in _deviceThumbDirs) {
    try {
      final dir = Directory(p);
      if (!dir.existsSync()) continue;
      await for (final e in dir.list(followLinks: false)) {
        try {
          if (e is File) {
            final len = await e.length();
            await e.delete();
            freed += len;
          } else if (e is Directory) {
            final size = await _pathSizeBytes(e.path);
            await e.delete(recursive: true);
            freed += size;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
  return freed;
}
