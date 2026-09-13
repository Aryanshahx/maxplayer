import 'dart:typed_data';

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
              foregroundColor: AppColors.onAccent,
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
        icon: Icon(Icons.add_rounded, color: AppColors.onAccent),
        label: Text('New', style: TextStyle(color: AppColors.onAccent)),
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

  Future<void> _addVideos() async {
    final ids = (await LocalStore().playlists())[widget.name] ?? const [];
    if (!mounted) return;
    final added = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => _AddVideosScreen(
          name: widget.name,
          existing: ids.toSet(),
        ),
      ),
    );
    if (added != null && added > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Added $added video${added == 1 ? '' : 's'} to "${widget.name}"')));
    }
    _resolve();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        icon: Icon(Icons.playlist_add_rounded, color: AppColors.onAccent),
        label: Text('Add videos',
            style: TextStyle(color: AppColors.onAccent)),
        onPressed: _addVideos,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : _videos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Empty playlist.\nTap "Add videos" below to pick videos '
                      'from this device.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : VideoGrid(videos: _videos, onChanged: _resolve),
    );
  }
}

/// Multi-select picker for adding device videos into one playlist. Lists
/// every video on the device (already-added ones are marked and skipped).
class _AddVideosScreen extends StatefulWidget {
  const _AddVideosScreen({required this.name, required this.existing});

  final String name;
  final Set<String> existing;

  @override
  State<_AddVideosScreen> createState() => _AddVideosScreenState();
}

class _AddVideosScreenState extends State<_AddVideosScreen> {
  final _store = LocalStore();
  final List<AssetEntity> _videos = [];
  final Set<String> _selected = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Storage permission denied - allow it and try again.';
          });
        }
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
          type: RequestType.video, onlyAll: true);
      final path = paths.isEmpty ? null : paths.first;
      final list = <AssetEntity>[];
      if (path != null) {
        var page = 0;
        while (true) {
          final batch = await path.getAssetListPaged(page: page, size: 200);
          if (batch.isEmpty) break;
          list.addAll(batch.where((a) => a.type == AssetType.video));
          if (batch.length < 200) break;
          page++;
        }
      }
      if (!mounted) return;
      setState(() {
        _videos
          ..clear()
          ..addAll(list);
        _loading = false;
      });
    } catch (e) {
      CrashLog.error('playlist.add_scan_failed', e);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not scan videos on this device.';
        });
      }
    }
  }

  Future<void> _addSelected() async {
    var added = 0;
    for (final id in _selected) {
      if (await _store.addToPlaylist(widget.name, id)) added++;
    }
    if (!mounted) return;
    Navigator.of(context).pop(added);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add to ${widget.name}')),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              icon: Icon(Icons.add_rounded, color: AppColors.onAccent),
              label: Text('Add ${_selected.length}',
                  style: TextStyle(color: AppColors.onAccent)),
              onPressed: _addSelected,
            ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : _videos.isEmpty
                  ? const Center(
                      child: Text('No videos on this device',
                          style: TextStyle(color: AppColors.textSecondary)))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.18,
                      ),
                      itemCount: _videos.length,
                      itemBuilder: (context, i) {
                        final a = _videos[i];
                        final already = widget.existing.contains(a.id);
                        final sel = _selected.contains(a.id);
                        return _PickTile(
                          asset: a,
                          selected: sel,
                          already: already,
                          onTap: already
                              ? null
                              : () => setState(() {
                                    sel
                                        ? _selected.remove(a.id)
                                        : _selected.add(a.id);
                                  }),
                        );
                      },
                    ),
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.asset,
    required this.selected,
    required this.already,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool selected;
  final bool already;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.accent
                : Colors.white.withValues(alpha: 0.06),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: videoThumb(asset, const ThumbnailSize(480, 480)),
                    builder: (context, snap) => snap.hasError || snap.data == null
                        ? const ColoredBox(color: AppColors.surfaceAlt)
                        : Image.memory(snap.data!,
                            fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                  if (already)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Added',
                            style:
                                TextStyle(fontSize: 10, color: Colors.white)),
                      ),
                    ),
                  if (selected)
                    Container(
                        color: AppColors.accent.withValues(alpha: 0.18)),
                  if (selected)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(Icons.check_circle_rounded,
                          color: AppColors.accent, size: 22),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Text(
                asset.title ?? 'Untitled',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
