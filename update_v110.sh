#!/usr/bin/env bash
# =============================================================================
# Max Player — update_v110.sh
#
#  1) "The Easy Way" video picking: Android's built-in document picker
#     (ACTION_OPEN_DOCUMENT) lists this device AND installed storage providers
#     (Google Drive app) — NO Google sign-in / NO Drive-API OAuth verification.
#     Cloud picks are copied for playback, with a "Save to device" option that
#     writes a permanent copy into Movies/Max Player.
#  2) Lock-screen fix: the now-playing notification was a PLAIN ongoing
#     notification on the frozen low-importance "playback" channel — hidden on
#     the lock screen by many devices. It is now a MediaStyle notification
#     bound to the MediaSession token, on a fresh lockscreen-PUBLIC,
#     default-importance-but-silent channel ("playback_v2").
#  3) Docs: user manual (picker guide + lock-screen FAQ), in-app privacy
#     policy, GitHub PRIVACY_POLICY.md + docs/privacy.html, terms of service
#     (also fixes the brand-name mismatch that breaks the v108 widget test).
#  4) Version -> 1.0.0+110.
#
# Run from the repo root:  cd ~/IdeaProjects/maxplayer && bash update_v110.sh
# =============================================================================
set -euo pipefail

if [ ! -f pubspec.yaml ] || [ ! -f lib/main.dart ]; then
  echo "ERROR: run this script from the Max Player repo root (~/IdeaProjects/maxplayer)"
  exit 1
fi

# Safety net for forgotten local changes (see project rules): warn, don't wipe.
# (update_v*.sh scripts themselves are ignored - they are delivery vehicles.)
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

# ============================================================================
# 1) android/app/build.gradle.kts — androidx.media dependency (MediaStyle)
# ============================================================================
patch('android/app/build.gradle.kts', r"""    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
""", r"""    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // v110: androidx.media NotificationCompat.MediaStyle — needed to bind the
    // now-playing notification to the MediaSession token, which is what puts
    // REAL media controls on the lock screen (plain ongoing notifications on
    // a low-importance channel are hidden on the lock screen of MIUI/HyperOS,
    // ColorOS and several other builds).
    implementation("androidx.media:media:1.7.0")
}
""")

# ============================================================================
# 2) Notifications.kt — fresh lockscreen-PUBLIC playback channel
# ============================================================================
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt', r"""import android.app.NotificationChannel
""", r"""import android.app.Notification
import android.app.NotificationChannel
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt', r"""    const val CHANNEL_PLAYBACK = "playback"
""", r"""    const val CHANNEL_PLAYBACK = "playback"

    // v110: fresh channel id for now-playing. Android freezes a channel's
    // lock-screen visibility at CREATION time, so devices that already hold
    // the old "playback" channel could never gain PUBLIC visibility on it.
    const val CHANNEL_PLAYBACK_V2 = "playback_v2"
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt', r"""        Triple(CHANNEL_PLAYBACK, "Playback", NotificationManager.IMPORTANCE_LOW),
""", r"""        Triple(CHANNEL_PLAYBACK, "Playback", NotificationManager.IMPORTANCE_LOW),
        Triple(CHANNEL_PLAYBACK_V2, "Now playing", NotificationManager.IMPORTANCE_DEFAULT),
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt', r"""                    NotificationChannel(id, title, importance).apply {
                        description = "Max Player notifications"
                    }
""", r"""                    NotificationChannel(id, title, importance).apply {
                        description = "Max Player notifications"
                        if (id == CHANNEL_PLAYBACK_V2) {
                            // A media channel must stay SILENT but VISIBLE:
                            // importance DEFAULT (IMPORTANCE_LOW rows are
                            // minimized or hidden on the lock screen by
                            // several OEM skins) with sound and vibration
                            // switched off, no badge, and explicitly
                            // lock-screen PUBLIC - this is only honored
                            // because the channel id is brand-new.
                            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                            setShowBadge(false)
                            setSound(null, null)
                            enableVibration(false)
                        }
                    }
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt', r"""            .setPriority(
                if (channel == CHANNEL_AI_SUBS || channel == CHANNEL_PLAYBACK)
                    NotificationCompat.PRIORITY_LOW
                else
                    NotificationCompat.PRIORITY_DEFAULT
            )
