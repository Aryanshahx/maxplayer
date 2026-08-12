import 'package:flutter/material.dart' hide RepeatMode;
import '../models/video_track.dart' show RepeatMode;
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import 'progress_bar.dart';
import 'track_selection_sheet.dart';

/// Controls drawn on top of the video. Two slim rows are used instead of one
/// long row - the previous single-row layout needed ~540dp and overflowed
/// (black/yellow error stripes) on portrait phones. Row 2 uses compact 34dp
/// buttons so all options fit on narrow screens.
///
/// This widget rebuilds itself via [AnimatedBuilder] on every player tick,
/// so the parent screen does NOT rebuild (which kept recreating the video
/// surface and caused fullscreen flicker).
class PlayerControlsOverlay extends StatelessWidget {
  final MediaPlayerState player;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleQueue;

  /// Fired on every control interaction; the screen uses it to restart the
  /// auto-hide countdown.
  final VoidCallback onInteract;

  /// Cycles the video fit (contain -> cover -> fill).
  final VoidCallback onCycleFit;

  /// Rotation lock toggle (auto-rotate vs locked to current orientation).
  final bool orientationLocked;
  final VoidCallback onToggleOrientationLock;

  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onToggleQueue,
    required this.onInteract,
    required this.onCycleFit,
    required this.orientationLocked,
    required this.onToggleOrientationLock,
  });

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
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
                onSeek: (d) {
                  player.seek(d);
                  onInteract();
                },
              ),
              // Row 1: playback (shuffle | -10s prev play next +10s | repeat)
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
                  _iconBtn(
                    icon: Icons.replay_10,
                    onTap: () => player.seekBy(-10),
                  ),
                  _iconBtn(icon: Icons.skip_previous, onTap: player.prevTrack),
                  _iconBtn(
                    icon: player.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 40,
                    onTap: player.togglePlay,
                  ),
                  _iconBtn(icon: Icons.skip_next, onTap: player.nextTrack),
                  _iconBtn(
                    icon: Icons.forward_10,
                    onTap: () => player.seekBy(10),
                  ),
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
              // Row 2 (compact): mute speed audio subs fit AB rotate | queue fs
              Row(
                children: [
                  _iconBtn(
                    icon: player.isMuted || player.volume == 0
                        ? Icons.volume_off
                        : Icons.volume_up,
                    onTap: player.toggleMute,
                    compact: true,
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
                    compact: true,
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
                    compact: true,
                  ),
                  _iconBtn(
                    icon: Icons.aspect_ratio,
                    onTap: onCycleFit,
                    compact: true,
                  ),
                  _abButton(accent),
                  _iconBtn(
                    icon: orientationLocked
                        ? Icons.screen_lock_rotation
                        : Icons.screen_rotation,
                    active: orientationLocked,
                    onTap: onToggleOrientationLock,
                    compact: true,
                  ),
                  const Spacer(),
                  _iconBtn(
                    icon: Icons.queue_music,
                    onTap: onToggleQueue,
                    compact: true,
                  ),
                  _iconBtn(
                    icon: isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    onTap: onToggleFullscreen,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// A-B loop: compact two-letter button; each letter lights up when set.
  Widget _abButton(Color accent) {
    final hasA = player.loopA != null;
    final hasB = player.loopB != null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        player.tapLoopPoint();
        onInteract();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'A',
                style: TextStyle(
                  color: hasA ? accent : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const TextSpan(
                text: '→',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              TextSpan(
                text: 'B',
                style: TextStyle(
                  color: hasB ? accent : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _speedMenu() {
    return PopupMenuButton<double>(
      initialValue: player.playbackRate,
      color: const Color(0xFF1a1a24),
      onSelected: (r) {
        player.setPlaybackRate(r);
        onInteract();
      },
      itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
          .map((r) => PopupMenuItem(
                value: r,
                child: Text('${r}x',
                    style: const TextStyle(color: Colors.white)),
              ))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Text('${player.playbackRate}x',
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    double size = 24,
    bool compact = false,
  }) {
    final accent = themeState.accent;
    return IconButton(
      icon: Icon(icon, size: compact ? 20 : size,
          color: active ? accent : Colors.white),
      // Compact rows must fit ~9 actions on a 320dp-wide phone.
      constraints:
          compact ? const BoxConstraints.tightFor(width: 34, height: 40) : null,
      padding: compact ? EdgeInsets.zero : null,
      visualDensity: compact ? VisualDensity.compact : null,
      // Every press also restarts the screen's auto-hide countdown.
      onPressed: () {
        onTap();
        onInteract();
      },
    );
  }
}
