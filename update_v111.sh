#!/usr/bin/env bash
# =============================================================================
# Max Player — update_v111.sh
#
#  1) REMOVE "Sign in with Google" from Cloud Storage entirely: the sheet is
#     now import-only via Android's document picker. gdrive_service.dart and
#     the google_sign_in dependency are deleted; docs/tests updated.
#  2) Progress bar while importing: the native copy loop now reports
#     bytes-done/total (~10x/sec) over a new onPickProgress channel event and
#     the sheet shows a cancellable progress dialog (Cancel aborts the copy).
#  3) Import-only scope: picker stays video/*; the sheet's one job is
#     importing a video from Google Drive / Dropbox / other cloud storage.
#  4) Save-to-device now reuses the just-imported cache copy first (no second
#     cloud download).
#  5) Version -> 1.0.0+111.
#
# Run from the repo root:  cd ~/IdeaProjects/maxplayer && bash update_v111.sh
# =============================================================================
set -euo pipefail

if [ ! -f pubspec.yaml ] || [ ! -f lib/main.dart ]; then
  echo "ERROR: run this script from the Max Player repo root (~/IdeaProjects/maxplayer)"
  exit 1
fi

dirty="$(git status --porcelain 2>/dev/null | grep -vE '\?\? update_v[0-9]+\.sh' || true)"
if [ -n "$dirty" ]; then
  echo "WARNING: your local repo has uncommitted changes:"
  echo "$dirty"
  echo ""
  echo "These will be kept (this script only edits files in place), but they"
  echo "may be leftovers from another session. Type 'y' to continue, anything"
  echo "else to abort so you can review them first."
  read -r answer
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "Aborted."
    exit 1
  fi
fi

python3 - << 'PYEOF'
import sys, io

def patch(path, old, new, count=1):
    with io.open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    n = src.count(old)
    if n != count:
        print('FAIL: %s' % path)
        print('  anchor found %d time(s), expected %d.' % (n, count))
        sys.exit(1)
    src = src.replace(old, new)
    with io.open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print('patched: %s' % path)

def write(path, content):
    with io.open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('written: %s' % path)

