import 'package:flutter/services.dart';

/// Result of a native metadata extraction for one video file.
class VideoMetadata {
  final Duration? duration;
  final String? thumbnailPath;
  final int? width;
  final int? height;

  /// Overall bitrate in bits/sec (from the container), if reported.
  final int? bitrateBps;

  /// Friendly video codec name (e.g. "H.265 (HEVC)"); works on every
  /// Android version (read via MediaExtractor track MIME).
  final String? codec;

  /// v27 advanced video info: video frame rate (0 = container omits it),
  /// and the FIRST audio track's details (null/0 = none or unknown).
  final int? frameRate;
  final String? audioCodec;
  final int? audioChannels;
  final int? audioSampleRate;

  /// v32: detected dynamic range of the video track:
  /// 'sdr' | 'hdr10' | 'hdr10+' | 'hlg' | 'dolby-vision'.
  /// Dolby Vision plays via its HDR10-compatible fallback layer.
  final String? hdr;

  const VideoMetadata({
    this.duration,
    this.thumbnailPath,
    this.width,
    this.height,
    this.bitrateBps,
    this.codec,
    this.frameRate,
    this.audioCodec,
    this.audioChannels,
    this.audioSampleRate,
    this.hdr,
  });
}

/// One AI-generated subtitle cue (whisper.cpp segment).
class AiSegment {
  final int startMs;
  final int endMs;
  final String text;
  const AiSegment(this.startMs, this.endMs, this.text);
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
  static void Function(String stage, int percent)? _onAiProgress;
  static void Function(List<AiSegment> segments)? _onAiDone;
  static void Function(String error)? _onAiFailed;

  /// v62 Phase 1: a notification was tapped. The argument is the opaque
  /// payload string the feature passed when it posted the notification -
  /// treat it like a deep link (e.g. "ai:<jobId>" or "video:<path>").
  static void Function(String payload)? _onNotificationTap;

  /// v67 B1: media notification action tapped ('play_pause', 'next', 'prev', 'stop').
  static void Function(String action)? _onMediaAction;

  /// v70 C4: media notification seekbar / smartwatch scrub tapped.
  static void Function(Duration position)? _onMediaSeek;

  /// v70: custom in-app microphone speech recognition callbacks.
  static void Function(String state)? _onVoiceState;
  static void Function(double rms)? _onVoiceRms;
  static void Function(String text)? _onVoicePartial;
  static void Function(String text)? _onVoiceResult;
  static void Function(int error)? _onVoiceError;

  /// v48: one finished cloud slice - raw .srt text at an absolute offset.
  static bool _handlerRegistered = false;

