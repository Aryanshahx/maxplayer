import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'progress_bar.dart';
import 'track_selection_sheet.dart';

/// Controls drawn on top of the video - v19 final-polish layout:
///
///   [progress bar, with scrub thumbnail preview]
///   row 1:  previous  -  play/pause  -  next            (centered trio)
///   row 2:  mute - speed - Tracks(subs/audio/A-B) - rotation lock
///           ...  queue - fit
///
/// Removed per the final polish pass: shuffle, repeat, the dedicated
/// +/-10 s buttons (horizontal drag-seek covers them) and the fullscreen
/// button (sensor auto-rotate replaces it); the fit cycle moved to the
/// corner where fullscreen used to sit.
///
/// This widget rebuilds itself via [AnimatedBuilder] on every player tick,
/// so the parent screen does NOT rebuild (which kept recreating the video
/// surface and caused fullscreen flicker).
class PlayerControlsOverlay extends StatelessWidget {
  final MediaPlayerState player;
  final VoidCallback onToggleQueue;

  /// Fired on every control interaction; the screen uses it to restart the
  /// auto-hide countdown.
  final VoidCallback onInteract;

  /// Cycles the video fit (contain -> cover -> fill).
  final VoidCallback onCycleFit;

  /// Rotation lock toggle (auto-rotate by sensor vs pinned).
  final bool orientationLocked;
  final VoidCallback onToggleOrientationLock;

  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.onToggleQueue,
    required this.onInteract,
    required this.onCycleFit,
    required this.orientationLocked,
    required this.onToggleOrientationLock,
    // v25: karaoke toggle moved INTO the tracks sheet (was the ⋮ menu).
    required this.karaokeOn,
    required this.onToggleKaraoke,
  });

  /// v25: karaoke state + toggle, so the tracks sheet can host the switch
  /// next to Subtitles / Audio track / A-B loop.
  final bool karaokeOn;
  final VoidCallback onToggleKaraoke;

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
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressBar(
                position: player.position,
                duration: player.duration,
                previewThumb: player.scrubThumbPath,
                onSeek: (d) {
                  player.seek(d);
                  onInteract();
                },
              ),
              // Row 1: previous / play-pause / next - the transport trio.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _iconBtn(
                    icon: Icons.skip_previous,
                    size: 30,
                    onTap: player.prevTrack,
                  ),
                  const SizedBox(width: 22),
                  _iconBtn(
                    icon: player.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 46,
                    onTap: player.togglePlay,
                  ),
                  const SizedBox(width: 22),
                  _iconBtn(
                    icon: Icons.skip_next,
                    size: 30,
                    onTap: player.nextTrack,
                  ),
                ],
              ),
              // Row 2 (compact): mute speed tracks rotate | queue fit
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
                  _tracksMenu(context),
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
                    tooltip: 'Fit: contain / cover / fill',
                    icon: Icons.aspect_ratio,
                    onTap: onCycleFit,
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

  /// One button opening ONE bottom sheet for everything track-shaped:
  /// subtitles, audio tracks, and the A-B loop (previously three separate
  /// buttons). v20: switched from PopupMenuButton to a bottom sheet - the
  /// popup glitched because this overlay rebuilds on every player tick
  /// while the popup was open.
  Widget _tracksMenu(BuildContext context) {
    final active = player.subtitlesActive ||
        player.audioTracks.length > 1 ||
        player.abLoopActive;
    return IconButton(
      tooltip: 'Subtitles, audio tracks, A-B loop',
      icon: Icon(
        Icons.tune,
        size: 20,
        color: active ? themeState.accent : Colors.white,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 40),
      onPressed: () {
        onInteract();
        _showTracksSheet(context);
      },
    );
  }

  void _showTracksSheet(BuildContext context) {
    final hasA = player.loopA != null;
    final hasB = player.loopB != null;
    final abSubtitle = hasA && hasB
        ? 'Looping ${formatDuration(player.loopA)} - ${formatDuration(player.loopB)} (tap to clear)'
        : hasA
            ? 'A set at ${formatDuration(player.loopA)} - tap to set B'
            : 'Off - tap to mark point A';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                player.subtitlesActive
                    ? Icons.subtitles
                    : Icons.subtitles_outlined,
                color: Colors.white70,
              ),
              title: Text(
                player.subtitlesActive ? 'Subtitles (on)' : 'Subtitles',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                TrackSelectionSheet.show(context, player, isSubtitle: true);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.audiotrack_outlined,
                color: Colors.white70,
              ),
              title: Text(
                player.audioTracks.length > 1
                    ? 'Audio track (${player.audioTracks.length} available)'
                    : 'Audio track',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                TrackSelectionSheet.show(context, player, isSubtitle: false);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.repeat_one_outlined,
                color: player.abLoopActive
                    ? themeState.accent
                    : Colors.white70,
              ),
              title: const Text(
                'A-B loop',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                abSubtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                final msg = player.tapLoopPoint();
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      duration: const Duration(milliseconds: 1400),
                    ),
                  );
              },
            ),
            ListTile(
              leading: Icon(
                karaokeOn
                    ? Icons.closed_caption
                    : Icons.closed_caption_off_outlined,
                color: karaokeOn ? themeState.accent : Colors.white70,
              ),
              title: Text(
                // v25: karaoke moved here from the ⋮ menu.
                karaokeOn ? 'Karaoke subtitles (on)' : 'Karaoke subtitles',
                style: TextStyle(
                    color:
                        karaokeOn ? themeState.accent : Colors.white),
              ),
              subtitle: const Text(
                'Words light up - other subtitles hide while on',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onToggleKaraoke();
              },
            ),
            const SizedBox(height: 8),
          ],
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
      itemBuilder: (context) =>
          const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0] // v22: up to 3x
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
    String? tooltip,
  }) {
    final accent = themeState.accent;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon,
          size: compact ? 20 : size, color: active ? accent : Colors.white),
      // Compact rows must fit ~7 actions on a 320dp-wide phone.
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
