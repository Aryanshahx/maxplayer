#!/usr/bin/env bash
# =============================================================
#  Max Player - v23 BUGFIX ROUND (includes ALL of v22 - standalone)
#  Repo: https://github.com/Aryanshahx/maxplayer   Version: 1.0.0+21
#
#  NOTE: this script is COMPLETE BY ITSELF. You may run it directly on
#  the repo as it is now (the v22 script never needs to run first).
#
#  v23 (new):
#  - THEME COLOUR EVERYWHERE IN THE PLAYER: icons, titles, menus,
#    settings sheet, tracks sheet, equalizer, video info, cast sheet,
#    playlist panel, mini player, seek-bar times, volume/brightness
#    pop-ups, lock chips - all follow the picked theme colour.
#    New WHITE theme colour added (dark icons auto-picked on white).
#  - Karaoke ON  =>  the normal/default subtitle display turns OFF,
#    so only the karaoke line shows (works with any subtitle source).
#  - Sleep timer: countdown below the title, incl. "end of video" mode.
#
#  Carried in from v22:
#  1. Private folder hardened (asks All files access, shows REAL error,
#     no silent half-moves) + empty screen prints the requested hint:
#     "Hold on a video in the Library to add it to the Private folder".
#  2. Karaoke works with ANY subtitles (embedded / own .srt / AI).
#  3. 4K thumbnails: mpv captures a frame after ~1.5s of playback when
#     Android cannot decode one.
#  4. Speed menu up to 3x (added 2.5x / 3.0x).
#  5. Skip-intro chip also works with the video's own .srt file.
#  6. AI subtitles much faster: Fast model (~75MB) + all CPU cores.
#  7. 200% volume boost ON by default.
#  8. Volume leveling fixed (was fighting the equalizer for one slot).
#
#  FILES (32) - each maps to a report above.
#
#  HOW TO USE:
#    cd ~/IdeaProjects/maxplayer
#    nano update_maxplayer_v23.sh   # paste, save, exit
#    bash update_maxplayer_v23.sh
#    git add -A && git commit -m "v23: theme colour across whole player
#        (+white), karaoke-only display, sleep countdown, v22 fixes"
#    git push
# =============================================================
set -e
cd "$HOME/IdeaProjects/maxplayer" || { echo "ERROR: project folder not found"; exit 1; }

if ! grep -q "^name: maxplayer" pubspec.yaml 2>/dev/null; then
  echo "ERROR: This does not look like the maxplayer project folder."
  exit 1
fi
if grep -q "v23: whole player rides the theme colour" lib/widgets/player_controls_overlay.dart 2>/dev/null; then
  echo "v23 looks already applied. Nothing to do."
  exit 0
fi

# v17 cleanup (idempotent): drop v16s temporary CI diagnostics step.
if grep -q "^      - name: Diagnose signing secrets" codemagic.yaml 2>/dev/null; then
  echo "==> removing v16 temporary CI diagnostics step from codemagic.yaml"
  sed -i '/^      - name: Diagnose signing secrets/,/^      - name: Clean build/{/^      - name: Clean build/!d}' codemagic.yaml
  sed -i '/^      - name: Clean build/i\      # after it confirmed CI signing is green (CI KEYSTORE CHECK: OK).' codemagic.yaml
  sed -i '/after it confirmed CI signing is green/i\      # v16'"'"'s temporary "Diagnose signing secrets" step was removed in v17' codemagic.yaml
fi

echo "==> v23: writing 32 files ..."

