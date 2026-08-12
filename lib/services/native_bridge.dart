import 'package:flutter/services.dart';

/// Result of a native metadata extraction for one video file.
class VideoMetadata {
  final Duration? duration;
  final String? thumbnailPath;
  final int? width;
  final int? height;

  const VideoMetadata({
    this.duration,
    this.thumbnailPath,
    this.width,
    this.height,
  });
}

/// Bridge to the Android native code in `MainActivity.kt` over a single
/// MethodChannel ("maxplayer/native"):
///
///  - [fetchMetadata]: duration + cached JPEG thumbnail per video. This
///    replaces the `video_thumbnail` plugin, which was incompatible with the
///    AGP 9 / Kotlin 2.3 toolchain — the native side has no external deps.
///  - [loadSettings] / [saveSetting]: a tiny key/value store backed by
///    Android SharedPreferences, avoiding another plugin dependency.
///  - brightness helpers for the player's left-half swipe.
///  - "Open with" VIDEO intent delivery (cold + warm).
///  - Picture-in-picture enter + state callbacks.
///
/// IMPORTANT: there is exactly ONE MethodChannel.setMethodCallHandler
/// registration ([_dispatch]) — a second registration would silently replace
/// the first. All native->Dart events flow through the callbacks configured
/// via [configureCallbacks].
///
/// EVERY call is guarded: where the channel doesn't exist (unit tests,
/// desktop platforms), calls fail silently and return empty values.
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('maxplayer/native');

  static void Function(String path)? _onOpenVideo;
  static void Function(String uri)? _onOpenVideoFailed;
  static void Function(bool isPip)? _onPipChanged;
  static void Function()? _onPipAction;
  static bool _handlerRegistered = false;

  /// Registers (or replaces) the app-level native event callbacks.
  static void configureCallbacks({
    void Function(String path)? onOpenVideo,
    void Function(String uri)? onOpenVideoFailed,
    void Function(bool isPip)? onPipChanged,

    /// Fired when the play/pause button ON THE PiP WINDOW is tapped.
    void Function()? onPipAction,
  }) {
    if (onOpenVideo != null) _onOpenVideo = onOpenVideo;
    if (onOpenVideoFailed != null) _onOpenVideoFailed = onOpenVideoFailed;
    if (onPipChanged != null) _onPipChanged = onPipChanged;
    if (onPipAction != null) _onPipAction = onPipAction;
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    _channel.setMethodCallHandler(_dispatch);
  }

  static Future<dynamic> _dispatch(MethodCall call) async {
    switch (call.method) {
      case 'onOpenVideo':
        final p = call.arguments as String?;
        if (p != null && p.isNotEmpty) _onOpenVideo?.call(p);
        break;
      case 'onOpenVideoFailed':
        final u = call.arguments as String?;
        if (u != null) _onOpenVideoFailed?.call(u);
        break;
      case 'onPipChanged':
        _onPipChanged?.call(call.arguments == true);
        break;
      case 'onPipAction':
        _onPipAction?.call();
        break;
    }
    return null;
  }

  static Future<VideoMetadata> fetchMetadata(String path) async {
    try {
      final Map<Object?, Object?>? res = await _channel
          .invokeMethod<Map<Object?, Object?>>('getMetadata', {'path': path});
      if (res == null) return const VideoMetadata();
      final durationMs = res['durationMs'];
      final width = res['width'];
      final height = res['height'];
      return VideoMetadata(
        duration: durationMs is int ? Duration(milliseconds: durationMs) : null,
        thumbnailPath: res['thumbnailPath'] as String?,
        width: width is int ? width : null,
        height: height is int ? height : null,
      );
    } catch (_) {
      return const VideoMetadata();
    }
  }

  static Future<Map<String, String>> loadSettings() async {
    try {
      final Map<Object?, Object?>? res = await _channel
          .invokeMethod<Map<Object?, Object?>>('settingsGetAll');
      if (res == null) return <String, String>{};
      return res.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return <String, String>{};
    }
  }

  static Future<void> saveSetting(String key, String value) async {
    try {
      await _channel.invokeMethod('settingsPut', {'key': key, 'value': value});
    } catch (_) {
      // Ignore - settings persistence is best-effort.
    }
  }

  // --- App-local screen brightness (player swipe gesture) ---

  static Future<double> getBrightness() async {
    try {
      final res = await _channel.invokeMethod<double>('getBrightness');
      if (res != null) return res.clamp(0.0, 1.0);
    } catch (_) {}
    return 1.0;
  }

  static Future<void> setBrightness(double value) async {
    try {
      await _channel.invokeMethod('setBrightness', {'value': value});
    } catch (_) {}
  }

  /// Give control back to the system auto-brightness.
  static Future<void> resetBrightness() async {
    try {
      await _channel.invokeMethod('resetBrightness');
    } catch (_) {}
  }

  // --- "Open with" intent delivery ---

  /// Cold-start check: a video opened from another app before Dart attached.
  /// Returns a map with keys 'path' (resolved file path) and/or 'failed'
  /// (the URI we could not resolve); both may be null.
  static Future<Map<String, String>> getInitialOpenVideo() async {
    try {
      final Map<Object?, Object?>? res = await _channel
          .invokeMethod<Map<Object?, Object?>>('getInitialOpenVideo');
      if (res == null) return const {};
      final out = <String, String>{};
      for (final key in ['path', 'failed']) {
        final v = res[key];
        if (v is String && v.isNotEmpty) out[key] = v;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  // --- Picture in picture ---

  /// Ask Android to enter PiP. [playing] picks the correct initial icon for
  /// the PiP window's play/pause remote action.
  static Future<void> enterPip({bool playing = true}) async {
    try {
      await _channel.invokeMethod('enterPip', {'playing': playing});
    } catch (_) {}
  }

  /// Keeps the PiP window's play/pause action in sync with the player.
  /// Cheap no-op when not in PiP (and on non-Android platforms).
  static Future<void> setPipPlaying(bool playing) async {
    try {
      await _channel.invokeMethod('setPipPlaying', playing);
    } catch (_) {}
  }
}
