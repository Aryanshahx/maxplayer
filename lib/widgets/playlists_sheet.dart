import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/playlist.dart';
import '../models/video_track.dart';
import '../screens/player_screen.dart';
import '../state/media_player_state.dart';
import '../state/playlist_store.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/formatters.dart';
import 'fade_in_image.dart';
import 'video_picker_sheet.dart';

/// v40: named, persistent playlists manager.
///
/// Replaces the old ephemeral queue sheet (the "Build playlist" button) -
/// that queue vanished on every app restart ("playlists are not saving,
/// they disappear after reopening"). Now the user creates any number of
/// named playlists ("Movies", "Songs", ...), adds videos to them, and they
/// are persisted (JSON in the app's settings store) across restarts.
///
/// Two views inside one sheet: the playlist LIST, and one playlist's
/// DETAIL (videos, play, add, remove). Uses a DraggableScrollableSheet so
/// every row stays reachable in portrait AND landscape (the v35 lesson).
class PlaylistsSheet extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;
  final ScrollController scrollController;

  const PlaylistsSheet({
    super.key,
    required this.library,
    required this.player,
    required this.scrollController,
  });

  static Future<void> show(
    BuildContext context, {
    required VideoLibraryState library,
    required MediaPlayerState player,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => PlaylistsSheet(
          library: library,
          player: player,
          scrollController: controller,
        ),
      ),
    );
  }

  @override
  State<PlaylistsSheet> createState() => _PlaylistsSheetState();
}

class _PlaylistsSheetState extends State<PlaylistsSheet> {
  /// Id of the playlist whose detail view is open; null = the list view.
  String? _openId;

  // --------------------------------------------------------------------------
  // Actions

  /// Video paths -> playable tracks: prefer the scanned library (durations
  /// and thumbnails come along for free); a path outside the library still
  /// plays via a basic track; a path whose FILE is gone (deleted, or the
  /// SD card was removed meanwhile) is skipped silently.
  List<VideoTrack> _resolveTracks(Playlist pl) {
    final out = <VideoTrack>[];
    for (final path in pl.videoPaths) {
      final known = widget.library.findByPath(path);
      if (known != null) {
        out.add(known);
        continue;
      }
      try {
        if (!File(path).existsSync()) continue;
      } catch (_) {
        continue;
      }
      out.add(VideoTrack(
        id: path,
        title: p.basenameWithoutExtension(path),
        path: path,
      ));
    }
    return out;
  }

