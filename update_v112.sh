#!/usr/bin/env bash
# ======================================================================
# v112 - Play policy: remove MANAGE_EXTERNAL_STORAGE, scoped replacements
# Run from the maxplayer repo root:  bash update_v112.sh
# ======================================================================
set -euo pipefail
cd "$(dirname "$0")"

python3 <<'PYEOF'
import sys

def patch(path, old, new):
    with open(path, 'r') as f:
        data = f.read()
    count = data.count(old)
    if count != 1:
        print(f'FAIL: {path}: expected 1 match, found {count}')
        print('---') ; print(old[:400]) ; print('---')
        sys.exit(1)
    with open(path, 'w') as f:
        f.write(data.replace(old, new, 1))
    print(f'OK: {path}')

# ---------------------------------------------------------------
# 1. Manifest: drop the permission, leave a policy breadcrumb.
# ---------------------------------------------------------------
patch('android/app/src/main/AndroidManifest.xml', r"""    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
        tools:ignore="ScopedStorage" />
""", r"""    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <!-- v112: All-files access removed. Play rejected it as non-core; the
         library scans via MediaStore, saving uses MediaStore inserts, and
         vault deletions use the system per-file consent dialog. -->
""")

# ---------------------------------------------------------------
# 2. MainActivity.kt - imports for the new scoped helpers.
# ---------------------------------------------------------------
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
""", r"""import android.app.PictureInPictureParams
import android.app.RecoverableSecurityException
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
""")

# 2b. Request code for the delete-consent round trip.
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""        private const val REQ_SAF_PICK = 47
""", r"""        private const val REQ_SAF_PICK = 47
        private const val REQ_MEDIA_DELETE = 48
""")

