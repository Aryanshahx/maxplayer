/// Pure pinch-zoom + fit-ladder math shared by the player screen and unit
/// tests (ported 1:1 from the old MaxPlayer, v1.0.0+148).
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Pinch range: 1.0 = fit screen (the DEFAULT), up to 4x zoomed in.
const double kMinVideoZoom = 1.0;
const double kMaxVideoZoom = 4.0;

/// Keeps a pinch result inside [kMinVideoZoom]..[kMaxVideoZoom].
double clampVideoZoom(double v) => v.clamp(kMinVideoZoom, kMaxVideoZoom);

/// A quick two-finger TAP (both fingers down and up fast, with no real
/// pinch movement) means "snap back to fit screen" - the gesture MX/VLC
/// users expect. Anything with genuine scale change or long travel is a
/// real pinch, not a tap.
bool isTwoFingerTapReset({
  required int durationMs,
  required double travelPx,
  required bool scaled,
}) =>
    !scaled && travelPx < 24 && durationMs <= 400;

/// Spreading the fingers by this factor climbs exactly ONE fit step in the
/// two-finger fit loop. Kept moderate so all six fits are reachable inside
/// a normal phone pinch; the wrap-around means a firm spread just loops.
const double kFitLadderStepScale = 1.20;

double _log2(double v) => math.log(v) / math.ln2;

/// Maps a live pinch [scale] to a fit-ladder position, given the [basePos]
/// (integer fit index) captured when the fingers landed. The position is
/// UNBOUNDED on purpose - callers wrap it with [wrapFitLadderPos] so the
/// ladder loops Original -> Fit. Pure for tests.
double fitLadderPosFor({
  required double basePos,
  required double scale,
}) {
  if (scale <= 0) return basePos;
  return basePos + _log2(scale) / _log2(kFitLadderStepScale);
}

/// Wraps an unbounded ladder position into 0..[fitCount]-1 with
/// wrap-around (pos fitCount wraps back to 0; pos -1 wraps to
/// fitCount-1). This is what makes Original -> Fit loop.
int wrapFitLadderPos(double pos, int fitCount) {
  if (fitCount <= 0) return 0;
  var rounded = pos.round();
  rounded = rounded % fitCount;
  if (rounded < 0) rounded += fitCount;
  return rounded;
}

/// Two-finger zoom mode: the direct free-zoom map. Zoom = the zoom level
/// captured when the fingers landed ([baseZoom]) times the live pinch
/// [scale], clamped to 1.0x..4.0x. This is the whole map-app behavior in
/// one line; it makes zoom work from the FIRST millimetre of the pinch.
double freeZoomFor({
  required double baseZoom,
  required double scale,
}) =>
    clampVideoZoom(baseZoom * scale);

/// (v1.0.14) Clamped pan range for a center-scaled video: at zoom [z] the
/// frame overflows the viewport by (z-1)*size/2 on EACH side, so valid
/// pan is -half..+half on both axes. Scale in Flutter is center-based;
/// the old one-sided (-max..0) clamp left half the zoomed frame
/// unreachable and let the far end overscroll into black.
Offset clampPanFor({
  required Offset pan,
  required double zoom,
  required Size size,
}) {
  final halfX = size.width * (zoom - 1) / 2;
  final halfY = size.height * (zoom - 1) / 2;
  return Offset(
    pan.dx.clamp(-halfX, halfX).toDouble(),
    pan.dy.clamp(-halfY, halfY).toDouble(),
  );
}

/// v1.0.15: focal-anchored pinch pan. Flutter's Transform.scale pivots
/// around the CENTER of its child (default Alignment.center), so for an
/// anchor to stay pinned under the moving fingers the pan must satisfy:
///
///   screenPoint = pan + C + (childPoint - C) * zoom      (C = viewport center)
///
/// Given the touch-down focal, the start pan/zoom and the live
/// focal/zoom, the pan that keeps the touch-down content under the live
/// fingers is derived from those. The OLD formula
/// `liveFocal - (startFocal - startPan)/startZoom * zoom` is the same
/// physics with the pivot at the ORIGIN (0,0) instead of the center —
/// anchors drifted toward screen middle, i.e. "zoom doesn't happen where
/// my fingers are". Pure for tests.
Offset pinchPanFor({
  required Offset startFocal,
  required Offset liveFocal,
  required Offset startPan,
  required double startZoom,
  required double zoom,
  required Size size,
}) {
  final c = Offset(size.width / 2, size.height / 2);
  final v = startFocal - startPan - c;
  return liveFocal - c - v * (zoom / startZoom);
}
