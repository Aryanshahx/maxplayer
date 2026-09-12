import 'package:flutter/services.dart';

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

  static const MethodChannel _channel = MethodChannel('maxplayer/storage');

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
}