# ============================================================================
# 1) MainActivity.kt — progress events, abortable copy, size query
# ============================================================================
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""    private var pendingSafPickResult: MethodChannel.Result? = null
""", r"""    private var pendingSafPickResult: MethodChannel.Result? = null

    // v111: flipped by the "abortPickCopy" call (progress dialog's Cancel);
    // the streaming copy loop polls it between chunks.
    @Volatile
    private var safCopyAborted = false
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""                "nowPlayingShow" -> {
""", r"""                "abortPickCopy" -> {
                    // v111: Cancel on the import progress dialog. The copy
                    // loop sees the flag, stops early and deletes the
                    // partial cache file.
                    safCopyAborted = true
                    result.success(true)
                }
                "nowPlayingShow" -> {
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""        if (pending == null) return
        val uri = if (resultCode == RESULT_OK) data?.data else null
""", r"""        if (pending == null) return
        safCopyAborted = false
        val uri = if (resultCode == RESULT_OK) data?.data else null
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""            if (resolved == null) {
                resolved = copyContentToCache(uri)
                cached = resolved != null
            }
""", r"""            if (resolved == null) {
                // v111: stream with progress events for the sheet's import
                // bar, honoring the dialog's Cancel via the abort flag.
                resolved = copyContentToCache(uri) { done, total ->
                    mainHandler.post {
                        channel?.invokeMethod(
                            "onPickProgress",
                            hashMapOf("done" to done, "total" to total)
                        )
                    }
                }
                cached = resolved != null
            }
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""    private fun copyContentToCache(uri: Uri): String? {
        return try {
            var name = queryDisplayName(uri) ?: "video.mp4"
            name = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            if (!name.contains('.')) name += ".mp4"
            val dir = File(cacheDir, "opened")
            if (dir.exists()) {
                dir.listFiles()?.forEach { it.delete() }
            } else {
                dir.mkdirs()
            }
            val out = File(dir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(out).use { output -> input.copyTo(output) }
            } ?: return null
            if (out.length() <= 0) {
                out.delete()
                null
            } else {
                out.absolutePath
            }
        } catch (e: Exception) {
            null
        }
    }
""", r"""    private fun copyContentToCache(uri: Uri): String? {
        return copyContentToCache(uri, null)
    }

    /**
     * v111: progress + abortable variant. [onProgress] gets
     * (bytesDone, bytesTotal) about every 100 ms while streaming; the total
     * is 0 when the provider does not report a size. Only this pick-driven
     * path honors the abort flag; the share-intent path above copies
     * uninterrupted.
     */
    private fun copyContentToCache(
        uri: Uri,
        onProgress: ((Long, Long) -> Unit)?
    ): String? {
        return try {
            var name = queryDisplayName(uri) ?: "video.mp4"
            name = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            if (!name.contains('.')) name += ".mp4"
            val dir = File(cacheDir, "opened")
            if (dir.exists()) {
                dir.listFiles()?.forEach { it.delete() }
            } else {
                dir.mkdirs()
            }
            val out = File(dir, name)
            val total = queryDocumentSize(uri)
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(out).use { output ->
                    if (onProgress == null) {
                        input.copyTo(output)
                    } else {
                        val buf = ByteArray(128 * 1024)
                        var doneBytes = 0L
                        var lastEmit = 0L
                        while (true) {
                            if (safCopyAborted) break
                            val n = input.read(buf)
                            if (n < 0) break
                            output.write(buf, 0, n)
                            doneBytes += n
                            val now = android.os.SystemClock.elapsedRealtime()
                            if (now - lastEmit >= 100) {
                                lastEmit = now
                                onProgress.invoke(doneBytes, total)
                            }
                        }
                        onProgress.invoke(doneBytes, total)
                    }
                }
            } ?: return null
            val aborted = onProgress != null && safCopyAborted
            if (aborted || out.length() <= 0) {
                out.delete()
                null
            } else {
                out.absolutePath
            }
        } catch (e: Exception) {
            null
        }
    }
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""    private fun queryDisplayName(uri: Uri): String? {
""", r"""    /** v111: provider-reported size of a document in bytes (0 = unknown). */
    private fun queryDocumentSize(uri: Uri): Long {
        return try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.SIZE), null, null, null
            )?.use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else 0L } ?: 0L
        } catch (e: Exception) {
            0L
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
""")

# Save now prefers the cache copy made during import (local, fast) and only
# falls back to the cloud grant when it is missing.
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""    /** Readable byte stream for a picked document: its SAF grant first,
     * then the on-device/cache copy as fallback. */
    private fun openDocumentInput(
        sourceUri: String?,
        cachePath: String?
    ): java.io.InputStream? {
        if (!sourceUri.isNullOrEmpty()) {
            try {
                contentResolver.openInputStream(Uri.parse(sourceUri))
                    ?.let { return it }
            } catch (_: Exception) {}
        }
        if (!cachePath.isNullOrEmpty()) {
            try {
                val f = File(cachePath)
                if (f.exists()) return FileInputStream(f)
            } catch (_: Exception) {}
        }
        return null
    }
""", r"""    /** Readable byte stream for a picked document: the on-device/cache copy
     * first (it was just imported - no second cloud download), then the SAF
     * grant as fallback. */
    private fun openDocumentInput(
        sourceUri: String?,
        cachePath: String?
    ): java.io.InputStream? {
        if (!cachePath.isNullOrEmpty()) {
            try {
                val f = File(cachePath)
                if (f.exists()) return FileInputStream(f)
            } catch (_: Exception) {}
        }
        if (!sourceUri.isNullOrEmpty()) {
            try {
                contentResolver.openInputStream(Uri.parse(sourceUri))
                    ?.let { return it }
            } catch (_: Exception) {}
        }
        return null
    }
""")

# ============================================================================
# 2) native_bridge.dart — progress listener + abort call
# ============================================================================
patch('lib/services/native_bridge.dart', r"""  /// v70: custom in-app microphone speech recognition callbacks.
  static void Function(String state)? _onVoiceState;
""", r"""  /// v111: progress while a picked cloud video is being copied into the
  /// app (bytesDone, bytesTotal; total 0 = provider reported no size). The
  /// Cloud Storage sheet installs a listener for the pick's duration.
  static void Function(int doneBytes, int totalBytes)? pickProgressListener;

  /// v70: custom in-app microphone speech recognition callbacks.
  static void Function(String state)? _onVoiceState;
""")

patch('lib/services/native_bridge.dart', r"""      case 'onAiSubtitleDone':
""", r"""      case 'onPickProgress':
        final m = call.arguments as Map?;
        if (m != null) {
          final d = (m['done'] as num?)?.toInt() ?? 0;
          final t = (m['total'] as num?)?.toInt() ?? 0;
          pickProgressListener?.call(d, t);
        }
        break;
      case 'onAiSubtitleDone':
""")

patch('lib/services/native_bridge.dart', r"""  // ---------------------------------------------------------------------------
  // v62 Phase 1: notifications
""", r"""  /// v111: aborts the in-flight cloud copy started by pickVideoDocument;
  /// the partial cache file is discarded natively. Safe to call anytime.
  static Future<void> abortPickCopy() async {
    try {
      await _channel.invokeMethod('abortPickCopy');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // v62 Phase 1: notifications
""")

