import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../state/media_player_state.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/playlist_panel.dart';

class PlayerScreen extends StatefulWidget {
  final MediaPlayerState player;

  const PlayerScreen({super.key, required this.player});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Shared, app-lifetime controller owned by MediaPlayerState (this media_kit
  // version has no VideoController.dispose, so per-visit controllers leaked
  // and glitched the player).
  late final VideoController _controller = widget.player.videoController;
  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _showQueue = false;

  // NOTE: no addListener/setState here. Rebuilding the whole screen on
  // every position tick re-created the video surface each time and made
  // fullscreen toggling flicker. Ticking parts (overlay, spinner, queue,
  // title) listen to the player themselves via AnimatedBuilder.

  @override
  void dispose() {
    if (_isFullscreen) _exitFullscreen();
    super.dispose();
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      _exitFullscreen();
    }
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _isFullscreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                title: AnimatedBuilder(
                  animation: player,
                  builder: (context, _) => Text(
                    player.currentTrack?.title ?? 'Max Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
        body: SafeArea(
          top: !_isFullscreen,
          // Lift controls above the gesture/nav bar in landscape fullscreen.
          bottom: true,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _controlsVisible = !_controlsVisible),
                  onDoubleTap: _toggleFullscreen,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: player.currentTrack != null
                            ? RepaintBoundary(
                                child: Video(
                                  controller: _controller,
                                  controls: NoVideoControls,
                                ),
                              )
                            : const Text('No video loaded',
                                style: TextStyle(color: Colors.white38)),
                      ),
                      // Buffering spinner - follows the player stream only.
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: player,
                          builder: (context, _) => player.isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFFA855F7)),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      if (_controlsVisible)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: PlayerControlsOverlay(
                            player: player,
                            isFullscreen: _isFullscreen,
                            onToggleFullscreen: _toggleFullscreen,
                            onToggleQueue: () =>
                                setState(() => _showQueue = !_showQueue),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_showQueue && !_isFullscreen)
                SizedBox(
                  width: 280,
                  child: Container(
                    color: const Color(0xFF12121a),
                    child: AnimatedBuilder(
                      animation: player,
                      builder: (context, _) => PlaylistPanel(
                        playlist: player.playlist,
                        currentIndex: player.currentIndex,
                        onPlay: player.playTrack,
                        onRemove: player.removeFromPlaylist,
                      ),
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
