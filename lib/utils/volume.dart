/// Pure volume math shared by the Dart player and verified by tests.
///
/// Background (v1.0.8 / drop "volume stuck" fix): on several OEM skins
/// (Realme UI, ColorOS, MIUI, OriginOS) `AudioManager.setStreamVolume()`
/// completes WITHOUT throwing but secretly ignores the change — the
/// stream level never actually moves. The player used to believe the
/// success reply, so its mpv-gain fallback never engaged and the volume
/// swipe appeared dead ("stuck at device volume"). The native side now
/// reads the stream level BACK and only claims success when the device
/// truly applied the target; these helpers keep that check testable.
library;

/// Device stream level (in ticks, 0..[max]) matching [fraction] (0..1).
///
/// Mirrors the Kotlin side exactly (round, clamp to the stream max) so
/// the Dart and Android computations can never disagree on what counts
/// as "the device applied the change".
int targetDeviceLevel(double fraction, int max) {
  final safeMax = max < 1 ? 1 : max;
  final t = (fraction.clamp(0.0, 1.0) * safeMax).round();
  return t.clamp(0, safeMax);
}

/// True when the level read back from the device equals what we asked
/// for. A mismatch means an OEM skin swallowed the change even though
/// the platform call reported success — the caller must treat that as
/// failure so the player falls back to mpv gain.
bool deviceVolumeApplied(int target, int readback) => target == readback;

/// The fraction (0..1) the device ACTUALLY applied, computed from the
/// read-back level. Used to keep the on-screen pill honest when an OEM
/// skin quantizes requests to its own tick count.
double readbackFraction(int readback, int max) {
  final safeMax = max < 1 ? 1 : max;
  final r = readback.clamp(0, safeMax);
  return r / safeMax;
}
