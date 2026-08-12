#!/bin/bash
# ============================================================
# Max Player - UPDATE v14 (2026-08-13): STABILITY + PLAY STORE
# ============================================================
# STABILITY (your crash reports):
#   * CRASH JOURNAL: any Dart-side error is now recorded and shown as a
#     COPYABLE report on the next app launch ("Max Player closed
#     unexpectedly" dialog in the library). Send me that text and I can
#     finally see WHY the app closes for you. Native (libmpv) aborts still
#     need a logcat, but most closes land in the journal.
#   * AI SUBTITLES PERSIST ACROSS REOPEN: opening a video now re-attaches
#     "<video>.maxai.srt" automatically (they ARE saved on disk; the new
#     session just never re-loaded them). Also auto-selected.
#   * AI LANGUAGE: the Generate dialog now asks the SPOKEN LANGUAGE
#     (Auto/English/Hindi/Urdu/... 16 options) + MODEL (Fast/Balanced/
#     Best). Pinning the language is the biggest accuracy boost.
#   * CAST DIAGNOSTICS: "No TVs found" now splits the cause: 0 network
#     replies = same-Wi-Fi/router issue; replies but no renderer = the TV
#     doesn't speak DLNA (many newer Samsung/LG TVs removed it).
#
# PLAY STORE READINESS:
#   * package renamed com.example.maxplayer -> com.hypertechlabs.maxplayer
#   * release signing: android/key.properties (template + .gitignore
#     included) - debug key fallback keeps local/CI builds working
#   * codemagic.yaml now ALSO builds the AAB (the Play upload file) and
#     can inject the upload key from Codemagic env vars
#   * PRIVACY_POLICY.md + PLAY_STORE_GUIDE.md added to the repo
#   * repo CLEANUP: deletes stray delivery scripts/snippets from the root
#     (safe: they were never part of the app)
#
# HOW TO USE (on the Pi):
#   cd ~/IdeaProjects/maxplayer
#   nano update_v14.sh     # paste this whole file, save & exit
#   bash update_v14.sh
#   git add -A && git commit -m "v14: crash journal, AI persistence+language picker, cast diagnostics, Play Store packaging (AAB, signing, com.hypertechlabs)" && git push
# ============================================================
set -e
cd "$(dirname "$0")"
echo "==> Applying Max Player v14 update..."
mkdir -p lib/cast
mkdir -p android/app/src/main/kotlin/com/hypertechlabs/maxplayer
rm -rf android/app/src/main/kotlin/com/example

# Repo cleanup: delivery scripts/snippets that were committed by accident
# (they are tools, not app code - removing them cannot break the build).
rm -f setup_maxplayer.sh update_maxplayer.sh update_maxplayer_v*.sh \
      update_player_tracks.sh update_player_v3.sh hotfix2.sh \
      hotfix_manifest.sh hotfix_pip_params.sh android_manifest_snippet.xml \
      atom_change_fragment.diff

cat > 'android/app/src/main/AndroidManifest.xml' <<'EOF_MARKER_0'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
        tools:ignore="ScopedStorage" />

    <!-- Network: one-time AI model download + streaming URLs + DLNA cast control -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <!-- DLNA/UPnP casting: SSDP device discovery needs the multicast lock -->
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <application
        android:label="Max Player"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
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
EOF_MARKER_0

