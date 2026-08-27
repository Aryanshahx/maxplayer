package com.hypertechlabs.maxplayer

import android.app.KeyguardManager
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
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.media.AudioAttributes
import android.media.AudioFocusRequest
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
import android.os.CancellationSignal
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.speech.RecognizerIntent
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
import kotlinx.coroutines.runBlocking
import kotlin.math.min

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

    // v64 hotfix: notification permission (Android 13+) request in flight.
    // Uses the classic requestPermissions / onRequestPermissionsResult
    // Activity API instead of an AndroidX activity-result launcher - the
    // latter was not resolvable on the FlutterActivity base class under
    // Codemagic's AGP/Kotlin classpath (it broke the v62/v63 release build).
    private var pendingNotificationResult: MethodChannel.Result? = null

    // v62 Phase 1: a notification tap that arrived before Dart attached to
    // the channel; getInitialNotificationPayload picks it up after attach.
    private var pendingNotificationPayload: String? = null

    /** Thrown by the model downloader when the user cancels the job. */
    private class AiCancelledException : Exception("cancelled")

    companion object {
        private const val ACTION_PIP_TOGGLE = "com.hypertechlabs.maxplayer.action.PIP_TOGGLE"
        const val ACTION_MEDIA_CONTROL = "com.hypertechlabs.maxplayer.action.MEDIA_CONTROL"
        const val EXTRA_MEDIA_ACTION = "action"
        private const val REQ_PIP_TOGGLE = 42
        private const val REQ_PIP_OPEN = 43
        private const val REQ_CONFIRM_CREDENTIAL = 44
        private const val REQ_NOTIF_PERMISSION = 45
        private const val REQ_VOICE_SEARCH = 46
        private val STREAM_SCHEMES = setOf("http", "https", "rtsp", "rtmp", "mms")
    }

    private var pendingVoiceSearchResult: MethodChannel.Result? = null
    private var mediaReceiverRegistered = false
    private var wakeLock: PowerManager.WakeLock? = null

    private val mediaReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_MEDIA_CONTROL) {
                val act = intent.getStringExtra(EXTRA_MEDIA_ACTION) ?: return
                channel?.invokeMethod("onMediaAction", act)
            }
        }
    }

    private fun ensureMediaReceiver() {
        if (mediaReceiverRegistered) return
        mediaReceiverRegistered = true
        val filter = IntentFilter(ACTION_MEDIA_CONTROL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(mediaReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(mediaReceiver, filter)
        }
    }

    private fun setWakeLock(enable: Boolean) {
        try {
            if (enable) {
                if (wakeLock == null) {
                    val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MaxPlayer::BackgroundAudioLock")
                }
                if (wakeLock?.isHeld == false) {
                    wakeLock?.acquire(24 * 60 * 60 * 1000L)
                }
            } else {
                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                }
            }
        } catch (_: Exception) {}
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val lp = window.attributes
            lp.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = lp
        }
    }

    private fun applyImmersiveMode(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val lp = window.attributes
            lp.layoutInDisplayCutoutMode = if (enabled) {
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            } else {
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
            }
            window.attributes = lp
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(!enabled)
            val controller = window.insetsController ?: return
            if (enabled) {
                controller.hide(android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            } else {
                controller.show(android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars())
            }
        } else {
            @Suppress("DEPRECATION")
            if (enabled) {
                window.decorView.systemUiVisibility = (
                    android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                )
            } else {
                window.decorView.systemUiVisibility = (
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                )
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        CrashCrumbs.mark(this, "activity_create_begin")
        super.onCreate(savedInstanceState)
        // v68/v70: Cutout / punch hole handling - draw under camera cutouts
        // on short edges for true edge-to-edge borderless display (VLC style).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        )
        // v62 Phase 1: create all notification channels once, before any
        // feature (AI-subs-ready, continue watching, ...) posts one.
        Notifications.ensureChannels(applicationContext)
        // v68 B1/B2: wire foreground media service actions to Flutter channel.
        MediaPlaybackService.onMediaAction = { action ->
            mainHandler.post { channel?.invokeMethod("onMediaAction", action) }
        }
        MediaPlaybackService.onMediaSeek = { posMs ->
            mainHandler.post { channel?.invokeMethod("onMediaSeek", posMs) }
        }
        CrashCrumbs.mark(this, "activity_create_ok")
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingIntent(intent)
    }

    /**
     * v40: absolute roots of EVERY mounted storage volume (internal storage
     * AND any SD card). The Dart scanner used to walk only
     * "/storage/emulated/0/", so videos on SD cards never appeared in the
     * library ("does not show external storage added on phone like sd
     * cards"). getExternalFilesDirs returns one app folder per volume
     * ("<root>/Android/data/<pkg>/files"); stripping the app suffix yields
     * the volume root. Needs no permission and never throws.
     */
    private fun storageRoots(): List<String> {
        val roots = LinkedHashSet<String>()
        try {
            @Suppress("DEPRECATION")
            roots.add(Environment.getExternalStorageDirectory().absolutePath)
        } catch (_: Throwable) {
        }
        try {
            for (dir in getExternalFilesDirs(null)) {
                val p = dir?.absolutePath ?: continue
                val i = p.indexOf("/Android/data/")
                roots.add(if (i > 0) p.substring(0, i) else p)
            }
        } catch (_: Throwable) {
        }
        if (roots.isEmpty()) roots.add("/storage/emulated/0")
        return roots.toList()
    }

    /**
     * v43: opens a YouTube video in the official YouTube app / browser via
     * an ACTION_VIEW intent. Needs no query permissions on modern Android
     * and returns false instead of throwing when nothing can handle it.
     */
    private fun openYouTube(key: String): Boolean {
        if (key.isEmpty()) return false
        return try {
            val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://www.youtube.com/watch?v=$key")
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        // v51: one-time prune of seek-strip bloat accumulated by older
        // versions (off the UI thread; recently-used order untouched).
        executor.execute { pruneThumbStrips() }
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
                    } else if (!Build.SUPPORTED_ABIS.contains("arm64-v8a")) {
                        // v39: the whisper engine ships arm64-only native
                        // libraries. On 32-bit phones (POCO C51 & friends)
                        // decline cleanly BEFORE any model download - Dart
                        // turns the null job id into the friendly snack.
                        result.success(null)
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
                "vaultDirPath" -> {
                    // v24 private-folder crash fix: the vault lived at a
                    // hardcoded /Android/data/<pkg> path, and creating the
                    // package folder there via raw mkdir is EACCES-denied
                    // on some devices when it is missing (real crash:
                    // PathAccessException errno=13 right after PIN entry).
                    // getExternalFilesDir lets the FRAMEWORK create/own it -
                    // no storage permission involved at all. On most phones
                    // this resolves to the exact same path as before, so
                    // already-hidden files stay put (Dart also migrates).
                    try {
                        val base = getExternalFilesDir(null) ?: filesDir
                        val dir = File(base, "Private")
                        if (dir.exists() || dir.mkdirs()) {
                            result.success(dir.absolutePath)
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "confirmDeviceCredential" -> {
                    // v26: "Forgot PIN" for the Private folder must first
                    // pass the PHONE's own lock (device password / pattern /
                    // PIN or fingerprint) - pure platform APIs, no new deps.
                    confirmDeviceCredential(
                        call.argument<String>("title") ?: "Unlock to continue",
                        result,
                    )
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
                "storageReport" -> {
                    // v28 Cleaner tile: sizes of the app's own reclaimable
                    // storage (thumbs / preview strips / AI temp / models).
                    result.success(storageReport())
                }
                "clearStorage" -> {
                    // Long (bytes freed); videos themselves are untouched.
                    result.success(clearStorageKind(call.argument<String>("kind") ?: ""))
                }
                "storageTotals" -> {
                    // v31 Cleaner graph: total/free bytes of the internal
                    // storage volume the app lives on.
                    val stat = StatFs(filesDir.absolutePath)
                    val out = HashMap<String, Long>()
                    out["total"] = stat.blockSizeLong * stat.blockCountLong
                    out["free"] = stat.blockSizeLong * stat.availableBlocksLong
                    result.success(out)
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
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                // v40: every mounted storage volume root, for the library
                // scanner (SD cards were invisible before).
                "storageRoots" -> result.success(storageRoots())
                // v43: Discover's cache dir (TMDB json + posters).
                "cacheDirPath" -> result.success(cacheDir.absolutePath)
                // v43: trailers open in the official YouTube app - the
                // Play-policy-safe path (streaming them through our own
                // player would violate YouTube's terms).
                "openYouTube" -> {
                    val key = call.argument<String>("key").orEmpty()
                    result.success(openYouTube(key))
                }
                "crumb" -> {
                    // v37: startup breadcrumb from Dart - append a stage
                    // mark to maxplayer_start.log (internal + the
                    // Android/data folder), survives a dead Dart/engine.
                    CrashCrumbs.mark(this, call.argument<String>("stage") ?: "unknown")
                    result.success(true)
                }
                "nativeCrashGet" -> {
                    // v34: read the JVM crash report the Application-level
                    // catcher (MaxPlayerApp) wrote after a "has stopped".
                    // null when there is none.
                    val text = try {
                        val f = File(filesDir, MaxPlayerApp.CRASH_FILE)
                        if (f.exists()) f.readText() else null
                    } catch (_: Exception) {
                        null
                    }
                    result.success(text)
                }
                "nativeCrashClear" -> {
                    // Called once the report was shown to the user.
                    try {
                        val f = File(filesDir, MaxPlayerApp.CRASH_FILE)
                        if (f.exists()) f.delete()
                    } catch (_: Exception) {
                        // best effort only
                    }
                    result.success(true)
                }
                // v62 Phase 1: notification foundation ----------------------
                "notifyShow" -> {
                    val id = (call.argument<Number>("id")?.toInt()) ?: 0
                    val outId = try {
                        Notifications.show(
                            context = applicationContext,
                            channel = call.argument<String>("channel")
                                ?: Notifications.CHANNEL_GENERAL,
                            id = id,
                            title = call.argument<String>("title") ?: "Max Player",
                            body = call.argument<String>("body") ?: "",
                            payload = call.argument<String>("payload"),
                            ongoing = call.argument<Boolean>("ongoing") ?: false,
                            progress = call.argument<Number>("progress")?.toInt(),
                        )
                    } catch (e: Exception) {
                        result.error("notify", e.message, null); return@setMethodCallHandler
                    }
                    result.success(outId)
                }
                "notifyCancel" -> {
                    val id = call.argument<Number>("id")?.toInt()
                    if (id != null) Notifications.cancel(applicationContext, id)
                    result.success(true)
                }
                "notifyCancelAll" -> {
                    Notifications.cancelAll(applicationContext)
                    result.success(true)
                }
                "notificationsEnabled" -> {
                    result.success(Notifications.areEnabled(applicationContext))
                }
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                        // No runtime permission below Android 13 - always on.
                        result.success(Notifications.areEnabled(applicationContext))
                    } else if (Notifications.areEnabled(applicationContext)) {
                        result.success(true)
                    } else if (pendingNotificationResult != null) {
                        result.error("busy", "a permission request is already showing", null)
                    } else {
                        pendingNotificationResult = result
                        try {
                            // Classic runtime permission request (works on
                            // every API level from 23 up; no AndroidX
                            // activity-ktx required). onRequestPermissionsResult
                            // delivers the answer below.
                            requestPermissions(
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                REQ_NOTIF_PERMISSION
                            )
                        } catch (e: Exception) {
                            pendingNotificationResult = null
                            result.success(false)
                        }
                    }
                }
                "getInitialNotificationPayload" -> {
                    val p = pendingNotificationPayload
                    pendingNotificationPayload = null
                    result.success(p)
                }
                "startVoiceSearch" -> {
                    if (pendingVoiceSearchResult != null) {
                        result.error("in_progress", "Voice search already running", null)
                    } else {
                        pendingVoiceSearchResult = result
                        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                            putExtra(RecognizerIntent.EXTRA_PROMPT, "Search movies & series...")
                            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                        }
                        try {
                            startActivityForResult(intent, REQ_VOICE_SEARCH)
                        } catch (e: Exception) {
                            pendingVoiceSearchResult = null
                            result.error("unavailable", "Speech recognition not available on this device", null)
                        }
                    }
                }
                "nowPlayingShow" -> {
                    val title = call.argument<String>("title") ?: "Max Player"
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val path = call.argument<String>("path") ?: ""
                    val thumbPath = call.argument<String>("thumbnailPath")
                    val posMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                    val durMs = call.argument<Number>("durationMs")?.toLong() ?: 0L
                    MediaPlaybackService.startOrUpdate(
                        applicationContext,
                        title,
                        subtitle,
                        isPlaying,
                        path,
                        thumbPath,
                        posMs,
                        durMs
                    )
                    result.success(MediaPlaybackService.NOTIF_ID)
                }
                "nowPlayingCancel" -> {
                    MediaPlaybackService.stop(applicationContext)
                    result.success(true)
                }
                "setWakeLock" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    setWakeLock(enable)
                    result.success(true)
                }
                "setImmersive" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    applyImmersiveMode(enabled)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        CrashCrumbs.mark(this, "channel_ready")
        // Channel is ready: deliver anything that arrived before Dart attached.
        pendingOpenPath?.let {
            channel?.invokeMethod("onOpenVideo", it)
            pendingOpenPath = null
        }
        pendingOpenFailed?.let {
            channel?.invokeMethod("onOpenVideoFailed", it)
            pendingOpenFailed = null
        }
        pendingNotificationPayload?.let {
            channel?.invokeMethod("onNotificationTap", it)
            pendingNotificationPayload = null
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
        // v62 Phase 1: a notification tap carries an opaque PAYLOAD string
        // (deep-link for the feature that posted it). Consume it once and
        // hand it to Dart (cold start via pending field, warm via channel).
        val notifPayload = intent.getStringExtra(Notifications.EXTRA_PAYLOAD)
        if (!notifPayload.isNullOrEmpty()) {
            intent.removeExtra(Notifications.EXTRA_PAYLOAD)
            deliverNotificationPayload(notifPayload)
        }
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

    /** v62 Phase 1: hand a notification-tap payload to Dart. */
    private fun deliverNotificationPayload(payload: String) {
        if (channel != null) {
            channel?.invokeMethod("onNotificationTap", payload)
        } else {
            pendingNotificationPayload = payload
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

    // ------------------------------------------------------------------
    // v28: Cleaner tile - reclaimable app storage report + freeing
    // ------------------------------------------------------------------

    private fun dirSizeBytes(f: File): Long {
        try {
            if (!f.exists()) return 0L
            if (f.isFile) return f.length()
            var total = 0L
            val list = f.listFiles() ?: return 0L
            for (c in list) total += dirSizeBytes(c)
            return total
        } catch (_: Exception) {
            return 0L
        }
    }

    private fun thumbStripDirs(): List<File> {
        val list = cacheDir.listFiles() ?: return emptyList()
        return list.filter { it.isDirectory && it.name.startsWith("thumbstrip_") }
    }

    /**
     * v51: one 72-frame strip costs ~1 MB and every video ever seeked
     * kept its own strip forever - the real source of the 800 MB+ app     * cache bloat (not mpv's demuxer cache, which is RAM and dies with
     * playback). Keep only the 48 most recently used strips.
     */
    private fun pruneThumbStrips(keep: Int = 48) {
        try {
            thumbStripDirs()
                .sortedByDescending { it.lastModified() }
                .drop(keep)
                .forEach { it.deleteRecursively() }
        } catch (_: Throwable) {
            // Best effort - never break playback over cache hygiene.
        }
    }

    /** Leftover AI wav chunks / abandoned capture temp files in the cache root. */
    private fun tempAiFiles(): List<File> {
        val list = cacheDir.listFiles() ?: return emptyList()
        return list.filter {
            it.isFile && (
                it.name.startsWith("ai_audio_") ||
                    it.name.startsWith("ai_slice_") ||
                    it.name.startsWith("ai_span_") ||
                    it.name.endsWith(".capture")
                )
        }
    }

    private fun storageReport(): HashMap<String, Long> {
        val out = HashMap<String, Long>()
        var strips = 0L
        for (d in thumbStripDirs()) strips += dirSizeBytes(d)
        var temp = 0L
        for (f in tempAiFiles()) temp += f.length()
        out["thumbs"] = dirSizeBytes(File(cacheDir, "thumbs"))
        out["strips"] = strips
        out["temp"] = temp
        out["models"] = dirSizeBytes(File(filesDir, "models"))
        return out
    }

    private fun clearStorageKind(kind: String): Long {
        var freed = 0L
        when (kind) {
            "thumbs" -> {
                val d = File(cacheDir, "thumbs")
                freed += dirSizeBytes(d)
                d.deleteRecursively()
                d.mkdirs()
                for (s in thumbStripDirs()) {
                    freed += dirSizeBytes(s)
                    s.deleteRecursively()
                }
            }
            "temp" -> {
                for (f in tempAiFiles()) {
                    val len = f.length()
                    if (f.delete()) freed += len
                }
            }
            "models" -> {
                val d = File(filesDir, "models")
                freed += dirSizeBytes(d)
                d.deleteRecursively()
            }
        }
        return freed
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
        // v47: scoped-storage phones may hand us a content URI; don't
        // reject it at the File-exists gate.
        val isContent = path.startsWith("content://")
        if (!isContent && !videoFile.exists()) return out

        val retriever = MediaMetadataRetriever()
        try {
            try {
                // v47: content URIs need the Context overload.
                if (isContent) retriever.setDataSource(
                    this, android.net.Uri.parse(path))
                else retriever.setDataSource(path)
            } catch (e: Exception) {
                retriever.setDataSource(this, android.net.Uri.parse(path))
            }
            val durationMs =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            out["durationMs"] = durationMs
            out["width"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            out["height"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            out["bitrate"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull()
            // Track details from the container (one extractor pass, works
            // on all API levels): video codec + frame rate, first audio
            // track's codec/channels/sample-rate. v27: powers the advanced
            // Video info sheet.
            addTrackDetails(path, out)

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
    /**
     * v27: fills [out] with codec + technical track details in ONE
     * MediaExtractor pass (cheap enough for the per-file library scan):
     *  - "codec": friendly video codec name from the video track MIME
     *  - "frameRate": video track fps (0 when the container omits it)
     *  - "audioCodec": friendly name of the FIRST audio track
     *  - "audioChannels" / "audioSampleRate": same track's layout/rate
     */
    private fun addTrackDetails(path: String, out: HashMap<String, Any?>) {
        out["frameRate"] = 0
        out["audioCodec"] = null
        out["audioChannels"] = 0
        out["audioSampleRate"] = 0
        out["hdr"] = "sdr"
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            var videoDone = false
            var audioDone = false
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime =
                    if (format.containsKey(MediaFormat.KEY_MIME)) {
                        format.getString(MediaFormat.KEY_MIME)
                    } else {
                        null
                    } ?: continue
                if (!videoDone && mime.startsWith("video/")) {
                    out["codec"] = friendlyCodec(mime)
                    if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                        out["frameRate"] = format.getInteger(MediaFormat.KEY_FRAME_RATE)
                    }
                    // v32: dynamic-range detection for the info sheet.
                    // Dolby Vision has no licensed pipeline here - mpv plays
                    // its HDR10-compatible fallback, which the Dart label
                    // communicates. Dolby files report mime
                    // "video/dolby-vision" (dvhe/dvav) via MediaExtractor.
                    out["hdr"] = when {
                        mime == "video/dolby-vision" -> "dolby-vision"
                        format.containsKey("hdr10-plus-info") -> "hdr10+"
                        format.containsKey("hdr-static-info") -> "hdr10"
                        format.containsKey(MediaFormat.KEY_COLOR_TRANSFER) ->
                            when (format.getInteger(MediaFormat.KEY_COLOR_TRANSFER)) {
                                6 -> "hdr10" // MediaFormat.COLOR_TRANSFER_ST2084 (PQ)
                                7 -> "hlg"   // MediaFormat.COLOR_TRANSFER_HLG
                                else -> "sdr"
                            }
                        else -> "sdr"
                    }
                    videoDone = true
                } else if (!audioDone && mime.startsWith("audio/")) {
                    out["audioCodec"] = friendlyCodec(mime)
                    if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        out["audioChannels"] =
                            format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                    if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        out["audioSampleRate"] =
                            format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    }
                    audioDone = true
                }
                if (videoDone && audioDone) break
            }
        } catch (_: Exception) {
            // Leave the defaults/nulls - Dart renders "Unknown".
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
            // v27: audio track names for the advanced Video info sheet.
            "audio/mp4a-latm" -> "AAC"
            "audio/mpeg", "audio/mpeg-l1", "audio/mpeg-l2" -> "MP3"
            "audio/opus" -> "Opus"
            "audio/vorbis" -> "Vorbis"
            "audio/flac" -> "FLAC"
            "audio/ac3" -> "AC-3"
            "audio/eac3", "audio/eac3-joc" -> "E-AC-3"
            "audio/truehd" -> "TrueHD"
            "audio/x-ms-wma" -> "WMA"
            "audio/amr-nb", "audio/amr-wb" -> "AMR"
            "audio/raw" -> "PCM"
            else -> mime.substringAfter('/').uppercase()
        }
    }

    // ---------------------------------------------------------------------------
    // AI subtitles pipeline (v54: back ON DEVICE - whisper.cpp,
    // offline & free after the one-time model download)
    //
    //   video -> [MediaExtractor + MediaCodec] 16 kHz mono WAV (on device)
    //         -> speech gating (on device) -> speech slices <= 3 min
    //         -> speech-slice WAVs on disk. Dart uploads each slice to
    //         the OpenRouter cloud (built-in key) and merges the SRT.
    //
    // Dart merges the slice SRTs (pure, unit-tested), writes the .srt and
    // mpv loads it via `sub-add`. No model download, no 64-bit limit, no
    // WebView, no sign-in - the API key is compiled in (like movie Q&A).
    // ---------------------------------------------------------------------------

    private fun aiProgress(jobId: Int, stage: String, percent: Int) {
        mainHandler.post {
            channel?.invokeMethod(
                "onAiProgress",
                hashMapOf("job" to jobId, "stage" to stage, "percent" to percent)
            )
        }
    }

    /**
     * Greedy grouping of speech spans into cloud-sized slices: spans merge
     * while the slice's WALL duration (gaps between spans included) stays
     * <= [maxWallSec]. Sending only voiced audio costs a fraction of the
     * whole file and short kept gaps preserve sentence context across
     * spans. Indices are 16 kHz mono sample positions (same as speechSpans).
     */
    private fun groupSpans(spans: List<IntArray>, maxWallSec: Int): List<IntArray> {
        val groups = ArrayList<IntArray>()
        val maxSamples = maxWallSec * 16000
        var start = -1
        var end = -1
        for (sp in spans) {
            if (start < 0) {
                start = sp[0]
                end = sp[1]
            } else if (sp[1] - start <= maxSamples) {
                end = maxOf(end, sp[1])
            } else {
                groups.add(intArrayOf(start, end))
                start = sp[0]
                end = sp[1]
            }
        }
        if (start >= 0) groups.add(intArrayOf(start, end))
        return groups
    }

    /**
     * v52: prepares cloud subtitle input ON DEVICE: video -> 16 kHz mono
     * WAV -> speech gating -> ~3 minute speech-slice WAV files on disk.
     * Returns a map {slices: [{path, offsetMs}...]} for Dart, which then
     * uploads each slice to the OpenRouter cloud itself. An empty slice
     * list means "no speech"; "error" holds a user-readable reason
     * ('cancelled' when aborted).
     */
    // v25: only the accurate models stay ("tiny" removed for good). Speed
    // comes from all-core threading instead of a weaker model. Unknown ids
    // (including a "tiny" id saved by v22-v24 builds) fall back to "base".
    private fun modelFileFor(name: String): File {
        val safe = when (name) {
            "base", "small" -> name
            else -> "base"
        }
        return File(filesDir, "models/ggml-$safe.bin")
    }

    private fun modelUrlFor(name: String): String {
        return when (name) {
            "small" ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
            else ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
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
            // those bytes to the 16-bit resampler produced noise, and the
            // transcriber answered noise with "music" captions.
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
     * the transcriber answered noise with "music".
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
     * <=30 s so slices stay small and fast to transcribe.
     *
     * Conservative by design: only true near-silence is dropped. The
     * threshold sits at ~2x the adaptive noise floor with a very low
     * absolute floor, so quiet speech is kept while digital/room silence is
     * skipped. Music is far above this floor and is therefore NEVER gated
     * out (speech over loud background music still gets transcribed).
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
                if (have >= count) {
                    // v51: touch so LRU pruning keeps recently-used strips.
                    dir.setLastModified(System.currentTimeMillis())
                    return dir.absolutePath
                }
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
            pruneThumbStrips()
            return dir.absolutePath
        } catch (t: Throwable) {
            return null
        }
    }

    // ------------------------------------------------------------------
    // v26: device-credential check (Private-folder "Forgot PIN" gate)
    // ------------------------------------------------------------------

    /** Pending Dart reply while a device-unlock prompt is on screen. */
    private var pendingCredentialResult: MethodChannel.Result? = null

    /**
     * Shows the phone's own unlock UI (device PIN / pattern / password, or
     * fingerprint/face where enrolled) and answers true only when the owner
     * passes it. A device WITHOUT any screen lock answers true at once -
     * nothing exists to ask for there, and the unlocked phone itself is
     * the proof of possession. Uses only platform classes (works back to
     * the app's minSdk, no androidx.biometric dependency):
     * BiometricPrompt on API 28+, the classic KeyguardManager confirm
     * activity below that.
     */
    private fun confirmDeviceCredential(title: String, result: MethodChannel.Result) {
        if (pendingCredentialResult != null) {
            result.error("busy", "an unlock prompt is already showing", null)
            return
        }
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val secure =
            if (Build.VERSION.SDK_INT >= 23) km.isDeviceSecure else km.isKeyguardSecure
        if (!secure) {
            result.success(true)
            return
        }
        pendingCredentialResult = result
        if (Build.VERSION.SDK_INT >= 28) {
            showBiometricCredentialPrompt(title)
        } else {
            showKeyguardCredentialPrompt(title)
        }
    }

    /** Platform BiometricPrompt (API 28+) including the DEVICE credential. */
    private fun showBiometricCredentialPrompt(title: String) {
        val promptExecutor = java.util.concurrent.Executor { command ->
            mainHandler.post(command)
        }
        val builder = BiometricPrompt.Builder(this).setTitle(title)
        if (Build.VERSION.SDK_INT >= 30) {
            // v27 fix (real device report: instant "unlock failed" on a
            // Samsung tab): on API 30+ a NEGATIVE BUTTON may NOT be combined
            // with DEVICE_CREDENTIAL - the prompt throws before it can show.
            // The system credential screen has its own cancel, and errors
            // arrive in onAuthenticationError instead.
            builder.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setDeviceCredentialAllowed(true)
            builder.setNegativeButton("Cancel", promptExecutor) { _, _ ->
                finishCredentialPrompt(false)
            }
        }
        try {
            builder.build().authenticate(
                CancellationSignal(),
                promptExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(
                        authResult: BiometricPrompt.AuthenticationResult
                    ) {
                        finishCredentialPrompt(true)
                    }

                    override fun onAuthenticationError(
                        errorCode: Int,
                        errString: CharSequence
                    ) {
                        when (errorCode) {
                            // 11 = no biometrics enrolled, 12 = no hardware,
                            // 14 = no device credential: some builds report
                            // these even with DEVICE_CREDENTIAL allowed -
                            // retry via the classic confirm-credential screen.
                            11, 12, 14 -> showKeyguardCredentialPrompt(title)
                            // Everything else (cancel, lockout, hw busy...):
                            // answer "not unlocked" - Dart shows a snackbar.
                            else -> finishCredentialPrompt(false)
                        }
                    }
                    // onAuthenticationFailed intentionally NOT handled:
                    // the system prompt stays open for another attempt.
                },
            )
        } catch (e: Exception) {
            // Prompt could not even be constructed/shown -> classic fallback.
            showKeyguardCredentialPrompt(title)
        }
    }

    /** The classic "confirm your screen lock" activity (works on all APIs). */
    private fun showKeyguardCredentialPrompt(title: String) {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        @Suppress("DEPRECATION")
        val intent = km.createConfirmDeviceCredentialIntent(title, null)
        if (intent == null) {
            finishCredentialPrompt(true)
            return
        }
        try {
            startActivityForResult(intent, REQ_CONFIRM_CREDENTIAL)
        } catch (e: Exception) {
            finishCredentialPrompt(false)
        }
    }

    private fun finishCredentialPrompt(ok: Boolean) {
        val pending = pendingCredentialResult ?: return
        pendingCredentialResult = null
        mainHandler.post { pending.success(ok) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_CONFIRM_CREDENTIAL) {
            finishCredentialPrompt(resultCode == RESULT_OK)
        } else if (requestCode == REQ_VOICE_SEARCH) {
            val pending = pendingVoiceSearchResult
            pendingVoiceSearchResult = null
            if (resultCode == RESULT_OK && data != null) {
                val matches = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val query = matches?.firstOrNull()?.trim()
                pending?.success(query)
            } else {
                pending?.success(null)
            }
        }
    }

    // v64 hotfix: answers the POST_NOTIFICATIONS runtime request started by
    // the "requestNotifications" channel call (classic API, no AndroidX
    // activity-ktx). A null pending result means the app was recreated mid-
    // prompt - the next Dart-side check reads the actual state anyway.
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_NOTIF_PERMISSION) return
        val r = pendingNotificationResult
        pendingNotificationResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        r?.success(granted)
    }

    override fun onDestroy() {
        if (pipReceiverRegistered) {
            try {
                unregisterReceiver(pipReceiver)
            } catch (_: Exception) {
            }
            pipReceiverRegistered = false
        }
        if (mediaReceiverRegistered) {
            try {
                unregisterReceiver(mediaReceiver)
            } catch (_: Exception) {
            }
            mediaReceiverRegistered = false
        }
        if (wakeLock?.isHeld == true) {
            try {
                wakeLock?.release()
            } catch (_: Exception) {
            }
        }
        executor.shutdown()
        super.onDestroy()
    }
}
