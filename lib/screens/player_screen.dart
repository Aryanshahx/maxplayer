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
  late final VideoController _controller;
  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _showQueue = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoController(widget.player.player);
    widget.player.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.player.removeListener(_onChange);
    if (_isFullscreen) _exitFullscreen();
    super.dispose();
  }

  void _onChange() => setState(() {});

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
                title: Text(player.currentTrack?.title ?? 'Max Player',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
        body: SafeArea(
          top: !_isFullscreen,
          bottom: false,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _controlsVisible = !_controlsVisible),
                  onDoubleTap: _toggleFullscreen,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: player.currentTrack != null
                            ? Video(controller: _controller, controls: NoVideoControls)
                            : const Text('No video loaded', style: TextStyle(color: Colors.white38)),
                      ),
                      if (player.isLoading)
                        const Center(child: CircularProgressIndicator(color: Color(0xFFA855F7))),
                      if (_controlsVisible)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: PlayerControlsOverlay(
                            player: player,
                            isFullscreen: _isFullscreen,
                            onToggleFullscreen: _toggleFullscreen,
                            onToggleQueue: () => setState(() => _showQueue = !_showQueue),
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
                    child: PlaylistPanel(
                      playlist: player.playlist,
                      currentIndex: player.currentIndex,
                      onPlay: player.playTrack,
                      onRemove: player.removeFromPlaylist,
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