cat > 'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt' <<'EOF_MARKER_1'
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
                    if (videoPath.isNullOrEmpty()) {
                        result.error("bad_args", "videoPath is required", null)
                    } else {
                        aiCancelled = false
                        val jobId = ++aiJobCounter
                        executor.execute {
                            runAiPipeline(jobId, videoPath, model, language)
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

    private fun runAiPipeline(
        jobId: Int,
        videoPath: String,
        modelName: String,
        language: String
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

            // 3. Transcribe with whisper.cpp (offline). NOTE: this stage
            // cannot be cancelled mid-run; a cancel during it discards the
            // result afterwards.
            aiProgress(jobId, "transcribing", 0)
            val segments = ArrayList<HashMap<String, Any>>()
            runBlocking {
                var model: WhisperModel? = null
                try {
                    model = Whisper.loadModel(this@MainActivity, modelFile.absolutePath)
                    // The user can pin a language ("hi", "ur", "en", ...) in
                    // the Generate dialog; "auto" = detect it. Pinning the
                    // right language is noticeably more accurate than
                    // detection on short clips.
                    val res = Whisper.transcribe(
                        model,
                        wav.absolutePath,
                        WhisperConfig(language = language)
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
EOF_MARKER_1

cat > 'android/app/build.gradle.kts' <<'EOF_MARKER_2'
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play Store upload key: android/key.properties holds the real signing
// credentials when present (generated per PLAY_STORE_GUIDE.md); CI injects
// it. When absent (local dev, old clones) release falls back to the debug
// key so nothing breaks - a debug-signed build just can't go to the Play
// Console.
val uploadProps = Properties().apply {
    // Conventional location: android/key.properties (git-ignored).
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasUploadKey = uploadProps.getProperty("storeFile")?.isNotEmpty() == true

android {
    namespace = "com.hypertechlabs.maxplayer"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("playStore") {
            keyAlias = uploadProps.getProperty("keyAlias") ?: ""
            keyPassword = uploadProps.getProperty("keyPassword") ?: ""
            storePassword = uploadProps.getProperty("storePassword") ?: ""
            uploadProps.getProperty("storeFile")?.let {
                // Resolved relative to the android/ project dir.
                storeFile = rootProject.file(it)
            }
        }
    }

    defaultConfig {
        // Unique application ID (renamed from com.example.* for Play Store;
        // a published app can never change this again).
        applicationId = "com.hypertechlabs.maxplayer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // APK SIZE: the default Flutter/media_kit build bundles native libs
        // for FOUR CPU architectures (arm64-v8a, armeabi-v7a, x86, x86_64) -
        // that alone was ~60 MB of the ~93 MB APK. Every phone from ~2017
        // onward is arm64-v8a, so shipping just that cuts the APK to ~1/3.
        // (Also matches the whisper-android AAR, which is arm64-only.)
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        release {
            // Real upload key when android/key.properties exists, otherwise
            // the debug key so `flutter run --release` still works.
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("playStore")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // AI SUBTITLES (Phase 1): prebuilt on-device whisper.cpp engine.
    // Plain Maven artifact (NOT a Gradle/Flutter plugin) = no toolchain
    // conflicts. ~1.1 MB AAR, MIT licensed, runs 100% offline & free.
    implementation("dev.ffmpegkit-maintained:whisper-android:1.0.0")
    // The AAR only exports coroutines on the runtime classpath; we call its
    // suspend functions from Kotlin, so we need it explicitly at compile
    // time. Same version as the AAR's -> no conflict.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
EOF_MARKER_2

cat > 'android/key.properties.template' <<'EOF_MARKER_3'
# Play Store upload key configuration.
# 1) Generate the keystore ONCE from the repo root (keep the file AND the
#    passwords safe forever - every future update must be signed with the
#    same key, or the Play Store rejects it):
#      keytool -genkey -v -keystore android/upload-keystore.jks \
#        -keyalg RSA -keysize 2048 -validity 10000 -alias maxplayer
# 2) Copy this file to  android/key.properties  (git-ignored) and replace
#    the two passwords with the ones you chose. Both files are listed in
#    .gitignore, so the key never lands on GitHub.
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=maxplayer
storeFile=upload-keystore.jks
EOF_MARKER_3

cat > 'codemagic.yaml' <<'EOF_MARKER_4'
workflows:
  android-apk:
    name: Max Player - Android APK + AAB
    max_build_duration: 60
    environment:
      # Pinned on purpose: 'stable' auto-upgrades, and upcoming Flutter
      # versions will refuse to build plugins that still apply the Kotlin
      # Gradle Plugin (media_kit's transitive package_info_plus /
      # wakelock_plus warn about this today). A pinned version keeps every
      # CI build reproducible.
      flutter: 3.44.9
      # Play Store upload key comes from these environment variables when
      # they are configured in Codemagic (App settings -> Environment
      # variables -> group "keystore_credentials"): CM_KEYSTORE (base64 of
      # the .jks/.keystore), CM_KEYSTORE_PASSWORD, CM_KEY_ALIAS,
      # CM_KEY_ALIAS_PASSWORD. Without them the build signs with the debug
      # key (fine for testing; Play Console needs the real key).
      groups:
        - keystore_credentials
      vars:
        CM_KEYSTORE_PATH: /tmp/maxplayer-upload.keystore
    scripts:
      - name: Prepare upload key (optional)
        script: |
          if [ -n "$CM_KEYSTORE" ]; then
            echo "$CM_KEYSTORE" | base64 --decode > "$CM_KEYSTORE_PATH"
            {
              echo "storePassword=$CM_KEYSTORE_PASSWORD"
              echo "keyPassword=$CM_KEY_ALIAS_PASSWORD"
              echo "keyAlias=$CM_KEY_ALIAS"
              echo "storeFile=$CM_KEYSTORE_PATH"
            } > android/key.properties
            echo "Upload key configured - release will be Play-Store signed."
          else
            echo "No upload key configured - release signs with the debug key."
          fi
      - name: Clean build (avoid stale plugin registration after dependency upgrades)
        script: flutter clean
      - name: Get Flutter packages
        script: flutter pub get
      - name: Build APK (release, arm64 only)
        # --target-platform makes the Flutter TOOL package only arm64 engine
        # + plugin libs (ndk.abiFilters alone doesn't strip the Flutter
        # artefacts). This is what cut the APK from ~93 MB to ~62 MB.
        script: flutter build apk --release --target-platform=android-arm64
      - name: Build AAB for the Play Store (release, arm64 only)
        script: flutter build appbundle --release --target-platform=android-arm64
    artifacts:
      - build/app/outputs/flutter-apk/*.apk
      - build/app/outputs/bundle/release/*.aab
    publishing:
      email:
        recipients:
          - your-email@example.com
        notify:
          success: true
          failure: true
EOF_MARKER_4

cat > 'pubspec.yaml' <<'EOF_MARKER_5'
name: maxplayer
description: "Max Player - a local video library & player."
publish_to: 'none'
version: 1.0.0+14

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

cat > '.gitignore' <<'EOF_MARKER_6'
# Miscellaneous
*.class
*.log
*.pyc
*.swp
.DS_Store
.atom/
.build/
.buildlog/
.history
.svn/
.swiftpm/
migrate_working_dir/

# IntelliJ related
*.iml
*.ipr
*.iws
.idea/

# The .vscode folder contains launch configuration and tasks you configure in
# VS Code which you may wish to be included in version control, so this line
# is commented out by default.
#.vscode/

# Flutter/Dart/Pub related
**/doc/api/
**/ios/Flutter/.last_build_id
.dart_tool/
.flutter-plugins-dependencies
.pub-cache/
.pub/
/build/
/coverage/

# Symbolication related
app.*.symbols

# Obfuscation related
app.*.map.json

# Android Studio will place build artifacts here
/android/app/debug
/android/app/profile
/android/app/release

# Play Store upload key - NEVER commit these
android/key.properties
android/upload-keystore.jks
android/upload-keystore.keystore
EOF_MARKER_6

cat > 'PRIVACY_POLICY.md' <<'EOF_MARKER_7'
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
Subtitle generation runs entirely **on your device** using the open-source whisper.cpp engine. Your audio never leaves your phone. The only network access is the one-time model file download from Hugging Face (ggerganov/whisper.cpp), which you trigger and can delete afterwards.

## Children's privacy
The app collects no data from anyone, including children.

## Changes
Any change to this policy will be committed to this file in the public repository, with the new effective date above.

## Contact
Questions: open an issue on the GitHub repository above.
EOF_MARKER_7

cat > 'PLAY_STORE_GUIDE.md' <<'EOF_MARKER_8'
# Play Store Checklist — Max Player

Everything needed to pass Google Play review, step by step.

## 1. Package name
`com.hypertechlabs.maxplayer` (renamed from the default `com.example.maxplayer`
— Google accepts `com.example.*` technically, but it is unprofessional and the
first-to-claim risk is real). **Once you publish, the package name can never
change again.**

## 2. Versioning
`pubspec.yaml` → `version: 1.0.0+14`. The part after `+` (versionCode) must
**go up by at least 1 on every upload**. Never decrease it.

## 3. App signing (required)
The Play Console rejects debug-signed builds. One-time setup on the Pi:

```bash
cd ~/IdeaProjects/maxplayer
keytool -genkey -v -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias maxplayer
cp android/key.properties.template android/key.properties
nano android/key.properties   # fill in the two passwords you chose
```

Both files are git-ignored. **Back up the .jks + passwords somewhere safe
(cloud/USB). Losing them means you can never update the published app again**
(without Play's reset process).

### For Codemagic CI signing
1. `base64 -w0 android/upload-keystore.jks > /tmp/key.b64` and copy the text.
2. Codemagic → app settings → **Environment variables** → create a group
   named exactly `keystore_credentials` with:
   - `CM_KEYSTORE` = the base64 text
   - `CM_KEYSTORE_PASSWORD` = your store password
   - `CM_KEY_ALIAS` = `maxplayer`
   - `CM_KEY_ALIAS_PASSWORD` = your key password
3. `codemagic.yaml` already turns those into `android/key.properties` at
   build time and signs both APK + AAB with it.

## 4. Build files Codemagic now produces
- `app-release.apk` (sideload/testing)
- `app-release.aab` (**this is the file you upload to the Play Console**)

## 5. Play Console fields (what to answer)
- **Data safety:** No data collected, no data shared. (All offline — see
  `PRIVACY_POLICY.md`.) The only network calls: optional one-time AI model
  download, optional user-opened stream URLs.
- **Privacy policy URL:** host `PRIVACY_POLICY.md` — easiest free option is
  the GitHub repo itself:
  `https://github.com/Aryanshahx/maxplayer/blob/main/PRIVACY_POLICY.md`
  (Play accepts GitHub blob URLs), or GitHub Pages later.
- **Target audience:** 13+ (it's a media player, not child-directed).
- **Content rating questionnaire:** answer honestly — app plays user content,
  no generated/social content features → low ratings everywhere.
- **MANAGE_EXTERNAL_STORAGE declaration:** Play asks for justification since
  the app uses all-files access. Justification: *"Core functionality: the
  app's primary purpose is playing video files stored anywhere on the device,
  including external SD cards and USB-OTG; MediaStore/scoped storage cannot
  enumerate all video files (e.g. .mkv/.ts on SD cards). Screenshots and AI
  subtitle files are written next to the source videos."* — this is the
  standard media-player justification and is routinely accepted **for apps
  whose main function is media playback**. Record the short screen-video they
  ask for showing: scanning the library + playing a video.
- **Ads declaration:** No ads.
- **News apps / COVID etc.:** all No.

## 6. Android version targeting
`targetSdk 36` ✓ (Play's requirement for new apps as of 2026). `minSdk` comes
from Flutter defaults; whisper needs 24+ and media_kit 21+ — the low floor is
fine.

## 7. 16 KB page-size support (Play requirement)
AGP 9 + NDK default output is 16 KB-aligned, the Flutter 3.44 engine supports
16 KB, and the bundled whisper library is 16 KB-native. **Verify once after
the first CI AAB:** download the AAB from Codemagic, then on the Pi:

```bash
unzip -o app-release.aab -d /tmp/aab >/dev/null
# every .so should print "2**14" (16384) alignment:
find /tmp/aab -name "*.so" -exec sh -c 'objdump -p {} | grep -m1 LOAD' \;
```

If any library shows `2**12` (4096), report which `.so` and I'll pin/fix the
offending lib version.

## 8. Store listing assets needed (not code)
- App icon: already shipped in the app (mipmap). Also upload 512×512 PNG.
- Feature graphic 1024×500 PNG.
- At least 2 phone screenshots (take them from your Samsung).

## 9. Testing tracks
Upload the AAB to **Internal testing** first → install from Play on your own
phone → verify everything works → then promote to production. This catches
"works on my sideload APK but not on Play" issues for free.
EOF_MARKER_8

cat > 'lib/app_info.dart' <<'EOF_MARKER_9'
/// Central app identity. Bump together with pubspec.yaml's version
/// (versionName = kAppVersion). Shown in the ⋮ menu footer, the user
/// manual and the About sheet - one place to update for all of them.
const String kAppVersion = '1.0.0';
EOF_MARKER_9

cat > 'lib/main.dart' <<'EOF_MARKER_10'
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
EOF_MARKER_10

cat > 'lib/services/native_bridge.dart' <<'EOF_MARKER_11'
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
  }) async {
    try {
      return await _channel.invokeMethod<int>(
        'aiSubtitleGenerate',
        {'videoPath': videoPath, 'model': model, 'language': language},
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
EOF_MARKER_11

cat > 'lib/models/video_track.dart' <<'EOF_MARKER_12'
import 'package:path/path.dart' as p;

/// Mirrors the web app's VideoTrack type, adapted for local files on Android.
class VideoTrack {
  final String id;
  final String title;
  final String path; // absolute filesystem path (was `src` blob URL on web)
  final String? thumbnailPath; // cached jpg path, generated on scan
  final Duration? duration;
  final int? sizeBytes;
  final int? lastModifiedMs;
  final int? width; // pixels, from native metadata
  final int? height;

  const VideoTrack({
    required this.id,
    required this.title,
    required this.path,
    this.thumbnailPath,
    this.duration,
    this.sizeBytes,
    this.lastModifiedMs,
    this.width,
    this.height,
  });

  /// Name of the folder containing this video (used by "Group by folder").
  String get folderName {
    final dir = p.dirname(path);
    final base = p.basename(dir);
    return base.isEmpty ? dir : base;
  }

  /// Human resolution badge ("1080p", "4K", "SD", ...) based on the SHORTER
  /// side, so portrait videos get the same label as their landscape peers.
  /// Null when dimensions are unknown.
  String? get qualityLabel {
    final w = width ?? 0;
    final h = height ?? 0;
    final short = w < h ? (w == 0 ? h : w) : (h == 0 ? w : h);
    if (short <= 0) return null;
    if (short >= 2160) return '4K';
    if (short >= 1440) return '2K';
    if (short >= 1080) return '1080p';
    if (short >= 720) return '720p';
    if (short >= 480) return '480p';
    if (short >= 360) return '360p';
    return 'SD';
  }

  VideoTrack copyWith({
    String? thumbnailPath,
    Duration? duration,
  }) {
    return VideoTrack(
      id: id,
      title: title,
      path: path,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      duration: duration ?? this.duration,
      sizeBytes: sizeBytes,
      lastModifiedMs: lastModifiedMs,
      width: width,
      height: height,
    );
  }
}

enum RepeatMode { none, one, all }

enum SortMode { name, date, size, length }

enum ViewMode { grid, list }

enum GroupMode { none, name, folder }

/// What tapping a video does: queue every visible video, or just that file.
enum PlaybackAction { all, single }
EOF_MARKER_12

cat > 'lib/models/history_entry.dart' <<'EOF_MARKER_13'
/// One row in the watch-history list. Persisted as JSON inside the native
/// settings store (SharedPreferences) by MediaPlayerState.
class HistoryEntry {
  final String path;
  final String title;
  final String? thumbnailPath;

  /// Where playback stopped (0 = finished / never started meaningfully).
  int lastPositionSecs;

  /// Total length if known (drives the little progress bar in the list).
  final int durationSecs;

  /// Last time the video was opened (ms since epoch).
  int playedAtMs;

  HistoryEntry({
    required this.path,
    required this.title,
    this.thumbnailPath,
    this.lastPositionSecs = 0,
    this.durationSecs = 0,
    required this.playedAtMs,
  });

  double get progress =>
      durationSecs > 0 ? (lastPositionSecs / durationSecs).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        if (thumbnailPath != null) 'thumb': thumbnailPath,
        'pos': lastPositionSecs,
        'dur': durationSecs,
        'at': playedAtMs,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        path: j['path'] as String? ?? '',
        title: j['title'] as String? ?? '',
        thumbnailPath: j['thumb'] as String?,
        lastPositionSecs: (j['pos'] as num?)?.toInt() ?? 0,
        durationSecs: (j['dur'] as num?)?.toInt() ?? 0,
        playedAtMs: (j['at'] as num?)?.toInt() ?? 0,
      );
}
EOF_MARKER_13

cat > 'lib/state/video_library_state.dart' <<'EOF_MARKER_14'
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
EOF_MARKER_14

cat > 'lib/state/media_player_state.dart' <<'EOF_MARKER_15'
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
    await _attachSidecarSubtitles(track.path);
    await _recordOpen(track);
    await _restoreBookmark(track);
  }

  /// Re-attaches previously generated AI subtitles ("<video>.maxai.srt"
  /// next to the video) so they survive closing/reopening the app - they
  /// are written to disk, only the player session forgot them.
  Future<void> _attachSidecarSubtitles(String videoPath) async {
    if (videoPath.contains('://')) return; // no sidecars for streams
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      final srt = srtPathForVideo(videoPath);
      if (File(srt).existsSync()) {
        // "select" makes it the active track right away.
        await platform.command(['sub-add', srt, 'select']);
      }
    } catch (_) {
      // Missing/unreadable sidecar is not fatal.
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
EOF_MARKER_15

cat > 'lib/state/player_settings.dart' <<'EOF_MARKER_16'
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
    return NativeBridge.saveSetting(kLockButton, '$lockButton');
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
    );
  }
}
EOF_MARKER_16

cat > 'lib/state/theme_state.dart' <<'EOF_MARKER_17'
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
  ];

  static const String _kAccentKey = 'theme.accent';

  Color _accent = swatches.first;
  Color get accent => _accent;

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
EOF_MARKER_17

cat > 'lib/utils/formatters.dart' <<'EOF_MARKER_18'
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
EOF_MARKER_18

cat > 'lib/utils/srt.dart' <<'EOF_MARKER_19'
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
EOF_MARKER_19

cat > 'lib/utils/crash_log.dart' <<'EOF_MARKER_20'
import '../services/native_bridge.dart';

/// Minimal crash journal so an "app closed unexpectedly" is no longer
/// invisible: the Dart-side error is stored in the native settings store
/// (plain strings) and shown ONCE on the next app launch, where the user
/// can copy it and send it for analysis.
///
/// NOTE: this catches Dart/framework errors. A native abort inside libmpv
/// or a decoder can't be caught here - those still need a logcat or the
/// Android tombstone, but in practice most unexpected closes surface as
/// Dart errors.
class CrashLog {
  CrashLog._();

  static const String _kCrashKey = 'crash.last';

  /// Records [error] (+ truncated [stack]) under [kind] ('flutter' for
  /// widget-tree errors, 'async' for uncaught zone errors, 'zone' for the
  /// outermost guard).
  static Future<void> record(
    String kind,
    String error,
    StackTrace? stack,
  ) async {
    try {
      final buf = StringBuffer()
        ..writeln('Max Player crash report')
        ..writeln('time: ${DateTime.now().toIso8601String()}')
        ..writeln('kind: $kind')
        ..writeln('error: $error')
        ..writeln('stack:');
      final frames = stack?.toString().split('\n') ?? const <String>[];
      buf.write(frames.take(24).join('\n'));
      var text = buf.toString();
      if (text.length > 6000) text = text.substring(0, 6000);
      await NativeBridge.saveSetting(_kCrashKey, text);
    } catch (_) {
      // Never let crash-reporting itself crash the app.
    }
  }

  /// Returns the last stored report and clears it (shown once).
  static Future<String?> takeLast() async {
    try {
      final s = await NativeBridge.loadSettings();
      final v = s[_kCrashKey];
      if (v == null || v.isEmpty) return null;
      await NativeBridge.saveSetting(_kCrashKey, '');
      return v;
    } catch (_) {
      return null;
    }
  }
}
EOF_MARKER_20

cat > 'lib/utils/ai_subtitles.dart' <<'EOF_MARKER_21'
import 'dart:async';
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

  /// Persisted picker defaults (native settings store).
  static const String _kModelKey = 'ai.model';
  static const String _kLanguageKey = 'ai.language';

  /// Model choices: id -> (label, detail with size).
  static const Map<String, (String, String)> modelChoices = {
    'tiny': ('Fast', '~75 MB · weakest on Hindi/Urdu'),
    'base': ('Balanced', '~142 MB · good for most videos'),
    'small': ('Best', '~466 MB · slowest, most accurate'),
  };

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

    // Ask for quality + language first (choices are remembered).
    final stored = await NativeBridge.loadSettings();
    if (!context.mounted) return;
    final options = await showDialog<({String model, String language})>(
      context: context,
      builder: (_) => _AiOptionsDialog(
        initialModel: stored[_kModelKey] ?? 'base',
        initialLanguage: stored[_kLanguageKey] ?? 'auto',
      ),
    );
    if (options == null || !context.mounted) return;
    unawaited(NativeBridge.saveSetting(_kModelKey, options.model));
    unawaited(NativeBridge.saveSetting(_kLanguageKey, options.language));

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

  const _AiOptionsDialog({
    required this.initialModel,
    required this.initialLanguage,
  });

  @override
  State<_AiOptionsDialog> createState() => _AiOptionsDialogState();
}

class _AiOptionsDialogState extends State<_AiOptionsDialog> {
  late String _model = widget.initialModel;
  late String _language = widget.initialLanguage;

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
          const SizedBox(height: 10),
          const Text(
            'Runs 100% offline after a one-time model download.',
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
          onPressed: () => Navigator.of(context)
              .pop((model: _model, language: _language)),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Generate'),
        ),
      ],
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
EOF_MARKER_21

cat > 'lib/cast/cast_support.dart' <<'EOF_MARKER_22'
/// Pure, unit-testable building blocks for DLNA/UPnP casting.
///
/// Everything here is dependency-free and contains no I/O, so the wire
/// formats (SSDP headers, device-description XML, SOAP envelopes, DIDL-Lite
/// metadata, DLNA time format) can be locked down by unit tests without a
/// TV. The sockets/HTTP that use these live in `cast_state.dart` and
/// `cast_file_server.dart`.
library;

/// One discovered DLNA renderer (a TV, Android box, ...).
class DlnaDevice {
  /// Display name from the device description ("Living Room TV").
  final String name;

  /// The SSDP LOCATION header (device description URL) - used to dedupe.
  final String location;

  /// Absolute AVTransport control URL we POST SOAP actions to.
  final String controlUrl;

  const DlnaDevice({
    required this.name,
    required this.location,
    required this.controlUrl,
  });
}

// ---------------------------------------------------------------------------
// SSDP (discovery)
// ---------------------------------------------------------------------------

/// M-SEARCH request body for a given search target.
String buildMSearchRequest(String st) =>
    'M-SEARCH * HTTP/1.1\r\n'
    'HOST: 239.255.255.250:1900\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: 2\r\n'
    'ST: $st\r\n'
    '\r\n';

/// Header lookup in an SSDP response/notify (case-insensitive names).
String? ssdpHeader(String datagram, String name) {
  final lower = name.toLowerCase();
  for (final line in datagram.split(RegExp(r'\r?\n'))) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    if (line.substring(0, idx).trim().toLowerCase() == lower) {
      final v = line.substring(idx + 1).trim();
      return v.isEmpty ? null : v;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Device description XML (UPnP)
// ---------------------------------------------------------------------------

String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// Parses a UPnP device description into a [DlnaDevice], or returns null
/// when the device has no AVTransport service (i.e. it is not a renderer
/// we can cast to - routers, speakers-only, etc.).
DlnaDevice? parseDeviceDescription(String xml, String location) {
  final nameMatch =
      RegExp(r'<friendlyName>([^<]*)</friendlyName>').firstMatch(xml);
  final name = nameMatch != null
      ? _xmlUnescape(nameMatch.group(1)!.trim())
      : 'DLNA device';

  // Find the <service> block that offers AVTransport (any version).
  String? controlPath;
  for (final m in RegExp(
    r'<service>(.*?)</service>',
    dotAll: true,
  ).allMatches(xml)) {
    final block = m.group(1)!;
    if (!block.contains('AVTransport')) continue;
    final cm = RegExp(r'<controlURL>([^<]+)</controlURL>').firstMatch(block);
    if (cm != null) {
      controlPath = cm.group(1)!.trim();
      break;
    }
  }
  if (controlPath == null || controlPath.isEmpty) return null;

  // controlURL is usually root-relative ("/dmr/avtransport") - resolve it
  // against the scheme://host:port of the description URL.
  final String controlUrl;
  if (controlPath.startsWith('http://') || controlPath.startsWith('https://')) {
    controlUrl = controlPath;
  } else {
    final loc = Uri.parse(location);
    final base = '${loc.scheme}://${loc.host}:${loc.port}';
    controlUrl = controlPath.startsWith('/')
        ? '$base$controlPath'
        : '$base/$controlPath';
  }

  return DlnaDevice(name: name, location: location, controlUrl: controlUrl);
}

// ---------------------------------------------------------------------------
// SOAP over HTTP (AVTransport control)
// ---------------------------------------------------------------------------

/// XML-escape a value embedded in SOAP / DIDL payloads.
String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

const String avTransportServiceType =
    'urn:schemas-upnp-org:service:AVTransport:1';

/// Builds a SOAP envelope for [action] with [args] as <Key>value</Key>
/// entries (InstanceID is always first - every AVTransport action needs it).
String buildSoapEnvelope(String action, List<MapEntry<String, String>> args) {
  final buf = StringBuffer()
    ..write('<?xml version="1.0" encoding="utf-8"?>')
    ..write('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">')
    ..write('<s:Body>')
    ..write('<u:$action xmlns:u="$avTransportServiceType">')
    ..write('<InstanceID>0</InstanceID>');
  for (final a in args) {
    buf.write('<${a.key}>${xmlEscape(a.value)}</${a.key}>');
  }
  buf
    ..write('</u:$action>')
    ..write('</s:Body></s:Envelope>');
  return buf.toString();
}

/// Pulls one tag value out of a SOAP response body (<RelTime>0:03:12</..>).
/// Tolerates namespaced tags (<m:RelTime>) and whitespace.
String? soapTag(String body, String tag) {
  final m = RegExp(
    '<(?:[A-Za-z0-9_]+:)?$tag>([^<]*)</(?:[A-Za-z0-9_]+:)?$tag>',
  ).firstMatch(body);
  if (m == null) return null;
  final v = m.group(1)!.trim();
  return v.isEmpty ? null : v;
}

// ---------------------------------------------------------------------------
// DIDL-Lite metadata (describes the media handed to the TV)
// ---------------------------------------------------------------------------

/// Content-type a TV understands, derived from the file extension.
String mimeForExtension(String path) {
  final q = path.split('?').first; // drop query when path is a URL
  final ext = q.contains('.') ? q.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mkv':
      return 'video/x-matroska';
    case 'webm':
      return 'video/webm';
    case 'avi':
    case 'divx':
      return 'video/x-msvideo';
    case 'mov':
      return 'video/quicktime';
    case 'flv':
    case 'f4v':
      return 'video/x-flv';
    case 'wmv':
    case 'asf':
      return 'video/x-ms-wmv';
    case 'ts':
    case 'm2ts':
    case 'mts':
      return 'video/mp2t';
    case '3gp':
    case '3gpp':
      return 'video/3gpp';
    case 'mpg':
    case 'mpeg':
    case 'vob':
      return 'video/mpeg';
    case 'rmvb':
    case 'rm':
      return 'video/vnd.rn-realvideo';
    default:
      // Unknown: mp4 is the most widely accepted container claim.
      return 'video/mp4';
  }
}

/// DIDL-Lite <item> describing the video. Some renderers reject playback
/// when CurrentURIMetadata is empty, so we always send this.
String buildDidlMetadata({
  required String title,
  required String videoUrl,
  required String mime,
  String? subsUrl,
}) {
  final buf = StringBuffer()
    ..write('<DIDL-Lite '
        'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"')
    ..write(subsUrl == null ? '' : ' xmlns:sec="http://www.sec.co.kr/"')
    ..write('>')
    ..write('<item id="0" parentID="-1" restricted="1">')
    ..write('<dc:title>${xmlEscape(title)}</dc:title>')
    ..write('<upnp:class>object.item.videoItem</upnp:class>')
    ..write('<res protocolInfo="http-get:*:$mime:*">'
        '${xmlEscape(videoUrl)}</res>');
  if (subsUrl != null) {
    // Samsung-style external subtitle pointer.
    buf.write('<sec:CaptionInfoEx sec:type="srt">${xmlEscape(subsUrl)}'
        '</sec:CaptionInfoEx>');
  }
  buf.write('</item></DIDL-Lite>');
  return buf.toString();
}

// ---------------------------------------------------------------------------
// DLNA time format (H:MM:SS[.FFF]) used by Seek / GetPositionInfo
// ---------------------------------------------------------------------------

String formatRelTime(Duration d) {
  final totalSecs = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = totalSecs ~/ 3600;
  final m = (totalSecs % 3600) ~/ 60;
  final s = totalSecs % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '$h:${two(m)}:${two(s)}';
}

/// Parses "0:03:12", "00:03:12.000" etc. Returns null for the sentinel
/// values TVs send when a property is unavailable (NOT_IMPLEMENTED/_X_...).
Duration? parseRelTime(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty || s.toUpperCase().contains('NOT_IMPLEMENTED')) return null;
  final parts = s.split(':');
  if (parts.length != 3) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final secPart = double.tryParse(parts[2]);
  if (h == null || m == null || secPart == null) return null;
  return Duration(
    hours: h,
    minutes: m,
    seconds: secPart.floor(),
    milliseconds: ((secPart - secPart.floor()) * 1000).round(),
  );
}
EOF_MARKER_22

cat > 'lib/cast/cast_file_server.dart' <<'EOF_MARKER_23'
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';


/// Tiny embedded HTTP server that hands the CURRENT video file to the TV.
///
/// DLNA renderers do not receive the video over the control channel - they
/// PULL it from an URL. While casting, the phone runs this server and the
/// TV fetches `http://<phone-ip>:<port>/video.mp4` (plus an optional SRT).
///
/// Range (byte-range) support is mandatory: TVs probe the file, seek with
/// Range headers and open several parallel connections. This server handles
/// one range per request, HEAD probes and keep-alive, all with dart:io so
/// no plugin dependency is added.
class CastFileServer {
  HttpServer? _server;
  String? _videoPath;
  String? _videoMime;
  String? _subsPath;

  bool get isRunning => _server != null;

  /// Base URL once started, e.g. "http://192.168.1.23:45678". Null before.
  String? baseUrl;

  /// Picks the IPv4 address of the interface that can reach the TV network
  /// (prefers Wi-Fi/en*, falls back to the first non-loopback address).
  static Future<String?> localIpV4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? fallback;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.')) continue;
          // Wi-Fi / ethernet-ish interface names first.
          final n = iface.name.toLowerCase();
          final preferred =
              n.startsWith('wlan') || n.startsWith('en') || n.startsWith('eth');
          if (preferred) return ip;
          fallback ??= ip;
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  /// Starts serving [videoPath] (and optionally [subsPath]) on a random
  /// port on all interfaces. Returns false when it could not start.
  Future<bool> start({
    required String videoPath,
    required String videoMime,
    String? subsPath,
  }) async {
    await stop();
    try {
      final ip = await localIpV4();
      if (ip == null) return false;
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: true,
      );
      _server = server;
      _videoPath = videoPath;
      _videoMime = videoMime;
      _subsPath = subsPath;
      baseUrl = 'http://$ip:${server.port}';
      server.listen(_handle, onError: (_) {});
      return true;
    } catch (_) {
      await stop();
      return false;
    }
  }

  String? get videoUrl =>
      _server == null ? null : '$baseUrl/video.mp4';
  String? get subsUrl =>
      _server == null || _subsPath == null ? null : '$baseUrl/subs.srt';

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _videoPath = null;
    _subsPath = null;
    baseUrl = null;
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (_) {}
    }
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      switch (req.uri.path) {
        case '/video.mp4':
          await _serveFile(req, _videoPath!, _videoMime!);
          return;
        case '/subs.srt':
          final p = _subsPath;
          if (p != null) {
            await _serveFile(req, p, 'text/plain; charset=utf-8');
            return;
          }
          break;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  /// Serves [path] honouring a single byte Range. Streams via a buffered
  /// RandomAccessFile so back-to-back 4K reads don't spike memory.
  Future<void> _serveFile(HttpRequest req, String path, String mime) async {
    final file = File(path);
    if (!file.existsSync()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final size = await file.length();
    final res = req.response;

    int start = 0;
    int end = size - 1; // inclusive
    var partial = false;

    final rangeHeader = req.headers.value('range');
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring(6).split(',').first.trim();
      final dash = spec.indexOf('-');
      if (dash >= 0) {
        final fromRaw = spec.substring(0, dash);
        final toRaw = spec.substring(dash + 1);
        if (fromRaw.isEmpty) {
          // "bytes=-N": the last N bytes.
          final n = int.tryParse(toRaw) ?? 0;
          if (n > 0) {
            start = size - n;
            if (start < 0) start = 0;
            partial = true;
          }
        } else {
          final from = int.tryParse(fromRaw);
          if (from != null && from < size) {
            start = from;
            final to = int.tryParse(toRaw);
            if (to != null && to < end) end = to;
            partial = true;
          }
        }
      }
    }

    final length = end - start + 1;
    res.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
    res.headers.set(HttpHeaders.contentTypeHeader, mime);
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    // DLNA flags: OP=01 (range supported). Helps TVs buffer properly.
    res.headers.set(
      'contentFeatures.dlna.org',
      'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000',
    );
    res.headers.set('transferMode.dlna.org', 'Streaming');
    if (partial) {
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }
    res.contentLength = length;

    if (req.method == 'HEAD') {
      await res.close();
      return;
    }

    final raf = await file.open();
    try {
      await raf.setPosition(start);
      const chunk = 256 * 1024;
      var remaining = length;
      while (remaining > 0) {
        final toRead = remaining < chunk ? remaining : chunk;
        // Fresh buffer per chunk: res.add() writes asynchronously, so a
        // reused buffer could be mutated before its flush completed.
        final buf = Uint8List(toRead);
        final got = await raf.readInto(buf, 0, toRead);
        if (got <= 0) break;
        res.add(got == toRead ? buf : buf.sublist(0, got));
        remaining -= got;
        // Let the event loop breathe so the SOAP control channel stays
        // responsive on long pulls.
        await res.flush();
      }
      await res.close();
    } finally {
      try {
        await raf.close();
      } catch (_) {}
    }
  }
}
EOF_MARKER_23

cat > 'lib/cast/cast_state.dart' <<'EOF_MARKER_24'
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/native_bridge.dart';
import 'cast_file_server.dart';
import 'cast_support.dart';

enum CastPhase {
  /// Nothing happening.
  idle,

  /// SSDP discovery in flight.
  scanning,

  /// Scan finished; [devices] may be empty.
  scanDone,

  /// Handing the video to the chosen TV.
  connecting,

  /// TV is (or should be) playing; remote controls are live.
  casting,

  /// Something failed - [error] explains what, in plain words.
  error,
}

/// Owns one DLNA casting session: SSDP discovery of renderers, the SOAP
/// AVTransport control channel, the embedded file server the TV pulls the
/// video from, and 2-second position polling for the remote-control UI.
///
/// Everything is guarded: with no Wi-Fi, no devices, or a grumpy TV the
/// state machine lands in [CastPhase.error] instead of throwing.
class CastState extends ChangeNotifier {
  CastPhase phase = CastPhase.idle;
  List<DlnaDevice> devices = const [];
  DlnaDevice? current;
  String? error;

  // Polled from the TV while casting (remote-control slider).
  Duration tvPosition = Duration.zero;
  Duration tvDuration = Duration.zero;
  bool tvPlaying = false;

  /// How many SSDP replies we heard during the last scan. 0 = the
  /// network/router is eating multicast; >0 but no TVs = the answers
  /// weren't DLNA renderers. Shown in the sheet to make "no TVs found"
  /// diagnosable.
  int repliesSeen = 0;

  final CastFileServer _server = CastFileServer();
  Timer? _pollTimer;
  bool _disposed = false;

  String? get videoUrl => _server.videoUrl;

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  /// Multicasts SSDP M-SEARCH for ~4 seconds and describes whatever
  /// answers. Safe to call repeatedly.
  Future<void> scan() async {
    if (phase == CastPhase.scanning || phase == CastPhase.connecting) return;
    phase = CastPhase.scanning;
    devices = const [];
    error = null;
    repliesSeen = 0;
    notifyListeners();

    await NativeBridge.setMulticastLock(true);
    final locations = <String>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
          .timeout(const Duration(seconds: 3));
      final s = socket; // bind succeeded, non-nullable from here on
      final target = InternetAddress('239.255.255.250');
      final packets = [
        ascii.encode(
            buildMSearchRequest('urn:schemas-upnp-org:device:MediaRenderer:1')),
        ascii.encode(buildMSearchRequest('ssdp:all')),
      ];

      final sub = s.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? dg;
        while ((dg = s.receive()) != null) {
          repliesSeen++;
          final text = utf8.decode(dg!.data, allowMalformed: true);
          final loc = ssdpHeader(text, 'location');
          if (loc != null && loc.startsWith('http')) locations.add(loc);
        }
      });

      // Four waves over ~2s then a quiet listening window - multicast UDP
      // can drop packets, and some TVs are slow to answer.
      for (var wave = 0; wave < 4; wave++) {
        for (final p in packets) {
          try {
            s.send(p, target, 1900);
          } catch (_) {}
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await Future<void>.delayed(const Duration(milliseconds: 3200));
      await sub.cancel();
    } catch (e) {
      phase = CastPhase.error;
      error = 'Wi-Fi scan failed (${e.runtimeType}). Connect both phone and '
          'TV to the same Wi-Fi and retry.';
      notifyListeners();
      socket?.close();
      await NativeBridge.setMulticastLock(false);
      return;
    }
    socket.close();
    await NativeBridge.setMulticastLock(false);

    // Fetch each responder's description (in parallel) and keep renderers.
    final found = await Future.wait([
      for (final loc in locations) _describe(loc),
    ]);
    final seen = <String>{};
    final list = <DlnaDevice>[];
    for (final d in found) {
      if (d == null) continue;
      if (!seen.add(d.controlUrl)) continue; // same TV via two LOCATIONs
      list.add(d);
    }
    if (_disposed) return;
    devices = list;
    phase = CastPhase.scanDone;
    notifyListeners();
  }

  Future<DlnaDevice?> _describe(String location) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 4);
      final req = await client
          .getUrl(Uri.parse(location))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
      return parseDeviceDescription(body, location);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Connect + control
  // ---------------------------------------------------------------------------

  /// Starts the file server (for local files; streams are handed to the TV
  /// directly), points the TV at the video and presses play.
  Future<void> connect(
    DlnaDevice device, {
    required String videoPath,
    required String title,
    String? subsPath,
  }) async {
    phase = CastPhase.connecting;
    current = device;
    error = null;
    tvPosition = Duration.zero;
    tvDuration = Duration.zero;
    tvPlaying = false;
    notifyListeners();

    try {
      String videoUrl;
      String? subsUrl;
      final mime = mimeForExtension(videoPath);
      if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
        // Network stream: the TV pulls it straight from the internet; the
        // phone only acts as the remote control.
        videoUrl = videoPath;
        subsUrl = null;
      } else {
        final hasSubs = subsPath != null && File(subsPath).existsSync();
        final ok = await _server.start(
          videoPath: videoPath,
          videoMime: mime,
          subsPath: hasSubs ? subsPath : null,
        );
        if (!ok) {
          throw StateError('could not start the phone-side media server '
              '(no Wi-Fi?)');
        }
        videoUrl = _server.videoUrl!;
        subsUrl = _server.subsUrl;
      }

      final metadata = buildDidlMetadata(
        title: title,
        videoUrl: videoUrl,
        mime: mime,
        subsUrl: subsUrl,
      );
      await _soap(device.controlUrl, 'SetAVTransportURI', [
        MapEntry('CurrentURI', videoUrl),
        MapEntry('CurrentURIMetadata', metadata),
      ]);
      await _soap(device.controlUrl, 'Play', [const MapEntry('Speed', '1')]);

      if (_disposed) return;
      phase = CastPhase.casting;
      tvPlaying = true;
      notifyListeners();
      _startPolling();
    } catch (e) {
      await _server.stop();
      if (_disposed) return;
      phase = CastPhase.error;
      current = null;
      error = 'The TV rejected the stream '
          '(${e.toString().split('\n').first}). The video format may be '
          'unsupported by this TV, or the connection dropped.';
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    final device = current;
    if (phase != CastPhase.casting || device == null) return;
    final action = tvPlaying ? 'Pause' : 'Play';
    // Optimistic UI; the next poll corrects it if the TV disagrees.
    tvPlaying = !tvPlaying;
    notifyListeners();
    try {
      await _soap(device.controlUrl, action, [
        if (action == 'Play') const MapEntry('Speed', '1'),
      ]);
    } catch (_) {}
  }

  Future<void> seekTo(Duration target) async {
    final device = current;
    if (phase != CastPhase.casting || device == null) return;
    tvPosition = target;
    notifyListeners();
    try {
      await _soap(device.controlUrl, 'Seek', [
        const MapEntry('Unit', 'REL_TIME'),
        MapEntry('Target', formatRelTime(target)),
      ]);
    } catch (_) {}
  }

  /// Stops playback on the TV and tears everything down.
  Future<void> stopCast({bool tellTv = true}) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final device = current;
    if (tellTv && device != null && phase == CastPhase.casting) {
      try {
        await _soap(device.controlUrl, 'Stop', []);
      } catch (_) {}
    }
    await _server.stop();
    if (_disposed) return;
    current = null;
    tvPosition = Duration.zero;
    tvDuration = Duration.zero;
    tvPlaying = false;
    phase = CastPhase.idle;
    error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // SOAP plumbing + polling
  // ---------------------------------------------------------------------------

  Future<String> _soap(
    String controlUrl,
    String action,
    List<MapEntry<String, String>> args,
  ) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 6);
      final req = await client
          .postUrl(Uri.parse(controlUrl))
          .timeout(const Duration(seconds: 6));
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/xml; charset="utf-8"',
      );
      req.headers.set(
        'SOAPACTION',
        '"$avTransportServiceType#$action"',
      );
      req.write(buildSoapEnvelope(action, args));
      final res = await req.close().timeout(const Duration(seconds: 6));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw SocketException('SOAP $action -> HTTP ${res.statusCode}');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // First poll right away so the slider has real values quickly.
    _poll();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    final device = current;
    if (_disposed || phase != CastPhase.casting || device == null) return;
    try {
      final info = await _soap(device.controlUrl, 'GetTransportInfo', []);
      final state = soapTag(info, 'CurrentTransportState');
      final posBody = await _soap(device.controlUrl, 'GetPositionInfo', []);
      final rel = parseRelTime(soapTag(posBody, 'RelTime'));
      final dur = parseRelTime(soapTag(posBody, 'TrackDuration'));
      if (_disposed) return;
      if (state == 'PLAYING') {
        tvPlaying = true;
      } else if (state != 'TRANSITIONING') {
        tvPlaying = false; // PAUSED_PLAYBACK / STOPPED / NO_MEDIA_PRESENT
      } // TRANSITIONING: keep the previous play/pause state.
      if (rel != null) tvPosition = rel;
      if (dur != null) tvDuration = dur;
      notifyListeners();
    } catch (_) {
      // Transient network hiccup - the next tick retries.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    current = null;
    unawaited(_server.stop());
    super.dispose();
  }
}
EOF_MARKER_24

cat > 'lib/widgets/about_sheet.dart' <<'EOF_MARKER_25'
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/native_bridge.dart';
import '../state/theme_state.dart';

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
EOF_MARKER_25

cat > 'lib/widgets/cast_sheet.dart' <<'EOF_MARKER_26'
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
                      color: Colors.white24,
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
                      const Expanded(
                        child: Text(
                          'Cast to TV',
                          style: TextStyle(
                            color: Colors.white,
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
                leading: const Icon(Icons.tv, color: Colors.white70),
                title: Text(
                  d.name,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                subtitle: const Text(
                  'Tap to start casting',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Playing on your TV - this phone is the remote',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
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
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  max: max,
                  onChanged: (v) {},
                  onChangeEnd: (v) =>
                      cast.seekTo(Duration(milliseconds: v.round())),
                  activeColor: _accent,
                  inactiveColor: Colors.white12,
                ),
              ),
              Text(
                formatDuration(total),
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
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
                color: Colors.white,
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
          Icon(icon, color: Colors.white38, size: 42),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
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
EOF_MARKER_26

cat > 'lib/widgets/display_settings_sheet.dart' <<'EOF_MARKER_27'
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
                  child: Row(
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
            color: selected ? Colors.white : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
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
EOF_MARKER_27

cat > 'lib/widgets/track_selection_sheet.dart' <<'EOF_MARKER_28'
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
                color: Colors.white24,
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
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('No audio tracks found',
            style: TextStyle(color: Colors.white38)),
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
        const Divider(height: 16, color: Colors.white12),
        // Offline AI subtitle generation (whisper.cpp) - free, no internet
        // after the one-time model download.
        ListTile(
          dense: true,
          leading: Icon(Icons.auto_awesome,
              size: 20, color: TrackSelectionSheet._accent),
          title: const Text(
            'Generate with AI ✨',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Offline & free · the AI writes subtitles for this video',
            style: TextStyle(color: Colors.white38, fontSize: 12),
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
          color: selected ? Colors.white : Colors.white70,
          fontSize: 15,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: (detail != null && detail!.isNotEmpty)
          ? Text(detail!,
              style: const TextStyle(color: Colors.white38, fontSize: 12))
          : null,
    );
  }
}
EOF_MARKER_28

cat > 'lib/widgets/player_settings_sheet.dart' <<'EOF_MARKER_29'
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
                  color: Colors.white24,
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
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 15)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
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
      style: const TextStyle(color: Colors.white70, fontSize: 13),
      items: [
        for (final e in entries.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: onChanged,
    );
  }
}
EOF_MARKER_29

cat > 'lib/widgets/equalizer_sheet.dart' <<'EOF_MARKER_30'
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
                  color: Colors.white24,
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
                        labelStyle: const TextStyle(color: Colors.white70),
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
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        SizedBox(
          height: 140,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: accent,
                thumbColor: accent,
                inactiveTrackColor: Colors.white12,
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
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}
EOF_MARKER_30

cat > 'lib/widgets/fade_in_image.dart' <<'EOF_MARKER_31'
import 'package:flutter/material.dart';

/// Shared [Image.frameBuilder]: thumbnails fade in softly (~220ms) instead
/// of popping onto the screen. Wraps the decoded frame of any Image.file /
/// Image.network that doesn't already handle transitions.
Widget fadeInImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
    child: child,
  );
}
EOF_MARKER_31

cat > 'lib/widgets/gesture_illustrations.dart' <<'EOF_MARKER_32'
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/theme_state.dart';

/// Vector-drawn illustrations for the gesture guide in the user manual.
/// They are painted in code (CustomPaint) instead of bundled image files:
/// always crisp at any DPI, they follow the app's accent colour, and they
/// add zero weight to the APK.
enum GestureKind {
  singleTap,
  doubleTapSides,
  doubleTapMiddle,
  swipeBrightness,
  swipeVolume,
  swipeSeek,
  pinchZoom,
  holdSpeed,
}

class GestureIllustration extends StatelessWidget {
  final GestureKind kind;
  final double height;

  const GestureIllustration({
    super.key,
    required this.kind,
    this.height = 110,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _GesturePainter(kind, themeState.accent),
      ),
    );
  }
}

class _GesturePainter extends CustomPainter {
  final GestureKind kind;
  final Color accent;

  _GesturePainter(this.kind, this.accent);

  // ---------- helpers -------------------------------------------------------

  Paint get _thinWhite => Paint()
    ..color = Colors.white60
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  Paint get _accentPaint => Paint()
    ..color = accent
    ..strokeWidth = 2.4
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  RRect _phone(Size size) {
    final w = size.width * 0.86;
    final h = size.height * 0.72;
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2 + 4),
        width: w,
        height: h);
    return RRect.fromRectAndRadius(rect, const Radius.circular(14));
  }

  void _drawPhone(Canvas canvas, Size size) {
    final phone = _phone(size);
    // Body.
    canvas.drawRRect(
        phone,
        Paint()
          ..color = const Color(0xFF181824)
          ..style = PaintingStyle.fill);
    // Screen with a soft gradient.
    final screen = phone.deflate(3);
    final rect = screen.outerRect;
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF232838), Color(0xFF12141f)],
        ).createShader(rect),
    );
    // Border.
    canvas.drawRRect(
        phone,
        Paint()
          ..color = Colors.white30
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // A dim "play" triangle to suggest a video on the screen.
    final c = screen.center;
    final tri = Path()
      ..moveTo(c.dx - 7, c.dy - 10)
      ..lineTo(c.dx + 10, c.dy)
      ..lineTo(c.dx - 7, c.dy + 10)
      ..close();
    canvas.drawPath(
        tri,
        Paint()
          ..color = Colors.white10
          ..style = PaintingStyle.fill);
  }

  void _arrow(Canvas canvas, Offset from, Offset to, [Paint? paint]) {
    final p = paint ?? _thinWhite;
    canvas.drawLine(from, to, p);
    final angle = (to - from).direction;
    for (final delta in [2.55, -2.55]) {
      final a = angle + delta;
      canvas.drawLine(
          to,
          to + Offset(math.cos(a) * 8, math.sin(a) * 8),
          p);
    }
  }

  /// A "finger tap" ripple: small accent dot + two expanding rings.
  void _tapRipple(Canvas canvas, Offset at) {
    canvas.drawCircle(
        at,
        5,
        Paint()
          ..color = accent
          ..style = PaintingStyle.fill);
    for (final r in [11.0, 18.0]) {
      canvas.drawCircle(
          at,
          r,
          Paint()
            ..color = accent.withValues(alpha: r == 11.0 ? 0.5 : 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  /// A held fingertip: filled dot with white ring and soft halo.
  void _fingertip(Canvas canvas, Offset at) {
    canvas.drawCircle(
        at,
        13,
        Paint()
          ..color = accent.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        at,
        7,
        Paint()
          ..color = accent
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        at,
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  void _label(Canvas canvas, String text, Offset center,
      {double size = 10, Color color = Colors.white70}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color, fontSize: size, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _sunGlyph(Canvas canvas, Offset at, double r) {
    const amber = Color(0xFFFFC107);
    final p = Paint()
      ..color = amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(at, r, p);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawLine(
        at + Offset(math.cos(a) * (r + 3), math.sin(a) * (r + 3)),
        at + Offset(math.cos(a) * (r + 7), math.sin(a) * (r + 7)),
        p,
      );
    }
  }

  void _speakerGlyph(Canvas canvas, Offset at) {
    final p = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    // Cone.
    final path = Path()
      ..moveTo(at.dx - 9, at.dy - 4)
      ..lineTo(at.dx - 4, at.dy - 4)
      ..lineTo(at.dx + 1, at.dy - 9)
      ..lineTo(at.dx + 1, at.dy + 9)
      ..lineTo(at.dx - 4, at.dy + 4)
      ..lineTo(at.dx - 9, at.dy + 4)
      ..close();
    canvas.drawPath(path, p);
    // Sound waves.
    for (final r in [5.0, 9.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: at + const Offset(3, 0), radius: r),
        -0.9,
        1.8,
        false,
        p,
      );
    }
  }

  /// Tinted half of the screen (left or right) with up/down arrows in it.
  void _halfSwipe(Canvas canvas, Size size,
      {required bool leftHalf,
      required Color tint,
      required IconKindDoodle doodle}) {
    final phone = _phone(size);
    final screen = phone.deflate(3);
    final r = screen.outerRect;
    final half = leftHalf
        ? Rect.fromLTRB(r.left, r.top, r.center.dx, r.bottom)
        : Rect.fromLTRB(r.center.dx, r.top, r.right, r.bottom);
    canvas.save();
    canvas.clipRRect(screen);
    canvas.drawRect(
        half,
        Paint()
          ..color = tint.withValues(alpha: 0.14)
          ..style = PaintingStyle.fill);
    // Divider down the middle.
    canvas.drawLine(
        Offset(r.center.dx, r.top + 6),
        Offset(r.center.dx, r.bottom - 6),
        Paint()
          ..color = Colors.white24
          ..strokeWidth = 1);
    canvas.restore();

    final ax = half.center.dx;
    final cy = half.center.dy;
    _arrow(canvas, Offset(ax, cy - 8), Offset(ax, cy - 28), _accentPaint);
    _arrow(canvas, Offset(ax, cy + 8), Offset(ax, cy + 28), _accentPaint);
    if (doodle == IconKindDoodle.sun) {
      _sunGlyph(canvas, Offset(ax, r.top + 15), 5.5);
    } else {
      _speakerGlyph(canvas, Offset(ax, r.top + 17));
    }
  }

  // ---------- scene ---------------------------------------------------------

  @override
  void paint(Canvas canvas, Size size) {
    _drawPhone(canvas, size);
    final phone = _phone(size);
    final screen = phone.deflate(3);
    final c = screen.center;
    final r = screen.outerRect;

    switch (kind) {
      case GestureKind.singleTap:
        _tapRipple(canvas, c);
        break;

      case GestureKind.doubleTapSides:
        _tapRipple(canvas, Offset(r.left + r.width * 0.24, c.dy - 4));
        _tapRipple(canvas, Offset(r.right - r.width * 0.24, c.dy - 4));
        _label(canvas, '-10s',
            Offset(r.left + r.width * 0.24, r.bottom - 10));
        _label(canvas, '+10s',
            Offset(r.right - r.width * 0.24, r.bottom - 10));
        break;

      case GestureKind.doubleTapMiddle:
        _tapRipple(canvas, Offset(c.dx, c.dy - 2));
        // Pause bars (what the middle double-tap toggles).
        final p = Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.fill;
        canvas.drawRect(
            Rect.fromLTWH(c.dx - 6, c.dy + 14, 4, 12), p);
        canvas.drawRect(
            Rect.fromLTWH(c.dx + 2, c.dy + 14, 4, 12), p);
        break;

      case GestureKind.swipeBrightness:
        _halfSwipe(canvas, size,
            leftHalf: true,
            tint: const Color(0xFFFFC107),
            doodle: IconKindDoodle.sun);
        break;

      case GestureKind.swipeVolume:
        _halfSwipe(canvas, size,
            leftHalf: false,
            tint: accent,
            doodle: IconKindDoodle.speaker);
        break;

      case GestureKind.swipeSeek:
        // Fingertip sliding sideways across the screen, with the "+45s ·
        // 03:12" pill the real player shows while scrubbing.
        final fy = c.dy + 8;
        _fingertip(canvas, Offset(c.dx, fy));
        _arrow(canvas, Offset(c.dx - 16, fy), Offset(c.dx - 48, fy),
            _accentPaint);
        _arrow(canvas, Offset(c.dx + 16, fy), Offset(c.dx + 48, fy),
            _accentPaint);
        // Landing pill, like the indicator in the player.
        final pill = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, r.top + 13), width: 92, height: 18),
            const Radius.circular(9));
        canvas.drawRRect(
            pill,
            Paint()
              ..color = accent
              ..style = PaintingStyle.fill);
        _label(canvas, '+45s · 03:12', Offset(c.dx, r.top + 13),
            color: Colors.white, size: 9.5);
        _label(canvas, 'or the other way', Offset(c.dx, r.bottom - 9),
            size: 8.5);
        break;

      case GestureKind.pinchZoom:
        // Two fingertips spreading apart with outward arrows.
        final fa = Offset(c.dx - 26, c.dy + 14);
        final fb = Offset(c.dx + 26, c.dy + 14);
        _arrow(canvas, fa, Offset(fa.dx - 18, fa.dy - 18), _accentPaint);
        _arrow(canvas, fb, Offset(fb.dx + 18, fb.dy - 18), _accentPaint);
        _fingertip(canvas, fa);
        _fingertip(canvas, fb);
        _label(canvas, '1× → 4×', Offset(c.dx, r.bottom - 10));
        break;

      case GestureKind.holdSpeed:
        _fingertip(canvas, Offset(c.dx, c.dy + 10));
        // Persistent "2x" badge, like the one shown during a real boost.
        final badge = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, r.top + 13), width: 40, height: 18),
            const Radius.circular(9));
        canvas.drawRRect(
            badge,
            Paint()
              ..color = accent
              ..style = PaintingStyle.fill);
        _label(canvas, '2.0x', Offset(c.dx, r.top + 13),
            color: Colors.white, size: 10.5);
        break;
    }
  }

  @override
  bool shouldRepaint(_GesturePainter old) =>
      old.kind != kind || old.accent != accent;
}