# 2c. Pending result state for the consent dialog.
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""    @Volatile
    private var safCopyAborted = false

    private fun startInAppSpeech(result: MethodChannel.Result) {
""", r"""    @Volatile
    private var safCopyAborted = false

    // v112: system delete-consent round trip (vault hide flow). API 30+
    // needs no retry list (createDeleteRequest handles the whole batch);
    // API 29 consents per file, so remember what is left to delete.
    private var pendingMediaDeleteResult: MethodChannel.Result? = null
    private var pendingMediaDeletePaths: ArrayList<String>? = null

    private fun startInAppSpeech(result: MethodChannel.Result) {
""")

# 2d. Method handlers: MediaStore video listing + delete consent.
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""                "abortPickCopy" -> {
                    // v111: Cancel on the import progress dialog. The copy
                    // loop sees the flag, stops early and deletes the
                    // partial cache file.
                    safCopyAborted = true
                    result.success(true)
                }
                "nowPlayingShow" -> {
""", r"""                "abortPickCopy" -> {
                    // v111: Cancel on the import progress dialog. The copy
                    // loop sees the flag, stops early and deletes the
                    // partial cache file.
                    safCopyAborted = true
                    result.success(true)
                }
                "listMediaStoreVideos" -> {
                    executor.execute {
                        val paths = queryMediaStoreVideoPaths()
                        mainHandler.post { result.success(paths) }
                    }
                }
                "requestMediaDelete" -> {
                    val paths = call.argument<ArrayList<String>>("paths")
                        ?: arrayListOf()
                    if (paths.isEmpty()) {
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        // API 30+: one batch system dialog for every file.
                        val uris = ArrayList<Uri>()
                        for (path in paths) {
                            resolveVideoUri(path)?.let { uris.add(it) }
                        }
                        if (uris.isEmpty()) {
                            result.success(false)
                        } else {
                            try {
                                val pi = MediaStore.createDeleteRequest(
                                    contentResolver, uris
                                )
                                pendingMediaDeleteResult = result
                                startIntentSenderForResult(
                                    pi.intentSender, REQ_MEDIA_DELETE,
                                    null, 0, 0, 0
                                )
                            } catch (_: Exception) {
                                pendingMediaDeleteResult = null
                                result.success(false)
                            }
                        }
                    } else {
                        // API 29: direct delete; the user's consent arrives
                        // wrapped in a RecoverableSecurityException.
                        executor.execute {
                            var consent: RecoverableSecurityException? = null
                            val remaining = ArrayList<String>()
                            for (path in paths) {
                                val uri = resolveVideoUri(path) ?: continue
                                try {
                                    contentResolver.delete(uri, null, null)
                                } catch (e: RecoverableSecurityException) {
                                    if (consent == null) consent = e
                                    remaining.add(path)
                                } catch (_: Exception) {
                                    remaining.add(path)
                                }
                            }
                            val request = consent
                            mainHandler.post {
                                when {
                                    remaining.isEmpty() -> result.success(true)
                                    request == null -> result.success(false)
                                    else -> {
                                        try {
                                            pendingMediaDeleteResult = result
                                            pendingMediaDeletePaths = remaining
                                            startIntentSenderForResult(
                                                request.userAction.actionIntent
                                                    .intentSender,
                                                REQ_MEDIA_DELETE,
                                                null, 0, 0, 0
                                            )
                                        } catch (_: Exception) {
                                            pendingMediaDeleteResult = null
                                            pendingMediaDeletePaths = null
                                            result.success(false)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                "nowPlayingShow" -> {
""")

# 2e. Route the result in onActivityResult.
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""        } else if (requestCode == REQ_CONFIRM_CREDENTIAL) {
            finishCredentialPrompt(resultCode == RESULT_OK)
        } else if (requestCode == REQ_VOICE_SEARCH) {
""", r"""        } else if (requestCode == REQ_CONFIRM_CREDENTIAL) {
            finishCredentialPrompt(resultCode == RESULT_OK)
        } else if (requestCode == REQ_MEDIA_DELETE) {
            finishMediaDelete(resultCode == RESULT_OK)
        } else if (requestCode == REQ_VOICE_SEARCH) {
""")

# 2f. Helpers (inserted just before saveDocumentToDevice).
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""    /**
     * v110: permanent copy of a picked cloud video into
     * Movies/Max Player. API 29+ goes through MediaStore (no permission
     * needed for our own insert); older versions write the public Movies
     * directory directly (we hold legacy storage permission there) and ping
     * the media scanner so gallery apps see it at once.
     */
""", r"""    /**
     * v112: real paths of every MediaStore-indexed video across all shared
     * volumes (internal + SD card). Replaces the v40 filesystem walk that
     * needed all-files access, which Play rejected as non-core.
     */
    private fun queryMediaStoreVideoPaths(): ArrayList<String> {
        val out = ArrayList<String>()
        try {
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            else
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            contentResolver.query(
                collection, arrayOf(MediaStore.MediaColumns.DATA),
                null, null, null
            )?.use { c ->
                val col = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                while (c.moveToNext()) {
                    val path = c.getString(col)
                    if (!path.isNullOrEmpty()) out.add(path)
                }
            }
        } catch (_: Exception) {}
        return out
    }

    /** v112: content:// Uri of an indexed video by its filesystem path. */
    private fun resolveVideoUri(path: String): Uri? {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        else
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        return try {
            contentResolver.query(
                collection,
                arrayOf(MediaStore.Video.Media._ID),
                MediaStore.MediaColumns.DATA + "=?",
                arrayOf(path),
                null
            )?.use { c ->
                if (c.moveToFirst())
                    ContentUris.withAppendedId(collection, c.getLong(0))
                else null
            }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * v112: completes the delete-consent flow (REQ_MEDIA_DELETE). API 30+
     * deleted everything inside createDeleteRequest itself; API 29 granted
     * one file's consent, so the pending list is retried once here.
     */
    private fun finishMediaDelete(granted: Boolean) {
        val pending = pendingMediaDeleteResult
        val paths = pendingMediaDeletePaths
        pendingMediaDeleteResult = null
        pendingMediaDeletePaths = null
        if (pending == null) return
        if (!granted || Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ||
            paths.isNullOrEmpty()
        ) {
            pending.success(granted)
            return
        }
        executor.execute {
            var ok = true
            for (path in paths) {
                val uri = resolveVideoUri(path) ?: continue
                try {
                    contentResolver.delete(uri, null, null)
                } catch (_: Exception) {
                    ok = false
                }
            }
            mainHandler.post { pending.success(ok) }
        }
    }

    /**
     * v110: permanent copy of a picked cloud video into
     * Movies/Max Player. API 29+ goes through MediaStore (no permission
     * needed for our own insert); older versions write the public Movies
     * directory directly (we hold legacy storage permission there) and ping
     * the media scanner so gallery apps see it at once.
     * v112: destination folder is a parameter now (Private folder's unhide
     * exports to plain Movies/).
     */
""")

