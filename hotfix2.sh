#!/bin/bash
# ============================================================
# Max Player - v7 HOTFIX (build fix)
# ============================================================
# Fixes the Codemagic build error:
#   MainActivity.kt:178:29 Unresolved reference
#   'setPictureInPictureParameters'
# The Android Activity method is called setPictureInPictureParams
# (no "ers"). One-word change, everything else untouched.
#
# HOW TO USE (on the Pi):
#   cd ~/IdeaProjects/maxplayer
#   nano hotfix2.sh      # paste this whole file, save & exit
#   bash hotfix2.sh
#   git add -A && git commit -m "hotfix: rename to setPictureInPictureParams (build fix)" && git push
# ============================================================
set -e
cd "$(dirname "$0")"
echo "==> Applying PiP hotfix..."

cat > 'android/app/src/main/kotlin/com/example/maxplayer/MainActivity.kt' <<'EOF_MARKER_MAINACTIVITY'
package com.example.maxplayer

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.drawable.Icon
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Native bridge for Max Player. One MethodChannel ("maxplayer/native") exposes:
 *
 *  - getMetadata(path): video duration/dimensions + a cached JPEG thumbnail,
 *    extracted with Android's own MediaMetadataRetriever (no third-party
 *    plugin = no AAR conflicts with the AGP 9 / Kotlin 2.3 toolchain).
 *
 *  - settingsGetAll / settingsPut: tiny key/value store backed by Android
 *    SharedPreferences (settings, watch history, gesture prefs).
 *
 *  - getBrightness / setBrightness / resetBrightness: app-local screen
 *    brightness for the player's left-half swipe gesture.
 *
 *  - "Open with" / "Share" support: VIEW and SEND intents carrying videos are
 *    resolved to real filesystem paths (file://, MediaStore content://,
 *    external-storage document URIs) and delivered to Dart via
 *    getInitialOpenVideo (cold start) or onOpenVideo / onOpenVideoFailed
 *    (warm start, singleTop re-use). Gallery/cloud URIs that do not expose a
 *    real path are stream-copied into the app cache as a fallback. Network
 *    URLs (http/https/rtsp/rtmp/mms) are passed to the player as-is.
 *
 *  - Picture-in-picture with a custom play/pause remote action: providing our
 *    own action also replaces the system's default "settings" gear in the PiP
 *    window. Playback state is kept in sync via setPipPlaying; taps on the
 *    PiP action arrive as the "onPipAction" channel call.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "maxplayer/native"
    private val executor = Executors.newFixedThreadPool(4)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var channel: MethodChannel? = null
    private var pendingOpenPath: String? = null
    private var pendingOpenFailed: String? = null

    // --- Picture-in-picture remote action state ---
    private var pipPlaying = true
    private var pipReceiverRegistered = false

    companion object {
        private const val ACTION_PIP_TOGGLE = "com.example.maxplayer.action.PIP_TOGGLE"
        private const val REQ_PIP_TOGGLE = 42
        private val STREAM_SCHEMES = setOf("http", "https", "rtsp", "rtmp", "mms")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getMetadata" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_args", "path argument is required", null)
                    } else {
                        executor.execute {
                            val data = extractMetadata(path)
                            mainHandler.post { result.success(data) }
                        }
                    }
                }
                "settingsGetAll" -> {
                    val prefs = getSharedPreferences("maxplayer_settings", MODE_PRIVATE)
                    val map = HashMap<String, String>()
                    for ((k, v) in prefs.all) {
                        if (v is String) map[k] = v
                    }
                    result.success(map)
                }
                "settingsPut" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<String>("value")
                    if (key == null || value == null) {
                        result.error("bad_args", "key and value are required", null)
                    } else {
                        getSharedPreferences("maxplayer_settings", MODE_PRIVATE)
                            .edit().putString(key, value).apply()
                        result.success(true)
                    }
                }
                "getBrightness" -> {
                    // screenBrightness < 0 means "no override" (system default).
                    val b = window.attributes.screenBrightness
                    result.success(if (b < 0f) 1.0 else b.toDouble())
                }
                "setBrightness" -> {
                    // Clamp to [0.02, 1] so the screen can never go fully
                    // black and trap the user.
                    val v = (call.argument<Double>("value") ?: 1.0).coerceIn(0.02, 1.0)
                    val lp = window.attributes
                    lp.screenBrightness = v.toFloat()
                    window.attributes = lp
                    result.success(true)
                }
                "resetBrightness" -> {
                    val lp = window.attributes
                    lp.screenBrightness =
                        WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    window.attributes = lp
                    result.success(true)
                }
                "getInitialOpenVideo" -> {
                    val map = HashMap<String, String?>()
                    map["path"] = pendingOpenPath
                    map["failed"] = pendingOpenFailed
                    pendingOpenPath = null
                    pendingOpenFailed = null
                    result.success(map)
                }
                "enterPip" -> {
                    pipPlaying = call.argument<Boolean>("playing") ?: true
                    result.success(
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                ensurePipReceiver()
                                enterPictureInPictureMode(buildPipParams())
                                true
                            } else {
                                false
                            }
                        } catch (e: Exception) {
                            false
                        }
                    )
                }
                "setPipPlaying" -> {
                    pipPlaying = (call.arguments as? Boolean) ?: true
                    // Only refresh the action while actually in PiP; swapping
                    // the action replaces the default settings gear with our
                    // play/pause button.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        isInPictureInPictureMode
                    ) {
                        try {
                            // Swapping the action also REPLACES the default
                            // "settings" gear with our play/pause button.
                            setPictureInPictureParams(buildPipParams())
                        } catch (_: Exception) {
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        // Channel is ready: deliver anything that arrived before Dart attached.
        pendingOpenPath?.let {
            channel?.invokeMethod("onOpenVideo", it)
            pendingOpenPath = null
        }
        pendingOpenFailed?.let {
            channel?.invokeMethod("onOpenVideoFailed", it)
            pendingOpenFailed = null
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }

    // ---------------------------------------------------------------------------
    // PiP play/pause remote action
    // ---------------------------------------------------------------------------

    private fun buildPipParams(): PictureInPictureParams {
        val toggleIntent = PendingIntent.getBroadcast(
            this,
            REQ_PIP_TOGGLE,
            Intent(ACTION_PIP_TOGGLE).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val label = if (pipPlaying) "Pause" else "Play"
        val action =
            RemoteAction(makePipIcon(pause = pipPlaying), label, label, toggleIntent)
        return PictureInPictureParams.Builder().setActions(listOf(action)).build()
    }

    /** Draws a simple white play triangle / pause bars icon (no resources needed). */
    private fun makePipIcon(pause: Boolean): Icon {
        val size = 96
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        if (pause) {
            val barW = size * 0.18f
            val gap = size * 0.14f
            val top = size * 0.24f
            val bottom = size * 0.76f
            val left = (size - barW * 2 - gap) / 2f
            canvas.drawRect(left, top, left + barW, bottom, paint)
            canvas.drawRect(left + barW + gap, top, left + barW * 2 + gap, bottom, paint)
        } else {
            val path = Path()
            path.moveTo(size * 0.36f, size * 0.24f)
            path.lineTo(size * 0.74f, size * 0.5f)
            path.lineTo(size * 0.36f, size * 0.76f)
            path.close()
            canvas.drawPath(path, paint)
        }
        return Icon.createWithBitmap(bmp)
    }

    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_PIP_TOGGLE) {
                channel?.invokeMethod("onPipAction", "toggle")
            }
        }
    }

    private fun ensurePipReceiver() {
        if (pipReceiverRegistered) return
        pipReceiverRegistered = true
        val filter = IntentFilter(ACTION_PIP_TOGGLE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(pipReceiver, filter)
        }
    }

    // ---------------------------------------------------------------------------
    // "Open with" / "Share" handling
    // ---------------------------------------------------------------------------

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val uri: Uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data ?: return
            Intent.ACTION_SEND -> extractSendUri(intent) ?: return
            else -> return
        }
        val scheme = uri.scheme?.lowercase()
        when {
            // Network link: hand the URL to libmpv directly.
            scheme in STREAM_SCHEMES -> deliverOpen(uri.toString(), null)
            else -> {
                // Path resolution + possible stream copy hit the disk - keep
                // it off the main thread.
                executor.execute {
                    var resolved = resolveVideoPath(uri)
                    if (resolved == null && scheme == "content") {
                        resolved = copyContentToCache(uri)
                    }
                    mainHandler.post {
                        deliverOpen(resolved, if (resolved == null) uri.toString() else null)
                    }
                }
            }
        }
    }

    private fun deliverOpen(resolved: String?, failed: String?) {
        if (channel != null) {
            if (resolved != null) {
                channel?.invokeMethod("onOpenVideo", resolved)
            } else if (failed != null) {
                channel?.invokeMethod("onOpenVideoFailed", failed)
            }
        } else {
            // Dart side not attached yet - getInitialOpenVideo picks this up.
            if (resolved != null) pendingOpenPath = resolved
            else if (failed != null) pendingOpenFailed = failed
        }
    }

    @Suppress("DEPRECATION")
    private fun extractSendUri(intent: Intent): Uri? {
        val direct: Uri? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
        if (direct != null) return direct
        // A few apps stuff the Uri into ClipData instead of EXTRA_STREAM.
        val clip = intent.clipData
        if (clip != null && clip.itemCount > 0) {
            return clip.getItemAt(0).uri
        }
        return null
    }

    /**
     * Turns a content:// or file:// URI into a real filesystem path our
     * player (libmpv) can open. Strategies:
     *  1. file:// -> direct path
     *  2. MediaStore DATA column (we hold all-files access, so it answers)
     *  3. ExternalStorageProvider document URIs ("primary:Downloads/x.mp4")
     */
    private fun resolveVideoPath(uri: Uri): String? {
        when (uri.scheme) {
            "file" -> return uri.path
            "content" -> {
                // MediaStore / generic providers exposing the _data column.
                try {
                    contentResolver.query(
                        uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null
                    )?.use { c ->
                        if (c.moveToFirst()) {
                            val p = c.getString(0)
                            if (!p.isNullOrEmpty()) return p
                        }
                    }
                } catch (e: Exception) {
                    // fall through to document parsing
                }
                // content://com.android.externalstorage.documents/document/primary:Dir/x.mp4
                if (uri.authority == "com.android.externalstorage.documents") {
                    val doc = uri.lastPathSegment ?: return null
                    val parts = doc.split(":", limit = 2)
                    if (parts.size == 2) {
                        val decoded = Uri.decode(parts[1])
                        return if (parts[0].equals("primary", ignoreCase = true)) {
                            "/storage/emulated/0/$decoded"
                        } else {
                            // SD card style volumes: "1234-5678:Dir/x.mp4"
                            "/storage/${parts[0]}/$decoded"
                        }
                    }
                }
            }
        }
        return null
    }

    /**
     * Last-resort fallback for gallery/cloud URIs that expose no real path
     * (e.g. Google Photos mediakey URIs): stream the bytes into the app cache
     * and play the copy. Older copies are cleared out first so this cannot
     * grow unboundedly.
     */
    private fun copyContentToCache(uri: Uri): String? {
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

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    // ---------------------------------------------------------------------------
    // Metadata + thumbnails
    // ---------------------------------------------------------------------------

    /**
     * Extracts duration/dimensions and writes a thumbnail JPEG into the app
     * cache dir. Thumbnails are cached per video path and re-used while the
     * source file's mtime is older than the cached image, so rescanning the
     * library does NOT regenerate them every launch.
     */
    private fun extractMetadata(path: String): HashMap<String, Any?> {
        val out = HashMap<String, Any?>()
        out["thumbnailPath"] = null
        out["durationMs"] = null
        out["width"] = null
        out["height"] = null

        val videoFile = File(path)
        if (!videoFile.exists()) return out

        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val durationMs =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            out["durationMs"] = durationMs
            out["width"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            out["height"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()

            val thumbsDir = File(cacheDir, "thumbs").apply { mkdirs() }
            val thumbFile = File(thumbsDir, md5(path) + ".jpg")

            val cacheValid =
                thumbFile.exists() && thumbFile.length() > 0 &&
                    thumbFile.lastModified() >= videoFile.lastModified()

            if (cacheValid) {
                out["thumbnailPath"] = thumbFile.absolutePath
            } else {
                // Grab a frame ~1s in (or the very first frame for tiny clips).
                val seekUs = if (durationMs != null && durationMs in 0..1500) 0L else 1_000_000L
                val frame =
                    retriever.getFrameAtTime(seekUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                if (frame != null) {
                    val scaled = scaleToWidth(frame, 320)
                    FileOutputStream(thumbFile).use { fos ->
                        scaled.compress(Bitmap.CompressFormat.JPEG, 82, fos)
                    }
                    if (scaled !== frame) scaled.recycle()
                    frame.recycle()
                    out["thumbnailPath"] = thumbFile.absolutePath
                } else {
                    thumbFile.delete() // don't keep a stale/broken cache entry
                }
            }
        } catch (e: Exception) {
            // Unparseable / inaccessible file -> return nulls, Dart side shows
            // the generic placeholder icon.
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
        return out
    }

    private fun scaleToWidth(src: Bitmap, targetWidth: Int): Bitmap {
        if (src.width <= targetWidth) return src
        val targetHeight =
            (src.height * (targetWidth.toFloat() / src.width)).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, targetWidth, targetHeight, true)
    }

    private fun md5(s: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(s.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    override fun onDestroy() {
        if (pipReceiverRegistered) {
            try {
                unregisterReceiver(pipReceiver)
            } catch (_: Exception) {
            }
            pipReceiverRegistered = false
        }
        executor.shutdown()
        super.onDestroy()
    }
}
EOF_MARKER_MAINACTIVITY

echo ""
echo "==> Done! Now run:"
echo "    git add -A && git commit -m \"hotfix: rename to setPictureInPictureParams (build fix)\" && git pusH
