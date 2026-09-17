/// Pure gate for the brightness/volume swipe haptics (v1.0.17).
///
/// The gestures piggyback on each drag's whole-percent changes: fire a
/// soft tick on every 1% crossed, and ONE slightly firmer edge tap the
/// moment the drag reaches min/max — never a buzz flood (firing on every
/// pointer-move is exactly why naive haptic attempts get silently dropped
/// by Android).
library;

enum GestureTick { none, tick, edgeLow, edgeHigh }

/// Decide what (if anything) to buzz for, when the displayed percent moves
/// from [prevPct] to [pct] inside [minPct]..[maxPct].
/// [prevPct] is null on the first sample of a drag (finger just arrived)
/// and never causes a buzz by itself.
GestureTick gestureTickFor(int? prevPct, int pct, int minPct, int maxPct) {
  // Both sides clamped: a prev that came in already past the bound (e.g.
  // finger held beyond the ceiling) must gate ONCE-then-silence the same
  // as an honest crossing — never a tick storm at the bound.
  final next = pct.clamp(minPct, maxPct);
  if (prevPct == null) return GestureTick.none;
  final prev = prevPct.clamp(minPct, maxPct);
  if (next == prev) return GestureTick.none;
  if (next <= minPct && prev > minPct) return GestureTick.edgeLow;
  if (next >= maxPct && prev < maxPct) return GestureTick.edgeHigh;
  return GestureTick.tick;
}
