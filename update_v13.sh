#!/bin/bash
# ============================================================
# Max Player - UPDATE v13 (2026-08-12) : TARGETED FIXES ONLY
# ============================================================
# Only the files that actually changed (6). Nothing else touched.
#
# FIX 1 - VOLUME CAN'T REACH FULL (device volume starts low):
#   The swipe used to drive the APP-internal mpv volume, which sits
#   ON TOP of the device media volume (mpv 100% x device 20% is
#   still quiet). Now the swipe drives the DEVICE media volume
#   directly via AudioManager (MX Player / VLC style) and reads the
#   real level when the player opens, so 100% on screen = 100% real
#   loudness. Mute button also drives it. (kotlin + bridge + state)
#
# FIX 2 - AI SUBTITLES "ONLY MUSIC" / BAD EXTRACTION:
#   a) Samsung/Qualcomm AAC decoders output 32-bit FLOAT PCM, but the
#      resampler assumed 16-bit -> whisper heard noise and wrote "music"
#      captions. The extractor now reads the decoder's OUTPUT format and
#      normalizes float / 32-bit / 24-bit PCM to 16-bit. (kotlin)
#   b) whisper was running with its default (English-leaning) language:
#      now explicitly language="auto" so Hindi/Urdu/etc. are detected.
#      (kotlin)
#   c) Default model upgraded tiny -> base (~142 MB one-time download):
#      tiny is too weak for multilingual speech. (dart)
#
# HOW TO USE (on the Pi):
#   cd ~/IdeaProjects/maxplayer
#   nano update_v13.sh     # paste this whole file, save & exit
#   bash update_v13.sh
#   git add -A && git commit -m "v13: device-volume swipe, AI PCM/language/model fixes" && git push
# ============================================================
set -e
cd "$(dirname "$0")"
echo "==> Applying Max Player v13 fixes..."