  Future<void> _play(Playlist pl, {int startAt = 0}) async {
    final tracks = _resolveTracks(pl);
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No playable videos in this playlist - the files may have '
            'been moved or deleted',
          ),
        ),
      );
      return;
    }
    final start = startAt < 0
        ? 0
        : (startAt >= tracks.length ? tracks.length - 1 : startAt);
    await widget.player.setPlaylistAndPlay(tracks, start);
    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  Future<void> _addVideos(Playlist pl) async {
    final videos = widget.library.allVideos;
    if (videos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No videos found yet - let the scan finish first'),
        ),
      );
      return;
    }
    final picked = await VideoPickerSheet.show(
      context,
      videos,
      title: 'Add to "${pl.name}"',
      actionLabel: 'Add',
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    playlistStore.addVideos(pl.id, [for (final t in picked) t.path]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${picked.length} video(s) to "${pl.name}"'),
      ),
    );
  }

  /// Name dialog shared by Create and Rename. Validation happens after the
  /// dialog closes so a bad name can show a snackbar and re-ask.
  Future<void> _askName({Playlist? existing}) async {
    final controller = TextEditingController(text: existing?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: Text(
          existing == null ? 'New playlist' : 'Rename playlist',
          style: const TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist name (e.g. Movies, Songs)',
            hintStyle: TextStyle(color: Colors.white38),
            counterStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(existing == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final err = validatePlaylistName(name);
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
      _askName(existing: existing);
      return;
    }
    if (existing == null) {
      final created = playlistStore.create(name);
      // Jump straight into the new playlist so videos can be added now.
      setState(() => _openId = created.id);
    } else {
      playlistStore.rename(existing.id, name);
    }
  }

  Future<void> _confirmDelete(Playlist pl) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text(
          'Delete playlist?',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Text(
          '"${pl.name}" is removed. The videos themselves stay on your '
          'phone - only this list is deleted.',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    playlistStore.delete(pl.id);
    if (_openId == pl.id) setState(() => _openId = null);
  }

  // --------------------------------------------------------------------------
  // Views

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: playlistStore,
      builder: (context, _) {
        final open = _openId == null ? null : playlistStore.byId(_openId!);
        if (_openId != null && open == null) {
          // The open playlist was deleted - fall back to the list.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _openId = null);
          });
        }
        return Column(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: open == null ? _listView() : _detailView(open),
            ),
          ],
        );
      },
    );
  }

  Widget _header({required Widget title, List<Widget> actions = const []}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          Expanded(child: title),
          ...actions,
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _listView() {
    final playlists = playlistStore.playlists;
    return Column(
      children: [
        _header(
          title: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              'Playlists · ${playlists.length}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'New playlist',
              onPressed: () => _askName(),
              icon: Icon(Icons.add, color: themeState.accent),
            ),
          ],
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: playlists.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      playlistStore.loaded
                          ? 'No playlists yet.\n\nTap + to make one by name '
                              '(e.g. "Movies", "Songs") and add videos to '
                              'it. Playlists are SAVED - they are still '
                              'here when you reopen the app.'
                          : 'Loading playlists...',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white54, height: 1.4),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: playlists.length,
                  itemBuilder: (context, i) {
                    final pl = playlists[i];
                    return ListTile(
                      onTap: () => setState(() => _openId = pl.id),
                      leading: Container(
                        width: 44,
                        height: 34,
                        decoration: BoxDecoration(
                          color: themeState.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.queue_music,
                            size: 20, color: themeState.accent),
                      ),
                      title: Text(
                        pl.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${pl.videoPaths.length} video${pl.videoPaths.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Play',
                            icon: Icon(Icons.play_circle_fill,
                                color: themeState.accent),
                            onPressed: () => _play(pl),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert,
                                color: Colors.white54),
                            color: const Color(0xFF2a2a38),
                            onSelected: (v) {
                              if (v == 'rename') _askName(existing: pl);
                              if (v == 'delete') _confirmDelete(pl);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename',
                                    style: TextStyle(color: Colors.white)),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete',
                                    style: TextStyle(
                                        color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _detailView(Playlist pl) {
    return Column(
      children: [
        _header(
          title: Row(
            children: [
              IconButton(
                tooltip: 'All playlists',
                icon:
                    const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => setState(() => _openId = null),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pl.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${pl.videoPaths.length} video${pl.videoPaths.length == 1 ? '' : 's'} · saved',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Add videos',
              onPressed: () => _addVideos(pl),
              icon: Icon(Icons.playlist_add, color: themeState.accent),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              color: const Color(0xFF2a2a38),
              onSelected: (v) {
                if (v == 'rename') _askName(existing: pl);
                if (v == 'delete') _confirmDelete(pl);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'rename',
                  child:
                      Text('Rename', style: TextStyle(color: Colors.white)),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete playlist',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ),
        if (pl.videoPaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: themeState.accent,
                  foregroundColor: themeState.onAccent,
                ),
                onPressed: () => _play(pl),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play all'),
              ),
            ),
          ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: pl.videoPaths.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'No videos yet.\n\nTap the playlist-add icon above to '
                      'pick videos from your library.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, height: 1.4),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: pl.videoPaths.length,
                  itemBuilder: (context, i) {
                    final path = pl.videoPaths[i];
                    final track = widget.library.findByPath(path);
                    return ListTile(
                      dense: true,
                      onTap: () => _play(pl, startAt: i),
                      leading: SizedBox(
                        width: 56,
                        height: 34,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: track?.thumbnailPath != null
                              ? Image.file(
                                  File(track!.thumbnailPath!),
                                  fit: BoxFit.cover,
                                  frameBuilder: fadeInImageFrame,
                                  errorBuilder: (_, __, ___) =>
                                      const _ThumbPlaceholder(),
                                )
                              : const _ThumbPlaceholder(),
                        ),
                      ),
                      title: Text(
                        track?.title ?? p.basenameWithoutExtension(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        [
                          if (formatDuration(track?.duration) != '--:--')
                            formatDuration(track?.duration),
                          p.dirname(path),
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove from playlist',
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.white38, size: 20),
                        onPressed: () =>
                            playlistStore.removeVideo(pl.id, path),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1e2a),
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 16, color: Colors.white24),
      ),
    );
  }
}