# ============================================================================
# 3) cloud_storage_sheet.dart — FULL REWRITE: import-only, progress dialog.
#    (File fully read first; >70% of it was the removed sign-in flow, so a
#    rewrite is the smallest honest patch.)
# ============================================================================
write('lib/widgets/cloud_storage_sheet.dart', r"""import 'dart:async';

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// v111: Cloud Storage is IMPORT-ONLY now. "The Easy Way" taken all the way:
/// the Google Sign-In / Drive-API path is gone completely - Android's own
/// document picker lists every installed storage provider app (Google Drive,
/// Dropbox, OneDrive, ...) plus this device, videos only. The picked file is
/// copied into the app with a live progress bar; cloud imports can then be
/// kept permanently with "Save to device" (Movies/Max Player).
class CloudStorageSheet extends StatefulWidget {
  final Future<void> Function(String url, String title,
      [Map<String, String>? httpHeaders]) onPlay;

  const CloudStorageSheet({super.key, required this.onPlay});

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function(String url, String title,
            [Map<String, String>? httpHeaders])
        onPlay,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CloudStorageSheet(onPlay: onPlay),
    );
  }

  @override
  State<CloudStorageSheet> createState() => _CloudStorageSheetState();
}

class _CloudStorageSheetState extends State<CloudStorageSheet> {
  bool _importing = false;
  bool _progressVisible = false;
  final ValueNotifier<int> _progDone = ValueNotifier<int>(0);
  final ValueNotifier<int> _progTotal = ValueNotifier<int>(0);
  Timer? _progressTimer;

  @override
  void dispose() {
    _progressTimer?.cancel();
    NativeBridge.pickProgressListener = null;
    _progDone.dispose();
    _progTotal.dispose();
    super.dispose();
  }

  /// The one action of this sheet: open Android's picker, copy the chosen
  /// video in (progress bar), then play it or save a permanent copy.
  Future<void> _importVideo() async {
    if (_importing) return;
    setState(() => _importing = true);
    _progDone.value = 0;
    _progTotal.value = 0;
    // Copy progress streams in while a cloud file imports; a device file
    // resolves silently without any events.
    NativeBridge.pickProgressListener = (done, total) {
      if (!mounted) return;
      _progDone.value = done;
      _progTotal.value = total;
      if (!_progressVisible) _showImportProgress();
    };
    // Unknown-size copies emit their first event late; open the bar after a
    // grace delay so big imports never look frozen.
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted && _importing && !_progressVisible) _showImportProgress();
    });

    Map<String, dynamic>? picked;
    try {
      picked = await NativeBridge.pickVideoDocument();
    } finally {
      _progressTimer?.cancel();
      NativeBridge.pickProgressListener = null;
    }
    if (!mounted) return;
    if (_progressVisible) {
      // showDialog defaults to the root navigator; pop only that dialog,
      // not this bottom sheet.
      Navigator.of(context, rootNavigator: true).pop();
      _progressVisible = false;
    }
    setState(() => _importing = false);
    if (picked == null) return; // picker canceled, or copy aborted

    final messenger = ScaffoldMessenger.maybeOf(context);
    final path = picked['path']?.toString() ?? '';
    final name = picked['name']?.toString() ?? 'video';
    if (path.isEmpty) {
      _showInfoDialog(
        "Couldn't import that file",
        'The selected video could not be read. Try another one.',
      );
      return;
    }
    if (picked['cached'] != true) {
      // A plain local file: already on the device, import is unnecessary.
      _playPicked(path, name);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Already on this device - opening it'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1b1b24),
        title: const Text('Play or keep?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          '"$name" came from a cloud app and is stored only as a temporary '
          'copy. Keep a permanent copy on this device?',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('play'),
            child: const Text('Play once'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: themeState.accent,
              foregroundColor: themeState.onAccent,
            ),
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('Save to device'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'play') {
      _playPicked(path, name);
      return;
    }
    final saved = await NativeBridge.savePickedVideoToDevice(
      sourceUri: picked['sourceUri']?.toString(),
      cachePath: path,
      name: name,
    );
    if (!mounted) return;
    if (saved == null) {
      _showInfoDialog(
        "Couldn't save",
        'The copy could not be written to Movies/Max Player. Playing the '
            'temporary copy is still possible.',
      );
      return;
    }
    final savedPath = saved['path']?.toString() ?? '';
    final location = saved['location']?.toString() ?? 'Movies/Max Player';
    _playPicked(savedPath.isNotEmpty ? savedPath : path, name);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Saved to $location'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _playPicked(String path, String name) {
    Navigator.of(context).pop();
    // Same onPlay pipeline other local files use: libmpv opens local
    // absolute paths exactly like stream URLs.
    widget.onPlay(path, name);
  }

  void _showImportProgress() {
    _progressVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1b1b24),
        title: const Text('Importing video…',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: AnimatedBuilder(
          animation: Listenable.merge([_progDone, _progTotal]),
          builder: (_, __) {
            final done = _progDone.value;
            final total = _progTotal.value;
            final double? pct =
                total > 0 ? (done / total).clamp(0.0, 1.0) : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 10),
                Text(
                  total > 0
                      ? '${formatFileSize(done)} of ${formatFileSize(total)}'
                      : '${formatFileSize(done)} copied…',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const Text(
                  'The video is being copied from the storage app.',
                  style: TextStyle(color: Colors.white38, fontSize: 11.5),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              NativeBridge.abortPickCopy();
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).then((_) => _progressVisible = false);
  }

  void _showInfoDialog(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1b1b24),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          body,
          style:
              const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_download_outlined, color: accent, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Import from cloud storage',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    child: Icon(Icons.drive_folder_upload_outlined,
                        size: 38, color: accent),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Import a video',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Android's file picker opens with Google Drive, Dropbox, "
                    'OneDrive or any storage app you use - videos only. The '
                    'picked file is copied into Max Player with a live '
                    'progress bar; keep it forever with Save to device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white54, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: themeState.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.file_open_outlined),
                      label: Text(
                        _importing
                            ? 'Importing…'
                            : 'Choose a video to import',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      onPressed: _importing ? null : _importVideo,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No sign-in at all - the picker hands Max Player one '
                    'file at a time, read-only.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
""")

