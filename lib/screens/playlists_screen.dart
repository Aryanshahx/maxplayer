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
