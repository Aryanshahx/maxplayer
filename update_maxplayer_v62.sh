#!/usr/bin/env bash
# =============================================================================
#  Max Player  -  v62  (1.0.0+58)
#  PHASE 1: NOTIFICATION FOUNDATION
#
#  Run from the repo root:   bash update_maxplayer_v62.sh
#  Idempotent - run it twice; both runs must end "N/N checks OK".
#
#  This is the GROUNDWORK for every notification feature we planned. It adds:
#
#   1. FIVE notification channels (created once, in onCreate):
#        ai_subs  continue  new_episodes  playback  general
#      Users can mute each kind independently in Android settings.
#
#   2. Android 13+ POST_NOTIFICATIONS runtime permission:
#        - <uses-permission> in AndroidManifest.xml
#        - NativeBridge.requestNotifications() -> system dialog
#        - NativeBridge.notificationsEnabled() -> current grant state
#
#   3. A generic notification API over the existing maxplayer/native channel:
#        NativeBridge.showNotification(channel, title, body, payload,
#                                     ongoing, progress) -> id
#        NativeBridge.cancelNotification(id) / cancelAllNotifications()
#      Tapping a notification delivers its `payload` (a deep-link string)
#      back to Dart via the onNotificationTap callback (warm) or
#      getInitialNotificationPayload() (cold start).
#
#   4. A NEW FILE android/.../Notifications.kt (plain AndroidX, no new
#      Flutter packages, no new Maven deps) + a monochrome status-bar icon
#      res/drawable/ic_stat_notify.xml.
#
#   5. A "Send a test notification" button in the About sheet - tap it to
#      verify the WHOLE pipeline (permission -> channel -> tap -> snackbar)
#      on your phone. This proves Phase 1 before we build real features.
#
#  NOTHING changes in playback, gestures or Discover. Later phases wire:
#    Phase B: AI-subs-ready, Continue watching, Scan/cast status
#    Phase C: New-episode alerts (Follow button + WorkManager)
#    Phase D: Now-playing controls (MediaSession)
#
#  AFTER "N/N checks OK":
#     git add -A && git commit -m "v62 Phase 1: notification foundation -
#     channels, POST_NOTIFICATIONS permission, generic notify API, test
#     button (1.0.0+58)" && git push
#  Codemagic builds APK/AAB. Install and phone-test (checklist at end).
#
#  RUN AS-IS. Do not hand-edit before pushing.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"
echo "============================================================"
echo " Max Player v62 (1.0.0+58) - Phase 1 notification foundation"
echo " Running from: $(pwd)"
echo "============================================================"
mkdir -p "$(dirname "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt")"
cat > "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt" <<'MAXV62_EOF_NOTIFICATIONS_KT'
package com.hypertechlabs.maxplayer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * v62 (Phase 1): the NOTIFICATION FOUNDATION used by every later feature
 * (AI-subs-ready, continue watching, new episodes, now-playing).
 *
 * Zero new Flutter packages - this is plain AndroidX (core-ktx ships with
 * the Flutter embedding already) behind the existing `maxplayer/native`
 * MethodChannel. Channels are created lazily/once; all calls are safe on
 * old Android (notification channels are an API 26 no-op below that).
 *
 * Channels:
 *  - ai_subs        : "AI subtitles"        (low/urgency - finished job)
 *  - continue       : "Continue watching"   (default)
 *  - new_episodes   : "New episodes"        (default)
 *  - playback       : "Playback"            (low, ongoing now-playing)
 *  - general        : "General"             (default)
 */
object Notifications {
    const val EXTRA_PAYLOAD = "maxplayer.notification.PAYLOAD"

    const val CHANNEL_AI_SUBS = "ai_subs"
    const val CHANNEL_CONTINUE = "continue"
    const val CHANNEL_NEW_EPISODES = "new_episodes"
    const val CHANNEL_PLAYBACK = "playback"
    const val CHANNEL_GENERAL = "general"

    private val channels = listOf(
        Triple(CHANNEL_AI_SUBS, "AI subtitles", NotificationManager.IMPORTANCE_LOW),
        Triple(CHANNEL_CONTINUE, "Continue watching", NotificationManager.IMPORTANCE_DEFAULT),
        Triple(CHANNEL_NEW_EPISODES, "New episodes", NotificationManager.IMPORTANCE_DEFAULT),
        Triple(CHANNEL_PLAYBACK, "Playback", NotificationManager.IMPORTANCE_LOW),
        Triple(CHANNEL_GENERAL, "General", NotificationManager.IMPORTANCE_DEFAULT),
    )

    /**
     * Creates every notification channel once. Safe to call repeatedly and
     * on any API level (channels are ignored below Android 8.0). Called from
     * Activity.onCreate so channels exist before the first notify.
     */
    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        for ((id, title, importance) in channels) {
            if (nm.getNotificationChannel(id) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(id, title, importance).apply {
                        description = "Max Player notifications"
                    }
                )
            }
        }
    }

    /**
     * Posts (or replaces) a notification. Returns the id used so callers can
     * cancel it later. [payload] is an opaque string delivered to Dart via
     * the onNotificationTap callback when the user taps the notification;
     * use it like a deep-link (e.g. "video:/path" or "ai:jobid").
     *
     * The small icon is the monochrome glyph in res/drawable (required on
     * Android 5+; a color/photo icon would render as a white square).
     */
    fun show(
        context: Context,
        channel: String,
        id: Int,
        title: String,
        body: String,
        payload: String?,
        ongoing: Boolean,
        progress: Int?,
    ): Int {
        val notifId = if (id != 0) id else ((System.currentTimeMillis() and 0x7FFFFFFF).toInt())
        val tap = createLaunchIntent(context, payload)
        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(!ongoing)
            .setOngoing(ongoing)
            .setPriority(
                if (channel == CHANNEL_AI_SUBS || channel == CHANNEL_PLAYBACK)
                    NotificationCompat.PRIORITY_LOW
                else
                    NotificationCompat.PRIORITY_DEFAULT
            )
            .setContentIntent(tap)
        if (progress != null && progress in 0..100) {
            builder.setProgress(100, progress, progress <= 0)
        }
        try {
            NotificationManagerCompat.from(context).notify(notifId, builder.build())
        } catch (_: SecurityException) {
            // Android 13+ without POST_NOTIFICATIONS - the Dart side asks
            // for the permission first; if it was denied we simply no-op.
        }
        return notifId
    }

    fun cancel(context: Context, id: Int) {
        NotificationManagerCompat.from(context).cancel(id)
    }

    fun cancelAll(context: Context) {
        NotificationManagerCompat.from(context).cancelAll()
    }

    /** Whether the app may post notifications (granted, or pre-API-33). */
    fun areEnabled(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()

    /**
     * Builds the tap intent: opens/reuses MainActivity (singleTop) and
     * carries [payload] as [EXTRA_PAYLOAD]. MainActivity reads it in
     * onCreate/onNewIntent and hands it to Dart via onNotificationTap.
     */
    fun createLaunchIntent(context: Context, payload: String?): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (!payload.isNullOrEmpty()) putExtra(EXTRA_PAYLOAD, payload)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(context, payload?.hashCode() ?: 0, intent, flags)
    }
}
MAXV62_EOF_NOTIFICATIONS_KT
echo "  wrote android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt"
mkdir -p "$(dirname "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt")"
cat > "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt" <<'MAXV62_EOF_MAINACTIVITY_KT'
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
import android.os.StatFs
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.WindowManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
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

    // v62 Phase 1: notification permission (Android 13+) request in flight.
    private var pendingNotificationResult: MethodChannel.Result? = null
    private val notificationPermissionLauncher: ActivityResultLauncher<String> =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val r = pendingNotificationResult
            pendingNotificationResult = null
            r?.success(granted)
        }

    // v62 Phase 1: a notification tap that arrived before Dart attached to
    // the channel; getInitialNotificationPayload picks it up after attach.
    private var pendingNotificationPayload: String? = null

    /** Thrown by the model downloader when the user cancels the job. */
    private class AiCancelledException : Exception("cancelled")

    companion object {
        private const val ACTION_PIP_TOGGLE = "com.hypertechlabs.maxplayer.action.PIP_TOGGLE"
        private const val REQ_PIP_TOGGLE = 42
        private const val REQ_PIP_OPEN = 43
        private const val REQ_CONFIRM_CREDENTIAL = 44
        private val STREAM_SCHEMES = setOf("http", "https", "rtsp", "rtmp", "mms")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        CrashCrumbs.mark(this, "activity_create_begin")
        super.onCreate(savedInstanceState)
        // v62 Phase 1: create all notification channels once, before any
        // feature (AI-subs-ready, continue watching, ...) posts one.
        Notifications.ensureChannels(applicationContext)
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
                            notificationPermissionLauncher.launch(
                                android.Manifest.permission.POST_NOTIFICATIONS
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
MAXV62_EOF_MAINACTIVITY_KT
echo "  wrote android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt"
mkdir -p "$(dirname "android/app/src/main/AndroidManifest.xml")"
cat > "android/app/src/main/AndroidManifest.xml" <<'MAXV62_EOF_ANDROIDMANIFEST_XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
        tools:ignore="ScopedStorage" />

    <!-- v51: release builds were seen merging the signature-level DUMP
         permission from a bundled library; a third-party app can never
         hold it, so strip it from the merged manifest explicitly. -->
    <uses-permission android:name="android.permission.DUMP"
        tools:node="remove" />

    <!-- Network: one-time AI model download + streaming URLs + DLNA cast control -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <!-- DLNA/UPnP casting: SSDP device discovery needs the multicast lock -->
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />

    <!-- v62 Phase 1: notifications (AI-subs-ready, continue watching, new
         episodes, now-playing). Only needed on Android 13+; below that
         notifications post without a runtime prompt. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <!-- v42 COMPAT AUDIT:
         1) WRITE_EXTERNAL_STORAGE (Android 10 and older only): READ alone is
            not enough for raw-path WRITES - moving a video into/out of the
            Private folder, deleting via some flows, etc. It auto-rides along
            with the classic Storage runtime request (v38/v40 helper).
         2) requestLegacyExternalStorage: Android 10 (API 29) sandboxes raw
            file paths EVEN with the Storage permission; our library scanner
            walks /storage with real paths (dart:io), and without this flag
            the scan finds NOTHING on Android 10 specifically. Restores the
            pre-Android-10 raw-path behavior there (ignored elsewhere).
         3) usesCleartextTraffic: plain http:// video streams are an
            advertised feature; for targetSdk 28+ cleartext defaults to
            BLOCKED, and OEM enforcement around native sockets varies -
            declare it allowed explicitly (standard for local players). -->
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="29" />

    <!-- v42: Play would otherwise infer "touchscreen required" and hide the
         app from Android TV boxes and other non-touch devices. -->
    <uses-feature android:name="android.hardware.touchscreen"
        android:required="false" />

    <application
        android:label="Max Player"
        android:name=".MaxPlayerApp"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:requestLegacyExternalStorage="true"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:resizeableActivity="true"
            android:supportsPictureInPicture="true"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />

            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>

            <!-- ================= Open with / Share ================= -->
            <!-- "Share -> Max Player" from any gallery, file manager, chat app -->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="video/*" />
            </intent-filter>

            <!-- Properly typed local videos (galleries, file managers) -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="content" android:mimeType="video/*" />
                <data android:scheme="file" android:mimeType="video/*" />
            </intent-filter>

            <!-- Typed video links in browsers -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="http" android:mimeType="video/*" />
                <data android:scheme="https" android:mimeType="video/*" />
            </intent-filter>

            <!-- Live streaming protocols -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="rtsp" />
                <data android:scheme="rtmp" />
                <data android:scheme="mms" />
            </intent-filter>

            <!-- Untyped URIs (FileProvider & friends): any mime, but the path
                 has a video extension. Lower- and upper-case patterns because
                 Android's pattern matching is case-sensitive. -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="file" />
                <data android:scheme="content" />
                <data android:host="*" />
                    <data android:pathPattern=".*\\.mp4" />
                    <data android:pathPattern=".*\\.MP4" />
                    <data android:pathPattern=".*\\.webm" />
                    <data android:pathPattern=".*\\.WEBM" />
                    <data android:pathPattern=".*\\.mkv" />
                    <data android:pathPattern=".*\\.MKV" />
                    <data android:pathPattern=".*\\.avi" />
                    <data android:pathPattern=".*\\.AVI" />
                    <data android:pathPattern=".*\\.mov" />
                    <data android:pathPattern=".*\\.MOV" />
                    <data android:pathPattern=".*\\.wmv" />
                    <data android:pathPattern=".*\\.WMV" />
                    <data android:pathPattern=".*\\.flv" />
                    <data android:pathPattern=".*\\.FLV" />
                    <data android:pathPattern=".*\\.m4v" />
                    <data android:pathPattern=".*\\.M4V" />
                    <data android:pathPattern=".*\\.3gp" />
                    <data android:pathPattern=".*\\.3GP" />
                    <data android:pathPattern=".*\\.3gpp" />
                    <data android:pathPattern=".*\\.3GPP" />
                    <data android:pathPattern=".*\\.ogv" />
                    <data android:pathPattern=".*\\.OGV" />
                    <data android:pathPattern=".*\\.ts" />
                    <data android:pathPattern=".*\\.TS" />
                    <data android:pathPattern=".*\\.mts" />
                    <data android:pathPattern=".*\\.MTS" />
                    <data android:pathPattern=".*\\.m2ts" />
                    <data android:pathPattern=".*\\.M2TS" />
                    <data android:pathPattern=".*\\.vob" />
                    <data android:pathPattern=".*\\.VOB" />
                    <data android:pathPattern=".*\\.mpg" />
                    <data android:pathPattern=".*\\.MPG" />
                    <data android:pathPattern=".*\\.mpeg" />
                    <data android:pathPattern=".*\\.MPEG" />
                    <data android:pathPattern=".*\\.rmvb" />
                    <data android:pathPattern=".*\\.RMVB" />
                    <data android:pathPattern=".*\\.divx" />
                    <data android:pathPattern=".*\\.DIVX" />
                    <data android:pathPattern=".*\\.f4v" />
                    <data android:pathPattern=".*\\.F4V" />
            </intent-filter>

            <!-- Videos wrongly typed as application/octet-stream (common on
                 Xiaomi/Oppo/Vivo/Realme galleries & some file managers). -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="file" />
                <data android:scheme="content" />
                <data android:scheme="http" />
                <data android:scheme="https" />
                <data android:host="*" />
                <data android:mimeType="application/octet-stream" />
                    <data android:pathPattern=".*\\.mp4" />
                    <data android:pathPattern=".*\\.MP4" />
                    <data android:pathPattern=".*\\.webm" />
                    <data android:pathPattern=".*\\.WEBM" />
                    <data android:pathPattern=".*\\.mkv" />
                    <data android:pathPattern=".*\\.MKV" />
                    <data android:pathPattern=".*\\.avi" />
                    <data android:pathPattern=".*\\.AVI" />
                    <data android:pathPattern=".*\\.mov" />
                    <data android:pathPattern=".*\\.MOV" />
                    <data android:pathPattern=".*\\.wmv" />
                    <data android:pathPattern=".*\\.WMV" />
                    <data android:pathPattern=".*\\.flv" />
                    <data android:pathPattern=".*\\.FLV" />
                    <data android:pathPattern=".*\\.m4v" />
                    <data android:pathPattern=".*\\.M4V" />
                    <data android:pathPattern=".*\\.3gp" />
                    <data android:pathPattern=".*\\.3GP" />
                    <data android:pathPattern=".*\\.3gpp" />
                    <data android:pathPattern=".*\\.3GPP" />
                    <data android:pathPattern=".*\\.ogv" />
                    <data android:pathPattern=".*\\.OGV" />
                    <data android:pathPattern=".*\\.ts" />
                    <data android:pathPattern=".*\\.TS" />
                    <data android:pathPattern=".*\\.mts" />
                    <data android:pathPattern=".*\\.MTS" />
                    <data android:pathPattern=".*\\.m2ts" />
                    <data android:pathPattern=".*\\.M2TS" />
                    <data android:pathPattern=".*\\.vob" />
                    <data android:pathPattern=".*\\.VOB" />
                    <data android:pathPattern=".*\\.mpg" />
                    <data android:pathPattern=".*\\.MPG" />
                    <data android:pathPattern=".*\\.mpeg" />
                    <data android:pathPattern=".*\\.MPEG" />
                    <data android:pathPattern=".*\\.rmvb" />
                    <data android:pathPattern=".*\\.RMVB" />
                    <data android:pathPattern=".*\\.divx" />
                    <data android:pathPattern=".*\\.DIVX" />
                    <data android:pathPattern=".*\\.f4v" />
                    <data android:pathPattern=".*\\.F4V" />
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
        <!-- v33: Force the legacy Skia renderer instead of Impeller.
             Impeller (default since Flutter 3.29) crashes / shows black
             video with libmpv on many older GPUs - older Androids keep
             playing fine through the Skia path. -->
        <meta-data
            android:name="io.flutter.embedding.android.EnableImpeller"
            android:value="false" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