# ============================================================================
# 4) pubspec.yaml — drop google_sign_in, bump version
# ============================================================================
patch('pubspec.yaml', r"""  # v106: native Google Sign-In for Drive (no google-services.json - the
  # SHA-1-registered OAuth client resolves via Play Services at runtime).
  google_sign_in: ^7.2.0
""", r"""  # v111: Google Sign-In + Drive API REMOVED (developer request) - cloud
  # import runs 100% through Android's document picker, no OAuth at all.
""")

patch('pubspec.yaml', r"""version: 1.0.0+110
""", r"""version: 1.0.0+111
""")

# ============================================================================
# 5) user_manual_sheet.dart — one import entry replaces both Drive entries
# ============================================================================
patch('lib/widgets/user_manual_sheet.dart', r"""  _Item(
    Icons.cloud_done_outlined,
    'Google Drive sign-in',
    'Library → Cloud Storage → Sign in with Google: your Drive videos list '
        'up, tap any video to stream it in Max Player. Sign in once - the '
        'session is quietly reused on later opens. Disconnect anytime from '
        'the same sheet.',
  ),
  _Item(
    Icons.folder_open_outlined,
    'Select video (no sign-in)',
    'Library → Cloud Storage → Select video: Android\'s own file picker '
        'opens with this device, your Google Drive app, and any other '
        'storage app side by side - no Google account needed. Cloud videos '
        'are copied into Max Player first (large ones take a moment); after '
        'picking, choose "Save to device" to keep a permanent copy in '
        'Movies/Max Player.',
  ),
""", r"""  _Item(
    Icons.cloud_download_outlined,
    'Import from cloud storage',
    'Library → Cloud Storage → Choose a video to import: Android\'s own '
        'file picker opens with Google Drive, Dropbox, OneDrive or any '
        'storage app - no sign-in at all. The video copies in with a live '
        'progress bar (big files on slow networks take a while; Cancel '
        'stops the copy); then choose "Save to device" for a permanent '
        'copy in Movies/Max Player.',
  ),
""")

# ============================================================================
# 6) lib/utils/privacy_policy.dart — one import section, no OAuth
# ============================================================================
patch('lib/utils/privacy_policy.dart', r"""    '- No Max Player accounts and no device identifiers collected (the '
    'optional Google Drive sign-in below is strictly between you and '
    'Google).\n'
""", r"""    '- No Max Player accounts and no device identifiers collected (cloud '
    'imports go through Android\'s file picker - strictly between you and '
    'the storage app).\n'
""")

patch('lib/utils/privacy_policy.dart', r"""    '- Internet: only for features you trigger yourself - TMDB movie '
    'discovery, stream URLs you open, and optional one-time AI subtitle model '
    'download. Nothing personal about you is sent anywhere.\n'
""", r"""    '- Internet: only for features you trigger yourself - TMDB movie '
    'discovery, stream URLs you open, cloud videos you import, and optional '
    'one-time AI subtitle model download. Nothing personal about you is sent '
    'anywhere.\n'
""")

