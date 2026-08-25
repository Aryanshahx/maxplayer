/// Pure pinch-zoom math shared by the player screen and unit tests (v52).
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

/// v59 (user's final design, after he phone-tested v58): finished
/// two-finger gesture -> snap home ONLY on a quick tap. The expand
/// ladder keeps whatever fit/zoom the pinch landed on; a real pinch is
/// never undone. Legacy/unknown values conservatively snap home.
bool twoFingerSnapsToFit({required String mode, required bool wasTap}) {
  if (mode == 'fit' || mode == 'zoom') return wasTap;
  return true; // legacy/unknown stored value
}

// ---------------------------------------------------------------------------
// v59 THE EXPAND LADDER - "make ALL fits reachable by expanding fingers,
// and zooming must work afterwards". Spreading two fingers walks up:
//
//   Fit -> Crop -> Stretch -> 16:9 -> 4:3 -> Original -> smooth ZOOM (4x)
//
// Pinching IN walks back down the same ladder. Fit steps live at integer
// positions 0..fitCount-1; everything above fitCount-1 is the zoom region
// (pos (fitCount-1)+1.0 == kMaxVideoZoom over the top fit).
// ---------------------------------------------------------------------------

/// Spreading the fingers by this factor climbs exactly ONE ladder step.
/// v60 retune (his phone report: the ladder never REACHED zoom - 1.35
/// per step needed a ~4.5x finger spread): 1.20 per step puts the zoom
/// region inside a normal phone pinch (~2.6x spread gets you there).
const double kFitLadderStepScale = 1.20;

/// Growth rate of the zoom REGION past the last fit (pos +1 == zoom
/// 2^slope). 2.6 makes the zoom arrive fast once you cross Original.
const double kFitLadderZoomSlope = 2.6;

double _log2(double v) => math.log(v) / math.ln2;

/// The ladder position of the CURRENT UI state (gesture start anchor):
/// zoomed in -> up in the zoom region; otherwise the plain fit index.
double fitLadderPosOf({
  required int fitIndex,
  required int fitCount,
  required double zoom,
}) {
  if (zoom > kMinVideoZoom) {
    final p = (fitCount - 1) + _log2(zoom) / kFitLadderZoomSlope;
    return p.clamp(0.0, (fitCount - 1) + _log2(kMaxVideoZoom) / kFitLadderZoomSlope);
  }
  return fitIndex.toDouble().clamp(0.0, (fitCount - 1).toDouble());
}

/// Maps a live pinch [scale] to an absolute ladder position, given the
/// [basePos] captured when the fingers landed. Pure for tests.
double fitLadderPosFor({
  required double basePos,
  required double scale,
  required int fitCount,
}) {
  if (scale <= 0) return basePos;
  final maxPos =
      (fitCount - 1) + _log2(kMaxVideoZoom) / kFitLadderZoomSlope;
  return (basePos + _log2(scale) / _log2(kFitLadderStepScale))
      .clamp(0.0, maxPos);
}

/// Turns a ladder position back into UI state: inside the fit region
/// (-> nearest fit, zoom 1x), above it -> smooth zoom over the top fit.
({int fitIndex, double zoom}) fitLadderDecode(double pos, int fitCount) {
  if (pos <= fitCount - 1) {
    return (fitIndex: pos.round().clamp(0, fitCount - 1), zoom: kMinVideoZoom);
  }
  final z = math.pow(2, (pos - (fitCount - 1)) * kFitLadderZoomSlope).toDouble();
  return (
    fitIndex: fitCount - 1,
    zoom: z.clamp(kMinVideoZoom, kMaxVideoZoom),
  );
}
