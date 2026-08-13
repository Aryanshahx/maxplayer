import 'package:path/path.dart' as p;

/// Where the AI subtitle runner writes sidecar files for [videoPath]:
/// "<video-name>.maxai.srt" next to the video. Shared by the runner and
/// the DLNA caster (which offers this file to the TV).
String srtPathForVideo(String videoPath) {
  final dir = p.dirname(videoPath);
  final base = p.basenameWithoutExtension(videoPath);
  return p.join(dir, '$base.maxai.srt');
}

/// One SRT subtitle cue.
class SrtCue {
  final int startMs;
  final int endMs;
  final String text;
  const SrtCue(this.startMs, this.endMs, this.text);
}

/// Builds a standards-compliant .srt document from cues. Pure + unit-tested.
///
/// Rules applied:
///  - cues with empty text are dropped
///  - an end before/at the start is bumped to start + 1s (players reject
///    zero-length cues)
///  - cues are sorted by start time and numbered from 1
String buildSrt(List<SrtCue> cues) {
  final usable = cues.where((c) => c.text.trim().isNotEmpty).toList()
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  final out = StringBuffer();
  for (var i = 0; i < usable.length; i++) {
    final c = usable[i];
    final end = c.endMs > c.startMs ? c.endMs : c.startMs + 1000;
    out
      ..writeln(i + 1)
      ..writeln('${_srtTime(c.startMs)} --> ${_srtTime(end)}')
      ..writeln(c.text.trim())
      ..writeln();
  }
  return out.toString();
}

/// ms -> "HH:MM:SS,mmm" (SRT format uses a comma for millis).
String _srtTime(int ms) {
  if (ms < 0) ms = 0;
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  final milli = ms % 1000;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)},${milli.toString().padLeft(3, '0')}';
}


// ---------------------------------------------------------------------------
// v21 additions: parsing + smart-caption helpers
// ---------------------------------------------------------------------------

final RegExp _srtTimeLine = RegExp(
  r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})',
);

/// Parses an .srt document back into cues (inverse of [buildSrt]).
///
/// Deliberately tolerant: sequence numbers are ignored, blank lines end a
/// cue, and timing lines that do not match the classic "HH:MM:SS,mmm -->
/// HH:MM:SS,mmm" shape are skipped. Used by the karaoke overlay, the
/// skip-intro chip and transcript search.
List<SrtCue> parseSrt(String doc) {
  final cues = <SrtCue>[];
  final lines = doc.split(RegExp(r'\r?\n'));
  var i = 0;
  while (i < lines.length) {
    final m = _srtTimeLine.firstMatch(lines[i]);
    if (m == null) {
      i++;
      continue;
    }
    int ms(int h, int mm, int s, String frac) =>
        ((h * 60 + mm) * 60 + s) * 1000 +
        int.parse(frac.padRight(3, '0').substring(0, 3));
    final start = ms(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      m.group(4)!,
    );
    final end = ms(
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
      int.parse(m.group(7)!),
      m.group(8)!,
    );
    i++;
    final textLines = <String>[];
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      textLines.add(lines[i].trim());
      i++;
    }
    cues.add(SrtCue(start, end, textLines.join(' ')));
  }
  return cues;
}

/// Picks the best subtitle file sitting next to a video from a directory
/// listing ([fileNames] = basenames in the video's folder). These are the
/// files mpv auto-loads, so parsing the same pick lets karaoke + skip-intro
/// work on ordinary subtitled videos. Pure + unit-tested.
///
/// Ranking: exact "<name>.srt" first, then language-suffixed
/// "<name>.<xx>.srt" (alphabetical). The AI sidecar ("<name>.maxai.srt")
/// has its own pipeline and is always excluded.
List<String> sidecarSrtCandidates(List<String> fileNames, String videoPath) {
  final base = videoPath.replaceAll(r'\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  final stem = (dot > 0 ? base.substring(0, dot) : base).toLowerCase();
  String? exact;
  final langMatches = <String>[];
  for (final raw in fileNames) {
    final f = raw.toLowerCase();
    if (!f.endsWith('.srt')) continue;
    if (f == '$stem.srt') {
      exact ??= raw;
      continue;
    }
    if (f.endsWith('.maxai.srt')) continue;
    if (f.startsWith('$stem.')) langMatches.add(raw);
  }
  langMatches.sort();
  return [if (exact != null) exact, ...langMatches];
}

/// Whisper's music-only captions ("♪", "[Music]", "(upbeat music)") carry no
/// dialogue - karaoke, skip-intro and transcript search skip them.
bool isMusicOnlyText(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  if (t.contains('♪')) return true;
  final t2 = t.toLowerCase();
  final starts = t2.startsWith('[') || t2.startsWith('(') || t2.startsWith('*');
  if (!starts) return false;
  return t2.contains('music') ||
      t2.contains('applause') ||
      t2.contains('laughter') ||
      t2.contains('silence') ||
      t2.contains('noise');
}

/// Where the dialogue actually begins: start of the first spoken (non-music)
/// cue, minus a 1 s margin. Returns null when speech starts almost right
/// away (< 20 s - nothing to skip) or later than 10 minutes in (by then a
/// chip no longer makes sense).
Duration? computeSkipIntro(List<SrtCue> cues) {
  for (final c in cues) {
    if (isMusicOnlyText(c.text)) continue;
    if (c.startMs < 20000) return null; // talking right away
    if (c.startMs > 600000) return null; // 10+ min of silence: not an intro
    final target = (c.startMs - 1000).clamp(0, 1 << 31);
    return Duration(milliseconds: target);
  }
  return null;
}