# 2g. saveDocumentToDevice: parameterise the destination folder.
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""                    val rawName = call.argument<String>("name") ?: "video"
                    if (sourceUri.isNullOrEmpty() && cachePath.isNullOrEmpty()) {
""", r"""                    val rawName = call.argument<String>("name") ?: "video"
                    val relPath = call.argument<String>("relativePath")
                        ?: "Movies/Max Player"
                    if (sourceUri.isNullOrEmpty() && cachePath.isNullOrEmpty()) {
""")
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""                            val saved = saveDocumentToDevice(sourceUri, cachePath, rawName)
""", r"""                            val saved = saveDocumentToDevice(sourceUri, cachePath, rawName, relPath)
""")
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""    private fun saveDocumentToDevice(
        sourceUri: String?,
        cachePath: String?,
        rawName: String
    ): HashMap<String, Any?>? {
""", r"""    private fun saveDocumentToDevice(
        sourceUri: String?,
        cachePath: String?,
        rawName: String,
        relativePath: String
    ): HashMap<String, Any?>? {
""")
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""                    put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/Max Player")
""", r"""                    put(MediaStore.Video.Media.RELATIVE_PATH, relativePath)
""")
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""                out["path"] = queryDataColumn(outUri)
                out["location"] = "Movies/Max Player/$name"
""", r"""                out["path"] = queryDataColumn(outUri)
                out["location"] = "$relativePath/$name"
""")

# ---------------------------------------------------------------
# 3. native_bridge.dart - the three new/adjusted calls.
# ---------------------------------------------------------------
patch('lib/services/native_bridge.dart', r"""  static Future<Map<String, dynamic>?> savePickedVideoToDevice({
    String? sourceUri,
    String? cachePath,
    required String name,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'saveDocumentToDevice',
        {'sourceUri': sourceUri, 'cachePath': cachePath, 'name': name},
      );
""", r"""  static Future<Map<String, dynamic>?> savePickedVideoToDevice({
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
""")

patch('lib/services/native_bridge.dart', r"""  /// v111: aborts the in-flight cloud copy started by pickVideoDocument;
""", r"""  /// v112: real filesystem paths of every MediaStore-indexed video across
  /// all shared volumes (internal + SD card). Replaces the filesystem walk
  /// that needed all-files access. Empty when the media read permission is
  /// missing or nothing is indexed yet.
  static Future<List<String>> listMediaStoreVideos() async {
    try {
      final res =
          await _channel.invokeMethod<List<Object?>>('listMediaStoreVideos');
      if (res == null) return const [];
      return [for (final e in res) if (e != null) e.toString()];
    } catch (_) {
      return const [];
    }
  }

  /// v112: the system consent dialog to delete shared-storage videos
  /// (Private folder's hide flow, called once the vault copy is safe).
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

  /// v111: aborts the in-flight cloud copy started by pickVideoDocument;
""")

# ---------------------------------------------------------------
# 4. storage_permission.dart - full rewrite (scoped-only asks).
# ---------------------------------------------------------------
STORAGE = r'''import 'package:permission_handler/permission_handler.dart';

import '../services/native_bridge.dart';

/// v112 (Play policy): all-files access (MANAGE_EXTERNAL_STORAGE) is GONE -
/// Google rejected it as non-core, and scoped storage covers the app's real
/// needs. This one helper still asks for media-read access with the
/// version-correct permission set:
///
/// Android 13+ (API 33+): videos/photos/audio are separate runtime grants
/// that gate MediaStore reads.
/// Android 10-12 (API 29-32): READ_EXTERNAL_STORAGE grants media reads.
/// Android 9 and older: the classic Storage permission.
///
/// Returns true when reading videos is allowed (calling request() when
/// already granted resolves granted without showing any dialog). v40 note:
/// the Private folder's "+" flow and the library's long-press "hide" flow
/// route through here too - keep it that way.
Future<bool> ensureStorageAccess() async {
  final sdk = await NativeBridge.sdkInt();
  PermissionStatus status;
  try {
    if (sdk >= 33) {
      status = await Permission.videos.request();
      // v106-fix: Android 13+ lists Photos / Music separately in App info -
      // ask alongside so nothing reads as "Not allowed". The video grant is
      // what this helper reports; either subset granted is fine.
      await Permission.photos.request();
      await Permission.audio.request();
    } else {
      status = await Permission.storage.request();
    }
  } catch (_) {
    // Some skins/Go builds lack a permission screen entirely and the
    // request can throw instead of returning denied.
    status = PermissionStatus.denied;
  }
  return status.isGranted;
}
'''
with open('lib/utils/storage_permission.dart', 'w') as f:
    f.write(STORAGE)
print('OK: lib/utils/storage_permission.dart')

# ---------------------------------------------------------------
# 5. video_library_state.dart - scoped scan.
# ---------------------------------------------------------------
patch('lib/state/video_library_state.dart', r"""  /// Requests "All files access" (Android 11+) or the classic Storage
  /// runtime permission (Android 10 and older), then scans the whole of
  /// internal storage for videos. Call again any time to retry after a
  /// denial.
  Future<void> scanAllStorage() async {
    if (isScanning) return;
    permissionDenied = false;
    notifyListeners();
    unawaited(NativeBridge.crumb('scan_start'));

    PermissionStatus status;
    try {
      status = await Permission.manageExternalStorage.request();
    } catch (_) {
      // v37: some skins/builds (Tecno/Infinix/MIUI, Go editions) lack the
      // "All files access" settings screen entirely, and the request can
      // blow up instead of returning 'denied'. Never die at app start:
      // fall back to the existing denied-state UI with a retry button.
      unawaited(NativeBridge.crumb('scan_permission_threw'));
      permissionDenied = true;
      notifyListeners();
      return;
    }
    if (!status.isGranted && (await NativeBridge.sdkInt()) < 30) {
      // v38: Android 10 and older (API < 30) have no "All files access" at
      // all - the request above resolves to denied FOREVER there (the real
      // API 27 log: scan_start twice, never scan_granted, even after the
      // user granted Storage manually). The classic Storage runtime
      // permission is the correct ask on those versions.
      unawaited(NativeBridge.crumb('scan_legacy_perm'));
      status = await Permission.storage.request();
    }
    if (!status.isGranted) {
      permissionDenied = true;
      notifyListeners();
      return;
    }

    unawaited(NativeBridge.crumb('scan_granted'));
    folderName = 'Device storage';
    // v40: scan EVERY mounted storage volume (internal + SD card, e.g.
    // "/storage/1C4B-9A2F"). The old code walked only
    // "/storage/emulated/0/", so videos on SD cards never appeared
    // ("does not show external storage added on phone like sd cards").
    await _scanDirectories(
      normalizeStorageRoots(await NativeBridge.storageRoots()),
    );
  }
""", r"""  /// v112 (Play policy): all-files access is gone - the library asks the
  /// version-correct scoped permission and lists videos through MediaStore
  /// (covers internal + SD card) on Android 10+; Android 9 and older keep
  /// the classic Storage permission + filesystem walk. Call again any time
  /// to retry after a denial.
  Future<void> scanAllStorage() async {
    if (isScanning) return;
    permissionDenied = false;
    notifyListeners();
    unawaited(NativeBridge.crumb('scan_start'));

    final sdk = await NativeBridge.sdkInt();
    PermissionStatus status;
    try {
      // API 33+: the Videos media permission gates MediaStore reads.
      // API 29-32: READ_EXTERNAL_STORAGE. API <= 28: the same classic
      // runtime permission, granted as a broad legacy read.
      status = sdk >= 33
          ? await Permission.videos.request()
          : await Permission.storage.request();
    } catch (_) {
      // v37: some skins/builds (Tecno/Infinix/MIUI, Go editions) can throw
      // instead of returning denied. Never die at app start: fall back to
      // the existing denied-state UI with a retry button.
      unawaited(NativeBridge.crumb('scan_permission_threw'));
      permissionDenied = true;
      notifyListeners();
      return;
    }
    if (!status.isGranted) {
      permissionDenied = true;
      notifyListeners();
      return;
    }

    unawaited(NativeBridge.crumb('scan_granted'));
    folderName = 'Device storage';
    if (sdk >= 29) {
      await _scanMediaStore();
    } else {
      // v40: scan EVERY mounted storage volume (internal + SD card, e.g.
      // "/storage/1C4B-9A2F"). The old code walked only
      // "/storage/emulated/0/", so videos on SD cards never appeared
      // ("does not show external storage added on phone like sd cards").
      await _scanDirectories(
        normalizeStorageRoots(await NativeBridge.storageRoots()),
      );
    }
  }
""")

patch('lib/state/video_library_state.dart', r"""  Future<void> rescan() => scanAllStorage();
""", r"""  /// v112: MediaStore listing (scoped-storage safe) feeding the same track
  /// pipeline the filesystem walk uses below. Covers internal + SD card
  /// volumes via VOLUME_EXTERNAL; [seenPaths] dedupes paths that surface
  /// twice on quirky builds.
  Future<void> _scanMediaStore() async {
    isScanning = true;
    _videos = [];
    scanProgress = const ScanProgress();
    notifyListeners();

    final seenPaths = <String>{};
    final foundPaths = <String>[];
    for (final path in await NativeBridge.listMediaStoreVideos()) {
      if (seenPaths.add(path)) foundPaths.add(path);
    }

    scanProgress =
        ScanProgress(found: foundPaths.length, total: foundPaths.length);
    notifyListeners();

    final allVideos = <VideoTrack>[];
    // Process in small batches so the UI can show progress incrementally.
    const batchSize = 8;
    for (var i = 0; i < foundPaths.length; i += batchSize) {
      final batch = foundPaths.skip(i).take(batchSize);
      final tracks = await Future.wait(batch.map(_buildTrack));
      allVideos.addAll(tracks.whereType<VideoTrack>());
      _videos = [...allVideos];
      scanProgress = ScanProgress(
        found: foundPaths.length,
        processed: (i + batchSize).clamp(0, foundPaths.length),
        total: foundPaths.length,
      );
      notifyListeners();
    }

    isScanning = false;
    notifyListeners();
  }

  Future<void> rescan() => scanAllStorage();
""")

# ---------------------------------------------------------------
# 6. private_vault.dart - hide deletes via system consent, unhide
#    exports through MediaStore.
# ---------------------------------------------------------------
patch('lib/state/private_vault.dart', r"""  /// Moves [srcPath] into the vault and returns the new file. Same-filesystem
  /// rename is instant; a cross-device fallback copies then deletes.
  Future<File> hide(String srcPath) async {
    final src = File(srcPath);
    if (!src.existsSync()) {
      throw const FileSystemException('Video file not found');
    }
    final target = await _uniqueIn(await _dir(), srcPath);
    final moved = await _move(src, target);
    revision++; // v26: vault contents changed
""", r"""  /// Moves [srcPath] into the vault and returns the new file. API <= 28
  /// renames instantly; on scoped storage (API 29+) we may READ the video
  /// with the media permission but deleting the original needs the system's
  /// consent dialog (v112), which shows once the copy is safely inside.
  Future<File> hide(String srcPath) async {
    final src = File(srcPath);
    if (!src.existsSync()) {
      throw const FileSystemException('Video file not found');
    }
    final target = await _uniqueIn(await _dir(), srcPath);
    final File moved;
    if ((await NativeBridge.sdkInt()) >= 29) {
      moved = await src.copy(target);
      final deleted = await NativeBridge.requestMediaDelete([srcPath]);
      if (!deleted) {
        // Roll back so a declined delete never leaves a silent duplicate.
        try {
          await moved.delete();
        } catch (_) {}
        throw const FileSystemException('Delete of the original was declined');
      }
    } else {
      moved = await _move(src, target);
    }
    revision++; // v26: vault contents changed
""")

patch('lib/state/private_vault.dart', r"""  Future<File> unhide(String hiddenPath) async {
    final src = File(hiddenPath);
    if (!src.existsSync()) {
      throw const FileSystemException('Hidden video not found');
    }
    final destDir = Directory(unhideDirPath);
""", r"""  Future<File> unhide(String hiddenPath) async {
    final src = File(hiddenPath);
    if (!src.existsSync()) {
      throw const FileSystemException('Hidden video not found');
    }
    if ((await NativeBridge.sdkInt()) >= 29) {
      // v112 / scoped storage: export through MediaStore into the public
      // Movies folder (auto-indexed - no rescan needed), then drop the
      // vault copy, which lives in our own app directory.
      final name = hiddenPath.split('/').last;
      final saved = await NativeBridge.savePickedVideoToDevice(
        cachePath: hiddenPath,
        name: name,
        relativePath: 'Movies',
      );
      if (saved == null) {
        throw const FileSystemException('Could not export the video');
      }
      await src.delete();
      revision++;
      final outPath = saved['path']?.toString();
      return File(
        outPath != null && outPath.isNotEmpty ? outPath : '$unhideDirPath/$name',
      );
    }
    final destDir = Directory(unhideDirPath);
""")

patch('lib/state/private_vault.dart', r"""        throw const FileSystemException(
          'Vault storage is not available - allow "All files access" for '
          'Max Player and try again',
        );
""", r"""        throw const FileSystemException(
          'Vault storage is not available - allow storage permission for '
          'Max Player and try again',
        );
""")

patch('lib/state/private_vault.dart', r"""        throw const FileSystemException(
          'Could not remove the original file - allow "All files access" '
          'for Max Player and try again',
        );
""", r"""        throw const FileSystemException(
          'Could not remove the original file - allow storage permission '
          'for Max Player and try again',
        );
""")

# ---------------------------------------------------------------
# 7. file_manager_screen.dart - scoped wording only (behavior on
#    API 30+ degrades to the readable subset; folder browse of
#    arbitrary dirs is impossible without the rejected permission).
# ---------------------------------------------------------------
patch('lib/screens/file_manager_screen.dart', r"""  /// v95: ask for "All files access" ONCE up front, then list. Without
  /// this the shortcut tiles (WhatsApp especially) silently showed nothing
  /// on Android 11+. Re-used by the in-list "Grant access" button.
""", r"""  /// v95: ask for storage access ONCE up front, then list. Without this
  /// the shortcut tiles (WhatsApp especially) silently showed nothing on
  /// Android 11+. v112: the broad all-files grant was rejected by Play as
  /// non-core and is gone - the ask is the scoped media permission now.
  /// Re-used by the in-list "Grant access" button.
""")

patch('lib/screens/file_manager_screen.dart', r"""              ? 'Max Player needs "All files access" to read this folder.'
""", r"""              ? 'Max Player needs media storage permission to read this folder.'
""")

# 8. library_screen.dart - comment wording.
patch('lib/screens/library_screen.dart', r"""    // ONLY "All files access" resolved denied FOREVER on Android 10 and
""", r"""    // ONLY the legacy ask resolved denied FOREVER on Android 10 and
""")

# ---------------------------------------------------------------
# 9. Docs.
# ---------------------------------------------------------------
patch('PLAY_STORE_GUIDE.md', r"""- **MANAGE_EXTERNAL_STORAGE declaration:** Play asks for justification since
  the app uses all-files access. Justification: *"Core functionality: the
  app's primary purpose is playing video files stored anywhere on the device,
  including external SD cards and USB-OTG; MediaStore/scoped storage cannot
  enumerate all video files (e.g. .mkv/.ts on SD cards). Screenshots and AI
  subtitle files are written next to the source videos."* — this is the
  standard media-player justification and is routinely accepted **for apps
  whose main function is media playback**. Record the short screen-video they
  ask for showing: scanning the library + playing a video.
""", r"""- **Permissions declaration:** v112 removed all-files access entirely (Play
  rejected the justification as non-core). The app uses scoped media access
  only: the library scans through MediaStore, cloud imports arrive via
  Android's file picker (SAF), and the Private folder deletes originals
  through the per-file system consent dialog. If the Console still shows an
  old **All files access** declaration from a previous release, open that
  form and state the permission is no longer used before resubmitting - a
  stale form keeps failing review even with the manifest cleaned.
""")

patch('docs/privacy.html', r"""    <li><b>All files access (optional):</b> full-folder scanning on Android
    11+.</li>
""", r"""    <li><b>Media library:</b> the video list is built through Android's
    MediaStore (scoped storage) - no all-files access.</li>
""")

# ---------------------------------------------------------------
# 10. Version bump.
# ---------------------------------------------------------------
patch('pubspec.yaml', r"""version: 1.0.0+111
""", r"""version: 1.0.0+112
""")

# ---------------------------------------------------------------
# 11. Tests: new v112 group pinning the removal + the replacements.
# ---------------------------------------------------------------
patch('test/widget_test.dart', r"""        expect(manual.contains('Google Drive sign-in'), isFalse);
      });
    });
  });
}
""", r"""        expect(manual.contains('Google Drive sign-in'), isFalse);
      });
    });

    group('v112 Play policy: MANAGE_EXTERNAL_STORAGE removed', () {
      test('no all-files permission survives anywhere user-facing', () {
        final manifest = File('android/app/src/main/AndroidManifest.xml')
            .readAsStringSync();
        expect(manifest.contains('MANAGE_EXTERNAL_STORAGE'), isFalse);
        expect(manifest, contains('v112: All-files access removed'));
        final storage =
            File('lib/utils/storage_permission.dart').readAsStringSync();
        expect(storage.contains('manageExternalStorage'), isFalse);
        final vault = File('lib/state/private_vault.dart').readAsStringSync();
        expect(vault.contains('All files access'), isFalse);
        final fm =
            File('lib/screens/file_manager_screen.dart').readAsStringSync();
        expect(fm.contains('All files access'), isFalse);
        expect(fm, contains('media storage permission'));
        final guide = File('PLAY_STORE_GUIDE.md').readAsStringSync();
        expect(guide.contains('MANAGE_EXTERNAL_STORAGE'), isFalse);
        final privacy = File('docs/privacy.html').readAsStringSync();
        expect(privacy.contains('All files access'), isFalse);
        expect(privacy, contains('MediaStore'));
        final pubspec = File('pubspec.yaml').readAsStringSync();
        expect(pubspec, contains('version: 1.0.0+112'));
      });

      test('scoped replacements are wired end-to-end', () {
        final state = File('lib/state/video_library_state.dart')
            .readAsStringSync();
        expect(state.contains('manageExternalStorage'), isFalse);
        expect(state, contains('_scanMediaStore'));
        expect(state, contains('listMediaStoreVideos'));
        final bridge =
            File('lib/services/native_bridge.dart').readAsStringSync();
        expect(bridge, contains('listMediaStoreVideos'));
        expect(bridge, contains('requestMediaDelete'));
        expect(bridge, contains('relativePath'));
        final mainKt = File(
                'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt')
            .readAsStringSync();
        expect(mainKt, contains('queryMediaStoreVideoPaths'));
        expect(mainKt, contains('resolveVideoUri'));
        expect(mainKt, contains('createDeleteRequest'));
        expect(mainKt, contains('RecoverableSecurityException'));
        expect(mainKt, contains('REQ_MEDIA_DELETE'));
        expect(mainKt, contains('finishMediaDelete'));
        expect(mainKt, contains('pendingMediaDeleteResult'));
        final vault = File('lib/state/private_vault.dart').readAsStringSync();
        expect(vault, contains('requestMediaDelete'));
        expect(vault, contains("relativePath: 'Movies'"));
      });
    });
  });
}
""")

print('ALL PATCHES APPLIED')
PYEOF

echo ""
echo "======================================================================"
echo " v112 patched. Next steps:"
echo "   flutter analyze"
echo "   flutter test"
echo " Then commit & push (see chat instructions for the exact commands)."
echo "======================================================================"