enum IconKindDoodle { sun, speaker }
EOF_MARKER_32

cat > 'lib/widgets/mini_player.dart' <<'EOF_MARKER_33'
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
                          backgroundColor: Colors.white10,
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
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      '${formatDuration(player.position)} / ${formatDuration(player.duration)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white38,
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
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white38,
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
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 16, color: Colors.white24),
      ),
    );
  }
}
EOF_MARKER_33

cat > 'lib/widgets/user_manual_sheet.dart' <<'EOF_MARKER_34'
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
EOF_MARKER_34

cat > 'lib/widgets/video_info_sheet.dart' <<'EOF_MARKER_35'
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

  const VideoInfoSheet({super.key, required this.player});

  static Future<void> show(BuildContext context, MediaPlayerState player) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => VideoInfoSheet(player: player),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = player.currentTrack;
    final accent = themeState.accent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
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
              const Text('Nothing is loaded right now',
                  style: TextStyle(color: Colors.white38))
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
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
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
EOF_MARKER_35

cat > 'lib/widgets/video_tile.dart' <<'EOF_MARKER_36'
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
EOF_MARKER_36

cat > 'lib/widgets/video_list_item.dart' <<'EOF_MARKER_37'
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
EOF_MARKER_37

cat > 'lib/widgets/player_controls_overlay.dart' <<'EOF_MARKER_38'
import 'package:flutter/material.dart' hide RepeatMode;
import '../models/video_track.dart' show RepeatMode;
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import 'progress_bar.dart';
import 'track_selection_sheet.dart';