mkdir -p "$(dirname 'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt')"
cat > 'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt' <<'EOF_MARKER_0'
package com.hypertechlabs.maxplayer

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
import android.hardware.SensorManager
import android.view.OrientationEventListener
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
        private const val ACTION_PIP_TOGGLE = "com.hypertechlabs.maxplayer.action.PIP_TOGGLE"
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
                "enableSensorRotate" -> {
                    // v19: rotate the player by ACCELEROMETER, ignoring the
                    // phone's auto-rotate switch (explicit orientation
                    // requests win over the system toggle).
                    ensureRotateListener()
                    rotateLocked = false
                    rotateListener?.enable()
                    result.success(true)
                }
                "disableSensorRotate" -> {
                    rotateListener?.disable()
                    rotateLocked = false
                    // Hand rotation control back to the system.
                    requestedOrientation =
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    result.success(true)
                }
                "lockRotation" -> {
                    val landscape = call.argument<Boolean>("landscape") ?: true
                    rotateLocked = true
                    rotateListener?.disable()
                    requestedOrientation = if (landscape)
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    else
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    result.success(true)
                }
                "thumbStripEnsure" -> {
                    val p = call.argument<String>("path")
                    executor.execute {
                        val dir = thumbStripEnsureSync(p)
                        mainHandler.post { result.success(dir) }
                    }
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
                    val model = call.argument<String>("model") ?: "base"
                    val language = call.argument<String>("language") ?: "auto"
                    // v21: whisper translate task -> English subtitles from
                    // any spoken language.
                    val translate = call.argument<Boolean>("translate") ?: false
                    if (videoPath.isNullOrEmpty()) {
                        result.error("bad_args", "videoPath is required", null)
                    } else {
                        aiCancelled = false
                        val jobId = ++aiJobCounter
                        executor.execute {
                            runAiPipeline(jobId, videoPath, model, language, translate)
                        }
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
                "thumbnailPathFor" -> {
                    // The Dart player's 4K/HDR thumbnail fallback (v22): when
                    // Android's metadata engine can't decode a frame from a
                    // file, mpv (which plays them fine) captures one at this
                    // exact cache path during playback. Returning null tells
                    // Dart "don't even try" (missing file / stream).
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty() || !File(path).exists()) {
                        result.success(null)
                    } else {
                        result.success(thumbFileFor(path).absolutePath)
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
     * v21 4K/HDR-safe frame grab, least-risk first. The old code asked for a
     * FULL-SIZE frame and scaled it afterwards - on 4K videos that bitmap is
     * ~33 MB, which OOM-failed (or returned null on some 10-bit HEVC rips)
     * and the tile silently kept the placeholder icon. Ladder:
     *   1. getScaledFrameAtTime: decode directly at 320px wide (API 27+)
     *   2. plain getFrameAtTime at the same timestamp
     *   3. plain getFrameAtTime(0)  - some files only expose the first frame
     *   4. embedded cover art
     * Every step swallows Throwables (incl. OutOfMemoryError) and falls
     * through to the next one.
     */
    private fun grabFrameSafely(
        retriever: MediaMetadataRetriever,
        seekUs: Long,
        width: Int?,
        height: Int?
    ): Bitmap? {
        if (Build.VERSION.SDK_INT >= 27 && width != null && height != null && width > 0 && height > 0) {
            val dstW = 320
            val dstH = (320.0 * height / width).toInt().coerceAtLeast(1)
            try {
                val f = retriever.getScaledFrameAtTime(
                    seekUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, dstW, dstH
                )
                if (f != null) return f
            } catch (_: Throwable) {
            }
        }
        try {
            val f = retriever.getFrameAtTime(seekUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (f != null) return f
        } catch (_: Throwable) {
        }
        try {
            val f = retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (f != null) return f
        } catch (_: Throwable) {
        }
        try {
            val art = retriever.embeddedPicture
            if (art != null) return BitmapFactory.decodeByteArray(art, 0, art.size)
        } catch (_: Throwable) {
        }
        return null
    }

    /**
     * Cache file holding the thumbnail of [path]. Shared with the Dart
     * player's mpv-screenshot fallback (v22), which writes to this exact
     * location when Android's MediaMetadataRetriever can't decode a file.
     */
    private fun thumbFileFor(path: String): File {
        val thumbsDir = File(cacheDir, "thumbs").apply { mkdirs() }
        return File(thumbsDir, md5(path) + ".jpg")
    }

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

            val thumbFile = thumbFileFor(path)

            val cacheValid =
                thumbFile.exists() && thumbFile.length() > 0 &&
                    thumbFile.lastModified() >= videoFile.lastModified()

            if (cacheValid) {
                out["thumbnailPath"] = thumbFile.absolutePath
            } else {
                // Grab a frame ~1s in (or the very first frame for tiny clips).
                val seekUs = if (durationMs != null && durationMs in 0..1500) 0L else 1_000_000L
                val frame = grabFrameSafely(
                    retriever, seekUs,
                    out["width"] as? Int, out["height"] as? Int
                )
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
    // `sub-add`. The model is downloaded once from Hugging Face (~142 MB
    // base / ~466 MB small); after that everything is offline & free.
    // ---------------------------------------------------------------------------

    // v22: "tiny" (~75 MB) returns as the explicit "Fast" choice - roughly
    // 4x quicker than base at some accuracy cost (the user picks it, eyes
    // open). Unknown ids still fall back to "base" (also covers stale ids
    // saved by older versions).
    private fun modelFileFor(name: String): File {
        val safe = when (name) {
            "tiny", "base", "small" -> name
            else -> "base"
        }
        return File(filesDir, "models/ggml-$safe.bin")
    }

    private fun modelUrlFor(name: String): String {
        return when (name) {
            "tiny" ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
            "small" ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
            else ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
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

    private fun runAiPipeline(
        jobId: Int,
        videoPath: String,
        modelName: String,
        language: String,
        translate: Boolean = false
    ) {
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

            // 3. Transcribe with whisper.cpp (offline), speech-gated:
            // the 16 kHz track is first split into voiced spans and only
            // those are sent to whisper. Long silent stretches of a video
            // are skipped entirely, which is FASTER (a big share of any
            // movie is non-speech) AND cleaner (whisper used to answer
            // silence with "music" hallucinations). Music is never treated
            // as silence, so speech over loud background music still gets
            // transcribed. A cancel between spans takes effect immediately;
            // a cancel mid-span discards the result afterwards.
            aiProgress(jobId, "transcribing", 0)
            val segments = ArrayList<HashMap<String, Any>>()
            runBlocking {
                var model: WhisperModel? = null
                try {
                    model = Whisper.loadModel(this@MainActivity, modelFile.absolutePath)
                    val pcmData = readWavPcm(wav) ?: ByteArray(0)
                    val spans = speechSpans(pcmData)
                    // spans empty = no voice anywhere -> empty result, and
                    // Dart shows its friendly "No speech detected" snack.
                    spans.forEachIndexed { i, span ->
                        if (aiCancelled) return@forEachIndexed
                        val spanWav = File(cacheDir, "ai_span_${jobId}_$i.wav")
                        try {
                            writeSpanWav(spanWav, pcmData, span[0], span[1])
                            // The user can pin a language ("hi", "ur", "en", ...)
                            // in the Generate dialog; "auto" = detect it. Pinning
                            // is noticeably more accurate than detection.
                            val res = Whisper.transcribe(
                                model,
                                spanWav.absolutePath,
                                WhisperConfig(
                                    language = language,
                                    translate = translate,
                                    // v22: use every core the phone offers -
                                    // whisper.cpp scales well to 8 threads,
                                    // roughly halving transcription time vs
                                    // the library default of 4.
                                    threads = Runtime.getRuntime()
                                        .availableProcessors()
                                        .coerceIn(2, 8),
                                )
                            )
                            val offsetMs = span[0] * 1000L / 16000
                            for (s in res.segments) {
                                val text = s.text.trim()
                                if (text.isEmpty()) continue
                                segments.add(
                                    hashMapOf(
                                        "start" to (s.startMs + offsetMs) as Any,
                                        "end" to (s.endMs + offsetMs) as Any,
                                        "text" to text as Any
                                    )
                                )
                            }
                        } finally {
                            spanWav.delete()
                        }
                        aiProgress(jobId, "transcribing", (i + 1) * 100 / spans.size)
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

    /** Reads the PCM data section of a 16 kHz mono 16-bit WAV we wrote
     * (i.e. everything after the 44-byte header). Null if unreadable. */
    private fun readWavPcm(wav: File): ByteArray? {
        return try {
            val bytes = wav.readBytes()
            if (bytes.size <= 44) null else bytes.copyOfRange(44, bytes.size)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Writes [pcm] samples in [fromSample, toSample) as a standalone 16 kHz
     * mono 16-bit WAV (header + raw little-endian data).
     */
    private fun writeSpanWav(out: File, pcm: ByteArray, fromSample: Int, toSample: Int) {
        val from = fromSample * 2
        val to = minOf(toSample * 2, pcm.size)
        val raf = RandomAccessFile(out, "rw")
        try {
            raf.setLength(0)
            writeWavHeader(raf, 16000, (to - from).toLong())
            raf.write(pcm, from, to - from)
        } finally {
            raf.close()
        }
    }

    /**
     * Speech-gate for the AI pipeline (v18): finds voiced spans in 16 kHz
     * mono 16-bit PCM (raw little-endian bytes, no header) and returns them
     * as [startSample, endSample) pairs - padded, gap-merged and chunked to
     * <=30 s so whisper's context window stays effective.
     *
     * Conservative by design: only true near-silence is dropped. The
     * threshold sits at ~2x the adaptive noise floor with a very low
     * absolute floor, so quiet speech is kept while digital/room silence is
     * skipped. Music is far above this floor and is therefore NEVER gated
     * out (speech over loud background music still reaches whisper).
     */
    private fun speechSpans(pcm: ByteArray): List<IntArray> {
        val frame = 400 // 25 ms at 16 kHz
        val totalSamples = pcm.size / 2
        val totalFrames = totalSamples / frame
        if (totalFrames < 8) return emptyList() // under 0.2 s of audio at all

        // RMS energy per 25 ms frame, straight from the raw bytes.
        val rms = DoubleArray(totalFrames)
        var i = 0
        while (i < totalFrames) {
            var sum = 0.0
            var j = 0
            val base = i * frame
            while (j < frame) {
                val idx = (base + j) * 2
                val s =
                    ((pcm[idx + 1].toInt() shl 8) or (pcm[idx].toInt() and 0xFF))
                        .toShort()
                        .toInt()
                sum += s * s
                j++
            }
            rms[i] = kotlin.math.sqrt(sum / frame)
            i++
        }

        // Adaptive threshold: ~2.2x the 20th-percentile frame energy (the
        // noise floor), but never below a conservative absolute floor.
        val sorted = rms.sorted()
        val noise = sorted[(totalFrames * 0.2).toInt().coerceIn(0, totalFrames - 1)]
        val threshold = maxOf(noise * 2.2, 260.0)

        // Voiced frames -> raw spans.
        val raw = mutableListOf<IntArray>()
        var start = -1
        i = 0
        while (i < totalFrames) {
            if (rms[i] >= threshold) {
                if (start < 0) start = i
            } else if (start >= 0) {
                raw.add(intArrayOf(start, i))
                start = -1
            }
            i++
        }
        if (start >= 0) raw.add(intArrayOf(start, totalFrames))
        if (raw.isEmpty()) return emptyList()

        // Merge spans separated by < 0.3 s (breaths / sentence gaps), then
        // pad 0.15 s on each side and drop remnants shorter than 0.4 s.
        val mergeGap = 12
        val pad = 6
        val merged = mutableListOf<IntArray>()
        var cur = raw[0]
        i = 1
        while (i < raw.size) {
            val n = raw[i]
            if (n[0] - cur[1] <= mergeGap) {
                cur[1] = n[1]
            } else {
                merged.add(cur)
                cur = n
            }
            i++
        }
        merged.add(cur)
        val padded = mutableListOf<IntArray>()
        for (m in merged) {
            val a = maxOf(0, m[0] - pad)
            val b = minOf(totalFrames, m[1] + pad)
            if (b - a >= 16) {
                padded.add(intArrayOf(a * frame, minOf(b * frame, totalSamples)))
            }
        }

        // Chunk anything longer than 30 s; split at the quietest frame near
        // the midpoint (best-effort word boundary), with a hard-split
        // fallback so the loop always makes progress.
        val maxFrames = 1200 // 30 s
        val chunked = mutableListOf<IntArray>()
        for (o in padded) {
            var s0 = o[0]
            val e0 = o[1]
            while (e0 - s0 > maxFrames * frame) {
                val midFrame = (s0 / frame + e0 / frame) / 2
                val win = 120 // +-3 s
                var best = midFrame
                var bestV = Double.MAX_VALUE
                var f = maxOf(s0 / frame + 16, midFrame - win)
                val fEnd = minOf(e0 / frame - 16, midFrame + win)
                while (f <= fEnd) {
                    if (f >= 0 && f < totalFrames && rms[f] < bestV) {
                        bestV = rms[f]
                        best = f
                    }
                    f++
                }
                val splitSample = best * frame
                if (splitSample <= s0 + frame * 16 || splitSample >= e0 - frame * 16) {
                    val hard = s0 + maxFrames * frame
                    chunked.add(intArrayOf(s0, hard))
                    s0 = hard
                } else {
                    chunked.add(intArrayOf(s0, splitSample))
                    s0 = splitSample
                }
            }
            chunked.add(intArrayOf(s0, e0))
        }
        return chunked
    }

    // -----------------------------------------------------------------------
    // v19: sensor-driven rotation + scrub thumbnail strip
    // -----------------------------------------------------------------------

    private var rotateListener: OrientationEventListener? = null
    private var rotateLocked = false

    private fun ensureRotateListener() {
        if (rotateListener != null) return
        rotateListener = object : OrientationEventListener(
            this, SensorManager.SENSOR_DELAY_NORMAL
        ) {
            override fun onOrientationChanged(angle: Int) {
                if (angle == ORIENTATION_UNKNOWN || rotateLocked) return
                // 45-degree quadrants, no upside-down portrait. Explicit
                // requestedOrientation applies even while the phone's
                // system auto-rotate is OFF - that is the whole point.
                val target = when {
                    angle in 45..134 ->
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                    angle in 225..314 ->
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    else ->
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
                if (requestedOrientation != target) requestedOrientation = target
            }
        }
    }

    /**
     * Builds (or reuses) a strip of 72 small JPEG frames for the scrub
     * preview bubble. Returns the strip directory path, or null for
     * streams / unreadable files. Runs on the executor; reusing a cached
     * strip is instant.
     */
    private fun thumbStripEnsureSync(path: String?): String? {
        if (path.isNullOrEmpty() || path.startsWith("http")) return null
        val src = File(path)
        if (!src.exists()) return null
        val count = 72
        val dir = File(cacheDir, "thumbstrip_" + md5(path))
        try {
            if (dir.isDirectory) {
                val have =
                    dir.listFiles()?.count { it.name.endsWith(".jpg") } ?: 0
                if (have >= count) return dir.absolutePath
            }
            val retriever = android.media.MediaMetadataRetriever()
            try {
                retriever.setDataSource(path)
                val durMs = retriever.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
                )?.toLongOrNull() ?: 0L
                if (durMs <= 0L) return null
                dir.mkdirs()
                for (i in 0 until count) {
                    val us = durMs * 1000L * i / (count - 1)
                    val frame = try {
                        retriever.getFrameAtTime(
                            us,
                            android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                        )
                    } catch (e: Exception) {
                        null
                    }
                    if (frame != null) {
                        val thumb = scaleToWidth(frame, 192)
                        FileOutputStream(File(dir, "f_%03d.jpg".format(i)))
                            .use { out ->
                                thumb.compress(
                                    Bitmap.CompressFormat.JPEG, 72, out
                                )
                            }
                        if (thumb !== frame) thumb.recycle()
                        frame.recycle()
                    }
                }
            } finally {
                retriever.release()
            }
            return dir.absolutePath
        } catch (t: Throwable) {
            return null
        }
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

mkdir -p "$(dirname 'lib/services/native_bridge.dart')"
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
  /// (`onAiProgress` / `onAiDone` / `onAiFailed`). [model] is tiny/base/
  /// small; [language] is a whisper language code or 'auto' (detect).
  static Future<int?> aiSubtitleGenerate({
    required String videoPath,
    String model = 'base',
    String language = 'auto',
    // v21: whisper's translate task - any spoken language -> English subs.
    bool translate = false,
  }) async {
    try {
      return await _channel.invokeMethod<int>(
        'aiSubtitleGenerate',
        {
          'videoPath': videoPath,
          'model': model,
          'language': language,
          'translate': translate,
        },
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

  /// v22: the cache-file path the native scanner uses for [path]'s
  /// thumbnail (null for streams/missing files). The player writes an
  /// mpv-captured frame there when Android can't decode one itself.
  static Future<String?> thumbnailPathFor(String path) async {
    try {
      return await _channel
          .invokeMethod<String>('thumbnailPathFor', {'path': path});
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
      return await _channel
          .invokeMethod<String>('thumbStripEnsure', {'path': path});
    } catch (_) {
      return null;
    }
  }
}
EOF_MARKER_1

mkdir -p "$(dirname 'lib/state/media_player_state.dart')"
cat > 'lib/state/media_player_state.dart' <<'EOF_MARKER_2'
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../models/history_entry.dart';
import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../utils/formatters.dart';
import '../utils/srt.dart';
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
  Timer? _uiTicker;
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
        _checkSleepAtEnd(v); // "sleep at end of video" timer
        _maybeCaptureThumb(v); // 4K/HDR thumbnail fallback (v22)
        notifyListeners();
      }),
      player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
        // Kick off scrub-preview thumbnail generation (idempotent - runs
        // once per file, cached on disk afterwards).
        _ensureThumbStrip();
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
        // Karaoke mode: switching to a real subtitle track flips the
        // overlay on (and mpv's own rendering off) immediately.
        if (karaokeMode) unawaited(_applySubVisibility());
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
    // v19: guaranteed UI pulse - the mini player / scrub bar / time labels
    // keep ticking even if the position stream coalesces (the home-screen
    // mini player's progress bar looked frozen because of that).
    _uiTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      // v22: also pulse while a sleep timer runs so the under-title
      // countdown keeps counting even when playback is paused.
      if (!isPlaying && !sleepTimerActive) return;
      final p = player.state.position;
      if (p != position || sleepTimerActive) {
        position = p;
        _maybeCaptureThumb(p);
        notifyListeners();
      }
    });
    _startLiveSubObserver();
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
    final plat = player.platform;
    if (plat is NativePlayer) {
      // Head-room for the 200% volume boost + re-apply the current gain /
      // leveling filter for the new file.
      unawaited(plat.setProperty('volume-max', '200'));
      // Force the sub-visibility to be re-pushed for the new file (mpv may
      // reset it at open, while our cache would think it's still applied).
      _appliedSubVisibility = null;
    }
    await player.open(Media(track.path), play: autoplay);
    await player.setRate(playbackRate);
    await _applyMpvVolume();
    await _applyAudioFilters(); // equalizer + leveling survive file changes
    await _attachSidecarSubtitles(track.path);
    await _recordOpen(track);
    await _restoreBookmark(track);
    // v22: if this file has no cached thumbnail AND Android's metadata
    // engine could not make one, remember it - after ~1.5 s of playback a
    // frame is captured through mpv instead (see _maybeCaptureThumb).
    _pendingThumbFor =
        (track.thumbnailPath == null && !track.path.contains('://'))
            ? track.path
            : null;
  }

  /// Re-attaches previously generated AI subtitles ("<video>.maxai.srt"
  /// next to the video) so they survive closing/reopening the app - they
  /// are written to disk, only the player session forgot them.
  /// v21: cues of the AI sidecar currently attached (null when none or the
  /// file is a stream). Feeds the karaoke word-highlight overlay.
  List<SrtCue>? aiCues;

  /// v22: cues parsed from the video's OWN same-name subtitle file
  /// ("movie.srt", "movie.en.srt" - the files mpv auto-loads). Used when
  /// there is no AI sidecar, so karaoke + skip-intro work on ordinary
  /// subtitled videos too.
  List<SrtCue>? sidecarCues;

  /// v21 skip-intro chip: where the dialogue actually starts, when
  /// subtitles (AI sidecar or same-name .srt) show speech begins
  /// noticeably late (see computeSkipIntro).
  Duration? skipIntroAt;

  Future<void> _attachSidecarSubtitles(String videoPath) async {
    aiCues = null;
    sidecarCues = null;
    skipIntroAt = null;
    liveSubCue = null;
    if (videoPath.contains('://')) return; // no sidecars for streams
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      final srt = srtPathForVideo(videoPath);
      if (File(srt).existsSync()) {
        // "select" makes it the active track right away.
        await platform.command(['sub-add', srt, 'select']);
        await refreshAiCues(videoPath);
      }
    } catch (_) {
      // Missing/unreadable sidecar is not fatal.
    }
    // v22: no AI captions -> look for the video's own subtitle file and
    // use it as the skip-intro + karaoke source instead.
    if (aiCues == null) {
      try {
        final cues = await _loadSidecarCues(videoPath);
        if (cues != null && cues.isNotEmpty) sidecarCues = cues;
      } catch (_) {
        // An unreadable sibling file must never break playback.
      }
    }
    _recomputeSkipIntro();
    await _applySubVisibility();
    notifyListeners();
  }

  /// Parses the best same-name .srt sitting next to [videoPath], if any.
  Future<List<SrtCue>?> _loadSidecarCues(String videoPath) async {
    final dir = Directory(p.dirname(videoPath));
    if (!dir.existsSync()) return null;
    final names = <String>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is File) names.add(p.basename(e.path));
    }
    final candidates = sidecarSrtCandidates(names, videoPath);
    if (candidates.isEmpty) return null;
    final cues = parseSrt(
      await File(p.join(dir.path, candidates.first)).readAsString(),
    );
    return cues.isEmpty ? null : cues;
  }

  void _recomputeSkipIntro() {
    // AI captions win (word-accurate); same-name .srt is the fallback.
    final cues = aiCues ?? sidecarCues;
    skipIntroAt = cues == null ? null : computeSkipIntro(cues);
  }

  /// (Re)parses the AI sidecar for karaoke + skip-intro. Called when a track
  /// attaches its sidecar, and by the AI runner right after it finishes
  /// writing new subtitles.
  Future<void> refreshAiCues(String videoPath) async {
    aiCues = null;
    if (videoPath.contains('://')) return;
    try {
      final srt = File(srtPathForVideo(videoPath));
      if (!srt.existsSync()) return;
      final cues = parseSrt(await srt.readAsString());
      if (cues.isEmpty) return;
      aiCues = cues;
    } catch (_) {
      // A corrupt sidecar must never break playback.
    }
    _recomputeSkipIntro();
    await _applySubVisibility();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Karaoke mode + live subtitle reading (v22)
  // ---------------------------------------------------------------------------

  /// Whether karaoke rendering is enabled (mirrors the player setting).
  bool karaokeMode = false;

  /// The subtitle line mpv is showing RIGHT NOW (from its `sub-text` /
  /// `sub-start` / `sub-end` properties), with real cue timing. This makes
  /// karaoke work with ANY subtitle - embedded mkv tracks included - not
  /// just ones we can parse as files.
  SrtCue? liveSubCue;

  /// Last sub-visibility value we pushed to mpv (avoids redundant sets).
  String? _appliedSubVisibility;

  Future<void> _startLiveSubObserver() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.observeProperty('sub-text', (text) async {
        final plat = player.platform;
        if (text.trim().isEmpty || plat is! NativePlayer) {
          if (liveSubCue != null) {
            liveSubCue = null;
            notifyListeners();
          }
          return;
        }
        var startMs = 0;
        var endMs = 0;
        try {
          startMs = ((double.tryParse(
                          await plat.getProperty('sub-start')) ??
                      0) *
                  1000)
              .round();
          endMs = ((double.tryParse(await plat.getProperty('sub-end')) ??
                      0) *
                  1000)
              .round();
        } catch (_) {}
        if (endMs <= startMs) endMs = startMs + 2000; // sane fallback
        final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        liveSubCue = isMusicOnlyText(clean)
            ? null
            : SrtCue(startMs, endMs, clean);
        notifyListeners();
      });
    } catch (_) {
      // Older engine - karaoke simply falls back to parsed cue files.
    }
  }

  /// Player-settings-driven: turn karaoke mode on/off. Hides mpv's own
  /// subtitle rendering (our overlay takes over) whenever a usable
  /// subtitle source exists.
  Future<void> setKaraokeMode(bool on) async {
    karaokeMode = on;
    await _applySubVisibility();
  }

  Future<void> _applySubVisibility() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final hide = karaokeMode &&
        (subtitlesActive || aiCues != null || sidecarCues != null);
    final want = hide ? 'no' : 'yes';
    if (want == _appliedSubVisibility) return;
    _appliedSubVisibility = want;
    try {
      await platform.setProperty('sub-visibility', want);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 4K/HDR thumbnail fallback (v22)
  //
  // Android's MediaMetadataRetriever gives up on some 4K/HDR (10-bit HEVC,
  // certain mkv) files, so their library tiles stayed placeholder-grey.
  // mpv plays those same files fine - so once such a video has been playing
  // for ~1.5 s we ask mpv for a frame and write it to the exact cache file
  // the native scanner uses, then shrink it to the standard 320px width.
  // ---------------------------------------------------------------------------

  /// Video awaiting a playback-captured thumbnail.
  String? _pendingThumbFor;

  /// Wired by main.dart: (videoPath, thumbPath) -> live-updates the
  /// library tile so the image appears without a rescan.
  void Function(String videoPath, String thumbPath)? onThumbnailCaptured;

  void _maybeCaptureThumb(Duration pos) {
    final path = _pendingThumbFor;
    if (path == null || pos < const Duration(milliseconds: 1500)) return;
    _pendingThumbFor = null;
    unawaited(_captureThumbWithMpv(path));
  }

  Future<void> _captureThumbWithMpv(String videoPath) async {
    try {
      final platform = player.platform;
      if (platform is! NativePlayer) return;
      final target = await NativeBridge.thumbnailPathFor(videoPath);
      if (target == null) return;
      final thumb = File(target);
      if (thumb.existsSync()) return; // scanner beat us to it meanwhile
      final tmp = File('$target.capture');
      if (tmp.existsSync()) await tmp.delete();
      await platform.setProperty('screenshot-format', 'jpg');
      await platform.setProperty('screenshot-jpeg-quality', '82');
      await platform.command(['screenshot-to-file', tmp.path, 'video']);
      // mpv encodes the shot asynchronously - wait briefly for the file.
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (tmp.existsSync() && tmp.lengthSync() > 0) break;
      }
      if (!tmp.existsSync() || tmp.lengthSync() == 0) return;
      // A 4K screenshot decodes to a ~33 MB bitmap; shrink to the same
      // 320px width the native scanner writes, so scrolling the library
      // never decodes a giant image.
      final data = await tmp.readAsBytes();
      final codec = await ui.instantiateImageCodec(data, targetWidth: 320);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (png == null) return;
      await thumb.writeAsBytes(png.buffer.asUint8List(), flush: true);
      await tmp.delete();
      onThumbnailCaptured?.call(videoPath, target);
    } catch (_) {
      // Worst case: the tile keeps its movie-icon placeholder.
    }
  }

  // ---------------------------------------------------------------------------
  // Sleep timer (v21)
  // ---------------------------------------------------------------------------

  Timer? _sleepTimer;
  DateTime? _sleepFireAt;
  bool _sleepAtEndOfVideo = false;

  bool get sleepTimerActive => _sleepFireAt != null || _sleepAtEndOfVideo;

  /// Short label for menus ("12 min" / "end of video"); null when inactive.
  String? get sleepTimerLabel {
    if (_sleepAtEndOfVideo) return 'end of video';
    final at = _sleepFireAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now()).inSeconds;
    if (left <= 0) return null;
    return '${(left + 30) ~/ 60} min'; // rounded while counting down
  }

  /// v22: precise live countdown for the player top bar ("23:41" or
  /// "end of video"); null when no timer runs. The state pulses every
  /// 500 ms while a timer is active, so this ticks visibly.
  String? get sleepTimerCountdown {
    if (_sleepAtEndOfVideo) return 'end of video';
    final at = _sleepFireAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now());
    return left.inSeconds <= 0 ? null : formatCountdown(left.inSeconds);
  }

  void setSleepTimer({Duration? forDuration, bool atEndOfVideo = false}) {
    cancelSleepTimer();
    if (atEndOfVideo) {
      _sleepAtEndOfVideo = true;
    } else if (forDuration != null) {
      _sleepFireAt = DateTime.now().add(forDuration);
      _sleepTimer = Timer(forDuration, _fireSleepTimer);
    }
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepFireAt = null;
    _sleepAtEndOfVideo = false;
    notifyListeners();
  }

  Future<void> _fireSleepTimer() async {
    cancelSleepTimer();
    _notices.add('Sleep timer paused playback');
    await pause();
  }

  void _checkSleepAtEnd(Duration pos) {
    if (!_sleepAtEndOfVideo || duration <= Duration.zero) return;
    if (duration - pos <= const Duration(milliseconds: 1500)) {
      cancelSleepTimer();
      _notices.add('Sleep timer: stopped at end of video');
      pause();
    }
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
    // v19: optimistic UI - flip the icon instantly; the playing stream
    // confirms (or corrects) a moment later. Kills the visible tap->icon
    // lag that made the play/pause button feel delayed.
    final wantPlay = !isPlaying;
    isPlaying = wantPlay;
    notifyListeners();
    if (wantPlay) {
      await player.play();
    } else {
      await pause();
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
    // v20: pause FIRST so the video freezes instantly. The previous order
    // (boost cleanup + bookmark disk write BEFORE pausing) added a visible
    // delay between tapping pause and the video actually stopping.
    await player.pause();
    // Pausing always ends an active long-press boost (and its badge).
    await stopSpeedBoost();
    _saveBookmark();
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

  /// v21: when the setting is on, the volume range becomes 0..200%.
  /// The device volume covers 0..100%; mpv's decoder gain (volume-max=200
  /// is set when a track opens) covers the 100..200% boost region.
  bool volumeBoost200 = false;

  /// Current volume upper limit for the swipe gesture / slider math.
  double get volumeCap => volumeBoost200 ? 2.0 : 1.0;

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, volumeCap);
    if (volume > 0) {
      isMuted = false;
      _preMuteVolume = volume;
    }
    await NativeBridge.setMediaVolume(isMuted ? 0 : volume.clamp(0.0, 1.0));
    await _applyMpvVolume();
    notifyListeners();
  }

  Future<void> _applyMpvVolume() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final pct = volume <= 1 ? 100.0 : volume * 100.0;
    try {
      await platform.setProperty('volume', pct.toStringAsFixed(0));
    } catch (_) {}
  }

  /// Settings toggle: enable/disable the 200% boost region. Turning it off
  /// while boosted pulls the volume back to 100%.
  Future<void> setVolumeBoost200(bool on) async {
    volumeBoost200 = on;
    if (!on && volume > 1.0) await setVolume(1.0);
    if (!on) await _applyMpvVolume();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Volume leveling (v21) - mpv dynaudnorm: quiet dialogue and loud
  // explosions come out at a steady level.
  // v22: merged with the equalizer into ONE mpv `af` chain (both used to
  // overwrite the whole property, silently cancelling each other), the
  // window was widened so the effect is actually audible, and the applied
  // chain is read back once - if this engine build lacks dynaudnorm the
  // user is told instead of the toggle doing nothing.
  // ---------------------------------------------------------------------------

  static const String kLevelingFilter = 'dynaudnorm=f=150:g=15:m=5:p=0.95';
  bool _levelingOn = false;
  bool _levelingWarned = false;
  bool get volumeLeveling => _levelingOn;

  Future<void> setVolumeLeveling(bool on) async {
    _levelingOn = on;
    notifyListeners();
    await _applyAudioFilters();
  }

  /// The single writer of mpv's `af` property: equalizer bands + leveling
  /// combined. Replaces the old pair of writers that clobbered each other.
  Future<void> _applyAudioFilters() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final chain = <String>[
      if (eqEnabled) buildEqualizerFilter(eqGains),
      if (_levelingOn) kLevelingFilter,
    ].join(',');
    try {
      await platform.setProperty('af', chain);
      if (_levelingOn && !_levelingWarned) {
        final applied = await platform.getProperty('af');
        if (!applied.contains('dynaudnorm')) {
          _levelingWarned = true;
          _notices.add(
            'Volume leveling is not supported by this video engine build',
          );
        }
      }
    } catch (_) {}
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

  Future<void> _applyEqFilter() => _applyAudioFilters(); // v22: shared chain

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
  // Scrub preview thumbnail strip (v19)
  // ---------------------------------------------------------------------------

  /// Frames generated per video - must match the native generator
  /// (MainActivity.thumbStripEnsureSync).
  static const int thumbStripCount = 72;

  String? _thumbStripFor;
  String? _thumbStripDir;

  void _ensureThumbStrip() {
    final track = currentTrack;
    if (track == null) return;
    final path = track.path;
    if (path.startsWith('http')) return; // streams: nothing on disk to scan
    if (_thumbStripFor == path) return; // already requested for this file
    _thumbStripFor = path;
    _thumbStripDir = null;
    NativeBridge.thumbStripEnsure(path).then((dir) {
      if (dir != null && _thumbStripFor == path) {
        _thumbStripDir = dir;
        notifyListeners();
      }
    });
  }

  /// Thumbnail file for the preview bubble at [fraction] (0..1 of the
  /// video), or null while that frame hasn't been generated yet (the
  /// bubble then shows the timestamp only).
  String? scrubThumbPath(double fraction) {
    final dir = _thumbStripDir;
    if (dir == null) return null;
    final i = (fraction.clamp(0.0, 1.0) * (thumbStripCount - 1)).round();
    final f = File('$dir/f_${i.toString().padLeft(3, '0')}.jpg');
    return f.existsSync() ? f.path : null;
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
    _uiTicker?.cancel();
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

mkdir -p "$(dirname 'lib/state/player_settings.dart')"
cat > 'lib/state/player_settings.dart' <<'EOF_MARKER_3'
import '../services/native_bridge.dart';

/// Immutable snapshot of the customizable player settings (gestures, auto
/// hide, resume). Persisted through the native settings store so only plain
/// key/value strings cross the MethodChannel - no extra plugin deps.
class PlayerSettings {
  final bool doubleTapSeek;
  final int seekSeconds;
  final bool doubleTapPlayPause;
  final bool volumeSwipe;
  final bool brightnessSwipe;
  final bool pinchZoom;

  /// Hold a finger on the video to temporarily play faster.
  final bool longPressSpeed;

  /// Multiplier applied while long-pressing (1.5 / 2.0 / 2.5 / 3.0).
  final double longPressMultiplier;

  /// Seconds of inactivity before the controls vanish. 0 = never auto-hide.
  final int autoHideSeconds;

  /// Reopen a video where you left off (backed by the watch history).
  final bool resumePlayback;

  /// Drag horizontally anywhere on the video to scrub through it.
  final bool horizontalSeek;

  /// Show the "Cast to TV" (DLNA) button in the player top bar.
  final bool castButton;

  /// Show the screenshot button in the player top bar.
  final bool screenshotButton;

  /// Show the screen-lock (kids mode) button on the video.
  final bool lockButton;

  /// v21: playback extras.
  /// Volume slider/drag may go past 100% up to 200% (mpv decoder gain).
  final bool volumeBoost200;

  /// mpv dynaudnorm: loud explosions and quiet dialogue evened out.
  final bool volumeLeveling;

  /// Karaoke-style word highlight for AI subtitles.
  final bool karaokeSubs;

  /// Offer a "Skip intro" chip when AI subtitles show the dialogue starts
  /// noticeably after the video start.
  final bool skipIntroChip;

  const PlayerSettings({
    this.doubleTapSeek = true,
    this.seekSeconds = 10,
    this.doubleTapPlayPause = true,
    this.volumeSwipe = true,
    this.brightnessSwipe = true,
    this.pinchZoom = true,
    this.longPressSpeed = true,
    this.longPressMultiplier = 2.0,
    this.autoHideSeconds = 4,
    this.resumePlayback = true,
    this.horizontalSeek = true,
    this.castButton = true,
    this.screenshotButton = true,
    this.lockButton = true,
    // v22: ON by default ("volume up to 200% out of the box"); only people
    // who explicitly turned it off keep it off (saved 'false' below).
    this.volumeBoost200 = true,
    this.volumeLeveling = false,
    this.karaokeSubs = false,
    this.skipIntroChip = true,
  });

  // Persisted keys (MediaPlayerState reads the resume key directly).
  static const String kDoubleTapSeek = 'player.doubleTapSeek';
  static const String kSeekSeconds = 'player.seekSeconds';
  static const String kDoubleTapPlayPause = 'player.doubleTapPlayPause';
  static const String kVolumeSwipe = 'player.volumeSwipe';
  static const String kBrightnessSwipe = 'player.brightnessSwipe';
  static const String kPinchZoom = 'player.pinchZoom';
  static const String kLongPressSpeed = 'player.longPressSpeed';
  static const String kLongPressMultiplier = 'player.longPressMultiplier';
  static const String kAutoHideSeconds = 'player.autoHideSeconds';
  static const String kResumePlayback = 'player.resumePlayback';
  static const String kHorizontalSeek = 'player.horizontalSeek';
  static const String kCastButton = 'player.castButton';
  static const String kScreenshotButton = 'player.screenshotButton';
  static const String kLockButton = 'player.lockButton';
  static const String kVolumeBoost200 = 'player.volumeBoost200';
  static const String kVolumeLeveling = 'player.volumeLeveling';
  static const String kKaraokeSubs = 'player.karaokeSubs';
  static const String kSkipIntroChip = 'player.skipIntroChip';

  static Future<PlayerSettings> load() async {
    final s = await NativeBridge.loadSettings();
    const d = PlayerSettings();
    return PlayerSettings(
      doubleTapSeek: s[kDoubleTapSeek] != 'false',
      seekSeconds: int.tryParse(s[kSeekSeconds] ?? '') ?? d.seekSeconds,
      doubleTapPlayPause: s[kDoubleTapPlayPause] != 'false',
      volumeSwipe: s[kVolumeSwipe] != 'false',
      brightnessSwipe: s[kBrightnessSwipe] != 'false',
      pinchZoom: s[kPinchZoom] != 'false',
      longPressSpeed: s[kLongPressSpeed] != 'false',
      longPressMultiplier:
          double.tryParse(s[kLongPressMultiplier] ?? '') ??
              d.longPressMultiplier,
      autoHideSeconds:
          int.tryParse(s[kAutoHideSeconds] ?? '') ?? d.autoHideSeconds,
      resumePlayback: s[kResumePlayback] != 'false',
      horizontalSeek: s[kHorizontalSeek] != 'false',
      castButton: s[kCastButton] != 'false',
      screenshotButton: s[kScreenshotButton] != 'false',
      lockButton: s[kLockButton] != 'false',
      volumeBoost200: s[kVolumeBoost200] != 'false', // v22: default on
      volumeLeveling: s[kVolumeLeveling] == 'true',
      karaokeSubs: s[kKaraokeSubs] == 'true',
      skipIntroChip: s[kSkipIntroChip] != 'false',
    );
  }

  Future<void> save() {
    NativeBridge.saveSetting(kDoubleTapSeek, '$doubleTapSeek');
    NativeBridge.saveSetting(kSeekSeconds, '$seekSeconds');
    NativeBridge.saveSetting(kDoubleTapPlayPause, '$doubleTapPlayPause');
    NativeBridge.saveSetting(kVolumeSwipe, '$volumeSwipe');
    NativeBridge.saveSetting(kBrightnessSwipe, '$brightnessSwipe');
    NativeBridge.saveSetting(kPinchZoom, '$pinchZoom');
    NativeBridge.saveSetting(kLongPressSpeed, '$longPressSpeed');
    NativeBridge.saveSetting(
        kLongPressMultiplier, longPressMultiplier.toStringAsFixed(1));
    NativeBridge.saveSetting(kAutoHideSeconds, '$autoHideSeconds');
    NativeBridge.saveSetting(kResumePlayback, '$resumePlayback');
    NativeBridge.saveSetting(kHorizontalSeek, '$horizontalSeek');
    NativeBridge.saveSetting(kCastButton, '$castButton');
    NativeBridge.saveSetting(kScreenshotButton, '$screenshotButton');
    NativeBridge.saveSetting(kLockButton, '$lockButton');
    NativeBridge.saveSetting(kVolumeBoost200, '$volumeBoost200');
    NativeBridge.saveSetting(kVolumeLeveling, '$volumeLeveling');
    NativeBridge.saveSetting(kKaraokeSubs, '$karaokeSubs');
    return NativeBridge.saveSetting(kSkipIntroChip, '$skipIntroChip');
  }

  PlayerSettings copyWith({
    bool? doubleTapSeek,
    int? seekSeconds,
    bool? doubleTapPlayPause,
    bool? volumeSwipe,
    bool? brightnessSwipe,
    bool? pinchZoom,
    bool? longPressSpeed,
    double? longPressMultiplier,
    int? autoHideSeconds,
    bool? resumePlayback,
    bool? horizontalSeek,
    bool? castButton,
    bool? screenshotButton,
    bool? lockButton,
    bool? volumeBoost200,
    bool? volumeLeveling,
    bool? karaokeSubs,
    bool? skipIntroChip,
  }) {
    return PlayerSettings(
      doubleTapSeek: doubleTapSeek ?? this.doubleTapSeek,
      seekSeconds: seekSeconds ?? this.seekSeconds,
      doubleTapPlayPause: doubleTapPlayPause ?? this.doubleTapPlayPause,
      volumeSwipe: volumeSwipe ?? this.volumeSwipe,
      brightnessSwipe: brightnessSwipe ?? this.brightnessSwipe,
      pinchZoom: pinchZoom ?? this.pinchZoom,
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
      longPressMultiplier: longPressMultiplier ?? this.longPressMultiplier,
      autoHideSeconds: autoHideSeconds ?? this.autoHideSeconds,
      resumePlayback: resumePlayback ?? this.resumePlayback,
      horizontalSeek: horizontalSeek ?? this.horizontalSeek,
      castButton: castButton ?? this.castButton,
      screenshotButton: screenshotButton ?? this.screenshotButton,
      lockButton: lockButton ?? this.lockButton,
      volumeBoost200: volumeBoost200 ?? this.volumeBoost200,
      volumeLeveling: volumeLeveling ?? this.volumeLeveling,
      karaokeSubs: karaokeSubs ?? this.karaokeSubs,
      skipIntroChip: skipIntroChip ?? this.skipIntroChip,
    );
  }
}
EOF_MARKER_3

mkdir -p "$(dirname 'lib/state/theme_state.dart')"
cat > 'lib/state/theme_state.dart' <<'EOF_MARKER_4'
import 'package:flutter/material.dart';

import '../services/native_bridge.dart';

/// App-wide accent color state. A single global instance ([themeState]) is
/// fine here - main.dart rebuilds MaterialApp when it notifies, which
/// refreshes every screen. Widgets read [ThemeState.accent] directly so
/// no InheritedWidget plumbing is needed.
class ThemeState extends ChangeNotifier {
  /// Selectable accent colors (first = brand purple default).
  static const List<Color> swatches = [
    Color(0xFFA855F7), // purple (default)
    Color(0xFF22D3EE), // cyan
    Color(0xFF34D399), // green
    Color(0xFFFB923C), // orange
    Color(0xFFF472B6), // pink
    Color(0xFF60A5FA), // blue
    Color(0xFFFFFFFF), // white (v22)
  ];

  static const String _kAccentKey = 'theme.accent';

  Color _accent = swatches.first;
  Color get accent => _accent;

  /// Text/icon color to paint ON TOP of the accent (light accents like
  /// white need dark ink, the rest use white).
  Color get onAccent => contrastColorFor(_accent);

  Future<void> load() async {
    final s = await NativeBridge.loadSettings();
    final v = int.tryParse(s[_kAccentKey] ?? '');
    if (v != null) {
      final match = swatches.where((c) => c.toARGB32() == v);
      _accent = match.isNotEmpty ? match.first : Color(v);
      notifyListeners();
    }
  }

  void setAccent(Color c) {
    _accent = c;
    notifyListeners();
    NativeBridge.saveSetting(_kAccentKey, '${c.toARGB32()}');
  }
}

/// The one app-wide instance.
final ThemeState themeState = ThemeState();

/// Text/icon color that stays readable ON a [c]-coloured surface. Pure +
/// unit-tested (v22: this is what keeps the speed badge visible on the
/// white accent).
Color contrastColorFor(Color c) {
  final argb = c.toARGB32();
  // Perceived luminance (WCAG-ish), cheap and fine for our swatches.
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final lum = 0.299 * r + 0.587 * g + 0.114 * b;
  return lum > 160 ? const Color(0xFF16161f) : Colors.white;
}
EOF_MARKER_4

mkdir -p "$(dirname 'lib/state/video_library_state.dart')"
cat > 'lib/state/video_library_state.dart' <<'EOF_MARKER_5'
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../utils/formatters.dart';

class ScanProgress {
  final int found;
  final int processed;
  final int total;
  const ScanProgress({this.found = 0, this.processed = 0, this.total = 0});
}

/// One section in the library when grouping is enabled.
class VideoGroup {
  final String title;
  final List<VideoTrack> videos;
  const VideoGroup(this.title, this.videos);
}

/// Parses an enum value from its persisted name, falling back to [fallback].
T _parseEnum<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Mirrors the web app's useVideoLibrary hook, simplified to a single flow:
/// request storage permission, then scan all of internal storage for videos.
/// No folder picker - file_picker's Android implementation proved
/// incompatible with the current AGP 9 / Kotlin 2.3 / Flutter 3.44 toolchain.
///
/// Also owns all VLC-style display settings (view mode, favourites, grouping,
/// playback action, sorting) and persists them through [NativeBridge].
class VideoLibraryState extends ChangeNotifier {
  List<VideoTrack> _videos = [];
  bool isScanning = false;
  ScanProgress scanProgress = const ScanProgress();
  String? folderName;
  bool permissionDenied = false;

  String searchQuery = '';
  SortMode sortMode = SortMode.name;
  bool sortAscending = true;

  // --- VLC-style display settings (persisted) ---
  ViewMode viewMode = ViewMode.grid;
  GroupMode groupMode = GroupMode.none;
  PlaybackAction playbackAction = PlaybackAction.all;
  bool favoritesOnly = false;
  Set<String> _favoritePaths = {};

  bool _disposed = false;

  static const String _internalStorageRoot = '/storage/emulated/0/';

  /// Folders under internal storage that are never worth scanning for videos
  /// (app-private caches, thumbnails, etc) - skipping these keeps the
  /// whole-device scan fast and avoids permission-denied noise.
  static const List<String> _skipDirNames = [
    'Android', // app-private data/obb, largely inaccessible + irrelevant anyway
    '.thumbnails',
    '.trashed',
    'cache',
  ];

  VideoLibraryState() {
    _loadSettings();
  }

  // ---------------------------------------------------------------------------
  // Derived views
  // ---------------------------------------------------------------------------

  List<VideoTrack> get videos {
    final filtered = _videos.where((v) {
      if (favoritesOnly && !_favoritePaths.contains(v.path)) return false;
      if (searchQuery.isEmpty) return true;
      return v.title.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    filtered.sort(_compareTracks);
    return filtered;
  }

  /// [videos] split into groups per [groupMode]. With [GroupMode.none] this
  /// returns a single unnamed group - the UI can always render [groups].
  List<VideoGroup> get groups {
    final visible = videos;
    if (groupMode == GroupMode.none) {
      return [VideoGroup('', visible)];
    }
    final byKey = <String, List<VideoTrack>>{};
    for (final v in visible) {
      final key = groupMode == GroupMode.folder ? v.folderName : _nameKey(v.title);
      byKey.putIfAbsent(key, () => []).add(v);
    }
    final keys = byKey.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [for (final k in keys) VideoGroup(k, byKey[k]!)];
  }

  int get allVideosCount => _videos.length;
  int get favoriteCount => _favoritePaths.length;
  bool isFavorite(VideoTrack track) => _favoritePaths.contains(track.path);

  int _compareTracks(VideoTrack a, VideoTrack b) {
    int cmp;
    switch (sortMode) {
      case SortMode.name:
        cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        break;
      case SortMode.date:
        cmp = (a.lastModifiedMs ?? 0).compareTo(b.lastModifiedMs ?? 0);
        break;
      case SortMode.size:
        cmp = (a.sizeBytes ?? 0).compareTo(b.sizeBytes ?? 0);
        break;
      case SortMode.length:
        // Videos with unknown duration always sink to the bottom,
        // whichever direction is active.
        final av = a.duration?.inMilliseconds;
        final bv = b.duration?.inMilliseconds;
        if (av == null && bv == null) {
          cmp = 0;
        } else if (av == null) {
          return 1;
        } else if (bv == null) {
          return -1;
        } else {
          cmp = av.compareTo(bv);
        }
        break;
    }
    return sortAscending ? cmp : -cmp;
  }

  /// First A-Z/0-9 character of the title, '#' otherwise (VLC-style buckets).
  static String _nameKey(String title) {
    if (title.isEmpty) return '#';
    final c = title[0].toUpperCase();
    return RegExp(r'[A-Z0-9]').hasMatch(c) ? c : '#';
  }

  // ---------------------------------------------------------------------------
  // Settings mutators (persisted)
  // ---------------------------------------------------------------------------

  void setSearchQuery(String q) {
    searchQuery = q;
    notifyListeners();
  }

  void setSortMode(SortMode m) {
    sortMode = m;
    _persist();
    notifyListeners();
  }

  void toggleSortDirection() {
    sortAscending = !sortAscending;
    _persist();
    notifyListeners();
  }

  /// One-shot setter used by the display-settings sheet - selecting e.g.
  /// "A → Z" fixes both the mode and the direction, like in VLC.
  void setSort(SortMode mode, bool ascending) {
    sortMode = mode;
    sortAscending = ascending;
    _persist();
    notifyListeners();
  }

  void setViewMode(ViewMode mode) {
    viewMode = mode;
    _persist();
    notifyListeners();
  }

  void setGroupMode(GroupMode mode) {
    groupMode = mode;
    _persist();
    notifyListeners();
  }

  void setPlaybackAction(PlaybackAction action) {
    playbackAction = action;
    _persist();
    notifyListeners();
  }

  void setFavoritesOnly(bool value) {
    favoritesOnly = value;
    _persist();
    notifyListeners();
  }

  void toggleFavorite(VideoTrack track) {
    if (!_favoritePaths.remove(track.path)) {
      _favoritePaths.add(track.path);
    }
    _persist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Persistence (native SharedPreferences via MethodChannel)
  // ---------------------------------------------------------------------------

  Future<void> _loadSettings() async {
    final s = await NativeBridge.loadSettings();
    if (_disposed) return;
    viewMode = _parseEnum(ViewMode.values, s['viewMode'], viewMode);
    groupMode = _parseEnum(GroupMode.values, s['groupMode'], groupMode);
    playbackAction =
        _parseEnum(PlaybackAction.values, s['playbackAction'], playbackAction);
    sortMode = _parseEnum(SortMode.values, s['sortMode'], sortMode);
    sortAscending = s['sortAscending'] != 'false'; // default true
    favoritesOnly = s['favoritesOnly'] == 'true';
    _favoritePaths = (s['favorites'] ?? '')
        .split(',')
        .where((e) => e.isNotEmpty)
        .toSet();
    notifyListeners();
  }

  void _persist() {
    NativeBridge.saveSetting('viewMode', viewMode.name);
    NativeBridge.saveSetting('groupMode', groupMode.name);
    NativeBridge.saveSetting('playbackAction', playbackAction.name);
    NativeBridge.saveSetting('sortMode', sortMode.name);
    NativeBridge.saveSetting('sortAscending', '$sortAscending');
    NativeBridge.saveSetting('favoritesOnly', '$favoritesOnly');
    NativeBridge.saveSetting('favorites', _favoritePaths.join(','));
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  /// Requests "All files access", then scans the whole of internal storage
  /// for videos. Call this again any time to retry after a denial.
  Future<void> scanAllStorage() async {
    if (isScanning) return;
    permissionDenied = false;
    notifyListeners();

    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      permissionDenied = true;
      notifyListeners();
      return;
    }

    folderName = 'Internal storage';
    await _scanDirectory(_internalStorageRoot);
  }

  Future<void> rescan() => scanAllStorage();

  /// v22: swap in a thumbnail the PLAYER captured with mpv (Android's
  /// metadata engine can't decode some 4K/HDR files, whose tiles stayed
  /// grey). Updates the list in place - no rescan needed.
  void setThumbnail(String videoPath, String thumbPath) {
    var hit = false;
    for (var i = 0; i < _videos.length; i++) {
      if (_videos[i].path == videoPath) {
        _videos[i] = _videos[i].copyWith(thumbnailPath: thumbPath);
        hit = true;
      }
    }
    if (hit) notifyListeners();
  }

  Future<void> _scanDirectory(String dirPath) async {
    isScanning = true;
    _videos = [];
    scanProgress = const ScanProgress();
    notifyListeners();

    final dir = Directory(dirPath);
    final foundFiles = <File>[];
    await for (final entity in _listVideosSkippingJunk(dir)) {
      foundFiles.add(entity);
    }

    scanProgress =
        ScanProgress(found: foundFiles.length, total: foundFiles.length);
    notifyListeners();

    final allVideos = <VideoTrack>[];
    // Process in small batches so the UI can show progress incrementally.
    const batchSize = 8;
    for (var i = 0; i < foundFiles.length; i += batchSize) {
      final batch = foundFiles.skip(i).take(batchSize);
      final tracks = await Future.wait(batch.map((f) => _buildTrack(f.path)));
      allVideos.addAll(tracks.whereType<VideoTrack>());
      _videos = [...allVideos];
      scanProgress = ScanProgress(
        found: foundFiles.length,
        processed: (i + batchSize).clamp(0, foundFiles.length),
        total: foundFiles.length,
      );
      notifyListeners();
    }

    isScanning = false;
    notifyListeners();
  }

  /// Recursively lists video files under [dir], skipping subfolders named in
  /// [_skipDirNames] and silently ignoring individual permission-denied
  /// entries (common under /storage/emulated/0/Android on newer Android).
  Stream<File> _listVideosSkippingJunk(Directory dir) async* {
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (_) {
      return; // can't read this directory (permission denied etc) - skip it
    }

    for (final entity in entries) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (_skipDirNames.contains(name)) continue;
        yield* _listVideosSkippingJunk(entity);
      } else if (entity is File && isVideoFile(entity.path)) {
        yield entity;
      }
    }
  }

  Future<VideoTrack?> _buildTrack(String path) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      // Duration + thumbnail come from native MediaMetadataRetriever code
      // (replaces the AGP-incompatible video_thumbnail plugin). Thumbnails
      // are cached on disk natively, so this is cheap on repeat scans.
      final meta = await NativeBridge.fetchMetadata(path);
      return VideoTrack(
        id: '$path-${stat.modified.millisecondsSinceEpoch}',
        title: p.basenameWithoutExtension(path),
        path: path,
        thumbnailPath: meta.thumbnailPath,
        duration: meta.duration,
        sizeBytes: stat.size,
        lastModifiedMs: stat.modified.millisecondsSinceEpoch,
        width: meta.width,
        height: meta.height,
      );
    } catch (e) {
      debugPrint('Failed to read $path: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Test hook - swaps the scanned list without touching the filesystem.
  @visibleForTesting
  void debugSetVideos(List<VideoTrack> videos) {
    _videos = videos;
    notifyListeners();
  }
}
EOF_MARKER_5

mkdir -p "$(dirname 'lib/state/private_vault.dart')"
cat > 'lib/state/private_vault.dart' <<'EOF_MARKER_6'
import 'dart:io';

import '../services/native_bridge.dart';
import '../utils/sha256.dart';

/// Private folder ("vault"), v21.
///
/// Mechanism (same idea as MX Player / PlayIt): the video FILE IS MOVED into
/// the app's own directory. Android blocks Gallery / Photos / Files from
/// looking inside another app's private directory, so a hidden video
/// disappears from the rest of the phone, and Max Player lists it only
/// after the PIN.
///
/// The PIN protects the list; the file location is the real hiding. The PIN
/// hash (never the PIN itself) is stored in the app's settings store.
///
/// ⚠ Uninstalling the app deletes the app's private directory - hidden
/// videos along with it. The UI always offers "Move out of Private" first.
class PrivateVault {
  static const String _pinKey = 'vault.pinHash';

  static const String vaultDirPath =
      '/storage/emulated/0/Android/data/com.hypertechlabs.maxplayer/files/Private';

  /// Videos moved OUT of the vault land here.
  static const String unhideDirPath = '/storage/emulated/0/Movies';

  static const Set<String> videoExts = {
    '.mp4', '.mkv', '.webm', '.avi', '.mov', '.wmv', '.flv', '.ts', '.m2ts',
    '.mpg', '.mpeg', '.3gp', '.vob', '.m4v',
  };

  /// True when [path] already lives inside the vault.
  static bool isPrivatePath(String path) =>
      path.startsWith(vaultDirPath);

  String _hashPin(String pin) => sha256Hex('maxplayer.vault::$pin');

  Future<bool> hasPin() async {
    final s = await NativeBridge.loadSettings();
    return (s[_pinKey] ?? '').isNotEmpty;
  }

  Future<bool> verifyPin(String pin) async {
    final s = await NativeBridge.loadSettings();
    final stored = s[_pinKey] ?? '';
    return stored.isNotEmpty && stored == _hashPin(pin);
  }

  Future<void> setPin(String pin) =>
      NativeBridge.saveSetting(_pinKey, _hashPin(pin));

  Future<Directory> _dir() async {
    final d = Directory(vaultDirPath);
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }

  /// Video files currently inside the vault (name-sorted).
  Future<List<File>> listVideos() async {
    final d = await _dir();
    final files = d
        .listSync()
        .whereType<File>()
        .where((f) =>
            videoExts.contains(f.path.toLowerCase().split('.').last.isEmpty
                ? ''
                : '.${f.path.toLowerCase().split('.').last}'))
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Moves [srcPath] into the vault and returns the new file. Same-filesystem
  /// rename is instant; a cross-device fallback copies then deletes.
  Future<File> hide(String srcPath) async {
    final src = File(srcPath);
    if (!src.existsSync()) {
      throw const FileSystemException('Video file not found');
    }
    final target = await _uniqueIn(await _dir(), srcPath);
    final moved = await _move(src, target);
    // Refresh the gallery scan for the OLD location so it disappears.
    // v22: best-effort only - a failed rescan must NOT undo a good move.
    try {
      await NativeBridge.scanFile(srcPath);
    } catch (_) {}
    return moved;
  }

  /// Moves a vault file back to public storage (/storage/emulated/0/Movies).
  Future<File> unhide(String hiddenPath) async {
    final src = File(hiddenPath);
    if (!src.existsSync()) {
      throw const FileSystemException('Hidden video not found');
    }
    final destDir = Directory(unhideDirPath);
    if (!destDir.existsSync()) await destDir.create(recursive: true);
    final target = await _uniqueIn(destDir, hiddenPath);
    final moved = await _move(src, target);
    try {
      await NativeBridge.scanFile(moved.path); // visible to gallery again
    } catch (_) {}
    return moved;
  }

  Future<String> _uniqueIn(Directory dir, String fromPath) async {
    var name = fromPath.split('/').last;
    var dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = '${dir.path}/$name';
    var i = 2;
    while (File(candidate).existsSync()) {
      candidate = '${dir.path}/$stem ($i)$ext';
      i++;
    }
    return candidate;
  }

  Future<File> _move(File src, String targetPath) async {
    try {
      return await src.rename(targetPath);
    } on FileSystemException {
      // Cross-volume move (e.g. SD card): copy, then remove the original.
      // v22: if the delete fails we roll the copy back - the old code
      // left a silent duplicate in the vault AND reported failure, which
      // made "Private folder not working" reports un-debuggable.
      final copied = await src.copy(targetPath);
      try {
        await src.delete();
      } catch (_) {
        try {
          await copied.delete();
        } catch (_) {}
        throw const FileSystemException(
          'Could not remove the original file - allow "All files access" '
          'for Max Player and try again',
        );
      }
      return copied;
    }
  }
}
EOF_MARKER_6

mkdir -p "$(dirname 'lib/widgets/karaoke_subtitle.dart')"
cat > 'lib/widgets/karaoke_subtitle.dart' <<'EOF_MARKER_7'
import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/srt.dart';

/// Word index to highlight for [cue] at playback position [posMs].
///
/// whisper.cpp only gives us per-CUE timestamps, so word timing inside a cue
/// is approximated: each word occupies a time slice proportional to its
/// character count (spoken English/Hindi is remarkably even per letter).
/// Top-level + pure so the widget test can pin the behavior.
int karaokeWordIndex(SrtCue cue, int posMs) {
  final words = cue.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final list = words.toList();
  if (list.isEmpty) return -1;
  final span = cue.endMs - cue.startMs;
  if (span <= 0) return 0;
  final frac = ((posMs - cue.startMs) / span).clamp(0.0, 1.0);
  final totalChars = list.fold<int>(0, (a, w) => a + w.length);
  if (totalChars == 0) return 0;
  var target = frac * totalChars;
  for (var i = 0; i < list.length; i++) {
    if (target < list[i].length) return i;
    target -= list[i].length;
  }
  return list.length - 1;
}

/// The cue active at [posMs] (last cue that already started; a trailing
/// 600 ms grace keeps short gaps from flickering).
SrtCue? karaokeActiveCue(List<SrtCue> cues, int posMs) {
  SrtCue? active;
  for (final c in cues) {
    if (isMusicOnlyText(c.text)) continue;
    if (c.startMs <= posMs) {
      active = (posMs <= c.endMs + 600) ? c : active;
    } else {
      break;
    }
  }
  if (active != null && posMs > active.endMs + 600) return null;
  return active;
}

/// Which cue the karaoke overlay should show at [posMs]. Pure + unit-tested.
///
/// Priority (v22):
///  1. [live] - the line mpv is displaying right now, read through its
///     sub-text/sub-start/sub-end properties. Real cue timing, and works
///     with ANY subtitle source (embedded mkv tracks included).
///  2. [aiCues] - the AI sidecar's cue list.
///  3. [sidecarCues] - the video's own same-name .srt file.
SrtCue? karaokeCueAt(
  SrtCue? live,
  List<SrtCue>? aiCues,
  List<SrtCue>? sidecarCues,
  int posMs,
) {
  if (live != null && posMs <= live.endMs + 600) return live;
  final fromAi = aiCues == null ? null : karaokeActiveCue(aiCues, posMs);
  if (fromAi != null) return fromAi;
  return sidecarCues == null ? null : karaokeActiveCue(sidecarCues, posMs);
}

/// Karaoke-style AI subtitle: words light up one by one as they are spoken.
/// Shown instead of mpv's own subtitle rendering while the setting is on.
class KaraokeSubtitle extends StatelessWidget {
  final MediaPlayerState player;

  const KaraokeSubtitle({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final posMs = player.position.inMilliseconds;
        final cue = karaokeCueAt(
          player.liveSubCue,
          player.aiCues,
          player.sidecarCues,
          posMs,
        );
        if (cue == null) return const SizedBox.shrink();
        final activeIdx = karaokeWordIndex(cue, posMs);
        final words =
            cue.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

        // v22: unlit words are dimmed further so the accent highlight
        // stays visible even when the accent itself is white.
        const baseColor = Colors.white54;
        const shadow = [
          Shadow(color: Colors.black, blurRadius: 6),
          Shadow(color: Colors.black, offset: Offset(0, 1)),
        ];
        final spans = <InlineSpan>[
          for (var i = 0; i < words.length; i++)
            TextSpan(
              text: i == 0 ? words[i] : ' ${words[i]}',
              style: TextStyle(
                color: i <= activeIdx ? themeState.accent : baseColor,
                fontSize: 17,
                fontWeight: i == activeIdx ? FontWeight.w800 : FontWeight.w500,
                shadows: shadow,
                height: 1.35,
              ),
            ),
        ];
        return IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text.rich(
              TextSpan(children: spans),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}
EOF_MARKER_7

mkdir -p "$(dirname 'lib/widgets/player_controls_overlay.dart')"
cat > 'lib/widgets/player_controls_overlay.dart' <<'EOF_MARKER_8'
import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'progress_bar.dart';
import 'track_selection_sheet.dart';

/// Controls drawn on top of the video - v19 final-polish layout:
///
///   [progress bar, with scrub thumbnail preview]
///   row 1:  previous  -  play/pause  -  next            (centered trio)
///   row 2:  mute - speed - Tracks(subs/audio/A-B) - rotation lock
///           ...  queue - fit
///
/// Removed per the final polish pass: shuffle, repeat, the dedicated
/// +/-10 s buttons (horizontal drag-seek covers them) and the fullscreen
/// button (sensor auto-rotate replaces it); the fit cycle moved to the
/// corner where fullscreen used to sit.
///
/// This widget rebuilds itself via [AnimatedBuilder] on every player tick,
/// so the parent screen does NOT rebuild (which kept recreating the video
/// surface and caused fullscreen flicker).
class PlayerControlsOverlay extends StatelessWidget {
  final MediaPlayerState player;
  final VoidCallback onToggleQueue;

  /// Fired on every control interaction; the screen uses it to restart the
  /// auto-hide countdown.
  final VoidCallback onInteract;

  /// Cycles the video fit (contain -> cover -> fill).
  final VoidCallback onCycleFit;

  /// Rotation lock toggle (auto-rotate by sensor vs pinned).
  final bool orientationLocked;
  final VoidCallback onToggleOrientationLock;

  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.onToggleQueue,
    required this.onInteract,
    required this.onCycleFit,
    required this.orientationLocked,
    required this.onToggleOrientationLock,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressBar(
                position: player.position,
                duration: player.duration,
                previewThumb: player.scrubThumbPath,
                onSeek: (d) {
                  player.seek(d);
                  onInteract();
                },
              ),
              // Row 1: previous / play-pause / next - the transport trio.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _iconBtn(
                    icon: Icons.skip_previous,
                    size: 30,
                    onTap: player.prevTrack,
                  ),
                  const SizedBox(width: 22),
                  _iconBtn(
                    icon: player.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 46,
                    onTap: player.togglePlay,
                  ),
                  const SizedBox(width: 22),
                  _iconBtn(
                    icon: Icons.skip_next,
                    size: 30,
                    onTap: player.nextTrack,
                  ),
                ],
              ),
              // Row 2 (compact): mute speed tracks rotate | queue fit
              Row(
                children: [
                  _iconBtn(
                    icon: player.isMuted || player.volume == 0
                        ? Icons.volume_off
                        : Icons.volume_up,
                    onTap: player.toggleMute,
                    compact: true,
                  ),
                  _speedMenu(),
                  _tracksMenu(context),
                  _iconBtn(
                    icon: orientationLocked
                        ? Icons.screen_lock_rotation
                        : Icons.screen_rotation,
                    active: orientationLocked,
                    onTap: onToggleOrientationLock,
                    compact: true,
                  ),
                  const Spacer(),
                  _iconBtn(
                    icon: Icons.queue_music,
                    onTap: onToggleQueue,
                    compact: true,
                  ),
                  _iconBtn(
                    tooltip: 'Fit: contain / cover / fill',
                    icon: Icons.aspect_ratio,
                    onTap: onCycleFit,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// One button opening ONE bottom sheet for everything track-shaped:
  /// subtitles, audio tracks, and the A-B loop (previously three separate
  /// buttons). v20: switched from PopupMenuButton to a bottom sheet - the
  /// popup glitched because this overlay rebuilds on every player tick
  /// while the popup was open.
  Widget _tracksMenu(BuildContext context) {
    final active = player.subtitlesActive ||
        player.audioTracks.length > 1 ||
        player.abLoopActive;
    return IconButton(
      tooltip: 'Subtitles, audio tracks, A-B loop',
      icon: Icon(
        Icons.tune,
        size: 20,
        // v23: whole player rides the theme colour; "active" states keep
        // full strength, idle states dim to 75% of the same colour.
        color: active
            ? themeState.accent
            : themeState.accent.withValues(alpha: 0.75),
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 40),
      onPressed: () {
        onInteract();
        _showTracksSheet(context);
      },
    );
  }

  void _showTracksSheet(BuildContext context) {
    final hasA = player.loopA != null;
    final hasB = player.loopB != null;
    final abSubtitle = hasA && hasB
        ? 'Looping ${formatDuration(player.loopA)} - ${formatDuration(player.loopB)} (tap to clear)'
        : hasA
            ? 'A set at ${formatDuration(player.loopA)} - tap to set B'
            : 'Off - tap to mark point A';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: themeState.accent.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                player.subtitlesActive
                    ? Icons.subtitles
                    : Icons.subtitles_outlined,
                color: themeState.accent.withValues(alpha: 0.75),
              ),
              title: Text(
                player.subtitlesActive ? 'Subtitles (on)' : 'Subtitles',
                style: TextStyle(color: themeState.accent),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                TrackSelectionSheet.show(context, player, isSubtitle: true);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.audiotrack_outlined,
                color: themeState.accent.withValues(alpha: 0.75),
              ),
              title: Text(
                player.audioTracks.length > 1
                    ? 'Audio track (${player.audioTracks.length} available)'
                    : 'Audio track',
                style: TextStyle(color: themeState.accent),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                TrackSelectionSheet.show(context, player, isSubtitle: false);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.repeat_one_outlined,
                color: player.abLoopActive
                    ? themeState.accent
                    : themeState.accent.withValues(alpha: 0.75),
              ),
              title: Text(
                'A-B loop',
                style: TextStyle(color: themeState.accent),
              ),
              subtitle: Text(
                abSubtitle,
                style: TextStyle(
                    color: themeState.accent.withValues(alpha: 0.5),
                    fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                final msg = player.tapLoopPoint();
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      duration: const Duration(milliseconds: 1400),
                    ),
                  );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _speedMenu() {
    return PopupMenuButton<double>(
      initialValue: player.playbackRate,
      color: const Color(0xFF1a1a24),
      onSelected: (r) {
        player.setPlaybackRate(r);
        onInteract();
      },
      itemBuilder: (context) =>
          const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0] // v22: up to 3x
              .map((r) => PopupMenuItem(
                    value: r,
                    child: Text('${r}x',
                        style: TextStyle(color: themeState.accent)),
                  ))
              .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Text('${player.playbackRate}x',
            style: TextStyle(
                color: themeState.accent.withValues(alpha: 0.75),
                fontSize: 11)),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    double size = 24,
    bool compact = false,
    String? tooltip,
  }) {
    final accent = themeState.accent;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon,
          size: compact ? 20 : size,
          color: active ? accent : accent.withValues(alpha: 0.75)),
      // Compact rows must fit ~7 actions on a 320dp-wide phone.
      constraints:
          compact ? const BoxConstraints.tightFor(width: 34, height: 40) : null,
      padding: compact ? EdgeInsets.zero : null,
      visualDensity: compact ? VisualDensity.compact : null,
      // Every press also restarts the screen's auto-hide countdown.
      onPressed: () {
        onTap();
        onInteract();
      },
    );
  }
}
EOF_MARKER_8

mkdir -p "$(dirname 'lib/widgets/player_settings_sheet.dart')"
cat > 'lib/widgets/player_settings_sheet.dart' <<'EOF_MARKER_9'
import 'package:flutter/material.dart';

import '../state/player_settings.dart';
import '../state/theme_state.dart';

/// "Player settings" sheet - customize every gesture and playback behavior.
/// Changes are saved immediately and picked up by the open PlayerScreen.
class PlayerSettingsSheet extends StatefulWidget {
  const PlayerSettingsSheet({super.key});

  static Color get _accent => themeState.accent;
  static const Color _surface = Color(0xFF1a1a24);

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PlayerSettingsSheet(),
    );
  }

  @override
  State<PlayerSettingsSheet> createState() => _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends State<PlayerSettingsSheet> {
  PlayerSettings _settings = const PlayerSettings();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await PlayerSettings.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _loaded = true;
    });
  }

  void _update(PlayerSettings s) {
    setState(() => _settings = s);
    s.save(); // fire-and-forget persistence
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: themeState.accent.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                'Player settings',
                style: TextStyle(
                  color: PlayerSettingsSheet._accent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!_loaded)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(
                      color: PlayerSettingsSheet._accent),
                ),
              )
            else ...[
              const _SectionHeader('Gesture controls'),
              _SwitchTile(
                icon: Icons.touch_app_outlined,
                label: 'Double-tap sides to seek',
                subtitle: 'Double-tap left/right edge',
                value: _settings.doubleTapSeek,
                onChanged: (v) =>
                    _update(_settings.copyWith(doubleTapSeek: v)),
                trailing: _settings.doubleTapSeek
                    ? _MiniDropdown<int>(
                        value: _settings.seekSeconds,
                        entries: const {
                          5: '5s',
                          10: '10s',
                          15: '15s',
                          30: '30s',
                        },
                        onChanged: (v) => _update(
                            _settings.copyWith(seekSeconds: v ?? 10)),
                      )
                    : null,
              ),
              _SwitchTile(
                icon: Icons.play_circle_outline,
                label: 'Double-tap middle to play/pause',
                value: _settings.doubleTapPlayPause,
                onChanged: (v) =>
                    _update(_settings.copyWith(doubleTapPlayPause: v)),
              ),
              _SwitchTile(
                icon: Icons.volume_up_outlined,
                label: 'Swipe right side for volume',
                value: _settings.volumeSwipe,
                onChanged: (v) => _update(_settings.copyWith(volumeSwipe: v)),
              ),
              _SwitchTile(
                icon: Icons.brightness_6_outlined,
                label: 'Swipe left side for brightness',
                value: _settings.brightnessSwipe,
                onChanged: (v) =>
                    _update(_settings.copyWith(brightnessSwipe: v)),
              ),
              _SwitchTile(
                icon: Icons.swap_horizontal_circle_outlined,
                label: 'Horizontal swipe to seek',
                subtitle: 'Drag sideways anywhere to scrub (±90s per screen)',
                value: _settings.horizontalSeek,
                onChanged: (v) =>
                    _update(_settings.copyWith(horizontalSeek: v)),
              ),
              _SwitchTile(
                icon: Icons.pinch_outlined,
                label: 'Pinch to zoom (two fingers)',
                value: _settings.pinchZoom,
                onChanged: (v) => _update(_settings.copyWith(pinchZoom: v)),
              ),
              _SwitchTile(
                icon: Icons.fast_forward,
                label: 'Long-press to speed up',
                subtitle: 'Hold finger on the video',
                value: _settings.longPressSpeed,
                onChanged: (v) =>
                    _update(_settings.copyWith(longPressSpeed: v)),
                trailing: _settings.longPressSpeed
                    ? _MiniDropdown<double>(
                        value: _settings.longPressMultiplier,
                        entries: {
                          1.5: '1.5x',
                          2.0: '2x',
                          2.5: '2.5x',
                          3.0: '3x',
                        },
                        onChanged: (v) => _update(_settings.copyWith(
                            longPressMultiplier: v ?? 2.0)),
                      )
                    : null,
              ),
              const _SectionHeader('Playback'),
              _SwitchTile(
                icon: Icons.timer_off_outlined,
                label: 'Auto-hide controls',
                subtitle: 'Hide during playback after inactivity',
                value: _settings.autoHideSeconds > 0,
                onChanged: (v) =>
                    _update(_settings.copyWith(autoHideSeconds: v ? 4 : 0)),
                trailing: _settings.autoHideSeconds > 0
                    ? _MiniDropdown<int>(
                        value: _settings.autoHideSeconds,
                        entries: const {3: '3s', 4: '4s', 5: '5s', 6: '6s'},
                        onChanged: (v) => _update(
                            _settings.copyWith(autoHideSeconds: v ?? 4)),
                      )
                    : null,
              ),
              _SwitchTile(
                icon: Icons.history,
                label: 'Resume playback',
                subtitle: 'Continue videos where you left off',
                value: _settings.resumePlayback,
                onChanged: (v) =>
                    _update(_settings.copyWith(resumePlayback: v)),
              ),
              const _SectionHeader('Player buttons'),
              _SwitchTile(
                icon: Icons.cast_outlined,
                label: 'Cast to TV (DLNA)',
                subtitle: 'Show the cast button in the player top bar',
                value: _settings.castButton,
                onChanged: (v) => _update(_settings.copyWith(castButton: v)),
              ),
              _SwitchTile(
                icon: Icons.camera_alt_outlined,
                label: 'Screenshot button',
                subtitle: 'Save the current frame to the gallery',
                value: _settings.screenshotButton,
                onChanged: (v) =>
                    _update(_settings.copyWith(screenshotButton: v)),
              ),
              _SwitchTile(
                icon: Icons.lock_outline,
                label: 'Screen lock (kids mode)',
                subtitle: 'Lock button on the video edge locks every touch',
                value: _settings.lockButton,
                onChanged: (v) => _update(_settings.copyWith(lockButton: v)),
              ),
              const _SectionHeader('Sound & subtitles'),
              _SwitchTile(
                icon: Icons.volume_up,
                label: 'Volume boost up to 200%',
                subtitle: 'ON by default - the swipe just continues past '
                    '100% for quiet videos',
                value: _settings.volumeBoost200,
                onChanged: (v) =>
                    _update(_settings.copyWith(volumeBoost200: v)),
              ),
              _SwitchTile(
                icon: Icons.graphic_eq,
                label: 'Volume leveling',
                subtitle: 'Steady loudness: soft dialogue and loud '
                    'explosions evened out',
                value: _settings.volumeLeveling,
                onChanged: (v) =>
                    _update(_settings.copyWith(volumeLeveling: v)),
              ),
              _SwitchTile(
                icon: Icons.lyrics_outlined,
                label: 'Karaoke subtitle highlight',
                subtitle: 'Words light up as they are spoken - works with '
                    'any subtitle (AI, embedded or .srt file)',
                value: _settings.karaokeSubs,
                onChanged: (v) => _update(_settings.copyWith(karaokeSubs: v)),
              ),
              _SwitchTile(
                icon: Icons.fast_forward,
                label: 'Skip intro chip',
                subtitle: 'Offer to jump when subtitles (AI or the video\'s '
                    'own .srt file) show the dialogue starts later',
                value: _settings.skipIntroChip,
                onChanged: (v) =>
                    _update(_settings.copyWith(skipIntroChip: v)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          color: PlayerSettingsSheet._accent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? trailing;

  const _SwitchTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          // v23: the whole player UI rides the picked theme colour.
          Icon(icon,
              color: themeState.accent.withValues(alpha: 0.75), size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(color: themeState.accent, fontSize: 15)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: TextStyle(
                          color: themeState.accent.withValues(alpha: 0.5),
                          fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: PlayerSettingsSheet._accent,
          ),
        ],
      ),
    );
  }
}

class _MiniDropdown<T> extends StatelessWidget {
  final T value;
  final Map<T, String> entries;
  final ValueChanged<T?> onChanged;

  const _MiniDropdown({
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      dropdownColor: const Color(0xFF26262f),
      underline: const SizedBox.shrink(),
      isDense: true,
      style: TextStyle(
          color: themeState.accent.withValues(alpha: 0.75), fontSize: 13),
      items: [
        for (final e in entries.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: onChanged,
    );
  }
}
EOF_MARKER_9

mkdir -p "$(dirname 'lib/widgets/display_settings_sheet.dart')"
cat > 'lib/widgets/display_settings_sheet.dart' <<'EOF_MARKER_10'
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../state/video_library_state.dart';
import '../state/theme_state.dart';

/// VLC-style "Display settings" sheet: list/grid toggle, favourites filter,
/// grouping, playback action and grouped sort options with direction choices.
class DisplaySettingsSheet extends StatelessWidget {
  final VideoLibraryState library;

  const DisplaySettingsSheet({super.key, required this.library});

  static Color get _accent => themeState.accent;
  static const Color _surface = Color(0xFF1a1a24);

  static Future<void> show(BuildContext context, VideoLibraryState library) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DisplaySettingsSheet(library: library),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds whenever the library OR theme notifies, so checkmarks and
    // swatch selection update in place.
    return AnimatedBuilder(
      animation: Listenable.merge([library, themeState]),
      builder: (context, _) {
        final lib = library;
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(
                    'Display settings',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _SwitchRow(
                  icon: Icons.view_list_outlined,
                  label: 'Display in list',
                  value: lib.viewMode == ViewMode.list,
                  onChanged: (v) =>
                      lib.setViewMode(v ? ViewMode.list : ViewMode.grid),
                ),
                _CheckRow(
                  icon: Icons.favorite_border,
                  label: 'Show only favourites',
                  value: lib.favoritesOnly,
                  onChanged: (v) => lib.setFavoritesOnly(v ?? false),
                ),
                _DropdownRow<GroupMode>(
                  icon: Icons.collections_outlined,
                  label: 'Group videos',
                  value: lib.groupMode,
                  entries: const {
                    GroupMode.none: "Don't group",
                    GroupMode.name: 'Group by name',
                    GroupMode.folder: 'Group by folder',
                  },
                  onChanged: (m) => lib.setGroupMode(m ?? GroupMode.none),
                ),
                _DropdownRow<PlaybackAction>(
                  icon: Icons.play_arrow,
                  label: 'Playback action',
                  subtitle: 'When tapping a video',
                  value: lib.playbackAction,
                  entries: const {
                    PlaybackAction.all: 'Play all (queue)',
                    PlaybackAction.single: 'Play single video',
                  },
                  onChanged: (a) =>
                      lib.setPlaybackAction(a ?? PlaybackAction.all),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 2),
                  child: Text(
                    'Theme color',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 6),
                  // v22: Wrap (was Row) - seven swatches can overflow very
                  // narrow phones.
                  child: Wrap(
                    runSpacing: 10,
                    children: [
                      for (final c in ThemeState.swatches)
                        _ColorSwatch(
                          color: c,
                          selected: themeState.accent.toARGB32() == c.toARGB32(),
                          onTap: () => themeState.setAccent(c),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Sort by...',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _SortGroup(
                  icon: Icons.sort_by_alpha,
                  title: 'Name',
                  mode: SortMode.name,
                  options: const ['A → Z', 'Z → A'],
                  library: lib,
                ),
                _SortGroup(
                  icon: Icons.timer_outlined,
                  title: 'Length',
                  mode: SortMode.length,
                  options: const ['Shortest first', 'Longest first'],
                  library: lib,
                ),
                _SortGroup(
                  icon: Icons.history,
                  title: 'Recently added',
                  mode: SortMode.date,
                  // lastModified ascending = oldest files first
                  options: const ['Oldest first', 'Newest first'],
                  library: lib,
                ),
                _SortGroup(
                  icon: Icons.sd_storage_outlined,
                  title: 'Size',
                  mode: SortMode.size,
                  options: const ['Smallest first', 'Largest first'],
                  library: lib,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            // White swatch needs a visible ring even when idle; others get
            // the ring only while selected.
            color: selected
                ? (color.computeLuminance() > 0.7
                    ? Colors.black87
                    : Colors.white)
                : (color.computeLuminance() > 0.7
                    ? Colors.white24
                    : Colors.transparent),
            width: 2.5,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 16,
                // v22: dark check on the white/light swatches.
                color: color.computeLuminance() > 0.7
                    ? Colors.black87
                    : Colors.white,
              )
            : null,
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(color: Colors.white, fontSize: 15)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: DisplaySettingsSheet._accent,
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _CheckRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 15)),
            ),
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: DisplaySettingsSheet._accent,
              checkColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final T value;
  final Map<T, String> entries;
  final ValueChanged<T?> onChanged;

  const _DropdownRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          DropdownButton<T>(
            value: value,
            dropdownColor: const Color(0xFF26262f),
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            items: [
              for (final e in entries.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// One VLC-style sort block: title on the left, its two direction options on
/// the right, purple checkmark on the active option. Option 0 is ascending,
/// option 1 is descending.
class _SortGroup extends StatelessWidget {
  final IconData icon;
  final String title;
  final SortMode mode;
  final List<String> options;
  final VideoLibraryState library;

  const _SortGroup({
    required this.icon,
    required this.title,
    required this.mode,
    required this.options,
    required this.library,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(icon, color: Colors.white70, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < options.length; i++)
                  _SortOption(
                    label: options[i],
                    active: library.sortMode == mode &&
                        library.sortAscending == (i == 0),
                    onTap: () => library.setSort(mode, i == 0),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SortOption({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color:
                      active ? DisplaySettingsSheet._accent : Colors.white70,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            SizedBox(
              width: 22,
              child: active
                  ? Icon(Icons.check,
                      size: 18, color: DisplaySettingsSheet._accent)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
EOF_MARKER_10

mkdir -p "$(dirname 'lib/widgets/user_manual_sheet.dart')"
cat > 'lib/widgets/user_manual_sheet.dart' <<'EOF_MARKER_11'
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../state/theme_state.dart';
import 'gesture_illustrations.dart';

/// In-app user manual, opened from the home screen's ⋮ menu
/// ("User manual"). Static content only - no platform calls. Gesture
/// entries are illustrated with drawn vector diagrams
/// ([GestureIllustration]) so no image assets are bundled.
class UserManualSheet extends StatelessWidget {
  final ScrollController? scrollController;

  const UserManualSheet({super.key, this.scrollController});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            UserManualSheet(scrollController: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        // Grab handle.
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: const BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
        Row(
          children: [
            Icon(Icons.menu_book_outlined, color: accent),
            const SizedBox(width: 10),
            const Text(
              'User manual',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        // --- Home screen ------------------------------------------------
        _SectionTitle('Home screen', accent),
        for (final item in _homeItems) _IconRow(item: item),

        // --- Gestures (illustrated) -------------------------------------
        _SectionTitle('Gesture controls', accent),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'All gestures work both in windowed and full-screen mode, on '
            'every video. Each one can be switched off individually in the '
            'player\'s ⚙ settings sheet.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ),
        for (final g in _gestureItems) _GestureCard(item: g),

        // --- Player buttons ---------------------------------------------
        _SectionTitle('Player buttons', accent),
        for (final item in _playerItems) _IconRow(item: item),

        // --- Smart features ---------------------------------------------
        _SectionTitle('Smart features', accent),
        for (final item in _smartItems) _IconRow(item: item),

        // --- Tips & FAQ ---------------------------------------------------
        _SectionTitle('Tips & answers', accent),
        for (final item in _tipItems) _IconRow(item: item),

        const SizedBox(height: 22),
        const Center(
          child: Text(
            'Max Player v$kAppVersion  ·  Hyper Tech Labs',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color accent;
  const _SectionTitle(this.text, this.accent);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Text row with a small leading icon (non-illustrated entries).
class _IconRow extends StatelessWidget {
  final _Item item;
  const _IconRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gesture guide card: drawn illustration on top, title + detailed
/// step-by-step description underneath.
class _GestureCard extends StatelessWidget {
  final _GestureItem item;
  const _GestureCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          GestureIllustration(kind: item.kind),
          const SizedBox(height: 8),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final IconData icon;
  final String title;
  final String description;
  const _Item(this.icon, this.title, this.description);
}

class _GestureItem {
  final GestureKind kind;
  final String title;
  final String description;
  const _GestureItem(this.kind, this.title, this.description);
}

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

const List<_Item> _homeItems = [
  _Item(
    Icons.sync,
    'Rescan button (⟳ top bar)',
    'New videos you download or copy do not appear by themselves - tap the '
        '⟳ button in the top bar and the whole device is re-scanned. While '
        'scanning, the button turns into a spinner and a progress bar shows '
        'how far along it is. The same action lives in ⋮ → Rescan library.',
  ),
  _Item(
    Icons.search,
    'Search',
    'Type any part of a file name into the search bar under the title. The '
        'list filters live as you type; clear the text to see everything '
        'again.',
  ),
  _Item(
    Icons.favorite_border,
    'Favourites',
    'Tap the ♥ on any video to star it. Then open ⋮ → Display settings and '
        'enable "Show only favourites" to see just your picks. Stars are '
        'remembered between launches.',
  ),
  _Item(
    Icons.tune,
    'Sort, group, grid & accent colour',
    '⋮ → Display settings lets you: switch between list and grid view, sort '
        'by name / length / date added / size (tap again to flip the '
        'direction), group by first letter or by folder, and change the app\'s '
        'accent colour from six swatches.',
  ),
  _Item(
    Icons.open_in_new,
    'Playing videos from other apps',
    'In your Gallery or Files app, tap a video → "Open with" → Max Player. '
        'Some galleries hide this under Share - Share → Max Player works the '
        'same. Videos stored only in the cloud (e.g. Google Photos) are '
        'copied to a temporary file first, so they can take a few seconds to '
        'start.',
  ),
  _Item(
    Icons.link,
    'Network streams',
    '⋮ → Open stream URL: paste a direct video link (http/https) or a live '
        'stream (rtsp/rtmp/mms) and it plays immediately. Links opened in a '
        'browser can also be handed to Max Player directly from the "Open '
        'with" dialog.',
  ),
  _Item(
    Icons.history,
    'History & resume',
    'The 🕘 button in the top bar lists your recently watched videos. Every '
        'video reopens exactly where you stopped watching (a "Resumed …" '
        'message confirms it). Turn this off in the player\'s ⚙ settings → '
        'Resume playback.',
  ),
  _Item(
    Icons.bar_chart,
    'Statistics',
    '⋮ → Statistics shows how much you watched each day of the last week as '
        'a bar chart, plus totals.',
  ),
];

const List<_GestureItem> _gestureItems = [
  _GestureItem(
    GestureKind.singleTap,
    'Single tap - show / hide controls',
    'Tap once anywhere on the video: the seek bar and all buttons slide in. '
        'Tap again (or wait ~4 seconds) and they hide so nothing covers the '
        'picture. The auto-hide delay can be changed in ⚙ settings.',
  ),
  _GestureItem(
    GestureKind.doubleTapSides,
    'Double-tap the sides - seek ±10 seconds',
    'Double-tap the LEFT third of the video to jump back 10 seconds, the '
        'RIGHT third to jump forward 10 seconds. Each extra double-tap adds '
        'another 10 seconds. The 10-second step is configurable in ⚙ '
        'settings (5s-30s).',
  ),
  _GestureItem(
    GestureKind.doubleTapMiddle,
    'Double-tap the middle - play / pause',
    'Double-tap the CENTER of the video to pause and resume - no need to '
        'aim for the small button.',
  ),
  _GestureItem(
    GestureKind.swipeBrightness,
    'Swipe on the LEFT half - brightness',
    'Put a finger on the left half of the video and slide UP to brighten or '
        'DOWN to dim (a percentage shows at the top while you swipe). This '
        'is app-local: your normal brightness is restored the moment you '
        'leave the player.',
  ),
  _GestureItem(
    GestureKind.swipeVolume,
    'Swipe on the RIGHT half - volume',
    'The same gesture on the right half changes the volume. Sliding all the '
        'way down mutes the video; swipe up or tap the speaker button to '
        'unmute.',
  ),
  _GestureItem(
    GestureKind.swipeSeek,
    'Swipe SIDEWAYS - scrub through the video',
    'Drag one finger LEFT or RIGHT anywhere on the video to scrub: the pill '
        'at the top shows how far you are jumping ("+45s · 03:12") and the '
        'video follows live while you drag. A full screen-width swipe is '
        '±90 seconds. Release to land exactly there. When zoomed in, the '
        'same drag moves the picture instead. Can be turned off in ⚙ '
        'settings → Gesture controls.',
  ),
  _GestureItem(
    GestureKind.pinchZoom,
    'Pinch with two fingers - zoom up to 4×',
    'Place TWO fingers on the video and spread them apart to zoom in, pinch '
        'them together to zoom out (1.0× to 4.0×). The zoom anchors at your '
        'fingers, and while zoomed you can drag with ONE finger to move the '
        'picture around. If you pinch back almost to 1×, the video snaps '
        'back to normal on its own.',
  ),
  _GestureItem(
    GestureKind.holdSpeed,
    'Hold your finger - speed boost',
    'Press and HOLD anywhere on the video to play faster (2× by default) '
        'for as long as you keep holding; lift your finger to return to '
        'normal speed. The "2.0x" badge stays visible at the top for the '
        'whole boost. The multiplier (1.5×/2×/2.5×/3×) is set in ⚙ settings.',
  ),
];

const List<_Item> _playerItems = [
  _Item(
    Icons.queue_music,
    'Playlist / queue',
    'Opens the side panel with everything queued up. Tap any row to jump to '
        'that video, the small ✕ to remove one, and the » button at the top '
        'to collapse the panel again.',
  ),
  _Item(
    Icons.fullscreen,
    'Fullscreen',
    'Fills the entire screen (and switches to landscape). All gestures keep '
        'working. Press the same button or the back gesture to return.',
  ),
  _Item(
    Icons.screen_rotation,
    'Rotation lock',
    'By default the player follows your phone - tip it sideways and the '
        'video rotates with you. Tap the rotate button to LOCK the current '
        'orientation (it keeps the video put no matter how you tilt); tap '
        'again to release the lock.',
  ),
  _Item(
    Icons.aspect_ratio,
    'Fit (picture size)',
    'Cycles Contain → Crop → Stretch. Contain shows the whole frame with '
        'bars, Crop zooms to fill the screen (edges cut), Stretch fills '
        'exactly (may distort).',
  ),
  _Item(
    Icons.graphic_eq,
    'Equalizer (top bar)',
    'Five-band equalizer with presets (Bass, Vocal, Treble, Rock...). Your '
        'last setting is remembered and applied to every video.',
  ),
  _Item(
    Icons.timer_outlined,
    'A→B loop',
    'Tap at the start of the part you want to repeat (A lights up), tap '
        'again at the end (B lights up) - that section loops until you tap '
        'a third time to clear.',
  ),
  _Item(
    Icons.picture_in_picture_alt_outlined,
    'Picture-in-picture (top bar)',
    'Shrinks the video to a floating window that keeps playing while you '
        'use other apps. Tap the window for a play/pause button, drag it to '
        'any corner, and tap the expand icon to come back full-screen.',
  ),
  _Item(
    Icons.speed,
    'Playback speed',
    'Tap the "1.0x" label in the bottom controls to pick a constant speed '
        'from 0.5× up to 2×.',
  ),
  _Item(
    Icons.subtitles_outlined,
    'Subtitles & audio tracks',
    'Switch between embedded subtitle languages or turn them off, and pick '
        'a different audio track for dual-audio files (e.g. Hindi / '
        'English).',
  ),
  _Item(
    Icons.cast_outlined,
    'Cast to TV (top bar)',
    'Tap the cast icon to send the video to any DLNA smart TV or Android '
        'box on the same Wi-Fi. The phone turns into a remote: play/pause, '
        'a live seek slider, and "Stop casting" hands the video back to '
        'the phone right where the TV left off. Closing the player stops '
        'casting. (Chromecast dongles use a different protocol and are '
        'not supported yet.)',
  ),
  _Item(
    Icons.camera_alt_outlined,
    'Screenshot (top bar)',
    'Saves the current frame - with any subtitles burned in, exactly as '
        'you see it - as a PNG into Pictures/Max Player, visible in your '
        'gallery at once. Not available for online streams.',
  ),
  _Item(
    Icons.lock_outline,
    'Screen lock / kids mode (left edge)',
    'The lock button on the left edge of the video locks EVERY button and '
        'gesture - safe to hand the phone to a child or keep in a pocket. '
        'To unlock, double-tap (or long-press) the lock on the right edge. '
        'The button can be hidden in ⚙ settings → Player buttons.',
  ),
  _Item(
    Icons.settings_outlined,
    'Player settings (⚙ top bar)',
    'Every gesture can be turned on/off individually (including horizontal '
        'swipe-to-seek), plus: seek step, auto-hide delay, speed-boost '
        'multiplier, resume playback, and which extra buttons (cast / '
        'screenshot / lock) show in the player.',
  ),
];

/// v21: the feature list Max Player has that other players do not.
const List<_Item> _smartItems = [
  _Item(
    Icons.translate,
    'AI subtitles in English (translate)',
    'Play a foreign-language video → subtitle button → AI subtitles → '
        'choose "→ English" before generating. Any spoken language becomes '
        'English subtitles, fully on-device.',
  ),
  _Item(
    Icons.lyrics_outlined,
    'Karaoke word highlight',
    'Player ⋮ menu → Karaoke subtitles: words light up one by one as they '
        'are spoken. Works with ANY subtitle - AI captions, the video\'s own '
        '.srt file, or subtitles embedded in the video. While karaoke is '
        'on, the normal subtitle display turns OFF so only the karaoke '
        'line shows. The same switch also lives in Player settings → '
        'Sound & subtitles.',
  ),
  _Item(
    Icons.fast_forward,
    'Skip intro chip',
    'When subtitles (AI captions or the video\'s own .srt file) show the '
        'dialogue starts late, a "Skip to …" chip appears near the start '
        'of the video. Turn it off in Player settings → Skip intro chip.',
  ),
  _Item(
    Icons.volume_up,
    'Volume boost up to 200%',
    'ON by default: the volume swipe simply continues past 100% for quiet '
        'videos. Player settings → Sound & subtitles switches it off.',
  ),
  _Item(
    Icons.graphic_eq,
    'Volume leveling',
    'Player settings → Sound & subtitles → Volume leveling: soft dialogue '
        'and loud explosions play at a steady loudness. Combines with the '
        'equalizer instead of replacing it.',
  ),
  _Item(
    Icons.bedtime_outlined,
    'Sleep timer',
    'Player ⋮ menu → Sleep timer: pauses playback after 15/30/45/60 '
        'minutes, or exactly at the end of the current video. While it '
        'runs, the remaining time shows under the video title.',
  ),
  _Item(
    Icons.speed,
    'Playback speed up to 3x',
    'Tap the "1.0x" button in the player controls: 0.5x … 3x (v22 added '
        '2.5x and 3x).',
  ),
  _Item(
    Icons.lock_outline,
    'Private folder (PIN)',
    'Long-press any video → "Move to Private folder". Hidden videos '
        'disappear from Gallery and file managers. Open them from the 🔒 '
        'icon in the library top bar after your PIN. Note: uninstalling '
        'the app deletes hidden videos - move them out first.',
  ),
];

const List<_Item> _tipItems = [
  _Item(
    Icons.info_outline,
    'A new video does not appear in the library?',
    'Press the ⟳ rescan button in the top bar. If it is still missing, '
        'check the file extension is a common one (.mp4, .mkv, .webm, ...) '
        'and that Max Player has storage permission.',
  ),
  _Item(
    Icons.info_outline,
    'Max Player does not show in "Open with"?',
    'Some galleries only offer Share: long-press the video → Share → Max '
        'Player. You can also open Android Settings → Apps → Max Player → '
        '"Open by default" and enable it for videos.',
  ),
  _Item(
    Icons.info_outline,
    'Can it play 8K video?',
    'Yes - 8K files (HEVC, VP9 or AV1) open and play. Smooth playback '
        'depends on your phone: recent flagships decode 8K in hardware, '
        'while mid-range chips may stutter at 8K. 1080p and 4K play '
        'smoothly on almost every device.',
  ),
  _Item(
    Icons.info_outline,
    'A video will not play at all?',
    'Very rarely a file uses an unusual codec. Try playing it from its '
        'share menu (Share → Max Player) or re-encode it to H.264/AAC - '
        'the most compatible combination.',
  ),
];
EOF_MARKER_11

mkdir -p "$(dirname 'lib/widgets/video_tile.dart')"
cat > 'lib/widgets/video_tile.dart' <<'EOF_MARKER_12'
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';
import '../state/theme_state.dart';
import 'fade_in_image.dart';

class VideoTile extends StatelessWidget {
  final VideoTrack track;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  const VideoTile({
    super.key,
    required this.track,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (track.thumbnailPath != null)
                    Image.file(
                      File(track.thumbnailPath!),
                      fit: BoxFit.cover,
                      // v22: bound the decode size - a stray full-size
                      // capture must never cost a 33 MB bitmap while
                      // scrolling the grid.
                      cacheWidth: 360,
                      frameBuilder: fadeInImageFrame,
                      errorBuilder: (_, __, ___) => const _Placeholder(),
                    )
                  else
                    const _Placeholder(),
                  // Quality badge (e.g. "1080p"), top-left like VLC.
                  if (track.qualityLabel != null)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          track.qualityLabel!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Favourite toggle
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onFavorite,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          size: 15,
                          color: isFavorite
                              ? themeState.accent
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  // Duration pill
                  if (track.duration != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          formatDuration(track.duration),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatFileSize(track.sizeBytes),
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5)),
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

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 32, color: Colors.white24),
      ),
    );
  }
}
EOF_MARKER_12

mkdir -p "$(dirname 'lib/widgets/video_list_item.dart')"
cat > 'lib/widgets/video_list_item.dart' <<'EOF_MARKER_13'
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';
import '../state/theme_state.dart';
import 'fade_in_image.dart';

/// List-mode row for the library (see "Display in list" in the settings
/// sheet): small thumbnail, title, size + duration, and a favourite toggle.
class VideoListItem extends StatelessWidget {
  final VideoTrack track;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  const VideoListItem({
    super.key,
    required this.track,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final duration = formatDuration(track.duration);
    final size = formatFileSize(track.sizeBytes);
    final parts = <String>[
      if (track.qualityLabel != null) track.qualityLabel!,
      if (duration != '--:--') duration,
      if (size.isNotEmpty) size,
    ];
    final subtitle = parts.join('  ·  ');

    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 96,
          height: 54,
          child: _Thumb(track: track),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.white38),
      ),
      trailing: IconButton(
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 20,
          color: isFavorite ? themeState.accent : Colors.white38,
        ),
        onPressed: onFavorite,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final VideoTrack track;
  const _Thumb({required this.track});

  @override
  Widget build(BuildContext context) {
    if (track.thumbnailPath != null) {
      return Image.file(
        File(track.thumbnailPath!),
        fit: BoxFit.cover,
        cacheWidth: 220, // v22: bound the decode size (see video_tile)
        frameBuilder: fadeInImageFrame,
        errorBuilder: (_, __, ___) => const _Placeholder(),
      );
    }
    return const _Placeholder();
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF12121a),
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 22, color: Colors.white24),
      ),
    );
  }
}
EOF_MARKER_13

mkdir -p "$(dirname 'lib/widgets/progress_bar.dart')"
cat > 'lib/widgets/progress_bar.dart' <<'EOF_MARKER_14'
import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/formatters.dart';
import '../state/theme_state.dart';

/// The seek slider + time labels.
///
/// v19: while the user DRAGS, a preview bubble floats above the thumb
/// showing the video frame at that position (once the native thumbnail
/// strip is ready) plus the exact timestamp.
class VideoProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  /// Optional thumbnail lookup for the scrub preview bubble: receives a
  /// 0..1 fraction of the video and returns an image path, or null while
  /// that frame hasn't been generated yet (the bubble shows a placeholder).
  final String? Function(double fraction)? previewThumb;

  const VideoProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.previewThumb,
  });

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  double? _dragValue; // 0..1 while the user is dragging

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds.clamp(1, 1 << 62);
    final value =
        _dragValue ?? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final shownMs = (_dragValue != null
            ? _dragValue! * totalMs
            : widget.position.inMilliseconds)
        .round();

    return Row(
      children: [
        Text(formatDuration(Duration(milliseconds: shownMs)),
            style: _timeStyle),
        const SizedBox(width: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              const bubbleW = 132.0;
              final dragging = _dragValue != null;
              final thumbPath = dragging && widget.previewThumb != null
                  ? widget.previewThumb!(_dragValue!)
                  : null;
              // Keep the bubble fully on screen.
              final rawLeft = dragging
                  ? _dragValue! * (w - 28) + 14 - bubbleW / 2
                  : 0.0;
              final left = rawLeft
                  .clamp(0.0, (w - bubbleW).clamp(0.0, w))
                  .toDouble();
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: themeState.accent,
                      inactiveTrackColor:
                          themeState.accent.withValues(alpha: 0.15),
                      thumbColor: themeState.accent,
                    ),
                    child: Slider(
                      value: value,
                      onChanged: (v) => setState(() => _dragValue = v),
                      onChangeEnd: (v) {
                        widget.onSeek(
                            Duration(milliseconds: (v * totalMs).round()));
                        setState(() => _dragValue = null);
                      },
                    ),
                  ),
                  if (dragging)
                    Positioned(
                      bottom: 30,
                      left: left,
                      child: IgnorePointer(
                        child: Container(
                          width: bubbleW,
                          padding: const EdgeInsets.fromLTRB(5, 5, 5, 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: themeState.accent
                                    .withValues(alpha: 0.35)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: bubbleW - 10,
                                  height: (bubbleW - 10) * 9 / 16,
                                  child: thumbPath != null
                                      ? Image.file(
                                          File(thumbPath),
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                          // Frames arriving mid-drag.
                                          errorBuilder: (_, __, ___) =>
                                              const _NoThumb(),
                                        )
                                      : const _NoThumb(),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatDuration(
                                    Duration(milliseconds: shownMs)),
                                style: TextStyle(
                                  color: themeState.accent,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 4),
        Text(formatDuration(widget.duration), style: _timeStyle),
      ],
    );
  }

  // v23: time labels ride the theme colour (75% strength, like all
  // secondary player chrome).
  static final _timeStyle = TextStyle(
      fontSize: 12, color: themeState.accent.withValues(alpha: 0.75));
}

class _NoThumb extends StatelessWidget {
  const _NoThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1e2a),
      child: Center(
        child: Icon(Icons.movie_outlined,
            size: 18, color: themeState.accent.withValues(alpha: 0.35)),
      ),
    );
  }
}
EOF_MARKER_14

mkdir -p "$(dirname 'lib/widgets/track_selection_sheet.dart')"
cat > 'lib/widgets/track_selection_sheet.dart' <<'EOF_MARKER_15'
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import '../state/theme_state.dart';
import '../utils/ai_subtitles.dart';

import '../state/media_player_state.dart';

/// Bottom sheet listing the current media's audio or subtitle tracks, with a
/// check on the active one. Opened from the player controls.
class TrackSelectionSheet extends StatelessWidget {
  final MediaPlayerState player;
  final bool isSubtitle;

  const TrackSelectionSheet({
    super.key,
    required this.player,
    required this.isSubtitle,
  });

  static Color get _accent => themeState.accent;
  static const Color _surface = Color(0xFF1a1a24);

  static Future<void> show(
    BuildContext context,
    MediaPlayerState player, {
    required bool isSubtitle,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          TrackSelectionSheet(player: player, isSubtitle: isSubtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: themeState.accent.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              isSubtitle ? 'Subtitles' : 'Audio track',
              style: TextStyle(
                color: _accent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Flexible(
            child: isSubtitle ? _subtitleList(context) : _audioList(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _audioList(BuildContext context) {
    // Dedupe by id - some containers list an entry twice.
    final tracks = <String, AudioTrack>{};
    for (final t in player.audioTracks) {
      if (t.id == 'no') continue;
      tracks[t.id] = t;
    }
    final list = tracks.values.toList();
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('No audio tracks found',
            style: TextStyle(color: themeState.accent.withValues(alpha: 0.5))),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (var i = 0; i < list.length; i++)
          _TrackTile(
            label: _audioLabel(list[i], i),
            detail: list[i].language,
            selected: player.currentAudioTrack?.id == list[i].id,
            onTap: () {
              player.selectAudioTrack(list[i]);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  Widget _subtitleList(BuildContext context) {
    // "no" is the explicit OFF entry; dedupe the rest by id.
    final tracks = <String, SubtitleTrack>{};
    for (final t in player.subtitleTracks) {
      if (t.id == 'no') continue;
      tracks[t.id] = t;
    }
    final list = [SubtitleTrack.no(), ...tracks.values];
    return ListView(
      shrinkWrap: true,
      children: [
        for (var i = 0; i < list.length; i++)
          _TrackTile(
            label: _subtitleLabel(list[i], i),
            detail: list[i].language ?? list[i].codec,
            selected: player.currentSubtitleTrack?.id == list[i].id,
            onTap: () {
              player.selectSubtitleTrack(list[i]);
              Navigator.of(context).pop();
            },
          ),
        Divider(
            height: 16,
            color: themeState.accent.withValues(alpha: 0.18)),
        // Offline AI subtitle generation (whisper.cpp) - free, no internet
        // after the one-time model download.
        ListTile(
          dense: true,
          leading: Icon(Icons.auto_awesome,
              size: 20, color: TrackSelectionSheet._accent),
          title: Text(
            'Generate with AI ✨',
            style: TextStyle(
              color: themeState.accent,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'Offline & free · the AI writes subtitles for this video',
            style: TextStyle(
                color: themeState.accent.withValues(alpha: 0.5),
                fontSize: 12),
          ),
          onTap: () {
            final rootCtx =
                Navigator.of(context, rootNavigator: true).context;
            Navigator.of(context).pop();
            AiSubtitleRunner.start(rootCtx, player);
          },
        ),
      ],
    );
  }

  String _audioLabel(AudioTrack t, int index) {
    if (t.id == 'auto') return 'Auto';
    final title = t.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    return t.language?.toUpperCase() ?? 'Audio ${index + 1}';
  }

  String _subtitleLabel(SubtitleTrack t, int index) {
    if (t.id == 'no') return 'Off';
    if (t.id == 'auto') return 'Auto';
    final title = t.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    return t.language?.toUpperCase() ?? 'Subtitle $index';
  }
}

class _TrackTile extends StatelessWidget {
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  const _TrackTile({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: SizedBox(
        width: 24,
        child: selected
            ? Icon(Icons.check,
                size: 18, color: TrackSelectionSheet._accent)
            : null,
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          // v23: theme colour everywhere (full strength when selected).
          color: selected
              ? themeState.accent
              : themeState.accent.withValues(alpha: 0.75),
          fontSize: 15,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: (detail != null && detail!.isNotEmpty)
          ? Text(detail!,
              style: TextStyle(
                  color: themeState.accent.withValues(alpha: 0.5),
                  fontSize: 12))
          : null,
    );
  }
}
EOF_MARKER_15

mkdir -p "$(dirname 'lib/widgets/equalizer_sheet.dart')"
cat > 'lib/widgets/equalizer_sheet.dart' <<'EOF_MARKER_16'
import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';

/// 5-band equalizer backed by libmpv's lavfi `equalizer` filters, applied via
/// NativePlayer.setProperty('af', ...). Changes apply live during playback.
class EqualizerSheet extends StatefulWidget {
  final MediaPlayerState player;

  const EqualizerSheet({super.key, required this.player});

  static const surface = Color(0xFF1a1a24);

  static Future<void> show(BuildContext context, MediaPlayerState player) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EqualizerSheet(player: player),
    );
  }

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  late List<double> _gains;
  late bool _enabled;

  static const _presets = <String, List<double>>{
    'Flat': [0, 0, 0, 0, 0],
    'Bass': [6, 4, 0, -1, -2],
    'Vocal': [-2, 0, 3, 3, 0],
    'Treble': [-2, -1, 0, 4, 6],
    'Rock': [4, 2, -1, 2, 4],
  };

  static const _bandLabels = ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];

  @override
  void initState() {
    super.initState();
    _gains = List.of(widget.player.eqGains);
    _enabled = widget.player.eqEnabled;
  }

  void _apply() {
    widget.player.applyEqualizer(_gains, _enabled);
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: themeState.accent.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Equalizer',
                      style: TextStyle(
                        color: accent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    activeThumbColor: accent,
                    onChanged: (v) {
                      setState(() => _enabled = v);
                      _apply();
                    },
                  ),
                ],
              ),
            ),
            // Preset chips
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final p in _presets.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(p.key),
                        labelStyle: TextStyle(
                            color: themeState.accent.withValues(alpha: 0.75)),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        side: BorderSide.none,
                        onPressed: () {
                          setState(() {
                            _gains = List.of(p.value);
                            _enabled = true;
                          });
                          _apply();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Band sliders
            Opacity(
              opacity: _enabled ? 1 : 0.4,
              child: IgnorePointer(
                ignoring: !_enabled,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < _bandLabels.length; i++)
                      _BandSlider(
                        label: _bandLabels[i],
                        value: _gains[i],
                        accent: accent,
                        onChanged: (v) {
                          setState(() => _gains[i] = v);
                          _apply();
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  final String label;
  final double value; // dB, -12..+12
  final Color accent;
  final ValueChanged<double> onChanged;

  const _BandSlider({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value.toStringAsFixed(0),
            style: TextStyle(
                color: themeState.accent.withValues(alpha: 0.5),
                fontSize: 11)),
        SizedBox(
          height: 140,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: accent,
                thumbColor: accent,
                inactiveTrackColor: accent.withValues(alpha: 0.18),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.clamp(-12.0, 12.0),
                min: -12,
                max: 12,
                divisions: 24,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        Text(label,
            style: TextStyle(
                color: themeState.accent.withValues(alpha: 0.6),
                fontSize: 11)),
      ],
    );
  }
}
EOF_MARKER_16

mkdir -p "$(dirname 'lib/widgets/video_info_sheet.dart')"
cat > 'lib/widgets/video_info_sheet.dart' <<'EOF_MARKER_17'
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// Bottom sheet with technical details about the video currently loaded in
/// the player (resolution, codec, bitrate, size, duration, path...).
/// Values are refreshed live from the native MediaMetadataRetriever.
class VideoInfoSheet extends StatelessWidget {
  final MediaPlayerState player;

  /// Provided by the wrapping DraggableScrollableSheet so the info list can
  /// be dragged/scrolled up to see every row (v20).
  final ScrollController? scrollController;

  const VideoInfoSheet({
    super.key,
    required this.player,
    this.scrollController,
  });

  static Future<void> show(BuildContext context, MediaPlayerState player) {
    // v20: isScrollControlled + DraggableScrollableSheet - the old
    // fixed-height sheet cropped the bottom rows on small screens and
    // could not be dragged up ("video info is not sliding"). Now it drags
    // between 30% and 90% of the screen and the rows scroll.
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => VideoInfoSheet(
          player: player,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = player.currentTrack;
    final accent = themeState.accent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        // v20: scrollable content - pairs with the DraggableScrollableSheet
        // in show() so every row can be pulled up into view.
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Video info',
              style: TextStyle(
                color: accent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (track == null)
              Text('Nothing is loaded right now',
                  style: TextStyle(
                      color: themeState.accent.withValues(alpha: 0.5)))
            else
              FutureBuilder<VideoMetadata>(
                future: track.path.contains('://')
                    ? null
                    : NativeBridge.fetchMetadata(track.path),
                builder: (context, snap) {
                  final meta = snap.data;
                  final w = meta?.width ?? track.width;
                  final h = meta?.height ?? track.height;
                  final sizeBytes =
                      track.sizeBytes ?? _fileSizeOrNull(track.path);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Row('Name', track.title),
                      _Row('Location', track.path, small: true),
                      _Row(
                        'Resolution',
                        (w != null && h != null && w > 0)
                            ? '$w × $h  ·  ${track.qualityLabel ?? ''}'
                            : 'Unknown',
                      ),
                      _Row(
                          'Duration',
                          formatDuration(
                              meta?.duration ?? track.duration ??
                                  player.duration)),
                      _Row('File size', sizeBytes == null
                          ? 'Unknown'
                          : formatFileSize(sizeBytes)),
                      if (meta?.codec != null)
                        _Row('Video codec', meta!.codec!.toUpperCase()),
                      if (meta?.bitrateBps != null && meta!.bitrateBps! > 0)
                        _Row('Bitrate',
                            '${(meta.bitrateBps! / 1000000).toStringAsFixed(1)} Mbps'),
                      _Row('Queue position',
                          '${player.currentIndex + 1} of ${player.playlist.length}'),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  int? _fileSizeOrNull(String path) {
    try {
      if (path.contains('://')) return null;
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool small;

  const _Row(this.label, this.value, {this.small = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 106,
            child: Text(
              label,
              style: TextStyle(
                  color: themeState.accent.withValues(alpha: 0.5),
                  fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: themeState.accent,
                fontSize: small ? 11.5 : 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
EOF_MARKER_17

mkdir -p "$(dirname 'lib/widgets/cast_sheet.dart')"
cat > 'lib/widgets/cast_sheet.dart' <<'EOF_MARKER_18'
import 'package:flutter/material.dart';

import '../cast/cast_state.dart';
import '../cast/cast_support.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// "Cast to TV" sheet: scans the Wi-Fi for DLNA renderers, connects, and
/// then turns into a little remote (play/pause, seek slider, disconnect).
///
/// Pure UI - all network logic lives in [CastState]. The parent passes
/// [videoPath]/[title]/[subsPath] for the currently loaded video and
/// [onCastStarted]/[onCastStopped] hooks so the local player can pause
/// while the TV plays and resume (at the TV position) afterwards.
class CastSheet extends StatefulWidget {
  final CastState cast;
  final String videoPath;
  final String title;
  final String? subsPath;

  /// Local playback should pause once the TV takes over.
  final VoidCallback onCastStarted;

  /// Casting fully stopped (user pressed "Stop casting"); resume locally
  /// from [CastState.tvPosition].
  final Future<void> Function(Duration tvPosition) onCastStopped;

  const CastSheet({
    super.key,
    required this.cast,
    required this.videoPath,
    required this.title,
    required this.subsPath,
    required this.onCastStarted,
    required this.onCastStopped,
  });

  static Future<void> show(
    BuildContext context,
    CastState cast, {
    required String videoPath,
    required String title,
    String? subsPath,
    required VoidCallback onCastStarted,
    required Future<void> Function(Duration tvPosition) onCastStopped,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CastSheet(
        cast: cast,
        videoPath: videoPath,
        title: title,
        subsPath: subsPath,
        onCastStarted: onCastStarted,
        onCastStopped: onCastStopped,
      ),
    );
  }

  @override
  State<CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<CastSheet> {
  Color get _accent => themeState.accent;

  Future<void> _connect(DlnaDevice d) async {
    await widget.cast.connect(
      d,
      videoPath: widget.videoPath,
      title: widget.title,
      subsPath: widget.subsPath,
    );
    if (widget.cast.phase == CastPhase.casting) {
      widget.onCastStarted();
    }
  }

  Future<void> _stop() async {
    final pos = widget.cast.tvPosition;
    await widget.cast.stopCast();
    await widget.onCastStopped(pos);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: widget.cast,
        builder: (context, _) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 8,
              right: 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                  child: Row(
                    children: [
                      Icon(Icons.cast_connected, color: _accent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cast to TV',
                          style: TextStyle(
                            color: _accent,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.cast.phase == CastPhase.scanning)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                _body(),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _body() {
    final cast = widget.cast;
    switch (cast.phase) {
      case CastPhase.scanning:
        return _message(
          Icons.wifi_find,
          'Searching for TVs…',
          'Make sure the TV is ON and on the same Wi-Fi as this phone.',
        );

      case CastPhase.connecting:
        return _message(
          Icons.cast_connected,
          'Connecting to ${cast.current?.name ?? 'TV'}…',
          'Handing the video over - this takes a second.',
        );

      case CastPhase.casting:
        return _castingView();

      case CastPhase.error:
        return Column(
          children: [
            _message(Icons.error_outline, 'Connection problem', cast.error),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: cast.scan,
              icon: Icon(Icons.refresh, color: _accent, size: 20),
              label: Text('Scan again',
                  style: TextStyle(color: _accent, fontSize: 15)),
            ),
          ],
        );

      case CastPhase.scanDone:
      case CastPhase.idle:
        if (cast.devices.isEmpty && cast.phase == CastPhase.scanDone) {
          return Column(
            children: [
              _message(
                Icons.tv_off,
                'No TVs found',
                cast.repliesSeen == 0
                    ? 'Nothing on this Wi-Fi answered the search (${cast.repliesSeen} replies). '
                        'Check the phone and TV are on the SAME Wi-Fi (not '
                        'mobile data / guest network), then scan again.'
                    : '${cast.repliesSeen} device(s) answered, but none offer '
                        'DLNA video playback. Many newer Samsung/LG TVs '
                        'dropped DLNA - try opening the video in a DLNA '
                        'renderer app on the TV (e.g. VLC for Android TV) '
                        'and scan again.',
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: widget.cast.scan,
                icon: Icon(Icons.refresh, color: _accent, size: 20),
                label: Text('Scan again',
                    style: TextStyle(color: _accent, fontSize: 15)),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in widget.cast.devices)
              ListTile(
                leading: Icon(Icons.tv,
                    color: themeState.accent.withValues(alpha: 0.75)),
                title: Text(
                  d.name,
                  style: TextStyle(color: themeState.accent, fontSize: 15),
                ),
                subtitle: Text(
                  'Tap to start casting',
                  style: TextStyle(
                      color: themeState.accent.withValues(alpha: 0.5),
                      fontSize: 12),
                ),
                onTap: () => _connect(d),
              ),
            if (widget.cast.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton.icon(
                  onPressed: widget.cast.scan,
                  icon: Icon(Icons.wifi_find, color: _accent, size: 20),
                  label: Text('Search for TVs',
                      style: TextStyle(color: _accent, fontSize: 15)),
                ),
              ),
          ],
        );
    }
  }

  Widget _castingView() {
    final cast = widget.cast;
    final total = cast.tvDuration;
    final pos = cast.tvPosition;
    final max = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
    final value =
        pos.inMilliseconds.clamp(0, total.inMilliseconds).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.connected_tv, color: _accent, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cast.current?.name ?? 'TV',
                      style: TextStyle(
                        color: themeState.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Playing on your TV - this phone is the remote',
                      style: TextStyle(
                          color: themeState.accent.withValues(alpha: 0.5),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                formatDuration(pos),
                style: TextStyle(
                    color: themeState.accent.withValues(alpha: 0.75),
                    fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  max: max,
                  onChanged: (v) {},
                  onChangeEnd: (v) =>
                      cast.seekTo(Duration(milliseconds: v.round())),
                  activeColor: _accent,
                  inactiveColor: _accent.withValues(alpha: 0.18),
                ),
              ),
              Text(
                formatDuration(total),
                style: TextStyle(
                    color: themeState.accent.withValues(alpha: 0.75),
                    fontSize: 12),
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 52,
              icon: Icon(
                cast.tvPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: themeState.accent,
              ),
              onPressed: cast.togglePlayPause,
            ),
          ],
        ),
        TextButton.icon(
          onPressed: _stop,
          icon: const Icon(Icons.cast_connected,
              color: Colors.redAccent, size: 20),
          label: const Text(
            'Stop casting',
            style: TextStyle(color: Colors.redAccent, fontSize: 15),
          ),
        ),
      ],
    );
  }

  Widget _message(IconData icon, String title, [String? body]) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Icon(icon,
              color: themeState.accent.withValues(alpha: 0.5), size: 42),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: themeState.accent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: themeState.accent.withValues(alpha: 0.6),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
EOF_MARKER_18

mkdir -p "$(dirname 'lib/widgets/playlist_panel.dart')"
cat > 'lib/widgets/playlist_panel.dart' <<'EOF_MARKER_19'
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';
import '../state/theme_state.dart';
import 'fade_in_image.dart';

class PlaylistPanel extends StatelessWidget {
  final List<VideoTrack> playlist;
  final int currentIndex;
  final ValueChanged<int> onPlay;
  final ValueChanged<int> onRemove;

  /// Collapses the side panel (the ✕ button in the header).
  final VoidCallback onClose;

  const PlaylistPanel({
    super.key,
    required this.playlist,
    required this.currentIndex,
    required this.onPlay,
    required this.onRemove,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Panel header with an ALWAYS-visible collapse button (previously
        // there was no way to close the panel except the same toolbar icon
        // that opened it - easy to miss).
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(Icons.queue_music, size: 18, color: themeState.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Queue · ${playlist.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: themeState.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Collapse playlist',
                icon: Icon(
                  Icons.last_page,
                  size: 20,
                  color: themeState.accent.withValues(alpha: 0.75),
                ),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        Divider(
            height: 1, color: themeState.accent.withValues(alpha: 0.18)),
        Expanded(
          child: playlist.isEmpty
              ? Center(
                  child: Text(
                    'Queue is empty',
                    style: TextStyle(
                        color: themeState.accent.withValues(alpha: 0.5)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: playlist.length,
                  itemBuilder: (context, i) {
                    final track = playlist[i];
                    final active = i == currentIndex;
                    return ListTile(
                      dense: true,
                      onTap: () => onPlay(i),
                      tileColor: active
                          ? themeState.accent.withValues(alpha: 0.10)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      // Thumbnail with a small "now playing" badge on the active row.
                      leading: SizedBox(
                        width: 56,
                        height: 34,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: _QueueThumb(track: track),
                            ),
                            if (active)
                              Positioned(
                                right: 2,
                                bottom: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.black87,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.equalizer,
                                    size: 10,
                                    color: themeState.accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: active
                              ? themeState.accent
                              : themeState.accent.withValues(alpha: 0.75),
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        _subtitleFor(track),
                        style: TextStyle(
                          fontSize: 11,
                          color: themeState.accent.withValues(alpha: 0.5),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 16,
                          color: themeState.accent.withValues(alpha: 0.5),
                        ),
                        onPressed: () => onRemove(i),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _subtitleFor(VideoTrack track) {
    final parts = <String>[
      if (track.qualityLabel != null) track.qualityLabel!,
      if (formatDuration(track.duration) != '--:--')
        formatDuration(track.duration),
      if (formatFileSize(track.sizeBytes).isNotEmpty)
        formatFileSize(track.sizeBytes),
    ];
    return parts.join('  ·  ');
  }
}

class _QueueThumb extends StatelessWidget {
  final VideoTrack track;
  const _QueueThumb({required this.track});

  @override
  Widget build(BuildContext context) {
    if (track.thumbnailPath != null) {
      return Image.file(
        File(track.thumbnailPath!),
        fit: BoxFit.cover,
        frameBuilder: fadeInImageFrame,
        errorBuilder: (_, __, ___) => const _Placeholder(),
      );
    }
    return const _Placeholder();
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1e2a),
      child: Center(
        child: Icon(Icons.movie_outlined,
            size: 16, color: themeState.accent.withValues(alpha: 0.35)),
      ),
    );
  }
}
EOF_MARKER_19

mkdir -p "$(dirname 'lib/widgets/mini_player.dart')"
cat > 'lib/widgets/mini_player.dart' <<'EOF_MARKER_20'
import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/player_screen.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'fade_in_image.dart';

/// Compact player bar pinned to the bottom of the home screen while something
/// is loaded in the player. Tap to return to the full player; close to stop.
class MiniPlayer extends StatelessWidget {
  final MediaPlayerState player;

  const MiniPlayer({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final track = player.currentTrack;
        final total = player.duration.inMilliseconds;
        final progress = total > 0
            ? (player.position.inMilliseconds / total).clamp(0.0, 1.0)
            : 0.0;
        // Slides/grows in smoothly when playback starts, shrinks away on stop.
        return AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: track == null
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: const Color(0xFF12121a),
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(player: player),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 2,
                          backgroundColor: accent.withValues(alpha: 0.18),
                          color: accent,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 56,
                                  height: 32,
                                  child: _thumb(track),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: accent,
                                      ),
                                    ),
                                    Text(
                                      '${formatDuration(player.position)} / ${formatDuration(player.duration)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: accent.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  player.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                  color: accent,
                                  size: 30,
                                ),
                                onPressed: player.togglePlay,
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.close,
                                  color: accent.withValues(alpha: 0.5),
                                  size: 20,
                                ),
                                onPressed: player.stopMini,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _thumb(dynamic track) {
    final thumb = track.thumbnailPath as String?;
    if (thumb != null) {
      return Image.file(
        File(thumb),
        fit: BoxFit.cover,
        frameBuilder: fadeInImageFrame,
        errorBuilder: (_, __, ___) => const _Placeholder(),
      );
    }
    return const _Placeholder();
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1e2a),
      child: Center(
        child: Icon(Icons.movie_outlined,
            size: 16, color: themeState.accent.withValues(alpha: 0.35)),
      ),
    );
  }
}
EOF_MARKER_20

mkdir -p "$(dirname 'lib/screens/player_screen.dart')"
cat > 'lib/screens/player_screen.dart' <<'EOF_MARKER_21'
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
import '../widgets/karaoke_subtitle.dart';
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

  // v20 fit cycle with REAL size choices (the old contain/cover/fill trio
  // looked identical for 16:9 videos, so it felt like "fit does nothing").
  // aspectRatio forces the frame to that shape (stretch); null keeps the
  // video's own aspect ratio.
  static const List<BoxFit> _fits = [
    BoxFit.contain, // Fit - whole frame visible
    BoxFit.cover, // Crop - fill screen, edges cropped
    BoxFit.fill, // Stretch - fill screen, ignores aspect
    BoxFit.fill, // 16:9 - frame forced to widescreen
    BoxFit.fill, // 4:3 - frame forced to classic TV
    BoxFit.none, // Original - pixels 1:1, may overflow
  ];
  static const List<double?> _fitAspects = [null, null, null, 16 / 9, 4 / 3, null];
  static const List<String> _fitNames = [
    'Fit',
    'Crop',
    'Stretch',
    '16:9',
    '4:3',
    'Original',
  ];
  int _fitIndex = 0;
  static const List<IconData> _fitIcons = [
    Icons.fit_screen,
    Icons.crop,
    Icons.open_in_full,
    Icons.crop_16_9,
    Icons.crop_landscape,
    Icons.crop_original,
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
    // v19: rotation is driven by our own accelerometer listener, so the
    // player rotates even when the phone's auto-rotate switch is OFF
    // (MX Player / VLC style). The lock chip pins the current orientation;
    // dispose() hands control back to the system.
    unawaited(NativeBridge.enableSensorRotate());
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
    // Hand rotation control back to the system; never leave a lock behind.
    unawaited(NativeBridge.disableSensorRotate());
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
    // v21: push the playback-extras settings into the player state.
    unawaited(widget.player.setVolumeBoost200(s.volumeBoost200));
    unawaited(widget.player.setVolumeLeveling(s.volumeLeveling));
    _applyKaraokeSubtitleVisibility(s);
    _startHideTimer();
  }

  /// Karaoke mode replaces mpv's own subtitle rendering with our
  /// word-highlight overlay. v22: the visibility decision now lives in the
  /// player state (setKaraokeMode) so it also reacts to track switches and
  /// late-arriving cue files; karaoke itself now reads mpv's live subtitle
  /// line, so it works with embedded and auto-loaded subtitles too.
  void _applyKaraokeSubtitleVisibility(PlayerSettings s) {
    unawaited(widget.player.setKaraokeMode(s.karaokeSubs));
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

  /// Rotation toggle: sensor auto-rotate <-> pinned to portrait/landscape.
  void _toggleOrientationLock() {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (!_orientationLocked) {
      unawaited(NativeBridge.lockRotation(landscape: landscape));
      setState(() {
        _orientationLocked = true;
        _lockedOrientations = landscape
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ];
      });
      _showIndicator('Rotation locked', Icons.screen_lock_rotation);
    } else {
      _lockedOrientations = DeviceOrientation.values;
      setState(() => _orientationLocked = false);
      unawaited(NativeBridge.enableSensorRotate());
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

  /// Which intro chip the user dismissed (per dialogue-start time; a new
  /// track recomputes it, so the chip auto-reappears for the next video).
  Duration? _skipChipDismissedFor;

  // ---------------------------------------------------------------------------
  // Sleep timer (v21)
  // ---------------------------------------------------------------------------

  void _showSleepSheet() {
    final player = widget.player;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        Widget item(IconData icon, String label,
            {String? sub, bool active = false, VoidCallback? onTap}) {
          return ListTile(
            leading: Icon(icon,
                // v23: the whole player UI rides the picked theme colour.
                color: active
                    ? themeState.accent
                    : themeState.accent.withValues(alpha: 0.75)),
            title: Text(label,
                style: TextStyle(color: themeState.accent)),
            subtitle: sub == null
                ? null
                : Text(sub,
                    style: TextStyle(
                        color: themeState.accent.withValues(alpha: 0.5),
                        fontSize: 12)),
            trailing: active
                ? Icon(Icons.check, color: themeState.accent)
                : null,
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTap?.call();
              _onUserInteraction();
            },
          );
        }

        return SafeArea(
          child: AnimatedBuilder(
            animation: player,
            builder: (context, _) {
              final label = player.sleepTimerLabel;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: themeState.accent.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label == null
                        ? 'Sleep timer'
                        : 'Sleep timer: stops in $label',
                    style: TextStyle(
                        color: themeState.accent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  for (final mins in const [15, 30, 45, 60])
                    item(Icons.bedtime_outlined, '$mins minutes',
                        active: label == '$mins min',
                        onTap: () => player.setSleepTimer(
                            forDuration: Duration(minutes: mins))),
                  item(Icons.movie_outlined, 'Until end of this video',
                      active: label == 'end of video',
                      onTap: () =>
                          player.setSleepTimer(atEndOfVideo: true)),
                  item(Icons.close, 'Off',
                      onTap: player.cancelSleepTimer),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );
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
    // Dragging up increases; a 300px sweep covers the full range. v21: the
    // volume range grows to 0..200% while the boost setting is on.
    final cap = _scaleMode == _ScaleMode.volume ? widget.player.volumeCap : 1.0;
    final v = (_dragStartValue - _dragAccum.dy / (300 * cap)).clamp(0.0, cap);
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
        // v19: no Scaffold AppBar anymore - the title + actions live in an
        // auto-hiding top overlay INSIDE the video stack, so portrait video
        // gets the full height and a tap reveals title and controls
        // together (previously a tap surfaced only the bottom bar).
        body: SafeArea(
          top: !_isFullscreen,
          // v20: in LANDSCAPE the controls sit flush with the bottom edge
          // (requested - "one step down"); portrait keeps the gesture-bar
          // clearance so the seek bar is not touched by the system bar.
          bottom: MediaQuery.of(context).orientation == Orientation.portrait,
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
                                            // v20: forces the frame to 16:9 /
                                            // 4:3 in those fit modes; null
                                            // keeps the video's own ratio.
                                            aspectRatio: _fitAspects[_fitIndex],
                                          ),
                                        )
                                      : Text(
                                          'No video loaded',
                                          style: TextStyle(
                                            color: themeState.accent.withValues(
                                                alpha: 0.5),
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
                                // v19: this sign used to BLINK during
                                // volume/brightness swipes - the old
                                // switcher re-keyed itself on every tick,
                                // replaying a scale animation each time.
                                // Now: ONE stable container, only opacity
                                // animates, text/icon swap in place.
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 120),
                                  opacity: (_indicatorText != null && !_isPip)
                                      ? 1.0
                                      : 0.0,
                                  child: Container(
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
                                            color: themeState.accent,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          _indicatorText ?? '',
                                          style: TextStyle(
                                            color: themeState.accent,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // v20: BIG centred "2x" sign in the MIDDLE of the
                          // video for the WHOLE long-press boost (replaces the
                          // small top badge). Follows the player state
                          // directly, so it vanishes the moment the video is
                          // paused during a boost.
                          Positioned.fill(
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
                                              horizontal: 14,
                                              vertical: 7,
                                            ),
                                            decoration: BoxDecoration(
                                              color: themeState.accent
                                                  .withValues(alpha: 0.9),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.fast_forward,
                                                  // v22: stays readable on
                                                  // the white accent too.
                                                  color: themeState.onAccent,
                                                  size: 19,
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  '${_settings.longPressMultiplier}x',
                                                  style: TextStyle(
                                                    color: themeState.onAccent,
                                                    fontSize: 15,
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
                          // Top bar (v19): back + marquee title + the
                          // merged more-actions menu + settings. Auto-hides
                          // with the controls, always readable over video.
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: !_controlsVisible,
                              child: AnimatedSlide(
                                offset: _controlsVisible && !_isPip
                                    ? Offset.zero
                                    : const Offset(0, -0.5),
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: AnimatedOpacity(
                                  opacity: _controlsVisible && !_isPip
                                      ? 1.0
                                      : 0.0,
                                  duration: const Duration(milliseconds: 180),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.75),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                        2, 2, 2, 14),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          tooltip: 'Back',
                                          icon: Icon(Icons.arrow_back,
                                              size: 22,
                                              color: themeState.accent),
                                          onPressed: () {
                                            _onUserInteraction();
                                            Navigator.of(context).maybePop();
                                          },
                                        ),
                                        Expanded(
                                          child: AnimatedBuilder(
                                            animation: player,
                                            builder: (context, _) {
                                              // v22: while a sleep timer
                                              // runs, show the remaining
                                              // time right under the title.
                                              final countdown = player
                                                  .sleepTimerCountdown;
                                              return Column(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .start,
                                                children: [
                                                  _MarqueeTitle(
                                                    player.currentTrack
                                                            ?.title ??
                                                        'Max Player',
                                                    key: ValueKey(
                                                      player.currentTrack
                                                          ?.path,
                                                    ),
                                                  ),
                                                  if (countdown != null)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets
                                                              .only(top: 2),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize
                                                                .min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .bedtime_outlined,
                                                            size: 11,
                                                            color:
                                                                themeState
                                                                    .accent,
                                                          ),
                                                          const SizedBox(
                                                              width: 4),
                                                          Text(
                                                            countdown ==
                                                                    'end of video'
                                                                ? 'Sleep: stops at end of video'
                                                                : 'Sleep in $countdown',
                                                            style:
                                                                TextStyle(
                                                              fontSize:
                                                                  10.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color:
                                                                  themeState
                                                                      .accent,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                        _topMenu(context),
                                        IconButton(
                                          tooltip: 'Player settings',
                                          icon: Icon(
                                              Icons.settings_outlined,
                                              size: 22,
                                              color: themeState.accent),
                                          onPressed: () {
                                            _onUserInteraction();
                                            _openSettings();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // v21: karaoke word-highlight for AI subtitles
                          // (replaces mpv's own subtitle rendering).
                          if (_settings.karaokeSubs && !_isPip)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 120,
                              child: KaraokeSubtitle(player: widget.player),
                            ),
                          // v21: "Skip intro" - offered while the AI captions
                          // say the dialogue hasn't started yet.
                          if (_settings.skipIntroChip && !_isPip)
                            Positioned(
                              right: 14,
                              bottom: 132,
                              child: AnimatedBuilder(
                                animation: widget.player,
                                builder: (context, _) {
                                  final at = widget.player.skipIntroAt;
                                  if (at == null) return const SizedBox.shrink();
                                  final pos = widget.player.position;
                                  final untimely = pos >=
                                          at - const Duration(seconds: 1) ||
                                      pos > const Duration(minutes: 10);
                                  if (_skipChipDismissedFor == at || untimely) {
                                    return const SizedBox.shrink();
                                  }
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        widget.player.seek(at);
                                        setState(
                                            () => _skipChipDismissedFor = at);
                                        _onUserInteraction();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 8, 8, 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xF2152026),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: themeState.accent
                                                .withValues(alpha: 0.65),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.fast_forward,
                                                size: 16,
                                                color: themeState.accent),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Skip to ${formatDuration(at)}',
                                              style: TextStyle(
                                                color: themeState.accent,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            GestureDetector(
                                              onTap: () => setState(() =>
                                                  _skipChipDismissedFor = at),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(4),
                                                child: Icon(Icons.close,
                                                    size: 14,
                                                    color: themeState.accent
                                                        .withValues(
                                                            alpha: 0.5)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
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

  /// The merged more-actions menu (v19): video info, equalizer,
  /// screenshot, cast and picture-in-picture behind ONE button.
  Widget _topMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: const Icon(Icons.more_vert, size: 22),
      color: const Color(0xFF1a1a24),
      onSelected: (v) {
        _onUserInteraction();
        switch (v) {
          case 'info':
            VideoInfoSheet.show(context, widget.player);
          case 'eq':
            EqualizerSheet.show(context, widget.player);
          case 'shot':
            _takeScreenshot();
          case 'cast':
            _openCast();
          case 'pip':
            NativeBridge.enterPip(playing: widget.player.isPlaying);
          case 'sleep':
            _showSleepSheet();
          case 'karaoke':
            final next = _settings.copyWith(
                karaokeSubs: !_settings.karaokeSubs);
            setState(() => _settings = next);
            next.save();
            _applyKaraokeSubtitleVisibility(next);
            if (widget.player.aiCues == null) {
              widget.player
                  .refreshAiCues(widget.player.currentTrack?.path ?? '');
            }
        }
      },
      itemBuilder: (context) => [
        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer'),
        if (_settings.screenshotButton)
          _topMenuItem('shot', Icons.camera_alt_outlined, 'Screenshot'),
        if (_settings.castButton)
          _topMenuItem('cast', Icons.cast_outlined, 'Cast to TV'),
        _topMenuItem('pip', Icons.picture_in_picture_alt_outlined,
            'Picture in picture'),
        _topMenuItem(
          'sleep',
          Icons.bedtime_outlined,
          widget.player.sleepTimerActive
              ? 'Sleep timer (${widget.player.sleepTimerLabel})'
              : 'Sleep timer',
        ),
        _topMenuItem(
          'karaoke',
          _settings.karaokeSubs
              ? Icons.closed_caption
              : Icons.closed_caption_off_outlined,
          _settings.karaokeSubs ? 'Karaoke subtitles (on)' : 'Karaoke subtitles',
        ),
      ],
    );
  }

  PopupMenuItem<String> _topMenuItem(
      String v, IconData icon, String label) {
    return PopupMenuItem(
      value: v,
      child: Row(
        children: [
          Icon(icon, size: 18, color: themeState.accent),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: themeState.accent)),
        ],
      ),
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
          border:
              Border.all(color: themeState.accent.withValues(alpha: 0.35)),
        ),
        child: Icon(icon, color: themeState.accent, size: 22),
      ),
    );
  }
}

enum _ScaleMode { undecided, volume, brightness, seekH, pan, zoom, cant }

/// Player title bar (v19): long titles scroll sideways in a slow loop
/// (marquee) instead of getting ellipsized. The widget is keyed by the
/// track path, so it restarts cleanly on track change.
class _MarqueeTitle extends StatefulWidget {
  final String text;
  const _MarqueeTitle(this.text, {super.key});

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle> {
  final ScrollController _sc = ScrollController();

  /// v21: CONSTANT speed (the timer version restarted the animation
  /// mid-flight for long titles, which made the speed visibly change).
  static const double _pixelsPerSecond = 80;
  static const Duration _holdAtStart = Duration(milliseconds: 700);
  static const Duration _holdAtEnd = Duration(milliseconds: 1100);

  @override
  void initState() {
    super.initState();
    _loop();
  }

  Future<void> _loop() async {
    while (mounted) {
      await Future<void>.delayed(_holdAtStart);
      if (!mounted || !_sc.hasClients) return;
      final max = _sc.position.maxScrollExtent;
      if (max <= 0) {
        // Text fits on screen - nothing to scroll; keep waiting.
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      final ms = (max / _pixelsPerSecond * 1000).round().clamp(400, 60000);
      try {
        await _sc.animateTo(
          max,
          duration: Duration(milliseconds: ms),
          curve: Curves.linear,
        );
      } catch (_) {
        return; // controller detached mid-animation (screen closed)
      }
      await Future<void>.delayed(_holdAtEnd);
      if (!mounted || !_sc.hasClients) return;
      _sc.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _sc,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        // v23: title rides the picked theme colour too.
        style: TextStyle(
          color: themeState.accent,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
EOF_MARKER_21

mkdir -p "$(dirname 'lib/screens/library_screen.dart')"
cat > 'lib/screens/library_screen.dart' <<'EOF_MARKER_22'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_info.dart';
import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/crash_log.dart';
import '../widgets/about_sheet.dart';
import '../widgets/display_settings_sheet.dart';
import '../state/private_vault.dart';
import '../widgets/mini_player.dart';
import '../widgets/user_manual_sheet.dart';
import 'private_screen.dart';
import '../widgets/video_list_item.dart';
import '../widgets/video_tile.dart';
import 'history_screen.dart';
import 'player_screen.dart';
import 'stats_screen.dart';

class LibraryScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;

  const LibraryScreen({super.key, required this.library, required this.player});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    widget.library.addListener(_onChange);
    // Automatically ask for storage permission and scan the whole device
    // the first time this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.library.folderName == null && !widget.library.isScanning) {
        widget.library.scanAllStorage();
      }
      // If the previous session died with an error, offer the recorded
      // crash report (copyable) so it can be sent for analysis.
      CrashLog.takeLast().then((report) {
        if (report != null && mounted) _showCrashReport(report);
      });
    });
  }

  void _showCrashReport(String report) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Max Player closed unexpectedly',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            report,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: report));
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Crash report copied - send it to the developer'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.library.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  void _playVideo(VideoTrack track) {
    final lib = widget.library;
    if (lib.playbackAction == PlaybackAction.single) {
      // Queue only the tapped file.
      widget.player.setPlaylistAndPlay([track], 0);
    } else {
      // Queue every visible video, starting at the tapped one.
      final all = lib.videos;
      final idx = all.indexWhere((v) => v.id == track.id);
      widget.player.setPlaylistAndPlay(all, idx >= 0 ? idx : 0);
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  /// v21: long-press a video -> offer moving it into the Private folder.
  Future<void> _offerHide(VideoTrack track, VideoLibraryState lib) async {
    // v22: moving a file out of public storage needs the same "All files
    // access" grant the scanner uses. Ask up-front instead of letting the
    // move fail with a cryptic snackbar.
    if (!await Permission.manageExternalStorage.isGranted) {
      final status = await Permission.manageExternalStorage.request();
      if (!mounted) return;
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Private folder needs "All files access": allow it, then '
              'long-press the video again',
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Move to Private folder?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          '"${track.title}" moves into the app\'s private folder - invisible '
          'to Gallery and file managers, visible here only after your PIN.\n\n'
          'Warning: uninstalling the app deletes hidden videos.',
          style:
              const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('Hide'),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await PrivateVault().hide(track.path);
                widget.player.removeHistoryEntry(track.path);
                lib.rescan();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Moved to Private folder')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  // v22: show WHY it failed (was a bare "Could not hide")
                  final why = e
                      .toString()
                      .replaceAll('FileSystemException: ', '')
                      .replaceAll('Exception: ', '');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('Could not hide: $why'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _onMenuChoice(String choice, VideoLibraryState lib) {
    switch (choice) {
      case 'stream':
        _openStreamDialog();
        break;
      case 'stats':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StatsScreen(player: widget.player)),
        );
        break;
      case 'rescan':
        _rescan(lib);
        break;
      case 'manual':
        UserManualSheet.show(context);
        break;
      case 'about':
        AboutSheet.show(context);
        break;
      case 'display':
        DisplaySettingsSheet.show(context, lib);
        break;
    }
  }

  /// User-triggered rescan (top-bar ⟳ button or the ⋮ menu entry) with
  /// feedback so it's obvious something is happening.
  void _rescan(VideoLibraryState lib) {
    if (lib.isScanning) return;
    lib.rescan();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rescanning device for videos…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Lets the user paste an http(s)/rtsp/rtmp URL and play it directly.
  Future<void> _openStreamDialog() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text(
          'Open stream URL',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'https:// or rtsp:// ...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: themeState.accent),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Play'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    const schemes = {'http', 'https', 'rtsp', 'rtmp', 'mms'};
    if (uri == null ||
        !schemes.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That does not look like a stream URL'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final title =
        uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
        ? Uri.decodeComponent(uri.pathSegments.last)
        : uri.host;
    await widget.player.playStream(url, title);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF22D3EE)],
          ).createShader(bounds),
          child: const Text(
            'Max Player',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        actions: [
          // Prominent rescan button (new videos don't appear otherwise).
          IconButton(
            tooltip: 'Rescan library',
            onPressed: lib.isScanning ? null : () => _rescan(lib),
            icon: lib.isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  )
                : const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryScreen(player: widget.player),
              ),
            ),
          ),
          // v21: Private folder (PIN). Rescan on return so hidden/unhidden
          // videos appear/disappear immediately.
          IconButton(
            tooltip: 'Private folder',
            icon: const Icon(Icons.lock_outline),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PrivateScreen(player: widget.player),
                ),
              );
              lib.rescan();
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            color: const Color(0xFF26262f),
            onSelected: (choice) => _onMenuChoice(choice, lib),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'stream',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link),
                  title: Text('Open stream URL'),
                ),
              ),
              PopupMenuItem(
                value: 'stats',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bar_chart),
                  title: Text('Statistics'),
                ),
              ),
              PopupMenuItem(
                value: 'rescan',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh),
                  title: Text('Rescan library'),
                ),
              ),
              PopupMenuItem(
                value: 'display',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune),
                  title: Text('Display settings'),
                ),
              ),
              PopupMenuItem(
                value: 'manual',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.menu_book_outlined),
                  title: Text('User manual'),
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('About'),
                ),
              ),
              // Footer: app version (not selectable).
              PopupMenuItem(
                value: 'version',
                enabled: false,
                height: 30,
                padding: EdgeInsets.zero,
                child: Center(
                  child: Text(
                    'Version $kAppVersion',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      // Mini player sits at the bottom while something is loaded.
      bottomNavigationBar: MiniPlayer(player: widget.player),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: lib.setSearchQuery,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search ${lib.allVideosCount} videos...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (lib.isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: lib.scanProgress.total > 0
                        ? lib.scanProgress.processed / lib.scanProgress.total
                        : null,
                    color: themeState.accent,
                    backgroundColor: Colors.white10,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scanning ${lib.scanProgress.processed}/${lib.scanProgress.total}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          // Soft crossfade between grid/list/empty states.
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _buildBody(lib),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(VideoLibraryState lib) {
    // Single evaluation - the getter filters+sorts, so compute once per build.
    final groups = lib.groups;
    final visibleCount = groups.fold<int>(0, (sum, g) => sum + g.videos.length);

    if (visibleCount == 0) {
      return _EmptyState(
        key: const ValueKey('empty'),
        isScanning: lib.isScanning,
        permissionDenied: lib.permissionDenied,
        favoritesOnly: lib.favoritesOnly,
        onGrantAccess: lib.scanAllStorage,
      );
    }

    // Keyed by view mode so grid <-> list crossfades through the
    // AnimatedSwitcher above.
    return CustomScrollView(
      key: ValueKey(lib.viewMode),
      slivers: [
        for (final group in groups) ...[
          if (lib.groupMode != GroupMode.none)
            SliverToBoxAdapter(
              child: _GroupHeader(
                title: group.title,
                count: group.videos.length,
              ),
            ),
          if (lib.viewMode == ViewMode.grid)
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final track = group.videos[i];
                  return GestureDetector(
                    // v21: long-press moves the video to the Private folder.
                    onLongPress: () => _offerHide(track, lib),
                    child: VideoTile(
                      track: track,
                      isFavorite: lib.isFavorite(track),
                      onTap: () => _playVideo(track),
                      onFavorite: () => lib.toggleFavorite(track),
                    ),
                  );
                }, childCount: group.videos.length),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final track = group.videos[i];
                  return GestureDetector(
                    // v21: long-press moves the video to the Private folder.
                    onLongPress: () => _offerHide(track, lib),
                    child: VideoListItem(
                      track: track,
                      isFavorite: lib.isFavorite(track),
                      onTap: () => _playVideo(track),
                      onFavorite: () => lib.toggleFavorite(track),
                    ),
                  );
                }, childCount: group.videos.length),
              ),
            ),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;

  const _GroupHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Text(
        '$title  ·  $count',
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isScanning;
  final bool permissionDenied;
  final bool favoritesOnly;
  final VoidCallback onGrantAccess;

  const _EmptyState({
    super.key,
    required this.isScanning,
    required this.permissionDenied,
    required this.favoritesOnly,
    required this.onGrantAccess,
  });

  @override
  Widget build(BuildContext context) {
    if (isScanning) {
      // Progress bar above already shows scan status - avoid a duplicate message.
      return const SizedBox.shrink();
    }

    // Library loaded, but the favourites filter hides everything.
    if (favoritesOnly && !permissionDenied) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 48, color: Colors.white24),
            SizedBox(height: 12),
            Text(
              'No favourites yet.\nTap the heart on any video to add it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: 48,
            color: Colors.white24,
          ),
          const SizedBox(height: 12),
          Text(
            permissionDenied
                ? 'Max Player needs storage access to find your videos'
                : 'No videos yet',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGrantAccess,
            icon: const Icon(Icons.folder_open),
            label: Text(permissionDenied ? 'Try again' : 'Scan device'),
          ),
        ],
      ),
    );
  }
}
EOF_MARKER_22

mkdir -p "$(dirname 'lib/screens/private_screen.dart')"
cat > 'lib/screens/private_screen.dart' <<'EOF_MARKER_23'
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/private_vault.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'player_screen.dart';

/// Private folder screen (v21): PIN gate -> list of hidden videos with
/// play / move-out actions. Files themselves live in the app's private
/// directory (see [PrivateVault]).
class PrivateScreen extends StatefulWidget {
  final MediaPlayerState player;

  const PrivateScreen({super.key, required this.player});

  @override
  State<PrivateScreen> createState() => _PrivateScreenState();
}

class _PrivateScreenState extends State<PrivateScreen> {
  final _vault = PrivateVault();
  final _pinCtrl = TextEditingController();
  final _pin2Ctrl = TextEditingController();

  bool? _hasPin; // null = still loading
  bool _unlocked = false;
  String? _error;
  bool _busy = false;
  List<File>? _videos;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final has = await _vault.hasPin();
    if (mounted) setState(() => _hasPin = has);
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pin2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4 || pin.length > 8) {
      setState(() => _error = 'PIN must be 4-8 digits');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_hasPin == false) {
        // First visit: create the PIN (enter twice to avoid typos).
        if (_pin2Ctrl.text.trim() != pin) {
          setState(() => _error = 'PINs do not match');
          return;
        }
        await _vault.setPin(pin);
        _hasPin = true;
        _unlocked = true;
      } else {
        if (await _vault.verifyPin(pin)) {
          _unlocked = true;
        } else {
          setState(() => _error = 'Wrong PIN');
          return;
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final vids = await _vault.listVideos();
    if (mounted) {
      setState(() => _videos = vids);
    }
  }

  Future<void> _play(File file) async {
    final files = _videos ?? const <File>[];
    final tracks = [
      for (final f in files)
        VideoTrack(
          id: f.path,
          title: f.path.split('/').last,
          path: f.path,
        ),
    ];
    final idx = tracks.indexWhere((t) => t.path == file.path);
    await widget.player.setPlaylistAndPlay(tracks, idx < 0 ? 0 : idx);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  Future<void> _unhide(File file) async {
    try {
      final moved = await _vault.unhide(file.path);
      widget.player.removeHistoryEntry(file.path);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved back to Movies: ${moved.path.split('/').last}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not move the video out')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Private folder'),
      ),
      body: _hasPin == null
          ? const Center(child: CircularProgressIndicator())
          : !_unlocked
              ? _pinGate(accent)
              : _videoList(accent),
    );
  }

  Widget _pinGate(Color accent) {
    final creating = _hasPin == false;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: accent),
            const SizedBox(height: 14),
            Text(
              creating ? 'Create a PIN' : 'Private folder',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              creating
                  ? 'Choose 4-8 digits. Hidden videos stay inside the app\'s '
                      'private folder - invisible to Gallery and file managers.'
                  : 'Enter your PIN to see hidden videos.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 18),
            _pinField(_pinCtrl, creating ? 'New PIN (4-8 digits)' : 'PIN'),
            if (creating) ...[
              const SizedBox(height: 10),
              _pinField(_pin2Ctrl, 'Repeat PIN'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: Icon(creating ? Icons.check : Icons.lock_open),
                label: Text(creating ? 'Create & open' : 'Unlock'),
              ),
            ),
            if (creating) ...[
              const SizedBox(height: 14),
              const Text(
                'Warning: uninstalling the app also deletes hidden videos. '
                'Move them out first.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.amberAccent, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pinField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: 8,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: Colors.white, letterSpacing: 4),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onSubmitted: (_) => _submit(),
    );
  }

  Widget _videoList(Color accent) {
    final vids = _videos;
    if (vids == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vids.isEmpty) {
      // v22 (user request): the how-to line belongs ON this screen.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 44, color: accent.withValues(alpha: 0.65)),
              const SizedBox(height: 12),
              const Text(
                'Hold on a video in the Library to add it to the Private folder',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 6),
              const Text(
                'Nothing is hidden yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: vids.length,
        itemBuilder: (context, i) {
          final f = vids[i];
          final name = f.path.split('/').last;
          final size = f.lengthSync();
          return ListTile(
            leading: Icon(Icons.lock, color: accent, size: 20),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              formatFileSize(size),
              style:
                  const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            onTap: () => _play(f),
            trailing: TextButton.icon(
              onPressed: () => _confirmUnhide(f),
              icon: const Icon(Icons.lock_open, size: 16),
              label: const Text('Move out'),
            ),
          );
        },
      ),
    );
  }

  void _confirmUnhide(File f) {
    final name = f.path.split('/').last;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Move out of Private?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '"$name" will move to the Movies folder and become visible to '
          'Gallery and other apps again.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _unhide(f);
            },
            child: const Text('Move out'),
          ),
        ],
      ),
    );
  }
}
EOF_MARKER_23

mkdir -p "$(dirname 'lib/utils/ai_subtitles.dart')"
cat > 'lib/utils/ai_subtitles.dart' <<'EOF_MARKER_24'
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import 'srt.dart';

/// True when a whisper segment is caption decoration rather than speech -
/// e.g. "♪", "♪ ♪", "[Music]", "(music playing)". Whisper emits these over
/// music-only stretches; dropping them keeps the .srt clean (v18).
///
/// Deliberately conservative: anything that might be real speech (even
/// speech ABOUT music, like "I love music") is kept - we only drop the
/// exact decoration phrases whisper hallucinates.
bool isMusicOnlyCaption(String text) {
  var t = text.toLowerCase().trim();
  if (t.isEmpty) return true;
  // Pure note decorations: "♪", "♪ ♫ ♪", ...
  t = t.replaceAll(RegExp(r'[♪♫𝄞𝄢]+'), ' ').trim();
  if (t.isEmpty) return true;
  // Reduce to letters only, then compare against known decorations.
  final core = t.replaceAll(RegExp(r'[^a-z]'), '');
  return _musicOnlyCores.contains(core);
}

/// Lowercase, letters-only forms of whisper's music/SFX-only captions.
const Set<String> _musicOnlyCores = {
  'music',
  'musicplaying',
  'playingmusic',
  'backgroundmusic',
  'upbeatmusic',
  'instrumentalmusic',
  'dramaticmusic',
  'intensemusic',
  'softmusic',
  'loudmusic',
  'slowmusic',
  'rockmusic',
  'popmusic',
  'classicalmusic',
  'sadmusic',
  'happymusic',
  'jazzmusic',
  'applause',
  'applauses',
  'clapping',
  'cheering',
  'laughter',
  'laughing',
  'crowdcheering',
  'silence',
};

/// Runs the offline AI subtitle flow end to end and shows a progress dialog:
///
///   download model once (~142 MB) -> extract audio -> whisper.cpp ->
///   write "<video>.maxai.srt" next to the video -> load it into the player
///
/// Everything after the one-time model download is 100% offline & free.
class AiSubtitleRunner {
  AiSubtitleRunner._();

  /// Persisted picker defaults (native settings store).
  static const String _kModelKey = 'ai.model';
  static const String _kLanguageKey = 'ai.language';
  static const String _kTranslateKey = 'ai.translate';

  /// Model choices: id -> (label, detail with size). v22 brought "tiny"
  /// back as the explicit speed pick (v18's removal stopped being right
  /// once "generation takes too much time" became the complaint) - plus
  /// the engine now uses all CPU cores, so every choice is faster.
  static const Map<String, (String, String)> modelChoices = {
    'tiny': ('Fast', '~75 MB · ~4x quicker, more mistakes'),
    'base': ('Balanced', '~142 MB · good for most videos'),
    'small': ('Best', '~466 MB · strongest on music & noise, slower'),
  };

  /// Unknown ids (from older/future app versions) fall back to "base".
  static String normalizeModelId(String? id) =>
      modelChoices.containsKey(id) ? id! : 'base';

  /// Language choices: whisper code -> label; 'auto' = detect.
  static const Map<String, String> languageChoices = {
    'auto': 'Auto-detect',
    'en': 'English',
    'hi': 'Hindi',
    'ur': 'Urdu',
    'ar': 'Arabic',
    'bn': 'Bengali',
    'ta': 'Tamil',
    'te': 'Telugu',
    'pa': 'Punjabi',
    'mr': 'Marathi',
    'gu': 'Gujarati',
    'kn': 'Kannada',
    'ml': 'Malayalam',
    'ne': 'Nepali',
    'es': 'Spanish',
    'fr': 'French',
  };

    /// Approximate download size label per model (for the progress dialog).
  static String modelSizeLabel(String model) => switch (model) {
        'tiny' => '~75 MB',
        'small' => '~466 MB',
        _ => '~142 MB',
      };

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

    // Ask for quality + language + output mode first (choices are remembered).
    final stored = await NativeBridge.loadSettings();
    if (!context.mounted) return;
    final options =
        await showDialog<({String model, String language, bool translate})>(
      context: context,
      builder: (_) => _AiOptionsDialog(
        initialModel: normalizeModelId(stored[_kModelKey]),
        initialLanguage: stored[_kLanguageKey] ?? 'auto',
        initialTranslate: stored[_kTranslateKey] == 'true',
      ),
    );
    if (options == null || !context.mounted) return;
    unawaited(NativeBridge.saveSetting(_kModelKey, options.model));
    unawaited(NativeBridge.saveSetting(_kLanguageKey, options.language));
    unawaited(NativeBridge.saveSetting(_kTranslateKey, '${options.translate}'));

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
      model: options.model,
      language: options.language,
      translate: options.translate,
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
        model: options.model,
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
    // Music-only decoration captions ("♪", "[Music]") are filtered out.
    final cues = [
      for (final s in segments!)
        if (!isMusicOnlyCaption(s.text)) SrtCue(s.startMs, s.endMs, s.text),
    ];
    if (cues.isEmpty) {
      _snack(context,
          'Only background music was detected - no subtitles to write');
      return;
    }
    final srtPath = _srtPathFor(track.path);
    try {
      await File(srtPath).writeAsString(buildSrt(cues));
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'Subtitles generated, but saving the file failed');
      }
      return;
    }
    if (!context.mounted) return;

    // Hand it to mpv so the subtitle picker lists it immediately, and let the
    // karaoke overlay / skip-intro chip pick up the fresh cues.
    final platform = player.player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.command(['sub-add', srtPath]);
      } catch (_) {}
    }
    await player.refreshAiCues(track.path);
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
  final String model;
  final VoidCallback onCancel;

  const _AiProgressDialog({
    required this.progress,
    required this.model,
    required this.onCancel,
  });

  static String _stageLabel(String stage, String model) {
    switch (stage) {
      case 'downloading':
        return 'Downloading the AI model (one time, '
            '${AiSubtitleRunner.modelSizeLabel(model)})…';
      case 'extracting':
        return 'Extracting audio from the video…';
      case 'transcribing':
        return 'Listening to the speech in this video…\n'
            '(silent parts are skipped automatically for speed)';
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
          // "transcribing" became determinate in v18: Kotlin reports real
          // progress as speech spans finish.
          final determinate = stage == 'downloading' ||
              stage == 'extracting' ||
              stage == 'transcribing';
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _stageLabel(stage, model),
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

/// "Generate with AI" options: which whisper model (speed vs accuracy) and
/// which language the video is spoken in (auto-detect or pinned). Choosing
/// the right language is the single biggest accuracy boost on short clips.
class _AiOptionsDialog extends StatefulWidget {
  final String initialModel;
  final String initialLanguage;
  final bool initialTranslate;

  const _AiOptionsDialog({
    required this.initialModel,
    required this.initialLanguage,
    required this.initialTranslate,
  });

  @override
  State<_AiOptionsDialog> createState() => _AiOptionsDialogState();
}

class _AiOptionsDialogState extends State<_AiOptionsDialog> {
  late String _model = widget.initialModel;
  late String _language = widget.initialLanguage;
  late bool _translate = widget.initialTranslate;

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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spoken language',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _dropdown<String>(
            value: _language,
            items: [
              for (final e in AiSubtitleRunner.languageChoices.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _language = v ?? 'auto'),
          ),
          const SizedBox(height: 16),
          const Text(
            'AI model (quality)',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _dropdown<String>(
            value: _model,
            items: [
              for (final e in AiSubtitleRunner.modelChoices.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text('${e.value.$1}  ·  ${e.value.$2}'),
                ),
            ],
            onChanged: (v) => setState(() => _model = v ?? 'base'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Output',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _modeChip(
                  label: 'Same language',
                  icon: Icons.record_voice_over_outlined,
                  selected: !_translate,
                  onTap: () => setState(() => _translate = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _modeChip(
                  label: '→ English',
                  icon: Icons.translate,
                  selected: _translate,
                  onTap: () => setState(() => _translate = true),
                ),
              ),
            ],
          ),
          if (_translate)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Foreign speech becomes ENGLISH subtitles (AI translate).',
                style: TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'Runs 100% offline after a one-time model download.',
            style: TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tip: "Fast" finishes roughly 4x sooner (more mistakes). For '
            'videos with loud background music, pin the spoken language '
            'above and choose "Best".',
            style: TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
              (model: _model, language: _language, translate: _translate)),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: Text(_translate ? 'Translate' : 'Generate'),
        ),
      ],
    );
  }

  Widget _modeChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? themeState.accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? themeState.accent : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16, color: selected ? themeState.accent : Colors.white54),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          dropdownColor: const Color(0xFF26262f),
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }
}
EOF_MARKER_24

mkdir -p "$(dirname 'lib/utils/srt.dart')"
cat > 'lib/utils/srt.dart' <<'EOF_MARKER_25'
import 'package:path/path.dart' as p;

/// Where the AI subtitle runner writes sidecar files for [videoPath]:
/// "<video-name>.maxai.srt" next to the video. Shared by the runner and
/// the DLNA caster (which offers this file to the TV).
String srtPathForVideo(String videoPath) {
  final dir = p.dirname(videoPath);
  final base = p.basenameWithoutExtension(videoPath);
  return p.join(dir, '$base.maxai.srt');
}

/// One SRT subtitle cue.
class SrtCue {
  final int startMs;
  final int endMs;
  final String text;
  const SrtCue(this.startMs, this.endMs, this.text);
}

/// Builds a standards-compliant .srt document from cues. Pure + unit-tested.
///
/// Rules applied:
///  - cues with empty text are dropped
///  - an end before/at the start is bumped to start + 1s (players reject
///    zero-length cues)
///  - cues are sorted by start time and numbered from 1
String buildSrt(List<SrtCue> cues) {
  final usable = cues.where((c) => c.text.trim().isNotEmpty).toList()
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  final out = StringBuffer();
  for (var i = 0; i < usable.length; i++) {
    final c = usable[i];
    final end = c.endMs > c.startMs ? c.endMs : c.startMs + 1000;
    out
      ..writeln(i + 1)
      ..writeln('${_srtTime(c.startMs)} --> ${_srtTime(end)}')
      ..writeln(c.text.trim())
      ..writeln();
  }
  return out.toString();
}

/// ms -> "HH:MM:SS,mmm" (SRT format uses a comma for millis).
String _srtTime(int ms) {
  if (ms < 0) ms = 0;
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  final milli = ms % 1000;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)},${milli.toString().padLeft(3, '0')}';
}


// ---------------------------------------------------------------------------
// v21 additions: parsing + smart-caption helpers
// ---------------------------------------------------------------------------

final RegExp _srtTimeLine = RegExp(
  r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})',
);

/// Parses an .srt document back into cues (inverse of [buildSrt]).
///
/// Deliberately tolerant: sequence numbers are ignored, blank lines end a
/// cue, and timing lines that do not match the classic "HH:MM:SS,mmm -->
/// HH:MM:SS,mmm" shape are skipped. Used by the karaoke overlay, the
/// skip-intro chip and transcript search.
List<SrtCue> parseSrt(String doc) {
  final cues = <SrtCue>[];
  final lines = doc.split(RegExp(r'\r?\n'));
  var i = 0;
  while (i < lines.length) {
    final m = _srtTimeLine.firstMatch(lines[i]);
    if (m == null) {
      i++;
      continue;
    }
    int ms(int h, int mm, int s, String frac) =>
        ((h * 60 + mm) * 60 + s) * 1000 +
        int.parse(frac.padRight(3, '0').substring(0, 3));
    final start = ms(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      m.group(4)!,
    );
    final end = ms(
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
      int.parse(m.group(7)!),
      m.group(8)!,
    );
    i++;
    final textLines = <String>[];
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      textLines.add(lines[i].trim());
      i++;
    }
    cues.add(SrtCue(start, end, textLines.join(' ')));
  }
  return cues;
}

/// Picks the best subtitle file sitting next to a video from a directory
/// listing ([fileNames] = basenames in the video's folder). These are the
/// files mpv auto-loads, so parsing the same pick lets karaoke + skip-intro
/// work on ordinary subtitled videos. Pure + unit-tested.
///
/// Ranking: exact "<name>.srt" first, then language-suffixed
/// "<name>.<xx>.srt" (alphabetical). The AI sidecar ("<name>.maxai.srt")
/// has its own pipeline and is always excluded.
List<String> sidecarSrtCandidates(List<String> fileNames, String videoPath) {
  final base = videoPath.replaceAll(r'\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  final stem = (dot > 0 ? base.substring(0, dot) : base).toLowerCase();
  String? exact;
  final langMatches = <String>[];
  for (final raw in fileNames) {
    final f = raw.toLowerCase();
    if (!f.endsWith('.srt')) continue;
    if (f == '$stem.srt') {
      exact ??= raw;
      continue;
    }
    if (f.endsWith('.maxai.srt')) continue;
    if (f.startsWith('$stem.')) langMatches.add(raw);
  }
  langMatches.sort();
  return [if (exact != null) exact, ...langMatches];
}

/// Whisper's music-only captions ("♪", "[Music]", "(upbeat music)") carry no
/// dialogue - karaoke, skip-intro and transcript search skip them.
bool isMusicOnlyText(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  if (t.contains('♪')) return true;
  final t2 = t.toLowerCase();
  final starts = t2.startsWith('[') || t2.startsWith('(') || t2.startsWith('*');
  if (!starts) return false;
  return t2.contains('music') ||
      t2.contains('applause') ||
      t2.contains('laughter') ||
      t2.contains('silence') ||
      t2.contains('noise');
}

/// Where the dialogue actually begins: start of the first spoken (non-music)
/// cue, minus a 1 s margin. Returns null when speech starts almost right
/// away (< 20 s - nothing to skip) or later than 10 minutes in (by then a
/// chip no longer makes sense).
Duration? computeSkipIntro(List<SrtCue> cues) {
  for (final c in cues) {
    if (isMusicOnlyText(c.text)) continue;
    if (c.startMs < 20000) return null; // talking right away
    if (c.startMs > 600000) return null; // 10+ min of silence: not an intro
    final target = (c.startMs - 1000).clamp(0, 1 << 31);
    return Duration(milliseconds: target);
  }
  return null;
}
EOF_MARKER_25

mkdir -p "$(dirname 'lib/utils/formatters.dart')"
cat > 'lib/utils/formatters.dart' <<'EOF_MARKER_26'
String formatFileSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final totalSeconds = d.inSeconds;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Compact watch-time totals for the stats screen ("2h 15m", "45m", "30s").
String formatWatchTime(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${m % 60}m';
}

/// Relative "watched" timestamps for the history list ("5m ago", "3h ago",
/// "12 Aug", ...).
String timeAgo(int msSinceEpoch) {
  if (msSinceEpoch <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(msSinceEpoch);
  final diff = DateTime.now().difference(dt);
  if (diff.isNegative || diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

const List<String> videoExtensions = [
  '.mp4',
  '.webm',
  '.mkv',
  '.avi',
  '.mov',
  '.wmv',
  '.flv',
  '.m4v',
  '.3gp',
  '.3gpp',
  '.ogv',
  '.ts',
  '.mts',
  '.m2ts',
  '.vob',
  '.mpg',
  '.mpeg',
  '.rmvb',
  '.divx',
  '.f4v',
];

bool isVideoFile(String name) {
  final lower = name.toLowerCase();
  return videoExtensions.any((ext) => lower.endsWith(ext));
}

/// hh:mm:ss / m:ss countdown text from a number of seconds (sleep timer
/// "22:41" under the player title). Pure + unit-tested.
String formatCountdown(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}
EOF_MARKER_26

mkdir -p "$(dirname 'lib/utils/privacy_policy.dart')"
cat > 'lib/utils/privacy_policy.dart' <<'EOF_MARKER_27'
import 'package:flutter/material.dart';

/// The app's privacy policy, bundled so it can be read offline (also what
/// Play reviewers see when they open the app during review).
///
/// Play Console still needs the public-URL copy: PRIVACY_POLICY.md at the
/// repo root. Keep the two in sync when either changes - the widget test
/// checks that both carry the same anchors (effective date, developer).
const String kPrivacyPolicyText =
    'MAX PLAYER - PRIVACY POLICY\n'
    'Effective date: 13 August 2026\n'
    'Developer: Hyper Tech Labs (Aryan Shah)\n'
    '\n'
    'THE SHORT VERSION\n'
    'Max Player is a local video player. It does not collect, store, '
    'transmit, or share any personal data. Everything the app does happens '
    'on your device.\n'
    '\n'
    'WHAT THE APP ACCESSES, AND WHY\n'
    '\n'
    '- Storage (videos / all files): to find and play the videos stored on '
    'your device, save screenshots to "Pictures/Max Player", and write AI '
    'subtitle files next to your videos. None of it ever leaves your '
    'device.\n'
    '\n'
    '- Internet: only for two things you trigger yourself - (1) the '
    'one-time download of the AI subtitle model (~142 MB from '
    'huggingface.co) and (2) playing stream URLs you paste or open. '
    'Nothing about you is sent anywhere.\n'
    '\n'
    '- Local network (Wi-Fi / multicast): only when you tap "Cast to TV" - '
    'discovering DLNA televisions on your own Wi-Fi and serving the video '
    'file from your phone to the television. Your Wi-Fi only; no external '
    'server is involved.\n'
    '\n'
    'WHAT THE APP DOES NOT DO\n'
    '\n'
    '- No analytics, no tracking, no advertising, and no third-party SDKs '
    'that collect data.\n'
    '- No accounts, no sign-in, no device identifiers collected.\n'
    '- No collection of your video library contents, file names, or watch '
    'history - all of it stays in the app\'s local storage on your '
    'device.\n'
    '- No crash reporting service. Crash reports are shown to you inside '
    'the app and are only shared if you copy and send them yourself.\n'
    '\n'
    'AI SUBTITLES\n'
    '\n'
    'Subtitle generation runs entirely on your device using the '
    'open-source whisper.cpp engine. Your audio never leaves your phone. '
    'The only network access is the one-time model file download from '
    'Hugging Face, which you trigger and can delete afterwards. Translating '
    'subtitles to English uses the same fully on-device engine - no audio '
    'or text is sent anywhere.\n'
    '\n'
    'PRIVATE FOLDER\n'
    '\n'
    'Videos you hide are moved into the app\'s own protected folder, which '
    'Android blocks other apps from reading, and are unlocked with a PIN '
    'you choose. They never leave your device and are never uploaded; the '
    'PIN is stored only as a cryptographic hash inside the app\'s '
    'settings. Uninstalling the app deletes the protected folder - move '
    'videos out first.\n'
    '\n'
    'PLAYBACK EXTRAS (KARAOKE, SKIP INTRO, THUMBNAILS)\n'
    '\n'
    'Karaoke highlighting and skip-intro detection only read subtitle '
    'files already on your device (AI-generated .srt files or the video\'s '
    'own subtitle file) while you play a video. Library thumbnails are '
    'decoded from your own videos into the app\'s cache folder, which the '
    'system or you can clear at any time. None of this data leaves the '
    'device or is shared anywhere.\n'
    '\n'
    'CHILDREN\n'
    '\n'
    'The app collects no data from anyone, including children.\n'
    '\n'
    'GOOGLE PLAY DATA SAFETY (SHORT ANSWERS)\n'
    '\n'
    '- Data collected: none.\n'
    '- Data shared with third parties: none.\n'
    '- Data sent off this device: none - AI subtitles, watch history, '
    'bookmarks and settings are all local-only.\n'
    '- Because no data leaves the device, "encryption in transit" and '
    '"account/data deletion requests" do not apply: nothing is transmitted '
    'and there is nothing on any server to delete.\n'
    '\n'
    'CHANGES\n'
    '\n'
    'Any change to this policy is published in PRIVACY_POLICY.md in the '
    'public repository with a new effective date.\n'
    '\n'
    'CONTACT\n'
    '\n'
    'Questions: open an issue on github.com/Aryanshahx/maxplayer';

/// Dialog showing [kPrivacyPolicyText]. Opened from the About sheet's
/// "Privacy policy" button.
void showPrivacyPolicyDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1b1b24),
      title: const Text(
        'Privacy policy',
        style: TextStyle(color: Colors.white, fontSize: 17),
      ),
      scrollable: true,
      content: const Text(
        kPrivacyPolicyText,
        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
EOF_MARKER_27

mkdir -p "$(dirname 'lib/main.dart')"
cat > 'lib/main.dart' <<'EOF_MARKER_28'
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:path/path.dart' as p;

import 'models/video_track.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'services/native_bridge.dart';
import 'state/media_player_state.dart';
import 'state/theme_state.dart';
import 'state/video_library_state.dart';
import 'utils/crash_log.dart';

// Global keys so a native "Open with" callback can navigate + snackbar from
// anywhere, without a BuildContext of its own.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> _messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  // Crash journal: rather than vanishing silently, record any Dart-side
  // error and offer it as a copyable report on the next app launch -
  // "app closed unexpectedly" becomes debuggable without a PC/logcat.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // Must be called before any media_kit Player is created.
    MediaKit.ensureInitialized();
    FlutterError.onError = (details) {
      CrashLog.record(
          'flutter', details.exceptionAsString(), details.stack);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashLog.record('async', error.toString(), stack);
      return true;
    };
    // Follow the phone's own rotation everywhere; the player's lock button
    // temporarily restricts it (and restores on exit).
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    runApp(const MaxPlayerApp());
  }, (error, stack) {
    CrashLog.record('zone', error.toString(), stack);
  });
}

class MaxPlayerApp extends StatefulWidget {
  const MaxPlayerApp({super.key});

  @override
  State<MaxPlayerApp> createState() => _MaxPlayerAppState();
}

class _MaxPlayerAppState extends State<MaxPlayerApp> {
  final library = VideoLibraryState();
  final player = MediaPlayerState();

  @override
  void initState() {
    super.initState();
    // App-wide accent color (persisted).
    themeState.load();
    // v22: the player's fallback for 4K/HDR thumbnails writes the cached
    // image itself - swap it into the already-built library list so the
    // tile updates without a rescan.
    player.onThumbnailCaptured =
        (videoPath, thumbPath) => library.setThumbnail(videoPath, thumbPath);
    // "Open with Max Player" from other apps: warm delivery ...
    NativeBridge.configureCallbacks(
      onOpenVideo: _openExternalVideo,
      onOpenVideoFailed: _externalOpenFailed,
    );
    // ... and the cold-start case (app launched BY a VIEW intent).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await NativeBridge.getInitialOpenVideo();
      final path = initial['path'];
      final failed = initial['failed'];
      if (path != null) {
        _openExternalVideo(path);
      } else if (failed != null) {
        _externalOpenFailed(failed);
      }
    });
  }

  /// Plays a video that another app sent us. Local files arrive as real
  /// filesystem paths (resolved natively); http/rtsp-style links are treated
  /// as network streams and handed to libmpv directly.
  Future<void> _openExternalVideo(String path) async {
    const streamSchemes = {'http', 'https', 'rtsp', 'rtmp', 'mms'};
    final uri = Uri.tryParse(path);
    if (uri != null && streamSchemes.contains(uri.scheme.toLowerCase())) {
      final title =
          uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
              ? Uri.decodeComponent(uri.pathSegments.last)
              : uri.host;
      await player.playStream(path, title);
      _navigateToPlayer();
      return;
    }
    try {
      await File(path).stat();
    } catch (_) {
      _externalOpenFailed(path);
      return;
    }
    final meta = await NativeBridge.fetchMetadata(path);
    final track = VideoTrack(
      id: path,
      title: p.basenameWithoutExtension(path),
      path: path,
      thumbnailPath: meta.thumbnailPath,
      duration: meta.duration,
      width: meta.width,
      height: meta.height,
    );
    await player.setPlaylistAndPlay([track], 0);
    _navigateToPlayer();
  }

  /// Jump straight into the player, replacing an already-open one.
  void _navigateToPlayer() {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
    nav.push(MaterialPageRoute(builder: (_) => PlayerScreen(player: player)));
  }

  void _externalOpenFailed(String target) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text("Can't open '${p.basename(target)}' - "
            'the file may be unavailable or storage access is off'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    player.dispose();
    library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app when the accent color changes.
    return AnimatedBuilder(
      animation: themeState,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
          title: 'Max Player',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0a0a0f),
            colorScheme: ColorScheme.fromSeed(
              seedColor: themeState.accent,
              brightness: Brightness.dark,
            ),
          ),
          home: LibraryScreen(library: library, player: player),
        );
      },
    );
  }
}
EOF_MARKER_28

mkdir -p "$(dirname 'PRIVACY_POLICY.md')"
cat > 'PRIVACY_POLICY.md' <<'EOF_MARKER_29'
# Privacy Policy — Max Player

**Effective date:** 13 August 2026
**Developer:** Hyper Tech Labs (Aryan Shah)
**Contact:** https://github.com/Aryanshahx/maxplayer (see the repository profile for contact details)

## The short version
Max Player is a local video player. **It does not collect, store, transmit, or share any personal data.** Everything the app does happens on your device.

## What the app accesses and why

| Permission / access | Why | Where the data goes |
|---|---|---|
| **Storage (videos / all files)** | To find and play the videos stored on your device, save screenshots to *Pictures/Max Player*, and write AI subtitle files next to your videos | Never leaves your device |
| **Internet** | Only for two things you trigger yourself: (1) the one-time download of the AI subtitle model (a ~142 MB file from huggingface.co), (2) playing stream URLs you paste/open | The model file comes in; nothing about you goes out |
| **Local network (multicast/Wi-Fi)** | Only when you tap "Cast to TV": discovering DLNA TVs on your own Wi-Fi and serving the video file from your phone to your TV | Your Wi-Fi only; no external server is involved |

## What the app does NOT do
- No analytics, no tracking, no advertising, no third-party SDKs that collect data
- No accounts, no sign-in, no device identifiers collected
- No collection of your video library content, file names, or history — all of it stays in the app's local storage on your device
- No crash reporting service (crash reports are shown **to you** inside the app, and are only shared if **you** copy and send them)

## AI subtitles
Subtitle generation runs entirely **on your device** using the open-source whisper.cpp engine. Your audio never leaves your phone. The only network access is the one-time model file download from Hugging Face (ggerganov/whisper.cpp), which you trigger and can delete afterwards. Translating subtitles to English uses the same fully on-device engine — no audio or text is sent anywhere.

## Private folder
Videos you hide are **moved into the app's own protected folder**, which Android blocks other apps from reading, and are unlocked with a PIN you choose. They never leave your device and are never uploaded. The PIN is stored only as a cryptographic hash inside the app's settings. Uninstalling the app deletes the protected folder — move videos out first.

## Playback extras (karaoke, skip intro, thumbnails)
Karaoke highlighting and skip-intro detection only *read* subtitle files already on your device (AI-generated .srt files or the video's own subtitle file) while you play a video. Library thumbnails are decoded from your own videos into the app's cache folder, which the system or you can clear at any time. None of this data leaves the device or is shared anywhere.

## Children's privacy
The app collects no data from anyone, including children.

## Google Play Data Safety (short answers)
This section matches the app's Play Console Data Safety form:
- **Data collected:** none — there is nothing to list per category
- **Data shared with third parties:** none
- **Data sent off the device:** none (AI subtitle generation, history, bookmarks and settings are all local-only)
- Because no data leaves the device, "encryption in transit" and "account/data deletion requests" are **not applicable** — nothing is transmitted and there is nothing on any server to delete.

## Changes
Any change to this policy will be committed to this file in the public repository, with the new effective date above.

## Contact
Questions: open an issue on the GitHub repository above.
EOF_MARKER_29

mkdir -p "$(dirname 'pubspec.yaml')"
cat > 'pubspec.yaml' <<'EOF_MARKER_30'
name: maxplayer
description: "Max Player - a local video library & player."
publish_to: 'none'
version: 1.0.0+21

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
EOF_MARKER_30

mkdir -p "$(dirname 'test/widget_test.dart')"
cat > 'test/widget_test.dart' <<'EOF_MARKER_31'
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/app_info.dart';
import 'package:maxplayer/cast/cast_support.dart';
import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/state/media_player_state.dart';
import 'package:maxplayer/state/player_settings.dart';
import 'package:maxplayer/state/theme_state.dart';
import 'package:maxplayer/state/video_library_state.dart';
import 'package:maxplayer/utils/ai_subtitles.dart';
import 'package:maxplayer/utils/formatters.dart';
import 'package:maxplayer/utils/privacy_policy.dart';
import 'package:maxplayer/utils/sha256.dart';
import 'package:maxplayer/utils/srt.dart';
import 'package:maxplayer/widgets/karaoke_subtitle.dart';
import 'package:maxplayer/widgets/about_sheet.dart';
import 'package:maxplayer/widgets/gesture_illustrations.dart';
import 'package:maxplayer/widgets/user_manual_sheet.dart';

// Pure unit tests - no platform channels involved. (NativeBridge calls in
// VideoLibraryState are guarded and return defaults when no channel exists,
// so these tests run fine in the Dart VM.)
//
// A full-app pump test was removed: it constructed the real media_kit Player
// and fired a storage-permission request, both of which need a device.
// Re-add a widget test once the states can be injected/faked.

VideoTrack _track(
  String name, {
  Duration? duration,
  int? size,
  int? modified,
  String dir = '/storage/emulated/0/Movies',
}) {
  final path = '$dir/$name.mp4';
  return VideoTrack(
    id: path,
    title: name,
    path: path,
    duration: duration,
    sizeBytes: size,
    lastModifiedMs: modified,
  );
}

VideoLibraryState _libraryWith(List<VideoTrack> videos) {
  final lib = VideoLibraryState();
  lib.debugSetVideos(videos);
  addTearDown(lib.dispose);
  return lib;
}

void main() {
  group('formatters', () {
    test('formats file sizes', () {
      expect(formatFileSize(null), '');
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(2048), '2.0 KB');
      expect(formatFileSize(5 * 1024 * 1024), '5.0 MB');
      expect(formatFileSize(3 * 1024 * 1024 * 1024), '3.00 GB');
    });

    test('formats durations', () {
      expect(formatDuration(null), '--:--');
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });

    test('detects video extensions case-insensitively', () {
      expect(isVideoFile('clip.MKV'), isTrue);
      expect(isVideoFile('movie.mp4'), isTrue);
      expect(isVideoFile('notes.txt'), isFalse);
    });

    test('covers the extension set advertised in the manifest', () {
      // Keep in sync with the pathPatterns in AndroidManifest.xml.
      for (final ext in [
        'mp4', 'webm', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'm4v', '3gp',
        '3gpp', 'ogv', 'ts', 'mts', 'm2ts', 'vob', 'mpg', 'mpeg', 'rmvb',
        'divx', 'f4v',
      ]) {
        expect(isVideoFile('movie.$ext'), isTrue,
            reason: '.$ext must scan into the library');
        expect(isVideoFile('movie.${ext.toUpperCase()}'), isTrue);
      }
    });

    test('timeAgo buckets', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(timeAgo(now), 'Just now');
      expect(
          timeAgo(now - const Duration(minutes: 5).inMilliseconds), '5m ago');
      expect(timeAgo(now - const Duration(hours: 3).inMilliseconds), '3h ago');
      expect(timeAgo(now - const Duration(days: 2).inMilliseconds), '2d ago');
      expect(timeAgo(0), '');
    });
  });

  group('quality label', () {
    String? q(int? w, int? h) => VideoTrack(
        id: 'x', title: 'x', path: '/x.mp4', width: w, height: h).qualityLabel;

    test('maps the SHORTER side to a resolution badge', () {
      expect(q(1920, 1080), '1080p');
      expect(q(1080, 1920), '1080p'); // portrait video
      expect(q(3840, 2160), '4K');
      expect(q(2560, 1440), '2K');
      expect(q(1280, 720), '720p');
      expect(q(640, 480), '480p');
      expect(q(320, 240), 'SD');
    });

    test('null when dimensions unknown', () {
      expect(q(null, null), isNull);
      expect(q(0, 0), isNull);
    });
  });

  group('equalizer filter builder', () {
    test('all-zero gains produce an empty filter (clears af)', () {
      expect(MediaPlayerState.buildEqualizerFilter([0, 0, 0, 0, 0]), '');
    });

    test('skips flat bands and formats the rest as lavfi', () {
      final f =
          MediaPlayerState.buildEqualizerFilter([6, 0, -2, 0, 3.5]);
      expect(f,
          'lavfi=[equalizer=f=60:t=q:w=1.0:g=6.0,equalizer=f=910:t=q:w=1.0:g=-2.0,equalizer=f=14000:t=q:w=1.0:g=3.5]');
    });
  });

  group('watch stats', () {
    test('stats key is a sortable YYYYMMDD bucket', () {
      expect(MediaPlayerState.statsKeyFor(DateTime(2026, 8, 11)),
          'stats.20260811');
      expect(MediaPlayerState.statsKeyFor(DateTime(2026, 1, 5)),
          'stats.20260105');
    });

    test('formatWatchTime', () {
      expect(formatWatchTime(30), '30s');
      expect(formatWatchTime(45 * 60), '45m');
      expect(formatWatchTime(2 * 3600 + 15 * 60), '2h 15m');
    });
  });

  group('library sorting', () {
    final videos = [
      _track('banana', size: 300, modified: 100, duration: const Duration(minutes: 3)),
      _track('apple', size: 100, modified: 300, duration: const Duration(minutes: 1)),
      _track('cherry', size: 200, modified: 200),
    ];

    test('name A->Z and Z->A', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.name, true);
      expect(lib.videos.map((v) => v.title), ['apple', 'banana', 'cherry']);
      lib.setSort(SortMode.name, false);
      expect(lib.videos.map((v) => v.title), ['cherry', 'banana', 'apple']);
    });

    test('length shortest first, unknown duration sinks to the end', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.length, true);
      expect(lib.videos.map((v) => v.title), ['apple', 'banana', 'cherry']);
      // longest first, but the unknown one still ends up last
      lib.setSort(SortMode.length, false);
      expect(lib.videos.map((v) => v.title), ['banana', 'apple', 'cherry']);
    });

    test('recently added: newest first', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.date, false);
      expect(lib.videos.map((v) => v.title), ['apple', 'cherry', 'banana']);
    });

    test('size smallest first', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.size, true);
      expect(lib.videos.map((v) => v.title), ['apple', 'cherry', 'banana']);
    });
  });

  group('library filtering & favourites', () {
    final videos = [
      _track('cat video'),
      _track('dog video'),
      _track('cat fails'),
    ];

    test('search filters by title', () {
      final lib = _libraryWith(videos);
      lib.setSearchQuery('cat');
      expect(lib.videos.length, 2);
      lib.setSearchQuery('dog');
      expect(lib.videos.map((v) => v.title), ['dog video']);
    });

    test('favourites-only shows only hearted videos', () {
      final lib = _libraryWith(videos);
      lib.toggleFavorite(videos[1]);
      expect(lib.isFavorite(videos[1]), isTrue);
      lib.setFavoritesOnly(true);
      expect(lib.videos.map((v) => v.title), ['dog video']);
      lib.toggleFavorite(videos[1]);
      expect(lib.videos, isEmpty);
    });
  });

  group('grouping', () {
    test('group by name buckets titles by first letter', () {
      final lib = _libraryWith([
        _track('Banana'),
        _track('apple'),
        _track('avocado'),
        _track('123 intro'),
      ]);
      lib.setGroupMode(GroupMode.name);
      final groups = lib.groups;
      expect(groups.map((g) => g.title), ['1', 'A', 'B']);
      expect(groups[1].videos.length, 2); // apple + avocado under A
    });

    test('group by folder uses the parent directory name', () {
      final lib = _libraryWith([
        _track('one', dir: '/storage/emulated/0/Movies'),
        _track('two', dir: '/storage/emulated/0/Download'),
      ]);
      lib.setGroupMode(GroupMode.folder);
      expect(lib.groups.map((g) => g.title), ['Download', 'Movies']);
    });

    test('no grouping yields a single unnamed group', () {
      final lib = _libraryWith([_track('x')]);
      lib.setGroupMode(GroupMode.none);
      expect(lib.groups.length, 1);
      expect(lib.groups.single.title, '');
    });
  });

  group('SRT builder (AI subtitles)', () {
    test('formats numbered cues with HH:MM:SS,mmm times', () {
      final srt = buildSrt(const [
        SrtCue(1200, 3400, 'Hello world'),
        SrtCue(3605000, 3607000, 'second line'),
      ]);
      expect(
        srt,
        '1\n00:00:01,200 --> 00:00:03,400\nHello world\n\n'
        '2\n01:00:05,000 --> 01:00:07,000\nsecond line\n\n',
      );
    });

    test('drops empty cues and bumps zero-length ends', () {
      final srt = buildSrt(const [
        SrtCue(500, 500, 'same'),
        SrtCue(100, 900, '   '),
      ]);
      expect(srt, '1\n00:00:00,500 --> 00:00:01,500\nsame\n\n');
    });

    test('sorts cues by start time', () {
      final srt = buildSrt(const [
        SrtCue(5000, 6000, 'later'),
        SrtCue(1000, 2000, 'first'),
      ]);
      expect(srt.startsWith('1\n00:00:01,000'), isTrue);
    });
  });

  group('player settings (v12 defaults)', () {
    test('new v12 toggles all start ON and persist round-trip', () {
      const s = PlayerSettings();
      expect(s.horizontalSeek, isTrue);
      expect(s.castButton, isTrue);
      expect(s.screenshotButton, isTrue);
      expect(s.lockButton, isTrue);
      // copyWith actually carries them
      final t = s.copyWith(horizontalSeek: false, castButton: false);
      expect(t.horizontalSeek, isFalse);
      expect(t.castButton, isFalse);
      expect(t.screenshotButton, isTrue);
      expect(t.lockButton, isTrue);
    });

    test('load from empty store yields all v12 defaults', () async {
      final s = await PlayerSettings.load();
      expect(s.horizontalSeek, isTrue);
      expect(s.castButton, isTrue);
      expect(s.screenshotButton, isTrue);
      expect(s.lockButton, isTrue);
    });
  });

  group('DLNA cast helpers', () {
    test('SSDP header lookup is case-insensitive and trims', () {
      const dg = 'HTTP/1.1 200 OK\r\n'
          'CACHE-CONTROL: max-age=1800\r\n'
          'LOCATION: http://192.168.1.10:8080/dd.xml\r\n'
          'location: http://other/x.xml\r\n' // duplicate -> first wins
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n';
      expect(ssdpHeader(dg, 'location'), 'http://192.168.1.10:8080/dd.xml');
      expect(ssdpHeader(dg, 'ST'),
          'urn:schemas-upnp-org:device:MediaRenderer:1');
      expect(ssdpHeader(dg, 'server'), isNull);
    });

    test('M-SEARCH request is well formed', () {
      final m = buildMSearchRequest('ssdp:all');
      expect(m.startsWith('M-SEARCH * HTTP/1.1\r\n'), isTrue);
      expect(m, contains('ST: ssdp:all\r\n'));
      expect(m.endsWith('\r\n\r\n'), isTrue);
    });

    test('device description: finds AVTransport and resolves relative URL',
        () {
      const xml = '''
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>Living Room TV</friendlyName>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/rc/control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/avt/control</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';
      final d = parseDeviceDescription(xml, 'http://192.168.1.10:9000/dd.xml');
      expect(d, isNotNull);
      expect(d!.name, 'Living Room TV');
      expect(d.controlUrl, 'http://192.168.1.10:9000/avt/control');
    });

    test('device description: rejects devices without AVTransport', () {
      const xml = '<root><device><friendlyName>Router</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>'
          '<controlURL>/wan/control</controlURL>'
          '</service></serviceList></device></root>';
      expect(parseDeviceDescription(xml, 'http://10.0.0.1/d.xml'), isNull);
    });

    test('absolute controlURL kept as-is; xml entities unescaped in name',
        () {
      const xml = '<root><device><friendlyName>A &amp; B TV</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>'
          '<controlURL>http://192.168.1.5:81/avt</controlURL>'
          '</service></serviceList></device></root>';
      final d = parseDeviceDescription(xml, 'http://192.168.1.5:9999/dd');
      expect(d!.name, 'A & B TV');
      expect(d.controlUrl, 'http://192.168.1.5:81/avt');
    });

    test('SOAP envelope carries InstanceID first and escapes args', () {
      final env = buildSoapEnvelope('Play', const [
        MapEntry('Speed', '1'),
      ]);
      expect(env, contains('<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'));
      expect(env.indexOf('<InstanceID>0</InstanceID>'),
          lessThan(env.indexOf('<Speed>1</Speed>')));
      final esc = buildSoapEnvelope('X', const [
        MapEntry('V', 'a & <b> "q"'),
      ]);
      expect(esc, contains('a &amp; &lt;b&gt; &quot;q&quot;'));
    });

    test('soapTag digs values out of responses', () {
      const body = '<s:Envelope><s:Body><u:GetPositionInfoResponse>'
          '<Track>1</Track><RelTime>0:06:12</RelTime>'
          '</u:GetPositionInfoResponse></s:Body></s:Envelope>';
      expect(soapTag(body, 'RelTime'), '0:06:12');
      expect(soapTag(body, 'Track'), '1');
      expect(soapTag(body, 'AbsTime'), isNull);
    });

    test('DIDL metadata carries title, res and optional subtitle', () {
      final didl = buildDidlMetadata(
        title: 'My Video <1080p>',
        videoUrl: 'http://p:1/video.mp4',
        mime: 'video/mp4',
        subsUrl: 'http://p:1/subs.srt',
      );
      expect(didl, contains('<dc:title>My Video &lt;1080p&gt;</dc:title>'));
      expect(didl, contains('protocolInfo="http-get:*:video/mp4:*"'));
      expect(didl, contains('<sec:CaptionInfoEx'));
      final noSubs = buildDidlMetadata(
          title: 't', videoUrl: 'http://p/v.mp4', mime: 'video/mp4');
      expect(noSubs.contains('CaptionInfoEx'), isFalse);
    });

    test('mime map covers the containers we scan for', () {
      expect(mimeForExtension('/x/a.mkv'), 'video/x-matroska');
      expect(mimeForExtension('/x/a.MP4'), 'video/mp4');
      expect(mimeForExtension('/x/a.webm'), 'video/webm');
      expect(mimeForExtension('/x/a.avi'), 'video/x-msvideo');
      expect(mimeForExtension('/x/a.mov'), 'video/quicktime');
      expect(mimeForExtension('/x/a.wmv'), 'video/x-ms-wmv');
      expect(mimeForExtension('/x/a.ts'), 'video/mp2t');
      expect(mimeForExtension('http://s/v.mkv?token=1'), 'video/x-matroska');
      expect(mimeForExtension('/x/a.unknown'), 'video/mp4'); // safe default
    });

    test('DLNA rel-time format/parse round-trips', () {
      expect(formatRelTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
      expect(formatRelTime(Duration.zero), '0:00:00');
      expect(parseRelTime('0:06:12'), const Duration(minutes: 6, seconds: 12));
      expect(parseRelTime('1:02:03.500'),
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500));
      expect(parseRelTime('NOT_IMPLEMENTED'), isNull);
      expect(parseRelTime(null), isNull);
      expect(parseRelTime('garbage'), isNull);
    });
  });

  group('app version', () {
    test('kAppVersion matches the pubspec version name', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version:\s*([0-9][0-9.]*)\+', multiLine: true)
          .firstMatch(pub);
      expect(m, isNotNull, reason: 'pubspec.yaml must declare version: x.y.z+N');
      expect(m!.group(1), kAppVersion,
          reason: 'Keep kAppVersion in lib/app_info.dart in sync');
    });
  });

  group('AI subtitle options & caption filter (v18)', () {
    // v22: "tiny" returned as the explicit Fast pick (speed complaint).
    test('the fast/tiny model is back as an explicit pick; defaults sane',
        () {
      expect(AiSubtitleRunner.modelChoices.containsKey('tiny'), isTrue);
      expect(AiSubtitleRunner.modelChoices.keys,
          containsAll(<String>['tiny', 'base', 'small']));
      expect(AiSubtitleRunner.normalizeModelId(null), 'base');
      expect(AiSubtitleRunner.normalizeModelId('tiny'), 'tiny');
      expect(AiSubtitleRunner.normalizeModelId('small'), 'small');
      expect(AiSubtitleRunner.normalizeModelId('nonsense'), 'base');
      expect(AiSubtitleRunner.modelSizeLabel('tiny'), '~75 MB');
      expect(AiSubtitleRunner.modelSizeLabel('base'), '~142 MB');
    });

    test('music-only decoration captions are dropped, speech is kept', () {
      for (final t in [
        '♪',
        '♪ ♪',
        '♪♫♪',
        '[Music]',
        '(MUSIC)',
        'music',
        '( music playing )',
        '♪ Music ♪',
        '[Applause]',
        '(laughter)',
      ]) {
        expect(isMusicOnlyCaption(t), isTrue, reason: '"$t" must be dropped');
      }
      for (final t in [
        'Hello world',
        'I love music',
        'music is life',
        'the background music in this scene',
      ]) {
        expect(isMusicOnlyCaption(t), isFalse, reason: '"$t" must be kept');
      }
    });
  });

  group('privacy policy', () {
    test('in-app text carries the same anchors as PRIVACY_POLICY.md', () {
      final md = File('PRIVACY_POLICY.md').readAsStringSync();
      for (final anchor in [
        '13 August 2026',
        'Hyper Tech Labs',
        'github.com/Aryanshahx/maxplayer',
      ]) {
        expect(md, contains(anchor));
        expect(kPrivacyPolicyText, contains(anchor),
            reason: 'keep lib/utils/privacy_policy.dart in sync with '
                'PRIVACY_POLICY.md');
      }
    });
  });

  group('manual & about sheets', () {
    /// The sheets are lazy ListViews - give the test a huge viewport so
    /// every section builds, not just the first screenful.
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('every gesture illustration paints without errors',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final kind in GestureKind.values)
                    SizedBox(
                      width: 320,
                      child: GestureIllustration(kind: kind),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
          find.byType(GestureIllustration), findsNWidgets(GestureKind.values.length));
      expect(tester.takeException(), isNull);
    });

    testWidgets('user manual renders all sections', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: UserManualSheet())),
      );
      expect(find.text('User manual'), findsOneWidget);
      expect(find.text('GESTURE CONTROLS'), findsOneWidget);
      expect(find.text('Max Player v$kAppVersion  ·  Hyper Tech Labs'),
          findsOneWidget);
      expect(find.byType(GestureIllustration),
          findsNWidgets(GestureKind.values.length));
      expect(tester.takeException(), isNull);
    });

    testWidgets('about sheet renders brand text and version', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AboutSheet())),
      );
      expect(find.text('Max Player'), findsOneWidget);
      expect(find.text('by Hyper Tech Labs'), findsOneWidget);
      expect(find.text('Version $kAppVersion'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('about sheet bundles the privacy policy offline',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AboutSheet())),
      );
      await tester.tap(find.text('Privacy policy'));
      await tester.pumpAndSettle();
      expect(find.textContaining('does not collect, store, transmit'),
          findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.textContaining('does not collect, store, transmit'),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // v21: SRT parsing (karaoke / skip-intro / transcript groundwork)
  // -------------------------------------------------------------------------
  group('v21 srt parsing', () {
    test('parseSrt round-trips buildSrt output', () {
      final cues = [
        const SrtCue(0, 1500, 'Hello world'),
        const SrtCue(61000, 63500, 'Second caption line'),
      ];
      final parsed = parseSrt(buildSrt(cues));
      expect(parsed.length, 2);
      expect(parsed[0].startMs, 0);
      expect(parsed[0].endMs, 1500);
      expect(parsed[0].text, 'Hello world');
      expect(parsed[1].startMs, 61000);
      expect(parsed[1].text, 'Second caption line');
    });

    test('parseSrt tolerates missing indices and dot-millis', () {
      final parsed = parseSrt(
          '1\n00:00:01.000 --> 00:00:02.500\none two\n\n00:00:03,000 --> 00:00:04,000\nthree\n');
      expect(parsed.length, 2);
      expect(parsed[0].startMs, 1000);
      expect(parsed[0].endMs, 2500);
      expect(parsed[0].text, 'one two');
      expect(parsed[1].startMs, 3000);
    });

    test('computeSkipIntro finds late dialogue start', () {
      expect(
        computeSkipIntro([
          const SrtCue(0, 3000, '♪ opening theme ♪'),
          const SrtCue(92000, 94000, 'Are you ready?'),
        ]),
        const Duration(milliseconds: 91000),
      );
      // Speech right away -> nothing to skip.
      expect(computeSkipIntro([const SrtCue(3000, 5000, 'Hello')]), isNull);
      // First speech after 10 minutes -> not an intro.
      expect(
          computeSkipIntro([const SrtCue(700000, 701000, 'Too late')]), isNull);
      expect(computeSkipIntro(const []), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // v21: SHA-256 for the Private-folder PIN (dependency-free implementation)
  // -------------------------------------------------------------------------
  group('v21 sha256', () {
    test('standard test vectors', () {
      expect(sha256Hex(''),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sha256Hex('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(sha256Hex('1234'),
          '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4');
    });
  });

  // -------------------------------------------------------------------------
  // v21: karaoke timing helpers
  // -------------------------------------------------------------------------
  group('v21 karaoke timing', () {
    test('karaokeWordIndex walks words proportionally to characters', () {
      const cue = SrtCue(0, 2000, 'aa b');
      expect(karaokeWordIndex(cue, 0), 0);
      expect(karaokeWordIndex(cue, 500), 0);
      expect(karaokeWordIndex(cue, 1900), 1);
      expect(karaokeWordIndex(cue, 2000), 1);
    });

    test('karaokeActiveCue skips music-only cues and quiet gaps', () {
      final cues = [
        const SrtCue(0, 1000, '♪ music ♪'),
        const SrtCue(2000, 3000, 'Hello there'),
      ];
      expect(karaokeActiveCue(cues, 500), isNull);
      expect(karaokeActiveCue(cues, 2500)?.text, 'Hello there');
      expect(karaokeActiveCue(cues, 3400)?.text, 'Hello there'); // grace
      expect(karaokeActiveCue(cues, 5000), isNull);
    });

    // v22: live mpv line -> AI sidecar -> same-name .srt fallback order.
    test('karaokeCueAt picks live, then AI cues, then sidecar cues', () {
      const live = SrtCue(9000, 11000, 'live line');
      final ai = [const SrtCue(9000, 11000, 'ai line')];
      final side = [const SrtCue(9000, 11000, 'sidecar line')];
      expect(karaokeCueAt(live, ai, side, 10000)?.text, 'live line');
      expect(karaokeCueAt(null, ai, side, 10000)?.text, 'ai line');
      expect(karaokeCueAt(null, null, side, 10000)?.text, 'sidecar line');
      expect(karaokeCueAt(null, null, null, 10000), isNull);
      // Stale live cue (past its 600 ms grace) falls through to files.
      final ai2 = [const SrtCue(45000, 55000, 'ai line later')];
      expect(karaokeCueAt(live, ai2, side, 50000)?.text, 'ai line later');
      // Everything expired -> nothing shown.
      expect(karaokeCueAt(live, ai, side, 50000), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // v22: same-name sidecar picking (karaoke / skip-intro on the video's
  // own subtitle file)
  // -------------------------------------------------------------------------
  group('v22 sidecar .srt picking', () {
    test('exact same-name match wins over language variants', () {
      final names = ['movie.eng.srt', 'Movie.SRT', 'movie.maxai.srt', 'x.srt'];
      expect(
        sidecarSrtCandidates(names, '/sdcard/Movies/Movie.mp4'),
        ['Movie.SRT', 'movie.eng.srt'],
      );
    });
    test('AI sidecar is never picked as a plain sidecar', () {
      final names = ['movie.maxai.srt'];
      expect(sidecarSrtCandidates(names, '/a/movie.mkv'), isEmpty);
    });
    test('language variants are sorted and kept in original case', () {
      final names = ['movie.hi.srt', 'movie.en.srt'];
      expect(sidecarSrtCandidates(names, 'movie.mkv'),
          ['movie.en.srt', 'movie.hi.srt']);
    });
    test('unrelated files and non-srt are ignored', () {
      final names = ['movie.srt.txt', 'other.srt', 'movie.txt', '.srt'];
      expect(sidecarSrtCandidates(names, '/m/movie.mp4'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // v22: sleep-timer countdown + white-accent contrast
  // -------------------------------------------------------------------------
  group('v22 sleep countdown + accent contrast', () {
    test('formatCountdown renders m:ss and h:mm:ss', () {
      expect(formatCountdown(0), '0:00');
      expect(formatCountdown(9), '0:09');
      expect(formatCountdown(61), '1:01');
      expect(formatCountdown(599), '9:59');
      expect(formatCountdown(3600), '1:00:00');
      expect(formatCountdown(-5), '0:00'); // clamps negatives
    });

    test('contrastColorFor: dark ink on light accents, white on dark', () {
      const darkInk = Color(0xFF16161f);
      expect(contrastColorFor(const Color(0xFFFFFFFF)), darkInk);
      expect(contrastColorFor(const Color(0xFF22D3EE)), darkInk); // cyan
      expect(contrastColorFor(const Color(0xFFA855F7)), Colors.white);
      expect(contrastColorFor(const Color(0xFF60A5FA)), Colors.white);
    });

    test('white is a selectable accent swatch', () {
      expect(
        ThemeState.swatches.any((c) => c.toARGB32() == 0xFFFFFFFF),
        isTrue,
      );
    });
  });
}
EOF_MARKER_31

echo "==> Files written. Quick sanity check..."
S=0
grep -q "v23: whole player rides the theme colour" lib/widgets/player_controls_overlay.dart && echo "  OK theme: overlay" || { echo "  FAIL overlay"; S=1; }
grep -q "themeState.accent" lib/widgets/progress_bar.dart && echo "  OK theme: progress bar" || { echo "  FAIL progress"; S=1; }
grep -q "themeState.accent" lib/widgets/cast_sheet.dart && echo "  OK theme: cast sheet" || { echo "  FAIL cast"; S=1; }
grep -q "themeState.accent" lib/widgets/track_selection_sheet.dart && echo "  OK theme: track sheet" || { echo "  FAIL tracks"; S=1; }
grep -q "themeState.accent" lib/screens/player_screen.dart && echo "  OK theme: player screen" || { echo "  FAIL player"; S=1; }
grep -q "0xFFFFFFFF" lib/state/theme_state.dart && echo "  OK white accent" || { echo "  FAIL white"; S=1; }
grep -q "sidecarSrtCandidates" lib/utils/srt.dart && echo "  OK sidecar srt (karaoke+skip-intro)" || { echo "  FAIL srt"; S=1; }
grep -q "karaokeCueAt" lib/widgets/karaoke_subtitle.dart && echo "  OK karaoke any-subtitle" || { echo "  FAIL karaoke"; S=1; }
grep -q "_applySubVisibility" lib/state/media_player_state.dart && echo "  OK karaoke-only display" || { echo "  FAIL visibility"; S=1; }
grep -q "sleepTimerCountdown" lib/state/media_player_state.dart && echo "  OK sleep countdown" || { echo "  FAIL sleep"; S=1; }
grep -q "_captureThumbWithMpv" lib/state/media_player_state.dart && echo "  OK 4K thumb fallback" || { echo "  FAIL thumbs"; S=1; }
grep -q "threads = Runtime.getRuntime()" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  OK AI all-core speed" || { echo "  FAIL AI threads"; S=1; }
grep -q "ggml-tiny.bin" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  OK AI Fast model" || { echo "  FAIL tiny"; S=1; }
grep -q "2.5, 3.0" lib/widgets/player_controls_overlay.dart && echo "  OK 3x speed" || { echo "  FAIL 3x"; S=1; }
grep -q "Hold on a video in the Library" lib/screens/private_screen.dart && echo "  OK private hint text" || { echo "  FAIL private text"; S=1; }
grep -q "_applyAudioFilters" lib/state/media_player_state.dart && echo "  OK leveling fix" || { echo "  FAIL leveling"; S=1; }
grep -q "1.0.0+21" pubspec.yaml && echo "  OK pubspec (1.0.0+21)" || { echo "  FAIL pubspec"; S=1; }
if [ "$S" -ne 0 ]; then echo "SANITY CHECK FAILED - do not push; report the FAIL lines."; exit 1; fi

if command -v flutter >/dev/null 2>&1; then
  echo "==> flutter analyze (should print: No issues found!)"
  set +e; flutter analyze; A=$?; set -e
else
  echo "==> flutter not on PATH - Codemagic will build it"
fi

echo ''
echo '=============================================================='
echo ' v23 applied.  Push it:'
echo '   cd ~/IdeaProjects/maxplayer && git add -A'
echo '   git commit -m "v23: theme colour across whole player (+white), karaoke-only display, sleep countdown, v22 fixes"'
echo '   git push'
echo ''
echo 'THEN ON YOUR PHONE - TEST AND REPORT EACH LINE:'
echo '  1. Pick WHITE (or any colour) in library Settings -> Display;'
echo '     open the player: title, icons, menus, settings, seek times'
echo '     all follow the colour; 2x badge stays readable on white.'
echo '  2. ... menu -> Karaoke subtitles ON: only the karaoke line'
echo '     shows (normal subtitles hidden), words light up - works'
echo '     with embedded subs, own .srt, and AI subtitles.'
echo '  3. Private: long-press a video -> Hide (allow All files access'
echo '     if asked). Empty private screen shows the hold-a-video text.'
echo '  4. Sleep timer 15 min: countdown ticks under the title;'
echo '     "end of video" mode shows its note there too.'
echo '  5. 4K video: play 2 seconds ONCE -> thumbnail appears in library.'
echo '  6. Speed menu shows 2.5x and 3x; 3x plays.'
echo '  7. Volume swipe goes past 100% by default.'
echo '  8. Volume leveling ON (optionally with equalizer): steadier sound.'
echo '  9. AI subtitles with new Fast model finish much quicker.'
echo ' 10. Video with movie.srt beside movie.mp4 + late dialogue:'
echo '     Skip-to chip appears near start.'
echo '=============================================================='