patch('lib/utils/privacy_policy.dart', r"""    'GOOGLE DRIVE (OPTIONAL)\n'
    '\n'
    'Tapping "Sign in with Google" in Library - Cloud Storage uses Google '
    'OAuth on your device to list the video files in your own Drive and '
    'stream the ones you tap. The app requests read-only access; file '
    'names, thumbnails and streams travel only between your phone and '
    'Google, and the access token never leaves your device. Sign in once - '
    'the session is quietly reused. Disconnect anytime from the same '
    'sheet, or revoke access from your Google Account third-party access '
    'page.\n'
    '\n'
    'SELECT VIDEO (ANDROID FILE PICKER)\n'
    '\n'
    'Library - Cloud Storage also offers "Select video (no sign-in)": it\n'
    'opens Android\'s built-in file picker, which lists this device and\n'
    'the storage apps installed on it - including your Google Drive app.\n'
    'No account, password, or Google sign-in is involved, and the app\n'
    'never sees your Drive file list: the system hands Max Player a\n'
    'one-time, read-only grant for just the file you choose. A cloud\n'
    'file\'s bytes are streamed once into the app\'s private cache purely\n'
    'so it can play; the copy is discarded when replaced or cleared.\n'
    'Tapping "Save to device" stores a permanent copy in\n'
    'Movies/Max Player - nothing is uploaded anywhere.\n'
    '\n'
""", r"""    'CLOUD STORAGE IMPORT (ANDROID FILE PICKER)\n'
    '\n'
    'Library - Cloud Storage opens Android\'s built-in file picker, which\n'
    'lists the storage apps installed on your device - your Google Drive\n'
    'app, Dropbox, OneDrive, and others. There is no sign-in, account, or\n'
    'OAuth of any kind inside Max Player, and the app never sees your\n'
    'cloud file list: the system hands Max Player a one-time, read-only\n'
    'grant for just the one video you choose. While the file imports, a\n'
    'progress bar shows the copy in real time. The imported bytes live in\n'
    'the app\'s private cache purely so the video can play; the copy is\n'
    'discarded when replaced or cleared. Tapping "Save to device" stores\n'
    'a permanent copy in Movies/Max Player - nothing is uploaded\n'
    'anywhere.\n'
    '\n'
""")

# ============================================================================
# 7) PRIVACY_POLICY.md — same rewrite
# ============================================================================
patch('PRIVACY_POLICY.md', r"""- No Max Player accounts and no device identifiers collected (the optional Google Drive sign-in below is strictly between you and Google)
""", r"""- No Max Player accounts and no device identifiers collected (cloud video imports go through Android's own file picker — strictly between you and the storage app)
""")

patch('PRIVACY_POLICY.md', r"""| **Internet** | Only for things you trigger yourself: legal TMDB movie discovery, stream URLs you open, and optional one-time AI subtitle model download | Nothing personal about you goes out |
""", r"""| **Internet** | Only for things you trigger yourself: legal TMDB movie discovery, stream URLs you open, cloud videos you import, and optional one-time AI subtitle model download | Nothing personal about you goes out |
""")

patch('PRIVACY_POLICY.md', r"""## Google Drive (optional)
Tapping "Sign in with Google" in Library → Cloud Storage uses Google OAuth on your device to list the video files in your own Drive and stream the ones you tap. The app requests read-only access; file names, thumbnails and streams travel only between your phone and Google, and the access token never leaves your device. Sign in once — the session is quietly reused. Disconnect anytime from the same sheet, or revoke access from your Google Account's third-party access page.

### The system file picker ("Select video")
Library → Cloud Storage also offers **Select video (no sign-in)**: it opens Android's built-in file picker, which lists this device **and** the storage apps installed on it — including your Google Drive app. No account, password, or Google sign-in is involved, and the app never sees your Drive file list; the system hands Max Player a one-time, read-only grant for just the file you choose. If the file lives in a cloud app, its bytes are streamed once into the app's private cache purely so it can be played, and the copy is discarded when replaced or cleared. Tapping **Save to device** stores a permanent copy in *Movies/Max Player* — nothing is uploaded anywhere; the bytes travel only from the provider app (e.g. Google) to your own phone, exactly like a download in your browser.
""", r"""## Cloud storage — Android's file picker
Library → Cloud Storage opens **Android's built-in file picker**, which lists the storage apps installed on your device — your Google Drive app, Dropbox, OneDrive, and others. There is no sign-in, account, or OAuth of any kind inside Max Player, and the app never sees your cloud file list; the system hands Max Player a one-time, read-only grant for just the one video file you choose. While the file imports, a progress bar shows the copy in real time. The imported bytes live in the app's private cache purely so the video can play, and the copy is discarded when replaced or cleared. Tapping **Save to device** stores a permanent copy in *Movies/Max Player* — nothing is uploaded anywhere; the bytes travel only from the storage app (e.g. Google) to your own phone, exactly like a download in your browser.
""")

