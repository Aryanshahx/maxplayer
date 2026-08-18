import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/srt.dart';

/// Word index to highlight for [cue] at playback position [posMs].
///
/// whisper.cpp only gives us per-CUE timestamps, so word timing inside a cue
/// is approximated: each word occupies a time slice proportional to its
/// character count (spoken English/Hindi is remarkably even per letter).
/// Top-level + pure so the widget test can pin the behavior.
int karaokeWordIndex(SrtCue cue, int posMs) {
  final words = cue.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final list = words.toList();
  if (list.isEmpty) return -1;
  final span = cue.endMs - cue.startMs;
  if (span <= 0) return 0;
  final frac = ((posMs - cue.startMs) / span).clamp(0.0, 1.0);
  final totalChars = list.fold<int>(0, (a, w) => a + w.length);
  if (totalChars == 0) return 0;
  var target = frac * totalChars;
  for (var i = 0; i < list.length; i++) {
    if (target < list[i].length) return i;
    target -= list[i].length;
  }
  return list.length - 1;
}

/// The cue active at [posMs] (last cue that already started; a trailing
/// 600 ms grace keeps short gaps from flickering).
SrtCue? karaokeActiveCue(List<SrtCue> cues, int posMs) {
  SrtCue? active;
  for (final c in cues) {
    if (isMusicOnlyText(c.text)) continue;
    if (c.startMs <= posMs) {
      active = (posMs <= c.endMs + 600) ? c : active;
    } else {
      break;
    }
  }
  if (active != null && posMs > active.endMs + 600) return null;
  return active;
}

/// Which cue the karaoke overlay should show at [posMs]. Pure + unit-tested.
///
/// Priority (v22):
///  1. [live] - the line mpv is displaying right now, read through its
///     sub-text/sub-start/sub-end properties. Real cue timing, and works
///     with ANY subtitle source (embedded mkv tracks included).
///  2. [aiCues] - the AI sidecar's cue list.
///  3. [sidecarCues] - the video's own same-name .srt file.
SrtCue? karaokeCueAt(
  SrtCue? live,
  List<SrtCue>? aiCues,
  List<SrtCue>? sidecarCues,
  int posMs,
) {
  if (live != null && posMs <= live.endMs + 600) return live;
  final fromAi = aiCues == null ? null : karaokeActiveCue(aiCues, posMs);
  if (fromAi != null) return fromAi;
  return sidecarCues == null ? null : karaokeActiveCue(sidecarCues, posMs);
}

/// Karaoke-style AI subtitle: words light up one by one as they are spoken.
/// Shown instead of mpv's own subtitle rendering while the setting is on.
class KaraokeSubtitle extends StatelessWidget {
  final MediaPlayerState player;

  const KaraokeSubtitle({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final posMs = player.position.inMilliseconds;
        final cue = karaokeCueAt(
          player.liveSubCue,
          player.aiCues,
          player.sidecarCues,
          posMs,
        );
        if (cue == null) return const SizedBox.shrink();
        final activeIdx = karaokeWordIndex(cue, posMs);
        final words =
            cue.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

        // v22: unlit words are dimmed further so the accent highlight
        // stays visible even when the accent itself is white.
        const baseColor = Colors.white54;
        const shadow = [
          Shadow(color: Colors.black, blurRadius: 6),
          Shadow(color: Colors.black, offset: Offset(0, 1)),
        ];
        final spans = <InlineSpan>[
          for (var i = 0; i < words.length; i++)
            TextSpan(
              text: i == 0 ? words[i] : ' ${words[i]}',
              style: TextStyle(
                color: i <= activeIdx ? themeState.accent : baseColor,
                fontSize: 17,
                fontWeight: i == activeIdx ? FontWeight.w800 : FontWeight.w500,
                shadows: shadow,
                height: 1.35,
              ),
            ),
        ];
        return IgnorePointer(
          child: Padding(
            // v40: 16px side padding - exactly what media_kit's
            // SubtitleView uses, so karaoke text wraps at the same width
            // as default / AI subtitles (the overlay itself is positioned
            // at the SubtitleView spot by PlayerScreen).
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text.rich(
              TextSpan(children: spans),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}