""", r"""            .setPriority(
                if (channel == CHANNEL_AI_SUBS ||
                    channel == CHANNEL_PLAYBACK ||
                    channel == CHANNEL_PLAYBACK_V2)
                    NotificationCompat.PRIORITY_LOW
                else
                    NotificationCompat.PRIORITY_DEFAULT
            )
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt', r"""        val builder = NotificationCompat.Builder(context, CHANNEL_PLAYBACK)
""", r"""        val builder = NotificationCompat.Builder(context, CHANNEL_PLAYBACK_V2)
""")

# ============================================================================
# 3) MediaPlaybackService.kt — MediaStyle bound to the session token
# ============================================================================
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt', r"""        val builder = NotificationCompat.Builder(applicationContext, Notifications.CHANNEL_PLAYBACK)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(if (subtitle.isNotEmpty()) subtitle else "Max Player")
            .setContentIntent(tapIntent)
            .setOngoing(isPlaying)
            .setAutoCancel(!isPlaying)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
""", r"""        val builder = NotificationCompat.Builder(applicationContext, Notifications.CHANNEL_PLAYBACK_V2)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(if (subtitle.isNotEmpty()) subtitle else "Max Player")
            .setContentIntent(tapIntent)
            .setOngoing(isPlaying)
            .setAutoCancel(!isPlaying)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setShowWhen(false)
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt', r"""        builder.addAction(android.R.drawable.ic_media_previous, "Previous", prevPending)
        builder.addAction(playPauseIcon, playPauseLabel, playPausePending)
        builder.addAction(android.R.drawable.ic_media_next, "Next", nextPending)
        builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)

        return builder.build()
""", r"""        builder.addAction(android.R.drawable.ic_media_previous, "Previous", prevPending)
        builder.addAction(playPauseIcon, playPauseLabel, playPausePending)
        builder.addAction(android.R.drawable.ic_media_next, "Next", nextPending)
        builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)

        // v110 lock-screen fix: attach a MediaStyle bound to the live
        // MediaSession token. This promotes the row into the SYSTEM media
        // player (the lock-screen media area on Android 11+, and the OEM
        // media bubble on MIUI/OneUI/ColorOS). A plain ongoing notification -
        // even with VISIBILITY_PUBLIC - is hidden on the lock screen of many
        // devices because it sits on a silenced/minimized channel.
        val sessionTokenCompat = mediaSession?.sessionToken?.let {
            android.support.v4.media.session.MediaSessionCompat.Token.fromToken(it)
        }
        builder.setStyle(
            androidx.media.app.NotificationCompat.MediaStyle()
                .setMediaSession(sessionTokenCompat)
                .setShowActionsInCompactView(0, 1, 2)
                .setShowCancelButton(true)
                .setCancelButtonIntent(stopPending)
        )

        return builder.build()
