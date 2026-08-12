#!/bin/bash
# ============================================================
# Max Player - v10 update (size cut + AI subtitles Phase 1)
# ============================================================
#   APK SIZE (was ~93 MB):
#   * The default build shipped native libs for FOUR CPU
#     architectures. Now arm64-v8a only (every phone from ~2017+)
#     -> APK should land around 30-35 MB.
#
#   AI SUBTITLES - PHASE 1 (engine in, 100% free & offline):
#   * Bundles the prebuilt whisper.cpp engine (Maven AAR, ~1.1 MB,
#     MIT license - a plain dependency, NOT a Gradle/Flutter plugin,
#     so no toolchain conflicts).
#   * New native probe "whisperAvailable" + About sheet now shows
#     "AI subtitle engine: ready (offline & free)" when it loads on
#     your phone - check it after installing!
#   * Phases 2-4 (audio extraction, transcription, SRT + UI) come
#     next; nothing user-facing yet.
#
# HOW TO USE (on the Pi):
#   cd ~/IdeaProjects/maxplayer
#   nano update10.sh      # paste this whole file, save & exit
#   bash update10.sh
#   git add -A && git commit -m "v10: arm64-only build (93MB -> ~33MB), whisper.cpp engine Phase 1" && git push
# ============================================================
set -e
cd "$(dirname "$0")"
echo "==> Applying Max Player v10 files..."
mkdir -p "$(dirname 'android/app/src/main/AndroidManifest.xml')"
cat > 'android/app/src/main/AndroidManifest.xml' <<'EOF_MARKER_0'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
        tools:ignore="ScopedStorage" />
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
mkdir -p "$(dirname 'android/app/src/main/kotlin/com/example/maxplayer/MainActivity.kt')"
cat > 'android/app/src/main/kotlin/com/example/maxplayer/MainActivity.kt' <<'EOF_MARKER_1'
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
import dev.ffmpegkit.whisper.Whisper
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
EOF_MARKER_1
mkdir -p "$(dirname 'android/app/build.gradle.kts')"
cat > 'android/app/build.gradle.kts' <<'EOF_MARKER_2'
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.maxplayer"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.maxplayer"
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
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
}
EOF_MARKER_2
mkdir -p "$(dirname 'pubspec.yaml')"
cat > 'pubspec.yaml' <<'EOF_MARKER_3'
name: maxplayer
description: "Max Player - a local video library & player."
publish_to: 'none'
version: 1.0.0+10

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
EOF_MARKER_3
mkdir -p "$(dirname 'lib/app_info.dart')"
cat > 'lib/app_info.dart' <<'EOF_MARKER_4'
/// Central app identity. Bump together with pubspec.yaml's version
/// (versionName = kAppVersion). Shown in the ⋮ menu footer, the user
/// manual and the About sheet - one place to update for all of them.
const String kAppVersion = '1.0.0';
EOF_MARKER_4
mkdir -p "$(dirname 'lib/main.dart')"
cat > 'lib/main.dart' <<'EOF_MARKER_5'
import 'dart:io';

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

// Global keys so a native "Open with" callback can navigate + snackbar from
// anywhere, without a BuildContext of its own.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> _messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  // Must be called before any media_kit Player is created.
  MediaKit.ensureInitialized();
  // Follow the phone's own rotation everywhere; the player's lock button
  // temporarily restricts it (and restores on exit).
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  runApp(const MaxPlayerApp());
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
EOF_MARKER_5
mkdir -p "$(dirname 'lib/services/native_bridge.dart')"
cat > 'lib/services/native_bridge.dart' <<'EOF_MARKER_6'
import 'package:flutter/services.dart';

/// Result of a native metadata extraction for one video file.
class VideoMetadata {
  final Duration? duration;
  final String? thumbnailPath;
  final int? width;
  final int? height;

  const VideoMetadata({
    this.duration,
    this.thumbnailPath,
    this.width,
    this.height,
  });
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
  static bool _handlerRegistered = false;

