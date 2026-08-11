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
    // Automatically ask for storage permission and scan the whole device
    // the first time this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.library.folderName == null && !widget.library.isScanning) {
        widget.library.scanAllStorage();
      }
    });
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
                ? _EmptyState(
                    isScanning: lib.isScanning,
                    permissionDenied: lib.permissionDenied,
                    onGrantAccess: lib.scanAllStorage,
                  )
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
  final bool isScanning;
  final bool permissionDenied;
  final VoidCallback onGrantAccess;

  const _EmptyState({
    required this.isScanning,
    required this.permissionDenied,
    required this.onGrantAccess,
  });

  @override
  Widget build(BuildContext context) {
    if (isScanning) {
      // Progress bar above already shows scan status - avoid a duplicate message.
      return const SizedBox.shrink();
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library_outlined, size: 48, color: Colors.white24),
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
