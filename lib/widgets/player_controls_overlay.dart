import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/player_settings.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'progress_bar.dart';
import 'track_selection_sheet.dart';

/// Controls drawn on top of the video - v19 final-polish layout, v26 look:
///
///   [progress bar, with scrub thumbnail preview]
///   row 1:  previous  -  play/pause  -  next            (centered trio)
///   row 2:  mute - speed - Tracks(subs/audio/A-B)
///           ...  queue - fit - rotation lock
///
/// v26: every button follows the picked theme colour, EXCEPT the transport
/// trio (prev/play/next), which stays white and only flashes the accent as
/// a background effect WHILE pressed. The seek bar itself is untouched.
/// The rotation lock moved next to the fit button (user request).
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

  /// v26: reports seek-bar drag start/end; the screen pauses its auto-hide
  /// countdown while a scrub is in progress (controls faded mid-drag).
  final ValueChanged<bool> onScrubbing;

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
    required this.onScrubbing,
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
                onScrubbing: onScrubbing,
              ),
              // Row 1: previous / play-pause / next - the transport trio.
              // v26: these three STAY white; the theme colour appears only
              // as the press flash behind them (accentPress).
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _iconBtn(
                    icon: Icons.skip_previous,
                    size: 30,
                    accentPress: true,
                    tooltip: 'Previous video',
                    onTap: player.prevTrack,
                  ),
                  const SizedBox(width: 22),
                  _iconBtn(
                    icon: player.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 46,
                    accentPress: true,
                    onTap: player.togglePlay,
                  ),
                  const SizedBox(width: 22),
                  _iconBtn(
                    icon: Icons.skip_next,
                    size: 30,
                    accentPress: true,
                    tooltip: 'Next video',
                    onTap: player.nextTrack,
                  ),
                ],
              ),
              // Row 2 (compact): mute speed tracks | queue fit rotate
              Row(
                children: [
                  _iconBtn(
                    icon: player.isMuted || player.volume == 0
                        ? Icons.volume_off
                        : Icons.volume_up,
                    active: player.isMuted || player.volume == 0,
                    tooltip: 'Mute',
                    onTap: player.toggleMute,
                    compact: true,
                  ),
                  _speedMenu(),
                  _tracksMenu(context),
                  const Spacer(),
                  _iconBtn(
                    icon: Icons.queue_music,
                    tooltip: 'Queue',
                    onTap: onToggleQueue,
                    compact: true,
                  ),
                  _iconBtn(
                    tooltip: 'Fit: contain / cover / fill',
                    icon: Icons.aspect_ratio,
                    onTap: onCycleFit,
                    compact: true,
                  ),
                  // v26: rotation lock moved next to the fit button.
                  _iconBtn(
                    tooltip: orientationLocked
                        ? 'Rotation locked - tap for auto'
                        : 'Auto-rotate - tap to lock',
                    icon: orientationLocked
                        ? Icons.screen_lock_rotation
                        : Icons.screen_rotation,
                    active: orientationLocked,
                    onTap: onToggleOrientationLock,
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
    // v26: theme-coloured like the other row buttons; an "active" chip
    // background marks subtitles/audio/A-B in use.
    return _iconBtn(
      tooltip: 'Subtitles, audio tracks, A-B loop, karaoke',
      icon: Icons.tune,
      active: active,
      compact: true,
      onTap: () => _showTracksSheet(context),
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
      // v35: THIS is the button that was reported broken ("subtitles,
      // audio tracks, A-B loop, karaoke - not fully opens in phone"):
      // without isScrollControlled a bottom sheet is capped at HALF the
      // screen height, so in landscape (and on small phones) the A-B
      // loop and karaoke rows were clipped with no way to reach them.
      // A DraggableScrollableSheet sizes to content, always scrolls,
      // and drags up to 92% of the screen.
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: trackSheetInitialSize(
          8, // handle + subtitles + audio + A-B + karaoke + enhance + tone + dialogue
          MediaQuery.of(sheetContext).size.height,
        ),
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => SafeArea(
          top: false,
          child: ListView(
            controller: scrollController,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
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
              // v105: picture rows live here now (were Settings > Picture).
              // Switches stay live in the sheet (no pop) so several can be
              // flipped at once; the player state persists each one.
              StatefulBuilder(
                builder: (sbCtx, setSb) {
                  return SwitchListTile(
                    dense: true,
                    secondary: Icon(
                      Icons.auto_fix_high_outlined,
                      color: player.enhanceVideoOn
                          ? themeState.accent
                          : Colors.white70,
                    ),
                    title: const Text(
                      'Enhance video',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'GPU sharpen + contrast + colour boost',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: player.enhanceVideoOn,
                    activeThumbColor: themeState.accent,
                    onChanged: (v) async {
                      await player.setEnhanceVideo(v);
                      await NativeBridge.saveSetting(
                          PlayerSettings.kEnhanceVideo, '$v');
                      setSb(() {});
                      onInteract();
                    },
                  );
                },
              ),
              StatefulBuilder(
                builder: (sbCtx, setSb) {
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.hdr_on_outlined,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'HDR tone-mapping',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'How HDR10/Dolby sources fit your screen',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    trailing: DropdownButton<String>(
                      value: player.toneMappingMode,
                      dropdownColor: const Color(0xFF1a1a24),
                      underline: const SizedBox(),
                      items: const {
                        'auto': 'Auto',
                        'mobius': 'Mobius',
                        'hable': 'Hable',
                        'bt.2390': 'BT.2390',
                      }
                          .entries
                          .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value,
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) async {
                        await player.setToneMapping(v ?? 'auto');
                        setSb(() {});
                        onInteract();
                      },
                    ),
                  );
                },
              ),
              StatefulBuilder(
                builder: (sbCtx, setSb) {
                  return SwitchListTile(
                    dense: true,
                    secondary: Icon(
                      Icons.graphic_eq_outlined,
                      color: player.dialogueBoost
                          ? themeState.accent
                          : Colors.white70,
                    ),
                    title: const Text(
                      'Dialogue boost',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Lifts quiet speech (1-4 kHz). Off by default.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: player.dialogueBoost,
                    activeThumbColor: themeState.accent,
                    onChanged: (v) async {
                      await player.setDialogueBoost(v);
                      setSb(() {});
                      onInteract();
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
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
        // v26: the speed label follows the theme colour like the buttons.
        child: Text('${player.playbackRate}x',
            style: TextStyle(color: themeState.accent, fontSize: 11)),
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

    /// v26: the transport trio (prev/play/next) is the ONLY exception to
    /// the theme-coloured buttons: their icons stay white and the accent
    /// shows purely as the press flash behind the icon.
    bool accentPress = false,
  }) {
    final accent = themeState.accent;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(
        icon,
        size: compact ? 20 : size,
        // v26: every player button follows the picked theme colour
        // (accentPress buttons stay white - they flash it instead).
        color: accentPress ? Colors.white : accent,
      ),
      // Press-only theme colour for the transport trio.
      splashColor: accentPress ? accent.withValues(alpha: 0.45) : null,
      highlightColor: accentPress ? accent.withValues(alpha: 0.28) : null,
      // An "on" state (rotation locked, tracks in use, muted) sits on a
      // translucent accent chip so it reads as active even though every
      // icon is accent-coloured now.
      style: active
          ? ButtonStyle(
              backgroundColor: WidgetStateProperty.all(
                accent.withValues(alpha: 0.22),
              ),
            )
          : null,
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