  /// Registers (or replaces) the app-level native event callbacks.
  static void configureCallbacks({
    void Function(String path)? onOpenVideo,
    void Function(String uri)? onOpenVideoFailed,
    void Function(bool isPip)? onPipChanged,

    /// Fired when the play/pause button ON THE PiP WINDOW is tapped.
    void Function()? onPipAction,

    /// AI subtitle job progress events (see [aiSubtitleGenerate]).
    void Function(String stage, int percent)? onAiProgress,
    void Function(List<AiSegment> segments)? onAiDone,
    void Function(String error)? onAiFailed,

    /// v62 Phase 1: a posted notification was tapped by the user.
    void Function(String payload)? onNotificationTap,

    /// v67 B1: media notification action tapped.
    void Function(String action)? onMediaAction,

    /// v70 C4: media notification seek action.
    void Function(Duration position)? onMediaSeek,

    /// v70: custom voice search callbacks.
    void Function(String state)? onVoiceState,
    void Function(double rms)? onVoiceRms,
    void Function(String text)? onVoicePartial,
    void Function(String text)? onVoiceResult,
    void Function(int error)? onVoiceError,
  }) {
    if (onOpenVideo != null) _onOpenVideo = onOpenVideo;
    if (onOpenVideoFailed != null) _onOpenVideoFailed = onOpenVideoFailed;
    if (onPipChanged != null) _onPipChanged = onPipChanged;
    if (onPipAction != null) _onPipAction = onPipAction;
    if (onAiProgress != null) _onAiProgress = onAiProgress;
    if (onAiDone != null) _onAiDone = onAiDone;
    if (onAiFailed != null) _onAiFailed = onAiFailed;
    if (onNotificationTap != null) _onNotificationTap = onNotificationTap;
    if (onMediaAction != null) _onMediaAction = onMediaAction;
    if (onMediaSeek != null) _onMediaSeek = onMediaSeek;
    if (onVoiceState != null) _onVoiceState = onVoiceState;
    if (onVoiceRms != null) _onVoiceRms = onVoiceRms;
    if (onVoicePartial != null) _onVoicePartial = onVoicePartial;
    if (onVoiceResult != null) _onVoiceResult = onVoiceResult;
    if (onVoiceError != null) _onVoiceError = onVoiceError;
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
      case 'onAiProgress':
        final m = call.arguments as Map?;
        if (m != null) {
          _onAiProgress?.call(
            '${m['stage']}',
            (m['percent'] as num?)?.toInt() ?? 0,
          );
        }
        break;
      case 'onAiSubtitleDone':
        final list = call.arguments as Map?;
        final raw = list?['segments'] as List?;
        if (raw != null) {
          final segments = <AiSegment>[
            for (final e in raw)
              if (e is Map)
                AiSegment(
                  (e['start'] as num?)?.toInt() ?? 0,
                  (e['end'] as num?)?.toInt() ?? 0,
                  '${e['text']}',
                ),
          ];
          _onAiDone?.call(segments);
        }
        break;
      case 'onAiSubtitleFailed':
        final m = call.arguments as Map?;
        _onAiFailed?.call('${m?['message'] ?? 'failed'}');
        break;
      case 'onNotificationTap':
        final p = call.arguments as String?;
        if (p != null && p.isNotEmpty) _onNotificationTap?.call(p);
        break;
      case 'onMediaAction':
        final a = call.arguments as String?;
        if (a != null && a.isNotEmpty) _onMediaAction?.call(a);
        break;
      case 'onMediaSeek':
        final ms = call.arguments as num?;
        if (ms != null) _onMediaSeek?.call(Duration(milliseconds: ms.toInt()));
        break;
      case 'onVoiceState':
        final s = call.arguments as String?;
        if (s != null) _onVoiceState?.call(s);
        break;
      case 'onVoiceRms':
        final r = call.arguments as num?;
        if (r != null) _onVoiceRms?.call(r.toDouble());
        break;
      case 'onVoicePartial':
        final p = call.arguments as String?;
        if (p != null) _onVoicePartial?.call(p);
        break;
      case 'onVoiceResult':
        final res = call.arguments as String?;
        if (res != null) _onVoiceResult?.call(res);
        break;
      case 'onVoiceError':
        final err = call.arguments as num?;
        if (err != null) _onVoiceError?.call(err.toInt());
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
      final bitrate = res['bitrate'];
      final fps = res['frameRate'];
      final aCh = res['audioChannels'];
      final aRate = res['audioSampleRate'];
      return VideoMetadata(
        duration: durationMs is int ? Duration(milliseconds: durationMs) : null,
        thumbnailPath: res['thumbnailPath'] as String?,
        width: width is int ? width : null,
        height: height is int ? height : null,
        bitrateBps: bitrate is int ? bitrate : null,
        codec: res['codec'] as String?,
        // v27: advanced track details (0 on the wire = unknown -> null).
        frameRate: fps is int && fps > 0 ? fps : null,
        audioCodec: res['audioCodec'] as String?,
        audioChannels: aCh is int && aCh > 0 ? aCh : null,
        audioSampleRate: aRate is int && aRate > 0 ? aRate : null,
        // v32: 'sdr' | 'hdr10' | 'hdr10+' | 'hlg' | 'dolby-vision'.
        hdr: res['hdr'] as String?,
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

  // --- Device MEDIA volume (player swipe drives the real system volume) ---

  /// Current media volume as 0..1. Falls back to 1.0 when unavailable.
  static Future<double> getMediaVolume() async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getMediaVolume',
      );
      final level = (res?['level'] as num?)?.toDouble() ?? 1.0;
      final max = (res?['max'] as num?)?.toDouble() ?? 1.0;
      if (max <= 0) return 1.0;
      return (level / max).clamp(0.0, 1.0);
    } catch (_) {
      return 1.0;
    }
  }

  /// Sets the device media volume (0..1). MX Player / VLC style: the
  /// player's inline volume IS the system media volume, so the user can
  /// always reach the phone's true maximum.
  static Future<void> setMediaVolume(double value) async {
    try {
      await _channel.invokeMethod('setMediaVolume', {
        'value': value.clamp(0.0, 1.0),
      });
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

  // --- AI subtitles (v54: back ON DEVICE, offline & free) ---

  /// Returns the whisper.cpp system-info string when the on-device AI
  /// subtitle engine is bundled and its native library loads, else null.
  /// Used by the About sheet as a build verification.
  static Future<String?> whisperEngineStatus() async {
    try {
      final res = await _channel.invokeMethod<String>('whisperAvailable');
      return (res != null && res.isNotEmpty) ? res : null;
    } catch (_) {
      return null;
    }
  }

  /// Which models are present on device. Returns {base: MB, small: MB};
  /// 0 MB means "not downloaded yet".
  static Future<Map<String, int>> aiModelStatus() async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'aiModelStatus',
      );
      if (res == null) return const {};
      return res.map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return const {};
    }
  }

  /// Starts the offline AI subtitle job for [videoPath]. Returns the job id
  /// immediately; progress/completion arrive via [configureCallbacks]
  /// (`onAiProgress` / `onAiDone` / `onAiFailed`). [model] is base/small;
  /// [language] is a whisper language code or 'auto' (detect). A null job
  /// id means the engine cannot run here (32-bit-only chip).
  static Future<int?> aiSubtitleGenerate({
    required String videoPath,
    String model = 'base',
    String language = 'auto',
    // whisper's translate task - any spoken language -> English subs.
    bool translate = false,
  }) async {
    try {
      return await _channel.invokeMethod<int>('aiSubtitleGenerate', {
        'videoPath': videoPath,
        'model': model,
        'language': language,
        'translate': translate,
      });
    } catch (_) {
      return null;
    }
  }

  /// Asks the running job to stop (effective during download/extraction; a
  /// running transcription finishes but its result is discarded).
  static Future<void> aiSubtitleCancel() async {
    try {
      await _channel.invokeMethod('aiSubtitleCancel');
    } catch (_) {}
  }

  /// Registers [path] with the Android media scanner so freshly-written
  /// files (screenshots, AI subtitles) show up in gallery apps at once.
  static Future<void> scanFile(String path) async {
    try {
      await _channel.invokeMethod('scanFile', {'path': path});
    } catch (_) {}
  }

  /// v22: the cache-file path the native scanner uses for [path]'s
  /// thumbnail (null for streams/missing files). The player writes an
  /// mpv-captured frame there when Android can't decode one itself.
  static Future<String?> thumbnailPathFor(String path) async {
    try {
      return await _channel.invokeMethod<String>('thumbnailPathFor', {
        'path': path,
      });
    } catch (_) {
      return null;
    }
  }

  /// v24: absolute path of the Private-folder vault directory, created and
  /// owned through the Android framework (no storage permission needed).
  /// Null = this build can't provide one.
  static Future<String?> vaultDirPath() async {
    try {
      return await _channel.invokeMethod<String>('vaultDirPath');
    } catch (_) {
      return null;
    }
  }

  /// v28 Cleaner tile: reclaimable app storage in bytes, split by kind
  /// ({thumbs, strips, temp, models}). Your videos are never included.
  static Future<Map<String, int>> storageReport() async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'storageReport',
      );
      if (res == null) return const {};
      return res.map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return const {};
    }
  }

  /// v28: deletes one storage kind ('thumbs' | 'temp' | 'models') and
  /// returns the freed bytes. Everything is recreated on demand.
  static Future<int> clearStorage(String kind) async {
    try {
      final res = await _channel.invokeMethod<int>('clearStorage', {
        'kind': kind,
      });
      return res ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// v31 Cleaner: total/free bytes of the device's internal storage
  /// (StatFs on the app files dir). Null when the platform side is
  /// unavailable (desktop, tests) - the UI hides the graph then.
  static Future<DeviceStorage?> storageTotals() async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'storageTotals',
      );
      if (res == null) return null;
      final total = (res['total'] as num?)?.toInt() ?? 0;
      final free = (res['free'] as num?)?.toInt() ?? 0;
      if (total <= 0) return null;
      return DeviceStorage(total: total, free: free);
    } catch (_) {
      return null;
    }
  }

  /// Holds/releases the Wi-Fi multicast lock used during DLNA (SSDP)
  /// device discovery. [hold] true = acquire, false = release.
  static Future<void> setMulticastLock(bool hold) async {
    try {
      await _channel.invokeMethod('setMulticastLock', hold);
    } catch (_) {}
  }

  /// v26: asks for the PHONE's own unlock secret - device PIN / pattern /
  /// password, or fingerprint/face - before the Private-folder PIN may be
  /// reset (user request: a forgotten PIN must not be openable by anyone
  /// holding the unlocked phone). True = the owner proved it; false =
  /// cancelled / failed / unavailable. A device WITHOUT any screen lock
  /// answers true (nothing exists to ask - the unlocked phone is the
  /// proof of possession).
  static Future<bool> confirmDeviceCredential({String? title}) async {
    try {
      final res = await _channel.invokeMethod<bool>('confirmDeviceCredential', {
        'title': title ?? 'Unlock to continue',
      });
      return res == true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // v19: sensor-driven rotation + scrub thumbnail strip
  // ---------------------------------------------------------------------------

  /// Player rotation that IGNORES the phone's system auto-rotate switch:
  /// native tracks the accelerometer and requests portrait/landscape
  /// directly (MX Player / VLC style). Enabled when the player opens.
  static Future<void> enableSensorRotate() async {
    try {
      await _channel.invokeMethod('enableSensorRotate');
    } catch (_) {}
  }

  /// Hands rotation control back to the system (leaving the player).
  static Future<void> disableSensorRotate() async {
    try {
      await _channel.invokeMethod('disableSensorRotate');
    } catch (_) {}
  }

  /// Rotation lock chip: pins the player to landscape (both sides still
  /// flippable) or portrait until [enableSensorRotate] is called again.
  static Future<void> lockRotation({required bool landscape}) async {
    try {
      await _channel.invokeMethod('lockRotation', {'landscape': landscape});
    } catch (_) {}
  }

  /// Ensures a strip of small JPEG frames exists for scrub previews and
  /// returns its cache directory (null for streams/failures). Idempotent:
  /// a strip is generated once per file and reused after that.
  static Future<String?> thumbStripEnsure(String path) async {
    try {
      return await _channel.invokeMethod<String>('thumbStripEnsure', {
        'path': path,
      });
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // v34: Android-layer crash reporter ("Max Player has stopped")
  // ---------------------------------------------------------------------------

  /// Reads the JVM crash report the native Application class recorded
  /// after an uncaught Android-layer exception; null when there is none.
  /// (Dart-side errors are journaled separately by CrashLog.)
  static Future<String?> nativeCrashGet() async {
    try {
      return await _channel.invokeMethod<String>('nativeCrashGet');
    } catch (_) {
      return null;
    }
  }

  /// Wipes the stored Android-layer crash report (after it was shown).
  static Future<void> nativeCrashClear() async {
    try {
      await _channel.invokeMethod('nativeCrashClear');
    } catch (_) {}
  }

  /// v37: startup breadcrumb - appends a stage mark to
  /// maxplayer_start.log (internal + Android/data). If the app dies early
  /// on some phone, that file shows the last stage it reached.
  static Future<void> crumb(String stage) async {
    try {
      await _channel.invokeMethod('crumb', {'stage': stage});
    } catch (_) {}
  }

  /// v38: Android API level of the device (0 when unknown - treated as
  /// "old" by callers so they take the maximally-compatible path).
  static Future<int> sdkInt() async {
    try {
      return await _channel.invokeMethod<int>('sdkInt') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// v40: absolute roots of every mounted storage volume (internal storage
  /// AND any SD card), so the library scanner can cover all of them. The
  /// old scanner walked only "/storage/emulated/0/" - videos on SD cards
  /// never appeared. Falls back to internal storage when the channel is
  /// missing (tests, very old builds).
  static Future<List<String>> storageRoots() async {
    try {
      final List<Object?>? res =
          await _channel.invokeMethod<List<Object?>>('storageRoots');
      if (res == null) return const ['/storage/emulated/0'];
      final roots = [for (final r in res) if (r != null) '$r'];
      return roots.isEmpty ? const ['/storage/emulated/0'] : roots;
    } catch (_) {
      return const ['/storage/emulated/0'];
    }
  }

  /// v43: the app's private cache directory (Discover's TMDB responses +
  /// poster images are cached here without any permission).
  static Future<String?> cacheDirPath() async {
    try {
      return await _channel.invokeMethod<String>('cacheDirPath');
    } catch (_) {
      return null;
    }
  }

  /// v43: opens a trailer in the official YouTube app (or browser
  /// fallback). This is the Play-policy-safe way to show trailers -
  /// playing a YouTube stream through our own player would violate
  /// YouTube's terms and get the app banned.
  static Future<bool> openYouTube(String videoKey) async {
    try {
      return await _channel
              .invokeMethod<bool>('openYouTube', {'key': videoKey}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // v110: Android system document picker (SAF) - "Select video", no sign-in
  // ---------------------------------------------------------------------------

  /// Opens Android's built-in file picker (ACTION_OPEN_DOCUMENT, video/*
  /// only). The picker lists this device plus every installed storage
  /// provider app - including Google Drive when the user has it - with NO
  /// Google sign-in and no Drive-API OAuth verification. Returns null when
  /// the user cancels or the document cannot be read. On success the map
  /// holds: path (real device path, or a cache copy for cloud documents),
  /// name, cached (true when path is a temporary copy), sourceUri,
  /// sizeBytes.
  static Future<Map<String, dynamic>?> pickVideoDocument() async {
    try {
      final res = await _channel
          .invokeMethod<Map<Object?, Object?>>('pickVideoDocument');
      if (res == null) return null;
      return {
        for (final e in res.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } catch (_) {
      return null;
    }
  }

  /// Saves a permanent copy of a picked cloud video into
  /// Movies/Max Player (MediaStore on Android 10+, the public Movies folder
  /// below that). Reads the SAF URI when its grant survived, otherwise the
  /// cache copy made for playback. Returns {name, path, location} on
  /// success, null on failure. path itself can be null even on success
  /// (scoped storage hides real paths) - location always says where it went.
  static Future<Map<String, dynamic>?> savePickedVideoToDevice({
    String? sourceUri,
    String? cachePath,
    required String name,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'saveDocumentToDevice',
        {'sourceUri': sourceUri, 'cachePath': cachePath, 'name': name},
      );
      if (res == null) return null;
      return {
        for (final e in res.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // v62 Phase 1: notifications
  // ---------------------------------------------------------------------------

  /// Whether notifications are currently allowed. On Android 12 and below
  /// this is true at install time; on Android 13+ it reflects the runtime
  /// POST_NOTIFICATIONS grant. Always false on desktop/tests (no channel).
  static Future<bool> notificationsEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('notificationsEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the Android 13+ runtime notification permission dialog. On older
  /// versions (or if already granted) returns the current state without
  /// prompting. Returns whether notifications are enabled afterwards.
  static Future<bool> requestNotifications() async {
    try {
      return await _channel.invokeMethod<bool>('requestNotifications') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Posts (or replaces) a notification and returns the system id used
  /// (pass 0 to let the native side allocate one).
  ///
  /// [channel] must be one of the [NotificationChannels] constants. Tapping
  /// the notification delivers [payload] to the `onNotificationTap` callback
  /// (use it as a deep link, e.g. "ai:<jobId>"). [ongoing] notifications
  /// can't be swiped away; [progress] (0..100) shows a progress bar.
  static Future<int> showNotification({
    required String channel,
    required String title,
    required String body,
    int id = 0,
    String? payload,
    bool ongoing = false,
    int? progress,
  }) async {
    try {
      final res = await _channel.invokeMethod<int>('notifyShow', {
        'channel': channel,
        'title': title,
        'body': body,
        'id': id,
        if (payload != null) 'payload': payload,
        'ongoing': ongoing,
        if (progress != null) 'progress': progress,
      });
      return res ?? id;
    } catch (_) {
      return id;
    }
  }

  /// Cancels one notification by [id].
  static Future<void> cancelNotification(int id) async {
    try {
      await _channel.invokeMethod('notifyCancel', {'id': id});
    } catch (_) {}
  }

  /// Clears every Max Player notification.
  static Future<void> cancelAllNotifications() async {
    try {
      await _channel.invokeMethod('notifyCancelAll');
    } catch (_) {}
  }

  /// Cold-start payload from a notification tap that launched the app
  /// (null when the app was already running or launched normally). The
  /// value is consumed once.
  static Future<String?> getInitialNotificationPayload() async {
    try {
      final res =
          await _channel.invokeMethod<String>('getInitialNotificationPayload');
      return (res != null && res.isNotEmpty) ? res : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // v66 A5: voice search in Discover
  // ---------------------------------------------------------------------------

  /// Launches the in-app speech recognition or fallback dialog.
  static Future<bool> startVoiceSearch() async {
    try {
      final res = await _channel.invokeMethod('startVoiceSearch');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// v72: Directly launches system Google speech recognition modal dialogue.
  static Future<String?> launchSystemVoiceSearch() async {
    try {
      final res =
          await _channel.invokeMethod<String>('launchSystemVoiceSearch');
      return (res != null && res.trim().isNotEmpty) ? res.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Stops in-app speech recognition.
  static Future<void> stopVoiceSearch() async {
    try {
      await _channel.invokeMethod('stopVoiceSearch');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // v67 B1/B2: now-playing controls & background / screen-off audio
  // ---------------------------------------------------------------------------

  /// Shows or updates the ongoing Now-Playing notification with Play/Pause,
  /// Next, Previous and Stop actions, plus thumbnail and scrub playbar.
  static Future<int> showNowPlaying({
    required String title,
    String subtitle = 'Max Player',
    required bool isPlaying,
    required String path,
    String? thumbnailPath,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    try {
      final res = await _channel.invokeMethod<int>('nowPlayingShow', {
        'title': title,
        'subtitle': subtitle,
        'isPlaying': isPlaying,
        'path': path,
        if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
        'positionMs': positionMs,
        'durationMs': durationMs,
      });
      return res ?? 1001;
    } catch (_) {
      return 1001;
    }
  }

  /// Cancels the Now-Playing notification.
  static Future<void> cancelNowPlaying() async {
    try {
      await _channel.invokeMethod('nowPlayingCancel');
    } catch (_) {}
  }

  /// Acquires or releases a partial wake lock to keep background audio playing.
  static Future<void> setWakeLock(bool enable) async {
    try {
      await _channel.invokeMethod('setWakeLock', {'enable': enable});
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // v68: VLC-style immersive mode (WindowInsetsController / cutout mode)
  // ---------------------------------------------------------------------------

  /// Hides status and navigation bars with swipe-to-reveal transient behavior
  /// and enables full-bleed drawing under camera notches/cutouts.
  static Future<void> setImmersive(bool enabled) async {
    try {
      await _channel.invokeMethod('setImmersive', {'enabled': enabled});
    } catch (_) {}
  }
}

/// v62 Phase 1: the notification channels Max Player creates. Matches the
/// native `Notifications.CHANNEL_*` constants. Pick the channel that fits
/// the feature so users can mute each kind independently in system settings.
class NotificationChannels {
  /// An on-device AI subtitle job finished (low urgency).
  static const String aiSubs = 'ai_subs';

  /// "Continue watching" jump-back-into-a-video reminders.
  static const String continueWatching = 'continue';

  /// A followed series has a new season/episode.
  static const String newEpisodes = 'new_episodes';

  /// Ongoing playback / now-playing (low, persistent).
  static const String playback = 'playback';

  /// Anything that doesn't fit the above.
  static const String general = 'general';

  static const List<String> all = [
    aiSubs,
    continueWatching,
    newEpisodes,
    playback,
    general,
  ];

  const NotificationChannels._();
}

/// v31: device internal-storage totals for the cleaner's storage graph.
class DeviceStorage {
  final int total;
  final int free;
  const DeviceStorage({required this.total, required this.free});

  int get used => total - free;

  /// 0..1 fill of the usage bar (guarded against a bogus total).
  double get usedFraction => total <= 0 ? 0 : (used.clamp(0, total)) / total;
}