MAXV62_EOF_ANDROIDMANIFEST_XML
echo "  wrote android/app/src/main/AndroidManifest.xml"
mkdir -p "$(dirname "android/app/src/main/res/drawable/ic_stat_notify.xml")"
cat > "android/app/src/main/res/drawable/ic_stat_notify.xml" <<'MAXV62_EOF_RES_DRAWABLE_IC_STAT_NOTIFY_XML'
<!-- v62: monochrome status-bar glyph for notifications (Android 5+ requires
     a white-on-transparent silhouette; a color/photo icon renders as a white
     square). A simple rounded rectangle with a play triangle. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M8,5.5v13l11,-6.5z" />
</vector>
MAXV62_EOF_RES_DRAWABLE_IC_STAT_NOTIFY_XML
echo "  wrote android/app/src/main/res/drawable/ic_stat_notify.xml"
mkdir -p "$(dirname "lib/services/native_bridge.dart")"
cat > "lib/services/native_bridge.dart" <<'MAXV62_EOF_NATIVE_BRIDGE_DART'
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
  }) {
    if (onOpenVideo != null) _onOpenVideo = onOpenVideo;
    if (onOpenVideoFailed != null) _onOpenVideoFailed = onOpenVideoFailed;
    if (onPipChanged != null) _onPipChanged = onPipChanged;
    if (onPipAction != null) _onPipAction = onPipAction;
    if (onAiProgress != null) _onAiProgress = onAiProgress;
    if (onAiDone != null) _onAiDone = onAiDone;
    if (onAiFailed != null) _onAiFailed = onAiFailed;
    if (onNotificationTap != null) _onNotificationTap = onNotificationTap;
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
MAXV62_EOF_NATIVE_BRIDGE_DART
echo "  wrote lib/services/native_bridge.dart"
mkdir -p "$(dirname "lib/main.dart")"
cat > "lib/main.dart" <<'MAXV62_EOF_MAIN_DART'
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
    // v37: startup breadcrumbs - maxplayer_start.log (also in Android/
    // data/...) shows how far a phone gets before dying.
    unawaited(NativeBridge.crumb('dart_main'));
    // Must be called before any media_kit Player is created.
    MediaKit.ensureInitialized();
    unawaited(NativeBridge.crumb('mediakit_ok'));
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

  // v37: created inside initState under a guard - if the playback engine's
  // native library can't load on this device, show a readable error screen
  // instead of dying with "Max Player has stopped" at startup.
  MediaPlayerState? _player;
  Object? _playerError;

  @override
  void initState() {
    super.initState();
    try {
      _player = MediaPlayerState();
      unawaited(NativeBridge.crumb('player_ok'));
    } catch (e) {
      _playerError = e;
      unawaited(NativeBridge.crumb('player_FAIL: $e'));
    }
    // App-wide accent color (persisted).
    themeState.load();
    final mp = _player;
    if (mp != null) {
      // v22: the player's fallback for 4K/HDR thumbnails writes the cached
      // image itself - swap it into the already-built library list so the
      // tile updates without a rescan.
      mp.onThumbnailCaptured =
          (videoPath, thumbPath) => library.setThumbnail(videoPath, thumbPath);
      // "Open with Max Player" from other apps: warm delivery ...
      NativeBridge.configureCallbacks(
        onOpenVideo: _openExternalVideo,
        onOpenVideoFailed: _externalOpenFailed,
        // v62 Phase 1: a notification was tapped while the app was running.
        onNotificationTap: _handleNotificationTap,
      );
      // ... and the cold-start cases (app launched BY a VIEW intent or a
      // notification tap).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final initial = await NativeBridge.getInitialOpenVideo();
        final path = initial['path'];
        final failed = initial['failed'];
        if (path != null) {
          _openExternalVideo(path);
        } else if (failed != null) {
          _externalOpenFailed(failed);
        }
        // Cold start from a notification tap.
        final notifPayload =
            await NativeBridge.getInitialNotificationPayload();
        if (notifPayload != null) {
          _handleNotificationTap(notifPayload);
        }
      });
    }
  }

  /// Plays a video that another app sent us. Local files arrive as real
  /// filesystem paths (resolved natively); http/rtsp-style links are treated
  /// as network streams and handed to libmpv directly.
  Future<void> _openExternalVideo(String path) async {
    final mp = _player;
    if (mp == null) return;
    const streamSchemes = {'http', 'https', 'rtsp', 'rtmp', 'mms'};
    final uri = Uri.tryParse(path);
    if (uri != null && streamSchemes.contains(uri.scheme.toLowerCase())) {
      final title =
          uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
              ? Uri.decodeComponent(uri.pathSegments.last)
              : uri.host;
      await mp.playStream(path, title);
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
    await mp.setPlaylistAndPlay([track], 0);
    _navigateToPlayer();
  }

  /// Jump straight into the player, replacing an already-open one.
  void _navigateToPlayer() {
    final nav = _navigatorKey.currentState;
    final mp = _player;
    if (nav == null || mp == null) return;
    nav.popUntil((route) => route.isFirst);
    nav.push(MaterialPageRoute(builder: (_) => PlayerScreen(player: mp)));
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

  /// v62 Phase 1: a Max Player notification was tapped. Phase 1 only routes
  /// the payload and confirms it arrived; later phases (AI-subs-ready,
  /// continue watching, new episodes) attach real deep-link handling here.
  void _handleNotificationTap(String payload) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('Notification: $payload'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _player?.dispose();
    library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mp = _player;
    // Rebuild the whole app when the accent color changes.
    return AnimatedBuilder(
      animation: themeState,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
          title: 'Max Player',
          debugShowCheckedModeBanner: false,
          // v60 CRASH FIX (his report: "Null check operator used on a null
          // value" in _onUnknownRoute): when Android pushes a route the
          // app does not know (task restore / back stack / plugin intent),
          // pushNamed returned null and Flutter crashed with a null-check.
          // Unknown routes now land on the normal home screen.
          onUnknownRoute: (settings) => MaterialPageRoute(
            builder: (_) => mp == null
                ? _StartupFailureScreen(error: _playerError)
                : LibraryScreen(library: library, player: mp),
          ),
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0a0a0f),
            colorScheme: ColorScheme.fromSeed(
              seedColor: themeState.accent,
              brightness: Brightness.dark,
            ),
          ),
          home: mp == null
              ? _StartupFailureScreen(error: _playerError)
              : LibraryScreen(library: library, player: mp),
        );
      },
    );
  }
}

/// v37: shown if the playback engine itself failed to initialise (e.g. its
/// native library could not load on this device). Much better than a silent
/// "has stopped": the reason is visible + copyable, and the startup trace
/// file pinpoints the exact stage.
class _StartupFailureScreen extends StatelessWidget {
  final Object? error;

  const _StartupFailureScreen({this.error});

