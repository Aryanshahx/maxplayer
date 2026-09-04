import 'dart:async';

/// v98 feature coordinator foundation.
///
/// Keeps optional/experimental features out of the core playback state until
/// their native implementations are ready. Every feature is deliberately
/// capability-gated so unsupported devices can keep the stable player path.
class V98FeatureService {
  V98FeatureService._();

  static final V98FeatureService instance = V98FeatureService._();

  bool smartSleepEnabled = false;
  bool voiceScrubbingEnabled = true;
  bool aiUpscaleEnabled = false;
  bool frameInterpolationEnabled = false;

  Timer? _smartSleepTimer;
  DateTime? _eyesClosedSince;

  /// Feed local eye-state samples from the eventual Android camera/ML layer.
  /// A stable closed state for 30 seconds is considered a smart-sleep trigger.
  bool updateEyeClosed(bool closed) {
    if (!smartSleepEnabled) {
      _eyesClosedSince = null;
      return false;
    }
    if (!closed) {
      _eyesClosedSince = null;
      return false;
    }
    _eyesClosedSince ??= DateTime.now();
    return DateTime.now().difference(_eyesClosedSince!) >=
        const Duration(seconds: 30);
  }

  void startSmartSleep({required void Function() onTriggered}) {
    smartSleepEnabled = true;
    _smartSleepTimer?.cancel();
    _smartSleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (updateEyeClosed(true)) {
        onTriggered();
        _eyesClosedSince = null;
      }
    });
  }

  void stopSmartSleep() {
    smartSleepEnabled = false;
    _eyesClosedSince = null;
    _smartSleepTimer?.cancel();
    _smartSleepTimer = null;
  }

  void dispose() {
    _smartSleepTimer?.cancel();
    _smartSleepTimer = null;
    _eyesClosedSince = null;
  }
}