/// Controls drawn on top of the video. Two slim rows are used instead of one
/// long row - the previous single-row layout needed ~540dp and overflowed
/// (black/yellow error stripes) on portrait phones. Row 2 uses compact 34dp
/// buttons so all options fit on narrow screens.
///
/// This widget rebuilds itself via [AnimatedBuilder] on every player tick,
/// so the parent screen does NOT rebuild (which kept recreating the video
/// surface and caused fullscreen flicker).
class PlayerControlsOverlay extends StatelessWidget {
  final MediaPlayerState player;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleQueue;

  /// Fired on every control interaction; the screen uses it to restart the
  /// auto-hide countdown.
  final VoidCallback onInteract;

  /// Cycles the video fit (contain -> cover -> fill).
  final VoidCallback onCycleFit;

  /// Rotation lock toggle (auto-rotate vs locked to current orientation).
  final bool orientationLocked;
  final VoidCallback onToggleOrientationLock;

  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onToggleQueue,
    required this.onInteract,
    required this.onCycleFit,
    required this.orientationLocked,
    required this.onToggleOrientationLock,
  });

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressBar(
                position: player.position,
                duration: player.duration,
                onSeek: (d) {
                  player.seek(d);
                  onInteract();
                },
              ),
              // Row 1: playback (shuffle | -10s prev play next +10s | repeat)
              Row(
                children: [
                  _iconBtn(
                    icon: player.isShuffled
                        ? Icons.shuffle_on_outlined
                        : Icons.shuffle,
                    active: player.isShuffled,
                    onTap: player.toggleShuffle,
                  ),
                  const Spacer(),
                  _iconBtn(
                    icon: Icons.replay_10,
                    onTap: () => player.seekBy(-10),
                  ),
                  _iconBtn(icon: Icons.skip_previous, onTap: player.prevTrack),
                  _iconBtn(
                    icon: player.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 40,
                    onTap: player.togglePlay,
                  ),
                  _iconBtn(icon: Icons.skip_next, onTap: player.nextTrack),
                  _iconBtn(
                    icon: Icons.forward_10,
                    onTap: () => player.seekBy(10),
                  ),
                  const Spacer(),
                  _iconBtn(
                    icon: switch (player.repeatMode) {
                      RepeatMode.none => Icons.repeat,
                      RepeatMode.all => Icons.repeat_on_outlined,
                      RepeatMode.one => Icons.repeat_one_on_outlined,
                    },
                    active: player.repeatMode != RepeatMode.none,
                    onTap: player.toggleRepeat,
                  ),
                ],
              ),
              // Row 2 (compact): mute speed audio subs fit AB rotate | queue fs
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
                  _iconBtn(
                    icon: Icons.audiotrack_outlined,
                    // Highlight when the file actually offers multiple tracks.
                    active: player.audioTracks.length > 1,
                    onTap: () => TrackSelectionSheet.show(
                      context,
                      player,
                      isSubtitle: false,
                    ),
                    compact: true,
                  ),
                  _iconBtn(
                    icon: player.subtitlesActive
                        ? Icons.subtitles
                        : Icons.subtitles_outlined,
                    active: player.subtitlesActive,
                    onTap: () => TrackSelectionSheet.show(
                      context,
                      player,
                      isSubtitle: true,
                    ),
                    compact: true,
                  ),
                  _iconBtn(
                    icon: Icons.aspect_ratio,
                    onTap: onCycleFit,
                    compact: true,
                  ),
                  _abButton(accent),
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
                    icon: isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    onTap: onToggleFullscreen,
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

  /// A-B loop: compact two-letter button; each letter lights up when set.
  Widget _abButton(Color accent) {
    final hasA = player.loopA != null;
    final hasB = player.loopB != null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        player.tapLoopPoint();
        onInteract();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'A',
                style: TextStyle(
                  color: hasA ? accent : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const TextSpan(
                text: '→',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              TextSpan(
                text: 'B',
                style: TextStyle(
                  color: hasB ? accent : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
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
      itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
          .map((r) => PopupMenuItem(
                value: r,
                child: Text('${r}x',
                    style: const TextStyle(color: Colors.white)),
              ))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Text('${player.playbackRate}x',
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    double size = 24,
    bool compact = false,
  }) {
    final accent = themeState.accent;
    return IconButton(
      icon: Icon(icon, size: compact ? 20 : size,
          color: active ? accent : Colors.white),
      // Compact rows must fit ~9 actions on a 320dp-wide phone.
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
EOF_MARKER_38

cat > 'lib/widgets/progress_bar.dart' <<'EOF_MARKER_39'
import 'package:flutter/material.dart';
import '../utils/formatters.dart';
import '../state/theme_state.dart';

class VideoProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const VideoProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  double? _dragValue; // 0..1 while user is dragging

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds.clamp(1, 1 << 62);
    final value = _dragValue ?? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Row(
      children: [
        Text(formatDuration(widget.position), style: _timeStyle),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: themeState.accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
              thumbColor: themeState.accent,
            ),
            child: Slider(
              value: value,
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                widget.onSeek(Duration(milliseconds: (v * totalMs).round()));
                setState(() => _dragValue = null);
              },
            ),
          ),
        ),
        Text(formatDuration(widget.duration), style: _timeStyle),
      ],
    );
  }

  static const _timeStyle = TextStyle(fontSize: 12, color: Colors.white70);
}
EOF_MARKER_39

