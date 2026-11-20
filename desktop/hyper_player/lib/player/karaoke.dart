import 'srt.dart';

/// Karaoke-subtitle helpers, ported from the old app's
/// `widgets/karaoke_subtitle.dart`. Word-level timing inside a cue is
/// approximated: each word occupies a time slice proportional to its
/// character count (spoken English/Hindi is remarkably even per letter).

/// Word index to highlight for [cue] at playback position [posMs]. -1 when
/// the cue has no words.
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
/// 600 ms grace keeps short gaps from flickering). Music-only captions are
/// skipped.
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

/// Which cue the karaoke overlay should show at [posMs]. Priority:
///  1. [live]  — the line mpv is displaying right now (any subtitle source:
///     embedded mkv tracks, sidecar .srt and AI-generated .maxai.srt alike).
///  2. [sidecarCues] — the video's own same-name .srt file.
SrtCue? karaokeCueAt(
  SrtCue? live,
  List<SrtCue>? sidecarCues,
  int posMs,
) {
  if (live != null && posMs <= live.endMs + 600) return live;
  return sidecarCues == null ? null : karaokeActiveCue(sidecarCues, posMs);
}
