/// Pure pinch-zoom math shared by the player screen and unit tests (v52).
library;

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

/// v57/v58: what a finished two-finger gesture should do, from the
/// Settings choice (PlayerSettings.kTwoFingerModes). DEFAULT is 'fit':
/// every two-finger gesture ends up at fit screen (pinch zoom is off;
/// pinch STEPS through the fits instead - see nextFitIndex). 'zoom':
/// pinch keeps its zoom; only a quick two-finger TAP snaps home so the
/// user is never stuck zoomed in. Legacy/unknown values = 'fit' default.
bool twoFingerSnapsToFit({required String mode, required bool wasTap}) {
  if (mode == 'zoom') return wasTap;
  return true; // 'fit' (DEFAULT) and any legacy/unknown value
}

/// v58 (user's design): with the zoom switch OFF, a two-finger pinch
/// STEPS through the fit list (Fit, Crop, Stretch, 16:9, 4:3, Original):
/// dir=+1 = pinch OUT -> next fit, dir=-1 = pinch IN -> previous fit.
/// Wraps around both ways. Pure for tests.
int nextFitIndex({required int cur, required int dir, required int length}) {
  final n = (cur + dir) % length;
  return n < 0 ? n + length : n;
}
