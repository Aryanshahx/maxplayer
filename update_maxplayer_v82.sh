#!/usr/bin/env bash
# Max Player v82 update script
# Run from the repo root: ~/IdeaProjects/maxplayer
set -euo pipefail

if [ ! -f "pubspec.yaml" ]; then
  echo "ERROR: run this from the maxplayer repo root (pubspec.yaml not found here)."
  exit 1
fi

echo "==> Patching lib/utils/srt.dart (Ask-AI now recognizes .vtt sidecar subtitles too)"
python3 - <<'PYEOF'
import sys
p = "lib/utils/srt.dart"
s = open(p, encoding="utf-8").read()
old = '''/// Picks the best subtitle file sitting next to a video from a directory
/// listing ([fileNames] = basenames in the video's folder). These are the
/// files mpv auto-loads, so parsing the same pick lets karaoke + skip-intro
/// work on ordinary subtitled videos. Pure + unit-tested.
///
/// Ranking: exact "<name>.srt" first, then language-suffixed
/// "<name>.<xx>.srt" (alphabetical). The AI sidecar ("<name>.maxai.srt")
/// has its own pipeline and is always excluded.
List<String> sidecarSrtCandidates(List<String> fileNames, String videoPath) {
  final base = videoPath.replaceAll(r'\\', '/').split('/').last;
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
}'''
new = '''/// Picks the best subtitle file sitting next to a video from a directory
/// listing ([fileNames] = basenames in the video's folder). These are the
/// files mpv auto-loads, so parsing the same pick lets karaoke + skip-intro
/// work on ordinary subtitled videos. Pure + unit-tested.
///
/// Ranking: exact "<name>.srt"/"<name>.vtt" first, then language-suffixed
/// "<name>.<xx>.srt"/"<name>.<xx>.vtt" (alphabetical). The AI sidecar
/// ("<name>.maxai.srt") has its own pipeline and is always excluded.
///
/// v82: matches .vtt (WebVTT) as well as .srt now - mpv auto-loads and
/// displays .vtt sidecars the exact same way as .srt, but this used to
/// only ever look for .srt, so Ask-AI reported "no transcript" for any
/// video whose visible subtitle was a .vtt file. [parseSrt]'s timing
/// regex already accepts VTT's dot-decimal timestamps, so no separate
/// parser is needed - just recognizing the extension was the whole fix.
List<String> sidecarSrtCandidates(List<String> fileNames, String videoPath) {
  final base = videoPath.replaceAll(r'\\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  final stem = (dot > 0 ? base.substring(0, dot) : base).toLowerCase();
  String? exact;
  final langMatches = <String>[];
  for (final raw in fileNames) {
    final f = raw.toLowerCase();
    final isSub = f.endsWith('.srt') || f.endsWith('.vtt');
    if (!isSub) continue;
    if (f == '$stem.srt' || f == '$stem.vtt') {
      exact ??= raw;
      continue;
    }
    if (f.endsWith('.maxai.srt')) continue;
    if (f.startsWith('$stem.')) langMatches.add(raw);
  }
  langMatches.sort();
  return [if (exact != null) exact, ...langMatches];
}'''
if old not in s:
    sys.exit("[srt.dart] anchor not found, aborting")
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching test/widget_test.dart (add a test for .vtt sidecar support)"
python3 - <<'PYEOF'
import sys
p = "test/widget_test.dart"
s = open(p, encoding="utf-8").read()
old = """    test('unrelated files and non-srt are ignored', () {
      final names = ['movie.srt.txt', 'other.srt', 'movie.txt', '.srt'];
      expect(sidecarSrtCandidates(names, '/m/movie.mp4'), isEmpty);
    });
  });"""
new = """    test('unrelated files and non-srt are ignored', () {
      final names = ['movie.srt.txt', 'other.srt', 'movie.txt', '.srt'];
      expect(sidecarSrtCandidates(names, '/m/movie.mp4'), isEmpty);
    });
    test('v82: .vtt sidecar is picked the same way as .srt', () {
      final names = ['movie.vtt', 'movie.eng.vtt'];
      expect(sidecarSrtCandidates(names, '/m/movie.mp4'), [
        'movie.vtt',
        'movie.eng.vtt',
      ]);
    });
  });"""
if old not in s:
    print("  WARNING: test anchor not found - skipping test addition (main fix still applied)")
else:
    s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("  OK")
PYEOF

echo ""
echo "===================================================================="
echo " v82 applied. What changed:"
echo "  Found the real remaining bug: the sidecar-subtitle scanner only"
echo "  ever looked for '.srt' files. mpv itself auto-loads and shows"
echo "  '.vtt' (WebVTT) sidecar subtitles identically to '.srt' - so if"
echo "  your video's visible subtitle is a .vtt file sitting next to it,"
echo "  you'd SEE it play fine while Ask-AI still said 'no transcript',"
echo "  because its own file scan never recognized that extension."
echo "  Now it does - no separate parser needed, the existing timestamp"
echo "  parser already understood VTT's format."
echo "===================================================================="
echo ""
echo "If this STILL doesn't fix it for your test video, it means the"
echo "subtitle is EMBEDDED in the video file itself (baked into an MKV,"
echo "selected via the Subtitles button) rather than a separate .srt/.vtt"
echo "file next to it. That's a different, bigger problem - Android/mpv"
echo "renders embedded subtitles internally and never hands the app their"
echo "text. Fixing that needs an FFmpeg-based extraction step, and I want"
echo "to flag something important: the standard library for that"
echo "(ffmpeg-kit) was pulled from Maven Central in 2025 and the whole"
echo "Android FFmpeg-wrapper ecosystem is currently in flux with no single"
echo "obvious stable replacement yet. I don't want to wire up a dependency"
echo "that might not even resolve when you build. Tell me which case is"
echo "yours (embedded vs. a separate .vtt/.srt/.ass file) and I'll scope"
echo "the right fix properly instead of guessing again."
echo "===================================================================="
echo ""
echo "Next steps:"
echo "  flutter analyze        # should print: No issues found!"
echo "  flutter test"
echo "  flutter build appbundle --release"
echo "  git add -A && git commit -m 'v82: Ask-AI now recognizes .vtt sidecar subtitles, not just .srt' && git push"
