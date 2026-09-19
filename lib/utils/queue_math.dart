import 'dart:math';

/// Repeat mode shared by the audio engine and the video player queue
/// (v1.0.1 fix 3: video player gained shuffle/repeat buttons — same math).
enum AudioRepeatMode { off, all, one }

/// Pure next-track math (unit-tested — no engine involved).
/// Returns -1 when playback should STOP after the current track.
/// [rand] is injected for tests: it must map [count) -> 0..count-1.
int audioNextIndex({
  required int current,
  required int count,
  required bool shuffle,
  required AudioRepeatMode repeat,
  int Function(int maxExclusive)? rand,
}) {
  if (count <= 0 || current < 0) return -1;
  if (repeat == AudioRepeatMode.one) return current;
  if (shuffle) {
    final r = rand ?? Random().nextInt;
    var next = r(count);
    // Avoid the "shuffle plays the same song again" anti-feel when there
    // is more than one candidate.
    if (count > 1 && next == current) next = (next + 1) % count;
    return next;
  }
  final n = current + 1;
  if (n >= count) return repeat == AudioRepeatMode.all ? 0 : -1;
  return n;
}

/// Pure previous-track math: classic player semantics — wrap to the last
/// track from the first only under repeat-all, otherwise stay at 0.
int audioPrevIndex({
  required int current,
  required int count,
  required AudioRepeatMode repeat,
}) {
  if (count <= 0 || current < 0) return -1;
  if (current > 0) return current - 1;
  return repeat == AudioRepeatMode.all ? count - 1 : 0;
}