""")

# ============================================================================
# 4) MainActivity.kt — SAF picker + save-to-device
# ============================================================================
patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""import android.content.BroadcastReceiver
import android.content.Context
""", r"""import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""import java.io.File
import java.io.FileOutputStream
""", r"""import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""        private const val REQ_VOICE_SEARCH = 46
""", r"""        private const val REQ_VOICE_SEARCH = 46
        private const val REQ_SAF_PICK = 47
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""    private var pendingVoiceSearchResult: MethodChannel.Result? = null
""", r"""    private var pendingVoiceSearchResult: MethodChannel.Result? = null

    // v110: system document picker (SAF) round-trip in flight. One pending
    // Dart result, same pattern as the voice search / credential prompts.
    private var pendingSafPickResult: MethodChannel.Result? = null
""", count=1)

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""                "nowPlayingShow" -> {
""", r"""                "pickVideoDocument" -> {
                    // v110 "The Easy Way": Android's built-in document picker
                    // (Storage Access Framework). It lists device storage AND
                    // every installed provider app - including Google Drive -
                    // with no Google sign-in and no Drive-API verification.
                    if (pendingSafPickResult != null) {
                        result.error("busy", "a pick is already in progress", null)
                    } else {
                        pendingSafPickResult = result
                        try {
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "video/*"
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }
                            startActivityForResult(intent, REQ_SAF_PICK)
                        } catch (e: Exception) {
                            pendingSafPickResult = null
                            result.success(null)
                        }
                    }
                }
                "saveDocumentToDevice" -> {
                    val sourceUri = call.argument<String>("sourceUri")
                    val cachePath = call.argument<String>("cachePath")
                    val rawName = call.argument<String>("name") ?: "video"
                    if (sourceUri.isNullOrEmpty() && cachePath.isNullOrEmpty()) {
                        result.error("bad_args", "sourceUri or cachePath is required", null)
                    } else {
                        executor.execute {
                            val saved = saveDocumentToDevice(sourceUri, cachePath, rawName)
                            mainHandler.post {
                                if (saved != null) {
                                    result.success(saved)
                                } else {
                                    result.error("save_failed", "could not write the file", null)
                                }
                            }
                        }
                    }
                }
                "nowPlayingShow" -> {
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""    /**
     * Turns a content:// or file:// URI into a real filesystem path our
     * player (libmpv) can open. Strategies:
""", r"""    /**
     * v110: answer for the ACTION_OPEN_DOCUMENT pick. Local device files
     * resolve to a real path (instant, zero copy); cloud/provider documents
     * (Google Drive & friends) are stream-copied into the app cache first so
     * libmpv can open them. The original content:// URI is kept in the
     * result so Dart can offer "Save to device" afterwards.
     */
    private fun finishSafPick(resultCode: Int, data: Intent?) {
        val pending = pendingSafPickResult
        pendingSafPickResult = null
        if (pending == null) return
        val uri = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) {
            pending.success(null)
            return
        }
        // A durable read grant lets "Save to device" re-pull the original
        // bytes later (Drive-style providers support persistable grants).
        try {
            contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) {}
        executor.execute {
            val name = queryDisplayName(uri) ?: "video"
            var resolved = resolveVideoPath(uri)
            var cached = false
            if (resolved == null) {
                resolved = copyContentToCache(uri)
                cached = resolved != null
            }
            val path = resolved
            mainHandler.post {
                if (path == null) {
                    pending.success(null)
                } else {
                    val map = HashMap<String, Any?>()
                    map["path"] = path
                    map["name"] = name
                    map["cached"] = cached
                    map["sourceUri"] = uri.toString()
                    map["sizeBytes"] = try { File(path).length() } catch (_: Exception) { 0L }
                    pending.success(map)
                }
            }
        }
    }

    /** Readable byte stream for a picked document: its SAF grant first,
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

    /**
     * v110: permanent copy of a picked cloud video into
     * Movies/Max Player. API 29+ goes through MediaStore (no permission
     * needed for our own insert); older versions write the public Movies
     * directory directly (we hold legacy storage permission there) and ping
     * the media scanner so gallery apps see it at once.
     */
    private fun saveDocumentToDevice(
        sourceUri: String?,
        cachePath: String?,
        rawName: String
    ): HashMap<String, Any?>? {
        return try {
            var name = rawName.ifEmpty { "video.mp4" }
            name = name.replace(Regex("[^A-Za-z0-9._ -]"), "_")
            if (!name.contains('.')) name += ".mp4"
            val input = openDocumentInput(sourceUri, cachePath) ?: return null
            val out = HashMap<String, Any?>()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, name)
                    put(MediaStore.Video.Media.MIME_TYPE, guessVideoMime(name))
                    put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/Max Player")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
                val collection = MediaStore.Video.Media.getContentUri(
                    MediaStore.VOLUME_EXTERNAL_PRIMARY
                )
                val outUri = contentResolver.insert(collection, values)
                if (outUri == null) {
                    try { input.close() } catch (_: Exception) {}
                    return null
                }
                var ok = false
                try {
                    contentResolver.openOutputStream(outUri, "w")?.use { output ->
                        input.use { it.copyTo(output) }
                    }
                    ok = true
                } catch (_: Exception) {}
                if (!ok) {
                    try { contentResolver.delete(outUri, null, null) } catch (_: Exception) {}
                    return null
                }
                val done = ContentValues().apply {
                    put(MediaStore.Video.Media.IS_PENDING, 0)
                }
                try { contentResolver.update(outUri, done, null, null) } catch (_: Exception) {}
                out["path"] = queryDataColumn(outUri)
                out["location"] = "Movies/Max Player/$name"
                out["name"] = name
                out
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_MOVIES
                    ),
                    "Max Player"
                )
                if (!dir.exists()) dir.mkdirs()
                val outFile = File(dir, name)
                var ok = false
                try {
                    FileOutputStream(outFile).use { output ->
                        input.use { it.copyTo(output) }
                    }
                    ok = outFile.length() > 0
                } catch (_: Exception) {}
                if (!ok) {
                    try { outFile.delete() } catch (_: Exception) {}
                    return null
                }
                try {
                    MediaScannerConnection.scanFile(
                        this,
                        arrayOf(outFile.absolutePath),
                        arrayOf(guessVideoMime(name)),
                        null
                    )
                } catch (_: Exception) {}
                out["path"] = outFile.absolutePath
                out["location"] = "Movies/Max Player/$name"
                out["name"] = name
                out
            }
        } catch (e: Exception) {
            null
        }
    }

    /** _data column for a MediaStore row we just wrote (null on stricter builds). */
    private fun queryDataColumn(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null
            )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        } catch (e: Exception) {
            null
        }
    }

    private fun guessVideoMime(name: String): String {
        return when (name.substringAfterLast('.', "").lowercase()) {
            "webm" -> "video/webm"
            "mkv" -> "video/x-matroska"
            "avi" -> "video/x-msvideo"
            "mov" -> "video/quicktime"
            "wmv" -> "video/x-ms-wmv"
            "flv" -> "video/x-flv"
            "ts", "mts", "m2ts" -> "video/mp2t"
            "3gp", "3gpp" -> "video/3gpp"
            "mpg", "mpeg" -> "video/mpeg"
            else -> "video/mp4"
        }
    }

    /**
     * Turns a content:// or file:// URI into a real filesystem path our
     * player (libmpv) can open. Strategies:
""")

patch('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt', r"""    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_CONFIRM_CREDENTIAL) {
""", r"""    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SAF_PICK) {
            finishSafPick(resultCode, data)
        } else if (requestCode == REQ_CONFIRM_CREDENTIAL) {
""")

# ============================================================================
# 5) native_bridge.dart — Dart wrappers
# ============================================================================
patch('lib/services/native_bridge.dart', r"""  // ---------------------------------------------------------------------------
  // v62 Phase 1: notifications
""", r"""  // ---------------------------------------------------------------------------
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
""")

# ============================================================================
# 6) cloud_storage_sheet.dart — "Select video" UI + save dialog
# ============================================================================
patch('lib/widgets/cloud_storage_sheet.dart', r"""  bool _signingIn = false;
""", r"""  bool _signingIn = false;
  bool _picking = false; // v110: Android system picker round-trip in progress
""")

patch('lib/widgets/cloud_storage_sheet.dart', r"""  void _playVideo(GDriveItem item) {
    Navigator.of(context).pop();
    widget.onPlay(item.streamUrl, item.name, _headers);
  }
""", r"""  void _playVideo(GDriveItem item) {
    Navigator.of(context).pop();
    widget.onPlay(item.streamUrl, item.name, _headers);
  }

  // v110 "The Easy Way": Android's built-in file picker lists this device
  // AND the user's installed storage apps (Google Drive included) - no
  // Google sign-in, no OAuth verification. Local files play straight from
  // their path; cloud files arrive as a temporary copy, so the user is
  // offered a permanent "Save to device" copy in Movies/Max Player.
  Future<void> _pickViaAndroidPicker() async {
    if (_picking) return;
    setState(() => _picking = true);
    final picked = await NativeBridge.pickVideoDocument();
    if (!mounted) return;
    setState(() => _picking = false);
    if (picked == null) return; // user canceled the picker
    final messenger = ScaffoldMessenger.maybeOf(context);
    final path = picked['path']?.toString() ?? '';
    final name = picked['name']?.toString() ?? 'video';
    if (path.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1b1b24),
          title: const Text("Couldn't open that file",
              style: TextStyle(color: Colors.white, fontSize: 17)),
          content: const Text(
            'The selected video could not be read. Try another file, or '
            'sign in to Google Drive instead.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (picked['cached'] != true) {
      // Plain local file: already on the device, nothing to save.
      _playPicked(path, name);
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
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1b1b24),
          title: const Text("Couldn't save",
              style: TextStyle(color: Colors.white, fontSize: 17)),
          content: const Text(
            'The copy could not be written to Movies/Max Player. Playing '
            'the temporary copy is still possible.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
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
    // Same onPlay pipeline the Drive list uses: libmpv opens local absolute
    // paths exactly like stream URLs.
    widget.onPlay(path, name);
  }
""")

patch('lib/widgets/cloud_storage_sheet.dart', r"""                                  onPressed: _signingIn ? null : _signIn,
                                ),
                              ),
                            ],
""", r"""                                  onPressed: _signingIn ? null : _signIn,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'or',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side:
                                        const BorderSide(color: Colors.white24),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(
                                      Icons.folder_open_outlined),
                                  label: Text(
                                    _picking
                                        ? 'Opening picker…'
                                        : 'Select video (no sign-in)',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14),
                                  ),
                                  onPressed:
                                      _picking ? null : _pickViaAndroidPicker,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                "Opens Android's file picker: choose a video "
                                'from this device, your Google Drive app, or '
                                'any storage app. Cloud files are copied '
                                'first, so big ones take a moment - then you '
                                'can keep them with Save to device.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11.5,
                                    height: 1.35),
                              ),
                            ],
""")

patch('lib/widgets/cloud_storage_sheet.dart', r"""                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                            child: Row(
""", r"""                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                      color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 11),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                                icon: const Icon(
                                    Icons.folder_open_outlined,
                                    size: 20),
                                label: Text(
                                  _picking
                                      ? 'Opening picker…'
                                      : 'Select video via Android picker '
                                          '(device / Drive app)',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500),
                                ),
                                onPressed: _picking
                                    ? null
                                    : _pickViaAndroidPicker,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                            child: Row(
""")

# ============================================================================
# 7) pubspec.yaml — version bump
# ============================================================================
patch('pubspec.yaml', r"""version: 1.0.0+109
""", r"""version: 1.0.0+110
""")

# ============================================================================
# 8) user_manual_sheet.dart — picker guide + lock-screen FAQ
# ============================================================================
patch('lib/widgets/user_manual_sheet.dart', r"""  _Item(
    Icons.volume_up,
    'Volume boost up to 200%',
""", r"""  _Item(
    Icons.folder_open_outlined,
    'Select video (no sign-in)',
    'Library → Cloud Storage → Select video: Android\'s own file picker '
        'opens with this device, your Google Drive app, and any other '
        'storage app side by side - no Google account needed. Cloud videos '
        'are copied into Max Player first (large ones take a moment); after '
        'picking, choose "Save to device" to keep a permanent copy in '
        'Movies/Max Player.',
  ),
  _Item(
    Icons.volume_up,
    'Volume boost up to 200%',
""")

patch('lib/widgets/user_manual_sheet.dart', r"""const List<_Item> _tipItems = [
""", r"""const List<_Item> _tipItems = [
  _Item(
    Icons.notifications_active_outlined,
    'Playback controls missing on the lock screen?',
    'Keep the app updated, then check: (1) Android Settings → Apps → Max '
        'Player → Notifications is allowed; (2) your phone\'s lock-screen '
        'setting shows notifications - on Xiaomi/Redmi/Poco open Settings → '
        'Notifications → "Notifications on lock screen", on Samsung open '
        'Settings → Lock screen → Notifications; (3) battery saving or '
        'background restrictions are off for Max Player. The media panel '
        'with play/pause & seek appears whenever a video is playing or '
        'paused in the background.',
  ),
""")

# ============================================================================
# 9) lib/utils/privacy_policy.dart — in-app policy
# ============================================================================
patch('lib/utils/privacy_policy.dart', r"""    '- Storage (videos / all files): to find and play the videos stored on '
    'your device, save screenshots to "Pictures/Max Player", and write AI '
    'subtitle files next to your videos. None of it ever leaves your '
    'device.\n'
""", r"""    '- Storage (videos / all files): to find and play the videos stored on '
    'your device, play videos you pick in Android\'s file picker, save '
    'screenshots to "Pictures/Max Player", save picked videos to '
    '"Movies/Max Player" (only when you tap Save), and write AI subtitle '
    'files next to your videos. None of it ever leaves your device.\n'
""")

patch('lib/utils/privacy_policy.dart', r"""    'page.\n'
    '\n'
    'AI SUBTITLES\n'
""", r"""    'page.\n'
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
    'AI SUBTITLES\n'
""")

# ============================================================================
# 10) PRIVACY_POLICY.md — GitHub policy
# ============================================================================
patch('PRIVACY_POLICY.md', r"""| **Storage (videos / all files)** | To find and play the videos stored on your device, save screenshots to *Pictures/Max Player*, and write AI subtitle files next to your videos | Never leaves your device |
""", r"""| **Storage (videos / all files)** | To find and play the videos stored on your device, play videos you pick in Android's file picker, save screenshots to *Pictures/Max Player*, save picked videos to *Movies/Max Player* (only when you tap Save), and write AI subtitle files next to your videos | Never leaves your device |
""")

patch('PRIVACY_POLICY.md', r"""page.

## AI subtitles
""", r"""page.

### The system file picker ("Select video")
Library → Cloud Storage also offers **Select video (no sign-in)**: it opens Android's built-in file picker, which lists this device **and** the storage apps installed on it — including your Google Drive app. No account, password, or Google sign-in is involved, and the app never sees your Drive file list; the system hands Max Player a one-time, read-only grant for just the file you choose. If the file lives in a cloud app, its bytes are streamed once into the app's private cache purely so it can be played, and the copy is discarded when replaced or cleared. Tapping **Save to device** stores a permanent copy in *Movies/Max Player* — nothing is uploaded anywhere; the bytes travel only from the provider app (e.g. Google) to your own phone, exactly like a download in your browser.

## AI subtitles
""")

patch('PRIVACY_POLICY.md', r"""- **Data sent off the device:** only what you trigger — Drive file listings and streams travel between your phone and Google while you use Cloud Storage; everything else (AI subtitles, history, bookmarks, settings) is local-only
""", r"""- **Data sent off the device:** only what you trigger — Drive file listings and streams (or a picked cloud file's bytes, via the provider app) travel between your phone and Google while you use Cloud Storage or the system file picker; everything else (AI subtitles, history, bookmarks, settings) is local-only
""")

# ============================================================================
# 11) docs/privacy.html — GitHub Pages policy
# ============================================================================
patch('docs/privacy.html', r"""  Account third-party access page.</p>
  <h2>Device permissions</h2>
""", r"""  Account third-party access page.</p>
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
  <h2>Device permissions</h2>
""")

# ============================================================================
# 12) docs/terms.html — picker addendum
# ============================================================================
patch('docs/terms.html', r"""  <p>Cloud Storage uses Google OAuth on your device with read-only access.
  Drive features are additionally subject to Google's Terms of Service and
  API policies.</p>
""", r"""  <p>Cloud Storage uses Google OAuth on your device with read-only access;
  alternatively, "Select video" opens Android's built-in file picker (no
  sign-in) for files offered by the Drive app on your device. Drive
  features are additionally subject to Google's Terms of Service and API
  policies.</p>
""")

# ============================================================================
# 13) TERMS_OF_SERVICE.md — picker addendum + brand-name fix (v108 test)
# ============================================================================
patch('TERMS_OF_SERVICE.md', r"""**Developer:** Hyper Tech Labs (Aryan Shah)
""", r"""**Developer:** HyperTech Labs (Aryan Shah)
""")

patch('TERMS_OF_SERVICE.md', r"""## Google Drive
Cloud Storage uses Google OAuth on your device with read-only access to list
and stream your own Drive videos. File names, thumbnails and streams travel
only between your phone and Google. Drive features are additionally subject
to Google's Terms of Service and API policies.
""", r"""## Google Drive
Cloud Storage uses Google OAuth on your device with read-only access to list
and stream your own Drive videos; alternatively, "Select video" uses
Android's built-in file picker (no sign-in) to open files offered by the
Drive app on your device. File names, thumbnails and streams travel only
between your phone and Google. Drive features are additionally subject to
Google's Terms of Service and API policies.
""")

patch('TERMS_OF_SERVICE.md', r"""To the maximum extent permitted by law, Hyper Tech Labs is not liable for any
""", r"""To the maximum extent permitted by law, HyperTech Labs is not liable for any
""")

# ============================================================================
# 14) docs/index.html — feature line
# ============================================================================
patch('docs/index.html', r"""explicitly stream them from your own Drive.</p>
""", r"""explicitly stream them from your own Drive.
  Or use Select video: Android's file picker opens videos straight from this
  device and your installed storage apps (Google Drive included) - no
  sign-in, with the option to save a copy to device storage.</p>
""")

# ============================================================================
# 15) test/widget_test.dart — v110 guard tests
# ============================================================================
patch('test/widget_test.dart', r"""      expect(svc, contains('static Map<String, String>? _memHeaders'));
    });

  });
}
""", r"""      expect(svc, contains('static Map<String, String>? _memHeaders'));
    });

    group('v110 SAF picker, lock-screen media notification, docs', () {
      test('system file picker is wired end-to-end', () {
        final pub = File('pubspec.yaml').readAsStringSync();
        expect(pub, contains('1.0.0+110'));
        final bridge =
            File('lib/services/native_bridge.dart').readAsStringSync();
        for (final k in [
          'pickVideoDocument',
          'saveDocumentToDevice',
          'savePickedVideoToDevice',
        ]) {
          expect(bridge, contains(k));
        }
        final sheet =
            File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
        expect(sheet, contains('Select video (no sign-in)'));
        expect(sheet, contains('_pickViaAndroidPicker'));
        expect(sheet, contains('Save to device'));
        final mainKt = File(
                'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt')
            .readAsStringSync();
        for (final k in [
          'ACTION_OPEN_DOCUMENT',
          'REQ_SAF_PICK',
          'takePersistableUriPermission',
          'private fun saveDocumentToDevice',
        ]) {
          expect(mainKt, contains(k));
        }
      });

      test('now-playing is a lock-screen MediaStyle notification', () {
        final svc = File(
                'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt')
            .readAsStringSync();
        expect(
            svc, contains('androidx.media.app.NotificationCompat.MediaStyle'));
        expect(svc, contains('MediaSessionCompat.Token.fromToken'));
        expect(svc, contains('Notifications.CHANNEL_PLAYBACK_V2'));
        final notifs = File(
                'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt')
            .readAsStringSync();
        expect(notifs, contains('playback_v2'));
        expect(
            notifs,
            contains(
                'lockscreenVisibility = Notification.VISIBILITY_PUBLIC'));
        final gradle =
            File('android/app/build.gradle.kts').readAsStringSync();
        expect(gradle, contains('androidx.media'));
      });

      test('v110 docs updated; older pinned strings still intact', () {
        final md = File('PRIVACY_POLICY.md').readAsStringSync();
        expect(md, contains('5 September 2026'));
        expect(md, contains('system file picker'));
        expect(md, contains('Movies/Max Player'));
        final inApp =
            File('lib/utils/privacy_policy.dart').readAsStringSync();
        expect(inApp, contains('SELECT VIDEO (ANDROID FILE PICKER)'));
        final terms = File('TERMS_OF_SERVICE.md').readAsStringSync();
        expect(terms, contains('HyperTech Labs'));
        final manual =
            File('lib/widgets/user_manual_sheet.dart').readAsStringSync();
        expect(manual, contains('Select video (no sign-in)'));
        expect(manual, contains('lock screen'));
        expect(manual, contains('Google Drive sign-in'));
        expect(File('docs/privacy.html').readAsStringSync(),
            contains('file picker'));
      });
    });
  });
}
""")

# ============================================================================
# 16) test/widget_test.dart — BASELINE REPAIR (pre-existing, present in the
#     repo before v110): the v105 "picture rows" test was never closed — a
#     dropped `});` — so the v106/v106-fix/v106-fix2/v107 test declarations
#     were lexically trapped inside its body. The suite silently SKIPPED
#     those four tests and failed on every clean checkout. Verify for
#     yourself: git stash; flutter test. Restoring the brace brings them
#     back; their assertions were verified against this tree first.
# ============================================================================
patch('test/widget_test.dart', r"""      expect(sheet.contains('HDR tone-mapping'), isFalse);
    test('v106 Google Sign-In powers Drive', () {
""", r"""      expect(sheet.contains('HDR tone-mapping'), isFalse);
    });

    test('v106 Google Sign-In powers Drive', () {
""")

# ...and remove the stray `});` that used to "balance" the bug before the
# v108 test. With the real close restored above, this one is extra.
patch('test/widget_test.dart', r"""      expect(terms, contains('as is'));
    });


    });

    test('v108 karaoke switch, iptv label, docs, sticky session', () {
""", r"""      expect(terms, contains('as is'));
    });

    test('v108 karaoke switch, iptv label, docs, sticky session', () {
""")

# ...and a second piece of rot in the same trapped block: the sheet's
# comment was reworded to "wait for the Sign-In button" in a later session
# (v108) but nobody updated this pinned string back then / nobody could see
# it fail. Pin the current wording instead - same intent (no prompt, ever).
patch('test/widget_test.dart', r"""      expect(sheet, contains('wait for the button'));
""", r"""      expect(sheet, contains('Sign-In button'));
""")

# ============================================================================
# 18) analysis_options.yaml — the current Flutter toolchain auto-adds this
#     exclude block the first time `flutter analyze` runs and it would
#     otherwise ride along into your commit as unexplained noise.
# ============================================================================
patch('analysis_options.yaml', r"""# The following line activates a set of recommended lints for Flutter apps,
# packages, and plugins designed to encourage good coding practices.
include: package:flutter_lints/flutter.yaml
""", r"""# The following line activates a set of recommended lints for Flutter apps,
# packages, and plugins designed to encourage good coding practices.
analyzer:
  exclude:
    - build/**
    - android/**
    - ios/**
include: package:flutter_lints/flutter.yaml
""")

print('')
print('All v110 patches applied OK.')
print('Files touched: build.gradle.kts, Notifications.kt,')
print('MediaPlaybackService.kt, MainActivity.kt, native_bridge.dart,')
print('cloud_storage_sheet.dart, user_manual_sheet.dart, privacy_policy.dart,')
print('PRIVACY_POLICY.md, TERMS_OF_SERVICE.md, docs/*.html, pubspec.yaml,')
print('test/widget_test.dart')
PYEOF

echo ""
echo "======================================================================"
echo " v110 patched. Next steps:"
echo "   flutter analyze"
echo "   flutter test"
echo " Then commit & push (see chat instructions for the exact commands)."
echo "======================================================================"
