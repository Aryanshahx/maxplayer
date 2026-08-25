/// Pure pinch-zoom + fit-ladder math shared by the player screen and unit
/// tests.
library;

import 'dart:math' as math;

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

/// v61 (user's final design, after phone-testing v59/v60): what a finished
/// two-finger gesture does depends ONLY on whether it was a quick tap.
///
///   - a quick two-finger TAP always snaps back to the default fit screen
///     (so you are never stuck zoomed in / on a weird fit);
///   - a real pinch is NEVER undone - the player keeps whatever fit/zoom
///     the fingers landed on.
///
/// Works identically in BOTH toggle modes ('fit' loop and 'zoom' free
/// zoom). Legacy/unknown stored values conservatively snap home.
bool twoFingerSnapsToFit({required String mode, required bool wasTap}) {
  if (mode == 'fit' || mode == 'zoom') return wasTap;
  return true; // legacy/unknown stored value
}

// ---------------------------------------------------------------------------
// v61 THE TWO-FINGER TOGGLE - "when toggle is off then only fit screens in
// loop; when toggle is on then only zoom". The old v59/v60 continuous
// ladder (Fit -> ... -> Original -> smooth ZOOM) is GONE: it buried zoom at
// the top behind a ~2.6x spread, so on a real phone zoom was effectively
// unreachable. Now the two modes are cleanly separate:
//
//   TOGGLE OFF ('fit'): a spread walks the six fit modes in a LOOP -
//     Fit -> Crop -> Stretch -> 16:9 -> 4:3 -> Original -> back to Fit ->
//     ... and a pinch walks back down the same loop. It NEVER zooms
//     (zoom stays exactly 1.0 the whole time).
//
//   TOGGLE ON ('zoom'): a pinch does ONLY free zoom, 1.0x..4.0x, exactly
//     like a map app: zoom = clamp(baseZoom * scale). No fit cycling at
//     all. A quick two-finger tap resets to 1.0x.
// ---------------------------------------------------------------------------

/// Spreading the fingers by this factor climbs exactly ONE fit step in the
/// toggle-OFF loop. Kept moderate so all six fits are reachable inside a
/// normal phone pinch; the wrap-around means a firm spread just loops.
const double kFitLadderStepScale = 1.20;

double _log2(double v) => math.log(v) / math.ln2;

/// v61 toggle-OFF: maps a live pinch [scale] to a fit-ladder position,
/// given the [basePos] (integer fit index) captured when the fingers
/// landed. The position is UNBOUNDED on purpose - callers wrap it with
/// [wrapFitLadderPos] so the ladder loops Original -> Fit. Pure for tests.
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

/// v61 toggle-ON: the direct free-zoom map. Zoom = the zoom level captured
/// when the fingers landed ([baseZoom]) times the live pinch [scale],
/// clamped to 1.0x..4.0x. This is the whole map-app behavior in one line;
/// it makes zoom work from the FIRST millimetre of the pinch instead of
/// being hidden at the top of a ladder.
double freeZoomFor({
  required double baseZoom,
  required double scale,
}) =>
    clampVideoZoom(baseZoom * scale);