cat > 'lib/widgets/playlist_panel.dart' <<'EOF_MARKER_40'
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Collapse playlist',
                icon: const Icon(
                  Icons.last_page,
                  size: 20,
                  color: Colors.white70,
                ),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: playlist.isEmpty
              ? const Center(
                  child: Text(
                    'Queue is empty',
                    style: TextStyle(color: Colors.white38),
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
                          ? Colors.white.withValues(alpha: 0.08)
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
                          color: active ? Colors.white : Colors.white70,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        _subtitleFor(track),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white38,
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
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 16, color: Colors.white24),
      ),
    );
  }
}
EOF_MARKER_40

cat > 'lib/screens/library_screen.dart' <<'EOF_MARKER_41'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_info.dart';
import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/crash_log.dart';
import '../widgets/about_sheet.dart';
import '../widgets/display_settings_sheet.dart';
import '../widgets/mini_player.dart';
import '../widgets/user_manual_sheet.dart';
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
                  return VideoTile(
                    track: track,
                    isFavorite: lib.isFavorite(track),
                    onTap: () => _playVideo(track),
                    onFavorite: () => lib.toggleFavorite(track),
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
                  return VideoListItem(
                    track: track,
                    isFavorite: lib.isFavorite(track),
                    onTap: () => _playVideo(track),
                    onFavorite: () => lib.toggleFavorite(track),
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
EOF_MARKER_41

cat > 'lib/screens/player_screen.dart' <<'EOF_MARKER_42'
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
EOF_MARKER_42

cat > 'lib/screens/history_screen.dart' <<'EOF_MARKER_43'
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import '../state/media_player_state.dart';
import '../utils/formatters.dart';
import 'player_screen.dart';
import '../state/theme_state.dart';

/// Watch history - most recently opened videos first, each with its saved
/// progress. Tapping resumes where you left off.
class HistoryScreen extends StatelessWidget {
  final MediaPlayerState player;

  const HistoryScreen({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        title: const Text('History'),
        actions: [
          AnimatedBuilder(
            animation: player,
            builder: (context, _) => player.history.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear history',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => _confirmClear(context),
                  ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          final entries = player.history;
          if (entries.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 48, color: Colors.white24),
                  SizedBox(height: 12),
                  Text(
                    'Nothing watched yet.\nVideos you open will show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              indent: 120,
              color: Color(0xFF1a1a24),
            ),
            itemBuilder: (context, i) =>
                _HistoryTile(entry: entries[i], player: player),
          );
        },
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Clear history?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This also resets the saved resume position of every video.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: themeState.accent),
            onPressed: () {
              player.clearHistory();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final MediaPlayerState player;

  const _HistoryTile({required this.entry, required this.player});

  @override
  Widget build(BuildContext context) {
    final position = Duration(seconds: entry.lastPositionSecs);
    final total = Duration(seconds: entry.durationSecs);
    final posLabel = formatDuration(position);
    final totalLabel = formatDuration(total);
    final hasProgress = entry.durationSecs > 0 && entry.lastPositionSecs > 0;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 96,
          height: 54,
          child: _thumb(),
        ),
      ),
      title: Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            hasProgress
                ? '${timeAgo(entry.playedAtMs)}  ·  $posLabel / $totalLabel'
                : timeAgo(entry.playedAtMs),
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
          if (hasProgress) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: entry.progress,
                minHeight: 3,
                backgroundColor: Colors.white10,
                color: themeState.accent,
              ),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18, color: Colors.white38),
        tooltip: 'Remove from history',
        onPressed: () => player.removeHistoryEntry(entry.path),
      ),
      onTap: () {
        player.playHistoryEntry(entry);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlayerScreen(player: player)),
        );
      },
    );
  }

  Widget _thumb() {
    if (entry.thumbnailPath != null) {
      return Image.file(
        File(entry.thumbnailPath!),
        fit: BoxFit.cover,
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
EOF_MARKER_43

cat > 'lib/screens/stats_screen.dart' <<'EOF_MARKER_44'
import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// Weekly watch-time statistics - a 7-day bar chart plus totals.
class StatsScreen extends StatelessWidget {
  final MediaPlayerState player;

  const StatsScreen({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        title: const Text('Statistics'),
      ),
      body: FutureBuilder<List<WatchDay>>(
        future: player.getWeekStats(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: accent),
            );
          }
          final days = snapshot.data!;
          final weekTotal =
              days.fold<int>(0, (sum, d) => sum + d.seconds);
          final maxSecs =
              days.fold<int>(60, (m, d) => d.seconds > m ? d.seconds : m);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                formatWatchTime(weekTotal),
                style: TextStyle(
                  color: accent,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'watched this week',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in days) _DayBar(day: d, maxSecs: maxSecs),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Daily average: ${formatWatchTime(weekTotal ~/ 7)}',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final WatchDay day;
  final int maxSecs;

  const _DayBar({required this.day, required this.maxSecs});

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final isToday = _isSameDay(day.day, DateTime.now());
    final fraction = (day.seconds / maxSecs).clamp(0.0, 1.0);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              day.seconds > 0 ? formatWatchTime(day.seconds) : '',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: fraction == 0 ? 0.02 : fraction,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isToday
                          ? accent
                          : Colors.white.withValues(alpha: 0.16),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _weekdays[day.day.weekday - 1],
              style: TextStyle(
                color: isToday ? accent : Colors.white38,
                fontSize: 11,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
EOF_MARKER_44

cat > 'test/widget_test.dart' <<'EOF_MARKER_45'
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/app_info.dart';
import 'package:maxplayer/cast/cast_support.dart';
import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/state/media_player_state.dart';
import 'package:maxplayer/state/player_settings.dart';
import 'package:maxplayer/state/video_library_state.dart';
import 'package:maxplayer/utils/formatters.dart';
import 'package:maxplayer/utils/srt.dart';
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
  });
}
EOF_MARKER_45

echo ""
echo "==> Done! Now run:"
echo "    git add -A && git commit -m \"v14: crash journal, AI persistence+language picker, cast diagnostics, Play Store packaging (AAB, signing, com.hypertechlabs)\" && git push"
echo ""
echo "==> NOTE: after installing the new build, open a video; if the app"
echo "    closes again, REOPEN the app - a copyable crash report appears in"
echo "    the library. Send that text with your next message."