  @override
  Widget build(BuildContext context) {
    final detail = error?.toString() ?? 'unknown error';
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 56),
              const SizedBox(height: 16),
              const Text(
                'The video engine failed to start on this phone',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              const Text(
                'Please send this text + the file\n'
                'Android/data/com.hypertechlabs.maxplayer/files/maxplayer_start.log\n'
                'to the developer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: detail)),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy error'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
MAXV62_EOF_MAIN_DART
echo "  wrote lib/main.dart"
mkdir -p "$(dirname "lib/widgets/about_sheet.dart")"
cat > "lib/widgets/about_sheet.dart" <<'MAXV62_EOF_ABOUT_SHEET_DART'
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/native_bridge.dart';
import '../state/theme_state.dart';
import '../utils/privacy_policy.dart';

/// "About Max Player" sheet, opened from the home screen's ⋮ menu.
/// Brand copy by Hyper Tech Labs. Static content - no platform calls.
class AboutSheet extends StatelessWidget {
  final ScrollController? scrollController;

  const AboutSheet({super.key, this.scrollController});

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
            AboutSheet(scrollController: controller),
      ),
    );
  }

  /// v62 Phase 1: asks for the notification permission once (Android 13+)
  /// and posts a simple test notification. Tapping it should bring the app
  /// back and show a "Notification: test:hello" snackbar - proving the whole
  /// permission -> channel -> tap pipeline works for later phases.
  Future<void> _sendTestNotification(BuildContext context) async {
    final granted = await NativeBridge.requestNotifications();
    if (!context.mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifications are blocked - enable them in '
              'Android settings > App notifications'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await NativeBridge.showNotification(
      channel: NotificationChannels.general,
      title: 'Max Player notifications are on',
      body: 'Tap this to return to the app. AI subtitle alerts and new-'
          'episode updates will appear here soon.',
      payload: 'test:hello',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test notification sent - check your status bar'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
        // Brand header.
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.play_circle_fill, color: accent, size: 32),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Max Player',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'by Hyper Tech Labs',
                  style: TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Max Player is a next-generation media player designed to make '
          'watching and listening effortless. Built from the ground up with '
          'performance, simplicity, and reliability in mind, Max Player '
          'brings together powerful playback technology and a clean, '
          'intuitive interface - so you can focus on your content, not on '
          'fighting with your player.\n\n'
          'Whether you\'re binge-watching your favorite series, enjoying '
          'high-definition movies, or listening to music on the go, Max '
          'Player is engineered to handle it all smoothly, without lag, '
          'crashes, or unnecessary clutter.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        _Heading('Our mission', accent),
        const Text(
          'At Max Player, our goal is simple: to create the most seamless, '
          'distraction-free media experience possible. We believe great '
          'software should feel invisible - it should just work, every time, '
          'without getting in your way. That philosophy drives every design '
          'and engineering decision behind Max Player.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        _Heading('Key features', accent),
        for (final f in _features)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 16, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: '${f.$1} - ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: f.$2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        _Heading('Our story', accent),
        const Text(
          'Max Player was created out of a simple frustration: too many '
          'media players were bloated, slow, or filled with intrusive ads '
          'and unnecessary features. We set out to build something '
          'different - a player that respects your time, your device, and '
          'your experience.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        _Heading('The team behind Max Player', accent),
        const Text(
          'Max Player is proudly developed and maintained by Hyper Tech '
          'Labs, a technology company focused on building thoughtful, '
          'high-quality applications for everyday use. Founded by Aryan '
          'Shah, Hyper Tech Labs is driven by a passion for clean design, '
          'efficient engineering, and solving real problems through '
          'software.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        _Heading('Looking ahead', accent),
        const Text(
          'We\'re constantly working to improve Max Player - adding new '
          'features, refining performance, and listening closely to our '
          'users. This is just the beginning, and we\'re excited to keep '
          'building a player that truly puts you first.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        const SizedBox(height: 22),
        const Divider(color: Colors.white12),
        const SizedBox(height: 6),
        // v62 Phase 1: lets the user verify the notification foundation
        // (permission prompt + channel + tap delivery) on their phone. Later
        // phases replace this with the real AI-subs / continue-watching
        // notifications.
        Center(
          child: TextButton.icon(
            onPressed: () => _sendTestNotification(context),
            icon: const Icon(Icons.notifications_active_outlined, size: 16),
            label: const Text('Send a test notification'),
            style: TextButton.styleFrom(
              foregroundColor: accent,
              textStyle: const TextStyle(fontSize: 12.5),
            ),
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: () => showPrivacyPolicyDialog(context),
            icon: const Icon(Icons.privacy_tip_outlined, size: 16),
            label: const Text('Privacy policy'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
              textStyle: const TextStyle(fontSize: 12.5),
            ),
          ),
        ),
        const Center(
          child: Text(
            'Version $kAppVersion',
            style: TextStyle(color: Colors.white38, fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 4),
        // Phase-1 verification: proves the offline whisper.cpp engine
        // bundled in this build actually loads on this device.
        Center(
          child: FutureBuilder<String?>(
            future: NativeBridge.whisperEngineStatus(),
            builder: (context, snap) {
              final ready = snap.hasData && snap.data != null;
              return Text(
                ready
                    ? 'AI subtitle engine: ready (offline & free)'
                    : 'AI subtitle engine: unavailable on this build',
                style: TextStyle(
                  color: ready
                      ? Colors.greenAccent.withValues(alpha: 0.7)
                      : Colors.white24,
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  final Color accent;
  const _Heading(this.text, this.accent);

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

const List<(String, String)> _features = [
  (
    'Universal Format Support',
    'Play almost any video or audio file without needing extra codecs or '
        'converters.'
  ),
  (
    'Smooth, High-Performance Playback',
    'Optimized for speed and stability, even with large or high-resolution '
        'files.'
  ),
  (
    'Clean, Intuitive Interface',
    'A minimal design that keeps the focus on your content.'
  ),
  (
    'Customizable Controls',
    'Adjust playback speed, subtitles, audio tracks, and more to fit your '
        'preferences.'
  ),
  (
    'Lightweight & Efficient',
    'Built to run smoothly without draining your device\'s resources.'
  ),
  (
    'Regular Updates',
    'Continuously improved based on user feedback and evolving technology.'
  ),
];
MAXV62_EOF_ABOUT_SHEET_DART
echo "  wrote lib/widgets/about_sheet.dart"
mkdir -p "$(dirname "test/widget_test.dart")"
cat > "test/widget_test.dart" <<'MAXV62_EOF_WIDGET_TEST_DART'
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/app_info.dart';
import 'package:maxplayer/cast/cast_support.dart';
import 'package:maxplayer/screens/player_screen.dart';
import 'package:maxplayer/models/playlist.dart';
import 'package:maxplayer/models/saved_server.dart';
import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/services/native_bridge.dart';
import 'package:maxplayer/services/tmdb_client.dart';
import 'package:maxplayer/widgets/tmdb_image.dart';
import 'package:maxplayer/services/movie_ai.dart';
import 'package:maxplayer/services/ai_suggest.dart';
import 'package:maxplayer/services/subtitle_langs.dart';
import 'package:maxplayer/widgets/video_search_delegate.dart';
import 'package:maxplayer/widgets/video_thumb.dart';
import 'package:maxplayer/state/media_player_state.dart';
import 'package:maxplayer/state/video_zoom.dart';
import 'package:maxplayer/state/player_settings.dart';
import 'package:maxplayer/state/playlist_store.dart';
import 'package:maxplayer/utils/movie_match.dart';
import 'package:maxplayer/state/private_vault.dart';
import 'package:maxplayer/state/theme_state.dart';
import 'package:maxplayer/state/video_library_state.dart';
import 'package:maxplayer/utils/ai_subtitles.dart';
import 'package:maxplayer/utils/cleaner_stats.dart';
import 'package:maxplayer/utils/crash_log.dart';
import 'package:maxplayer/utils/formatters.dart';
import 'package:maxplayer/utils/privacy_policy.dart';
import 'package:maxplayer/utils/sha256.dart';
import 'package:maxplayer/utils/srt.dart';
import 'package:maxplayer/widgets/karaoke_subtitle.dart';
import 'package:maxplayer/widgets/about_sheet.dart';
import 'package:maxplayer/widgets/track_selection_sheet.dart';
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
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('detects video extensions case-insensitively', () {
      expect(isVideoFile('clip.MKV'), isTrue);
      expect(isVideoFile('movie.mp4'), isTrue);
      expect(isVideoFile('notes.txt'), isFalse);
    });

    test('covers the extension set advertised in the manifest', () {
      // Keep in sync with the pathPatterns in AndroidManifest.xml.
      for (final ext in [
        'mp4',
        'webm',
        'mkv',
        'avi',
        'mov',
        'wmv',
        'flv',
        'm4v',
        '3gp',
        '3gpp',
        'ogv',
        'ts',
        'mts',
        'm2ts',
        'vob',
        'mpg',
        'mpeg',
        'rmvb',
        'divx',
        'f4v',
      ]) {
        expect(
          isVideoFile('movie.$ext'),
          isTrue,
          reason: '.$ext must scan into the library',
        );
        expect(isVideoFile('movie.${ext.toUpperCase()}'), isTrue);
      }
    });

    test('timeAgo buckets', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(timeAgo(now), 'Just now');
      expect(
        timeAgo(now - const Duration(minutes: 5).inMilliseconds),
        '5m ago',
      );
      expect(timeAgo(now - const Duration(hours: 3).inMilliseconds), '3h ago');
      expect(timeAgo(now - const Duration(days: 2).inMilliseconds), '2d ago');
      expect(timeAgo(0), '');
    });
  });

  group('quality label', () {
    String? q(int? w, int? h) => VideoTrack(
      id: 'x',
      title: 'x',
      path: '/x.mp4',
      width: w,
      height: h,
    ).qualityLabel;

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
      final f = MediaPlayerState.buildEqualizerFilter([6, 0, -2, 0, 3.5]);
      expect(
        f,
        'lavfi=[equalizer=f=60:t=q:w=1.0:g=6.0,equalizer=f=910:t=q:w=1.0:g=-2.0,equalizer=f=14000:t=q:w=1.0:g=3.5]',
      );
    });
  });

  group('watch stats', () {
    test('stats key is a sortable YYYYMMDD bucket', () {
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 8, 11)),
        'stats.20260811',
      );
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 1, 5)),
        'stats.20260105',
      );
    });

    test('formatWatchTime', () {
      expect(formatWatchTime(30), '30s');
      expect(formatWatchTime(45 * 60), '45m');
      expect(formatWatchTime(2 * 3600 + 15 * 60), '2h 15m');
    });
  });

  group('library sorting', () {
    final videos = [
      _track(
        'banana',
        size: 300,
        modified: 100,
        duration: const Duration(minutes: 3),
      ),
      _track(
        'apple',
        size: 100,
        modified: 300,
        duration: const Duration(minutes: 1),
      ),
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
      const dg =
          'HTTP/1.1 200 OK\r\n'
          'CACHE-CONTROL: max-age=1800\r\n'
          'LOCATION: http://192.168.1.10:8080/dd.xml\r\n'
          'location: http://other/x.xml\r\n' // duplicate -> first wins
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n';
      expect(ssdpHeader(dg, 'location'), 'http://192.168.1.10:8080/dd.xml');
      expect(
        ssdpHeader(dg, 'ST'),
        'urn:schemas-upnp-org:device:MediaRenderer:1',
      );
      expect(ssdpHeader(dg, 'server'), isNull);
    });

    test('M-SEARCH request is well formed', () {
      final m = buildMSearchRequest('ssdp:all');
      expect(m.startsWith('M-SEARCH * HTTP/1.1\r\n'), isTrue);
      expect(m, contains('ST: ssdp:all\r\n'));
      expect(m.endsWith('\r\n\r\n'), isTrue);
    });

    test('device description: finds AVTransport and resolves relative URL', () {
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
      const xml =
          '<root><device><friendlyName>Router</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>'
          '<controlURL>/wan/control</controlURL>'
          '</service></serviceList></device></root>';
      expect(parseDeviceDescription(xml, 'http://10.0.0.1/d.xml'), isNull);
    });

    test('absolute controlURL kept as-is; xml entities unescaped in name', () {
      const xml =
          '<root><device><friendlyName>A &amp; B TV</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>'
          '<controlURL>http://192.168.1.5:81/avt</controlURL>'
          '</service></serviceList></device></root>';
      final d = parseDeviceDescription(xml, 'http://192.168.1.5:9999/dd');
      expect(d!.name, 'A & B TV');
      expect(d.controlUrl, 'http://192.168.1.5:81/avt');
    });

    test('SOAP envelope carries InstanceID first and escapes args', () {
      final env = buildSoapEnvelope('Play', const [MapEntry('Speed', '1')]);
      expect(
        env,
        contains(
          '<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">',
        ),
      );
      expect(
        env.indexOf('<InstanceID>0</InstanceID>'),
        lessThan(env.indexOf('<Speed>1</Speed>')),
      );
      final esc = buildSoapEnvelope('X', const [MapEntry('V', 'a & <b> "q"')]);
      expect(esc, contains('a &amp; &lt;b&gt; &quot;q&quot;'));
    });

    test('soapTag digs values out of responses', () {
      const body =
          '<s:Envelope><s:Body><u:GetPositionInfoResponse>'
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
        title: 't',
        videoUrl: 'http://p/v.mp4',
        mime: 'video/mp4',
      );
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
      expect(
        formatRelTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatRelTime(Duration.zero), '0:00:00');
      expect(parseRelTime('0:06:12'), const Duration(minutes: 6, seconds: 12));
      expect(
        parseRelTime('1:02:03.500'),
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
      );
      expect(parseRelTime('NOT_IMPLEMENTED'), isNull);
      expect(parseRelTime(null), isNull);
      expect(parseRelTime('garbage'), isNull);
    });
  });