patch('PRIVACY_POLICY.md', r"""- **Data sent off the device:** only what you trigger — Drive file listings and streams (or a picked cloud file's bytes, via the provider app) travel between your phone and Google while you use Cloud Storage or the system file picker; everything else (AI subtitles, history, bookmarks, settings) is local-only
""", r"""- **Data sent off the device:** only what you trigger — a picked cloud video's bytes travel from the storage app (e.g. Google Drive) to your phone while you import it; everything else (AI subtitles, history, bookmarks, settings) is local-only
""")

# ============================================================================
# 8) docs/privacy.html — same rewrite
# ============================================================================
patch('docs/privacy.html', r"""  <h2>Google Drive (optional)</h2>
  <p>Tapping "Sign in with Google" in Library - Cloud Storage uses Google
  OAuth on your device to list the video files in your own Drive and stream
  the ones you tap. The app requests read-only access; file names, thumbnails
  and streams travel only between your phone and Google, and the access token
  never leaves your device. Sign in once - the session is quietly reused.
  Disconnect anytime from the same sheet, or revoke access from your Google
  Account third-party access page.</p>
  <h2>The system file picker ("Select video")</h2>
  <p>Library - Cloud Storage also offers "Select video (no sign-in)": it
  opens Android's built-in file picker, which lists this device and the
  storage apps installed on it - including your Google Drive app. No
  account or Google sign-in is involved and the app never sees your Drive
  file list; the system hands Max Player a one-time, read-only grant for
  just the file you choose. A cloud file is streamed once into the app's
  private cache purely so it can play, and the copy is discarded when
  replaced or cleared. "Save to device" stores a permanent copy in
  Movies/Max Player. Nothing is uploaded anywhere.</p>
""", r"""  <h2>Cloud storage - Android's file picker</h2>
  <p>Library - Cloud Storage opens Android's built-in file picker, which
  lists the storage apps installed on your device - your Google Drive app,
  Dropbox, OneDrive, and others. There is no sign-in, account, or OAuth of
  any kind inside Max Player, and the app never sees your cloud file list;
  the system hands Max Player a one-time, read-only grant for just the one
  video you choose. While the file imports, a progress bar shows the copy
  in real time. The imported bytes live in the app's private cache purely
  so the video can play, and the copy is discarded when replaced or
  cleared. "Save to device" stores a permanent copy in Movies/Max Player.
  Nothing is uploaded anywhere.</p>
""")

# ============================================================================
# 9) Terms — Drive section becomes picker-only
# ============================================================================
patch('TERMS_OF_SERVICE.md', r"""## Google Drive
Cloud Storage uses Google OAuth on your device with read-only access to list
and stream your own Drive videos; alternatively, "Select video" uses
Android's built-in file picker (no sign-in) to open files offered by the
Drive app on your device. File names, thumbnails and streams travel only
between your phone and Google. Drive features are additionally subject to
Google's Terms of Service and API policies.
""", r"""## Cloud storage
Cloud Storage opens Android's built-in file picker: videos offered by the
storage apps on your device (Google Drive, Dropbox, and others) are copied
in, one file at a time, with read-only access granted to just the file you
pick. There is no sign-in or OAuth inside the app. Connected services
remain subject to their own terms; Drive files remain subject to Google's
Terms of Service.
""")

patch('docs/terms.html', r"""  <h2>Google Drive</h2>
  <p>Cloud Storage uses Google OAuth on your device with read-only access;
  alternatively, "Select video" opens Android's built-in file picker (no
  sign-in) for files offered by the Drive app on your device. Drive
  features are additionally subject to Google's Terms of Service and API
  policies.</p>
""", r"""  <h2>Cloud storage</h2>
  <p>Cloud Storage opens Android's built-in file picker: videos offered by
  the storage apps on your device (Google Drive, Dropbox, and others) are
  copied in, one file at a time, with read-only access granted to just the
  file you pick. There is no sign-in or OAuth inside the app. Connected
  services remain subject to their own terms; Drive files remain subject
  to Google's Terms of Service.</p>
""")

# ============================================================================
# 10) docs/index.html — feature line becomes import
# ============================================================================
patch('docs/index.html', r"""playback speed up to 3x, karaoke word highlight, dialogue boost, picture
  enhancement, private folder, network (SMB) playback and optional Google
  Drive streaming. Local-first: your files never leave your phone unless you
  explicitly stream them from your own Drive.
  Or use Select video: Android's file picker opens videos straight from this
  device and your installed storage apps (Google Drive included) - no
  sign-in, with the option to save a copy to device storage.</p>
""", r"""playback speed up to 3x, karaoke word highlight, dialogue boost, picture
  enhancement, private folder, network (SMB) playback, and cloud imports.
  Import videos from Google Drive, Dropbox and other storage apps through
  Android's file picker - no sign-in, with a live progress bar and an
  option to save a copy to device storage. Local-first: your files never
  leave your phone unless you explicitly open or import them from a
  storage app.</p>
""")

