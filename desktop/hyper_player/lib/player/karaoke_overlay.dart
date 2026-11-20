import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'karaoke.dart';
import 'srt.dart';
import 'android_controls.dart' show PlaybackSnapshot;

/// Matches Android's character-weighted word highlighting within timed subtitle
/// cues. This approximates word timings; it is not speech alignment/generation.
class KaraokeOverlay extends StatelessWidget {
  final ValueListenable<PlaybackSnapshot> playback;
  final ValueListenable<SrtCue?> cue;
  const KaraokeOverlay({super.key, required this.playback, required this.cue});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SrtCue?>(
      valueListenable: cue,
      builder: (_, line, __) => ValueListenableBuilder<PlaybackSnapshot>(
          valueListenable: playback,
          builder: (_, state, __) {
            final active =
                karaokeCueAt(line, null, state.position.inMilliseconds);
            if (active == null ||
                state.position.inMilliseconds < active.startMs) {
              return const SizedBox.shrink();
            }
            final words = active.text
                .split(RegExp(r'\s+'))
                .where((word) => word.isNotEmpty)
                .take(160)
                .toList();
            final highlighted =
                karaokeWordIndex(active, state.position.inMilliseconds);
            return IgnorePointer(
                child: Text.rich(
                    TextSpan(children: [
                      for (var i = 0; i < words.length; i++)
                        TextSpan(
                            text: '${i == 0 ? '' : ' '}${words[i]}',
                            style: TextStyle(
                                color: i <= highlighted
                                    ? Colors.amberAccent
                                    : Colors.white70,
                                fontWeight: i == highlighted
                                    ? FontWeight.w800
                                    : FontWeight.w500))
                    ]),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20,
                        height: 1.35,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 8)
                        ])));
          }));
}
