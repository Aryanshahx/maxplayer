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
        final cues = player.aiCues;
        if (cues == null || cues.isEmpty) return const SizedBox.shrink();
        final cue = karaokeActiveCue(cues, player.position.inMilliseconds);
        if (cue == null) return const SizedBox.shrink();
        final activeIdx = karaokeWordIndex(cue, player.position.inMilliseconds);
        final words =
            cue.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

        const baseColor = Color(0xE6FFFFFF); // 90% white
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
