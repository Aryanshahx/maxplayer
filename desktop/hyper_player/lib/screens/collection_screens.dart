import '../local_thumbnail.dart';
import 'package:flutter/material.dart';

import '../desktop_store.dart';
import '../playlist.dart';
import '../utils/app_language.dart';

const secondary = Color(0xff9296a0);
const edge = Color(0xff26262c);
Widget collectionEmpty(IconData icon, String message) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            LText(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: secondary, fontSize: 16),
            ),
          ],
        ),
      ),
    );
Future<bool> confirmRemoval(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: LText(title),
        content: LText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LText('Clear'),
          ),
        ],
      ),
    ) ??
    false;

/// Full route matching Android's history/list screen, not a desktop modal.
class SourceCollectionScreen extends StatefulWidget {
  final String title;
  final List<String> sources;
  final Future<void> Function()? onSave;
  const SourceCollectionScreen({
    super.key,
    required this.title,
    required this.sources,
    this.onSave,
  });
  @override
  State<SourceCollectionScreen> createState() => _SourceCollectionScreenState();
}

class _SourceCollectionScreenState extends State<SourceCollectionScreen> {
  Future<void> clear() async {
    if (!await confirmRemoval(
      context,
      'Clear ${widget.title.toLowerCase()}?',
      'Only this saved list is cleared. Media files are not deleted.',
    )) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => widget.sources.clear());
    await widget.onSave?.call();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: LText(widget.title),
          actions: [
            if (widget.onSave != null && widget.sources.isNotEmpty)
              IconButton(
                tooltip: 'Clear list',
                onPressed: clear,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
          ],
        ),
        body: widget.sources.isEmpty
            ? collectionEmpty(
                widget.title == 'History'
                    ? Icons.history
                    : Icons.video_library_outlined,
                widget.title == 'History'
                    ? 'Nothing watched yet.\nVideos you open will show up here.'
                    : 'No entries yet.',
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: widget.sources.length,
                separatorBuilder: (context, i) =>
                    const Divider(height: 1, indent: 120, color: edge),
                itemBuilder: (context, i) {
                  final source = widget.sources[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: SizedBox(
                        width: 96, height: 54, child: LocalThumbnail(source)),
                    title: Text(
                      labelFor(source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: LText(
                      validStream(source) ? 'Network media' : 'Local file',
                      style: const TextStyle(fontSize: 12, color: secondary),
                    ),
                    trailing: widget.onSave == null
                        ? null
                        : IconButton(
                            tooltip: 'Remove from list',
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () async {
                              setState(() => widget.sources.removeAt(i));
                              await widget.onSave?.call();
                            },
                          ),
                    onTap: () => Navigator.pop(context, source),
                  );
                },
              ),
      );
}

class DesktopPlaylistsScreen extends StatefulWidget {
  final DesktopStore store;
  final List<String> currentQueue;
  const DesktopPlaylistsScreen({
    super.key,
    required this.store,
    required this.currentQueue,
  });
  @override
  State<DesktopPlaylistsScreen> createState() => _DesktopPlaylistsScreenState();
}

class _DesktopPlaylistsScreenState extends State<DesktopPlaylistsScreen> {
  Future<void> create() async {
    String name = '';
    bool includeQueue = false;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const LText('New playlist', style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  onChanged: (value) => name = value.trim(),
                  decoration: const LInputDecoration(hintText: 'Playlist name'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Include current queue',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: includeQueue,
                  onChanged: (value) =>
                      update(() => includeQueue = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const LText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, name),
              child: const LText('Create'),
            ),
          ],
        ),
      ),
    );
    if (value == null || value.isEmpty || !mounted) {
      return;
    }
    if (widget.store.playlists.containsKey(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LText('A playlist with that name exists')),
      );
      return;
    }
    setState(
      () => widget.store.playlists[value] =
          includeQueue ? List.of(widget.currentQueue) : [],
    );
    await widget.store.save();
  }

  Future<void> open(String name) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistItemsScreen(
          name: name,
          store: widget.store,
          currentQueue: widget.currentQueue,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (result != null) {
      Navigator.pop(context, result);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.store.playlists.keys.toList();
    return Scaffold(
      appBar: AppBar(title: const LText('Playlists')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: create,
        icon: const Icon(Icons.add_rounded),
        label: const LText('New'),
      ),
      body: names.isEmpty
          ? collectionEmpty(
              Icons.playlist_play_rounded,
              'No playlists yet.\nCreate one to organise your media.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: names.length,
              separatorBuilder: (context, i) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final name = names[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.playlist_play_rounded, size: 30),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${widget.store.playlists[name]!.length} media items',
                      style: const TextStyle(color: secondary, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xffe5484d),
                        size: 20,
                      ),
                      tooltip: 'Delete playlist',
                      onPressed: () async {
                        if (!await confirmRemoval(
                          context,
                          'Delete playlist?',
                          'Media files will not be deleted.',
                        )) {
                          return;
                        }
                        if (!mounted) {
                          return;
                        }
                        setState(() => widget.store.playlists.remove(name));
                        await widget.store.save();
                      },
                    ),
                    onTap: () => open(name),
                  ),
                );
              },
            ),
    );
  }
}

class PlaylistItemsScreen extends StatelessWidget {
  final String name;
  final DesktopStore store;
  final List<String> currentQueue;
  const PlaylistItemsScreen({
    super.key,
    required this.name,
    required this.store,
    required this.currentQueue,
  });
  @override
  Widget build(BuildContext context) => StatefulBuilder(
        builder: (context, update) => Scaffold(
          appBar: AppBar(
            title: Text(name),
            actions: [
              IconButton(
                tooltip: 'Add current queue',
                icon: const Icon(Icons.playlist_add),
                onPressed: () async {
                  final list = store.playlists[name]!;
                  for (final source in currentQueue) {
                    if (!list.contains(source)) {
                      list.add(source);
                    }
                  }
                  await store.save();
                  update(() {});
                },
              ),
            ],
          ),
          body: store.playlists[name]!.isEmpty
              ? collectionEmpty(Icons.video_library_outlined, 'No entries yet.')
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: store.playlists[name]!.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.55,
                  ),
                  itemBuilder: (context, i) {
                    final source = store.playlists[name]![i];
                    return Card(
                      child: InkWell(
                        onTap: () => Navigator.pop(context, source),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: SizedBox(
                                      width: double.infinity,
                                      child: LocalThumbnail(source))),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      labelFor(source),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove from playlist',
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () async {
                                      store.playlists[name]!.removeAt(i);
                                      await store.save();
                                      if (context.mounted) {
                                        update(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      );
}