  /// Registers (or replaces) the app-level native event callbacks.
  static void configureCallbacks({
    void Function(String path)? onOpenVideo,
    void Function(String uri)? onOpenVideoFailed,
    void Function(bool isPip)? onPipChanged,

    /// Fired when the play/pause button ON THE PiP WINDOW is tapped.
    void Function()? onPipAction,
  }) {
    if (onOpenVideo != null) _onOpenVideo = onOpenVideo;
    if (onOpenVideoFailed != null) _onOpenVideoFailed = onOpenVideoFailed;
    if (onPipChanged != null) _onPipChanged = onPipChanged;
    if (onPipAction != null) _onPipAction = onPipAction;
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
      return VideoMetadata(
        duration: durationMs is int ? Duration(milliseconds: durationMs) : null,
        thumbnailPath: res['thumbnailPath'] as String?,
        width: width is int ? width : null,
        height: height is int ? height : null,
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
}
EOF_MARKER_6
mkdir -p "$(dirname 'lib/models/video_track.dart')"
cat > 'lib/models/video_track.dart' <<'EOF_MARKER_7'
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
EOF_MARKER_7
mkdir -p "$(dirname 'lib/models/history_entry.dart')"
cat > 'lib/models/history_entry.dart' <<'EOF_MARKER_8'
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
EOF_MARKER_8
mkdir -p "$(dirname 'lib/state/video_library_state.dart')"
cat > 'lib/state/video_library_state.dart' <<'EOF_MARKER_9'
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
EOF_MARKER_9
mkdir -p "$(dirname 'lib/state/media_player_state.dart')"
cat > 'lib/state/media_player_state.dart' <<'EOF_MARKER_10'
import 'dart:async';
import 'dart:convert';
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
    player.setVolume(volume * 100);
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

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    if (volume > 0) isMuted = false;
    await player.setVolume(isMuted ? 0 : volume * 100);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    isMuted = !isMuted;
    await player.setVolume(isMuted ? 0 : volume * 100);
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
EOF_MARKER_10
mkdir -p "$(dirname 'lib/state/player_settings.dart')"
cat > 'lib/state/player_settings.dart' <<'EOF_MARKER_11'
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
    return NativeBridge.saveSetting(kResumePlayback, '$resumePlayback');
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
    );
  }
}
EOF_MARKER_11
mkdir -p "$(dirname 'lib/state/theme_state.dart')"
cat > 'lib/state/theme_state.dart' <<'EOF_MARKER_12'
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
EOF_MARKER_12
mkdir -p "$(dirname 'lib/widgets/about_sheet.dart')"
cat > 'lib/widgets/about_sheet.dart' <<'EOF_MARKER_13'
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
EOF_MARKER_13
mkdir -p "$(dirname 'lib/widgets/display_settings_sheet.dart')"
cat > 'lib/widgets/display_settings_sheet.dart' <<'EOF_MARKER_14'
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
EOF_MARKER_14
mkdir -p "$(dirname 'lib/widgets/track_selection_sheet.dart')"
cat > 'lib/widgets/track_selection_sheet.dart' <<'EOF_MARKER_15'
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import '../state/theme_state.dart';

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
EOF_MARKER_15
mkdir -p "$(dirname 'lib/widgets/player_settings_sheet.dart')"
cat > 'lib/widgets/player_settings_sheet.dart' <<'EOF_MARKER_16'
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
EOF_MARKER_16
mkdir -p "$(dirname 'lib/widgets/equalizer_sheet.dart')"
cat > 'lib/widgets/equalizer_sheet.dart' <<'EOF_MARKER_17'
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
EOF_MARKER_17
mkdir -p "$(dirname 'lib/widgets/fade_in_image.dart')"
cat > 'lib/widgets/fade_in_image.dart' <<'EOF_MARKER_18'
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
EOF_MARKER_18
mkdir -p "$(dirname 'lib/widgets/gesture_illustrations.dart')"
cat > 'lib/widgets/gesture_illustrations.dart' <<'EOF_MARKER_19'
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
EOF_MARKER_20
mkdir -p "$(dirname 'lib/widgets/user_manual_sheet.dart')"
cat > 'lib/widgets/user_manual_sheet.dart' <<'EOF_MARKER_21'
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
    Icons.settings_outlined,
    'Player settings (⚙ top bar)',
    'Every gesture can be turned on/off individually, plus: seek step, '
        'auto-hide delay, speed-boost multiplier, and whether videos resume '
        'where you left off.',
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
EOF_MARKER_21
mkdir -p "$(dirname 'lib/widgets/video_tile.dart')"
cat > 'lib/widgets/video_tile.dart' <<'EOF_MARKER_22'
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
EOF_MARKER_22
mkdir -p "$(dirname 'lib/widgets/video_list_item.dart')"
cat > 'lib/widgets/video_list_item.dart' <<'EOF_MARKER_23'
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
EOF_MARKER_23
mkdir -p "$(dirname 'lib/widgets/player_controls_overlay.dart')"
cat > 'lib/widgets/player_controls_overlay.dart' <<'EOF_MARKER_24'
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
EOF_MARKER_24
mkdir -p "$(dirname 'lib/widgets/progress_bar.dart')"
cat > 'lib/widgets/progress_bar.dart' <<'EOF_MARKER_25'
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
EOF_MARKER_25
mkdir -p "$(dirname 'lib/widgets/playlist_panel.dart')"
cat > 'lib/widgets/playlist_panel.dart' <<'EOF_MARKER_26'
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
EOF_MARKER_26
mkdir -p "$(dirname 'lib/utils/formatters.dart')"
cat > 'lib/utils/formatters.dart' <<'EOF_MARKER_27'
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
EOF_MARKER_27
mkdir -p "$(dirname 'lib/screens/library_screen.dart')"
cat > 'lib/screens/library_screen.dart' <<'EOF_MARKER_28'
import 'package:flutter/material.dart';
import '../app_info.dart';
import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
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
    });
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
EOF_MARKER_28
mkdir -p "$(dirname 'lib/screens/player_screen.dart')"
cat > 'lib/screens/player_screen.dart' <<'EOF_MARKER_29'
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/player_settings.dart';
import '../state/theme_state.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/player_settings_sheet.dart';
import '../widgets/playlist_panel.dart';

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

  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _showQueue = false;
  bool _isPip = false;

  // Orientation lock (rotation toggle in the controls).
  bool _orientationLocked = false;
  List<DeviceOrientation> _lockedOrientations = DeviceOrientation.values;

  // Customizable behavior (persisted, edited in the Settings sheet).
  PlayerSettings _settings = const PlayerSettings();

  Timer? _hideTimer;

  // Transient center indicator ("+10s", "Volume 80%", "Resumed 12:34", ...).
  String? _indicatorText;
  IconData? _indicatorIcon;
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
  // two-finger panning while zoomed.
  double _zoom = 1.0;
  double _zoomBase = 1.0;
  Offset _pan = Offset.zero;
  Offset _panBase = Offset.zero;
  Offset _focalBase = Offset.zero;

  // Gesture plumbing (double-tap seek / volume & brightness swipes).
  double _gestureWidth = 0;
  double _gestureHeight = 0;
  double _lastDoubleTapDx = 0;

  /// Which axis the current vertical drag drives.
  _DragMode _dragMode = _DragMode.none;
  double _dragStartValue = 0;
  double _dragDy = 0;

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
    _startHideTimer();
  }

  @override
  void dispose() {
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
  // Transient indicator
  // ---------------------------------------------------------------------------

  void _showIndicator(String text, [IconData? icon]) {
    if (!mounted) return;
    _indicatorTimer?.cancel();
    setState(() {
      _indicatorText = text;
      _indicatorIcon = icon;
    });
    _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _indicatorText = null);
    });
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

  void _onScaleStart(ScaleStartDetails details) {
    if (!_settings.pinchZoom) return;
    _zoomBase = _zoom;
    _panBase = _pan;
    _focalBase = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_settings.pinchZoom) return;
    // One-finger moves only pan once already zoomed; otherwise leave them
    // for the tap / volume / brightness recognizers.
    if (details.pointerCount < 2 && _zoom <= 1.0) return;

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
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_settings.pinchZoom) return;
    // Snap back when barely zoomed.
    if (_zoom < 1.1) {
      setState(() {
        _zoom = 1.0;
        _pan = Offset.zero;
      });
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
  // Tap & swipe gestures
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

  void _onVerticalDragStart(DragStartDetails d) {
    final rightHalf = d.localPosition.dx > _gestureWidth / 2;
    if (rightHalf && _settings.volumeSwipe) {
      _dragMode = _DragMode.volume;
      _dragStartValue = widget.player.isMuted ? 0.0 : widget.player.volume;
      _dragDy = 0;
    } else if (!rightHalf && _settings.brightnessSwipe) {
      _dragMode = _DragMode.brightness;
      _dragStartValue = widget.player.brightness;
      _dragDy = 0;
    } else {
      _dragMode = _DragMode.none;
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_dragMode == _DragMode.none) return;
    _dragDy -= d.delta.dy; // dragging up = increase
    final v = (_dragStartValue + _dragDy / 300).clamp(0.0, 1.0);
    if (_dragMode == _DragMode.volume) {
      widget.player.setVolume(v);
      _showIndicator(
        'Volume ${(v * 100).round()}%',
        v == 0 ? Icons.volume_off : Icons.volume_up,
      );
    } else {
      widget.player.setBrightness(v);
      _showIndicator(
        'Brightness ${(v * 100).round()}%',
        Icons.brightness_6_outlined,
      );
    }
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    _dragMode = _DragMode.none;
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) _toggleFullscreen();
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
                  IconButton(
                    tooltip: 'Equalizer',
                    icon: const Icon(Icons.graphic_eq),
                    onPressed: () =>
                        EqualizerSheet.show(context, widget.player),
                  ),
                  IconButton(
                    tooltip: 'Picture in picture',
                    icon: const Icon(Icons.picture_in_picture_alt_outlined),
                    onPressed: () =>
                        NativeBridge.enterPip(playing: widget.player.isPlaying),
                  ),
                  IconButton(
                    tooltip: 'Player settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: _openSettings,
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
                      onTap: _toggleControls,
                      onDoubleTapDown: (d) =>
                          _lastDoubleTapDx = d.localPosition.dx,
                      onDoubleTap: _onDoubleTap,
                      onLongPressStart: _onLongPressStart,
                      onLongPressEnd: _onLongPressEnd,
                      onVerticalDragStart: _onVerticalDragStart,
                      onVerticalDragUpdate: _onVerticalDragUpdate,
                      onVerticalDragEnd: _onVerticalDragEnd,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onScaleEnd: _onScaleEnd,
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
}

enum _DragMode { none, volume, brightness }
EOF_MARKER_29
mkdir -p "$(dirname 'lib/screens/history_screen.dart')"
cat > 'lib/screens/history_screen.dart' <<'EOF_MARKER_30'
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
EOF_MARKER_30
mkdir -p "$(dirname 'lib/screens/stats_screen.dart')"
cat > 'lib/screens/stats_screen.dart' <<'EOF_MARKER_31'
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
EOF_MARKER_31
mkdir -p "$(dirname 'test/widget_test.dart')"
cat > 'test/widget_test.dart' <<'EOF_MARKER_32'
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/app_info.dart';
import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/state/media_player_state.dart';
import 'package:maxplayer/state/video_library_state.dart';
import 'package:maxplayer/utils/formatters.dart';
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
EOF_MARKER_32

echo ""
echo "==> Done! Now run:"
echo "    git add -A && git commit -m \"v10: arm64-only build (93MB -> ~33MB), whisper.cpp engine Phase 1\" && git push"