  group('app version', () {
    test('kAppVersion matches the pubspec version name', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(
        r'^version:\s*([0-9][0-9.]*)\+',
        multiLine: true,
      ).firstMatch(pub);
      expect(
        m,
        isNotNull,
        reason: 'pubspec.yaml must declare version: x.y.z+N',
      );
      expect(
        m!.group(1),
        kAppVersion,
        reason: 'Keep kAppVersion in lib/app_info.dart in sync',
      );
    });
  });

  group('AI subtitle options & caption filter (v18)', () {
    // v54: back on-device - accurate whisper models; stale ids migrate.
    test('only accurate models remain; stale tiny ids map to base', () {
      expect(AiSubtitleRunner.modelChoices.containsKey('tiny'), isFalse);
      expect(
        AiSubtitleRunner.modelChoices.keys,
        containsAll(<String>['base', 'small']),
      );
      expect(AiSubtitleRunner.normalizeModelId(null), 'base');
      expect(
        AiSubtitleRunner.normalizeModelId('tiny'),
        'base',
        reason: 'a stale v22-24 "tiny" pref must migrate to base',
      );
      expect(AiSubtitleRunner.normalizeModelId('small'), 'small');
      expect(AiSubtitleRunner.normalizeModelId('nonsense'), 'base');
      expect(AiSubtitleRunner.modelSizeLabel('base'), '~142 MB');
      expect(AiSubtitleRunner.modelSizeLabel('small'), '~466 MB');
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
        expect(
          kPrivacyPolicyText,
          contains(anchor),
          reason:
              'keep lib/utils/privacy_policy.dart in sync with '
              'PRIVACY_POLICY.md',
        );
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

    testWidgets('every gesture illustration paints without errors', (
      tester,
    ) async {
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
        find.byType(GestureIllustration),
        findsNWidgets(GestureKind.values.length),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('user manual renders all sections', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: UserManualSheet())),
      );
      expect(find.text('User manual'), findsOneWidget);
      expect(find.text('GESTURE CONTROLS'), findsOneWidget);
      expect(
        find.text('Max Player v$kAppVersion  ·  Hyper Tech Labs'),
        findsOneWidget,
      );
      expect(
        find.byType(GestureIllustration),
        findsNWidgets(GestureKind.values.length),
      );
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

    testWidgets('about sheet bundles the privacy policy offline', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AboutSheet())),
      );
      await tester.tap(find.text('Privacy policy'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not collect, store, transmit'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not collect, store, transmit'),
        findsNothing,
      );
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
        '1\n00:00:01.000 --> 00:00:02.500\none two\n\n00:00:03,000 --> 00:00:04,000\nthree\n',
      );
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
        computeSkipIntro([const SrtCue(700000, 701000, 'Too late')]),
        isNull,
      );
      expect(computeSkipIntro(const []), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // v21: SHA-256 for the Private-folder PIN (dependency-free implementation)
  // -------------------------------------------------------------------------
  group('v21 sha256', () {
    test('standard test vectors', () {
      expect(
        sha256Hex(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha256Hex('1234'),
        '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4',
      );
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
      expect(sidecarSrtCandidates(names, '/sdcard/Movies/Movie.mp4'), [
        'Movie.SRT',
        'movie.eng.srt',
      ]);
    });
    test('AI sidecar is never picked as a plain sidecar', () {
      final names = ['movie.maxai.srt'];
      expect(sidecarSrtCandidates(names, '/a/movie.mkv'), isEmpty);
    });
    test('language variants are sorted and kept in original case', () {
      final names = ['movie.hi.srt', 'movie.en.srt'];
      expect(sidecarSrtCandidates(names, 'movie.mkv'), [
        'movie.en.srt',
        'movie.hi.srt',
      ]);
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

  // -------------------------------------------------------------------------
  // v26: karaoke fix (media_kit's own subtitle layer is off), karaoke switch
  // lives ONLY in the tracks sheet, vault change counter + device-unlock gate
  // for the forgotten-PIN flow.
  // -------------------------------------------------------------------------
  group('v26 polish', () {
    test('vault revision counter exists and starts clean in tests', () {
      // hide()/unhide() do real file IO (not exercised here), so the
      // in-process counter must still be zero.
      expect(PrivateVault.revision, 0);
    });

    test('vault path helpers unchanged', () {
      expect(
        PrivateVault.isPrivatePath(
          '/storage/emulated/0/Android/data/com.hypertechlabs.maxplayer/'
          'files/Private/movie.mp4',
        ),
        isTrue,
      );
      expect(
        PrivateVault.isPrivatePath('/storage/emulated/0/Movies/movie.mp4'),
        isFalse,
      );
    });

    test('karaoke setting survives copyWith (toggle kept, moved)', () {
      const s = PlayerSettings();
      expect(s.karaokeSubs, isFalse);
      expect(s.copyWith(karaokeSubs: true).karaokeSubs, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // v27: advanced video info + statistics helpers
  // -------------------------------------------------------------------------
  group('v27 advanced info + stats', () {
    test('formatAspectRatio simplifies common ratios', () {
      expect(formatAspectRatio(1920, 1080), '16:9');
      expect(formatAspectRatio(1280, 720), '16:9');
      expect(formatAspectRatio(1440, 1080), '4:3');
      expect(formatAspectRatio(3840, 2160), '16:9');
    });

    test('formatAspectRatio falls back for odd sizes and guards zero', () {
      expect(formatAspectRatio(1000, 423), '2.36:1');
      expect(formatAspectRatio(0, 1080), '');
      expect(formatAspectRatio(1920, 0), '');
    });

    test('statsKeyFor day buckets stay stable', () {
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 8, 14)),
        'stats.20260814',
      );
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 1, 5)),
        'stats.20260105',
      );
    });
  });

  // -------------------------------------------------------------------------
  // v28: home quick tiles - the Folders tile filters the library
  // -------------------------------------------------------------------------
  group('v28 folders tile', () {
    VideoTrack t(String path) =>
        VideoTrack(id: path, title: path.split('/').last, path: path);

    List<VideoTrack> threeVideos() => [
      t('/storage/emulated/0/Movies/a.mp4'),
      t('/storage/emulated/0/Movies/b.mp4'),
      t('/storage/emulated/0/DCIM/c.mp4'),
    ];

    test('folderFilter narrows the visible list and clears again', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos(threeVideos());
      expect(lib.videos.length, 3);
      lib.setFolderFilter('Movies');
      expect(lib.videos.length, 2);
      expect(lib.videos.map((v) => v.folderName).toSet(), {'Movies'});
      lib.setFolderFilter(null);
      expect(lib.videos.length, 3);
    });

    test('folderCounts lists every folder, name-sorted', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos(threeVideos());
      expect(lib.folderCounts, {'DCIM': 1, 'Movies': 2});
      expect(lib.folderCounts.keys.toList(), ['DCIM', 'Movies']);
    });

    test('folder filter composes with search', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos(threeVideos());
      lib.setFolderFilter('Movies');
      lib.setSearchQuery('b.mp4');
      expect(lib.videos.length, 1);
      expect(lib.videos.single.path, endsWith('/Movies/b.mp4'));
    });
  });

  // -------------------------------------------------------------------------
  // v29: device cleaner data + playlist/picker backing + white default theme
  // -------------------------------------------------------------------------
  group('v29 cleaner data + theme default', () {
    VideoTrack sized(String path, int size, int secs) => VideoTrack(
      id: path,
      title: path.split('/').last,
      path: path,
      sizeBytes: size,
      duration: Duration(seconds: secs),
    );

    test('largestVideos sorts biggest first and limits', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos([
        sized('/s/Movies/small.mp4', 100, 60),
        sized('/s/Movies/big.mp4', 9000, 900),
        sized('/s/DCIM/mid.mp4', 500, 120),
      ]);
      final top = lib.largestVideos(n: 2);
      expect(top.length, 2);
      expect(top.first.path, endsWith('big.mp4'));
      expect(top.last.path, endsWith('mid.mp4'));
    });

    test('duplicateGroups finds same size+duration copies only', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos([
        sized('/s/Movies/a.mp4', 700, 300),
        sized('/s/DCIM/a-copy.mp4', 700, 300), // same size+length = dupe
        sized('/s/Movies/a-lookalike.mp4', 700, 301), // different length
        sized('/s/Movies/unique.mp4', 42, 10),
      ]);
      final groups = lib.duplicateGroups;
      expect(groups.length, 1);
      expect(groups.single.length, 2);
      expect(
        groups.single.map((v) => v.path),
        containsAll(['/s/Movies/a.mp4', '/s/DCIM/a-copy.mp4']),
      );
    });

    test('removeVideo drops an entry in place', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos([
        sized('/s/Movies/a.mp4', 700, 300),
        sized('/s/Movies/b.mp4', 500, 300),
      ]);
      lib.removeVideo('/s/Movies/a.mp4');
      expect(lib.videos.length, 1);
      expect(lib.videos.single.path, endsWith('b.mp4'));
    });

    test('white is the default theme colour (existing picks kept)', () {
      expect(ThemeState().accent.toARGB32(), 0xFFFFFFFF);
      expect(ThemeState.defaultAccent.toARGB32(), 0xFFFFFFFF);
      // purple and the others remain selectable
      expect(ThemeState.swatches.length, 7);
    });
  });

  group('v30 playlist add-to-queue', () {
    VideoTrack vt(String path) =>
        VideoTrack(id: path, title: path.split('/').last, path: path);

    test('mergeQueueVideos appends new, skips duplicates, keeps order', () {
      final merged = mergeQueueVideos(
        [vt('/s/a.mp4'), vt('/s/b.mp4')],
        [vt('/s/b.mp4'), vt('/s/c.mp4'), vt('/s/a.mp4')],
      );
      expect(merged.map((v) => v.path).toList(), [
        '/s/a.mp4',
        '/s/b.mp4',
        '/s/c.mp4',
      ]);
    });

    test('mergeQueueVideos into an empty queue returns the picks', () {
      final merged = mergeQueueVideos(const [], [vt('/s/x.mp4')]);
      expect(merged.single.path, '/s/x.mp4');
    });

    test('mergeQueueVideos does not mutate the original queue', () {
      final queue = [vt('/s/a.mp4')];
      mergeQueueVideos(queue, [vt('/s/b.mp4')]);
      expect(queue.length, 1);
    });
  });

  group('v31 cleaner stats', () {
    test('segments drop empty kinds and keep a stable order', () {
      final segs = cleanerSegments(
        thumbs: 100,
        strips: 0,
        temp: 50,
        models: 0,
        deviceCache: 25,
      );
      expect(segs.map((s) => s.label).toList(), [
        'App thumbnails',
        'Temporary AI files',
        'Gallery cache',
      ]);
    });

    test('segment colours are stable per kind', () {
      final segs = cleanerSegments(
        thumbs: 1,
        strips: 2,
        temp: 3,
        models: 4,
        deviceCache: 5,
      );
      expect(segs[0].colorValue, cleanerKindColors['thumbs']);
      expect(segs[3].colorValue, cleanerKindColors['models']);
      // AI models keep their colour even when earlier kinds are empty.
      final lonely = cleanerSegments(
        thumbs: 0,
        strips: 0,
        temp: 0,
        models: 9,
        deviceCache: 0,
      );
      expect(lonely.single.colorValue, cleanerKindColors['models']);
    });

    test('clean cache total excludes models, grand total includes them', () {
      final cache = cleanerCacheTotal(
        thumbs: 10,
        strips: 10,
        temp: 10,
        deviceCache: 10,
      );
      final grand = cleanerGrandTotal(
        thumbs: 10,
        strips: 10,
        temp: 10,
        models: 7,
        deviceCache: 10,
      );
      expect(cache, 40);
      expect(grand, 47);
    });

    test('fractionOf guards an empty graph', () {
      const seg = CleanerSegment('x', 5, 0xFF000000);
      expect(seg.fractionOf(0), 0);
      expect(seg.fractionOf(20), 0.25);
    });

    test('DeviceStorage used + usedFraction are sane', () {
      const s = DeviceStorage(total: 100, free: 25);
      expect(s.used, 75);
      expect(s.usedFraction, 0.75);
    });
  });

  group('v32 picture settings, HDR labels and saved servers', () {
    test('hdrLabelFor maps known formats, hides SDR/unknown', () {
      expect(hdrLabelFor('hdr10'), 'HDR10');
      expect(hdrLabelFor('hdr10+'), 'HDR10+');
      expect(hdrLabelFor('hlg'), 'HLG');
      expect(hdrLabelFor('dolby-vision'), 'Dolby Vision (HDR mode)');
      expect(hdrLabelFor('sdr'), isNull);
      expect(hdrLabelFor(null), isNull);
      expect(hdrLabelFor('nonsense'), isNull);
    });

    test('picture settings default to off/auto and survive copyWith', () {
      const s = PlayerSettings();
      expect(s.enhanceVideo, isFalse);
      expect(s.toneMapping, 'auto');
      expect(PlayerSettings.kToneMappingModes, contains('bt.2390'));
      final on = s.copyWith(enhanceVideo: true, toneMapping: 'mobius');
      expect(on.enhanceVideo, isTrue);
      expect(on.toneMapping, 'mobius');
      expect(on.doubleTapSeek, isTrue); // untouched keys preserved
    });

    test('saved servers parse, round-trip, and junk is dropped', () {
      expect(parseServersJson(null), isEmpty);
      expect(parseServersJson(''), isEmpty);
      expect(parseServersJson('not json'), isEmpty);
      expect(parseServersJson('{"oops":true}'), isEmpty);
      const s = SavedServer(
        name: 'nas.local:5005',
        url: 'http://nas.local:5005/film.mkv',
      );
      final raw = serversToJson([s]);
      final back = parseServersJson(raw);
      expect(back.single.name, s.name);
      expect(back.single.url, s.url);
      // entries without a url are skipped, good ones kept
      final messy = parseServersJson(
        '[{"name":"x"},{"url":"rtsp://cam.local/live"}]',
      );
      expect(messy.single.url, 'rtsp://cam.local/live');
    });

    test('addSavedServer dedupes by url', () {
      const a = SavedServer(name: 'a', url: 'http://n.local/a.mkv');
      const dup = SavedServer(name: 'a2', url: 'http://n.local/a.mkv');
      final list = addSavedServer(addSavedServer(const [], a), dup);
      expect(list.length, 1);
      expect(list.single.name, 'a');
    });
  });

  group('v34 native crash reporter and track sheet sizing', () {
    test('trackSheetInitialSize never leaves the safe 0.4..0.8 band', () {
      for (final h in [320.0, 640.0, 800.0, 1280.0, 2400.0]) {
        for (var rows = 0; rows <= 40; rows++) {
          final f = trackSheetInitialSize(rows, h);
          expect(f, greaterThanOrEqualTo(0.4));
          expect(f, lessThanOrEqualTo(0.8));
        }
      }
    });

    test('trackSheetInitialSize grows with rows, guards bad heights', () {
      // Few rows on a tall screen -> the 40% floor (compact sheet).
      expect(trackSheetInitialSize(2, 2400), 0.4);
      // Many rows on a small/old phone -> the 80% cap; the sheet then
      // scrolls and can still be dragged up to 92%.
      expect(trackSheetInitialSize(30, 640), 0.8);
      // Degenerate heights can never produce NaN / Infinity.
      expect(trackSheetInitialSize(5, 0), 0.6);
      expect(trackSheetInitialSize(5, -1), 0.6);
    });

    test('takeLastIncludingNative simply finds nothing without a device',
        () async {
      // Unit tests have no method-channel native side: nativeCrashGet and
      // the settings store both guard, so the result is null - and it can
      // never throw, which is what matters at app start.
      expect(await CrashLog.takeLastIncludingNative(), isNull);
    });
  });

  group('v35 tune sheet (subtitles/audio/A-B/karaoke) opens fully', () {
    test('four rows size sanely in portrait AND landscape', () {
      // Small portrait phone: compact ~46% open, rows all visible.
      final portrait = trackSheetInitialSize(4, 800);
      expect(portrait, greaterThan(0.4));
      expect(portrait, lessThan(0.6));
      // Landscape/short screens (where the old half-height sheet cut the
      // A-B loop and karaoke rows): clamps to 80%, and everything stays
      // reachable because the sheet scrolls + drags up to 92%.
      expect(trackSheetInitialSize(4, 380), 0.8);
      expect(trackSheetInitialSize(4, 320), 0.8);
    });
  });

  group('v38 enhance decode mode + legacy storage permission', () {
    test('enhance ON switches to copy-back decode, OFF restores auto', () {
      // Direct hardware rendering silently skips user shaders (the "not
      // effective" bug); copy-back routes frames through the shader.
      expect(MediaPlayerState.enhanceHwdecFor(true), 'mediacodec-copy');
      expect(MediaPlayerState.enhanceHwdecFor(false), 'auto');
    });

    test('enhance hwdec constant matches the preference function', () {
      expect(
        MediaPlayerState.enhanceHwdecFor(true),
        MediaPlayerState.kEnhanceHwdec,
      );
    });
  });

  group('v40 named playlists + SD-card scanning', () {
    test('Playlist json round-trips (persistence format)', () {
      const pl = Playlist(
        id: '1712345678901234',
        name: 'Movies',
        videoPaths: ['/s/a.mp4', '/s/b.mkv'],
      );
      final back = Playlist.fromJson(pl.toJson());
      expect(back.id, pl.id);
      expect(back.name, pl.name);
      expect(back.videoPaths, ['/s/a.mp4', '/s/b.mkv']);
    });

    test('Playlist json survives junk (missing fields, garbage list)', () {
      final back = Playlist.fromJson(const {'name': 'Songs'});
      expect(back.name, 'Songs');
      expect(back.videoPaths, isEmpty);
      final withJunk = Playlist.fromJson(const {
        'id': 'x',
        'name': 'N',
        'videoPaths': ['/ok.mp4', 7, null],
      });
      expect(withJunk.videoPaths.first, '/ok.mp4');
      expect(withJunk.videoPaths.length, 3); // garbage stringifies, never throws
    });

    test('mergePlaylistPaths appends new, skips duplicates, keeps order', () {
      final merged = mergePlaylistPaths(
        ['/s/a.mp4', '/s/b.mp4'],
        ['/s/b.mp4', '/card/c.mp4', '/s/a.mp4'],
      );
      expect(merged, ['/s/a.mp4', '/s/b.mp4', '/card/c.mp4']);
    });

    test('mergePlaylistPaths does not mutate the input list', () {
      final existing = ['/s/a.mp4'];
      mergePlaylistPaths(existing, ['/s/b.mp4']);
      expect(existing.length, 1);
    });

    test('validatePlaylistName trims, rejects blank/too long, accepts names', () {
      expect(validatePlaylistName('   '), isNotNull);
      expect(validatePlaylistName(''), isNotNull);
      expect(validatePlaylistName('x' * 41), isNotNull);
      expect(validatePlaylistName('  Movies  '), isNull);
      expect(validatePlaylistName('Bhakti Songs'), isNull);
    });

    test('normalizeStorageRoots dedupes, strips slashes, keeps order', () {
      final roots = normalizeStorageRoots([
        '/storage/emulated/0/',
        '/storage/1C4B-9A2F',
        '/storage/emulated/0', // same as first after slash-strip
        '',
        '/',
        '  /storage/1C4B-9A2F  ', // same as second after trim
      ]);
      expect(roots, ['/storage/emulated/0', '/storage/1C4B-9A2F']);
    });

    test('normalizeStorageRoots falls back to internal storage when empty', () {
      expect(normalizeStorageRoots(const []), ['/storage/emulated/0']);
      expect(normalizeStorageRoots(const ['', '/']), ['/storage/emulated/0']);
    });
  });

  group('v41 system bars follow the video', () {
    test('landscape hides the bars even when fullscreen was never pressed', () {
      expect(
        playerSystemUiModeFor(fullscreen: false, landscape: true),
        SystemUiMode.immersiveSticky,
      );
    });

    test('manual fullscreen hides the bars in any orientation', () {
      expect(
        playerSystemUiModeFor(fullscreen: true, landscape: false),
        SystemUiMode.immersiveSticky,
      );
      expect(
        playerSystemUiModeFor(fullscreen: true, landscape: true),
        SystemUiMode.immersiveSticky,
      );
    });

    test('portrait without fullscreen keeps the bars (time, notifications)',
        () {
      expect(
        playerSystemUiModeFor(fullscreen: false, landscape: false),
        SystemUiMode.edgeToEdge,
      );
    });
  });

  group('v42 compatibility manifest', () {
    // These guards read the REAL AndroidManifest.xml (test CWD = package
    // root) so a future edit can never silently drop the compatibility
    // fixes again.
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('Android 10 raw-path storage: legacy flag + WRITE permission', () {
      expect(
        manifest.contains('android:requestLegacyExternalStorage="true"'),
        isTrue,
      );
      expect(
        manifest.contains('android.permission.WRITE_EXTERNAL_STORAGE'),
        isTrue,
      );
      // WRITE applies to Android 10 and older; newer versions use
      // All-files-access / per-app dirs instead.
      expect(manifest.contains('android:maxSdkVersion="29"'), isTrue);
    });

    test('http video streams: cleartext traffic explicitly allowed', () {
      expect(manifest.contains('android:usesCleartextTraffic="true"'), isTrue);
    });

    test('installable on Android TV / non-touch devices', () {
      expect(manifest.contains('android.hardware.touchscreen'), isTrue);
      expect(manifest.contains('android:required="false"'), isTrue);
    });
  });

  group('v43 Discover (TMDB) - legal movie discovery', () {
    const trendingJson = '{"results":['
        '{"id":27205,"title":"Inception","release_date":"2010-07-15",'
        '"vote_average":8.365,"poster_path":"/abc.jpg","overview":"Dreams."},'
        '{"id":"bad","title":"","vote_average":"x"},'
        '{"id":603,"title":"The Matrix","release_date":"1999-03-30",'
        '"vote_average":8.2,"poster_path":null,"overview":"Neo."}'
        ']}';

    test('parseTmdbList keeps good rows, skips junk, never throws', () {
      final movies = parseTmdbList(trendingJson);
      expect(movies.length, 2);
      expect(movies.first.title, 'Inception');
      expect(movies.first.year, 2010);
      expect(movies.first.rating, closeTo(8.365, 0.001));
      expect(movies.last.posterPath, isNull);
      expect(parseTmdbList('not json at all'), isEmpty);
      expect(parseTmdbList('{"results": 42}'), isEmpty);
    });

    test('pickTrailerKey prefers official YouTube trailer, falls back well',
        () {
      final videos = {
        'results': [
          {'site': 'Vimeo', 'type': 'Trailer', 'key': 'vimeo1'},
          {'site': 'YouTube', 'type': 'Teaser', 'key': 'teaser1'},
          {
            'site': 'YouTube',
            'type': 'Trailer',
            'official': true,
            'key': 'official1'
          },
        ]
      };
      expect(pickTrailerKey(videos), 'official1');
      expect(
        pickTrailerKey({
          'results': [
            {'site': 'YouTube', 'type': 'Clip', 'key': 'clip1'}
          ]
        }),
        'clip1',
      );
      expect(pickTrailerKey({'results': []}), isNull);
      expect(pickTrailerKey('garbage'), isNull);
    });

    test('rating badge + poster url formatting', () {
      expect(tmdbRatingText(8.365), '8.4');
      expect(tmdbRatingText(7.0), '7.0');
      expect(
        tmdbPosterUrl('/abc.jpg'),
        'https://image.tmdb.org/t/p/w342/abc.jpg',
      );
      expect(
        tmdbPosterUrl('/abc.jpg', big: true),
        'https://image.tmdb.org/t/p/w500/abc.jpg',
      );
      expect(tmdbPosterUrl(null), isEmpty);
    });

    test('normalizeMovieTitle strips quality/codec junk and years', () {
      expect(
        normalizeMovieTitle('Interstellar.2014.1080p.BluRay.x265'),
        'interstellar',
      );
      expect(normalizeMovieTitle('3_Idiots_2009_HD'), '3 idiots');
      expect(normalizeMovieTitle('The Dark Knight (2008) [1080p]'),
          'the dark knight');
    });

    test('findLocalMovie prefers the year-matching copy, falls back by title',
        () {
      VideoTrack vt(String path) => VideoTrack(
            id: path,
            title: path.split('/').last.replaceAll('.mkv', ''),
            path: path,
          );
      final lib = [
        vt('/s/Dune.Part.One.1080p.WEB-DL.mkv'),
        vt('/s/Interstellar.2014.1080p.BluRay.x265.mkv'),
      ];
      expect(
        findLocalMovie('Interstellar', 2014, lib)?.path,
        '/s/Interstellar.2014.1080p.BluRay.x265.mkv',
      );
      // Year mismatch / unknown year still falls back to the title hit.
      expect(findLocalMovie('Interstellar', null, lib), isNotNull);
      expect(findLocalMovie('Dune Part One', null, lib)?.path,
          '/s/Dune.Part.One.1080p.WEB-DL.mkv');
      // STRICT title match: "Dune" must NOT match "Dune Part One" (they are
      // different movies - false positives would be worse than no match).
      expect(findLocalMovie('Dune', 2021, lib), isNull);
      expect(findLocalMovie('Titanic', 1997, lib), isNull);
    });
  });

  group('v44 Discover upgrades + status-bar overlap fix', () {
    test('tmdbImageCacheName is deterministic and collision-safe', () {
      const a = 'https://image.tmdb.org/t/p/w342/abc123.jpg';
      final name = tmdbImageCacheName(a);
      expect(tmdbImageCacheName(a), name); // stable across calls
      // Same photo, different SIZE folder -> different cache entry.
      expect(tmdbImageCacheName('https://image.tmdb.org/t/p/w500/abc123.jpg'),
          isNot(name));
      // Different photo -> different cache entry.
      expect(tmdbImageCacheName('https://image.tmdb.org/t/p/w342/xyz999.jpg'),
          isNot(name));
      expect(name.contains('abc123.jpg'), isTrue); // human-readable
    });

    test('kDiscoverFilters: many more filters than v43 (3 -> 12)', () {
      expect(kDiscoverFilters.length, greaterThan(10));
      expect(kDiscoverFilters.first.trending, isTrue);
      expect(
          kDiscoverFilters
              .any((f) => f.key == 'hollywood' && f.language == 'en'),
          isTrue);
      expect(
          kDiscoverFilters
              .any((f) => f.key == 'bollywood' && f.language == 'hi'),
          isTrue);
      expect(kDiscoverFilters.where((f) => f.genreId != null).length,
          greaterThanOrEqualTo(7));
    });

    test('tmdbDiscoverQuery: language filter vs genre filter, with paging', () {
      final hw = kDiscoverFilters.firstWhere((f) => f.key == 'hollywood');
      final q1 = tmdbDiscoverQuery(hw, 2);
      expect(q1['with_original_language'], 'en');
      expect(q1['page'], '2');
      expect(q1.containsKey('with_genres'), isFalse);
      final action = kDiscoverFilters.firstWhere((f) => f.key == 'action');
      final q2 = tmdbDiscoverQuery(action, 1);
      expect(q2['with_genres'], '28');
      expect(q2.containsKey('with_original_language'), isFalse);
      expect(q2['include_adult'], 'false');
    });

    test('tmdbSearchQuery + cache name: stable, distinct, safe', () {
      final q = tmdbSearchQuery('Dune Part Two', 3);
      expect(q['query'], 'Dune Part Two');
      expect(q['page'], '3');
      expect(q['include_adult'], 'false');
      final n1 = tmdbSearchCacheName('dune 2', 1);
      expect(tmdbSearchCacheName('dune 2', 1), n1);
      expect(tmdbSearchCacheName('dune 2', 2), isNot(n1)); // page matters
      expect(tmdbSearchCacheName('dune 3', 1), isNot(n1)); // query matters
    });

    test('parseTmdbPage paginates and caps TMDB at 500 pages (thousands)', () {
      const body = '{"page":2,"total_pages":99999,"total_results":1999800,'
          '"results":[{"id":5,"title":"X","vote_average":7.2,'
          '"poster_path":"/p.jpg","release_date":"2020-01-01"}]}';
      final page = parseTmdbPage(body);
      expect(page.items.single.title, 'X');
      expect(page.page, 2);
      expect(page.totalPages, 500); // TMDB's own maximum depth
      expect(page.totalResults, 1999800);
      final bad = parseTmdbPage('garbage');
      expect(bad.items, isEmpty);
      expect(bad.totalPages, 1);
    });

    test('parseTmdbExtras: director + cast + runtime + genres + votes', () {
      const body = '{"id":1,"title":"X","runtime":136,"tagline":"Dream.",'
          '"status":"Released","vote_count":24513,'
          '"genres":[{"name":"Sci-Fi"},{"name":"Adventure"}],'
          '"credits":{"crew":[{"job":"Director","name":"Christopher Nolan"}],'
          '"cast":[{"name":"Leonardo DiCaprio"},'
          '{"name":"Joseph Gordon-Levitt"}]}}';
      final x = parseTmdbExtras(body);
      expect(x.director, 'Christopher Nolan');
      expect(x.cast, ['Leonardo DiCaprio', 'Joseph Gordon-Levitt']);
      expect(x.runtimeMinutes, 136);
      expect(x.genres, ['Sci-Fi', 'Adventure']);
      expect(x.tagline, 'Dream.');
      expect(x.voteCount, 24513);
      expect(parseTmdbExtras('{}').director, isEmpty);
      expect(parseTmdbExtras('not json').cast, isEmpty);
    });

    test('formatRuntime + formatVoteCount', () {
      expect(formatRuntime(136), '2h 16m');
      expect(formatRuntime(45), '45m');
      expect(formatRuntime(120), '2h');
      expect(formatRuntime(0), '');
      expect(formatVoteCount(24513), '24,513');
      expect(formatVoteCount(8), '8');
    });

    test('filterLibraryItems: the pure filter behind the new search icon', () {
      const titles = ['Dune Part Two.mkv', 'Interstellar.mp4', 'dune trailer.mp4'];
      expect(filterLibraryItems(titles, 'dune', (t) => t).length, 2);
      expect(filterLibraryItems(titles, '  INTER ', (t) => t),
          ['Interstellar.mp4']);
      expect(filterLibraryItems(titles, '', (t) => t).length, 3);
    });

    test('leaving the player restores MANUAL bars (no status-bar overlap)', () {
      expect(playerRestoreSystemUiMode, SystemUiMode.manual);
      expect(playerRestoreOverlays, containsAll(SystemUiOverlay.values));
    });
  });

  group('v45 Discover reliability + screenshots + Ask with AI', () {
    test('parseTmdbScreenshots picks backdrop paths, caps count, never throws', () {
      const body = '{"id":1,"images":{"backdrops":['
          '{"file_path":"/s1.jpg"},{"file_path":"/s2.jpg"},'
          '{"file_path":""},{"file_path":"/s3.jpg"}]}}';
      final shots = parseTmdbScreenshots(body);
      expect(shots, ['/s1.jpg', '/s2.jpg', '/s3.jpg']); // empty skipped
      expect(parseTmdbScreenshots(body, count: 2), ['/s1.jpg', '/s2.jpg']);
      expect(parseTmdbScreenshots('{}'), isEmpty);
      expect(parseTmdbScreenshots('junk'), isEmpty);
    });

    test('tmdbScreenshotUrl builds the w500 backdrop URL', () {
      expect(tmdbScreenshotUrl('/abc.jpg'),
          'https://image.tmdb.org/t/p/w500/abc.jpg');
      expect(tmdbScreenshotUrl(''), '');
    });

    test('openRouterChatBody: model + restricted system + user question', () {
      final body = openRouterChatBody(
        model: kOpenRouterModels.first,
        system: movieAiSystemPrompt(const TmdbMovie(
            id: 1, title: 'Dune', rating: 8, year: 2021)),
        question: 'Is it worth watching?',
      );
      expect(body['model'], kOpenRouterModels.first);
      final messages = body['messages'] as List;
      expect((messages.first as Map)['role'], 'system');
      expect('${messages.first['content']}'.contains('ONLY'), isTrue);
      expect('${messages.first['content']}'.contains('Dune'), isTrue);
      expect((messages.last as Map)['role'], 'user');
    });

    test('parseOpenRouterAnswer extracts the text, null on junk', () {
      const ok = '{"choices":[{"message":{"role":"assistant",'
          '"content":"  Watch it in IMAX.  "}}]}';
      expect(parseOpenRouterAnswer(ok), 'Watch it in IMAX.');
      expect(parseOpenRouterAnswer('{"choices":[]}'), isNull);
      expect(parseOpenRouterAnswer('not json'), isNull);
    });

    test('Ask-with-AI stays FREE: 4 fallback models + many templates', () {
      expect(kOpenRouterModels.length, greaterThanOrEqualTo(4));
      for (final m in kOpenRouterModels) {
        expect(m.endsWith(':free'), isTrue);
      }
      expect(kMovieAiTemplates.length, greaterThanOrEqualTo(5));
    });
  });

  group('v46 watch providers + reviews + upcoming + ai cache', () {
    test('tmdbEndpointPath: trending vs upcoming vs discover', () {
      const tr =
          DiscoverFilter(key: 't', label: 'T', trending: true);
      const up = DiscoverFilter(key: 'u', label: 'U', upcoming: true);
      const hw =
          DiscoverFilter(key: 'hollywood', label: 'H', language: 'en');
      expect(tmdbEndpointPath(tr), '/3/trending/movie/week');
      expect(tmdbEndpointPath(up), '/3/movie/upcoming');
      expect(tmdbEndpointPath(hw), '/3/discover/movie');
      expect(kDiscoverFilters.any((f) => f.upcoming), isTrue);
    });

    test('parseTmdbWatchProviders splits stream/rent/buy for IN', () {
      const body = '{"watch/providers":{"results":{"IN":{'
          '"flatrate":[{"provider_name":"Netflix"},'
          '{"provider_name":"Amazon Prime Video"}],'
          '"rent":[{"provider_name":"YouTube"}],'
          '"buy":[{"provider_name":"Google Play Movies"}]},'
          '"US":{"flatrate":[{"provider_name":"Hulu"}]}}}}';
      final w = parseTmdbWatchProviders(body);
      expect(w.stream, ['Netflix', 'Amazon Prime Video']);
      expect(w.rent, ['YouTube']);
      expect(w.buy, ['Google Play Movies']);
      expect(w.isEmpty, isFalse);
      expect(parseTmdbWatchProviders(body, region: 'XX').isEmpty, isTrue);
      expect(parseTmdbWatchProviders('junk').isEmpty, isTrue);
    });

    test('parseTmdbReviews: real text, rating, caps, junk-safe', () {
      const body = '{"reviews":{"results":[{"author":"Aryan",'
          '"content":"  Loved   every   minute.  ",'
          '"author_details":{"rating":9}},'
          '{"author":"Second","content":"Decent timepass.",'
          '"author_details":{}}]}}';
      final r = parseTmdbReviews(body);
      expect(r.length, 2);
      expect(r.first.text, 'Loved every minute.'); // whitespace collapsed
      expect(r.first.rating, 9.0);
      expect(r.last.rating, isNull);
      expect(parseTmdbReviews('{}'), isEmpty);
      expect(parseTmdbReviews('junk'), isEmpty);
    });

    test('parseTmdbExtras includes spoken languages', () {
      const body = '{"id":1,"title":"X","spoken_languages":['
          '{"english_name":"English"},{"english_name":"Hindi"}]}';
      expect(parseTmdbExtras(body).spokenLanguages, ['English', 'Hindi']);
      expect(parseTmdbExtras('{}').spokenLanguages, isEmpty);
    });

    test('movieAiCacheName is deterministic per movie+question', () {
      final a = movieAiCacheName(693134, 'Is it good?');
      expect(movieAiCacheName(693134, 'Is it good?'), a);
      expect(movieAiCacheName(693134, 'is it good?'), a); // case/trim-safe
      expect(movieAiCacheName(693134, 'ending?'), isNot(a));
      expect(movieAiCacheName(550, 'Is it good?'), isNot(a));
      expect(a.startsWith('ai_answer_693134_'), isTrue);
    });
  });

  group('v47 real subtitles + all TMDB data + thumbnails', () {
    test('parseOpenSubLanguages: unique sorted codes, junk-safe', () {
      const body = '{"data":[{"attributes":{"language":"en"}},'
          '{"attributes":{"language":"hi"}},'
          '{"attributes":{"language":"en"}},'
          '{"attributes":{}}]}';
      expect(parseOpenSubLanguages(body), ['en', 'hi']);
      expect(parseOpenSubLanguages('{}'), isEmpty);
      expect(parseOpenSubLanguages('junk'), isEmpty);
    });

    test('tmdbLanguageName maps codes, uppercases unknowns', () {
      expect(tmdbLanguageName('hi'), 'Hindi');
      expect(tmdbLanguageName('ta'), 'Tamil');
      expect(tmdbLanguageName('xx'), 'XX');
    });

    test('parseTmdbExtras v47: budget, revenue, companies, cert, languages', () {
      const body = '{"id":1,"title":"X","release_date":"2024-06-14",'
          '"original_title":"X Orig","budget":165000000,'
          '"revenue":711000000,'
          '"production_companies":[{"name":"Legendary"}],'
          '"production_countries":[{"name":"United States"}],'
          '"release_dates":{"results":[{"iso_3166_1":"US",'
          '"release_dates":[{"certification":"PG-13"}]}]},'
          '"translations":{"translations":[{"iso_639_1":"en"},'
          '{"iso_639_1":"hi"},{"iso_639_1":"ta"}]}}';
      final x = parseTmdbExtras(body);
      expect(x.releaseDate, '2024-06-14');
      expect(x.originalTitle, 'X Orig');
      expect(x.budgetUsd, 165000000);
      expect(x.revenueUsd, 711000000);
      expect(x.companies, ['Legendary']);
      expect(x.countries, ['United States']);
      expect(x.certification, 'PG-13');
      expect(x.allLanguages, ['English', 'Hindi', 'Tamil']);
    });
  });

  group('v52 two-finger zoom + default fit', () {
    test('clampVideoZoom keeps pinch inside 1x..4x (1x = fit screen)', () {
      expect(clampVideoZoom(0.4), 1.0);
      expect(clampVideoZoom(1.0), 1.0);
      expect(clampVideoZoom(2.5), 2.5);
      expect(clampVideoZoom(9), 4.0);
    });

    test('two-finger TAP resets to fit; a real pinch does not', () {
      // Quick tap with almost no travel and no scaling -> reset.
      expect(
        isTwoFingerTapReset(durationMs: 180, travelPx: 6, scaled: false),
        isTrue,
      );
      // User actually pinched -> do NOT snap home.
      expect(
        isTwoFingerTapReset(durationMs: 180, travelPx: 6, scaled: true),
        isFalse,
      );
      // Slow two-finger hold is not a tap.
      expect(
        isTwoFingerTapReset(durationMs: 900, travelPx: 6, scaled: false),
        isFalse,
      );
      // Big movement is a pan-ish pinch, not a tap.
      expect(
        isTwoFingerTapReset(durationMs: 180, travelPx: 60, scaled: false),
        isFalse,
      );
    });

    test('default fit is FIT SCREEN and cycles stay wired', () {
      const s = PlayerSettings();
      expect(s.defaultFitIndex, 0);
      expect(PlayerSettings.kFitModeNames.first, 'Fit');
      expect(PlayerSettings.kFitModeNames.length, 6);
      // copyWith carries the choice through (Settings sheet writes this).
      expect(s.copyWith(defaultFitIndex: 1).defaultFitIndex, 1);
    });

    test('v57 two-finger: FIT is default, switchable to zoom, one at a time', () {
      const s = PlayerSettings();
      // The user's rule: two fingers = FIT SCREEN by default.
      expect(s.twoFingerMode, 'fit');
      expect(PlayerSettings.kTwoFingerModes.keys, ['fit', 'zoom']);
      expect(s.copyWith(twoFingerMode: 'zoom').twoFingerMode, 'zoom');
      // Legacy/unknown stored values fall back to the fit default.
      expect(PlayerSettings.normalizeTwoFingerMode('both'), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode('pinch'), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode('junk'), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode(null), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode('zoom'), 'zoom');
      // ...while pinch zoom stays its own independent master toggle.
      expect(s.pinchZoom, isTrue);
    });

    test('v59 twoFingerSnapsToFit: only a TAP snaps home, pinch stays', () {
      // v59 (his v58 phone report "zooming is not working"): a real
      // pinch is NEVER undone - the ladder keeps its fit/zoom; only a
      // quick two-finger tap snaps back to fit, in BOTH modes.
      expect(twoFingerSnapsToFit(mode: 'fit', wasTap: true), isTrue);
      expect(twoFingerSnapsToFit(mode: 'fit', wasTap: false), isFalse);
      expect(twoFingerSnapsToFit(mode: 'zoom', wasTap: true), isTrue);
      expect(twoFingerSnapsToFit(mode: 'zoom', wasTap: false), isFalse);
      // unknown stored value conservatively snaps home.
      expect(twoFingerSnapsToFit(mode: 'junk', wasTap: false), isTrue);
    });

    // v61 (user: "when toggle is off then only fit screens in loop; when
    // toggle is on then only zoom ... zoom is still not working"). The old
    // continuous ladder put zoom at the END behind a ~2.6x spread, which
    // made it unreachable on a phone. The two modes are now split: toggle
    // OFF = fit loop (never zooms, wraps around); toggle ON = pure free
    // zoom from the first millimetre (1.0x..4.0x).
    test('v61 toggle OFF: fit loop steps one per spread and NEVER zooms', () {
      const n = 6; // Fit, Crop, Stretch, 16:9, 4:3, Original
      double posAt(int base, double scale) =>
          fitLadderPosFor(basePos: base.toDouble(), scale: scale);

      // One kFitLadderStepScale spread from Fit lands on Crop (index 1).
      expect(wrapFitLadderPos(posAt(0, kFitLadderStepScale), n), 1);
      // Two spreads -> Stretch (index 2).
      expect(
          wrapFitLadderPos(
              posAt(0, kFitLadderStepScale * kFitLadderStepScale), n),
          2);
      // Walking all SIX fits from Fit brings us back to Fit (the loop).
      var p = 0.0;
      for (var i = 0; i < n; i++) {
        p = posAt(p.round(), kFitLadderStepScale);
      }
      expect(wrapFitLadderPos(p, n), 0);
      // The CRITICAL rule: spreading ALL the way (even a huge 10x gesture)
      // only ever produces a fit index 0..n-1 - it can NEVER enter zoom,
      // because the loop wraps. There is no zoom value produced here at all.
      final huge = wrapFitLadderPos(posAt(0, 10.0), n);
      expect(huge, inInclusiveRange(0, n - 1));
      // ...and pinching IN walks back down (Fit -> Original via wrap).
      final in1 = wrapFitLadderPos(posAt(0, 1 / kFitLadderStepScale), n);
      expect(in1, n - 1); // Original
      final in2 = wrapFitLadderPos(
          posAt(0, 1 / (kFitLadderStepScale * kFitLadderStepScale)), n);
      expect(in2, n - 2); // 4:3
    });

    test('v61 toggle OFF: wrap-around Original -> Fit is explicit', () {
      const n = 6;
      // Just past the last fit (index 5 == Original) wraps straight to
      // index 0 (Fit) - this is the "loop" the user asked for.
      expect(wrapFitLadderPos(5.6, n), 0);
      expect(wrapFitLadderPos(6.0, n), 0);
      expect(wrapFitLadderPos(11.4, n), 5); // two full loops + Original
      // Negative positions (pinch in from Fit) wrap to the top.
      expect(wrapFitLadderPos(-0.6, n), 5); // -1 mod 6 -> Original
      expect(wrapFitLadderPos(-1.6, n), 4); // -2 mod 6 -> 4:3
      // Staying inside a step keeps the same fit.
      expect(wrapFitLadderPos(0.4, n), 0);
      expect(wrapFitLadderPos(2.4, n), 2);
    });

    test('v61 toggle ON: free zoom maps directly and clamps at 4.0x', () {
      // Zoom works from the FIRST millimetre - no ladder to climb.
      expect(freeZoomFor(baseZoom: 1.0, scale: 1.0), 1.0);
      expect(freeZoomFor(baseZoom: 1.0, scale: 1.5), closeTo(1.5, 0.001));
      expect(freeZoomFor(baseZoom: 1.0, scale: 2.0), closeTo(2.0, 0.001));
      // A tiny spread already zooms (this is what was broken before).
      expect(freeZoomFor(baseZoom: 1.0, scale: 1.05), closeTo(1.05, 0.001));
      // Clamps at the 4.0x ceiling, no matter how hard you spread.
      expect(freeZoomFor(baseZoom: 1.0, scale: 5.0), kMaxVideoZoom);
      expect(freeZoomFor(baseZoom: 1.0, scale: 100.0), kMaxVideoZoom);
      // Pinching in from 1.0 clamps at the 1.0x floor (fit screen).
      expect(freeZoomFor(baseZoom: 1.0, scale: 0.1), kMinVideoZoom);
      // Zooming on top of an already-zoomed base multiplies.
      expect(freeZoomFor(baseZoom: 2.0, scale: 1.5), closeTo(3.0, 0.001));
      expect(freeZoomFor(baseZoom: 2.0, scale: 3.0), kMaxVideoZoom);
    });

    test('v59 kAllFilters: ONE row, movies AND web series together', () {
      expect(kAllFilters.length,
          kDiscoverFilters.length + kSeriesFilters.length);
      expect(kAllFilters.first.trending, isTrue);
      expect(kAllFilters.any((f) => f.tv), isTrue);
      expect(kAllFilters.any((f) => !f.tv), isTrue);
      // every chip still resolves to a valid endpoint + cache name
      for (final f in kAllFilters) {
        expect(tmdbEndpointPath(f), startsWith('/3/'));
        expect(discoverCacheName(f, 1), endsWith('_p1.json'));
      }
    });

    test('v59 tmdbDiscoverQuery loads TONS more (vote bar relaxed)', () {
      final q = tmdbDiscoverQuery(kDiscoverFilters.first, 1);
      expect(q['vote_count.gte'], '8'); // was 25 - cut regional/series
    });

    test('v59 parseTmdbMultiPage: movies+series in, people out', () {
      final page = parseTmdbMultiPage(
          '{"page":1,"total_pages":4,"total_results":3,"results":['
          '{"id":1,"media_type":"movie","title":"Dhoom","release_date":"2004-01-01"},'
          '{"id":2,"media_type":"tv","name":"Mirzapur","first_air_date":"2018-11-16"},'
          '{"id":3,"media_type":"person","name":"Some Actor"}]}');
      expect(page.items.length, 2);
      expect(page.items[0].kind, 'movie');
      expect(page.items[1].kind, 'tv');
      expect(page.items[1].title, 'Mirzapur');
      expect(page.items[1].year, 2018);
    });

    test('v59 parseTmdbSeasons: all parts of a series', () {
      final seasons = parseTmdbSeasons('{"seasons":['
          '{"season_number":0,"name":"Specials","episode_count":2,"air_date":null},'
          '{"season_number":1,"name":"Season 1","episode_count":9,"air_date":"2018-11-16"},'
          '{"season_number":2,"episode_count":10,"air_date":"2020-10-23"}]}');
      expect(seasons.length, 3);
      expect(seasons[0].name, 'Specials');
      expect(seasons[1].episodes, 9);
      expect(seasons[1].year, 2018);
      expect(seasons[2].name, 'Season 2'); // fallback naming
      expect(parseTmdbSeasons('garbage'), isEmpty);
    });

    test('v60 parseTmdbSeasons falls back to the counters line', () {
      // some /tv payloads carry ONLY counters, no seasons array
      final s = parseTmdbSeasons(
          '{"seasons":[],"number_of_seasons":3,"number_of_episodes":24}');
      expect(s.single.name, contains('3 seasons'));
      expect(s.single.episodes, 24);
      expect(parseTmdbSeasons('{"seasons":[],"number_of_seasons":0}'),
          isEmpty);
    });

    test('v60 thumbnail slots cap at 2 and hand over in order', () async {
      await VideoThumb.acquireThumbSlot();
      await VideoThumb.acquireThumbSlot();
      var thirdDone = false;
      final third =
          VideoThumb.acquireThumbSlot().then((_) => thirdDone = true);
      await Future<void>.delayed(Duration.zero);
      expect(thirdDone, isFalse); // third waits - the cap holds
      VideoThumb.releaseThumbSlot(); // frees -> third gets the slot
      await third;
      expect(thirdDone, isTrue);
      VideoThumb.releaseThumbSlot();
    });

    test('v58 series filters drive the TMDB /tv endpoints', () {
      final t = kSeriesFilters.firstWhere((f) => f.key == 'tv_hindi');
      expect(kSeriesFilters.every((f) => f.tv), isTrue);
      expect(kDiscoverFilters.every((f) => !f.tv), isTrue);
      expect(tmdbEndpointPath(kSeriesFilters.first), '/3/trending/tv/week');
      expect(tmdbEndpointPath(t), '/3/discover/tv');
      expect(tmdbDiscoverQuery(t, 2)['with_original_language'], 'hi');
      // series get their own cache files, movie cache names unchanged
      expect(discoverCacheName(t, 1), contains('_tv_'));
      expect(discoverCacheName(kDiscoverFilters.first, 1),
          'tmdb_disc_trending_p1.json');
    });

    test('v58 parseTmdbPage reads SERIES (name/first_air_date, kind tv)', () {
      final page = parseTmdbPage(
          '{"page":1,"total_pages":3,"total_results":1,"results":['
          '{"id":1399,"name":"Game of Thrones","first_air_date":"2011-04-17",'
          '"vote_average":8.4,"poster_path":"/x.jpg"}]}',
          kind: 'tv');
      expect(page.items.single.title, 'Game of Thrones');
      expect(page.items.single.year, 2011);
      expect(page.items.single.kind, 'tv');
      // movies stay kind 'movie' by default
      expect(
          parseTmdbPage('{"results":[{"id":1,"title":"X",'
                  '"release_date":"2020-05-06"}]}')
              .items
              .single
              .kind,
          'movie');
    });

    test('v58 parseAiSuggestionJson tolerates prose, fences, garbage', () {
      final picks = parseAiSuggestionJson(
          'Sure! Here you go:\n```json\n[{"title":"3 Idiots","year":2009},'
          '{"title":"Dangal"},{"no":"title"},{"title":""}]\n```');
      expect(picks.map((p) => p.title), ['3 Idiots', 'Dangal']);
      expect(picks.first.year, 2009);
      expect(picks[1].year, isNull);
      expect(parseAiSuggestionJson('no json at all'), isEmpty);
      expect(parseAiSuggestionJson('[1,2,3]'), isEmpty);
      expect(parseAiSuggestionJson('[]'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // v62 Phase 1: notification foundation
  // -------------------------------------------------------------------------
  group('v62 notifications', () {
    test('five distinct channels exist and match the native constants', () {
      // Keep these strings in sync with Notifications.CHANNEL_* in
      // MainActivity.kt / Notifications.kt - a typo would silently route a
      // notification to the wrong channel on Android.
      expect(NotificationChannels.all, hasLength(5));
      expect(NotificationChannels.aiSubs, 'ai_subs');
      expect(NotificationChannels.continueWatching, 'continue');
      expect(NotificationChannels.newEpisodes, 'new_episodes');
      expect(NotificationChannels.playback, 'playback');
      expect(NotificationChannels.general, 'general');
      expect(NotificationChannels.all.toSet().length, 5,
          reason: 'channel ids must be unique');
    });

    test('notification calls are plugin-safe (no channel -> no throw)', () {
      // In the Dart VM test there is no Android side, so every call must
      // resolve cleanly to its safe default rather than throw.
      expect(NativeBridge.notificationsEnabled(), completion(isFalse));
      expect(NativeBridge.requestNotifications(), completion(isFalse));
      expect(
        NativeBridge.showNotification(
          channel: NotificationChannels.aiSubs,
          title: 'Subtitles ready',
          body: 'AI subtitles for Dhoom 3 finished.',
          payload: 'ai:42',
        ),
        completion(0),
      );
      expect(NativeBridge.cancelNotification(99), completes);
      expect(NativeBridge.cancelAllNotifications(), completes);
      expect(NativeBridge.getInitialNotificationPayload(), completion(isNull));
    });

    test('AndroidManifest declares POST_NOTIFICATIONS (Android 13+)', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('android.permission.POST_NOTIFICATIONS'), isTrue,
          reason: 'v62 needs the runtime notification permission');
    });

    test('notification helper files are wired into the project', () {
      expect(File('lib/services/native_bridge.dart').existsSync(), isTrue);
      final bridge =
          File('lib/services/native_bridge.dart').readAsStringSync();
      expect(bridge, contains('notifyShow'));
      expect(bridge, contains('onNotificationTap'));
      expect(bridge, contains('getInitialNotificationPayload'));
      // The native helper + status-bar glyph must exist.
      expect(
        File('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
                'Notifications.kt')
            .existsSync(),
        isTrue,
      );
      expect(
        File('android/app/src/main/res/drawable/ic_stat_notify.xml')
            .existsSync(),
        isTrue,
      );
    });
  });
}
MAXV62_EOF_WIDGET_TEST_DART
echo "  wrote test/widget_test.dart"
mkdir -p "$(dirname "pubspec.yaml")"
cat > "pubspec.yaml" <<'MAXV62_EOF_PUBSPEC_YAML'
name: maxplayer
description: "Max Player - a local video library & player."
publish_to: 'none'
version: 1.0.0+58

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

  assets:
    # Real-time Enhance shader loaded into mpv at runtime (v32).
    - assets/shaders/
MAXV62_EOF_PUBSPEC_YAML
echo "  wrote pubspec.yaml"

# ---- marker checks (proves the v62 content actually landed) -------------
echo "==> Checking v62 markers..."
ok=0; total=0
present() { total=$((total+1)); if grep -q "$2" "$3" 2>/dev/null; then echo "  [OK] $1"; ok=$((ok+1)); else echo "  [!!] MISSING: $1"; fi; }
absent()  { total=$((total+1)); if grep -q "$2" "$3" 2>/dev/null; then echo "  [!!] STILL PRESENT: $1"; else echo "  [OK] $1"; ok=$((ok+1)); fi; }

K="android/app/src/main/kotlin/com/hypertechlabs/maxplayer"
present "Notifications.kt: channel constants"        "CHANNEL_AI_SUBS"        "$K/Notifications.kt"
present "Notifications.kt: show() helper"           "fun show("             "$K/Notifications.kt"
present "Notifications.kt: permission check"        "areEnabled"            "$K/Notifications.kt"
present "MainActivity: channel creation in onCreate" "Notifications.ensureChannels" "$K/MainActivity.kt"
present "MainActivity: notifyShow handler"          '"notifyShow"'          "$K/MainActivity.kt"
present "MainActivity: requestNotifications handler" '"requestNotifications"' "$K/MainActivity.kt"
present "MainActivity: onNotificationTap delivery"  "onNotificationTap"     "$K/MainActivity.kt"
present "Manifest: POST_NOTIFICATIONS permission"   "POST_NOTIFICATIONS"    "android/app/src/main/AndroidManifest.xml"
present "notify glyph drawable exists"              "android:pathData"      "android/app/src/main/res/drawable/ic_stat_notify.xml"
present "native_bridge: showNotification"           "showNotification"      "lib/services/native_bridge.dart"
present "native_bridge: requestNotifications"       "requestNotifications"  "lib/services/native_bridge.dart"
present "native_bridge: NotificationChannels"       "class NotificationChannels" "lib/services/native_bridge.dart"
present "main.dart: onNotificationTap wired"        "onNotificationTap"     "lib/main.dart"
present "about sheet: test-notification button"     "Send a test notification" "lib/widgets/about_sheet.dart"
present "test: v62 notification tests"             "v62 notifications"     "test/widget_test.dart"
present "pubspec version 1.0.0+58"                  "^version: 1.0.0+58"    "pubspec.yaml"
echo ""
if [ "$ok" -eq "$total" ]; then echo "==> $ok/$total checks OK - v62 applied."; else echo "==> $ok/$total checks OK - SOME MARKERS MISSING. Do not push; re-run or report."; fi

echo ""
echo "============================================================"
echo " DONE. If you saw N/N checks OK, run (AS-IS, no hand edits):"
echo "   git add -A && git commit -m \"v62 Phase 1: notification"
echo "     foundation - channels, permission, notify API, test"
echo "     button (1.0.0+58)\" && git push"
echo "============================================================"
echo ""
echo " PHONE TEST CHECKLIST (after installing the Codemagic build):"
echo "  [ ] Open the app -> tap the more (⋮) menu -> About."
echo "  [ ] Tap 'Send a test notification'."
echo "      - On Android 13+ a permission dialog appears -> ALLOW."
echo "      - A 'Max Player notifications are on' notification appears."
echo "  [ ] Tap that notification -> the app comes to the front and a"
echo "      snackbar says 'Notification: test:hello' (proves tap -> Dart)."
echo "  [ ] In Android Settings -> Apps -> Max Player -> Notifications,"
echo "      you see 5 channels: AI subtitles, Continue watching, New"
echo "      episodes, Playback, General (each can be muted separately)."
echo "  [ ] On Android 12 or below: no permission dialog, the test"
echo "      notification just posts (expected)."
echo ""
echo " Please paste the LAST ~10 lines of this output and tell me the"
echo " phone results. Then I will build Phase 2 (AI-subs-ready +"
echo " continue watching + scan/cast notifications)."