# ============================================================================
# 11) test/widget_test.dart — retarget historical pins + v111 guards
# ============================================================================
patch('test/widget_test.dart', r"""    test('v106 Google Sign-In powers Drive', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub, contains('google_sign_in'));
      final gradle =
          File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('minSdk = 24'));
      final svc =
          File('lib/services/gdrive_service.dart').readAsStringSync();
      for (final k in [
        'GoogleSignIn.instance.initialize',
        'serverClientId',
        'drive.readonly',
        'authorizationHeaders',
        'attemptLightweightAuthentication',
        'authenticate()',
        'disconnect()',
        'alt=media',
      ]) {
        expect(svc, contains(k));
      }
      // No pasted tokens, no shipped API key.
      expect(svc.contains('AIza'), isFalse);
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet, contains('Sign in with Google'));
      expect(sheet.contains('Access Key'), isFalse);
      expect(sheet.contains('gdrive.access_token'), isFalse);
""", r"""    test('v106 Google Sign-In powers Drive', () {
      // v111: the Google Sign-In / Drive-API path was REMOVED (developer
      // request: "remove sign in with google from cloud storage"); import
      // runs fully through the SAF picker. These pins flipped to absence.
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub.contains('google_sign_in'), isFalse);
      expect(File('lib/services/gdrive_service.dart').existsSync(), isFalse);
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet.contains('Sign in with Google'), isFalse);
      expect(sheet.contains('GDriveAuth'), isFalse);
      expect(sheet.contains('google_sign_in'), isFalse);
      expect(sheet.contains('Access Key'), isFalse);
      expect(sheet.contains('gdrive.access_token'), isFalse);
""")

patch('test/widget_test.dart', r"""      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet, contains('e.description'));
    });
""", r"""      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      // v111: sign-in error reporting is gone with the sign-in screen.
      expect(sheet.contains('GoogleSignInException'), isFalse);
    });
""")

patch('test/widget_test.dart', r"""      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet, contains('email == null || email.isEmpty'));
      expect(sheet, contains('Sign-In button'));
    });
""", r"""      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      // v111: the import-only sheet has no sessions left to gate.
      expect(sheet, contains('_importVideo'));
      expect(sheet.contains('email == null || email.isEmpty'), isFalse);
    });
""")

patch('test/widget_test.dart', r"""      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      // Silent auth still gated on a past sign-in, but a dead grant no
      // longer wipes the email - the session stays sticky.
      expect(sheet, contains('email == null || email.isEmpty'));
      expect(sheet.contains('stop trying on future opens'), isFalse);
""", r"""      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      // v111: picker-only - none of the sticky sign-in machinery remains.
      expect(sheet.contains('email == null || email.isEmpty'), isFalse);
      expect(sheet.contains('stop trying on future opens'), isFalse);
""")

patch('test/widget_test.dart', r"""      for (final k in [
        'on/off ',
        'Google Drive sign-in',
      ]) {
        expect(manual, contains(k));
      }
      final svc =
          File('lib/services/gdrive_service.dart').readAsStringSync();
      expect(svc, contains('recall()'));
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet, contains('GDriveAuth.remember'));
""", r"""      for (final k in [
        'on/off ',
        'Import from cloud storage',
      ]) {
        expect(manual, contains(k));
      }
      // v111: gdrive_service.dart was deleted along with the sign-in flow.
      expect(File('lib/services/gdrive_service.dart').existsSync(), isFalse);
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet.contains('GDriveAuth.remember'), isFalse);
""")

patch('test/widget_test.dart', r"""      // Kept: Drive manual entry + sticky Drive session after reopen.
      expect(manual, contains('Google Drive sign-in'));
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet, contains('GDriveAuth.recall()'));
      expect(sheet, contains('GDriveAuth.remember'));
      final svc =
          File('lib/services/gdrive_service.dart').readAsStringSync();
      expect(svc, contains('static Map<String, String>? _memHeaders'));
    });
""", r"""      // v111: sign-in manual entry replaced by the import-only entry.
      expect(manual.contains('Google Drive sign-in'), isFalse);
      expect(manual, contains('Import from cloud storage'));
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet.contains('GDriveAuth.recall()'), isFalse);
      expect(sheet.contains('GDriveAuth.remember'), isFalse);
      expect(File('lib/services/gdrive_service.dart').existsSync(), isFalse);
    });
""")

