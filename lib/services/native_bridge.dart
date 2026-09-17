import 'package:flutter/services.dart';

import '../utils/ai_subtitles.dart';

/// Thin bridge to the Android side for the Drop 5 ports that need the
/// platform: the system document picker (cloud import), the private-folder
/// vault directory, system delete-consent, and on-demand thumbnails for
/// vault files. Everything fails soft (null / false / sensible defaults)
/// so tests and non-Android hosts never crash.
///
/// Uses its own channel (`maxplayer/storage`) so the incoming `onPickProgress`
/// events never collide with the player's `pipToggle` handler, which lives on
/// `maxplayer/native`.
class NativeBridge {
  NativeBridge._();

  // Storage operations are handled by maxplayer/storage. Player/device
  // operations (rename, speech recognition) live on the main native
  // channel. Keeping the two channels separate prevents calls from being
  // silently swallowed by the wrong Android handler.
  static const MethodChannel _channel = MethodChannel('maxplayer/storage');
  static const MethodChannel _nativeChannel = MethodChannel('maxplayer/native');

  /// Native -> Dart: cloud import copy progress (done, total bytes).
  static void Function(int done, int total)? pickProgressListener;

  static bool _handlerSet = false;

  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPickProgress') {
        final args = call.arguments;
        if (args is Map) {
          final done = (args['done'] as num?)?.toInt() ?? 0;
          final total = (args['total'] as num?)?.toInt() ?? 0;
          pickProgressListener?.call(done, total);
        }
      }
      return null;
    });
  }

  /// Android API level (0 when unknown — callers take the safe path).
  static Future<int> sdkInt() async {
    try {
      return await _channel.invokeMethod<int>('sdkInt') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Absolute path of the app's private vault directory (created through
  /// the Android framework — no storage permission needed). Null when the
  /// platform can't provide one.
  static Future<String?> vaultDirPath() async {
    try {
      return await _channel.invokeMethod<String>('vaultDirPath');
    } catch (_) {
      return null;
    }
  }

  /// Pings the Android media scanner for [path] so freshly-written files
  /// (vault exports) show up in gallery apps at once. Best-effort.
  static Future<void> scanFile(String path) async {
    try {
      await _channel.invokeMethod('scanFile', {'path': path});
    } catch (_) {}
  }

  /// Opens Android's system document picker (ACTION_OPEN_DOCUMENT, video/*).
  /// The picker lists this device plus every installed storage provider
  /// (Google Drive, Dropbox, OneDrive, ...) with no sign-in. Returns
  /// {path, name, cached, sourceUri, sizeBytes} or null on cancel.
  static Future<Map<String, dynamic>?> pickVideoDocument() async {
    _ensureHandler();
    try {
      final res =
          await _channel.invokeMethod<Map<Object?, Object?>>('pickVideoDocument');
      if (res == null) return null;
      return {
        for (final e in res.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } catch (_) {
      return null;
    }
  }

  /// Saves a permanent copy of a picked cloud video into Movies/Max Player
  /// (MediaStore on Android 10+, the public Movies folder below that).
  /// Returns {name, path, location} on success, null on failure.
  static Future<Map<String, dynamic>?> savePickedVideoToDevice({
    String? sourceUri,
    String? cachePath,
    required String name,
    String? relativePath,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'saveDocumentToDevice',
        {
          'sourceUri': sourceUri,
          'cachePath': cachePath,
          'name': name,
          'relativePath': relativePath,
        },
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

  /// v1.0.10: ask MainActivity to swallow volume keys and forward them to
  /// [volumeKeyListener] instead of the device media stream. The player
  /// enables this when opened and disables on dispose.
  static Future<void> setVolumeKeyIntercept(bool enabled) async {
    try {
      await _nativeChannel
          .invokeMethod('setVolumeKeyIntercept', {'enabled': enabled});
    } catch (_) {}
  }

  /// Aborts the in-flight cloud copy started by pickVideoDocument; the
  /// partial cache file is discarded natively. Safe to call anytime.
  static Future<void> abortPickCopy() async {
    try {
      await _channel.invokeMethod('abortPickCopy');
    } catch (_) {}
  }

  /// System delete-consent for shared-storage videos (vault hide flow).
  /// API 30+ shows one batch dialog; API 29 asks per file. True when the
  /// originals are gone; false when the user declines or deletion fails.
  static Future<bool> requestMediaDelete(List<String> paths) async {
    try {
      final res = await _channel
          .invokeMethod<bool>('requestMediaDelete', {'paths': paths});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Cached thumbnail file for [path] (a vault video). Builds one through
  /// the native MediaMetadataRetriever pipeline when the cache has no entry,
  /// and returns its absolute path — or null when it can't be decoded.
  static Future<String?> videoThumbnail(String path) async {
    try {
      return await _channel.invokeMethod<String>('videoThumbnail', {
        'path': path,
      });
    } catch (_) {
      return null;
    }
  }

  /// Renames a shared-storage video. [id] is the MediaStore _ID
  /// (photo_manager's AssetEntity.id) used to build the content URI directly
  /// — far more reliable than re-resolving the raw path on scoped storage.
  /// On Android 10+ this goes through MediaStore (updating DISPLAY_NAME)
  /// because a raw `File.rename` fails with "protected or in use"; on older
  /// Android / app-owned files the file itself is renamed on disk. True on
  /// success.
  static Future<bool> renameVideo(
      {required String id,
      required String path,
      required String newName}) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('renameVideo', {
        'id': id,
        'path': path,
        'newName': newName,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }



  /// Launches Android's speech recognition (in-app SpeechRecognizer first,
  /// system dialog as fallback) and returns the recognised query, or null on
  /// cancel/error. Callers must request the microphone permission first.
  static Future<String?> launchSystemVoiceSearch() async {
    try {
      final res =
          await _nativeChannel.invokeMethod<String>('launchSystemVoiceSearch');
      return (res != null && res.trim().isNotEmpty) ? res.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Starts the in-app speech recognizer (returns true when it began).
  /// Live events arrive through the callbacks configured by
  /// [ensureNativeHandler].
  static Future<bool> startVoiceSearch() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('startVoiceSearch');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stops the in-app speech recognizer. Safe to call anytime.
  static Future<void> stopVoiceSearch() async {
    try {
      await _nativeChannel.invokeMethod('stopVoiceSearch');
    } catch (_) {}
  }

  /// Real codec dimensions of [path] probed through the native
  /// MediaMetadataRetriever (rotation already applied, cached natively).
  /// Returns (width, height) or null when the file can't be decoded.
  /// Used for the quality badge when MediaStore reports 0×0 (common for
  /// MKV / WebM / AVI files).
  static Future<(int, int)?> videoDimensions(String path) async {
    try {
      final res = await _channel
          .invokeMethod<Map<Object?, Object?>>('videoDimensions', {
        'path': path,
      });
      final w = (res?['w'] as num?)?.toInt();
      final h = (res?['h'] as num?)?.toInt();
      if (w != null && h != null && w > 0 && h > 0) return (w, h);
      return null;
    } catch (_) {
      return null;
    }
  }






  /// v31: on-device facts for the About → Diagnostics sheet (support).
  static Future<Map<String, dynamic>> diagnostics() async {
    try {
      final raw = await _nativeChannel.invokeMethod<Map<Object?, Object?>>(
        'diagnostics',
      );
      if (raw == null) return const {};
      final out = raw.map((k, v) => MapEntry(k.toString(), v));
      return out;
    } catch (_) {
      return const {};
    }
  }


  // -------------------------------------------------------------------------
  // Single dispatcher for `maxplayer/native` INCOMING events. There must be
  // exactly ONE setMethodCallHandler on a channel — a second registration
  // silently replaces the first — so every native->Dart event (PiP button,
  // whisper AI-subtitle progress, voice-search callbacks) routes through
  // here. Registered once from main(); the player registers its callbacks
  // (pipToggleListener) instead of its own handler.
  // -------------------------------------------------------------------------
  static void Function()? pipToggleListener;

  /// v1.0.10: hardware volume keys, forwarded by MainActivity only while a
  /// player screen told the native side to intercept them (device stream
  /// stays untouched; the in-app AppVolume store is adjusted instead).
  static void Function(String dir)? volumeKeyListener;

  static void Function(String state)? onVoiceState;
  static void Function(double rms)? onVoiceRms;
  static void Function(String text)? onVoicePartial;
  static void Function(String text)? onVoiceResult;
  static void Function(int error)? onVoiceError;

  static bool _nativeHandlerSet = false;

  /// Registers the one-and-only `maxplayer/native` incoming-event handler.
  /// Idempotent — call it from main() and anywhere a feature starts.
  static void ensureNativeHandler() {
    if (_nativeHandlerSet) return;
    _nativeHandlerSet = true;
    _nativeChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pipToggle':
          pipToggleListener?.call();
          break;
        case 'volumeKey':
          final dir = call.arguments;
          if (dir is String) volumeKeyListener?.call(dir);
          break;
        case 'onAiProgress':
        case 'onAiSubtitleDone':
        case 'onAiSubtitleFailed':
          AiSubtitleRunner.handleNativeEvent(call);
          break;
        case 'onVoiceState':
          final s = call.arguments;
          if (s is String) onVoiceState?.call(s);
          break;
        case 'onVoiceRms':
          final r = (call.arguments as num?)?.toDouble();
          if (r != null) onVoiceRms?.call(r);
          break;
        case 'onVoicePartial':
          final p = call.arguments;
          if (p is String) onVoicePartial?.call(p);
          break;
        case 'onVoiceResult':
          final res = call.arguments;
          if (res is String) onVoiceResult?.call(res);
          break;
        case 'onVoiceError':
          final err = (call.arguments as num?)?.toInt();
          if (err != null) onVoiceError?.call(err);
          break;
      }
      return null;
    });
  }
}