cat > 'android/app/src/main/kotlin/com/example/maxplayer/MainActivity.kt' <<'EOF_MARKER_0'
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
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.WindowManager
import dev.ffmpegkit.whisper.Whisper
import dev.ffmpegkit.whisper.WhisperConfig
import dev.ffmpegkit.whisper.WhisperModel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.Executors
import kotlin.math.roundToInt
import kotlin.math.min
import kotlinx.coroutines.runBlocking

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

    // --- AI subtitles job state ---
    @Volatile
    private var aiCancelled = false
    private var aiJobCounter = 0

    // --- DLNA casting: multicast lock held during SSDP discovery ---
    private var multicastLock: WifiManager.MulticastLock? = null

    /** Thrown by the model downloader when the user cancels the job. */
    private class AiCancelledException : Exception("cancelled")

    companion object {
        private const val ACTION_PIP_TOGGLE = "com.example.maxplayer.action.PIP_TOGGLE"
        private const val REQ_PIP_TOGGLE = 42
        private const val REQ_PIP_OPEN = 43
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
                "getMediaVolume" -> {
                    // DEVICE media volume (the player's swipe drives this,
                    // like MX Player/VLC, so it can always reach the phone's
                    // true maximum loudness).
                    try {
                        val am =
                            getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            .coerceAtLeast(1)
                        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                        result.success(hashMapOf("level" to cur, "max" to max))
                    } catch (e: Exception) {
                        result.error("volume", e.message, null)
                    }
                }
                "setMediaVolume" -> {
                    try {
                        val v = (call.argument<Double>("value") ?: 0.75)
                            .coerceIn(0.0, 1.0)
                        val am =
                            getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            .coerceAtLeast(1)
                        am.setStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            (v * max).roundToInt().coerceIn(0, max),
                            0
                        )
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
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
                "whisperAvailable" -> {
                    // AI SUBTITLES Phase-1 probe: proves the on-device
                    // whisper.cpp engine loaded its native library on this
                    // device. Runs off the main thread (first call may load
                    // libwhisper.so).
                    executor.execute {
                        val info = try {
                            Whisper.getSystemInfo()
                        } catch (t: Throwable) {
                            null
                        }
                        mainHandler.post { result.success(info) }
                    }
                }
                "aiModelStatus" -> {
                    // Which models are already on disk, with size in MB.
                    val map = HashMap<String, Any>()
                    for (name in listOf("tiny", "base", "small")) {
                        val f = modelFileFor(name)
                        map[name] = if (f.exists() && f.length() > 1_000_000) {
                            (f.length() / (1024 * 1024)).toInt()
                        } else {
                            0
                        }
                    }
                    result.success(map)
                }
                "aiSubtitleGenerate" -> {
                    val videoPath = call.argument<String>("videoPath")
                    val model = call.argument<String>("model") ?: "tiny"
                    if (videoPath.isNullOrEmpty()) {
                        result.error("bad_args", "videoPath is required", null)
                    } else {
                        aiCancelled = false
                        val jobId = ++aiJobCounter
                        executor.execute { runAiPipeline(jobId, videoPath, model) }
                        result.success(jobId)
                    }
                }
                "aiSubtitleCancel" -> {
                    aiCancelled = true
                    result.success(true)
                }
                "scanFile" -> {
                    // Register a freshly-written file (screenshot, AI .srt)
                    // with the media scanner so gallery apps see it at once.
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_args", "path is required", null)
                    } else {
                        try {
                            MediaScannerConnection.scanFile(
                                applicationContext, arrayOf(path), null, null
                            )
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                "setMulticastLock" -> {
                    // DLNA casting: SSDP multicast discovery needs a Wi-Fi
                    // multicast lock on many devices; Dart holds it while a
                    // device scan runs and releases it afterwards.
                    val hold = call.arguments as? Boolean ?: false
                    try {
                        if (hold) {
                            if (multicastLock == null) {
                                val wm =
                                    applicationContext.getSystemService(Context.WIFI_SERVICE)
                                        as WifiManager
                                multicastLock = wm.createMulticastLock("maxplayer_cast")
                                multicastLock?.setReferenceCounted(true)
                            }
                            multicastLock?.acquire()
                        } else {
                            if (multicastLock?.isHeld == true) multicastLock?.release()
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
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
        val toggle = RemoteAction(makePipIcon(pause = pipPlaying), label, label, toggleIntent)
        // Second action: pop the PiP window back into the full app. Filling
        // the action tray with OUR buttons replaces any default system
        // "settings" gear the launcher would otherwise show.
        val openIntent = PendingIntent.getActivity(
            this,
            REQ_PIP_OPEN,
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val open = RemoteAction(makeExpandIcon(), "Open Max Player", "Open Max Player", openIntent)
        return PictureInPictureParams.Builder()
            .setActions(listOf(toggle, open))
            .build()
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

    /** Draws a white "expand" glyph (inner square + outward arrow). */
    private fun makeExpandIcon(): Icon {
        val size = 96
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = size * 0.07f
            strokeCap = Paint.Cap.ROUND
        }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        // Inner square.
        val inset = size * 0.28f
        canvas.drawRect(inset, inset, size - inset, size - inset, paint)
        // Outward diagonal arrow (top-right).
        val ax = size * 0.58f
        val ay = size * 0.42f
        canvas.drawLine(ax - size * 0.12f, ay + size * 0.12f, ax, ay, paint)
        val arrowHead = Path()
        arrowHead.moveTo(ax - size * 0.13f, ay - size * 0.02f)
        arrowHead.lineTo(ax + size * 0.02f, ay - size * 0.02f)
        arrowHead.lineTo(ax + size * 0.02f, ay + size * 0.13f)
        arrowHead.close()
        canvas.drawPath(arrowHead, fill)
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
        out["bitrate"] = null
        out["codec"] = null

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
            out["bitrate"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull()
            // Video codec from the container's video track MIME (works on all API levels).
            out["codec"] = detectVideoCodec(path)

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

    /**
     * Reads the first video track's MIME type from the container and maps it to a
     * friendly codec name (e.g. "video/hevc" -> "H.265 (HEVC)"). Returns null when
     * the file has no video track or cannot be parsed.
     */
    private fun detectVideoCodec(path: String): String? {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(path)
            var mime: String? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val trackMime =
                    if (format.containsKey(MediaFormat.KEY_MIME)) {
                        format.getString(MediaFormat.KEY_MIME)
                    } else {
                        null
                    }
                if (trackMime != null && trackMime.startsWith("video/")) {
                    mime = trackMime
                    break
                }
            }
            mime?.let { friendlyCodec(it) }
        } catch (_: Exception) {
            null
        } finally {
            extractor.release()
        }
    }

    private fun friendlyCodec(mime: String): String {
        return when (mime.lowercase()) {
            "video/avc", "video/h264" -> "H.264 (AVC)"
            "video/hevc", "video/h265" -> "H.265 (HEVC)"
            "video/av01" -> "AV1"
            "video/x-vnd.on2.vp8" -> "VP8"
            "video/x-vnd.on2.vp9" -> "VP9"
            "video/mp4v-es" -> "MPEG-4"
            "video/3gpp" -> "H.263"
            "video/mpeg2" -> "MPEG-2"
            "video/x-msvideo" -> "AVI"
            else -> mime.removePrefix("video/").uppercase()
        }
    }

    // ---------------------------------------------------------------------------
    // AI subtitles pipeline (Phases 2+3)
    //
    //   video -> [MediaExtractor + MediaCodec] 16 kHz mono WAV
    //         -> whisper.cpp (offline) -> timestamped segments -> Dart
    //
    // Dart builds the .srt text (pure, unit-tested) and mpv loads it via
    // `sub-add`. The model is downloaded once from Hugging Face (~75 MB for
    // tiny); after that everything is offline & free.
    // ---------------------------------------------------------------------------

    private fun modelFileFor(name: String): File {
        val safe = when (name) {
            "base", "small" -> name
            else -> "tiny"
        }
        return File(filesDir, "models/ggml-$safe.bin")
    }

    private fun modelUrlFor(name: String): String {
        return when (name) {
            "base" ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
            "small" ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
            else ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
        }
    }

    private fun aiProgress(jobId: Int, stage: String, percent: Int) {
        mainHandler.post {
            channel?.invokeMethod(
                "onAiProgress",
                hashMapOf("job" to jobId, "stage" to stage, "percent" to percent)
            )
        }
    }

    private fun aiDone(jobId: Int, segments: ArrayList<HashMap<String, Any>>) {
        mainHandler.post {
            channel?.invokeMethod(
                "onAiSubtitleDone",
                hashMapOf("job" to jobId, "segments" to segments)
            )
        }
    }

    private fun aiFailed(jobId: Int, message: String) {
        mainHandler.post {
            channel?.invokeMethod(
                "onAiSubtitleFailed",
                hashMapOf("job" to jobId, "message" to message)
            )
        }
    }

    private fun runAiPipeline(jobId: Int, videoPath: String, modelName: String) {
        try {
            // 1. Model file (one-time download).
            val modelFile = modelFileFor(modelName)
            if (!modelFile.exists() || modelFile.length() < 1_000_000) {
                aiProgress(jobId, "downloading", 0)
                val dlError = try {
                    downloadModel(modelUrlFor(modelName), modelFile, jobId)
                    null
                } catch (e: AiCancelledException) {
                    "cancelled"
                } catch (e: Exception) {
                    (e.message ?: "network error").take(80)
                }
                if (dlError != null) {
                    modelFile.delete()
                    aiFailed(
                        jobId,
                        if (dlError == "cancelled") "cancelled"
                        else "Model download failed ($dlError) - internet is needed once; after that AI subtitles work fully offline."
                    )
                    return
                }
            }
            if (aiCancelled) return aiFailed(jobId, "cancelled")

            // 2. Extract audio track -> 16 kHz mono WAV.
            aiProgress(jobId, "extracting", 0)
            val wav = File(cacheDir, "ai_audio_$jobId.wav")
            if (!extractAudioToWav(videoPath, wav, jobId)) {
                wav.delete()
                aiFailed(
                    jobId,
                    if (aiCancelled) "cancelled" else "Could not read the audio track of this file."
                )
                return
            }
            if (aiCancelled) {
                wav.delete()
                return aiFailed(jobId, "cancelled")
            }

            // 3. Transcribe with whisper.cpp (offline). NOTE: this stage
            // cannot be cancelled mid-run; a cancel during it discards the
            // result afterwards.
            aiProgress(jobId, "transcribing", 0)
            val segments = ArrayList<HashMap<String, Any>>()
            runBlocking {
                var model: WhisperModel? = null
                try {
                    model = Whisper.loadModel(this@MainActivity, modelFile.absolutePath)
                    // "auto" = detect the spoken language (Hindi/Urdu/
                    // English/...). Without this the default leans English
                    // and non-English speech degrades into stray captions.
                    val res = Whisper.transcribe(
                        model,
                        wav.absolutePath,
                        WhisperConfig(language = "auto")
                    )
                    for (s in res.segments) {
                        val text = s.text.trim()
                        if (text.isEmpty()) continue
                        segments.add(
                            hashMapOf(
                                "start" to s.startMs as Any,
                                "end" to s.endMs as Any,
                                "text" to text as Any
                            )
                        )
                    }
                } finally {
                    model?.let { Whisper.releaseModel(it) }
                }
            }
            wav.delete()
            if (aiCancelled) return aiFailed(jobId, "cancelled")
            aiDone(jobId, segments)
        } catch (t: Throwable) {
            aiFailed(jobId, t.message ?: "AI subtitle generation failed")
        }
    }

    /**
     * Downloads [url] into [dest] via a ".part" temp file. Redirects are
     * followed MANUALLY: huggingface.co /resolve/ URLs answer with a 302 to
     * a CDN host, and relying on HttpURLConnection's automatic redirect
     * handling has proven unreliable across Android versions. Progress is
     * reported as the "downloading" stage.
     *
     * Throws [AiCancelledException] when the user cancels, and
     * [java.io.IOException] with a short machine-readable reason otherwise,
     * so the failure snackbar can say WHAT went wrong.
     */
    private fun downloadModel(url: String, dest: File, jobId: Int) {
        dest.parentFile?.mkdirs()
        val tmp = File(dest.parentFile, dest.name + ".part")
        var conn: HttpURLConnection? = null
        try {
            var current = url
            var hops = 0
            while (true) {
                val c = URL(current).openConnection() as HttpURLConnection
                conn = c
                c.connectTimeout = 20000
                c.readTimeout = 30000
                c.instanceFollowRedirects = false
                c.setRequestProperty("User-Agent", "MaxPlayer/1.0 (Android)")
                c.connect()
                val code = c.responseCode
                if (code in 300..399) {
                    val loc = c.getHeaderField("Location")
                    c.disconnect()
                    if (loc == null || ++hops > 6) {
                        throw java.io.IOException("redirect failed (HTTP $code)")
                    }
                    // Handles both absolute and relative Location headers.
                    current = URL(URL(current), loc).toString()
                    continue
                }
                if (code !in 200..299) {
                    c.disconnect()
                    throw java.io.IOException("HTTP $code")
                }
                break
            }
            val c = conn ?: throw java.io.IOException("no connection")
            val total = c.contentLengthLong
            c.inputStream.use { input ->
                FileOutputStream(tmp).use { out ->
                    val buf = ByteArray(256 * 1024)
                    var done = 0L
                    var read: Int
                    while (input.read(buf).also { read = it } != -1) {
                        if (aiCancelled) throw AiCancelledException()
                        out.write(buf, 0, read)
                        done += read
                        if (total > 0) {
                            aiProgress(jobId, "downloading", (done * 100 / total).toInt())
                        }
                    }
                    if (total > 0 && done != total) {
                        throw java.io.IOException("incomplete download")
                    }
                }
            }
            c.disconnect()
            if (!tmp.renameTo(dest)) {
                tmp.copyTo(dest, overwrite = true)
                tmp.delete()
            }
        } finally {
            if (tmp.exists()) tmp.delete()
        }
    }

    /**
     * Decodes the first audio track of [videoPath] to a 16 kHz mono 16-bit
     * PCM WAV using MediaExtractor + MediaCodec. Returns false if the file
     * has no (decodable) audio track.
     */
    private fun extractAudioToWav(videoPath: String, outFile: File, jobId: Int): Boolean {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var raf: RandomAccessFile? = null
        return try {
            extractor.setDataSource(videoPath)
            var trackIndex = -1
            var sampleRate = 44100
            var channels = 1
            var durationUs = 0L
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIndex = i
                    if (f.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    }
                    if (f.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                    if (f.containsKey(MediaFormat.KEY_DURATION)) {
                        durationUs = f.getLong(MediaFormat.KEY_DURATION)
                    }
                    codec = MediaCodec.createDecoderByType(mime)
                    codec!!.configure(f, null, null, 0)
                    break
                }
            }
            if (trackIndex < 0 || codec == null) return false
            extractor.selectTrack(trackIndex)
            codec!!.start()

            // The decoder's OUTPUT format is authoritative: it can differ
            // from the container's declared format AND it reveals the PCM
            // encoding. Many AAC decoders output 32-bit FLOAT PCM - feeding
            // those bytes to the 16-bit resampler produced noise, and
            // whisper answered noise with "music" captions.
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT
            try {
                val of = codec!!.outputFormat
                if (of.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                    sampleRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                }
                if (of.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                    channels = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                }
                if (of.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                    pcmEncoding = of.getInteger(MediaFormat.KEY_PCM_ENCODING)
                }
            } catch (_: Exception) {
            }

            raf = RandomAccessFile(outFile, "rw")
            raf.setLength(0)
            writeWavHeader(raf, 16000, 0) // placeholder, patched at the end
            var dataBytes = 0L

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            while (!outputDone) {
                if (aiCancelled) return false
                if (!inputDone) {
                    val idx = codec!!.dequeueInputBuffer(10_000)
                    if (idx >= 0) {
                        val buf = codec!!.getInputBuffer(idx)!!
                        val n = extractor.readSampleData(buf, 0)
                        if (n < 0) {
                            codec!!.queueInputBuffer(
                                idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            codec!!.queueInputBuffer(idx, 0, n, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIdx = codec!!.dequeueOutputBuffer(info, 10_000)
                if (outIdx >= 0) {
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                    if (info.size > 0) {
                        val outBuf = codec!!.getOutputBuffer(outIdx)!!
                        val pcm = ByteArray(info.size)
                        outBuf.get(pcm)
                        outBuf.clear()
                        val mono = pcmToMono16k(pcm, channels, sampleRate, pcmEncoding)
                        raf.write(mono)
                        dataBytes += mono.size
                        if (durationUs > 0 && info.presentationTimeUs > 0) {
                            aiProgress(
                                jobId,
                                "extracting",
                                (info.presentationTimeUs * 100 / durationUs)
                                    .toInt()
                                    .coerceIn(0, 99)
                            )
                        }
                    }
                    codec!!.releaseOutputBuffer(outIdx, false)
                }
            }
            writeWavHeader(raf, 16000, dataBytes) // real sizes
            true
        } catch (e: Exception) {
            false
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            try {
                codec?.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
            try {
                raf?.close()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Normalizes decoder PCM (any common encoding) to interleaved signed
     * 16-bit little-endian samples. Without this, FLOAT/32-bit decoder
     * output was interpreted as 16-bit, which sounds like noise - and
     * whisper transcribes noise as "music".
     */
    private fun pcmToShorts(pcm: ByteArray, encoding: Int): ShortArray {
        return when (encoding) {
            AudioFormat.ENCODING_PCM_FLOAT -> {
                val fb = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN)
                    .asFloatBuffer()
                ShortArray(fb.remaining()) { i ->
                    (fb.get(i).coerceIn(-1f, 1f) * 32767f).toInt().toShort()
                }
            }
            AudioFormat.ENCODING_PCM_32BIT -> {
                val n = pcm.size / 4
                ShortArray(n) { i ->
                    // Top two bytes of each 32-bit LE sample.
                    val hi = pcm[i * 4 + 3].toInt()
                    val mid = pcm[i * 4 + 2].toInt() and 0xFF
                    ((hi shl 8) or mid).toShort()
                }
            }
            AudioFormat.ENCODING_PCM_24BIT_PACKED -> {
                val n = pcm.size / 3
                ShortArray(n) { i ->
                    val hi = pcm[i * 3 + 2].toInt()
                    val mid = pcm[i * 3 + 1].toInt() and 0xFF
                    ((hi shl 8) or mid).toShort()
                }
            }
            else -> { // ENCODING_PCM_16BIT (and sane fallback)
                val n = pcm.size / 2
                ShortArray(n) { i ->
                    ((pcm[i * 2 + 1].toInt() shl 8) or
                        (pcm[i * 2].toInt() and 0xFF)).toShort()
                }
            }
        }
    }

    /**
     * Downmixes interleaved PCM to mono and resamples to 16 kHz using a
     * simple averaging window (good enough for speech).
     */
    private fun pcmToMono16k(
        pcm: ByteArray,
        channels: Int,
        srcRate: Int,
        encoding: Int
    ): ByteArray {
        if (channels < 1) return ByteArray(0)
        val samples = pcmToShorts(pcm, encoding)
        val frames = samples.size / channels
        if (frames == 0) return ByteArray(0)
        val step = srcRate.toDouble() / 16000.0
        val outCount = (frames / step).toInt()
        val out = ByteArray(outCount * 2)
        var pos = 0.0
        var o = 0
        while (o < outCount) {
            val startF = pos.toInt()
            val endF = min(frames, (pos + step).toInt() + 1)
            var sum = 0
            var cnt = 0
            var f = startF
            while (f < endF) {
                var mixed = 0
                for (ch in 0 until channels) {
                    mixed += samples[f * channels + ch]
                }
                sum += mixed / channels
                cnt++
                f++
            }
            val v = if (cnt > 0) sum / cnt else 0
            out[o * 2] = (v and 0xFF).toByte()
            out[o * 2 + 1] = ((v shr 8) and 0xFF).toByte()
            o++
            pos += step
        }
        return out
    }

    /** Writes a standard PCM WAV header (44 bytes) at the current position 0. */
    private fun writeWavHeader(raf: RandomAccessFile, rate: Int, dataLen: Long) {
        fun intLe(v: Long) = byteArrayOf(
            (v and 0xFF).toByte(),
            ((v shr 8) and 0xFF).toByte(),
            ((v shr 16) and 0xFF).toByte(),
            ((v shr 24) and 0xFF).toByte()
        )

        fun shortLe(v: Int) = byteArrayOf(
            (v and 0xFF).toByte(),
            ((v shr 8) and 0xFF).toByte()
        )

        raf.seek(0)
        raf.writeBytes("RIFF")
        raf.write(intLe(36 + dataLen))
        raf.writeBytes("WAVE")
        raf.writeBytes("fmt ")
        raf.write(intLe(16)) // PCM fmt chunk size
        raf.write(shortLe(1)) // PCM format
        raf.write(shortLe(1)) // mono
        raf.write(intLe(rate.toLong()))
        raf.write(intLe(rate.toLong() * 2)) // byte rate
        raf.write(shortLe(2)) // block align
        raf.write(shortLe(16)) // bit depth
        raf.writeBytes("data")
        raf.write(intLe(dataLen))
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
EOF_MARKER_0

cat > 'lib/services/native_bridge.dart' <<'EOF_MARKER_1'
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

  const VideoMetadata({
    this.duration,
    this.thumbnailPath,
    this.width,
    this.height,
    this.bitrateBps,
    this.codec,
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
  static bool _handlerRegistered = false;

  /// Registers (or replaces) the app-level native event callbacks.
  static void configureCallbacks({
    void Function(String path)? onOpenVideo,
    void Function(String uri)? onOpenVideoFailed,
    void Function(bool isPip)? onPipChanged,

    /// Fired when the play/pause button ON THE PiP WINDOW is tapped.
    void Function()? onPipAction,

    /// AI subtitle job events (see [aiSubtitleGenerate]).
    void Function(String stage, int percent)? onAiProgress,
    void Function(List<AiSegment> segments)? onAiDone,
    void Function(String error)? onAiFailed,
  }) {
    if (onOpenVideo != null) _onOpenVideo = onOpenVideo;
    if (onOpenVideoFailed != null) _onOpenVideoFailed = onOpenVideoFailed;
    if (onPipChanged != null) _onPipChanged = onPipChanged;
    if (onPipAction != null) _onPipAction = onPipAction;
    if (onAiProgress != null) _onAiProgress = onAiProgress;
    if (onAiDone != null) _onAiDone = onAiDone;
    if (onAiFailed != null) _onAiFailed = onAiFailed;
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
      return VideoMetadata(
        duration: durationMs is int ? Duration(milliseconds: durationMs) : null,
        thumbnailPath: res['thumbnailPath'] as String?,
        width: width is int ? width : null,
        height: height is int ? height : null,
        bitrateBps: bitrate is int ? bitrate : null,
        codec: res['codec'] as String?,
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
      final res =
          await _channel.invokeMethod<Map<Object?, Object?>>('getMediaVolume');
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
      await _channel
          .invokeMethod('setMediaVolume', {'value': value.clamp(0.0, 1.0)});
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

  // --- AI subtitles (Phase 1 probe) ---

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

  // --- AI subtitles pipeline (Phases 2+3) ---

  /// Which models are present on device. Returns {tiny: MB, base: MB,
  /// small: MB}; 0 MB means "not downloaded yet".
  static Future<Map<String, int>> aiModelStatus() async {
    try {
      final res = await _channel
          .invokeMethod<Map<Object?, Object?>>('aiModelStatus');
      if (res == null) return const {};
      return res.map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return const {};
    }
  }

  /// Starts the offline AI subtitle job for [videoPath]. Returns the job id
  /// immediately; progress/completion arrive via [configureCallbacks]
  /// (`onAiProgress` / `onAiDone` / `onAiFailed`).
  static Future<int?> aiSubtitleGenerate({
    required String videoPath,
    String model = 'tiny',
  }) async {
    try {
      return await _channel.invokeMethod<int>(
        'aiSubtitleGenerate',
        {'videoPath': videoPath, 'model': model},
      );
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

  /// Holds/releases the Wi-Fi multicast lock used during DLNA (SSDP)
  /// device discovery. [hold] true = acquire, false = release.
  static Future<void> setMulticastLock(bool hold) async {
    try {
      await _channel.invokeMethod('setMulticastLock', hold);
    } catch (_) {}
  }
}
EOF_MARKER_1

cat > 'lib/state/media_player_state.dart' <<'EOF_MARKER_2'
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:media_kit_video/media_kit_video.dart';

import '../models/history_entry.dart';
import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../utils/formatters.dart';
import 'player_settings.dart';

/// Mirrors the web app's useMediaPlayer hook, backed by media_kit's Player.
class MediaPlayerState extends ChangeNotifier {
  final Player player = Player();

  /// ONE video controller for the app's lifetime, created lazily.
  /// PlayerScreen used to construct a new VideoController on every visit and
  /// (with media_kit_video 1.3.x having no public dispose) those stacked up
  /// on the same player - one source of the fullscreen glitches.
  late final VideoController videoController = VideoController(player);

  List<VideoTrack> playlist = [];
  int currentIndex = 0;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 0.75; // 0..1
  bool isMuted = false;
  double playbackRate = 1.0;
  RepeatMode repeatMode = RepeatMode.none;
  bool isShuffled = false;
  bool isLoading = false;
  List<int> _shuffledOrder = [];

  // Available tracks of the currently loaded media (populated from streams).
  List<AudioTrack> audioTracks = [];
  List<SubtitleTrack> subtitleTracks = [];
  AudioTrack? currentAudioTrack;
  SubtitleTrack? currentSubtitleTrack;

  /// Short user-facing notices ("Resumed 12:34" etc) - the player screen
  /// shows these as a transient overlay indicator.
  final _notices = StreamController<String>.broadcast();
  Stream<String> get notices => _notices.stream;

  /// Periodic bookmark saver ("resume from where you left off").
  Timer? _bookmarkTimer;

  /// Last-used app-local brightness (left-half swipe in the player).
  double brightness = 1.0;
  bool _brightnessSynced = false;

  // --- A-B loop ---
  Duration? loopA;
  Duration? loopB;
  bool get abLoopActive => loopA != null && loopB != null;

  // --- Long-press speed boost ---
  double? _preBoostRate;

  /// True while the long-press speed boost is engaged; the player shows a
  /// persistent "Nx" badge for the whole boost, not just a flash.
  bool get isSpeedBoosting => _preBoostRate != null;

  // --- Equalizer (libmpv lavfi filter chain) ---
  static const List<int> eqFrequencies = [60, 230, 910, 3600, 14000];
  List<double> eqGains = List.filled(eqFrequencies.length, 0);
  bool eqEnabled = false;

  // --- Watch-time stats ---
  int _watchTodaySecs = 0;
  String _todayStatsKey = '';

  // --- Watch history (drives the home History screen + resume playback) ---
  final List<HistoryEntry> _history = [];
  bool _historyLoaded = false;
  static const String _kHistoryKey = 'history';
  static const int _kHistoryMax = 150;

  List<HistoryEntry> get history => List.unmodifiable(_history);

  VideoTrack? get currentTrack =>
      playlist.isNotEmpty && currentIndex < playlist.length
      ? playlist[currentIndex]
      : null;

  final _rand = Random();
  late final List<StreamSubscription> _subs;

  MediaPlayerState() {
    _subs = [
      player.stream.playing.listen((v) {
        isPlaying = v;
        notifyListeners();
        // Keep the PiP window's play/pause remote action in sync
        // (native side ignores this when not in PiP).
        NativeBridge.setPipPlaying(v);
      }),
      player.stream.position.listen((v) {
        position = v;
        // Enforce the A-B loop window.
        final a = loopA;
        final b = loopB;
        if (a != null && b != null && b > a && v >= b) {
          player.seek(a);
        }
        notifyListeners();
      }),
      player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
      }),
      player.stream.buffering.listen((v) {
        isLoading = v;
        notifyListeners();
      }),
      player.stream.completed.listen((completed) {
        if (completed) _handleEnded();
      }),
      // Repopulates whenever a new media is opened.
      player.stream.tracks.listen((t) {
        audioTracks = t.audio;
        subtitleTracks = t.subtitle;
        notifyListeners();
      }),
      player.stream.track.listen((t) {
        currentAudioTrack = t.audio;
        currentSubtitleTrack = t.subtitle;
        notifyListeners();
      }),
    ];
    // libmpv stays at 100%: loudness is driven by the DEVICE media volume
    // (MX Player / VLC style) so the swipe can always reach the phone's
    // true maximum, no matter where the system volume started.
    player.setVolume(100);
    // Play/pause from the picture-in-picture window's own button.
    NativeBridge.configureCallbacks(onPipAction: togglePlay);
    _init();
    // Persist the resume point + watch time every few seconds.
    _bookmarkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveBookmark();
      _trackWatchTime();
    });
  }

  Future<void> _init() async {
    await _ensureHistoryLoaded();
    final s = await NativeBridge.loadSettings();
    // Restore today's accumulated watch time.
    _todayStatsKey = statsKeyFor(DateTime.now());
    _watchTodaySecs = int.tryParse(s[_todayStatsKey] ?? '') ?? 0;
    // Restore equalizer.
    eqEnabled = s[_kEqEnabledKey] == 'true';
    final gainsRaw = (s[_kEqGainsKey] ?? '').split(',');
    for (var i = 0; i < eqFrequencies.length && i < gainsRaw.length; i++) {
      eqGains[i] = double.tryParse(gainsRaw[i]) ?? 0;
    }
    if (eqEnabled) _applyEqFilter();
  }

  // ---------------------------------------------------------------------------
  // Watch history
  // ---------------------------------------------------------------------------

  Future<void> _ensureHistoryLoaded() async {
    if (_historyLoaded) return;
    _historyLoaded = true;
    try {
      final s = await NativeBridge.loadSettings();
      final raw = s[_kHistoryKey];
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _history
        ..clear()
        ..addAll([
          for (final e in list)
            HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        ]);
      notifyListeners();
    } catch (_) {
      // Corrupt payload -> start with an empty history.
    }
  }

  void _persistHistory() {
    final capped = _history.length > _kHistoryMax
        ? _history.sublist(0, _kHistoryMax)
        : _history;
    NativeBridge.saveSetting(
      _kHistoryKey,
      jsonEncode([for (final e in capped) e.toJson()]),
    );
  }

  HistoryEntry? _historyEntryFor(String path) {
    for (final e in _history) {
      if (e.path == path) return e;
    }
    return null;
  }

  /// Move the just-opened video to the top of the history, preserving its
  /// previous resume position.
  Future<void> _recordOpen(VideoTrack track) async {
    try {
      await _ensureHistoryLoaded();
      final prevPos = _historyEntryFor(track.path)?.lastPositionSecs ?? 0;
      _history.removeWhere((e) => e.path == track.path);
      _history.insert(
        0,
        HistoryEntry(
          path: track.path,
          title: track.title,
          thumbnailPath: track.thumbnailPath,
          durationSecs: track.duration?.inSeconds ?? 0,
          lastPositionSecs: prevPos,
          playedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _persistHistory();
      notifyListeners();
    } catch (_) {}
  }

  void clearHistory() {
    _history.clear();
    _persistHistory();
    notifyListeners();
  }

  void removeHistoryEntry(String path) {
    _history.removeWhere((e) => e.path == path);
    _persistHistory();
    notifyListeners();
  }

  /// Play a single video straight from a history row.
  Future<void> playHistoryEntry(HistoryEntry entry) async {
    final track = VideoTrack(
      id: entry.path,
      title: entry.title,
      path: entry.path,
      thumbnailPath: entry.thumbnailPath,
      duration: entry.durationSecs > 0
          ? Duration(seconds: entry.durationSecs)
          : null,
    );
    await setPlaylistAndPlay([track], 0);
  }

  /// Play a network stream URL (http/https/rtsp/rtmp). Handled directly by
  /// libmpv - the local-file metadata pipeline is skipped upstream.
  Future<void> playStream(String url, String title) async {
    final track = VideoTrack(id: url, title: title, path: url);
    await setPlaylistAndPlay([track], 0);
  }

  List<int> _generateShuffledOrder(int length, int currentIdx) {
    final indices = List.generate(length, (i) => i)..remove(currentIdx);
    indices.shuffle(_rand);
    return [currentIdx, ...indices];
  }

  int _getNextIndex({required bool forward}) {
    if (playlist.isEmpty) return 0;
    if (isShuffled && _shuffledOrder.isNotEmpty) {
      final pos = _shuffledOrder.indexOf(currentIndex);
      final len = _shuffledOrder.length;
      return forward
          ? _shuffledOrder[(pos + 1) % len]
          : _shuffledOrder[(pos - 1 + len) % len];
    }
    final len = playlist.length;
    return forward ? (currentIndex + 1) % len : (currentIndex - 1 + len) % len;
  }

  /// Replace the whole queue and start playing at [startIndex].
  Future<void> setPlaylistAndPlay(
    List<VideoTrack> videos, [
    int startIndex = 0,
  ]) async {
    playlist = videos;
    currentIndex = startIndex.clamp(0, videos.isEmpty ? 0 : videos.length - 1);
    notifyListeners();
    await _loadCurrent(autoplay: true);
  }

  Future<void> playTrack(int index) async {
    if (index < 0 || index >= playlist.length) return;
    currentIndex = index;
    notifyListeners();
    await _loadCurrent(autoplay: true);
  }

  Future<void> _loadCurrent({required bool autoplay}) async {
    final track = currentTrack;
    if (track == null) return;
    // A new file invalidates any A-B loop points from the previous one.
    loopA = null;
    loopB = null;
    await player.open(Media(track.path), play: autoplay);
    await player.setRate(playbackRate);
    await _recordOpen(track);
    await _restoreBookmark(track);
  }

  /// Jump to where the user left off last time this file was open. The saved
  /// position lives in the watch history; honours the "Resume playback"
  /// player setting.
  Future<void> _restoreBookmark(VideoTrack track) async {
    try {
      final settings = await NativeBridge.loadSettings();
      if (settings[PlayerSettings.kResumePlayback] == 'false') return;
      final secs = _historyEntryFor(track.path)?.lastPositionSecs ?? 0;
      if (secs < 10) return; // ignore tiny offsets

      var d = duration;
      if (d == Duration.zero) {
        // Wait briefly for the demuxer to report the length.
        d = await player.stream.duration
            .firstWhere((v) => v > Duration.zero)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => Duration.zero,
            );
      }
      if (d == Duration.zero) return;
      // Almost-finished videos start from the beginning again.
      if (secs >= d.inSeconds - 15) {
        final e = _historyEntryFor(track.path);
        if (e != null) {
          e.lastPositionSecs = 0;
          _persistHistory();
        }
        return;
      }
      // User may have switched tracks while we waited.
      if (currentTrack?.path != track.path) return;
      await player.seek(Duration(seconds: secs));
      _notices.add('Resumed ${formatDuration(Duration(seconds: secs))}');
    } catch (_) {
      // Resume is best-effort.
    }
  }

  void _saveBookmark() {
    final track = currentTrack;
    if (track == null || !isPlaying) return;
    final secs = position.inSeconds;
    if (secs <= 0) return;
    final entry = _historyEntryFor(track.path);
    if (entry != null && entry.lastPositionSecs != secs) {
      entry.lastPositionSecs = secs;
      _persistHistory();
    }
  }

  // ---------------------------------------------------------------------------
  // Brightness (left-half swipe in the player)
  // ---------------------------------------------------------------------------

  /// Reads the current override once so the first drag starts from the real
  /// screen brightness instead of a guess.
  Future<double> currentBrightness() async {
    if (!_brightnessSynced) {
      brightness = await NativeBridge.getBrightness();
      _brightnessSynced = true;
      notifyListeners();
    }
    return brightness;
  }

  Future<void> setBrightness(double v) async {
    brightness = v.clamp(0.0, 1.0);
    notifyListeners();
    await NativeBridge.setBrightness(brightness);
  }

  Future<void> resetBrightness() async {
    brightness = 1.0;
    _brightnessSynced = false;
    notifyListeners();
    await NativeBridge.resetBrightness();
  }

  Future<void> togglePlay() async {
    if (isPlaying) {
      await pause();
    } else {
      await player.play();
    }
  }

  /// Unconditional resume (used when handing playback back from a TV cast
  /// session - togglePlay would pause if the user already resumed).
  Future<void> resumePlayback() => player.play();

  /// Saves the CURRENT video frame exactly as shown (subtitles included)
  /// as a PNG into /storage/emulated/0/Pictures/Max Player and registers it
  /// with the media scanner so gallery apps see it immediately.
  ///
  /// Returns the saved path, or null when there is nothing to capture
  /// (no video, or a network stream) or the capture failed.
  Future<String?> captureScreenshot() async {
    final track = currentTrack;
    if (track == null) return null;
    if (track.path.startsWith('http')) return null; // stream: nothing on disk
    final platform = player.platform;
    if (platform is! NativePlayer) return null;
    try {
      final dir = Directory('/storage/emulated/0/Pictures/Max Player');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final out =
          '${dir.path}/MaxPlayer_${DateTime.now().millisecondsSinceEpoch}.png';
      // libmpv command; plain (non-async) screenshot-to-file blocks mpv's
      // core until the PNG is written, then we verify from Dart.
      await platform.command(['screenshot-to-file', out]);
      final f = File(out);
      for (var i = 0; i < 20; i++) {
        if (f.existsSync() && f.lengthSync() > 0) {
          await NativeBridge.scanFile(out);
          return out;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> pause() async {
    // Pausing always ends an active long-press boost (and its badge).
    await stopSpeedBoost();
    _saveBookmark();
    await player.pause();
  }

  Future<void> seek(Duration to) => player.seek(to);

  /// Relative seek (e.g. ±10s), clamped to the media bounds.
  Future<void> seekBy(int seconds) async {
    if (currentTrack == null) return;
    var target = position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await player.seek(target);
  }

  // ---------------------------------------------------------------------------
  // Volume (device MEDIA volume, MX Player / VLC style)
  // ---------------------------------------------------------------------------

  bool _volumeSynced = false;
  double _preMuteVolume = 0.5;

  /// Reads the real device media volume once so the player swipe starts
  /// from the true level (mirrors [currentBrightness]).
  Future<double> currentVolume() async {
    if (!_volumeSynced) {
      volume = await NativeBridge.getMediaVolume();
      isMuted = volume <= 0;
      _volumeSynced = true;
      notifyListeners();
    }
    return volume;
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    if (volume > 0) {
      isMuted = false;
      _preMuteVolume = volume;
    }
    await NativeBridge.setMediaVolume(isMuted ? 0 : volume);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    if (isMuted) {
      isMuted = false;
      if (volume <= 0) volume = _preMuteVolume;
      await NativeBridge.setMediaVolume(volume);
    } else {
      if (volume > 0) _preMuteVolume = volume;
      isMuted = true;
      await NativeBridge.setMediaVolume(0);
    }
    notifyListeners();
  }

  Future<void> setPlaybackRate(double rate) async {
    playbackRate = rate;
    await player.setRate(rate);
    notifyListeners();
  }

  /// Switch to a different audio track (e.g. Hindi / English in dual-audio
  /// files). Pass an entry of [audioTracks].
  void selectAudioTrack(AudioTrack track) => player.setAudioTrack(track);

  /// Switch subtitle track; pass SubtitleTrack.no() to turn subtitles off.
  void selectSubtitleTrack(SubtitleTrack track) =>
      player.setSubtitleTrack(track);

  /// True when a real subtitle track (not "no"/off) is currently active.
  bool get subtitlesActive =>
      currentSubtitleTrack != null && currentSubtitleTrack!.id != 'no';

  // ---------------------------------------------------------------------------
  // A-B loop
  // ---------------------------------------------------------------------------

  /// Button callback: 1st tap sets A, 2nd sets B (loop starts), 3rd clears.
  /// Returns a short message for the on-screen indicator.
  String tapLoopPoint() {
    if (loopA == null) {
      loopA = position;
      notifyListeners();
      return 'A set ${formatDuration(position)}';
    }
    if (loopB == null) {
      // Ignore a B that's not after A (user double-tapped by accident).
      if (position <= loopA! + const Duration(seconds: 1)) {
        loopA = position;
        notifyListeners();
        return 'A set ${formatDuration(position)}';
      }
      loopB = position;
      notifyListeners();
      return 'Looping ${formatDuration(loopA!)} → ${formatDuration(loopB!)}';
    }
    loopA = null;
    loopB = null;
    notifyListeners();
    return 'A-B loop cleared';
  }

  // ---------------------------------------------------------------------------
  // Long-press speed boost (customizable multiplier)
  // ---------------------------------------------------------------------------

  Future<void> startSpeedBoost(double multiplier) async {
    if (_preBoostRate != null) return; // already boosting
    if (!isPlaying) return; // no boost/badge while paused
    _preBoostRate = playbackRate;
    playbackRate = multiplier;
    await player.setRate(multiplier);
    notifyListeners();
  }

  Future<void> stopSpeedBoost() async {
    final restore = _preBoostRate;
    if (restore == null) return;
    _preBoostRate = null;
    playbackRate = restore;
    await player.setRate(restore);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Equalizer (libmpv `af` lavfi chain)
  // ---------------------------------------------------------------------------

  static const String _kEqEnabledKey = 'eq.enabled';
  static const String _kEqGainsKey = 'eq.gains';

  /// Builds the lavfi audio-filter chain, skipping bands at 0 dB.
  /// Pure + testable.
  static String buildEqualizerFilter(List<double> gains) {
    final parts = <String>[];
    for (var i = 0; i < eqFrequencies.length && i < gains.length; i++) {
      if (gains[i] == 0) continue;
      parts.add(
        'equalizer=f=${eqFrequencies[i]}:t=q:w=1.0:g=${gains[i].toStringAsFixed(1)}',
      );
    }
    return parts.isEmpty ? '' : 'lavfi=[${parts.join(',')}]';
  }

  Future<void> applyEqualizer(List<double> gains, bool enabled) async {
    eqGains = List.of(gains);
    eqEnabled = enabled;
    NativeBridge.saveSetting(_kEqEnabledKey, '$enabled');
    NativeBridge.saveSetting(
      _kEqGainsKey,
      gains.map((g) => g.toStringAsFixed(1)).join(','),
    );
    notifyListeners();
    await _applyEqFilter();
  }

  Future<void> _applyEqFilter() async {
    final platform = player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty(
          'af',
          eqEnabled ? buildEqualizerFilter(eqGains) : '',
        );
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Watch-time stats
  // ---------------------------------------------------------------------------

  /// Persisted key for a day bucket, e.g. stats.20260811. Pure + testable.
  static String statsKeyFor(DateTime d) =>
      'stats.${d.year * 10000 + d.month * 100 + d.day}';

  void _trackWatchTime() {
    if (!isPlaying) return;
    final key = statsKeyFor(DateTime.now());
    if (key != _todayStatsKey) {
      // Day rolled over while playing.
      _todayStatsKey = key;
      _watchTodaySecs = 0;
    }
    _watchTodaySecs += 5;
    NativeBridge.saveSetting(key, '$_watchTodaySecs');
  }

  /// Last 7 days of watch time (index 0 = 6 days ago, last = today).
  Future<List<WatchDay>> getWeekStats() async {
    final s = await NativeBridge.loadSettings();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    final days = <WatchDay>[];
    for (var i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = statsKeyFor(d);
      var secs = int.tryParse(s[key] ?? '') ?? 0;
      if (key == todayKey && _watchTodaySecs > secs) secs = _watchTodaySecs;
      days.add(WatchDay(d, secs));
    }
    return days;
  }

  // ---------------------------------------------------------------------------
  // Mini player
  // ---------------------------------------------------------------------------

  /// Dismisses the mini player: clears the queue and stops playback.
  Future<void> stopMini() async {
    playlist = [];
    currentIndex = 0;
    notifyListeners();
    await player.stop();
  }

  Future<void> nextTrack() async {
    if (playlist.length <= 1) return;
    await playTrack(_getNextIndex(forward: true));
  }

  Future<void> prevTrack() async {
    if (position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (playlist.length <= 1) return;
    await playTrack(_getNextIndex(forward: false));
  }

  void toggleRepeat() {
    repeatMode = switch (repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.none,
    };
    notifyListeners();
  }

  void toggleShuffle() {
    isShuffled = !isShuffled;
    if (isShuffled) {
      _shuffledOrder = _generateShuffledOrder(playlist.length, currentIndex);
    }
    notifyListeners();
  }

  Future<void> removeFromPlaylist(int index) async {
    final wasCurrent = index == currentIndex;
    playlist = [...playlist]..removeAt(index);
    if (playlist.isEmpty) {
      currentIndex = 0;
      await player.stop();
    } else if (wasCurrent) {
      currentIndex = currentIndex.clamp(0, playlist.length - 1);
      await _loadCurrent(autoplay: false);
    } else if (index < currentIndex) {
      currentIndex -= 1;
    }
    notifyListeners();
  }

  Future<void> _handleEnded() async {
    // Completed video: reset its saved position so it replays from the start.
    final track = currentTrack;
    if (track != null) {
      final e = _historyEntryFor(track.path);
      if (e != null) {
        e.lastPositionSecs = 0;
        _persistHistory();
      }
    }
    if (repeatMode == RepeatMode.one) {
      await player.seek(Duration.zero);
      await player.play();
    } else if (repeatMode == RepeatMode.all ||
        currentIndex < playlist.length - 1) {
      await nextTrack();
    }
  }

  @override
  void dispose() {
    _bookmarkTimer?.cancel();
    _notices.close();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}

/// One day of watch time for the stats screen.
class WatchDay {
  final DateTime day;
  final int seconds;
  const WatchDay(this.day, this.seconds);
}
EOF_MARKER_2

cat > 'lib/screens/player_screen.dart' <<'EOF_MARKER_3'
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../cast/cast_state.dart';
import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/player_settings.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import '../utils/srt.dart';
import '../widgets/cast_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/player_settings_sheet.dart';
import '../widgets/playlist_panel.dart';
import '../widgets/video_info_sheet.dart';

class PlayerScreen extends StatefulWidget {
  final MediaPlayerState player;

  const PlayerScreen({super.key, required this.player});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  // Shared, app-lifetime controller owned by MediaPlayerState (this media_kit
  // version has no VideoController.dispose, so per-visit controllers leaked).
  late final VideoController _controller = widget.player.videoController;

  /// DLNA cast session for this visit to the player. Disposed with the
  /// screen (leaving the player stops casting).
  final CastState _castState = CastState();

  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _showQueue = false;
  bool _isPip = false;

  /// Screen lock (kids mode): every gesture/button is swallowed until the
  /// on-screen lock is double-tapped (or long-pressed).
  bool _locked = false;

  // Orientation lock (rotation toggle in the controls).
  bool _orientationLocked = false;
  List<DeviceOrientation> _lockedOrientations = DeviceOrientation.values;

  // Customizable behavior (persisted, edited in the Settings sheet).
  PlayerSettings _settings = const PlayerSettings();

  Timer? _hideTimer;

  // Transient center indicator ("+10s", "Volume 80%", "Resumed 12:34", ...).
  String? _indicatorText;
  IconData? _indicatorIcon;
  String? _indicatorKey; // dedupe: identical text just refreshes the timer
  Timer? _indicatorTimer;
  StreamSubscription<String>? _noticeSub;

  // Aspect-ratio fit cycle: contain -> cover -> fill.
  static const List<BoxFit> _fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
  static const List<String> _fitNames = ['Contain', 'Cover', 'Fill'];
  int _fitIndex = 0;
  static const List<IconData> _fitIcons = [
    Icons.fit_screen,
    Icons.crop_free,
    Icons.open_in_full,
  ];

  // Pinch zoom (1x..4x), anchored at the fingers' focal point, with
  // one-finger panning while zoomed.
  double _zoom = 1.0;
  double _zoomBase = 1.0;
  Offset _pan = Offset.zero;
  Offset _panBase = Offset.zero;
  Offset _focalBase = Offset.zero;

  // Gesture plumbing (double-tap seek / unified drag handling).
  double _gestureWidth = 0;
  double _gestureHeight = 0;
  double _lastDoubleTapDx = 0;

  // --- Unified single-recognizer drag handling -----------------------------
  //
  // EVERYTHING drag-ish (volume / brightness / horizontal seek / zoom-pan)
  // is handled through the scale recognizer only. The old code ALSO
  // registered onVerticalDrag* on the same GestureDetector, and the two
  // recognizers fought in the gesture arena - whichever won was decided by
  // tiny direction differences, which is exactly what made the volume swipe
  // feel "glitchy". One recognizer = deterministic behavior.
  _ScaleMode _scaleMode = _ScaleMode.undecided;
  Offset _dragAccum = Offset.zero;
  Offset _focalStart = Offset.zero;
  double _dragStartValue = 0;

  // Horizontal seek drag.
  Duration _seekBasePos = Duration.zero;
  Duration? _seekTarget;
  int _seekLastAppliedSec = -1;

  // Volume drag dedupe (cuts mpv IPC + indicator reflows ~10x).
  int _lastVolPct = -1;

  // NOTE: no addListener/setState on the player here. The ticking parts
  // (overlay, spinner, queue, title) listen via their own AnimatedBuilder,
  // so the video surface itself is never rebuilt during playback.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Follow the phone's own rotation while in the player (the app used to
    // stay stuck in portrait); the lock button below restricts this on
    // demand and dispose() hands free rotation back.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _noticeSub = widget.player.notices.listen(
      (m) => _showIndicator(m, Icons.history),
    );
    NativeBridge.configureCallbacks(
      onPipChanged: (isPip) {
        if (mounted) setState(() => _isPip = isPip);
      },
    );
    _reloadSettings();
    widget.player.currentBrightness(); // sync once for the swipe gesture
    widget.player.currentVolume(); // start swipe from REAL device volume
    _startHideTimer();
  }

  @override
  void dispose() {
    _castState.dispose(); // stops casting + the embedded file server
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _noticeSub?.cancel();
    if (_isFullscreen) _exitFullscreen();
    // Never leave an orientation restriction behind.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    // Do NOT keep the audio running after leaving the player screen, and
    // hand brightness control back to the system.
    unawaited(widget.player.pause());
    unawaited(widget.player.resetBrightness());
    super.dispose();
  }

  /// Pause when the app goes to the background (sound must not keep playing
  /// with the app hidden).
  ///
  /// IMPORTANT: entering picture-in-picture maps to AppLifecycleState.
  /// inactive on Android - we must NOT pause for it, and we must skip the
  /// fully-backgrounded states while the PiP window is up. Otherwise PiP
  /// would freeze the video the moment it opens.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isPip) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.player.pause();
    }
  }

  Future<void> _reloadSettings() async {
    final s = await PlayerSettings.load();
    if (mounted) setState(() => _settings = s);
    _startHideTimer();
  }

  Future<void> _openSettings() async {
    await PlayerSettingsSheet.show(context);
    await _reloadSettings(); // apply changes immediately
  }

  // ---------------------------------------------------------------------------
  // Controls visibility (auto-hide)
  // ---------------------------------------------------------------------------

  void _startHideTimer() {
    _hideTimer?.cancel();
    final delay = _settings.autoHideSeconds;
    if (delay <= 0) return; // "never auto-hide"
    _hideTimer = Timer(Duration(seconds: delay), () {
      // Only auto-hide during playback; keep controls up while paused.
      if (mounted && widget.player.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  /// Called by the overlay on every button press / seek / menu selection so
  /// the auto-hide countdown restarts on any interaction.
  void _onUserInteraction() {
    if (_controlsVisible) _startHideTimer();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  // ---------------------------------------------------------------------------
  // Screen lock (kids mode)
  // ---------------------------------------------------------------------------

  void _lockScreen() {
    _hideTimer?.cancel();
    setState(() {
      _locked = true;
      _controlsVisible = false;
    });
    _showIndicator('Screen locked', Icons.lock);
  }

  void _unlockScreen() {
    setState(() {
      _locked = false;
      _controlsVisible = true;
    });
    _startHideTimer();
    _showIndicator('Unlocked', Icons.lock_open);
  }

  void _showLockHint() {
    _showIndicator('Locked - double-tap the lock to unlock', Icons.lock);
  }

  // ---------------------------------------------------------------------------
  // Transient indicator
  // ---------------------------------------------------------------------------

  void _showIndicator(String text, [IconData? icon]) {
    if (!mounted) return;
    _indicatorTimer?.cancel();
    _indicatorKey = '$text|${icon?.codePoint ?? 0}';
    setState(() {
      _indicatorText = text;
      _indicatorIcon = icon;
    });
    _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _indicatorText = null);
    });
  }

  /// Same as [_showIndicator] but an unchanged message only refreshes the
  /// hide timer (no setState flood while a drag gesture keeps reporting the
  /// same percentage).
  void _showIndicatorThrottled(String text, [IconData? icon]) {
    if (!mounted) return;
    final key = '$text|${icon?.codePoint ?? 0}';
    if (key == _indicatorKey) {
      _indicatorTimer?.cancel();
      _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _indicatorText = null);
      });
      return;
    }
    _showIndicator(text, icon);
  }

  // ---------------------------------------------------------------------------
  // Fullscreen, fit, zoom
  // ---------------------------------------------------------------------------

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      _exitFullscreen();
    }
    _onUserInteraction();
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Respect an active rotation lock when leaving fullscreen.
    SystemChrome.setPreferredOrientations(
      _orientationLocked ? _lockedOrientations : DeviceOrientation.values,
    );
  }

  /// Rotation toggle: auto-rotate <-> locked to the CURRENT orientation.
  void _toggleOrientationLock() {
    if (!_orientationLocked) {
      final landscape =
          MediaQuery.of(context).orientation == Orientation.landscape;
      _lockedOrientations = landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ];
      SystemChrome.setPreferredOrientations(_lockedOrientations);
      setState(() => _orientationLocked = true);
      _showIndicator('Rotation locked', Icons.screen_lock_rotation);
    } else {
      _lockedOrientations = DeviceOrientation.values;
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      setState(() => _orientationLocked = false);
      _showIndicator('Auto-rotate on', Icons.screen_rotation);
    }
    _onUserInteraction();
  }

  // ---------------------------------------------------------------------------
  // Long-press speed boost (customizable multiplier)
  // ---------------------------------------------------------------------------

  void _onLongPressStart(LongPressStartDetails _) {
    if (!_settings.longPressSpeed) return;
    // No boost (and no badge) while the video is paused.
    if (!widget.player.isPlaying) return;
    widget.player.startSpeedBoost(_settings.longPressMultiplier);
    setState(() {}); // mount the persistent "Nx" badge
    // NOTE: no flash indicator here - the persistent purple badge IS the
    // feedback (showing both looked like a duplicated "2x" bug).
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    widget.player.stopSpeedBoost();
    setState(() {}); // remove the persistent badge
  }

  void _cycleFit() {
    setState(() => _fitIndex = (_fitIndex + 1) % _fits.length);
    _showIndicator('Fit: ${_fitNames[_fitIndex]}', _fitIcons[_fitIndex]);
    _onUserInteraction();
  }

  // ---------------------------------------------------------------------------
  // Unified scale recognizer (pinch zoom + ALL drag gestures)
  // ---------------------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails details) {
    _scaleMode = _ScaleMode.undecided;
    _dragAccum = Offset.zero;
    _focalStart = details.localFocalPoint;
    _zoomBase = _zoom;
    _panBase = _pan;
    _focalBase = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Two+ fingers -> pinch zoom (focal-anchored).
    if (details.pointerCount >= 2) {
      if (!_settings.pinchZoom) return;
      _scaleMode = _ScaleMode.zoom;

      // Focal-anchored transform: the content point that was under the
      // fingers when the pinch started stays glued to the CURRENT focal
      // point. Because we track the live focal point, moving both fingers
      // together pans the zoomed video for free.
      final z = (_zoomBase * details.scale).clamp(1.0, 4.0);
      final contentV = (_focalBase - _panBase) / _zoomBase;
      final pan = _clampPan(details.localFocalPoint - contentV * z, z);

      if (z == _zoom && pan == _pan) return;
      setState(() {
        _zoom = z;
        _pan = pan;
      });
      if (details.scale != 1.0) {
        _showIndicator('Zoom ${z.toStringAsFixed(1)}x', Icons.pinch_outlined);
      }
      return;
    }

    // One finger -> figure out WHAT the drag is once we're past the slop,
    // then stick with that mode until the gesture ends.
    switch (_scaleMode) {
      case _ScaleMode.zoom:
        return; // came from two fingers; ignore until scale end
      case _ScaleMode.cant:
        return; // all relevant gestures are disabled
      case _ScaleMode.volume:
      case _ScaleMode.brightness:
        _dragAccum += details.focalPointDelta;
        _applyLevelDrag();
        return;
      case _ScaleMode.seekH:
        _dragAccum += details.focalPointDelta;
        _applySeekDrag();
        return;
      case _ScaleMode.pan:
        _applyPanDrag(details);
        return;
      case _ScaleMode.undecided:
        _dragAccum += details.focalPointDelta;
        if (_dragAccum.distance < 14) return; // slop
        final dx = _dragAccum.dx.abs();
        final dy = _dragAccum.dy.abs();
        if (dx > dy * 1.3) {
          // Horizontal: seek (or pan when zoomed in).
          if (_zoom > 1.0) {
            _scaleMode = _ScaleMode.pan;
            _applyPanDrag(details);
          } else if (_settings.horizontalSeek &&
              widget.player.currentTrack != null &&
              widget.player.duration > Duration.zero) {
            _scaleMode = _ScaleMode.seekH;
            _seekBasePos = widget.player.position;
            _seekTarget = null;
            _seekLastAppliedSec = -1;
            _dragAccum = Offset.zero;
          } else {
            _scaleMode = _ScaleMode.cant;
          }
        } else {
          // Vertical: volume (right half) or brightness (left half).
          final rightHalf = _focalStart.dx > _gestureWidth / 2;
          if (rightHalf && _settings.volumeSwipe) {
            _scaleMode = _ScaleMode.volume;
            _lastVolPct = (widget.player.isMuted
                    ? 0.0
                    : widget.player.volume * 100)
                .round();
            _dragStartValue =
                widget.player.isMuted ? 0.0 : widget.player.volume;
          } else if (!rightHalf && _settings.brightnessSwipe) {
            _scaleMode = _ScaleMode.brightness;
            _dragStartValue = widget.player.brightness;
          } else {
            _scaleMode = _ScaleMode.cant;
            return;
          }
          _dragAccum = Offset.zero;
        }
        return;
    }
  }

  /// Volume / brightness value from the accumulated vertical movement.
  void _applyLevelDrag() {
    // Dragging up increases; a 300px sweep covers the full 0..100% range.
    final v = (_dragStartValue - _dragAccum.dy / 300).clamp(0.0, 1.0);
    if (_scaleMode == _ScaleMode.volume) {
      final pct = (v * 100).round();
      if (pct == _lastVolPct) return; // spare mpv from per-pixel IPC
      _lastVolPct = pct;
      widget.player.setVolume(v);
      _showIndicatorThrottled(
        'Volume $pct%',
        pct == 0 ? Icons.volume_off : Icons.volume_up,
      );
    } else {
      widget.player.setBrightness(v);
      _showIndicatorThrottled(
        'Brightness ${(v * 100).round()}%',
        Icons.brightness_6_outlined,
      );
    }
  }

  /// Horizontal scrub: a full screen-width drag is +-90 seconds. Seeks live
  /// in whole-second steps (mpv is fine with it) and lands exactly on end.
  void _applySeekDrag() {
    final dur = widget.player.duration;
    if (dur <= Duration.zero) return;
    final offsetSec = _dragAccum.dx / _gestureWidth * 90.0;
    final targetMs =
        (_seekBasePos.inMilliseconds + (offsetSec * 1000).round())
            .clamp(0, dur.inMilliseconds);
    final target = Duration(milliseconds: targetMs);
    _seekTarget = target;
    final diffMs = targetMs - _seekBasePos.inMilliseconds;
    final sign = diffMs >= 0 ? '+' : '-';
    _showIndicatorThrottled(
      '$sign${(diffMs.abs() / 1000).round()}s · ${formatDuration(target)}',
      diffMs >= 0 ? Icons.fast_forward : Icons.fast_rewind,
    );
    // Live-seek in 1s steps while the finger moves.
    final s = target.inSeconds;
    if ((s - _seekLastAppliedSec).abs() >= 1) {
      _seekLastAppliedSec = s;
      widget.player.seek(Duration(seconds: s));
    }
  }

  /// One-finger panning while zoomed in.
  void _applyPanDrag(ScaleUpdateDetails details) {
    if (_zoom <= 1.0) return;
    final pan = _clampPan(
      _panBase + (details.localFocalPoint - _focalBase),
      _zoom,
    );
    if (pan != _pan) setState(() => _pan = pan);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final mode = _scaleMode;
    _scaleMode = _ScaleMode.undecided;
    if (mode == _ScaleMode.seekH) {
      final t = _seekTarget;
      if (t != null) widget.player.seek(t); // exact final landing
      _seekTarget = null;
      return;
    }
    if (mode == _ScaleMode.volume || mode == _ScaleMode.brightness) return;
    if (!_settings.pinchZoom && mode != _ScaleMode.pan) return;
    // Snap back when barely zoomed.
    if (_zoom < 1.1) {
      if (_zoom != 1.0 || _pan != Offset.zero) {
        setState(() {
          _zoom = 1.0;
          _pan = Offset.zero;
        });
      }
    } else {
      setState(() => _pan = _clampPan(_pan, _zoom));
    }
  }

  /// Keep the scaled video covering the viewport (no drifting past edges).
  Offset _clampPan(Offset pan, double z) {
    final maxX = _gestureWidth * (z - 1);
    final maxY = _gestureHeight * (z - 1);
    return Offset(pan.dx.clamp(-maxX, 0.0), pan.dy.clamp(-maxY, 0.0));
  }

  // ---------------------------------------------------------------------------
  // Tap gestures
  // ---------------------------------------------------------------------------

  void _onDoubleTap() {
    final third = _gestureWidth / 3;
    if (_lastDoubleTapDx < third) {
      if (!_settings.doubleTapSeek) return;
      widget.player.seekBy(-_settings.seekSeconds);
      _showIndicator('-${_settings.seekSeconds}s', Icons.replay_10);
    } else if (_lastDoubleTapDx > _gestureWidth - third) {
      if (!_settings.doubleTapSeek) return;
      widget.player.seekBy(_settings.seekSeconds);
      _showIndicator('+${_settings.seekSeconds}s', Icons.forward_10);
    } else {
      // Middle third: play / pause.
      if (!_settings.doubleTapPlayPause) return;
      final wasPlaying = widget.player.isPlaying;
      widget.player.togglePlay();
      _showIndicator(
        wasPlaying ? 'Paused' : 'Playing',
        wasPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Screenshot + cast
  // ---------------------------------------------------------------------------

  Future<void> _takeScreenshot() async {
    final path = await widget.player.captureScreenshot();
    if (!mounted) return;
    _showIndicator(
      path == null
          ? 'Screenshot unavailable for streams'
          : 'Screenshot saved to gallery',
      path == null ? Icons.error_outline : Icons.camera_alt,
    );
  }

  Future<void> _openCast() async {
    final track = widget.player.currentTrack;
    if (track == null) {
      _showIndicator('Nothing to cast - open a video first',
          Icons.videocam_off_outlined);
      return;
    }
    // Offer AI-generated subtitles to the TV when they exist on disk.
    String? subsPath;
    if (!track.path.startsWith('http')) {
      final srt = srtPathForVideo(track.path);
      if (File(srt).existsSync()) subsPath = srt;
    }
    // Kick off the device scan right away (the sheet renders its states).
    unawaited(_castState.scan());
    await CastSheet.show(
      context,
      _castState,
      videoPath: track.path,
      title: track.title,
      subsPath: subsPath,
      onCastStarted: () {
        widget.player.pause(); // the TV is playing; phone becomes remote
        _showIndicator('Casting to TV', Icons.cast_connected);
      },
      onCastStopped: (tvPos) async {
        // Hand playback back to the phone at the TV's position.
        if (tvPos > Duration.zero) await widget.player.seek(tvPos);
        await widget.player.resumePlayback();
        if (mounted) _showIndicator('Back on this phone', Icons.smartphone);
      },
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    return PopScope(
      canPop: !_isFullscreen && !_locked,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_locked) {
          _showLockHint();
        } else {
          _toggleFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _isFullscreen || _isPip
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                title: AnimatedBuilder(
                  animation: player,
                  builder: (context, _) => Text(
                    player.currentTrack?.title ?? 'Max Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                actions: [
                  _appBarBtn(
                    'Video info',
                    Icons.info_outline,
                    () => VideoInfoSheet.show(context, widget.player),
                  ),
                  _appBarBtn(
                    'Equalizer',
                    Icons.graphic_eq,
                    () => EqualizerSheet.show(context, widget.player),
                  ),
                  if (_settings.castButton)
                    _appBarBtn('Cast to TV', Icons.cast_outlined, _openCast),
                  if (_settings.screenshotButton)
                    _appBarBtn(
                      'Screenshot',
                      Icons.camera_alt_outlined,
                      _takeScreenshot,
                    ),
                  _appBarBtn(
                    'Picture in picture',
                    Icons.picture_in_picture_alt_outlined,
                    () => NativeBridge.enterPip(
                        playing: widget.player.isPlaying),
                  ),
                  _appBarBtn(
                    'Player settings',
                    Icons.settings_outlined,
                    _openSettings,
                  ),
                ],
              ),
        body: SafeArea(
          top: !_isFullscreen,
          // Lift controls above the gesture/nav bar in landscape fullscreen.
          bottom: true,
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _gestureWidth = constraints.maxWidth;
                    _gestureHeight = constraints.maxHeight;
                    return GestureDetector(
                      // While locked every gesture collapses to a lock hint.
                      onTap: _locked ? _showLockHint : _toggleControls,
                      onDoubleTapDown: _locked
                          ? null
                          : (d) => _lastDoubleTapDx = d.localPosition.dx,
                      onDoubleTap: _locked ? null : _onDoubleTap,
                      onLongPressStart: _locked ? null : _onLongPressStart,
                      onLongPressEnd: _locked ? null : _onLongPressEnd,
                      onScaleStart:
                          _locked ? (_) => _showLockHint() : _onScaleStart,
                      onScaleUpdate: _locked ? null : _onScaleUpdate,
                      onScaleEnd: _locked ? null : _onScaleEnd,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Video surface - pinch zoom/pan applies a matrix
                          // (scale about the finger focal point), clipped to
                          // the available area.
                          Positioned.fill(
                            child: ClipRect(
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
                                  ..scaleByDouble(_zoom, _zoom, _zoom, 1),
                                child: Center(
                                  child: player.currentTrack != null
                                      ? RepaintBoundary(
                                          child: Video(
                                            controller: _controller,
                                            controls: NoVideoControls,
                                            fit: _fits[_fitIndex],
                                          ),
                                        )
                                      : const Text(
                                          'No video loaded',
                                          style: TextStyle(
                                            color: Colors.white38,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                          // Buffering spinner - follows the player stream only.
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: player,
                              builder: (context, _) => player.isLoading
                                  ? Center(
                                      child: CircularProgressIndicator(
                                        color: themeState.accent,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          // Transient indicator (seek / volume / brightness /
                          // zoom / resume / fit / play-pause) - pops in and
                          // out with a small scale+fade.
                          Positioned(
                            top: 72,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 150),
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                        opacity: anim,
                                        child: ScaleTransition(
                                          scale: anim.drive(
                                            CurveTween(
                                              curve: Curves.decelerate,
                                            ),
                                          ),
                                          child: child,
                                        ),
                                      ),
                                  child: (_indicatorText != null && !_isPip)
                                      ? Container(
                                          key: ValueKey(
                                            '$_indicatorText|${_indicatorIcon?.codePoint}',
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.72,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_indicatorIcon != null) ...[
                                                Icon(
                                                  _indicatorIcon,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              Text(
                                                _indicatorText!,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : const SizedBox.shrink(
                                          key: ValueKey('noIndicator'),
                                        ),
                                ),
                              ),
                            ),
                          ),
                          // Persistent speed badge for the WHOLE long-press
                          // boost. Follows the player state directly (so it
                          // vanishes instantly if the video is paused during
                          // a boost) and pops in/out.
                          Positioned(
                            top: 12,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Center(
                                child: AnimatedBuilder(
                                  animation: player,
                                  builder: (context, _) => AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 160),
                                    transitionBuilder: (child, anim) =>
                                        FadeTransition(
                                          opacity: anim,
                                          child: ScaleTransition(
                                            scale: anim,
                                            child: child,
                                          ),
                                        ),
                                    child:
                                        (player.isSpeedBoosting &&
                                            player.isPlaying &&
                                            !_isPip)
                                        ? Container(
                                            key: const ValueKey('speedBadge'),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: themeState.accent
                                                  .withValues(alpha: 0.9),
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.fast_forward,
                                                  color: Colors.white,
                                                  size: 15,
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  '${_settings.longPressMultiplier}x',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : const SizedBox.shrink(
                                            key: ValueKey('noSpeedBadge'),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Screen-lock ENTER button (left edge, shown with
                          // the controls, MX-Player style).
                          Positioned(
                            left: 4,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              ignoring: !(_controlsVisible &&
                                  !_isPip &&
                                  !_locked &&
                                  _settings.lockButton &&
                                  player.currentTrack != null),
                              child: AnimatedOpacity(
                                opacity: (_controlsVisible &&
                                        !_isPip &&
                                        !_locked &&
                                        _settings.lockButton &&
                                        player.currentTrack != null)
                                    ? 1.0
                                    : 0.0,
                                duration: const Duration(milliseconds: 180),
                                child: Center(
                                  child: _lockChip(
                                    icon: Icons.lock_open_outlined,
                                    onTap: _lockScreen,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Screen-lock EXIT chip (right edge, always visible
                          // while locked).
                          if (_locked && !_isPip)
                            Positioned(
                              right: 4,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _lockChip(
                                  icon: Icons.lock,
                                  onTap: _showLockHint,
                                  onDoubleTap: _unlockScreen,
                                  onLongPress: _unlockScreen,
                                ),
                              ),
                            ),
                          // Controls slide up + fade in instead of snapping.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              ignoring: !_controlsVisible,
                              child: AnimatedSlide(
                                offset: _controlsVisible && !_isPip
                                    ? Offset.zero
                                    : const Offset(0, 0.45),
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: AnimatedOpacity(
                                  opacity: _controlsVisible && !_isPip
                                      ? 1.0
                                      : 0.0,
                                  duration: const Duration(milliseconds: 180),
                                  child: PlayerControlsOverlay(
                                    player: player,
                                    isFullscreen: _isFullscreen,
                                    onToggleFullscreen: _toggleFullscreen,
                                    onToggleQueue: () {
                                      setState(() => _showQueue = !_showQueue);
                                      _onUserInteraction();
                                    },
                                    onInteract: _onUserInteraction,
                                    onCycleFit: _cycleFit,
                                    orientationLocked: _orientationLocked,
                                    onToggleOrientationLock:
                                        _toggleOrientationLock,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_showQueue && !_isFullscreen && !_isPip)
                SizedBox(
                  width: 280,
                  child: Container(
                    color: const Color(0xFF12121a),
                    child: AnimatedBuilder(
                      animation: player,
                      builder: (context, _) => PlaylistPanel(
                        playlist: player.playlist,
                        currentIndex: player.currentIndex,
                        onPlay: player.playTrack,
                        onRemove: player.removeFromPlaylist,
                        onClose: () => setState(() => _showQueue = false),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appBarBtn(String tooltip, IconData icon, VoidCallback onPressed) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }

  Widget _lockChip({
    required IconData icon,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

enum _ScaleMode { undecided, volume, brightness, seekH, pan, zoom, cant }
EOF_MARKER_3

cat > 'lib/utils/ai_subtitles.dart' <<'EOF_MARKER_4'
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import 'srt.dart';

/// Runs the offline AI subtitle flow end to end and shows a progress dialog:
///
///   download model once (~142 MB) -> extract audio -> whisper.cpp ->
///   write "<video>.maxai.srt" next to the video -> load it into the player
///
/// Everything after the one-time model download is 100% offline & free.
class AiSubtitleRunner {
  AiSubtitleRunner._();

  /// Launches generation for the video currently loaded in [player].
  /// [context] must be a context that outlives the subtitle sheet (the
  /// caller closes the sheet first).
  static Future<void> start(
    BuildContext context,
    MediaPlayerState player,
  ) async {
    final track = player.currentTrack;
    if (track == null || track.path.contains('://')) {
      _snack(context,
          'AI subtitles work on local video files (not network streams)');
      return;
    }

    // One active job at a time; hook up the event callbacks first.
    final progress = ValueNotifier<(String, int)>(('starting', 0));
    var dialogOpen = false;
    List<AiSegment>? segments;
    String? error;

    void closeDialog() {
      if (dialogOpen && context.mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: false).pop();
      }
    }

    NativeBridge.configureCallbacks(
      onAiProgress: (stage, percent) => progress.value = (stage, percent),
      onAiDone: (s) {
        segments = s;
        closeDialog();
      },
      onAiFailed: (e) {
        error = e;
        closeDialog();
      },
    );

    final jobId = await NativeBridge.aiSubtitleGenerate(
      videoPath: track.path,
      // "base" (~142 MB one-time): the multilingual "tiny" model degrades
      // Hindi/Urdu/mixed speech into stray "music" captions; base is the
      // smallest model that's reliable for them.
      model: 'base',
    );
    if (!context.mounted) return;
    if (jobId == null) {
      _snack(context, 'AI engine is not available in this build');
      return;
    }

    if (!context.mounted) return;
    dialogOpen = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AiProgressDialog(
        progress: progress,
        onCancel: () {
          error = 'cancelled';
          NativeBridge.aiSubtitleCancel();
          closeDialog();
        },
      ),
    );
    dialogOpen = false;

    if (!context.mounted) return;

    if (error != null && error != 'cancelled') {
      _snack(context, 'AI subtitles failed: $error');
      return;
    }
    if (error == 'cancelled' || segments == null) return;

    if (segments!.isEmpty) {
      _snack(context,
          'No speech was detected in this video - nothing to write');
      return;
    }

    // (mounted was checked right after the dialog closed above)

    // Build the .srt (pure function) and save it next to the video.
    final srtPath = _srtPathFor(track.path);
    try {
      final cues = [
        for (final s in segments!)
          SrtCue(s.startMs, s.endMs, s.text),
      ];
      await File(srtPath).writeAsString(buildSrt(cues));
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'Subtitles generated, but saving the file failed');
      }
      return;
    }
    if (!context.mounted) return;

    // Hand it to mpv so the subtitle picker lists it immediately.
    final platform = player.player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.command(['sub-add', srtPath]);
      } catch (_) {}
    }
    if (context.mounted) {
      _snack(context, '✨ AI subtitles ready - pick them in the subtitle list');
    }
  }

  static String _srtPathFor(String videoPath) {
    final dir = p.dirname(videoPath);
    final base = p.basenameWithoutExtension(videoPath);
    return p.join(dir, '$base.maxai.srt');
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _AiProgressDialog extends StatelessWidget {
  final ValueNotifier<(String, int)> progress;
  final VoidCallback onCancel;

  const _AiProgressDialog({required this.progress, required this.onCancel});

  static String _stageLabel(String stage) {
    switch (stage) {
      case 'downloading':
        return 'Downloading the AI model (one time, ~142 MB)…';
      case 'extracting':
        return 'Extracting audio from the video…';
      case 'transcribing':
        return 'Listening and writing subtitles…\n(this runs fully offline; long videos take longer)';
      default:
        return 'Preparing…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a24),
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: themeState.accent, size: 20),
          const SizedBox(width: 8),
          const Text('AI subtitles', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: ValueListenableBuilder<(String, int)>(
        valueListenable: progress,
        builder: (context, value, _) {
          final (stage, percent) = value;
          final determinate = stage == 'downloading' || stage == 'extracting';
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _stageLabel(stage),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: determinate ? percent / 100 : null,
                color: themeState.accent,
                backgroundColor: Colors.white10,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(
                determinate ? '$percent%' : ' ',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
EOF_MARKER_4

cat > 'pubspec.yaml' <<'EOF_MARKER_5'
name: maxplayer
description: "Max Player - a local video library & player."
publish_to: 'none'
version: 1.0.0+13

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # Playback engine (libmpv/ffmpeg backed) - handles mp4/webm/mkv/avi/wmv/flv/ts/vob/etc
  # which ExoPlayer (video_player plugin) does not reliably support.
  media_kit: ^1.1.11
  media_kit_video: ^1.2.5
  media_kit_libs_android_video: ^1.3.6

  # Folder scanning via a manually-entered path + broad storage permission,
  # instead of file_picker's native SAF dialog (file_picker's Android side has
  # proven incompatible with current AGP/Kotlin toolchains as of this writing).
  permission_handler: ^11.3.1

  path: ^1.9.0
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
EOF_MARKER_5

echo ""
echo "==> Done! Now run:"
echo "    git add -A && git commit -m \"v13: device-volume swipe, AI PCM/language/model fixes\" && git push"