patch('test/widget_test.dart', r"""        final pub = File('pubspec.yaml').readAsStringSync();
        expect(pub, contains('1.0.0+110'));
""", r"""        final pub = File('pubspec.yaml').readAsStringSync();
        expect(pub, contains('version: 1.0.0+'));
""")

patch('test/widget_test.dart', r"""        expect(sheet, contains('Select video (no sign-in)'));
        expect(sheet, contains('_pickViaAndroidPicker'));
        expect(sheet, contains('Save to device'));
""", r"""        expect(sheet, contains('Import from cloud storage'));
        expect(sheet, contains('_importVideo'));
        expect(sheet, contains('Save to device'));
""")

patch('test/widget_test.dart', r"""        expect(manual, contains('Select video (no sign-in)'));
        expect(manual, contains('lock screen'));
        expect(manual, contains('Google Drive sign-in'));
""", r"""        expect(manual, contains('Import from cloud storage'));
        expect(manual, contains('lock screen'));
        expect(manual.contains('Google Drive sign-in'), isFalse);
""")

# v110 docs pins: headings were consolidated in v111; retarget the names.
patch('test/widget_test.dart', r"""        expect(md, contains('5 September 2026'));
        expect(md, contains('system file picker'));
        expect(md, contains('Movies/Max Player'));
        final inApp =
            File('lib/utils/privacy_policy.dart').readAsStringSync();
        expect(inApp, contains('SELECT VIDEO (ANDROID FILE PICKER)'));
""", r"""        expect(md, contains('5 September 2026'));
        expect(md, contains('file picker'));
        expect(md, contains('Movies/Max Player'));
        final inApp =
            File('lib/utils/privacy_policy.dart').readAsStringSync();
        expect(inApp, contains('CLOUD STORAGE IMPORT (ANDROID FILE PICKER)'));
""")

patch('test/widget_test.dart', r"""        expect(File('docs/privacy.html').readAsStringSync(),
            contains('file picker'));
      });
    });
  });
}
""", r"""        expect(File('docs/privacy.html').readAsStringSync(),
            contains('file picker'));
      });
    });

    group('v111 import-only Cloud Storage with copy progress', () {
      test('sheet imports via picker with a cancellable progress bar', () {
        final sheet =
            File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
        expect(sheet, contains('Import from cloud storage'));
        expect(sheet, contains('_importVideo'));
        expect(sheet, contains('LinearProgressIndicator'));
        expect(sheet, contains('pickProgressListener'));
        expect(sheet, contains('abortPickCopy'));
        expect(sheet, contains('Save to device'));
        expect(sheet.contains('Sign in with Google'), isFalse);
        final bridge =
            File('lib/services/native_bridge.dart').readAsStringSync();
        expect(bridge, contains('pickProgressListener'));
        expect(bridge, contains("case 'onPickProgress'"));
        expect(bridge, contains('abortPickCopy'));
        final mainKt = File(
                'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt')
            .readAsStringSync();
        expect(mainKt, contains('onPickProgress'));
        expect(mainKt, contains('queryDocumentSize'));
        expect(mainKt, contains('safCopyAborted'));
        expect(mainKt, contains('"abortPickCopy"'));
      });

      test('sign-in docs are gone; import docs stay', () {
        final md = File('PRIVACY_POLICY.md').readAsStringSync();
        expect(md.contains('Sign in with Google'), isFalse);
        expect(md, contains('file picker'));
        expect(md, contains('Google Drive'));
        final inApp =
            File('lib/utils/privacy_policy.dart').readAsStringSync();
        expect(inApp.contains('Sign in with Google'), isFalse);
        expect(inApp, contains('CLOUD STORAGE IMPORT'));
        final terms = File('TERMS_OF_SERVICE.md').readAsStringSync();
        expect(terms.contains('Google OAuth'), isFalse);
        expect(terms, contains('file picker'));
        final manual =
            File('lib/widgets/user_manual_sheet.dart').readAsStringSync();
        expect(manual, contains('Import from cloud storage'));
        expect(manual.contains('Google Drive sign-in'), isFalse);
      });
    });
  });
}
""")

print('')
print('All v111 patches applied OK.')
PYEOF

# Full removal of the deleted Drive service (test pins assert it is gone).
rm -f lib/services/gdrive_service.dart
echo "deleted: lib/services/gdrive_service.dart"

echo ""
echo "======================================================================"
echo " v111 patched. Next steps:"
echo "   flutter analyze"
echo "   flutter test"
echo " Then commit & push (see chat instructions for the exact commands)."
echo "======================================================================"
