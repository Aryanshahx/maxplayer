import 'package:flutter/material.dart' hide RepeatMode;
import '../models/video_track.dart' show RepeatMode;
import '../state/media_player_state.dart';
import 'progress_bar.dart';
import 'track_selection_sheet.dart';

/// Controls drawn on top of the video. Two slim rows are used instead of one
/// long row - the previous single-row layout needed ~540dp and overflowed
/// (black/yellow error stripes) on portrait phones.
///
/// This widget rebuilds itself via [AnimatedBuilder] on every player tick,
/// so the parent screen does NOT rebuild (which kept recreating the video
/// surface and caused fullscreen flicker).
class PlayerControlsOverlay extends StatelessWidget {
  final MediaPlayerState player;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleQueue;

  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onToggleQueue,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressBar(
                position: player.position,
                duration: player.duration,
                onSeek: player.seek,
              ),
              // Row 1: transport (shuffle - prev - play - next - repeat)
              Row(
                children: [
                  _iconBtn(
                    icon: player.isShuffled
                        ? Icons.shuffle_on_outlined
                        : Icons.shuffle,
                    active: player.isShuffled,
                    onTap: player.toggleShuffle,
                  ),
                  const Spacer(),
                  _iconBtn(icon: Icons.skip_previous, onTap: player.prevTrack),
                  _iconBtn(
                    icon: player.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 40,
                    onTap: player.togglePlay,
                  ),
                  _iconBtn(icon: Icons.skip_next, onTap: player.nextTrack),
                  const Spacer(),
                  _iconBtn(
                    icon: switch (player.repeatMode) {
                      RepeatMode.none => Icons.repeat,
                      RepeatMode.all => Icons.repeat_on_outlined,
                      RepeatMode.one => Icons.repeat_one_on_outlined,
                    },
                    active: player.repeatMode != RepeatMode.none,
                    onTap: player.toggleRepeat,
                  ),
                ],
              ),
              // Row 2: options (mute - speed - audio - subtitles | queue - fullscreen)
              Row(
                children: [
                  _iconBtn(
                    icon: player.isMuted || player.volume == 0
                        ? Icons.volume_off
                        : Icons.volume_up,
                    onTap: player.toggleMute,
                  ),
                  _speedMenu(),
                  _iconBtn(
                    icon: Icons.audiotrack_outlined,
                    // Highlight when the file actually offers multiple tracks.
                    active: player.audioTracks.length > 1,
                    onTap: () => TrackSelectionSheet.show(
                      context,
                      player,
                      isSubtitle: false,
                    ),
                  ),
                  _iconBtn(
                    icon: player.subtitlesActive
                        ? Icons.subtitles
                        : Icons.subtitles_outlined,
                    active: player.subtitlesActive,
                    onTap: () => TrackSelectionSheet.show(
                      context,
                      player,
                      isSubtitle: true,
                    ),
                  ),
                  const Spacer(),
                  _iconBtn(icon: Icons.queue_music, onTap: onToggleQueue),
                  _iconBtn(
                    icon: isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    onTap: onToggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _speedMenu() {
    return PopupMenuButton<double>(
      initialValue: player.playbackRate,
      color: const Color(0xFF1a1a24),
      onSelected: player.setPlaybackRate,
      itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
          .map((r) => PopupMenuItem(
                value: r,
                child: Text('${r}x',
                    style: const TextStyle(color: Colors.white)),
              ))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text('${player.playbackRate}x',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    double size = 24,
  }) {
    return IconButton(
      icon: Icon(icon,
          size: size, color: active ? const Color(0xFFA855F7) : Colors.white),
      onPressed: onTap,
    );
  }
}
