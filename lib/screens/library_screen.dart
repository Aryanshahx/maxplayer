import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/video_library_state.dart';
import '../widgets/video_tile.dart';
import 'player_screen.dart';
 
class LibraryScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;
 
  const LibraryScreen({super.key, required this.library, required this.player});
 
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}
 
class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    widget.library.addListener(_onChange);
  }
 
  @override
  void dispose() {
    widget.library.removeListener(_onChange);
    super.dispose();
  }
 
  void _onChange() => setState(() {});
 
  void _playVideo(VideoTrack track) {
    final all = widget.library.videos;
    final idx = all.indexWhere((v) => v.id == track.id);
    widget.player.setPlaylistAndPlay(all, idx >= 0 ? idx : 0);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }
 
  Future<void> _showFolderDialog() async {
    final controller = TextEditingController(
      text: VideoLibraryState.suggestedFolders.first,
    );
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Scan a folder', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Folder path',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Quick picks:', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: VideoLibraryState.suggestedFolders.map((folder) {
                return ActionChip(
                  label: Text(folder, style: const TextStyle(fontSize: 11)),
                  onPressed: () => controller.text = folder,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  labelStyle: const TextStyle(color: Colors.white70),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Scan'),
          ),
        ],
      ),
    );
    if (path != null && path.isNotEmpty) {
      await widget.library.scanFolder(path);
    }
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
          child: const Text('Max Player',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        actions: [
          IconButton(
            tooltip: 'Scan folder',
            icon: const Icon(Icons.folder_open),
            onPressed: _showFolderDialog,
          ),
          if (lib.folderName != null)
            IconButton(
              tooltip: 'Rescan',
              icon: const Icon(Icons.refresh),
              onPressed: lib.rescan,
            ),
        ],
      ),
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
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (lib.permissionError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Text(
                  lib.permissionError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
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
                    color: const Color(0xFFA855F7),
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
          Expanded(
            child: lib.videos.isEmpty
                ? _EmptyState(onPickFolder: _showFolderDialog)
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: lib.videos.length,
                    itemBuilder: (context, i) {
                      final track = lib.videos[i];
                      return VideoTile(track: track, onTap: () => _playVideo(track));
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
 
class _EmptyState extends StatelessWidget {
  final VoidCallback onPickFolder;
 
  const _EmptyState({required this.onPickFolder});
 
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library_outlined, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          const Text('No videos yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onPickFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Scan a folder'),
          ),
        ],
      ),
    );
  }
}
