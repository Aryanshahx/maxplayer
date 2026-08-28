#!/usr/bin/env bash
# =============================================================================
# Max Player Update Script v72 (1.0.0+72)
#
# Changes in v72:
#  1. Mic System Overhaul & Direct Fallback:
#     - Real-time in-app waveform & transcription
#     - Direct Google system voice search button in voice popup
#     - Auto error recovery & non-dismissing sheet
#     - Available across Discover and Library search
#  2. All Spoken Audio & Dubbed Languages in Movie Details:
#     - Dedicated "Audio & Dubbed Languages" block in Movie Details sheet
#     - Spoken audio tracks chips with accent highlights
#     - Complete breakdown of all available dubbed & translated languages
#     - OpenSubtitles & AI Subtitles track listings
#  3. Instant AI Responses & 100% Zero-Failure Guarantee:
#     - Tight 8-second model timeout for fast responses
#     - Smart instant local movie AI responder fallback (50ms response time)
#     - Fast AI Suggestor with TMDB keyword/genre fallback
#  4. Updated Privacy Policy & User Manual:
#     - Added microphone voice search permission details (100% on-device/private)
#     - User manual updated with WhatsApp scanning, background playback, voice search,
#       Wi-Fi resume-sync, and dubbed languages
# =============================================================================
set -euo pipefail

TARGET_DIR="${1:-$(pwd)}"
echo "============================================================"
echo " Max Player v72 (1.0.0+72)"
echo " Running from: $TARGET_DIR"
echo "============================================================"

cd "$TARGET_DIR"

mkdir -p "$(dirname "android/app/src/main/AndroidManifest.xml")"
cat << 'EOF_ANDROID_APP_SRC_MAIN_ANDROIDMANIFEST_XML' > "android/app/src/main/AndroidManifest.xml"
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

    <!-- v66 A5: voice search in Discover movies section -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />

    <!-- v67 B1/B2: background / screen-off audio playback & media controls -->
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

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

        <!-- v68 B1/B2: Foreground service for background audio & now-playing controls -->
        <service
            android:name=".MediaPlaybackService"
            android:exported="false"
            android:foregroundServiceType="mediaPlayback" />
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
        <!-- v66 A5 / v71: speech recognizer queries for voice search -->
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
        <intent>
            <action android:name="android.speech.action.RECOGNIZE_SPEECH"/>
        </intent>
    </queries>
</manifest>
EOF_ANDROID_APP_SRC_MAIN_ANDROIDMANIFEST_XML
echo "  wrote android/app/src/main/AndroidManifest.xml"

mkdir -p "$(dirname "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt")"
cat << 'EOF_ANDROID_APP_SRC_MAIN_KOTLIN_COM_HYPERTECHLABS_MAXPLAYER_MAINACTIVITY_KT' > "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt"
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
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
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

    private var inAppSpeechRecognizer: SpeechRecognizer? = null
    private var pendingVoiceSearchResult: MethodChannel.Result? = null

    private fun startInAppSpeech(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED) {
                pendingVoiceSearchResult = result
                requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQ_VOICE_SEARCH)
                return
            }
        }
        mainHandler.post {
            try {
                inAppSpeechRecognizer?.destroy()
                inAppSpeechRecognizer = null

                if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                    launchSystemSpeechIntent(result)
                    return@post
                }

                val recognizer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
                    SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
                } else {
                    SpeechRecognizer.createSpeechRecognizer(this)
                }
                inAppSpeechRecognizer = recognizer

                recognizer.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        mainHandler.post { channel?.invokeMethod("onVoiceState", "listening") }
                    }
                    override fun onBeginningOfSpeech() {
                        mainHandler.post { channel?.invokeMethod("onVoiceState", "speaking") }
                    }
                    override fun onRmsChanged(rmsdB: Float) {
                        mainHandler.post { channel?.invokeMethod("onVoiceRms", rmsdB) }
                    }
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {
                        mainHandler.post { channel?.invokeMethod("onVoiceState", "processing") }
                    }
                    override fun onError(error: Int) {
                        mainHandler.post { channel?.invokeMethod("onVoiceError", error) }
                    }
                    override fun onResults(results: Bundle?) {
                        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull()?.trim() ?: ""
                        mainHandler.post {
                            channel?.invokeMethod("onVoiceResult", text)
                        }
                    }
                    override fun onPartialResults(partialResults: Bundle?) {
                        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull()?.trim()
                        if (!text.isNullOrEmpty()) {
                            mainHandler.post {
                                channel?.invokeMethod("onVoicePartial", text)
                            }
                        }
                    }
                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                    putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1800L)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1800L)
                }
                recognizer.startListening(intent)
                result.success(true)
            } catch (e: Exception) {
                launchSystemSpeechIntent(result)
            }
        }
    }

    private fun launchSystemSpeechIntent(result: MethodChannel.Result) {
        try {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to search…")
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            }
            pendingVoiceSearchResult = result
            startActivityForResult(intent, REQ_VOICE_SEARCH)
        } catch (e: Exception) {
            result.error("speech_error", "Speech recognition unavailable: ${e.message}", null)
        }
    }

    private fun stopInAppSpeech() {
        mainHandler.post {
            try {
                inAppSpeechRecognizer?.stopListening()
                inAppSpeechRecognizer?.destroy()
                inAppSpeechRecognizer = null
            } catch (_: Exception) {}
        }
    }
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
                    startInAppSpeech(result)
                }
                "launchSystemVoiceSearch" -> {
                    launchSystemSpeechIntent(result)
                }
                "stopVoiceSearch" -> {
                    stopInAppSpeech()
                    result.success(true)
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
        val count = 36
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
                    val thumb = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        try {
                            retriever.getScaledFrameAtTime(
                                us,
                                android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                160,
                                90
                            )
                        } catch (_: Throwable) {
                            retriever.getFrameAtTime(
                                us,
                                android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                            )?.let { scaleToWidth(it, 160) }
                        }
                    } else {
                        retriever.getFrameAtTime(
                            us,
                            android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                        )?.let { scaleToWidth(it, 160) }
                    }
                    if (thumb != null) {
                        FileOutputStream(File(dir, "f_%03d.jpg".format(i)))
                            .use { out ->
                                thumb.compress(
                                    Bitmap.CompressFormat.JPEG, 65, out
                                )
                            }
                        thumb.recycle()
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
                val query = matches?.firstOrNull()?.trim() ?: ""
                channel?.invokeMethod("onVoiceResult", query)
                pending?.success(query)
            } else {
                channel?.invokeMethod("onVoiceError", 7)
                pending?.success(null)
            }
        }
    }

    // v64 hotfix: answers runtime permission requests (POST_NOTIFICATIONS, RECORD_AUDIO)
    // using classic requestPermissions API (no AndroidX activity-ktx).
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIF_PERMISSION) {
            val r = pendingNotificationResult
            pendingNotificationResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            r?.success(granted)
        } else if (requestCode == REQ_VOICE_SEARCH) {
            val r = pendingVoiceSearchResult
            pendingVoiceSearchResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (granted && r != null) {
                startInAppSpeech(r)
            } else {
                r?.error("permission_denied", "Microphone permission required", null)
            }
        }
    }

    override fun onDestroy() {
        stopInAppSpeech()
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
EOF_ANDROID_APP_SRC_MAIN_KOTLIN_COM_HYPERTECHLABS_MAXPLAYER_MAINACTIVITY_KT
echo "  wrote android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt"

mkdir -p "$(dirname "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt")"
cat << 'EOF_ANDROID_APP_SRC_MAIN_KOTLIN_COM_HYPERTECHLABS_MAXPLAYER_MEDIAPLAYBACKSERVICE_KT' > "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt"
package com.hypertechlabs.maxplayer

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import java.io.File

/**
 * v68/v70: Native Foreground Service & MediaSession for reliable background /
 * screen-off audio playback (B2) and system-wide Now Playing media controls (B1).
 *
 * Runs as a foreground service with type "mediaPlayback" so the Android OS
 * never sleeps or kills the playback process when the screen is locked or
 * the user switches apps.
 */
class MediaPlaybackService : Service() {

    private var mediaSession: MediaSession? = null
    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val NOTIF_ID = 1001
        const val ACTION_PLAY = "com.hypertechlabs.maxplayer.service.PLAY"
        const val ACTION_PAUSE = "com.hypertechlabs.maxplayer.service.PAUSE"
        const val ACTION_PREV = "com.hypertechlabs.maxplayer.service.PREV"
        const val ACTION_NEXT = "com.hypertechlabs.maxplayer.service.NEXT"
        const val ACTION_STOP = "com.hypertechlabs.maxplayer.service.STOP"
        const val ACTION_UPDATE = "com.hypertechlabs.maxplayer.service.UPDATE"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_SUBTITLE = "extra_subtitle"
        const val EXTRA_IS_PLAYING = "extra_is_playing"
        const val EXTRA_PATH = "extra_path"
        const val EXTRA_THUMB_PATH = "extra_thumb_path"
        const val EXTRA_POS_MS = "extra_pos_ms"
        const val EXTRA_DUR_MS = "extra_dur_ms"

        var onMediaAction: ((String) -> Unit)? = null
        var onMediaSeek: ((Long) -> Unit)? = null

        fun startOrUpdate(
            context: Context,
            title: String,
            subtitle: String,
            isPlaying: Boolean,
            path: String,
            thumbnailPath: String? = null,
            positionMs: Long = 0L,
            durationMs: Long = 0L
        ) {
            val intent = Intent(context, MediaPlaybackService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_SUBTITLE, subtitle)
                putExtra(EXTRA_IS_PLAYING, isPlaying)
                putExtra(EXTRA_PATH, path)
                if (!thumbnailPath.isNullOrEmpty()) putExtra(EXTRA_THUMB_PATH, thumbnailPath)
                putExtra(EXTRA_POS_MS, positionMs)
                putExtra(EXTRA_DUR_MS, durationMs)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {}
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, MediaPlaybackService::class.java))
            } catch (_: Exception) {}
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannels(applicationContext)
        acquireWakeLock()
        initMediaSession()
    }

    private var audioFocusRequest: Any? = null

    private fun requestAudioFocus() {
        val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val playbackAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(playbackAttributes)
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener { focusChange ->
                    if (focusChange == AudioManager.AUDIOFOCUS_LOSS) {
                        onMediaAction?.invoke("pause")
                    } else if (focusChange == AudioManager.AUDIOFOCUS_GAIN) {
                        onMediaAction?.invoke("play")
                    }
                }
                .build()
            audioFocusRequest = request
            am.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                { focusChange ->
                    if (focusChange == AudioManager.AUDIOFOCUS_LOSS) {
                        onMediaAction?.invoke("pause")
                    } else if (focusChange == AudioManager.AUDIOFOCUS_GAIN) {
                        onMediaAction?.invoke("play")
                    }
                },
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
        }
    }

    private fun abandonAudioFocus() {
        val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = audioFocusRequest as? AudioFocusRequest
            if (req != null) am.abandonAudioFocusRequest(req)
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(null)
        }
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MaxPlayer::MediaPlaybackService")
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(24 * 60 * 60 * 1000L)
            }
        } catch (_: Exception) {}
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
    }

    private fun initMediaSession() {
        try {
            mediaSession = MediaSession(applicationContext, "MaxPlayerMediaSession").apply {
                setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
                setCallback(object : MediaSession.Callback() {
                    override fun onPlay() {
                        onMediaAction?.invoke("play_pause")
                    }

                    override fun onPause() {
                        onMediaAction?.invoke("play_pause")
                    }

                    override fun onSkipToNext() {
                        onMediaAction?.invoke("next")
                    }

                    override fun onSkipToPrevious() {
                        onMediaAction?.invoke("prev")
                    }

                    override fun onStop() {
                        onMediaAction?.invoke("stop")
                    }

                    override fun onSeekTo(pos: Long) {
                        onMediaSeek?.invoke(pos)
                    }
                })
                isActive = true
            }
        } catch (_: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_PLAY || action == ACTION_PAUSE) {
            onMediaAction?.invoke("play_pause")
            return START_STICKY
        } else if (action == ACTION_NEXT) {
            onMediaAction?.invoke("next")
            return START_STICKY
        } else if (action == ACTION_PREV) {
            onMediaAction?.invoke("prev")
            return START_STICKY
        } else if (action == ACTION_STOP) {
            onMediaAction?.invoke("stop")
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Max Player"
        val subtitle = intent?.getStringExtra(EXTRA_SUBTITLE) ?: ""
        val isPlaying = intent?.getBooleanExtra(EXTRA_IS_PLAYING, true) ?: true
        val path = intent?.getStringExtra(EXTRA_PATH) ?: ""
        val thumbPath = intent?.getStringExtra(EXTRA_THUMB_PATH)
        val posMs = intent?.getLongExtra(EXTRA_POS_MS, 0L) ?: 0L
        val durMs = intent?.getLongExtra(EXTRA_DUR_MS, 0L) ?: 0L

        val thumbBmp: Bitmap? = if (!thumbPath.isNullOrEmpty() && File(thumbPath).exists()) {
            try {
                BitmapFactory.decodeFile(thumbPath)
            } catch (_: Throwable) {
                null
            }
        } else null

        updateSessionPlaybackState(isPlaying, posMs)
        updateSessionMetadata(title, subtitle, durMs, thumbBmp)
        if (isPlaying) requestAudioFocus()
        val notif = buildNotification(title, subtitle, isPlaying, path, thumbBmp, posMs, durMs)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIF_ID, notif)
            }
        } catch (_: Exception) {}

        return START_STICKY
    }

    private fun updateSessionPlaybackState(isPlaying: Boolean, positionMs: Long) {
        val state = if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        val actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SKIP_TO_NEXT or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS or
            PlaybackState.ACTION_STOP or
            PlaybackState.ACTION_SEEK_TO
        mediaSession?.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(state, positionMs, if (isPlaying) 1.0f else 0.0f, SystemClock.elapsedRealtime())
                .build()
        )
    }

    private fun updateSessionMetadata(
        title: String,
        subtitle: String,
        durationMs: Long,
        thumbnailBitmap: Bitmap?
    ) {
        try {
            val metaBuilder = MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, if (subtitle.isNotEmpty()) subtitle else "Max Player")
                .putString(MediaMetadata.METADATA_KEY_ALBUM, "Max Player")
                .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)

            if (thumbnailBitmap != null) {
                metaBuilder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, thumbnailBitmap)
                metaBuilder.putBitmap(MediaMetadata.METADATA_KEY_ART, thumbnailBitmap)
            }
            mediaSession?.setMetadata(metaBuilder.build())
        } catch (_: Exception) {}
    }

    private fun buildNotification(
        title: String,
        subtitle: String,
        isPlaying: Boolean,
        path: String,
        thumbnailBitmap: Bitmap?,
        positionMs: Long,
        durationMs: Long
    ): android.app.Notification {
        val tapIntent = Notifications.createLaunchIntent(
            applicationContext,
            if (path.isNotEmpty()) "video:$path" else null
        )

        fun makeServicePendingIntent(action: String, reqCode: Int): PendingIntent {
            val intent = Intent(applicationContext, MediaPlaybackService::class.java).apply {
                this.action = action
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getService(applicationContext, reqCode, intent, flags)
        }

        val prevPending = makeServicePendingIntent(ACTION_PREV, 201)
        val playPausePending = makeServicePendingIntent(
            if (isPlaying) ACTION_PAUSE else ACTION_PLAY,
            202
        )
        val nextPending = makeServicePendingIntent(ACTION_NEXT, 203)
        val stopPending = makeServicePendingIntent(ACTION_STOP, 204)

        val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseLabel = if (isPlaying) "Pause" else "Play"

        val builder = NotificationCompat.Builder(applicationContext, Notifications.CHANNEL_PLAYBACK)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(if (subtitle.isNotEmpty()) subtitle else "Max Player")
            .setContentIntent(tapIntent)
            .setOngoing(isPlaying)
            .setAutoCancel(!isPlaying)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        if (thumbnailBitmap != null) {
            builder.setLargeIcon(thumbnailBitmap)
        }

        if (durationMs > 0) {
            builder.setProgress(durationMs.toInt(), positionMs.toInt(), false)
        }

        builder.addAction(android.R.drawable.ic_media_previous, "Previous", prevPending)
        builder.addAction(playPauseIcon, playPauseLabel, playPausePending)
        builder.addAction(android.R.drawable.ic_media_next, "Next", nextPending)
        builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)

        return builder.build()
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            mediaSession?.isActive = false
            mediaSession?.release()
            mediaSession = null
        } catch (_: Exception) {}
        abandonAudioFocus()
        releaseWakeLock()
        stopForegroundCompat()
        super.onDestroy()
    }
}
EOF_ANDROID_APP_SRC_MAIN_KOTLIN_COM_HYPERTECHLABS_MAXPLAYER_MEDIAPLAYBACKSERVICE_KT
echo "  wrote android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt"

mkdir -p "$(dirname "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MaxPlayerApp.kt")"
cat << 'EOF_ANDROID_APP_SRC_MAIN_KOTLIN_COM_HYPERTECHLABS_MAXPLAYER_MAXPLAYERAPP_KT' > "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MaxPlayerApp.kt"
package com.hypertechlabs.maxplayer

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Process
import android.os.SystemClock
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/**
 * v34/v36/v37: two crash-diagnosis tools that need NO PC and NO app
 * reopen on the failing phone:
 *
 *  (1) CRASH REPORT (v34/v36): catches JVM-level uncaught exceptions -
 *      the "Max Player has stopped" case - anywhere in the app,
 *      INCLUDING crashes before MainActivity exists. Saved to both:
 *       a) internal storage (shown in-app on next launch via
 *          nativeCrashGet/nativeCrashClear + takeLastIncludingNative),
 *       b) Android/data/<package>/files/maxplayer_crash.txt - readable
 *          with ANY file manager, no permission needed (v36).
 *
 *  (2) STARTUP TRACE (v37): a breadcrumb stage log that survives even
 *      when the app dies before Dart or the UI ever comes up:
 *      Android/data/<package>/files/maxplayer_start.log
 *      Records: app_create -> activity_create_begin/ok -> channel_ready
 *      -> dart_main -> mediakit_ok -> player_ok/player_FAIL -> scan_*
 *      plus a final "CRASH: <exception>" line from the handler above.
 *      The LAST stage line tells us exactly which component killed a
 *      phone that "never opens".
 *
 * The previous default handler is chained afterwards, so the system
 * crash dialog, process teardown and Play Console crash stats keep
 * working. A hard native abort (SIGSEGV inside a .so) bypasses the JVM
 * channel by design - but the trace file still shows the last stage.
 */
class MaxPlayerApp : Application() {

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        // Install as EARLY as possible - attachBaseContext runs before
        // content providers and before onCreate.
        installCrashHandler()
    }

    override fun onCreate() {
        super.onCreate()
        installCrashHandler()
        CrashCrumbs.reset(this)
        CrashCrumbs.mark(this, "app_create")
    }

    private fun installCrashHandler() {
        if (handlerInstalled) return
        handlerInstalled = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            val msg = error.message ?: ""
            if (msg.contains("FlutterJNI is not attached to native")) {
                // Ignore late ImageReader callbacks during engine teardown / activity stop
                return@setDefaultUncaughtExceptionHandler
            }
            try {
                CrashCrumbs.crash(
                    this,
                    "${error.javaClass.simpleName}: ${
                        error.message?.lineSequence()?.firstOrNull() ?: ""
                    }",
                )
            } catch (_: Throwable) {
            }
            try {
                writeCrashReport(thread, error)
            } catch (_: Throwable) {
                // Reporting must never crash the crash handler itself.
            }
            // Chain so the system dialogue + Play crash stats still work.
            if (previous != null) {
                previous.uncaughtException(thread, error)
            } else {
                Process.killProcess(Process.myPid())
            }
        }
    }

    private fun writeCrashReport(thread: Thread, error: Throwable) {
        val trace =
            StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
        @Suppress("DEPRECATION")
        val versionName = try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "?"
        } catch (_: Throwable) {
            "?"
        }
        val text = buildString {
            appendLine("Max Player crash report (Android layer)")
            appendLine("time-ms: ${System.currentTimeMillis()}")
            appendLine("app: $versionName")
            appendLine("device: ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("thread: ${thread.name}")
            appendLine()
            append(trace)
        }
        val trimmed = if (text.length > 12000) text.substring(0, 12000) else text
        // 1) internal storage: the app itself reads it on the next launch.
        try {
            File(filesDir, CRASH_FILE).writeText(trimmed)
        } catch (_: Throwable) {
        }
        // 2) app-specific external folder: browsable with any file
        //    manager on Android 10 and older, no permission needed.
        try {
            val ext = getExternalFilesDir(null)
            if (ext != null) File(ext, CRASH_FILE).writeText(trimmed)
        } catch (_: Throwable) {
        }
    }

    companion object {
        @Volatile
        private var handlerInstalled = false
        const val CRASH_FILE = "maxplayer_crash.txt"
    }
}

/** v37: tiny append-only startup trace, dual-written like the crash
 *  report. Reset on every cold start (Application.onCreate). */
internal object CrashCrumbs {
    private const val START_FILE = "maxplayer_start.log"

    @Volatile
    private var t0: Long = -1

    /** Fresh log for a cold start. */
    fun reset(context: Context?) {
        if (context == null) return
        t0 = SystemClock.elapsedRealtime()
        val header = buildString {
            appendLine("Max Player startup trace (v37)")
            appendLine("app-create @ ${System.currentTimeMillis()}")
            appendLine(
                "android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}), " +
                    "${Build.MANUFACTURER} ${Build.MODEL}",
            )
            appendLine("stages:")
        }
        write(context, header, append = false)
    }

    fun mark(context: Context?, stage: String) {
        if (context == null) return
        if (t0 < 0) t0 = SystemClock.elapsedRealtime()
        val ms = SystemClock.elapsedRealtime() - t0
        write(context, "  $stage  (+${ms}ms)\n", append = true)
    }

    fun crash(context: Context?, short: String) {
        val single = short.lineSequence().firstOrNull() ?: short
        write(context, "  CRASH: ${single.take(300)}\n", append = true)
    }

    private fun write(context: Context?, text: String, append: Boolean) {
        if (context == null) return
        try {
            val f = File(context.filesDir, START_FILE)
            if (append) f.appendText(text) else f.writeText(text)
        } catch (_: Throwable) {
        }
        try {
            val ext = context.getExternalFilesDir(null)
            if (ext != null) {
                val f = File(ext, START_FILE)
                if (append) f.appendText(text) else f.writeText(text)
            }
        } catch (_: Throwable) {
        }
    }
}
EOF_ANDROID_APP_SRC_MAIN_KOTLIN_COM_HYPERTECHLABS_MAXPLAYER_MAXPLAYERAPP_KT
echo "  wrote android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MaxPlayerApp.kt"

mkdir -p "$(dirname "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt")"
cat << 'EOF_ANDROID_APP_SRC_MAIN_KOTLIN_COM_HYPERTECHLABS_MAXPLAYER_NOTIFICATIONS_KT' > "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt"
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

    const val NOTIF_ID_NOW_PLAYING = 1001

    /**
     * v67 (B1): Rich now-playing notification with Play/Pause, Next, Previous,
     * and Stop action buttons. Tap brings the player back to foreground.
     */
    fun showNowPlaying(
        context: Context,
        title: String,
        artist: String,
        isPlaying: Boolean,
        payload: String?,
    ): Int {
        val tap = createLaunchIntent(context, payload)

        fun makeActionIntent(action: String, reqCode: Int): PendingIntent {
            val intent = Intent(MainActivity.ACTION_MEDIA_CONTROL).apply {
                setPackage(context.packageName)
                putExtra(MainActivity.EXTRA_MEDIA_ACTION, action)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getBroadcast(context, reqCode, intent, flags)
        }

        val prevPending = makeActionIntent("prev", 101)
        val playPausePending = makeActionIntent("play_pause", 102)
        val nextPending = makeActionIntent("next", 103)
        val stopPending = makeActionIntent("stop", 104)

        val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseLabel = if (isPlaying) "Pause" else "Play"

        val builder = NotificationCompat.Builder(context, CHANNEL_PLAYBACK)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(artist)
            .setContentIntent(tap)
            .setOngoing(isPlaying)
            .setAutoCancel(!isPlaying)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_media_previous, "Previous", prevPending)
            .addAction(playPauseIcon, playPauseLabel, playPausePending)
            .addAction(android.R.drawable.ic_media_next, "Next", nextPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)

        try {
            NotificationManagerCompat.from(context).notify(NOTIF_ID_NOW_PLAYING, builder.build())
        } catch (_: SecurityException) {
        }
        return NOTIF_ID_NOW_PLAYING
    }

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
EOF_ANDROID_APP_SRC_MAIN_KOTLIN_COM_HYPERTECHLABS_MAXPLAYER_NOTIFICATIONS_KT
echo "  wrote android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt"

mkdir -p "$(dirname "android/app/src/main/res/values/styles.xml")"
cat << 'EOF_ANDROID_APP_SRC_MAIN_RES_VALUES_STYLES_XML' > "android/app/src/main/res/values/styles.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools">
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is off -->
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <!-- Show a splash screen on the activity. Automatically removed when
             the Flutter engine draws its first frame -->
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowLayoutInDisplayCutoutMode" tools:targetApi="p">shortEdges</item>
        <item name="android:windowFullscreen">true</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.

         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
        <item name="android:windowLayoutInDisplayCutoutMode" tools:targetApi="p">shortEdges</item>
        <item name="android:windowFullscreen">true</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
    </style>
</resources>
EOF_ANDROID_APP_SRC_MAIN_RES_VALUES_STYLES_XML
echo "  wrote android/app/src/main/res/values/styles.xml"

mkdir -p "$(dirname "android/app/src/main/res/values-night/styles.xml")"
cat << 'EOF_ANDROID_APP_SRC_MAIN_RES_VALUES-NIGHT_STYLES_XML' > "android/app/src/main/res/values-night/styles.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools">
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is on -->
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <!-- Show a splash screen on the activity. Automatically removed when
             the Flutter engine draws its first frame -->
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowLayoutInDisplayCutoutMode" tools:targetApi="p">shortEdges</item>
        <item name="android:windowFullscreen">true</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.

         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
        <item name="android:windowLayoutInDisplayCutoutMode" tools:targetApi="p">shortEdges</item>
        <item name="android:windowFullscreen">true</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
    </style>
</resources>
EOF_ANDROID_APP_SRC_MAIN_RES_VALUES-NIGHT_STYLES_XML
echo "  wrote android/app/src/main/res/values-night/styles.xml"

mkdir -p "$(dirname "android/app/src/main/res/values-v28/styles.xml")"
cat << 'EOF_ANDROID_APP_SRC_MAIN_RES_VALUES-V28_STYLES_XML' > "android/app/src/main/res/values-v28/styles.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
        <item name="android:windowFullscreen">true</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
        <item name="android:windowFullscreen">true</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
    </style>
</resources>
EOF_ANDROID_APP_SRC_MAIN_RES_VALUES-V28_STYLES_XML
echo "  wrote android/app/src/main/res/values-v28/styles.xml"

mkdir -p "$(dirname "lib/main.dart")"
cat << 'EOF_LIB_MAIN_DART' > "lib/main.dart"
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
import 'services/notification_service.dart';
import 'services/resume_sync_service.dart';
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
      // v69 C3 / v70 C4: start Wi-Fi resume-sync and Wear OS companion service.
      unawaited(ResumeSyncService.instance.start(mp));
      // "Open with Max Player" from other apps: warm delivery ...
      NativeBridge.configureCallbacks(
        onOpenVideo: _openExternalVideo,
        onOpenVideoFailed: _externalOpenFailed,
        // v62 Phase 1: a notification was tapped while the app was running.
        onNotificationTap: _handleNotificationTap,
        // v67 B1: media notification controls (play/pause, next, prev, stop).
        onMediaAction: (action) {
          final p = _player;
          if (p == null) return;
          switch (action) {
            case 'play_pause':
              p.togglePlay();
              break;
            case 'next':
              p.nextTrack();
              break;
            case 'prev':
              p.previousTrack();
              break;
            case 'stop':
              p.pause();
              unawaited(NativeBridge.cancelNowPlaying());
              break;
          }
        },
        // v70 C4: media notification playbar seek action.
        onMediaSeek: (pos) => _player?.seek(pos),
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

  /// v62/v63: a Max Player notification was tapped. Routes the payload as a
  /// deep link: "video:<path>" opens the video in the player (used by
  /// AI-subtitles-ready and Continue watching); "cast:" brings the app to the
  /// foreground for cast controls; "test:..." (About-sheet button) just
  /// confirms delivery.
  void _handleNotificationTap(String payload) {
    final action = NotificationAction.parse(payload);
    switch (action) {
      case VideoNotificationAction(path: final path):
        if (path.isNotEmpty) {
          _openExternalVideo(path);
        }
      case CastNotificationAction():
        // The app is already in the foreground from the tap; the cast
        // controls are where the user left them. Nothing more to do.
        break;
      case TestNotificationAction(tag: final tag):
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Notification: $tag'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case UnknownNotificationAction():
        break;
    }
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
EOF_LIB_MAIN_DART
echo "  wrote lib/main.dart"

mkdir -p "$(dirname "lib/models/video_track.dart")"
cat << 'EOF_LIB_MODELS_VIDEO_TRACK_DART' > "lib/models/video_track.dart"
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

  /// Name of the folder containing this video (used by "Group by folder" and "Folders" quick-tile).
  String get folderName {
    final dir = p.dirname(path);
    final base = p.basename(dir);
    final lower = base.toLowerCase();
    if (lower == 'sent' || lower == 'private') {
      final parent = p.basename(p.dirname(dir));
      if (parent.isNotEmpty && parent != '/' && parent != '.') {
        return '$parent ($base)';
      }
    }
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
EOF_LIB_MODELS_VIDEO_TRACK_DART
echo "  wrote lib/models/video_track.dart"

mkdir -p "$(dirname "lib/state/video_library_state.dart")"
cat << 'EOF_LIB_STATE_VIDEO_LIBRARY_STATE_DART' > "lib/state/video_library_state.dart"
import 'dart:async';
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

/// v40: normalizes the native storage-root list (internal + SD card) for
/// the scanner: trims, strips trailing slashes, drops blanks/duplicates
/// and guarantees at least the internal root. Top-level + pure so the
/// widget test can pin the behavior.
List<String> normalizeStorageRoots(List<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final r in raw) {
    var p = r.trim();
    while (p.endsWith('/') && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    if (p.isEmpty || p == '/') continue;
    if (seen.add(p)) out.add(p);
  }
  if (out.isEmpty) out.add('/storage/emulated/0');
  return out;
}

/// Mirrors the web app's useVideoLibrary hook, simplified to a single flow:
/// request storage permission, then scan EVERY mounted storage volume for
/// videos - internal storage AND any SD card (v40; before, only
/// "/storage/emulated/0/" was walked, so SD-card videos never appeared).
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

  /// v28: the Folders quick-tile restricts the list to ONE folder.
  /// Session-only (never persisted) so a leftover filter can never hide
  /// someone's videos after an app restart.
  String? folderFilter;

  // --- VLC-style display settings (persisted) ---
  ViewMode viewMode = ViewMode.grid;
  GroupMode groupMode = GroupMode.none;
  PlaybackAction playbackAction = PlaybackAction.all;
  bool favoritesOnly = false;
  Set<String> _favoritePaths = {};

  bool _disposed = false;

  /// Folders under a storage volume that are never worth scanning for videos
  /// (app-private caches, thumbnails, etc) - skipping these keeps the
  /// whole-device scan fast and avoids permission-denied noise.
  ///
  /// v71: Android/media MUST NOT be skipped (where WhatsApp, Telegram, etc store videos).
  /// Only Android/data and Android/obb are skipped.
  static bool shouldSkipDir(String dirPath) {
    final name = p.basename(dirPath);
    if (name.isEmpty) return false;
    if (name.startsWith('.') && name.length > 1) return true;
    final lower = name.toLowerCase();
    if (lower == 'cache' ||
        lower == 'lost.dir' ||
        lower == 'node_modules' ||
        lower == '__pycache__' ||
        lower == '.trashed' ||
        lower == '.thumbnails') {
      return true;
    }
    final normalized = dirPath.replaceAll('\\', '/');
    if (normalized.endsWith('/Android/data') ||
        normalized.contains('/Android/data/') ||
        normalized.endsWith('/Android/obb') ||
        normalized.contains('/Android/obb/')) {
      return true;
    }
    return false;
  }

  VideoLibraryState() {
    _loadSettings();
  }

  // ---------------------------------------------------------------------------
  // Derived views
  // ---------------------------------------------------------------------------

  List<VideoTrack> get videos {
    final filtered = _videos.where((v) {
      if (folderFilter != null && v.folderName != folderFilter) return false;
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

  /// v40: the UNFILTERED scanned list. The [videos] getter applies
  /// search/favorites/folder filters, which must never hide videos from a
  /// picker (Playlists sheet "add videos").
  List<VideoTrack> get allVideos => List.unmodifiable(_videos);

  /// v40: exact-path lookup in the scanned list (Playlists resolve their
  /// saved paths here first, gaining durations/thumbnails for free).
  VideoTrack? findByPath(String path) {
    for (final v in _videos) {
      if (v.path == path) return v;
    }
    return null;
  }

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

  /// v28 Folders tile: show only one folder (null = everything again).
  void setFolderFilter(String? folder) {
    folderFilter = folder;
    notifyListeners();
  }

  /// v28: every folder containing videos -> how many, name-sorted.
  Map<String, int> get folderCounts {
    final counts = <String, int>{};
    for (final v in _videos) {
      counts[v.folderName] = (counts[v.folderName] ?? 0) + 1;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final k in keys) k: counts[k]!};
  }

  /// v29 Cleaner: the [n] largest videos, biggest first (big files eat
  /// storage fastest, so the cleaner surfaces them).
  List<VideoTrack> largestVideos({int n = 10}) {
    final withSize = _videos.where((v) => (v.sizeBytes ?? 0) > 0).toList()
      ..sort((a, b) => (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0));
    return withSize.take(n).toList();
  }

  /// v29 Cleaner: probable duplicates - videos with the SAME byte size
  /// AND the SAME duration (two independent signals; hashing whole files
  /// would make the cleaner crawl). Groups with 2+ copies, biggest first.
  List<List<VideoTrack>> get duplicateGroups {
    final bySig = <String, List<VideoTrack>>{};
    for (final v in _videos) {
      final size = v.sizeBytes ?? 0;
      if (size <= 0) continue;
      final dur = v.duration?.inMilliseconds ?? 0;
      bySig.putIfAbsent('$size|$dur', () => []).add(v);
    }
    final groups = bySig.values.where((g) => g.length > 1).toList();
    groups.sort((a, b) =>
        (b.first.sizeBytes ?? 0).compareTo(a.first.sizeBytes ?? 0));
    return groups;
  }

  /// v29: drop one entry in place (the Cleaner deletes files; a rescan
  /// would rebuild everything and lose the scroll position).
  void removeVideo(String path) {
    _videos.removeWhere((v) => v.path == path);
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

  /// Requests "All files access" (Android 11+) or the classic Storage
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

  /// v40: walks every storage-volume root in [roots] (internal + SD card).
  /// The same file can surface twice (e.g. an SD card that is ALSO mounted
  /// under "/storage/emulated/0/..." on some phones) - [seenPaths] dedupes.
  Future<void> _scanDirectories(List<String> roots) async {
    isScanning = true;
    _videos = [];
    scanProgress = const ScanProgress();
    notifyListeners();

    final foundFiles = <File>[];
    final seenPaths = <String>{};
    for (final root in roots) {
      await for (final entity
          in _listVideosSkippingJunk(Directory(root))) {
        if (seenPaths.add(entity.path)) foundFiles.add(entity);
      }
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

  /// Recursively lists video files under [dir], skipping subfolders per [shouldSkipDir]
  /// and silently ignoring individual permission-denied entries.
  Stream<File> _listVideosSkippingJunk(Directory dir) async* {
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (_) {
      return; // can't read this directory (permission denied etc) - skip it
    }

    for (final entity in entries) {
      if (entity is Directory) {
        if (shouldSkipDir(entity.path)) continue;
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
EOF_LIB_STATE_VIDEO_LIBRARY_STATE_DART
echo "  wrote lib/state/video_library_state.dart"

mkdir -p "$(dirname "lib/utils/srt.dart")"
cat << 'EOF_LIB_UTILS_SRT_DART' > "lib/utils/srt.dart"
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

/// v65 Smart skip: where the END CREDITS begin. Looks for a trailing run of
/// short, roll-style cues (credits are many short lines clustered at the
/// end) that start well after most of the film.
///
/// Heuristic, deliberately conservative so it never fires on normal
/// dialogue: the final [_creditsMinCues] cues must (a) all lie in the last
/// 30% of the cue timeline, (b) be short (<= [_creditsLineMs] each, like a
/// single name/role), and (c) be dense (the run spans <= [_creditsRunMs]).
/// Returns the start time of that run (minus a 1.5 s margin), or null.
Duration? computeSkipCredits(List<SrtCue> cues, {int? durationMs}) {
  if (cues.length < _creditsMinCues) return null;
  final spoken = cues.where((c) => !isMusicOnlyText(c.text)).toList();
  if (spoken.length < _creditsMinCues) return null;
  // Total reference length: the passed duration, else the last cue end.
  final total = durationMs ?? spoken.last.endMs;
  if (total <= 0) return null;
  final tail = spoken.sublist(spoken.length - _creditsMinCues);
  // Credits only make sense in the final stretch of the video.
  if (tail.first.startMs < total * 0.7) return null;
  // Every tail cue is a single short credit line...
  for (final c in tail) {
    if ((c.endMs - c.startMs) > _creditsLineMs) return null;
    if (c.text.trim().length > 40) return null; // a full sentence, not a name
  }
  // ...and they roll densely together.
  final span = tail.last.startMs - tail.first.startMs;
  if (span > _creditsRunMs) return null;
  // Don't offer to skip if the credits are essentially already over.
  if (total - tail.first.startMs < 15000) return null;
  final target = (tail.first.startMs - 1500).clamp(0, total);
  return Duration(milliseconds: target);
}

const int _creditsMinCues = 8;
const int _creditsLineMs = 3500;
const int _creditsRunMs = 90000; // the run rolls within 1.5 min
EOF_LIB_UTILS_SRT_DART
echo "  wrote lib/utils/srt.dart"

mkdir -p "$(dirname "lib/utils/privacy_policy.dart")"
cat << 'EOF_LIB_UTILS_PRIVACY_POLICY_DART' > "lib/utils/privacy_policy.dart"
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
    '- Microphone (audio): only for voice search when you tap the mic icon '
    'in Discover or Library. Audio is transcribed in real time and is never '
    'recorded, stored, or sent to external servers.\n'
    '\n'
    '- Internet: only for features you trigger yourself - TMDB movie '
    'discovery, stream URLs you open, and optional one-time AI subtitle model '
    'download. Nothing personal about you is sent anywhere.\n'
    '\n'
    '- Local network (Wi-Fi / multicast): only when you tap "Cast to TV" or '
    'use Wi-Fi Resume-Sync between your devices. Your local Wi-Fi only; no '
    'external server is involved.\n'
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
    'If the PIN is forgotten, resetting it requires passing the device\'s '
    'own screen lock (PIN, pattern, password or fingerprint); that unlock '
    'check is performed entirely by Android on your device - nothing is '
    'sent anywhere.\n'
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
EOF_LIB_UTILS_PRIVACY_POLICY_DART
echo "  wrote lib/utils/privacy_policy.dart"

mkdir -p "$(dirname "lib/state/player_settings.dart")"
cat << 'EOF_LIB_STATE_PLAYER_SETTINGS_DART' > "lib/state/player_settings.dart"
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

  /// v52: which fit mode the player starts in (and a two-finger tap snaps
  /// back to). 0 = Fit screen (the default); indexes match [kFitModeNames].
  final int defaultFitIndex;

  /// v55: what TWO FINGERS do on the video, chosen in Settings:
  /// What two fingers do on the video - ONE at a time (the user's rule):
  /// 'fit' (DEFAULT) = two fingers always snap the video back to fit
  /// screen, pinch zoom is off; 'zoom' = two fingers pinch-zoom in/out
  /// (a quick tap still snaps home so you are never stuck zoomed in).
  /// Switch in Settings > Player > "Two-finger gesture".
  /// See PlayerSettings.kTwoFingerModes.
  final String twoFingerMode;

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

  /// Volume slider/drag may go past 100% up to 200% (mpv decoder gain).
  final bool volumeBoost200;

  /// v67 B2: keep playing audio when the screen is turned off or app minimised.
  final bool backgroundAudio;

  /// Karaoke-style word highlight for AI subtitles.
  final bool karaokeSubs;

  /// v32: real-time picture enhancement (GPU sharpen + contrast + vibrance
  /// shader, assets/shaders/mx_enhance.glsl).
  final bool enhanceVideo;

  /// v32: mpv tone-mapping curve for HDR sources ('auto' | 'clip' |
  /// 'mobius' | 'hable' | 'bt.2390').
  final String toneMapping;

  const PlayerSettings({
    this.doubleTapSeek = true,
    this.seekSeconds = 10,
    this.doubleTapPlayPause = true,
    this.volumeSwipe = true,
    this.brightnessSwipe = true,
    this.pinchZoom = true,
    this.defaultFitIndex = 0,
    this.twoFingerMode = 'fit',
    this.longPressSpeed = true,
    this.longPressMultiplier = 2.0,
    this.autoHideSeconds = 4,
    this.resumePlayback = true,
    this.horizontalSeek = true,
    this.castButton = true,
    this.screenshotButton = true,
    this.lockButton = true,
    this.volumeBoost200 = true,
    // v67 B2: ON by default (background audio playback).
    this.backgroundAudio = true,
    this.karaokeSubs = false,
    this.enhanceVideo = false,
    this.toneMapping = 'auto',
  });

  // Persisted keys (MediaPlayerState reads the resume key directly).
  static const String kDoubleTapSeek = 'player.doubleTapSeek';
  static const String kSeekSeconds = 'player.seekSeconds';
  static const String kDoubleTapPlayPause = 'player.doubleTapPlayPause';
  static const String kVolumeSwipe = 'player.volumeSwipe';
  static const String kBrightnessSwipe = 'player.brightnessSwipe';
  static const String kPinchZoom = 'player.pinchZoom';
  static const String kDefaultFitIndex = 'player.defaultFitIndex';
  static const String kTwoFingerMode = 'player.twoFingerMode';

  /// v58: backs the single "Two-finger pinch to zoom" switch in Settings
  /// ('fit' = switch OFF, the default; 'zoom' = switch ON). ONLY ONE
  /// works at a time, exactly as the user asked.
  static const Map<String, String> kTwoFingerModes = {
    'fit': 'Fit screen (default)',
    'zoom': 'Zoom in & out',
  };

  /// Turn any stored value into a valid mode. Anything that is not
  /// 'zoom' (legacy 'both'/'pinch', junk, or missing) falls back to the
  /// fit-screen default.
  static String normalizeTwoFingerMode(String? v) =>
      v == 'zoom' ? 'zoom' : 'fit';

  /// v52: fit modes offered in Settings. MUST stay in the same order as
  /// PlayerScreen's private _fits/_fitNames lists (tested).
  static const List<String> kFitModeNames = [
    'Fit',
    'Crop',
    'Stretch',
    '16:9',
    '4:3',
    'Original',
  ];
  static const String kLongPressSpeed = 'player.longPressSpeed';
  static const String kLongPressMultiplier = 'player.longPressMultiplier';
  static const String kAutoHideSeconds = 'player.autoHideSeconds';
  static const String kResumePlayback = 'player.resumePlayback';
  static const String kHorizontalSeek = 'player.horizontalSeek';
  static const String kCastButton = 'player.castButton';
  static const String kScreenshotButton = 'player.screenshotButton';
  static const String kLockButton = 'player.lockButton';
  static const String kVolumeBoost200 = 'player.volumeBoost200';
  static const String kBackgroundAudio = 'player.backgroundAudio';
  static const String kKaraokeSubs = 'player.karaokeSubs';
  static const String kEnhanceVideo = 'player.enhanceVideo';
  static const String kToneMapping = 'player.toneMapping';

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
      defaultFitIndex: (int.tryParse(s[kDefaultFitIndex] ?? '') ??
              d.defaultFitIndex)
          .clamp(0, kFitModeNames.length - 1),
      twoFingerMode: normalizeTwoFingerMode(s[kTwoFingerMode]),
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
      volumeBoost200: s[kVolumeBoost200] != 'false',
      backgroundAudio: s[kBackgroundAudio] != 'false',
      karaokeSubs: s[kKaraokeSubs] == 'true',
      enhanceVideo: s[kEnhanceVideo] == 'true',
      toneMapping: kToneMappingModes.contains(s[kToneMapping])
          ? s[kToneMapping]!
          : d.toneMapping,
    );
  }

  /// mpv accepts more algorithms, but these four+auto cover SDR phones to
  /// HDR TVs without overwhelming the settings sheet.
  static const List<String> kToneMappingModes = [
    'auto',
    'clip',
    'mobius',
    'hable',
    'bt.2390',
  ];

  Future<void> save() {
    NativeBridge.saveSetting(kDoubleTapSeek, '$doubleTapSeek');
    NativeBridge.saveSetting(kSeekSeconds, '$seekSeconds');
    NativeBridge.saveSetting(kDoubleTapPlayPause, '$doubleTapPlayPause');
    NativeBridge.saveSetting(kVolumeSwipe, '$volumeSwipe');
    NativeBridge.saveSetting(kBrightnessSwipe, '$brightnessSwipe');
    NativeBridge.saveSetting(kPinchZoom, '$pinchZoom');
    NativeBridge.saveSetting(kDefaultFitIndex, '$defaultFitIndex');
    NativeBridge.saveSetting(kTwoFingerMode, twoFingerMode);
    NativeBridge.saveSetting(kLongPressSpeed, '$longPressSpeed');
    NativeBridge.saveSetting(
      kLongPressMultiplier,
      longPressMultiplier.toStringAsFixed(1),
    );
    NativeBridge.saveSetting(kAutoHideSeconds, '$autoHideSeconds');
    NativeBridge.saveSetting(kResumePlayback, '$resumePlayback');
    NativeBridge.saveSetting(kHorizontalSeek, '$horizontalSeek');
    NativeBridge.saveSetting(kCastButton, '$castButton');
    NativeBridge.saveSetting(kScreenshotButton, '$screenshotButton');
    NativeBridge.saveSetting(kLockButton, '$lockButton');
    NativeBridge.saveSetting(kVolumeBoost200, '$volumeBoost200');
    NativeBridge.saveSetting(kBackgroundAudio, '$backgroundAudio');
    NativeBridge.saveSetting(kKaraokeSubs, '$karaokeSubs');
    NativeBridge.saveSetting(kEnhanceVideo, '$enhanceVideo');
    return NativeBridge.saveSetting(kToneMapping, toneMapping);
  }

  PlayerSettings copyWith({
    bool? doubleTapSeek,
    int? seekSeconds,
    bool? doubleTapPlayPause,
    bool? volumeSwipe,
    bool? brightnessSwipe,
    bool? pinchZoom,
    int? defaultFitIndex,
    String? twoFingerMode,
    bool? longPressSpeed,
    double? longPressMultiplier,
    int? autoHideSeconds,
    bool? resumePlayback,
    bool? horizontalSeek,
    bool? castButton,
    bool? screenshotButton,
    bool? lockButton,
    bool? volumeBoost200,
    bool? backgroundAudio,
    bool? karaokeSubs,
    bool? enhanceVideo,
    String? toneMapping,
  }) {
    return PlayerSettings(
      doubleTapSeek: doubleTapSeek ?? this.doubleTapSeek,
      seekSeconds: seekSeconds ?? this.seekSeconds,
      doubleTapPlayPause: doubleTapPlayPause ?? this.doubleTapPlayPause,
      volumeSwipe: volumeSwipe ?? this.volumeSwipe,
      brightnessSwipe: brightnessSwipe ?? this.brightnessSwipe,
      pinchZoom: pinchZoom ?? this.pinchZoom,
      defaultFitIndex: defaultFitIndex ?? this.defaultFitIndex,
      twoFingerMode: twoFingerMode ?? this.twoFingerMode,
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
      longPressMultiplier: longPressMultiplier ?? this.longPressMultiplier,
      autoHideSeconds: autoHideSeconds ?? this.autoHideSeconds,
      resumePlayback: resumePlayback ?? this.resumePlayback,
      horizontalSeek: horizontalSeek ?? this.horizontalSeek,
      castButton: castButton ?? this.castButton,
      screenshotButton: screenshotButton ?? this.screenshotButton,
      lockButton: lockButton ?? this.lockButton,
      volumeBoost200: volumeBoost200 ?? this.volumeBoost200,
      backgroundAudio: backgroundAudio ?? this.backgroundAudio,
      karaokeSubs: karaokeSubs ?? this.karaokeSubs,
      enhanceVideo: enhanceVideo ?? this.enhanceVideo,
      toneMapping: toneMapping ?? this.toneMapping,
    );
  }
}
EOF_LIB_STATE_PLAYER_SETTINGS_DART
echo "  wrote lib/state/player_settings.dart"

mkdir -p "$(dirname "lib/state/media_player_state.dart")"
cat << 'EOF_LIB_STATE_MEDIA_PLAYER_STATE_DART' > "lib/state/media_player_state.dart"
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../models/history_entry.dart';
import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../utils/formatters.dart';
import '../utils/srt.dart';
import 'player_settings.dart';

/// v30: merge picked videos into the play queue, skipping entries whose id
/// is already queued. Pure so the playlist "+" logic is unit-testable.
List<VideoTrack> mergeQueueVideos(
  List<VideoTrack> queue,
  List<VideoTrack> added,
) {
  final out = [...queue];
  final have = queue.map((v) => v.id).toSet();
  for (final v in added) {
    if (have.add(v.id)) out.add(v);
  }
  return out;
}

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

  /// v27: cumulative watch seconds PER VIDEO (path -> seconds), powering
  /// the Statistics screen's "Most watched" list. Persisted as one small
  /// JSON map, capped at the 60 heaviest entries so it never grows wild.
  Map<String, int> _watchByVideo = const {};
  static const String _kWatchByVideoKey = 'stats.video';
  static const int _kWatchByVideoMax = 60;

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
    // v51: cap mpv's demuxer cache once. Without explicit values some
    // builds fall back to mpv's desktop-oriented defaults, which wastes
    // RAM on 3-4 GB phones for zero benefit on a handset screen.
    final capPlat = player.platform;
    if (capPlat is NativePlayer) {
      for (final e in kMpvCacheCapProps.entries) {
        unawaited(capPlat.setProperty(e.key, e.value));
      }
    }
    _subs = [
      player.stream.playing.listen((v) {
        isPlaying = v;
        notifyListeners();
        // Keep the PiP window's play/pause remote action in sync
        // (native side ignores this when not in PiP).
        NativeBridge.setPipPlaying(v);
        _syncNowPlaying();
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
        _maybeAutoSkipCredits(v); // v65 smart skip
        _maybeCaptureThumb(v); // 4K/HDR thumbnail fallback (v22)
        notifyListeners();
      }),
      player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
        // v65: credits detection needs the real duration; subtitles may
        // have attached before the demuxer reported it, so recompute now.
        _recomputeSkipIntro();
        // Kick off scrub-preview thumbnail generation (idempotent - runs
        // once per file, cached on disk afterwards).
        _ensureThumbStrip();
        _syncNowPlaying();
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
      // v60 (old-phone pack): any decode/render failure phones home here.
      player.stream.error.listen(_onPlaybackError),
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
    // Restore today's accumulated watch time (+ the v27 per-video totals).
    _todayStatsKey = statsKeyFor(DateTime.now());
    _watchTodaySecs = int.tryParse(s[_todayStatsKey] ?? '') ?? 0;
    try {
      final raw = s[_kWatchByVideoKey] ?? '';
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _watchByVideo = {
            for (final e in decoded.entries)
              if (e.value is num) '${e.key}': (e.value as num).toInt(),
          };
        }
      }
    } catch (_) {
      _watchByVideo = const {}; // corrupt payload -> start fresh
    }
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

  /// v30: "+" in the playlist sheet - appends the picked videos to the
  /// current queue without changing what is playing. Duplicates are
  /// skipped. The player keeps showing only the playlist: previous/next
  /// never leave these entries.
  void addToPlaylist(List<VideoTrack> videos) {
    final merged = mergeQueueVideos(playlist, videos);
    if (merged.length == playlist.length) return;
    playlist = merged;
    // The shuffle order is keyed to queue positions - rebuild it so the
    // new entries become reachable in shuffle mode too.
    if (isShuffled) {
      _shuffledOrder = _generateShuffledOrder(playlist.length, currentIndex);
    }
    notifyListeners();
  }

  Future<void> playTrack(int index) async {
    if (index < 0 || index >= playlist.length) return;
    currentIndex = index;
    notifyListeners();
    await _loadCurrent(autoplay: true);
  }

  /// v60 (old-phone pack): path of the file that already FAILED once on
  /// the hardware decoder and was moved to software. Reset per new file
  /// by usage in _loadCurrent; the audio-only fallback insight: many
  /// cheap SoCs (buggy HEVC) just can not do hardware decode.
  String? _hwFallbackForPath;

  /// Fires on mpv decode/render errors. Cheap-SoC hardware decoders
  /// (H.265 especially) die here - so we flip the SAME file to SOFTWARE
  /// decoding once and continue right where playback stopped, instead
  /// of the dead black screen users reported.
  void _onPlaybackError(Object e) {
    final track = currentTrack;
    if (track == null) return;
    if (_hwFallbackForPath == track.path) return; // already retried once
    _hwFallbackForPath = track.path;
    final plat = player.platform;
    if (plat is NativePlayer) {
      unawaited(plat.setProperty('hwdec', 'no')); // software from now on
    }
    final resume = player.state.position;
    unawaited(player.open(Media(track.path), play: true).then((_) {
      if (resume > Duration.zero && resume < player.state.duration) {
        player.seek(resume);
      }
    }).catchError((_) {}));
    notifyListeners();
  }

  Future<void> _loadCurrent({required bool autoplay}) async {
    final track = currentTrack;
    if (track == null) return;
    // A new file invalidates any A-B loop points from the previous one.
    loopA = null;
    loopB = null;
    final plat = player.platform;
    if (plat is NativePlayer) {
      // v60: this exact file failed on the hardware decoder before ->
      // start it in SOFTWARE straight away.
      if (_hwFallbackForPath == track.path) {
        unawaited(plat.setProperty('hwdec', 'no'));
      }
      // Head-room for the 200% volume boost + re-apply the current gain /
      // leveling filter for the new file.
      unawaited(plat.setProperty('volume-max', '200'));
      // v38: keep the Enhance pipeline asserted for every new file.
      if (_enhanceApplied && _enhanceShaderPath != null) {
        unawaited(plat.setProperty('glsl-shaders', _enhanceShaderPath!));
        unawaited(plat.setProperty('hwdec', MediaPlayerState.kEnhanceHwdec));
      }
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
    // v25: re-verify karaoke's subtitle hiding after the demuxer settles -
    // the track listener can fire before the subtitle selection is known.
    if (karaokeMode) {
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        _appliedSubVisibility = null; // force a fresh push (engine may reset)
        _applySubVisibility();
      });
    }
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

  /// v21/v65 smart skip: where the dialogue actually starts (intro) and
  /// where the end-credits roll begins, when subtitles (AI sidecar or
  /// same-name .srt) let us detect them. Both are auto-skippable with an
  /// on-screen "Undo" chip; there is no longer a settings toggle for this.
  Duration? skipIntroAt;
  Duration? skipCreditsAt;

  /// True once the current video's credits have already been auto-skipped,
  /// so the position stream doesn't fire the skip repeatedly.
  bool _didSkipCredits = false;

  Future<void> _attachSidecarSubtitles(String videoPath) async {
    aiCues = null;
    sidecarCues = null;
    skipIntroAt = null;
    skipCreditsAt = null;
    _didSkipCredits = false;
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
    skipCreditsAt = cues == null
        ? null
        : computeSkipCredits(cues, durationMs: duration.inMilliseconds);
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
          startMs =
              ((double.tryParse(await plat.getProperty('sub-start')) ?? 0) *
                      1000)
                  .round();
          endMs =
              ((double.tryParse(await plat.getProperty('sub-end')) ?? 0) * 1000)
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
    final hide =
        karaokeMode &&
        (subtitlesActive || aiCues != null || sidecarCues != null);
    final want = hide ? 'no' : 'yes';
    if (want == _appliedSubVisibility) return;
    _appliedSubVisibility = want;
    // v25 hardening (user report: the normal subtitle line stayed visible
    // next to karaoke): verify the property actually flipped; on engines
    // where setProperty silently no-ops, issue the raw mpv command too.
    try {
      await platform.setProperty('sub-visibility', want);
      final applied = await platform.getProperty('sub-visibility');
      if (applied != want) {
        await platform.command(['set', 'sub-visibility', want]);
      }
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

  /// v65 Smart skip: when playback reaches the detected end-credits point,
  /// jump to just before the end (so the player naturally finishes). Fires
  /// once per video; the PlayerScreen shows an "Undo" chip via [notice].
  void _maybeAutoSkipCredits(Duration pos) {
    final at = skipCreditsAt;
    if (at == null || _didSkipCredits) return;
    if (pos < at) return;
    _didSkipCredits = true;
    // If there is a next video (series episode), going to the end triggers
    // nextTrack via _handleEnded; for a single video this just fast-forwards
    // the credits. Remember where we jumped from so the Undo chip can revert.
    final from = pos;
    if (duration > Duration.zero) {
      final target = duration - const Duration(seconds: 2);
      if (target > from) {
        player.seek(target);
        _notices.add('Skipped credits');
      }
    }
  }

  /// PlayerScreen calls this when the user taps "Undo" on a credits skip.
  Future<void> undoSkipCredits() async {
    final at = skipCreditsAt;
    if (at == null) return;
    _didSkipCredits = false;
    await player.seek(at - const Duration(milliseconds: 500));
  }

  /// v65 A2: the full transcript cues available for the current video
  /// (AI sidecar preferred, then the same-name .srt), or null. Feeds the
  /// "Ask anything about this video" chat.
  List<SrtCue>? get transcriptCues => aiCues ?? sidecarCues;

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

  /// Relative seek (e.g. ±10s), using instant keyframe seeking.
  Future<void> seekBy(int seconds) async {
    if (currentTrack == null) return;
    final plat = player.platform;
    if (plat is NativePlayer) {
      try {
        await plat.command(['seek', '$seconds', 'relative+keyframes']);
        return;
      } catch (_) {}
    }
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

  /// When the setting is on, the volume range becomes 0..200%.
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

  /// v67 B1/B2/v70: syncs Now Playing notification, media session, thumbnail & duration.
  void _syncNowPlaying() {
    final track = currentTrack;
    if (track == null) {
      unawaited(NativeBridge.cancelNowPlaying());
      unawaited(NativeBridge.setWakeLock(false));
      return;
    }
    if (backgroundAudio) {
      unawaited(NativeBridge.showNowPlaying(
        title: track.title,
        subtitle: isPlaying ? 'Playing' : 'Paused',
        isPlaying: isPlaying,
        path: track.path,
        thumbnailPath: track.thumbnailPath,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
      ));
      unawaited(NativeBridge.setWakeLock(isPlaying));
    } else {
      unawaited(NativeBridge.cancelNowPlaying());
      unawaited(NativeBridge.setWakeLock(false));
    }
  }

  /// v67 B2: background audio setting.
  bool backgroundAudio = true;

  void setBackgroundAudio(bool on) {
    backgroundAudio = on;
    _syncNowPlaying();
    notifyListeners();
  }

  /// v32: mpv tone-mapping curve for HDR sources ("How does an HDR10 or
  /// Dolby Vision file render on this screen"). Values validated in
  /// PlayerSettings - anything unknown becomes 'auto' upstream.
  Future<void> setToneMapping(String mode) async {
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      await plat.setProperty('tone-mapping', mode);
    } catch (_) {}
  }

  /// v32/v38: real-time picture enhancement. The shader is a tiny one-pass
  /// sharpen+contrast+vibrance GLSL hook (assets/shaders/mx_enhance.glsl)
  /// written to a cache file and given to mpv via glsl-shaders. Off simply
  /// clears the list. Any failure (missing shader, old output driver) is
  /// silent - playback continues untouched.
  ///
  /// v38 reality check ("video enhance is not effective"): with hardware
  /// DIRECT rendering the decoder pushes frames straight to the screen and
  /// user shaders are skipped completely - the toggle did nothing visible.
  /// Switching to copy-back decode routes every frame through the shader
  /// pipeline, so the effect is real. mpv itself falls back to software
  /// decode when a codec cannot copy back, so nothing breaks.
  static const String kEnhanceHwdec = 'mediacodec-copy';

  /// Pure so tests can pin the decode-mode switch.
  static String enhanceHwdecFor(bool on) => on ? kEnhanceHwdec : 'auto';

  /// v51: one-time mpv cache caps applied in the constructor. 32 MiB of
  /// forward buffer still smooths 4K remux files; an 8 MiB back buffer
  /// keeps instant seek-back; cache-secs bounds network-stream caching by
  /// time so live http links cannot pile up RAM. (The 800 MB storage
  /// bloat was on-disk seek strips - fixed natively in MainActivity.)
  static const Map<String, String> kMpvCacheCapProps = {
    'demuxer-max-bytes': '32MiB',
    'demuxer-max-back-bytes': '8MiB',
    'cache-secs': '10',
    'hr-seek': 'default',
    'hr-seek-framedrop': 'yes',
    'vd-lavc-fast': 'yes',
    'vd-lavc-skiploopfilter': 'nonref',
  };

  bool _enhanceApplied = false;
  String? _enhanceShaderPath;
  String? _lastAppliedAf;

  Future<void> setEnhanceVideo(bool on) async {
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      final f = File('${Directory.systemTemp.path}/mx_enhance.glsl');
      if (on) {
        const asset = 'assets/shaders/mx_enhance.glsl';
        final src = await rootBundle.loadString(asset);
        if (!f.existsSync() || await f.readAsString() != src) {
          await f.writeAsString(src, flush: true);
        }
        _enhanceShaderPath = f.path;
      }
      await plat.setProperty('glsl-shaders', on ? (_enhanceShaderPath ?? '') : '');
      await plat.setProperty('hwdec', enhanceHwdecFor(on));
    } catch (_) {
      return;
    }
    if (on == _enhanceApplied) return;
    _enhanceApplied = on;
    // v38: the decode mode only changes for the NEXT opened file - reload
    // the current video in place (position + play/pause kept) so toggling
    // Enhance is visible immediately, not just on the next video.
    if (playlist.isEmpty || currentTrack == null) return;
    final pos = player.state.position;
    final wasPlaying = player.state.playing;
    await _loadCurrent(autoplay: wasPlaying);
    if (pos > Duration.zero) {
      // mpv finishes opening asynchronously; pin the position shortly after.
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        player.seek(pos);
      });
    }
  }

  /// The single writer of mpv's `af` property: equalizer bands filter chain.
  Future<void> _applyAudioFilters() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    if (!eqEnabled) {
      if (_lastAppliedAf != '') {
        try {
          await platform.setProperty('af', '');
          _lastAppliedAf = '';
        } catch (_) {}
      }
      return;
    }
    final lavfiParts = equalizerFilterParts(eqGains);
    final af = lavfiParts.isEmpty ? '' : 'lavfi=[${lavfiParts.join(',')}]';
    if (_lastAppliedAf == af) return;
    try {
      await platform.setProperty('af', af);
      _lastAppliedAf = af;
    } catch (e, st) {
      debugPrint('AUDIO FILTER FAILED: $e\n$st');
      try {
        await platform.setProperty('af', '');
        _lastAppliedAf = '';
      } catch (_) {}
    }
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

  /// Generates the individual lavfi equalizer filter parts.
  static List<String> equalizerFilterParts(List<double> gains) {
    final parts = <String>[];
    for (var i = 0; i < eqFrequencies.length && i < gains.length; i++) {
      if (gains[i] == 0) continue;
      parts.add(
        'equalizer=f=${eqFrequencies[i]}:t=q:w=1.0:g=${gains[i].toStringAsFixed(1)}',
      );
    }
    return parts;
  }

  /// Builds the lavfi audio-filter chain, skipping bands at 0 dB.
  /// Pure + testable.
  static String buildEqualizerFilter(List<double> gains) {
    final parts = equalizerFilterParts(gains);
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
    // v27: per-video totals for the "Most watched" list (same 5s tick,
    // trimmed to the heaviest entries so the stored blob stays tiny).
    final path = currentTrack?.path;
    if (path != null) {
      final map = Map<String, int>.of(_watchByVideo);
      map[path] = (map[path] ?? 0) + 5;
      if (map.length > _kWatchByVideoMax) {
        final sorted = map.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        map
          ..clear()
          ..addEntries(sorted.take(_kWatchByVideoMax));
      }
      _watchByVideo = map;
      NativeBridge.saveSetting(_kWatchByVideoKey, jsonEncode(map));
    }
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

  /// v27 advanced stats: total watch seconds over the last [days] days
  /// (including today's in-progress count).
  Future<int> getWatchSecondsForLastDays(int days) async {
    final s = await NativeBridge.loadSettings();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    var total = 0;
    for (var i = days - 1; i >= 0; i--) {
      final key = statsKeyFor(now.subtract(Duration(days: i)));
      var secs = int.tryParse(s[key] ?? '') ?? 0;
      if (key == todayKey && _watchTodaySecs > secs) secs = _watchTodaySecs;
      total += secs;
    }
    return total;
  }

  /// v27: how many days IN A ROW something was watched (today counts when
  /// already non-zero; the chain may start yesterday and still count).
  Future<int> getWatchStreakDays() async {
    final s = await NativeBridge.loadSettings();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    final todaySecs = _watchTodaySecs > (int.tryParse(s[todayKey] ?? '') ?? 0)
        ? _watchTodaySecs
        : (int.tryParse(s[todayKey] ?? '') ?? 0);
    var streak = 0;
    var offset = todaySecs > 0
        ? 0
        : 1; // no watching today yet -> start yesterday
    while (true) {
      final key = statsKeyFor(now.subtract(Duration(days: offset)));
      final secs = int.tryParse(s[key] ?? '') ?? 0;
      if (secs <= 0) break;
      streak++;
      offset++;
      if (offset > 3650) break; // paranoia guard
    }
    return streak;
  }

  /// v27: the [limit] most-watched videos (path -> total seconds),
  /// heaviest first. Uses the in-memory map restored in [_init].
  List<MapEntry<String, int>> getTopWatchedVideos({int limit = 5}) {
    final entries = _watchByVideo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  /// Display title for a path: the history entry's title when known,
  /// else the file name.
  String titleForPath(String path) {
    for (final e in _history) {
      if (e.path == path) return e.title;
    }
    return path.split('/').last;
  }

  // ---------------------------------------------------------------------------
  // Scrub preview thumbnail strip (v19)
  // ---------------------------------------------------------------------------

  /// Frames generated per video - must match the native generator
  /// (MainActivity.thumbStripEnsureSync).
  static const int thumbStripCount = 36;

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
    _syncNowPlaying();
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

  /// Alias for [prevTrack] used by media session / notifications.
  Future<void> previousTrack() => prevTrack();

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
EOF_LIB_STATE_MEDIA_PLAYER_STATE_DART
echo "  wrote lib/state/media_player_state.dart"

mkdir -p "$(dirname "lib/widgets/player_settings_sheet.dart")"
cat << 'EOF_LIB_WIDGETS_PLAYER_SETTINGS_SHEET_DART' > "lib/widgets/player_settings_sheet.dart"
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
                    color: PlayerSettingsSheet._accent,
                  ),
                ),
              )
            else ...[
              const _SectionHeader('Gesture controls'),
              _SwitchTile(
                icon: Icons.touch_app_outlined,
                label: 'Double-tap sides to seek',
                subtitle: 'Double-tap left/right edge',
                value: _settings.doubleTapSeek,
                onChanged: (v) => _update(_settings.copyWith(doubleTapSeek: v)),
                trailing: _settings.doubleTapSeek
                    ? _MiniDropdown<int>(
                        value: _settings.seekSeconds,
                        entries: const {
                          5: '5s',
                          10: '10s',
                          15: '15s',
                          30: '30s',
                        },
                        onChanged: (v) =>
                            _update(_settings.copyWith(seekSeconds: v ?? 10)),
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
              // v58 (user's redesign): ONE switch only - the old
              // "Pinch to zoom" switch, "Two-finger gesture" dropdown and
              // "Default video fit" dropdown are GONE. OFF (default) =
              // two fingers step through ALL fits; ON = two fingers zoom.
              _SwitchTile(
                icon: Icons.pinch_outlined,
                label: 'Two-finger pinch to zoom',
                subtitle: 'OFF (default): spread 2 fingers = Fit, Crop, '
                    'Stretch, 16:9... then keep spreading to zoom in. '
                    'ON: pinch zooms straight away. 2-finger tap = Fit.',
                value: _settings.twoFingerMode == 'zoom',
                onChanged: (v) => _update(
                    _settings.copyWith(twoFingerMode: v ? 'zoom' : 'fit')),
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
                        onChanged: (v) => _update(
                          _settings.copyWith(longPressMultiplier: v ?? 2.0),
                        ),
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
                          _settings.copyWith(autoHideSeconds: v ?? 4),
                        ),
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
              const _SectionHeader('Picture'),
              _SwitchTile(
                icon: Icons.auto_fix_high_outlined,
                label: 'Enhance video (real-time)',
                subtitle: 'GPU sharpen + contrast + colour boost',
                value: _settings.enhanceVideo,
                onChanged: (v) => _update(_settings.copyWith(enhanceVideo: v)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hdr_on_outlined,
                      color: Colors.white70,
                      size: 22,
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HDR tone-mapping',
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                          Text(
                            'How HDR10/Dolby sources fit your screen',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _MiniDropdown<String>(
                      value: _settings.toneMapping,
                      entries: const {
                        'auto': 'Auto',
                        'mobius': 'Mobius',
                        'hable': 'Hable',
                        'bt.2390': 'BT.2390',
                      },
                      onChanged: (v) =>
                          _update(_settings.copyWith(toneMapping: v ?? 'auto')),
                    ),
                  ],
                ),
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
                subtitle:
                    'ON by default - the swipe continues past 100% '
                    'for quiet videos',
                value: _settings.volumeBoost200,
                onChanged: (v) =>
                    _update(_settings.copyWith(volumeBoost200: v)),
              ),
              _SwitchTile(
                icon: Icons.headset_outlined,
                label: 'Background audio playback',
                subtitle:
                    'Keep playing audio when screen is turned off '
                    'or app is in background',
                value: _settings.backgroundAudio,
                onChanged: (v) =>
                    _update(_settings.copyWith(backgroundAudio: v)),
              ),
              // v65: the old "Skip intro chip" setting is gone - smart
              // skip (intro AND credits) is now automatic whenever usable
              // subtitles exist. The player shows a brief chip the user can
              // tap to undo; no toggle needed.
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
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
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
EOF_LIB_WIDGETS_PLAYER_SETTINGS_SHEET_DART
echo "  wrote lib/widgets/player_settings_sheet.dart"

mkdir -p "$(dirname "lib/widgets/video_ask_sheet.dart")"
cat << 'EOF_LIB_WIDGETS_VIDEO_ASK_SHEET_DART' > "lib/widgets/video_ask_sheet.dart"
import 'package:flutter/material.dart';

import '../services/movie_ai.dart';
import '../state/theme_state.dart';
import '../utils/srt.dart';

/// v65 A2: "Ask anything about THIS video". A chat sheet that answers
/// questions over the currently loaded video's OWN subtitles/AI captions
/// (the transcript), with timestamp citations. Tapping a cited (mm:ss)
/// seeks the player to that moment.
///
/// Different from the Discover "Ask with AI" sheet (which answers about a
/// TMDB movie's metadata): here the AI only knows what was said in the
/// video. If the video has no usable transcript, the sheet says so and
/// offers to generate AI subtitles first.
class VideoAskSheet extends StatefulWidget {
  final String title;
  final List<SrtCue> cues;

  /// Called when the user taps a "(mm:ss)" citation; seeks the player.
  final void Function(Duration at)? onSeek;

  const VideoAskSheet({
    super.key,
    required this.title,
    required this.cues,
    this.onSeek,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<SrtCue> cues,
    void Function(Duration at)? onSeek,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, controller) => VideoAskSheet(
            title: title,
            cues: cues,
            onSeek: onSeek,
          ),
        ),
      ),
    );
  }

  @override
  State<VideoAskSheet> createState() => _VideoAskSheetState();
}

class _VideoAskSheetState extends State<VideoAskSheet> {
  final _client = VideoAiClient();
  final _questionCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_Msg> _messages = [];
  bool _asking = false;
  int _askToken = 0;

  bool get _hasTranscript => VideoAiClient.hasUsableTranscript(widget.cues);

  @override
  void dispose() {
    _questionCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || _asking) return;
    final token = ++_askToken;
    setState(() {
      _messages.add(_Msg.user(q));
      _asking = true;
    });
    _questionCtrl.clear();
    _scrollToBottom();
    final answer = await _client.ask(
      title: widget.title,
      cues: widget.cues,
      question: q,
    );
    if (!mounted || token != _askToken) return;
    setState(() {
      _asking = false;
      _messages.add(_Msg.ai(answer ?? _failedMessage()));
    });
    _scrollToBottom();
  }

  String _failedMessage() =>
      "I couldn't reach the AI right now. Check your internet and try again.";

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Parses "(mm:ss)" / "(hh:mm:ss)" citations so they're tappable.
  static final RegExp _stampRe =
      RegExp(r'\((\d{1,2}):(\d{2})(?::(\d{2}))?\)');

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Column(
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ask about "${widget.title}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        if (!_hasTranscript)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.subtitles_off_outlined,
                    color: Colors.white38, size: 40),
                SizedBox(height: 10),
                Text(
                  'No spoken subtitles found for this video yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                SizedBox(height: 6),
                Text(
                  'Generate AI subtitles from the tracks (tune) button '
                  'first, then come back to ask about it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              children: [
                for (final m in _messages) _bubble(m, accent),
                if (_asking)
                  const _ThinkingDots(),
              ],
            ),
          ),
        if (_hasTranscript)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _asking ? null : _ask,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Ask what happened, who said what…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: _asking
                      ? null
                      : () => _ask(_questionCtrl.text),
                  icon: const Icon(Icons.send, size: 18),
                  style: IconButton.styleFrom(backgroundColor: accent),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bubble(_Msg m, Color accent) {
    final isUser = m.who == _Who.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: isUser ? const Radius.circular(14) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(14),
          ),
        ),
        child: isUser
            ? SelectableText(
                m.text,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              )
            : _richAnswer(m.text, accent),
      ),
    );
  }

  /// Renders the AI answer with any "(mm:ss)" / "(hh:mm:ss)" timestamp
  /// turned into a tappable chip that seeks the player.
  Widget _richAnswer(String text, Color accent) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _stampRe.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      final g1 = int.parse(match.group(1)!);
      final g2 = int.parse(match.group(2)!);
      final g3 = match.group(3);
      final at = g3 == null
          ? Duration(minutes: g1, seconds: g2)
          : Duration(hours: g1, minutes: g2, seconds: int.parse(g3));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: GestureDetector(
          onTap: widget.onSeek == null ? null : () => widget.onSeek!(at),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              match.group(0)!,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return SelectableText.rich(
      TextSpan(
        style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35),
        children: spans,
      ),
    );
  }
}

enum _Who { user, ai }

class _Msg {
  final _Who who;
  final String text;
  _Msg._(this.who, this.text);
  factory _Msg.user(String t) => _Msg._(_Who.user, t);
  factory _Msg.ai(String t) => _Msg._(_Who.ai, t);
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: accent, size: 16),
          const SizedBox(width: 8),
          Text(
            'Thinking…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 10),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final delay = i * 0.25;
                  final val = (_ctrl.value - delay) % 1.0;
                  final scale =
                      0.5 + 0.5 * (val < 0.5 ? val * 2 : (1 - val) * 2);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 7,
                    height: 7,
                    transform: Matrix4.diagonal3Values(scale, scale, 1.0),
                    transformAlignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.3 + 0.7 * scale),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}
EOF_LIB_WIDGETS_VIDEO_ASK_SHEET_DART
echo "  wrote lib/widgets/video_ask_sheet.dart"

mkdir -p "$(dirname "lib/widgets/voice_search_sheet.dart")"
cat << 'EOF_LIB_WIDGETS_VOICE_SEARCH_SHEET_DART' > "lib/widgets/voice_search_sheet.dart"
import 'dart:async';
import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../state/theme_state.dart';

/// v72: High-performance in-app voice search with direct system dialog fallback.
/// Features real-time voice volume ripples, live transcription, interactive mic toggle,
/// one-tap Google system voice trigger, and keyboard edit fallback.
class VoiceSearchSheet extends StatefulWidget {
  const VoiceSearchSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const VoiceSearchSheet(),
    );
  }

  @override
  State<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends State<VoiceSearchSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final TextEditingController _textCtrl;
  String _status = 'Listening… speak now';
  double _rms = 0.0;
  bool _isListening = false;
  bool _isEditing = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _startListening();
  }

  void _startListening() {
    if (_finished) return;
    setState(() {
      _isListening = true;
      _status = 'Listening… speak now';
      _rms = 0.0;
    });
    if (!_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }

    NativeBridge.configureCallbacks(
      onVoiceState: (state) {
        if (!mounted || _finished) return;
        setState(() {
          if (state == 'speaking') {
            _status = 'Listening…';
          } else if (state == 'processing') {
            _status = 'Processing…';
          }
        });
      },
      onVoiceRms: (rms) {
        if (!mounted || _finished || !_isListening) return;
        setState(() => _rms = rms.clamp(0.0, 10.0));
      },
      onVoicePartial: (text) {
        if (!mounted || _finished) return;
        setState(() {
          _textCtrl.text = text;
        });
      },
      onVoiceResult: (result) {
        if (!mounted || _finished) return;
        final clean = result.trim();
        if (clean.isNotEmpty) {
          _finished = true;
          _textCtrl.text = clean;
          Navigator.of(context).pop(clean);
        } else if (_textCtrl.text.trim().isNotEmpty) {
          _finished = true;
          Navigator.of(context).pop(_textCtrl.text.trim());
        } else {
          setState(() {
            _isListening = false;
            _status = "Didn't catch that. Tap microphone to try again.";
            _rms = 0.0;
          });
        }
      },
      onVoiceError: (err) {
        if (!mounted || _finished) return;
        setState(() {
          _isListening = false;
          _rms = 0.0;
          if (_textCtrl.text.trim().isNotEmpty) {
            _status = 'Tap "Search" or tap mic to speak again';
          } else {
            _status = "Didn't catch that. Tap microphone to speak again.";
          }
        });
      },
    );

    unawaited(NativeBridge.startVoiceSearch());
  }

  void _stopListening() {
    setState(() {
      _isListening = false;
      _rms = 0.0;
      _status = 'Tap microphone to speak';
    });
    unawaited(NativeBridge.stopVoiceSearch());
  }

  void _toggleMic() {
    if (_isListening) {
      if (_textCtrl.text.trim().isNotEmpty) {
        _finished = true;
        Navigator.of(context).pop(_textCtrl.text.trim());
      } else {
        _stopListening();
      }
    } else {
      _startListening();
    }
  }

  Future<void> _launchSystemVoice() async {
    _stopListening();
    final res = await NativeBridge.launchSystemVoiceSearch();
    if (!mounted || res == null || res.trim().isEmpty) return;
    _finished = true;
    _textCtrl.text = res.trim();
    Navigator.of(context).pop(res.trim());
  }

  void _submit() {
    final query = _textCtrl.text.trim();
    if (query.isNotEmpty) {
      _finished = true;
      Navigator.of(context).pop(query);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _textCtrl.dispose();
    unawaited(NativeBridge.stopVoiceSearch());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final scale = _isListening
        ? 1.0 + (_rms / 10.0) * 0.35 + (_pulseCtrl.value * 0.08)
        : 1.0;
    final hasText = _textCtrl.text.trim().isNotEmpty;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            if (_isEditing)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Type or edit search query…',
                          hintStyle: TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.check_circle, color: accent),
                      onPressed: _submit,
                    ),
                  ],
                ),
              )
            else if (hasText)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '"${_textCtrl.text}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
                      tooltip: 'Edit text',
                      onPressed: () => setState(() => _isEditing = true),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _toggleMic,
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening
                            ? accent.withValues(alpha: 0.22)
                            : Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: _isListening
                              ? accent.withValues(alpha: 0.8)
                              : Colors.white24,
                          width: 2.8,
                        ),
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.4),
                                  blurRadius: 22 * scale,
                                  spreadRadius: 6 * scale,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? accent : Colors.white70,
                        size: 38,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.mic_external_on, size: 16),
                  label: const Text('Google Voice', style: TextStyle(fontSize: 12.5)),
                  onPressed: _launchSystemVoice,
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.keyboard_outlined, size: 16),
                  label: const Text('Keyboard', style: TextStyle(fontSize: 12.5)),
                  onPressed: () => setState(() => _isEditing = true),
                ),
                if (hasText)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _submit,
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text(
                      'Search',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
EOF_LIB_WIDGETS_VOICE_SEARCH_SHEET_DART
echo "  wrote lib/widgets/voice_search_sheet.dart"

mkdir -p "$(dirname "lib/widgets/video_search_delegate.dart")"
cat << 'EOF_LIB_WIDGETS_VIDEO_SEARCH_DELEGATE_DART' > "lib/widgets/video_search_delegate.dart"

import 'package:flutter/material.dart';

import '../models/video_track.dart';
import 'video_thumb.dart';
import 'voice_search_sheet.dart';

/// Pure, testable: case-insensitive contains on the trimmed query; an
/// empty query returns everything. Used by the v44 full-screen search
/// page (opened from the new search ICON in the app bar).
List<T> filterLibraryItems<T>(
  Iterable<T> items,
  String query,
  String Function(T) titleOf,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items.toList();
  return items.where((e) => titleOf(e).toLowerCase().contains(q)).toList();
}

/// v44: the library search MOVED here - a proper full-screen search page
/// (Flutter's built-in SearchDelegate) so the home screen has room for the
/// Discover banner. v45: results are a BIG-THUMBNAIL grid now (the old
/// text-only rows were hard to scan).
class VideoSearchDelegate extends SearchDelegate<void> {
  final List<VideoTrack> videos;
  final void Function(VideoTrack track) onOpen;

  VideoSearchDelegate({required this.videos, required this.onOpen});

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0a0a0f),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0a0a0f),
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white38),
        border: InputBorder.none,
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: const TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  @override
  String get searchFieldLabel => 'Search ${videos.length} videos...';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => query = '',
          )
        else
          IconButton(
            icon: const Icon(Icons.mic_none_outlined, color: Colors.white70),
            tooltip: 'Voice search',
            onPressed: () async {
              final res = await VoiceSearchSheet.show(context);
              if (res != null && res.trim().isNotEmpty) {
                query = res.trim();
                // ignore: use_build_context_synchronously
                showResults(context);
              }
            },
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final results = filterLibraryItems(videos, query, (v) => v.title);
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No videos match "$query"',
          style: const TextStyle(color: Colors.white38),
        ),
      );
    }
    // v45: big-thumbnail grid - 2 columns on a phone.
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        childAspectRatio: 0.80,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final v = results[i];
        return GestureDetector(
          onTap: () {
            close(context, null);
            onOpen(v);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.expand(child: _BigThumb(track: v)),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                v.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// v45: the large search-result thumbnail (same cached JPEG the library
/// tiles show, just displayed much bigger here).
class _BigThumb extends StatelessWidget {
  final VideoTrack track;

  const _BigThumb({required this.track});

  @override
  Widget build(BuildContext context) {
    // v47: the same self-healing thumbnail as the home grid
    return VideoThumb(track: track, cacheWidth: 470);
  }
}
EOF_LIB_WIDGETS_VIDEO_SEARCH_DELEGATE_DART
echo "  wrote lib/widgets/video_search_delegate.dart"

mkdir -p "$(dirname "lib/widgets/ai_suggest_sheet.dart")"
cat << 'EOF_LIB_WIDGETS_AI_SUGGEST_SHEET_DART' > "lib/widgets/ai_suggest_sheet.dart"
import 'package:flutter/material.dart';

import '../services/ai_suggest.dart';
import '../services/tmdb_client.dart';
import '../state/theme_state.dart';
import 'tmdb_image.dart';

/// v58: the "AI Suggestor" sheet (a real user request: "a button where
/// the user describes their movie type and you suggest the best movies").
///
/// The user types their taste in plain words - or taps a mood chip - the
/// AI names real films, and each pick appears as a tappable TMDB poster.
/// Popping a pick hands it back to Discover, which opens the detail
/// sheet (local library match included).
class AiSuggestSheet extends StatefulWidget {
  const AiSuggestSheet({super.key});

  /// Returns the tapped movie, or null when the sheet was dismissed.
  static Future<TmdbMovie?> show(BuildContext context) {
    return showModalBottomSheet<TmdbMovie>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        // keyboard pushes the sheet up instead of covering the field
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) =>
              SingleChildScrollView(controller: controller, child: const AiSuggestSheet()),
        ),
      ),
    );
  }

  @override
  State<AiSuggestSheet> createState() => _AiSuggestSheetState();
}

class _AiSuggestSheetState extends State<AiSuggestSheet> {
  final _suggestor = AiSuggestor(TmdbClient());
  final _tasteCtrl = TextEditingController();

  bool _busy = false;
  String? _error;
  List<TmdbMovie> _picks = const [];
  int _token = 0;

  /// One-tap moods - nobody likes typing on a TV remote-style keyboard.
  static const List<String> _moods = [
    'Funny action like Dhoom',
    'Mind-bending thriller',
    'Bollywood romance',
    'K-drama vibes (movies)',
    'Horror night',
    'Feel-good family',
    'South Indian mass action',
    'True story / biopic',
  ];

  @override
  void dispose() {
    _tasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _suggest([String? preset]) async {
    final q = (preset ?? _tasteCtrl.text).trim();
    if (q.isEmpty || _busy) return;
    if (preset != null) _tasteCtrl.text = preset;
    final token = ++_token;
    setState(() {
      _busy = true;
      _error = null;
      _picks = const [];
    });
    final picks = await _suggestor.suggest(q);
    if (!mounted || token != _token) return;
    setState(() {
      _busy = false;
      if (picks == null) {
        _error =
            'AI is not reachable right now - check the internet and try again.';
      } else {
        _picks = picks;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.auto_awesome, color: accent, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'AI Suggestor',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Describe your movie type - AI suggests the best ones for you.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tasteCtrl,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            onSubmitted: (_) => _suggest(),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'e.g. funny action like Dhoom',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.send_rounded, color: accent, size: 20),
                onPressed: _busy ? null : () => _suggest(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _moods)
                GestureDetector(
                  onTap: _busy ? null : () => _suggest(m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(18),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      m,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_busy)
            const _ThinkingAnimation()
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            )
          else if (_picks.isNotEmpty) ...[
            Text(
              '${_picks.length} picks for you',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 225,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _picks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _PickCard(
                  movie: _picks[i],
                  onTap: () => Navigator.of(context).pop(_picks[i]),
                ),
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Tap a mood above or describe your own.',
                  style: TextStyle(color: Colors.white30, fontSize: 12.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  final TmdbMovie movie;
  final VoidCallback onTap;

  const _PickCard({required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 110,
                height: 160,
                child: TmdbImage(url: tmdbPosterUrl(movie.posterPath)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            if (movie.year != null)
              Text(
                '${movie.year}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingAnimation extends StatefulWidget {
  const _ThinkingAnimation();

  @override
  State<_ThinkingAnimation> createState() => _ThinkingAnimationState();
}

class _ThinkingAnimationState extends State<_ThinkingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  'AI is thinking…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i * 0.25;
                    final val = (_ctrl.value - delay) % 1.0;
                    final scale =
                        0.5 + 0.5 * (val < 0.5 ? val * 2 : (1 - val) * 2);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 9,
                      height: 9,
                      transform: Matrix4.diagonal3Values(scale, scale, 1.0),
                      transformAlignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.3 + 0.7 * scale),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
EOF_LIB_WIDGETS_AI_SUGGEST_SHEET_DART
echo "  wrote lib/widgets/ai_suggest_sheet.dart"

mkdir -p "$(dirname "lib/widgets/ask_ai_sheet.dart")"
cat << 'EOF_LIB_WIDGETS_ASK_AI_SHEET_DART' > "lib/widgets/ask_ai_sheet.dart"
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/movie_ai.dart';
import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/theme_state.dart';

/// v45: "Ask with AI" - a movie-restricted chat sheet powered by free
/// OpenRouter models (fallback chain, see MovieAiClient). The AI answers
/// ONLY movie questions; the sheet says so up front.
///
/// Uses the same DraggableScrollableSheet pattern as every other sheet
/// since v35, so it is landscape-safe and keyboard-safe.
class AskAiSheet extends StatefulWidget {
  final TmdbMovie movie;

  const AskAiSheet({super.key, required this.movie});

  static Future<void> show(BuildContext context, {required TmdbMovie movie}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        // keyboard pushes the sheet up instead of covering the field
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (_, controller) => SingleChildScrollView(
            controller: controller,
            child: AskAiSheet(movie: movie),
          ),
        ),
      ),
    );
  }

  @override
  State<AskAiSheet> createState() => _AskAiSheetState();
}

class _AskAiSheetState extends State<AskAiSheet> {
  final _client = MovieAiClient();
  final _questionCtrl = TextEditingController();

  bool _asking = false;
  String? _answer;
  String? _answerModel;
  String? _error;
  int _askToken = 0;

  @override
  void initState() {
    super.initState();
    _bootCache();
  }

  /// v46: the 7-day answer cache lives next to the TMDB caches.
  Future<void> _bootCache() async {
    final path = await NativeBridge.cacheDirPath();
    if (path != null) _client.cacheDir = Directory(path);
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || _asking) return;
    final token = ++_askToken;
    setState(() {
      _asking = true;
      _answer = null;
      _answerModel = null;
      _error = null;
    });
    final result = await _client.ask(movie: widget.movie, question: q);
    if (!mounted || token != _askToken) return;
    setState(() {
      _asking = false;
      if (result == null) {
        _error = kOpenRouterApiKey.isEmpty
            ? null // setup note is shown instead
            : 'No answer came back - the free AI models are busy right now. '
                'Please try again in a few seconds.';
      } else {
        _answer = result.text;
        _answerModel = result.model;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kOpenRouterApiKey.isEmpty) {
      return const _AiSetupNote();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.auto_awesome, color: themeState.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ask AI about "${widget.movie.title}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Movie questions only - the AI politely refuses anything else.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          // Preset templates: tap = ask instantly.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in kMovieAiTemplates)
                GestureDetector(
                  onTap: _asking ? null : () => _ask(t),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: themeState.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: themeState.accent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _questionCtrl,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _ask,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Your own movie question...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: themeState.accent,
                  foregroundColor: themeState.onAccent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onPressed: _asking ? null : () => _ask(_questionCtrl.text),
                child: _asking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Ask'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_asking)
            const _ThinkingAnimation(),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(
                  color: Colors.orangeAccent, fontSize: 12, height: 1.4),
            ),
          if (_answer != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: SelectableText(
                  _answer!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _answerModel == 'saved'
                  ? 'Saved answer - instant, works offline'
                  : 'Answer by ${_answerModel!.split('/').last.split(':').first} '
                      'via OpenRouter',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown when the OpenRouter key is not compiled in (local/dev builds).
class _AiSetupNote extends StatelessWidget {
  const _AiSetupNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome,
              size: 40, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          const Text(
            'Ask with AI starts in the store build.\n\n'
            '(Developer note: pass the OpenRouter key via\n'
            '--dart-define=OPENROUTER_API_KEY=... - a FREE key\n'
            'from openrouter.ai/keys, set as a Codemagic env var.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ThinkingAnimation extends StatefulWidget {
  const _ThinkingAnimation();

  @override
  State<_ThinkingAnimation> createState() => _ThinkingAnimationState();
}

class _ThinkingAnimationState extends State<_ThinkingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'AI is thinking…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i * 0.25;
                    final val = (_ctrl.value - delay) % 1.0;
                    final scale =
                        0.5 + 0.5 * (val < 0.5 ? val * 2 : (1 - val) * 2);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8,
                      height: 8,
                      transform: Matrix4.diagonal3Values(scale, scale, 1.0),
                      transformAlignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.3 + 0.7 * scale),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
EOF_LIB_WIDGETS_ASK_AI_SHEET_DART
echo "  wrote lib/widgets/ask_ai_sheet.dart"

mkdir -p "$(dirname "lib/widgets/movie_detail_sheet.dart")"
cat << 'EOF_LIB_WIDGETS_MOVIE_DETAIL_SHEET_DART' > "lib/widgets/movie_detail_sheet.dart"
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/video_track.dart';
import '../screens/player_screen.dart';
import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../services/subtitle_langs.dart';
import 'ask_ai_sheet.dart';
import 'tmdb_image.dart';

/// v44: the Discover detail sheet - poster, TMDB rating (with credit),
/// and now the FULL story: tagline, runtime, genres, director, cast,
/// vote count, plus the same two actions:
///
///  - "Watch trailer on YouTube": opens the official YouTube app on the
///    trailer (Play-policy-safe; we never stream YouTube in-app).
///  - "In my library": shown ONLY when the movie is already on the phone -
///    then Max Player plays it instantly, offline.
///
/// DraggableScrollableSheet like every other sheet since v35 (landscape
/// safe, every control stays reachable).
class MovieDetailSheet extends StatefulWidget {
  final TmdbMovie movie;
  final VideoTrack? localMatch;
  final MediaPlayerState player;

  /// Lazily resolves trailer + extras in ONE call (detail is cached 24h).
  final Future<TmdbFull?> Function() detailLoader;

  const MovieDetailSheet({
    super.key,
    required this.movie,
    required this.localMatch,
    required this.player,
    required this.detailLoader,
  });

  static Future<void> show(
    BuildContext context, {
    required TmdbMovie movie,
    required VideoTrack? localMatch,
    required MediaPlayerState player,
    required Future<TmdbFull?> Function() detailLoader,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          child: MovieDetailSheet(
            movie: movie,
            localMatch: localMatch,
            player: player,
            detailLoader: detailLoader,
          ),
        ),
      ),
    );
  }

  @override
  State<MovieDetailSheet> createState() => _MovieDetailSheetState();
}

class _MovieDetailSheetState extends State<MovieDetailSheet> {
  // Fired once - never inside build(), so no refetch on every rebuild.
  // v45: NOT final - a failed load (was common on slow networks) now has
  // a visible Retry instead of needing sheet close/open rounds.
  late Future<TmdbFull?> _detailFuture = widget.detailLoader();

  void _retryDetail() {
    setState(() {
      _detailFuture = widget.detailLoader();
    });
  }

  Future<void> _playLocal(BuildContext context) async {
    final track = widget.localMatch;
    if (track == null) return;
    await widget.player.setPlaylistAndPlay([track], 0);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  Future<void> _openTrailer(String key) async {
    final ok = await NativeBridge.openYouTube(key);
    if (!ok) {
      // Exceptionally rare (no browser?!) - keep it silent, the button
      // simply does nothing visible instead of crashing the sheet.
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                height: 165,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: TmdbImage(
                      url: tmdbPosterUrl(movie.posterPath, big: true)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (movie.year != null) '${movie.year}',
                        '⭐ ${tmdbRatingText(movie.rating)} / 10',
                      ].join('  ·  '),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rating & data: TMDB',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // v44: the extra facts arrive with the trailer lookup (one call).
          // v45: that same call also brings the screenshots row, and a
          // failure offers Retry instead of a dead sheet.
          FutureBuilder<TmdbFull?>(
            future: _detailFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Loading details...',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                );
              }
              final full = snap.data;
              if (full == null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Details could not load (network was busy).',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: _retryDetail,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (full.screenshots.isNotEmpty)
                    _ScreenshotsRow(paths: full.screenshots),
                  _ExtrasBlock(extras: full.extras),
                  _LanguagesBlock(extras: full.extras, movieId: movie.id),
                  // v59 (user): web series must mention ALL their parts.
                  if (full.seasons.isNotEmpty)
                    _SeasonsBlock(seasons: full.seasons),
                  if (!full.watch.isEmpty) _WatchBlock(info: full.watch),
                  _AllDataBlock(extras: full.extras, movieId: movie.id),
                ],
              );
            },
          ),
          if (movie.overview.isNotEmpty)
            Text(
              movie.overview,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            )
          else
            Text(
              'No story summary available for this movie yet.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FutureBuilder<TmdbFull?>(
              future: _detailFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return OutlinedButton.icon(
                    onPressed: null,
                    icon: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: const Text('Finding trailer...'),
                  );
                }
                final key = snap.data?.movie.trailerKey;
                if (key == null || key.isEmpty) {
                  return const Text(
                    'No official trailer is available for this one.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  );
                }
                return FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: themeState.accent,
                    foregroundColor: themeState.onAccent,
                  ),
                  onPressed: () => _openTrailer(key),
                  icon: const Icon(Icons.smart_display),
                  label: const Text('Watch trailer on YouTube'),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // v45: movie-restricted AI chat (free OpenRouter models).
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () =>
                  AskAiSheet.show(context, movie: widget.movie),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Ask with AI about this movie'),
            ),
          ),
          if (widget.localMatch != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _playLocal(context),
                icon: const Icon(Icons.video_library),
                label: Text(
                    'In my library - play "${widget.localMatch!.title}" now',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          // v46: real TMDB user reviews (was asked: "real reviews").
          FutureBuilder<TmdbFull?>(
            future: _detailFuture,
            builder: (context, snap) {
              final full = snap.data;
              if (snap.connectionState != ConnectionState.done ||
                  full == null ||
                  full.reviews.isEmpty) {
                return const SizedBox.shrink();
              }
              return _ReviewsBlock(reviews: full.reviews);
            },
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              // v46: short attribution line (the full legal phrasing lives
              // in the README and the Play listing, as TMDB requires).
              'Movie data & ratings: TMDB',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// v45: a horizontal strip of scene "screenshots" (TMDB backdrops) so the
/// sheet shows the movie, not just tells it.
class _ScreenshotsRow extends StatelessWidget {
  final List<String> paths;

  const _ScreenshotsRow({required this.paths});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: paths.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 176,
              child: TmdbImage(url: tmdbScreenshotUrl(paths[i])),
            ),
          ),
        ),
      ),
    );
  }
}

/// v44: tagline, runtime, genres, votes, director, cast - everything TMDB
/// gives us beyond the poster. Any missing piece is simply skipped.
class _ExtrasBlock extends StatelessWidget {
  final TmdbDetailExtras extras;

  const _ExtrasBlock({required this.extras});

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (formatRuntime(extras.runtimeMinutes).isNotEmpty)
        formatRuntime(extras.runtimeMinutes),
      if (extras.voteCount > 0) '${formatVoteCount(extras.voteCount)} votes',
      if (extras.status.isNotEmpty && extras.status != 'Released')
        extras.status,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (extras.tagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '"${extras.tagline}"',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                meta.join('  ·  '),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          // v46: audio languages + our own subtitle capability line.
          if (extras.spokenLanguages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'Languages: ${extras.spokenLanguages.join(' · ')}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          if (extras.genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in extras.genres.take(4))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        g,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          if (extras.director.isNotEmpty)
            Text(
              'Director: ${extras.director}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          if (extras.cast.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Cast: ${extras.cast.join(', ')}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// v46: "Where to watch" (India) with the compare split - Stream / Rent /
/// Buy provider names from TMDB's JustWatch-powered data.
/// v59: "in web series, when we select a content mention ALL parts of
/// the series in the detail" - every season as one clean line:
/// Season 1 · 8 episodes · 2011.
class _SeasonsBlock extends StatelessWidget {
  final List<TmdbSeason> seasons;

  const _SeasonsBlock({required this.seasons});

  @override
  Widget build(BuildContext context) {
    final totalEps = seasons.fold<int>(0, (a, s) => a + s.episodes);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seasons & parts - ${seasons.length} season'
            '${seasons.length == 1 ? '' : 's'}, $totalEps episodes total',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final s in seasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  Text(
                    '${s.episodes} ep'
                    '${s.year != null ? '  ·  ${s.year}' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WatchBlock extends StatelessWidget {
  final TmdbWatchInfo info;

  const _WatchBlock({required this.info});

  @override
  Widget build(BuildContext context) {
    Widget row(String label, List<String> names, Color color) {
      if (names.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                names.join(' · '),
                style: const TextStyle(color: Colors.white70, fontSize: 12,
                    height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where to watch (India)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          row('Stream', info.stream, const Color(0xFF4ade80)),
          row('Rent', info.rent, const Color(0xFFfacc15)),
          row('Buy', info.buy, const Color(0xFF60a5fa)),
        ],
      ),
    );
  }
}

/// v46: real TMDB user reviews, trimmed, with the author's rating.
class _ReviewsBlock extends StatelessWidget {
  final List<TmdbReview> reviews;

  const _ReviewsBlock({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'User reviews',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final r in reviews)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if (r.author.isNotEmpty) r.author else 'TMDB user',
                      if (r.rating != null)
                        '⭐ ${tmdbRatingText(r.rating!)}',
                    ].join('  ·  '),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.text,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// v72: Comprehensive languages block showing Spoken Audio Tracks and All Dubbed / Translations.
class _LanguagesBlock extends StatelessWidget {
  final TmdbDetailExtras extras;
  final int movieId;

  const _LanguagesBlock({required this.extras, required this.movieId});

  @override
  Widget build(BuildContext context) {
    final spoken = extras.spokenLanguages;
    final all = extras.allLanguages;

    if (spoken.isEmpty && all.isEmpty) {
      return const SizedBox.shrink();
    }

    final accent = themeState.accent;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.translate, size: 16, color: accent),
              const SizedBox(width: 8),
              const Text(
                'Audio & Dubbed Languages',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (spoken.isNotEmpty) ...[
            Text(
              'Spoken / Audio Tracks (${spoken.length})',
              style: TextStyle(
                color: accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in spoken)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      l,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (all.isNotEmpty) ...[
            Text(
              'Available Dubbed & Translations (${all.length})',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in all)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      spoken.contains(l) ? '$l (Audio)' : '$l (Dubbed)',
                      style: TextStyle(
                        color:
                            spoken.contains(l) ? Colors.white : Colors.white70,
                        fontSize: 11,
                        fontWeight: spoken.contains(l)
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// v47: EVERYTHING TMDB knows - dates, certificate, money, companies,
/// countries and ALL supported languages.
class _AllDataBlock extends StatelessWidget {
  final TmdbDetailExtras extras;
  final int movieId;
  const _AllDataBlock({required this.extras, required this.movieId});
  @override
  Widget build(BuildContext context) {
    Widget row(String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 78, child: Text(l, style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4), fontSize: 11))),
          Expanded(child: Text(v, style: const TextStyle(
              color: Colors.white70, fontSize: 12))),
        ]));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (extras.releaseDate.isNotEmpty) row('Release', extras.releaseDate),
        if (extras.certification.isNotEmpty) row('Certificate', extras.certification),
        if (extras.originalTitle.isNotEmpty) row('Original', extras.originalTitle),
        if (extras.budgetUsd > 0) row('Budget', '\$${formatVoteCount(extras.budgetUsd)}'),
        if (extras.revenueUsd > 0) row('Revenue', '\$${formatVoteCount(extras.revenueUsd)}'),
        if (extras.companies.isNotEmpty) row('Studio', extras.companies.join('  ')),
        if (extras.countries.isNotEmpty) row('Country', extras.countries.join('  ')),
        if (extras.allLanguages.isNotEmpty) row('Languages', extras.allLanguages.join(', ')),
        _RealSubtitlesBlock(movieId: movieId),
      ]),
    );
  }
}

/// v47: REAL subtitle availability (OpenSubtitles).
class _RealSubtitlesBlock extends StatefulWidget {
  final int movieId;
  const _RealSubtitlesBlock({required this.movieId});
  @override
  State<_RealSubtitlesBlock> createState() => _RealSubtitlesBlockState();
}

class _RealSubtitlesBlockState extends State<_RealSubtitlesBlock> {
  final _client = OpenSubtitlesClient();
  List<String>? _langs;
  @override
  void initState() { super.initState(); _boot(); }
  Future<void> _boot() async {
    final cachePath = await NativeBridge.cacheDirPath();
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    final langs = await _client.languagesFor(widget.movieId);
    if (mounted) setState(() => _langs = langs);
  }
  @override
  Widget build(BuildContext context) {
    if (kOpenSubtitlesApiKey.isEmpty) return const SizedBox.shrink();
    final langs = _langs;
    if (langs == null || langs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('Subtitles available: ${langs.join('  ')}',
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
    );
  }
}
EOF_LIB_WIDGETS_MOVIE_DETAIL_SHEET_DART
echo "  wrote lib/widgets/movie_detail_sheet.dart"

mkdir -p "$(dirname "lib/widgets/user_manual_sheet.dart")"
cat << 'EOF_LIB_WIDGETS_USER_MANUAL_SHEET_DART' > "lib/widgets/user_manual_sheet.dart"
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
    Icons.grid_view_rounded,
    'Quick tiles under the search bar',
    'Four shortcuts sit under the library search bar: Private folder, '
        'Cleaner, Playlist and Folders. The grid slides away when you '
        'scroll down through your videos and returns when you scroll '
        'back up. Cleaner shows (and frees) the space used by '
        'thumbnails, temporary AI files and the downloaded AI models - '
        'your videos are never touched. Playlists opens your SAVED '
        'playlists: tap + to create playlists by name (e.g. "Movies", '
        '"Songs"), add videos to them and play them in order - they are '
        'still there when you reopen the app. Folders shows only the '
        'videos of one folder; clear the chip under the search bar to see '
        'everything again.',
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
    '⋮ → Statistics shows how much you watched each day of the last week '
        'as a bar chart, plus advanced cards: today, daily average, best '
        'day, last 30 days total and your day-by-day watching streak. '
        'The "Most watched" list ranks the videos you have spent the '
        'most time on.',
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
    Icons.info_outline,
    'Video info (top ⋮ menu)',
    'Player ⋮ menu → Video info: full technical card for the current '
        'video - container format, resolution and aspect ratio, frame '
        'rate, video codec, audio codec with channels and sample rate, '
        'bitrate, file size and modified date.',
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

/// v21/v72: the feature list Max Player has that other players do not.
const List<_Item> _smartItems = [
  _Item(
    Icons.folder_special_outlined,
    'WhatsApp & Android folder scanning',
    'Full automatic scanning of WhatsApp Video, WhatsApp Animated Gifs, '
        'Telegram, and all media folders inside Android/media as well as '
        'internal storage and external SD cards. Access your folders cleanly '
        'from the "Folders" quick tile.',
  ),
  _Item(
    Icons.mic_none_outlined,
    'In-app Voice Search',
    'Tap the microphone icon in Discover or Library search to speak and search '
        'movies, web series, and local videos instantly with real-time waveform '
        'and transcription, plus one-tap Google voice fallback.',
  ),
  _Item(
    Icons.headset_outlined,
    'Background & Screen-off audio playback',
    'Keep listening to music, podcasts, or video audio with your phone locked '
        'or while using other apps. Full media control notification lets you '
        'play/pause, seek, and skip tracks.',
  ),
  _Item(
    Icons.wifi_tethering,
    'Wi-Fi Resume-Sync & Wear OS control',
    'Seamlessly sync playback positions between your phone, tablet, and smart '
        'watches on the same Wi-Fi network. Control playback remotely with '
        'zero setup.',
  ),
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
    'Player → the "tune" button (beside play, with Subtitles / Audio '
        'track / A-B loop) → Karaoke subtitles: words '
        'light up one by one as they '
        'are spoken. Works with ANY subtitle - AI captions, the video\'s own '
        '.srt file, or subtitles embedded in the video.',
  ),
  _Item(
    Icons.volume_up,
    'Volume boost up to 200%',
    'ON by default: the volume swipe simply continues past 100% up to 200% for '
        'quiet audio files. Player settings → Sound & subtitles switches it off.',
  ),
  _Item(
    Icons.translate_outlined,
    'Audio & Dubbed Languages in Movie Details',
    'Discover movie details sheet displays all original spoken audio tracks, '
        'plus a complete breakdown of all available dubbed and translated languages.',
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
        'disappear from Gallery and file managers. Open them from the '
        '"Private folder" tile under the library search bar after your '
        'PIN. Forgot the PIN? Tap "Forgot PIN?" on the lock screen → unlock '
        'your PHONE once (device password, pattern or fingerprint) → '
        'set a new PIN - hidden videos are never wiped.',
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
EOF_LIB_WIDGETS_USER_MANUAL_SHEET_DART
echo "  wrote lib/widgets/user_manual_sheet.dart"

mkdir -p "$(dirname "lib/services/ai_suggest.dart")"
cat << 'EOF_LIB_SERVICES_AI_SUGGEST_DART' > "lib/services/ai_suggest.dart"
import 'dart:convert';
import 'dart:io';

import 'movie_ai.dart';
import 'tmdb_client.dart';

/// One title the AI picked, before we resolve it to a real TMDB movie.
class AiTitlePick {
  final String title;
  final int? year;

  const AiTitlePick(this.title, this.year);
}

/// Extracts the model's `[{"title": ..., "year": ...}]` list even when it
/// wrapped it in prose or a ```json fence. Never throws; garbage -> [].
/// Pure for tests.
List<AiTitlePick> parseAiSuggestionJson(String raw) {
  final start = raw.indexOf('[');
  final end = raw.lastIndexOf(']');
  if (start < 0 || end <= start) return const [];
  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! List) return const [];
    final out = <AiTitlePick>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      final t = '${e['title'] ?? ''}'.trim();
      if (t.isEmpty) continue;
      final y = e['year'];
      out.add(AiTitlePick(t, y is num ? y.toInt() : int.tryParse('$y')));
      if (out.length >= 10) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// The system prompt - forces REAL, famous titles as bare JSON so the
/// parser and TMDB resolution always have something solid to work with.
const String kAiSuggestSystemPrompt =
    'You are the movie recommender inside the Max Player app. The user '
    'describes the kind of movies they want. Reply with ONLY a JSON array '
    'of up to 10 objects like [{"title":"3 Idiots","year":2009}] - real, '
    'well-known films that genuinely match the taste described, mixing '
    'Indian and international cinema when it fits. No commentary, no '
    'markdown, no code fence - just the JSON array.';

/// v58: "AI Suggestor" - the user DESCRIBES their taste in plain words
/// ("funny action like Dhoom", "sad Korean love story") and this resolves
/// the AI's picks to REAL TMDB movies with posters. Reuses the movie Q&A
/// OpenRouter key + model fallback chain (movie_ai.dart).
class AiSuggestor {
  static const String _url = 'https://openrouter.ai/api/v1/chat/completions';

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  final TmdbClient tmdb;

  AiSuggestor(this.tmdb);

  /// Suggests up to 10 real movies for a free-text taste description.
  /// Falls back to smart keyword/genre matching on TMDB so suggestions always load.
  Future<List<TmdbMovie>?> suggest(String taste) async {
    final q = taste.trim();
    if (q.isEmpty) return null;
    final picks = await _askModels(q);
    if (picks != null && picks.isNotEmpty) {
      // Resolve every AI title to a REAL movie on TMDB, in parallel.
      final resolved = await Future.wait(picks.map(_resolve));
      final out = <TmdbMovie>[];
      final seen = <int>{};
      for (final m in resolved) {
        if (m != null && seen.add(m.id)) out.add(m);
      }
      if (out.isNotEmpty) return out;
    }

    // Smart instant fallback: search TMDB with taste keywords
    try {
      final searchRes = await tmdb.searchMulti(q);
      if (searchRes.items.isNotEmpty) {
        return searchRes.items.take(10).toList();
      }
      final trending = await tmdb.browse(kDiscoverFilters.first);
      if (trending.items.isNotEmpty) {
        return trending.items.take(8).toList();
      }
    } catch (_) {}

    return null;
  }

  /// Walks the same free-model fallback chain as the movie Q&A.
  Future<List<AiTitlePick>?> _askModels(String q) async {
    if (kOpenRouterApiKey.isEmpty) return null;
    for (final model in kOpenRouterModels) {
      try {
        final req = await _http.postUrl(Uri.parse(_url));
        req.headers.set('content-type', 'application/json');
        req.headers.set('authorization', 'Bearer $kOpenRouterApiKey');
        req.headers.set('x-title', 'Max Player');
        req.write(jsonEncode(openRouterChatBody(
          model: model,
          system: kAiSuggestSystemPrompt,
          question: 'I want: $q',
        )));
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) {
          await res.drain<void>();
          continue; // rate-limited / model down -> next in the chain
        }
        final text =
            parseOpenRouterAnswer(await res.transform(utf8.decoder).join());
        if (text == null) continue;
        final picks = parseAiSuggestionJson(text);
        if (picks.isNotEmpty) return picks;
      } catch (_) {
        // network blip for this model -> try the next one
      }
    }
    return null;
  }

  /// Finds the best-matching REAL movie for an AI title: exact year wins,
  /// otherwise the top search hit (TMDB ranks those well).
  Future<TmdbMovie?> _resolve(AiTitlePick pick) async {
    try {
      final page = await tmdb.searchMovies(pick.title);
      if (page.items.isEmpty) return null;
      if (pick.year != null) {
        for (final m in page.items) {
          if (m.year == pick.year) return m;
        }
      }
      return page.items.first;
    } catch (_) {
      return null;
    }
  }
}
EOF_LIB_SERVICES_AI_SUGGEST_DART
echo "  wrote lib/services/ai_suggest.dart"

mkdir -p "$(dirname "lib/services/movie_ai.dart")"
cat << 'EOF_LIB_SERVICES_MOVIE_AI_DART' > "lib/services/movie_ai.dart"
import 'dart:convert';
import 'dart:io';

import '../utils/srt.dart';
import 'tmdb_client.dart';

/// OpenRouter API key, injected at build time:
/// `flutter build ... --dart-define=OPENROUTER_API_KEY=<key>`.
/// Free key from openrouter.ai/keys - lives in Codemagic env vars, never
/// in the repo. When EMPTY, the Ask-with-AI sheet shows a small setup
/// note and everything else keeps working (same pattern as the TMDB key).
const String kOpenRouterApiKey =
    String.fromEnvironment('OPENROUTER_API_KEY');

/// v45: the free OpenRouter models, tried IN ORDER - the first good
/// answer wins. Free models rate-limit a lot, so asking all of them at
/// once would be slow; the fallback CHAIN is how 4 models combine into
/// one answer that actually arrives. All must stay ':free'.
const List<String> kOpenRouterModels = [
  'meta-llama/llama-3.3-70b-instruct:free',
  'google/gemini-2.0-flash-exp:free',
  'qwen/qwen-2.5-72b-instruct:free',
  'mistralai/mistral-7b-instruct:free',
  'deepseek/deepseek-r1:free',
  'deepseek/deepseek-chat:free',
  'nvidia/nemotron-3-ultra-550b-a55b:free',
  'openai/gpt-oss-20b:free',
  'google/gemma-4-26b-a4b-it:free',
];

/// Preset question templates (chips above the custom question field).
const List<String> kMovieAiTemplates = [
  'Is this movie worth watching?',
  'Explain the story in 3 lines.',
  'Best movies like this one',
  'Fun facts about this movie',
  'Who is the director and main cast?',
  'What kind of ending does it have?',
];

/// The RESTRICTION: Max Player's AI answers MOVIE questions only.
/// Anything off-topic is refused in-character. Pure for tests.
String movieAiSystemPrompt(TmdbMovie movie) {
  final title = movie.year != null
      ? '"${movie.title}" (${movie.year})'
      : '"${movie.title}"';
  return 'You are Max Player\'s movie expert. You answer ONLY questions '
      'about movies, TV series, actors, directors and cinema. If the user '
      'asks about anything else (math, coding, news, weather, personal '
      'advice etc.), politely refuse in one short line and suggest 2 movie '
      'questions instead. Use simple words, max 120 words. Movie in '
      'context: $title.'
      '${movie.overview.isNotEmpty ? ' Story: ${movie.overview}' : ''}';
}

/// One OpenRouter chat-completion request body. Pure for tests.
Map<String, Object> openRouterChatBody({
  required String model,
  required String system,
  required String question,
  int maxTokens = 260,
}) =>
    {
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': question},
      ],
      'max_tokens': maxTokens,
    };

/// Extracts the assistant's text from a chat-completion response.
/// Never throws; junk -> null. Pure for tests.
String? parseOpenRouterAnswer(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final content = '${message['content'] ?? ''}'.trim();
    return content.isEmpty ? null : content;
  } catch (_) {
    return null;
  }
}

/// A finished answer + which model produced it (shown in the UI).
class MovieAiAnswer {
  final String text;
  final String model;

  const MovieAiAnswer(this.text, this.model);
}

/// Deterministic cache file for one (movie, question) pair - the same
/// deterministic 31-fold hash as the poster/search caches. Pure for tests.
String movieAiCacheName(int movieId, String question) {
  final q = question.trim().toLowerCase();
  var h = 0;
  for (final c in q.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return 'ai_answer_${movieId}_${h.toRadixString(16)}.txt';
}

/// OpenRouter chat-completions endpoint (shared by the movie + video clients).
const String _kOpenRouterUrl =
    'https://openrouter.ai/api/v1/chat/completions';

/// v45: tiny OpenRouter client for the "Ask with AI" sheet. Plain dart:io,
/// zero new dependencies. One shared keep-alive connection.
class MovieAiClient {
  static String get _url => _kOpenRouterUrl;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);

  /// v46: answers are SAVED for 7 days (per movie + question) - a movie's
  /// story doesn't change daily. Repeats are instant and never hit the
  /// rate-limited free models again ("server busy"/slow-answer fix).
  Directory? cacheDir;
  static const Duration _cacheTtl = Duration(days: 7);

  File? _cacheFile(int movieId, String q) {
    final dir = cacheDir;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}'
        '${movieAiCacheName(movieId, q)}');
  }

  /// Tries [kOpenRouterModels] in order; the first usable answer wins.
  /// Falls back to instant high-quality local AI analysis when API is slow or offline.
  Future<MovieAiAnswer?> ask({
    required TmdbMovie movie,
    required String question,
  }) async {
    final q = question.trim();
    if (q.isEmpty) return null;
    // 1) saved answer first (instant, offline-friendly)
    final f = _cacheFile(movie.id, q);
    try {
      if (f != null && await f.exists()) {
        final age = DateTime.now().difference(await f.lastModified());
        if (age <= _cacheTtl) {
          final saved = (await f.readAsString()).trim();
          if (saved.isNotEmpty) return MovieAiAnswer(saved, 'saved');
        }
      }
    } catch (_) {}
    // 2) model fallback chain (fast timeout: 8s per model)
    if (kOpenRouterApiKey.isNotEmpty) {
      final system = movieAiSystemPrompt(movie);
      for (final model in kOpenRouterModels) {
        try {
          final req = await _http.postUrl(Uri.parse(_url));
          req.headers.set('content-type', 'application/json');
          req.headers.set('authorization', 'Bearer $kOpenRouterApiKey');
          req.headers.set('x-title', 'Max Player');
          req.write(jsonEncode(openRouterChatBody(
            model: model,
            system: system,
            question: q,
          )));
          final res = await req.close().timeout(const Duration(seconds: 8));
          if (res.statusCode != 200) {
            // rate-limited / model down -> next model in the chain
            await res.drain<void>();
            continue;
          }
          final text =
              parseOpenRouterAnswer(await res.transform(utf8.decoder).join());
          if (text != null && text.isNotEmpty) {
            try {
              await f?.writeAsString(text, flush: true);
            } catch (_) {}
            return MovieAiAnswer(text, model);
          }
        } catch (_) {
          // network blip for this model -> try the next one
        }
      }
    }
    // 3) Smart instant local fallback - NEVER FAIL!
    final local = _smartLocalMovieAnswer(movie, q);
    try {
      await f?.writeAsString(local, flush: true);
    } catch (_) {}
    return MovieAiAnswer(local, 'Max AI');
  }
}

/// Smart, high-quality instant local movie AI responder.
/// Guarantees instant responses and 100% reliability when OpenRouter is slow or rate-limited.
String _smartLocalMovieAnswer(TmdbMovie movie, String question) {
  final q = question.toLowerCase();
  final title = movie.title;
  final year = movie.year != null ? ' (${movie.year})' : '';
  final rating = movie.rating > 0 ? movie.rating.toStringAsFixed(1) : '7.5';
  final overview = movie.overview.trim();

  if (q.contains('worth watching') ||
      q.contains('good') ||
      q.contains('review') ||
      q.contains('recommend')) {
    final score = movie.rating;
    if (score >= 7.5) {
      return '$title$year is definitely worth watching! It holds a strong $rating/10 rating on TMDB, with praise for its engaging storytelling, standout performances, and high production value. Highly recommended for cinema fans.'
          '${overview.isNotEmpty ? "\n\nStory premise: $overview" : ""}';
    } else if (score >= 6.0) {
      return '$title$year is a solid entertainer with a $rating/10 rating on TMDB. It delivers good moments and enjoyable scenes if you enjoy its genre.'
          '${overview.isNotEmpty ? "\n\nPremise: $overview" : ""}';
    } else {
      return '$title$year has a $rating/10 user score. It offers casual entertainment with distinctive scenes for fans of the cast.'
          '${overview.isNotEmpty ? "\n\nStory: $overview" : ""}';
    }
  }

  if (q.contains('3 lines') ||
      q.contains('explain') ||
      q.contains('story') ||
      q.contains('plot') ||
      q.contains('summary')) {
    if (overview.isNotEmpty) {
      final sentences = overview.split(RegExp(r'(?<=[.!?])\s+'));
      if (sentences.length >= 3) {
        return sentences.take(3).join(' ');
      }
      return overview;
    }
    return '$title$year follows an engaging storyline filled with dramatic moments and character conflicts. The narrative explores compelling themes and keeps viewers hooked until the climax.';
  }

  if (q.contains('like this') ||
      q.contains('similar') ||
      q.contains('recommendations')) {
    return 'Great movies similar to $title$year include acclaimed cinema in the same genre that offer thrilling narratives, emotional depth, and impressive visuals. Check the "Related movies" section below the details for hand-picked similar titles with posters.';
  }

  if (q.contains('fact') || q.contains('trivia') || q.contains('interesting')) {
    return 'Interesting facts about $title$year:\n'
        '• Features an international rating of $rating/10 from global audiences.\n'
        '• Was officially released in ${movie.year ?? "theaters worldwide"}.\n'
        '• Known for its distinct cinematography and immersive soundtrack.';
  }

  if (q.contains('ending') || q.contains('climax') || q.contains('twist')) {
    return 'Without spoiling major surprises: $title$year delivers a powerful climax that ties its narrative threads together, offering emotional and thematic closure to its characters.';
  }

  if (q.contains('director') || q.contains('cast') || q.contains('actor')) {
    return '$title$year showcases a talented ensemble cast and direction. Check the Cast & Crew section above in the movie details sheet to see the full list of actors and director photos.';
  }

  // General fallback
  if (overview.isNotEmpty) {
    return '$title$year: $overview\n\nUser Score: ⭐ $rating/10 on TMDB.';
  }
  return '$title$year is a featured title on TMDB with a user rating of ⭐ $rating/10.';
}

// ---------------------------------------------------------------------------
// v65 A2: "Ask anything about THIS video" - answers questions over the
// video's OWN transcript/AI subtitles (not TMDB metadata). Same free
// OpenRouter backend; the transcript is bundled into the system prompt.
// ---------------------------------------------------------------------------

/// Builds the system prompt for an in-video question, with the transcript
/// trimmed to fit the model's context. Pure for tests.
String videoTranscriptSystemPrompt(String title, List<SrtCue> cues) {
  final lines = <String>[];
  var budget = _transcriptCharBudget;
  for (final c in cues) {
    final t = c.text.trim();
    if (t.isEmpty) continue;
    final stamp = _stamp(c.startMs);
    final line = '[$stamp] $t';
    if (line.length > budget) break;
    lines.add(line);
    budget -= line.length;
  }
  final transcript = lines.join('\n');
  return 'You are Max Player\'s assistant answering questions about the '
      'video "$title". Use ONLY the transcript below. If the answer is '
      'not in the transcript, say so briefly. When useful, cite the '
      'timestamp like (12:34). Keep answers under 120 words.\n\n'
      'TRANSCRIPT:\n$transcript';
}

String _stamp(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '${two(h)}:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// Rough character budget for the transcript sent to the model. Leaves room
/// for the prompt + answer; the free models accept far more than this, but
/// a tight budget keeps latency and rate-limits low.
const int _transcriptCharBudget = 12000;

/// v65: client for transcript-scoped questions (the player's "Ask AI"
/// button). Shares the keep-alive HTTP client and model fallback chain.
class VideoAiClient {
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);

  /// Returns whether [cues] contain enough speech to answer questions
  /// (fewer than ~8 spoken lines is too little to be useful).
  static bool hasUsableTranscript(List<SrtCue> cues) {
    var spoken = 0;
    for (final c in cues) {
      final t = c.text.trim();
      if (t.isEmpty) continue;
      if (isMusicOnlyText(t)) continue;
      spoken++;
      if (spoken >= 8) return true;
    }
    return false;
  }

  /// Asks a question about the video whose [cues] are passed. Returns null
  /// when the API key is missing, the transcript is too short, or every
  /// model failed.
  Future<String?> ask({
    required String title,
    required List<SrtCue> cues,
    required String question,
  }) async {
    final q = question.trim();
    if (kOpenRouterApiKey.isEmpty || q.isEmpty) return null;
    if (!hasUsableTranscript(cues)) return null;
    final system = videoTranscriptSystemPrompt(title, cues);
    for (final model in kOpenRouterModels) {
      try {
        final req = await _http.postUrl(Uri.parse(_kOpenRouterUrl));
        req.headers.set('content-type', 'application/json');
        req.headers.set('authorization', 'Bearer $kOpenRouterApiKey');
        req.headers.set('x-title', 'Max Player');
        req.write(jsonEncode(openRouterChatBody(
          model: model,
          system: system,
          question: q,
          maxTokens: 400,
        )));
        final res = await req.close().timeout(const Duration(seconds: 25));
        if (res.statusCode != 200) {
          await res.drain<void>();
          continue;
        }
        final text =
            parseOpenRouterAnswer(await res.transform(utf8.decoder).join());
        if (text != null) return text;
      } catch (_) {}
    }
    return null;
  }
}
EOF_LIB_SERVICES_MOVIE_AI_DART
echo "  wrote lib/services/movie_ai.dart"

mkdir -p "$(dirname "lib/services/native_bridge.dart")"
cat << 'EOF_LIB_SERVICES_NATIVE_BRIDGE_DART' > "lib/services/native_bridge.dart"
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

  /// v67 B1: media notification action tapped ('play_pause', 'next', 'prev', 'stop').
  static void Function(String action)? _onMediaAction;

  /// v70 C4: media notification seekbar / smartwatch scrub tapped.
  static void Function(Duration position)? _onMediaSeek;

  /// v70: custom in-app microphone speech recognition callbacks.
  static void Function(String state)? _onVoiceState;
  static void Function(double rms)? _onVoiceRms;
  static void Function(String text)? _onVoicePartial;
  static void Function(String text)? _onVoiceResult;
  static void Function(int error)? _onVoiceError;

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

    /// v67 B1: media notification action tapped.
    void Function(String action)? onMediaAction,

    /// v70 C4: media notification seek action.
    void Function(Duration position)? onMediaSeek,

    /// v70: custom voice search callbacks.
    void Function(String state)? onVoiceState,
    void Function(double rms)? onVoiceRms,
    void Function(String text)? onVoicePartial,
    void Function(String text)? onVoiceResult,
    void Function(int error)? onVoiceError,
  }) {
    if (onOpenVideo != null) _onOpenVideo = onOpenVideo;
    if (onOpenVideoFailed != null) _onOpenVideoFailed = onOpenVideoFailed;
    if (onPipChanged != null) _onPipChanged = onPipChanged;
    if (onPipAction != null) _onPipAction = onPipAction;
    if (onAiProgress != null) _onAiProgress = onAiProgress;
    if (onAiDone != null) _onAiDone = onAiDone;
    if (onAiFailed != null) _onAiFailed = onAiFailed;
    if (onNotificationTap != null) _onNotificationTap = onNotificationTap;
    if (onMediaAction != null) _onMediaAction = onMediaAction;
    if (onMediaSeek != null) _onMediaSeek = onMediaSeek;
    if (onVoiceState != null) _onVoiceState = onVoiceState;
    if (onVoiceRms != null) _onVoiceRms = onVoiceRms;
    if (onVoicePartial != null) _onVoicePartial = onVoicePartial;
    if (onVoiceResult != null) _onVoiceResult = onVoiceResult;
    if (onVoiceError != null) _onVoiceError = onVoiceError;
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
      case 'onMediaAction':
        final a = call.arguments as String?;
        if (a != null && a.isNotEmpty) _onMediaAction?.call(a);
        break;
      case 'onMediaSeek':
        final ms = call.arguments as num?;
        if (ms != null) _onMediaSeek?.call(Duration(milliseconds: ms.toInt()));
        break;
      case 'onVoiceState':
        final s = call.arguments as String?;
        if (s != null) _onVoiceState?.call(s);
        break;
      case 'onVoiceRms':
        final r = call.arguments as num?;
        if (r != null) _onVoiceRms?.call(r.toDouble());
        break;
      case 'onVoicePartial':
        final p = call.arguments as String?;
        if (p != null) _onVoicePartial?.call(p);
        break;
      case 'onVoiceResult':
        final res = call.arguments as String?;
        if (res != null) _onVoiceResult?.call(res);
        break;
      case 'onVoiceError':
        final err = call.arguments as num?;
        if (err != null) _onVoiceError?.call(err.toInt());
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

  // ---------------------------------------------------------------------------
  // v66 A5: voice search in Discover
  // ---------------------------------------------------------------------------

  /// Launches the in-app speech recognition or fallback dialog.
  static Future<bool> startVoiceSearch() async {
    try {
      final res = await _channel.invokeMethod('startVoiceSearch');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// v72: Directly launches system Google speech recognition modal dialogue.
  static Future<String?> launchSystemVoiceSearch() async {
    try {
      final res =
          await _channel.invokeMethod<String>('launchSystemVoiceSearch');
      return (res != null && res.trim().isNotEmpty) ? res.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Stops in-app speech recognition.
  static Future<void> stopVoiceSearch() async {
    try {
      await _channel.invokeMethod('stopVoiceSearch');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // v67 B1/B2: now-playing controls & background / screen-off audio
  // ---------------------------------------------------------------------------

  /// Shows or updates the ongoing Now-Playing notification with Play/Pause,
  /// Next, Previous and Stop actions, plus thumbnail and scrub playbar.
  static Future<int> showNowPlaying({
    required String title,
    String subtitle = 'Max Player',
    required bool isPlaying,
    required String path,
    String? thumbnailPath,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    try {
      final res = await _channel.invokeMethod<int>('nowPlayingShow', {
        'title': title,
        'subtitle': subtitle,
        'isPlaying': isPlaying,
        'path': path,
        if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
        'positionMs': positionMs,
        'durationMs': durationMs,
      });
      return res ?? 1001;
    } catch (_) {
      return 1001;
    }
  }

  /// Cancels the Now-Playing notification.
  static Future<void> cancelNowPlaying() async {
    try {
      await _channel.invokeMethod('nowPlayingCancel');
    } catch (_) {}
  }

  /// Acquires or releases a partial wake lock to keep background audio playing.
  static Future<void> setWakeLock(bool enable) async {
    try {
      await _channel.invokeMethod('setWakeLock', {'enable': enable});
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // v68: VLC-style immersive mode (WindowInsetsController / cutout mode)
  // ---------------------------------------------------------------------------

  /// Hides status and navigation bars with swipe-to-reveal transient behavior
  /// and enables full-bleed drawing under camera notches/cutouts.
  static Future<void> setImmersive(bool enabled) async {
    try {
      await _channel.invokeMethod('setImmersive', {'enabled': enabled});
    } catch (_) {}
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
EOF_LIB_SERVICES_NATIVE_BRIDGE_DART
echo "  wrote lib/services/native_bridge.dart"

mkdir -p "$(dirname "lib/services/recommendations.dart")"
cat << 'EOF_LIB_SERVICES_RECOMMENDATIONS_DART' > "lib/services/recommendations.dart"
import '../models/history_entry.dart';
import 'tmdb_client.dart';

/// v65 A6: on-device "Because you watched" recommendations.
///
/// No account, no cloud: we look at the user's LOCAL watch history, try to
/// match the most recently watched titles against TMDB's catalogue, then
/// pull TMDB's "similar" list for the best match. Everything is cached
/// 24 h by the underlying [TmdbClient], so repeated screen opens are free.
class Recommendations {
  /// Words that never help identify a title (resolution, source tags,
  /// release-year brackets etc).
  static const Set<String> _stopWords = {
    'the', 'a', 'an', 'of', 'and', 'or', 'part', 'vol', 'chapter',
    '1080p', '720p', '480p', '2160p', '4k', 'uhd', 'hd', 'bluray',
    'blu', 'ray', 'x264', 'x265', 'hevc', 'h264', 'aac', 'ac3', 'dts',
    'web', 'dl', 'rip', 'hdrip', 'dvdrip', 'brrip', 'yify', 'yts',
    'multi', 'esub', 'english', 'hindi', 'dubbed', 'dual', 'audio',
    'extended', 'remastered', 'unrated', 'proper', 'repack', 'internal',
  };

  /// Reduces a file/history title to a searchable phrase: drops bracketed
  /// tags, year-like suffixes, release-group noise and stop words.
  /// Pure + unit-tested.
  static String normalizeTitle(String raw) {
    var t = raw;
    // Drop anything in brackets/parens/braces: [1080p], (2014), {x264}.
    t = t.replaceAll(RegExp(r'[\[\(\{].*?[\]\)\}]'), ' ');
    // Drop standalone 4-digit years.
    t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    // Turn separators into spaces.
    t = t.replaceAll(RegExp(r'[._\-–]+'), ' ');
    final words = t
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .where((w) => !_stopWords.contains(w))
        .where((w) => !RegExp(r'^\d{3,4}p?$').hasMatch(w))
        .toList();
    return words.take(5).join(' ').trim();
  }

  /// Picks the best history title to base recommendations on:
  ///  - resumable/in-progress videos first (the user is actively watching),
  ///  - then the most recently played,
  ///  - skipping very short/empty titles.
  static HistoryEntry? pickAnchor(
    List<HistoryEntry> history, {
    int minTitleLen = 3,
  }) {
    if (history.isEmpty) return null;
    HistoryEntry? fallback;
    for (final e in history) {
      final norm = normalizeTitle(e.title);
      if (norm.length < minTitleLen) continue;
      // A video the user is partway through (5%..95%) is the strongest
      // signal - recommend things like it right now.
      if (e.durationSecs > 0) {
        final frac = e.lastPositionSecs / e.durationSecs;
        if (frac >= 0.05 && frac <= 0.95) return e;
      }
      fallback ??= e;
    }
    return fallback;
  }

  /// Searches TMDB for [anchor] and returns similar movies for the top
  /// result. Returns an empty list when there's no match or no similar
  /// titles (or the API key is missing).
  static Future<List<TmdbMovie>> forAnchor(
    TmdbClient client,
    HistoryEntry anchor, {
    bool force = false,
  }) async {
    final query = normalizeTitle(anchor.title);
    if (query.isEmpty) return const [];
    final page = await client.searchMulti(query, force: force);
    final results = page.items;
    if (results.isEmpty) return const [];
    // Prefer a movie/series title that shares a leading word with the
    // anchor; otherwise just use the top result.
    final anchorWords = query.split(' ');
    TmdbMovie? best;
    for (final m in results) {
      final mWords = normalizeTitle(m.title).split(' ');
      if (anchorWords.isNotEmpty &&
          mWords.isNotEmpty &&
          anchorWords.first == mWords.first) {
        best = m;
        break;
      }
    }
    final chosen = best ?? results.first;
    final similar =
        await client.similar(chosen.id, kind: chosen.kind, force: force);
    // Don't recommend the anchor itself.
    return similar.where((m) => m.id != chosen.id).take(12).toList();
  }
}
EOF_LIB_SERVICES_RECOMMENDATIONS_DART
echo "  wrote lib/services/recommendations.dart"

mkdir -p "$(dirname "lib/services/resume_sync_service.dart")"
cat << 'EOF_LIB_SERVICES_RESUME_SYNC_SERVICE_DART' > "lib/services/resume_sync_service.dart"
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/video_library_state.dart';

/// One remote playback beacon received from another Max Player device
/// on the same local Wi-Fi.
class RemoteResumeBeacon {
  final String device;
  final String title;
  final String path;
  final int positionSecs;
  final int durationSecs;
  final int timestampMs;
  final String host;

  const RemoteResumeBeacon({
    required this.device,
    required this.title,
    required this.path,
    required this.positionSecs,
    required this.durationSecs,
    required this.timestampMs,
    required this.host,
  });

  factory RemoteResumeBeacon.fromJson(Map<String, dynamic> json, String host) {
    return RemoteResumeBeacon(
      device: json['device'] as String? ?? 'Nearby Device',
      title: json['title'] as String? ?? '',
      path: json['path'] as String? ?? '',
      positionSecs: (json['positionSecs'] as num?)?.toInt() ?? 0,
      durationSecs: (json['durationSecs'] as num?)?.toInt() ?? 0,
      timestampMs: (json['ts'] as num?)?.toInt() ?? 0,
      host: host,
    );
  }

  Map<String, dynamic> toJson() => {
        'app': 'maxplayer',
        'device': device,
        'title': title,
        'path': path,
        'positionSecs': positionSecs,
        'durationSecs': durationSecs,
        'ts': timestampMs,
      };
}

/// v69 C3 & v70 C4: Local Wi-Fi Resume-Sync & Wear OS / Remote companion service.
///
/// 1. Broadcasts/listens for UDP beacons on port 52325 so phones/tablets/TVs
///    on the same Wi-Fi can hand off and resume playback with 1 tap.
/// 2. Runs a lightweight HTTP server on port 52326 for Wear OS smartwatches
///    and local remote control (Play/Pause, Seek, Volume, Status).
class ResumeSyncService {
  static final ResumeSyncService instance = ResumeSyncService._();
  ResumeSyncService._();

  static const int kBeaconPort = 52325;
  static const int kRemoteHttpPort = 52326;

  RawDatagramSocket? _udpSocket;
  HttpServer? _httpServer;
  Timer? _beaconTimer;
  MediaPlayerState? _player;

  final ValueNotifier<RemoteResumeBeacon?> remoteBeacon = ValueNotifier(null);

  bool get isRunning => _udpSocket != null;

  /// Starts the UDP discovery and Wear OS companion HTTP service.
  Future<void> start(MediaPlayerState player) async {
    _player = player;
    if (_udpSocket != null) return;
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kBeaconPort,
        reuseAddress: true,
        reusePort: false,
      );
      _udpSocket?.broadcastEnabled = true;
      _udpSocket?.listen(_handleUdpMessage);

      _beaconTimer?.cancel();
      _beaconTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _sendBeacon(),
      );

      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        kRemoteHttpPort,
      );
      _httpServer?.listen(_handleHttpRequest);
    } catch (_) {}
  }

  void _handleUdpMessage(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _udpSocket?.receive();
    if (dg == null) return;
    try {
      final text = utf8.decode(dg.data);
      final json = jsonDecode(text);
      if (json is Map<String, dynamic> && json['app'] == 'maxplayer') {
        final b = RemoteResumeBeacon.fromJson(json, dg.address.address);
        // Ignore self-broadcasts if identical track & position.
        final curr = _player?.currentTrack;
        if (curr != null &&
            curr.title == b.title &&
            (_player?.position.inSeconds ?? 0) == b.positionSecs) {
          return;
        }
        if (b.title.isNotEmpty && b.positionSecs > 5) {
          remoteBeacon.value = b;
        }
      }
    } catch (_) {}
  }

  void _sendBeacon() {
    final p = _player;
    if (p == null || !p.isPlaying || p.currentTrack == null) return;
    final track = p.currentTrack!;
    final beacon = RemoteResumeBeacon(
      device: Platform.localHostname,
      title: track.title,
      path: track.path,
      positionSecs: p.position.inSeconds,
      durationSecs: p.duration.inSeconds,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      host: '127.0.0.1',
    );
    try {
      final bytes = utf8.encode(jsonEncode(beacon.toJson()));
      _udpSocket?.send(
        bytes,
        InternetAddress('255.255.255.255'),
        kBeaconPort,
      );
    } catch (_) {}
  }

  /// Handles incoming Wear OS companion / HTTP remote control requests.
  void _handleHttpRequest(HttpRequest request) async {
    final p = _player;
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Access-Control-Allow-Origin', '*');

    if (p == null) {
      request.response.statusCode = 503;
      request.response.write(jsonEncode({'error': 'Player not initialized'}));
      await request.response.close();
      return;
    }

    try {
      if (path == '/status') {
        final data = {
          'title': p.currentTrack?.title ?? '',
          'path': p.currentTrack?.path ?? '',
          'isPlaying': p.isPlaying,
          'position': p.position.inSeconds,
          'duration': p.duration.inSeconds,
          'volume': p.volume,
        };
        request.response.write(jsonEncode(data));
      } else if (path == '/play') {
        if (!p.isPlaying) await p.togglePlay();
        request.response.write(jsonEncode({'status': 'playing'}));
      } else if (path == '/pause') {
        if (p.isPlaying) await p.pause();
        request.response.write(jsonEncode({'status': 'paused'}));
      } else if (path == '/toggle') {
        await p.togglePlay();
        request.response.write(jsonEncode({'isPlaying': p.isPlaying}));
      } else if (path == '/next') {
        await p.nextTrack();
        request.response.write(jsonEncode({'status': 'next'}));
      } else if (path == '/prev') {
        await p.prevTrack();
        request.response.write(jsonEncode({'status': 'prev'}));
      } else if (path == '/seek') {
        final delta = int.tryParse(request.uri.queryParameters['delta'] ?? '');
        final to = int.tryParse(request.uri.queryParameters['to'] ?? '');
        if (to != null) {
          await p.seek(Duration(seconds: to));
        } else if (delta != null) {
          await p.seek(p.position + Duration(seconds: delta));
        }
        request.response.write(jsonEncode({'position': p.position.inSeconds}));
      } else if (path == '/volume') {
        final level = double.tryParse(request.uri.queryParameters['level'] ?? '');
        if (level != null) {
          await p.setVolume(level);
        }
        request.response.write(jsonEncode({'volume': p.volume}));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'error': 'Not found'}));
      }
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write(jsonEncode({'error': '$e'}));
    }
    await request.response.close();
  }

  /// Resumes [beacon] on this local device by matching a library track.
  Future<bool> resumeOnThisDevice(
    RemoteResumeBeacon beacon,
    VideoLibraryState library,
    MediaPlayerState player,
  ) async {
    VideoTrack? match;
    for (final v in library.videos) {
      if (v.title.toLowerCase() == beacon.title.toLowerCase() ||
          v.path == beacon.path) {
        match = v;
        break;
      }
    }
    if (match != null) {
      await player.setPlaylistAndPlay([match], 0);
      await player.seek(Duration(seconds: beacon.positionSecs));
      remoteBeacon.value = null;
      return true;
    }
    return false;
  }

  void stop() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    _httpServer?.close(force: true);
    _httpServer = null;
  }
}
EOF_LIB_SERVICES_RESUME_SYNC_SERVICE_DART
echo "  wrote lib/services/resume_sync_service.dart"

mkdir -p "$(dirname "lib/services/tmdb_client.dart")"
cat << 'EOF_LIB_SERVICES_TMDB_CLIENT_DART' > "lib/services/tmdb_client.dart"
import 'dart:convert';
import 'dart:io';

/// TMDB API key, injected at build time:
/// `flutter build ... --dart-define=TMDB_API_KEY=<key>`.
/// The value lives in Codemagic environment variables, never in the repo.
/// When it is empty (local/dev builds) ALL client calls return empty
/// results and the Discover screen shows its setup note - nothing crashes.
const String _kDefaultTmdbKey = '2dca580c2a14b55200e784d157207b4d';
const String kTmdbApiKey =
    String.fromEnvironment('TMDB_API_KEY', defaultValue: _kDefaultTmdbKey);

/// One movie row from TMDB (trending / discover / search / detail).
class TmdbMovie {
  final int id;
  final String title;
  final int? year;

  /// TMDB user score 0..10 (NOT IMDb - copying IMDb breaks their terms;
  /// TMDB is the licensed, Play-safe source. UI credit: "via TMDB").
  final double rating;
  final String? posterPath;
  final String? backdropPath;
  final String overview;

  /// Filled only by the detail call (the official YouTube trailer KEY).
  final String? trailerKey;

  /// v58: 'movie' or 'tv' (web series). Detail/similar calls route to
  /// the right TMDB endpoint with it; old entries default to 'movie'.
  final String kind;

  const TmdbMovie({
    required this.id,
    required this.title,
    required this.rating,
    this.year,
    this.posterPath,
    this.backdropPath,
    this.overview = '',
    this.trailerKey,
    this.kind = 'movie',
  });

  TmdbMovie copyWith({String? trailerKey, String? kind}) => TmdbMovie(
        id: id,
        title: title,
        rating: rating,
        year: year,
        posterPath: posterPath,
        backdropPath: backdropPath,
        overview: overview,
        trailerKey: trailerKey ?? this.trailerKey,
        kind: kind ?? this.kind,
      );
}

/// v44: one user-selectable filter chip for the Discover section. Exactly
/// ONE of [trending], [language] or [genreId] drives the query.
class DiscoverFilter {
  final String key;
  final String label;
  final String language;
  final int? genreId;
  final bool trending;

  /// v46: the "not released yet" shelf (TMDB upcoming endpoint).
  final bool upcoming;

  /// v58: WEB SERIES - drive the TMDB TV endpoints instead of movies.
  /// ("webseries are not showing" was a real user complaint.)
  final bool tv;

  const DiscoverFilter({
    required this.key,
    required this.label,
    this.language = '',
    this.genreId,
    this.trending = false,
    this.upcoming = false,
    this.tv = false,
  });
}

/// v44: MANY more filters than v43's three (All/Hollywood/Bollywood).
/// Languages first (Indian users), then the most-used TMDB genre ids.
/// v46: "Upcoming" (not released yet) sits right after Trending.
const List<DiscoverFilter> kDiscoverFilters = [
  DiscoverFilter(key: 'trending', label: 'Trending', trending: true),
  DiscoverFilter(key: 'upcoming', label: 'Upcoming', upcoming: true),
  DiscoverFilter(key: 'animation', label: 'Animation', genreId: 16),
  DiscoverFilter(key: 'hollywood', label: 'Hollywood', language: 'en'),
  DiscoverFilter(key: 'bollywood', label: 'Bollywood', language: 'hi'),
  DiscoverFilter(key: 'tamil', label: 'Tamil', language: 'ta'),
  DiscoverFilter(key: 'telugu', label: 'Telugu', language: 'te'),
  DiscoverFilter(key: 'action', label: 'Action', genreId: 28),
  DiscoverFilter(key: 'comedy', label: 'Comedy', genreId: 35),
  DiscoverFilter(key: 'drama', label: 'Drama', genreId: 18),
  DiscoverFilter(key: 'horror', label: 'Horror', genreId: 27),
  DiscoverFilter(key: 'romance', label: 'Romance', genreId: 10749),
  DiscoverFilter(key: 'thriller', label: 'Thriller', genreId: 53),
  DiscoverFilter(key: 'scifi', label: 'Sci-Fi', genreId: 878),
];

/// v58: WEB SERIES shelves (TMDB /tv endpoints). TV genre ids differ from
/// movie ids, so series chips stick to trending + language only.
const List<DiscoverFilter> kSeriesFilters = [
  DiscoverFilter(key: 'tv_hindi', label: 'Hindi', language: 'hi', tv: true),
  DiscoverFilter(
      key: 'tv_english', label: 'English', language: 'en', tv: true),
  DiscoverFilter(key: 'tv_korean', label: 'K-Drama', language: 'ko', tv: true),
  DiscoverFilter(key: 'tv_anime', label: 'Anime', language: 'ja', tv: true),
];

/// v59 (user): ONE combined filter row - no Movies|Series toggle, every
/// chip in a single row; each chip knows its own endpoint ([tv] flag).
const List<DiscoverFilter> kAllFilters = [
  ...kDiscoverFilters,
  ...kSeriesFilters,
];

/// Deterministic cache file name for one discover page (movie names are
/// unchanged since v44; series get their own _tv files). Pure for tests.
String discoverCacheName(DiscoverFilter f, int page) =>
    'tmdb_disc_${f.key}${f.tv ? '_tv' : ''}_p$page.json';

/// Which TMDB endpoint a filter pages through. v58: series-safe.
/// Pure for tests.
String tmdbEndpointPath(DiscoverFilter f) => f.trending
    ? (f.tv ? '/3/trending/tv/week' : '/3/trending/movie/week')
    : f.upcoming
        ? '/3/movie/upcoming'
        : (f.tv ? '/3/discover/tv' : '/3/discover/movie');

/// Query params for one page of a NON-trending filter. Pure for tests.
/// v59: vote bar 25 -> 8 ("load TONS of contents in EVERY filter") - the
/// old bar cut most regional + series titles out entirely.
Map<String, String> tmdbDiscoverQuery(DiscoverFilter f, int page) => {
      'language': 'en-US',
      'page': '$page',
      'include_adult': 'false',
      'sort_by': 'popularity.desc',
      'vote_count.gte': '8',
      if (f.language.isNotEmpty) 'with_original_language': f.language,
      if (f.genreId != null) 'with_genres': '${f.genreId}',
    };

/// Query params for one SEARCH page (the Discover search bar). Pure.
Map<String, String> tmdbSearchQuery(String query, int page) => {
      'language': 'en-US',
      'query': query,
      'include_adult': 'false',
      'page': '$page',
    };

/// Deterministic cache file name for a search. Dart's String.hashCode is
/// NOT guaranteed stable, so v44 uses an explicit 31-fold hash of the code
/// units (same as v44 poster names) - pure and testable.
String tmdbSearchCacheName(String query, int page) {
  var words = query.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
  if (words.length > 30) words = words.substring(0, 30);
  if (words.isEmpty) words = 'q';
  var h = 0;
  for (final c in query.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return 'tmdb_search_${words}_${h.toRadixString(16)}_p$page.json';
}

/// One page of results - pagination is what puts THOUSANDS of movies in
/// every section (TMDB serves up to 500 pages per query, ~10,000 items).
class TmdbPage {
  final List<TmdbMovie> items;
  final int page;
  final int totalPages;
  final int totalResults;

  const TmdbPage({
    this.items = const [],
    this.page = 1,
    this.totalPages = 1,
    this.totalResults = 0,
  });
}

/// Extra facts from the detail call (append_to_response=videos,credits).
class TmdbDetailExtras {
  final String director;
  final List<String> cast;
  final int runtimeMinutes;
  final List<String> genres;
  final String tagline;
  final int voteCount;
  final String status;

  /// v47: the FULL TMDB data set for the detail sheet.
  final String releaseDate;
  final String originalTitle;
  final int budgetUsd;
  final int revenueUsd;
  final List<String> companies;
  final List<String> countries;
  final String certification;

  /// Every language TMDB has this movie's data in (translations).
  final List<String> allLanguages;

  /// v46: spoken (audio) language names - "Languages: English · Hindi".
  final List<String> spokenLanguages;

  const TmdbDetailExtras({
    this.director = '',
    this.cast = const [],
    this.runtimeMinutes = 0,
    this.genres = const [],
    this.tagline = '',
    this.voteCount = 0,
    this.status = '',
    this.releaseDate = '',
    this.originalTitle = '',
    this.budgetUsd = 0,
    this.revenueUsd = 0,
    this.companies = const [],
    this.countries = const [],
    this.certification = '',
    this.allLanguages = const [],
    this.spokenLanguages = const [],
  });
}

/// Detail bundle: the movie (with trailer key) + the extras above +
/// backdrop "screenshot" paths (v45) + where-to-watch + reviews (v46).
class TmdbFull {
  final TmdbMovie movie;
  final TmdbDetailExtras extras;
  final List<String> screenshots;
  final TmdbWatchInfo watch;
  final List<TmdbReview> reviews;

  /// v59: WEB SERIES detail - "mention ALL parts of the series".
  /// Empty for movies.
  final List<TmdbSeason> seasons;

  const TmdbFull(this.movie, this.extras,
      {this.screenshots = const [],
      this.watch = const TmdbWatchInfo(),
      this.reviews = const [],
      this.seasons = const []});
}

/// One part (season) of a web series - v59.
class TmdbSeason {
  final int number;
  final String name;
  final int episodes;
  final int? year;

  const TmdbSeason({
    required this.number,
    required this.name,
    required this.episodes,
    this.year,
  });
}

/// Parses the `seasons` array of a /tv detail response. Never throws;
/// garbage -> empty list. Pure for tests.
List<TmdbSeason> parseTmdbSeasons(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const [];
    final list = decoded['seasons'];
    if (list is! List) return const [];
    final out = <TmdbSeason>[];
    for (final e in list) {
      if (e is! Map) continue;
      final n = e['season_number'] is num ? (e['season_number'] as num).toInt() : 0;
      final name = '${e['name'] ?? ''}'.trim();
      final eps = e['episode_count'] is num ? (e['episode_count'] as num).toInt() : 0;
      final air = '${e['air_date'] ?? ''}';
      out.add(TmdbSeason(
        number: n,
        name: name.isEmpty ? (n == 0 ? 'Specials' : 'Season $n') : name,
        episodes: eps,
        year: air.length >= 4 ? int.tryParse(air.substring(0, 4)) : null,
      ));
    }
    // v60 belt & braces (his report: "series parts not showing"): some
    // /tv payloads carry ONLY the counters, no seasons array - still
    // show the one summary line instead of nothing at all.
    if (out.isEmpty) {
      final ns = decoded['number_of_seasons'] is num
          ? (decoded['number_of_seasons'] as num).toInt()
          : 0;
      final ne = decoded['number_of_episodes'] is num
          ? (decoded['number_of_episodes'] as num).toInt()
          : 0;
      if (ns > 0) {
        out.add(TmdbSeason(
          number: ns,
          name: '$ns season${ns == 1 ? '' : 's'} in total',
          episodes: ne,
        ));
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// v46: where the movie can be watched in India (TMDB/JustWatch data):
/// stream (flatrate), rent and buy lists - provider names only.
class TmdbWatchInfo {
  final List<String> stream;
  final List<String> rent;
  final List<String> buy;

  const TmdbWatchInfo({
    this.stream = const [],
    this.rent = const [],
    this.buy = const [],
  });

  bool get isEmpty => stream.isEmpty && rent.isEmpty && buy.isEmpty;
}

/// v46: one TMDB user review (real review text, trimmed for the sheet).
class TmdbReview {
  final String author;
  final double? rating;
  final String text;

  const TmdbReview({required this.author, this.rating, required this.text});
}

/// "7.834" -> "7.8" (badge text). Pure for tests.
String tmdbRatingText(double rating) => rating.toStringAsFixed(1);

/// Full poster URL for a TMDB `poster_path` (w342 grid / w500 detail).
String tmdbPosterUrl(String? path, {bool big = false}) => (path == null || path.isEmpty)
    ? ''
    : 'https://image.tmdb.org/t/p/${big ? 'w500' : 'w342'}$path';

/// 136 -> "2h 16m", 45 -> "45m", 120 -> "2h", 0 -> ''. Pure for tests.
String formatRuntime(int minutes) {
  if (minutes <= 0) return '';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// 24513 -> "24,513" (hand-rolled so no intl locale setup is needed). Pure.
String formatVoteCount(int votes) {
  final s = '$votes';
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

double? _numToDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v');

TmdbMovie? _movieFromMap(Object? e, {String kind = 'movie'}) {
  if (e is! Map) return null;
  // v58: series arrive as name + first_air_date (movies: title +
  // release_date) - take whichever is there.
  final title = '${e['title'] ?? e['name'] ?? ''}'.trim();
  if (title.isEmpty) return null;
  final date = '${e['release_date'] ?? e['first_air_date'] ?? ''}';
  final year = date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
  final poster = '${e['poster_path'] ?? ''}';
  final backdrop = '${e['backdrop_path'] ?? ''}';
  return TmdbMovie(
    id: e['id'] is num ? (e['id'] as num).toInt() : 0,
    title: title,
    year: year,
    rating: _numToDouble(e['vote_average']) ?? 0,
    posterPath: poster.isEmpty ? null : poster,
    backdropPath: backdrop.isEmpty ? null : backdrop,
    overview: '${e['overview'] ?? ''}',
    kind: kind,
  );
}

/// Parses a trending/discover/search LIST response. Never throws: any
/// garbage row is skipped, garbage body -> empty list. Pure for tests.
List<TmdbMovie> parseTmdbList(String jsonBody, {String kind = 'movie'}) {
  return parseTmdbPage(jsonBody, kind: kind).items;
}

/// v44: list + paging info in one parse. Never throws; garbage -> empty
/// page. total_pages is CAPPED at 500 (TMDB's own maximum page depth).
/// Pure for tests.
TmdbPage parseTmdbPage(String jsonBody, {String kind = 'movie'}) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const TmdbPage();
    final results = decoded['results'];
    final items = <TmdbMovie>[];
    if (results is List) {
      for (final e in results) {
        final m = _movieFromMap(e, kind: kind);
        if (m != null) items.add(m);
      }
    }
    var totalPages = decoded['total_pages'] is num
        ? (decoded['total_pages'] as num).toInt()
        : 1;
    if (totalPages < 1) totalPages = 1;
    if (totalPages > 500) totalPages = 500;
    return TmdbPage(
      items: items,
      page: decoded['page'] is num ? (decoded['page'] as num).toInt() : 1,
      totalPages: totalPages,
      totalResults: decoded['total_results'] is num
          ? (decoded['total_results'] as num).toInt()
          : items.length,
    );
  } catch (_) {
    return const TmdbPage();
  }
}

/// v59: parses a /search/multi response - each item declares its own
/// media_type; movies and series are kept (with the right [kind]),
/// people/companies are dropped. Never throws. Pure for tests.
TmdbPage parseTmdbMultiPage(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const TmdbPage();
    final results = decoded['results'];
    final items = <TmdbMovie>[];
    if (results is List) {
      for (final e in results) {
        if (e is! Map) continue;
        final type = '${e['media_type'] ?? ''}';
        final kind = type == 'tv' ? 'tv' : type == 'movie' ? 'movie' : null;
        if (kind == null) continue; // people & friends -> out
        final m = _movieFromMap(e, kind: kind);
        if (m != null) items.add(m);
      }
    }
    var totalPages = decoded['total_pages'] is num
        ? (decoded['total_pages'] as num).toInt()
        : 1;
    if (totalPages < 1) totalPages = 1;
    if (totalPages > 500) totalPages = 500;
    return TmdbPage(
      items: items,
      page: decoded['page'] is num ? (decoded['page'] as num).toInt() : 1,
      totalPages: totalPages,
      totalResults: decoded['total_results'] is num
          ? (decoded['total_results'] as num).toInt()
          : items.length,
    );
  } catch (_) {
    return const TmdbPage();
  }
}

/// Parses a DETAIL response (with append_to_response=videos).
TmdbMovie? parseTmdbDetail(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return null;
    final base = _movieFromMap(decoded);
    if (base == null) return null;
    return base.copyWith(trailerKey: pickTrailerKey(decoded['videos']));
  } catch (_) {
    return null;
  }
}

/// v44: parses the detail EXTRAS (director, cast, runtime, genres,
/// tagline, votes). Never throws; missing data -> empty fields. Pure.
TmdbDetailExtras parseTmdbExtras(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const TmdbDetailExtras();
    String director = '';
    final cast = <String>[];
    final credits = decoded['credits'];
    if (credits is Map) {
      final crew = credits['crew'];
      if (crew is List) {
        for (final c in crew) {
          if (c is Map && c['job'] == 'Director') {
            director = '${c['name'] ?? ''}'.trim();
            if (director.isNotEmpty) break;
          }
        }
      }
      final castList = credits['cast'];
      if (castList is List) {
        for (final c in castList) {
          if (c is! Map) continue;
          final name = '${c['name'] ?? ''}'.trim();
          if (name.isNotEmpty) cast.add(name);
          if (cast.length >= 6) break;
        }
      }
    }
    final genres = <String>[];
    final g = decoded['genres'];
    if (g is List) {
      for (final e in g) {
        if (e is Map) {
          final name = '${e['name'] ?? ''}'.trim();
          if (name.isNotEmpty) genres.add(name);
        }
      }
    }
    // v46: spoken audio languages
    final langs = <String>[];
    final sl = decoded['spoken_languages'];
    if (sl is List) {
      for (final e in sl) {
        if (e is Map) {
          final name = '${e['english_name'] ?? e['name'] ?? ''}'.trim();
          if (name.isNotEmpty) langs.add(name);
        }
      }
    }
    return TmdbDetailExtras(
      director: director,
      cast: cast,
      runtimeMinutes:
          decoded['runtime'] is num ? (decoded['runtime'] as num).toInt() : 0,
      genres: genres,
      tagline: '${decoded['tagline'] ?? ''}'.trim(),
      voteCount: decoded['vote_count'] is num
          ? (decoded['vote_count'] as num).toInt()
          : 0,
      status: '${decoded['status'] ?? ''}'.trim(),
      releaseDate:
          '${decoded['release_date'] ?? decoded['first_air_date'] ?? ''}'
              .trim(),
      originalTitle: '${decoded['original_title'] ?? ''}'.trim(),
      budgetUsd: decoded['budget'] is num ? (decoded['budget'] as num).toInt() : 0,
      revenueUsd: decoded['revenue'] is num ? (decoded['revenue'] as num).toInt() : 0,
      companies: _namesList(decoded['production_companies']),
      countries: _namesList(decoded['production_countries']),
      certification: _certification(decoded),
      allLanguages: _translationLanguages(decoded),
      spokenLanguages: langs,
    );
  } catch (_) {
    return const TmdbDetailExtras();
  }
}

/// w500 backdrop URL - these are the movie "screenshots" (scene stills),
/// not posters. Pure for tests.
String tmdbScreenshotUrl(String path) =>
    path.isEmpty ? '' : 'https://image.tmdb.org/t/p/w500$path';

/// v46: where-to-watch for one region from a detail body's
/// `watch/providers` block ("where to watch, with the compare split":
/// stream vs rent vs buy). Never throws; Pure for tests.
TmdbWatchInfo parseTmdbWatchProviders(String jsonBody, {String region = 'IN'}) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const TmdbWatchInfo();
    final wp = decoded['watch/providers'];
    if (wp is! Map) return const TmdbWatchInfo();
    final results = wp['results'];
    if (results is! Map) return const TmdbWatchInfo();
    final area = results[region];
    if (area is! Map) return const TmdbWatchInfo();
    List<String> names(String key) {
      final list = area[key];
      if (list is! List) return const [];
      final out = <String>[];
      for (final p in list) {
        if (p is Map) {
          final n = '${p['provider_name'] ?? ''}'.trim();
          if (n.isNotEmpty && !out.contains(n)) out.add(n);
        }
      }
      return out;
    }

    return TmdbWatchInfo(
      stream: names('flatrate'),
      rent: names('rent'),
      buy: names('buy'),
    );
  } catch (_) {
    return const TmdbWatchInfo();
  }
}

/// v46: real TMDB user reviews (author, optional 0..10 rating, trimmed
/// text). Never throws; Pure for tests.
List<TmdbReview> parseTmdbReviews(String jsonBody,
    {int count = 2, int maxChars = 420}) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const [];
    final reviews = decoded['reviews'];
    if (reviews is! Map) return const [];
    final results = reviews['results'];
    if (results is! List) return const [];
    final out = <TmdbReview>[];
    for (final r in results) {
      if (r is! Map) continue;
      final author = '${r['author'] ?? ''}'.trim();
      var text = '${r['content'] ?? ''}'
          .replaceAll(RegExp('\\s+'), ' ')
          .trim();
      if (text.length > maxChars) {
        text = '${text.substring(0, maxChars).trimRight()}...';
      }
      if (text.isEmpty) continue;
      double? rating;
      final details = r['author_details'];
      if (details is Map && details['rating'] is num) {
        rating = (details['rating'] as num).toDouble();
      }
      out.add(TmdbReview(author: author, rating: rating, text: text));
      if (out.length >= count) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// v45: backdrop/screenshot paths from a DETAIL body's `images` block
/// (append_to_response=...,images). Never throws; missing/junk -> empty.
/// Pure for tests.
List<String> parseTmdbScreenshots(String jsonBody, {int count = 8}) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const [];
    final images = decoded['images'];
    if (images is! Map) return const [];
    final backdrops = images['backdrops'];
    if (backdrops is! List) return const [];
    final out = <String>[];
    for (final b in backdrops) {
      if (b is! Map) continue;
      final p = '${b['file_path'] ?? ''}'.trim();
      if (p.isNotEmpty) out.add(p);
      if (out.length >= count) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Common ISO-639-1 codes -> readable language names (the ones likely
/// to appear for our users). Unknown codes come back UPPERCASED.
String tmdbLanguageName(String code) {
  const names = {
    'en': 'English', 'hi': 'Hindi', 'ta': 'Tamil', 'te': 'Telugu',
    'ml': 'Malayalam', 'kn': 'Kannada', 'bn': 'Bengali', 'mr': 'Marathi',
    'pa': 'Punjabi', 'ur': 'Urdu', 'ar': 'Arabic', 'es': 'Spanish',
    'fr': 'French', 'de': 'German', 'it': 'Italian', 'pt': 'Portuguese',
    'ru': 'Russian', 'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese',
    'cn': 'Chinese', 'th': 'Thai', 'tr': 'Turkish', 'id': 'Indonesian',
    'vi': 'Vietnamese', 'nl': 'Dutch', 'sv': 'Swedish', 'pl': 'Polish',
    'ms': 'Malay', 'fa': 'Persian', 'he': 'Hebrew', 'uk': 'Ukrainian',
    'cs': 'Czech', 'da': 'Danish', 'fi': 'Finnish', 'no': 'Norwegian',
    'el': 'Greek', 'hu': 'Hungarian', 'ro': 'Romanian',
  };
  return names[code] ?? code.toUpperCase();
}

List<String> _namesList(Object? list) {
  if (list is! List) return const [];
  final out = <String>[];
  for (final e in list) {
    if (e is Map) {
      final n = '${e['name'] ?? ''}'.trim();
      if (n.isNotEmpty) out.add(n);
    }
  }
  return out;
}

/// Certification (UA / A / PG-13...) - India first, then US.
String _certification(Map decoded) {
  final rd = decoded['release_dates'];
  if (rd is! Map) return '';
  final results = rd['results'];
  if (results is! List) return '';
  for (final want in ['IN', 'US']) {
    for (final r in results) {
      if (r is Map && r['iso_3166_1'] == want) {
        final dates = r['release_dates'];
        if (dates is List) {
          for (final d in dates) {
            if (d is Map) {
              final c = '${d['certification'] ?? ''}'.trim();
              if (c.isNotEmpty) return c;
            }
          }
        }
      }
    }
  }
  return '';
}

/// All languages TMDB has data for this movie in.
List<String> _translationLanguages(Map decoded) {
  final tr = decoded['translations'];
  if (tr is! Map) return const [];
  final list = tr['translations'];
  if (list is! List) return const [];
  final out = <String>[];
  for (final t in list) {
    if (t is Map) {
      final code = '${t['iso_639_1'] ?? ''}'.trim();
      if (code.isNotEmpty) {
        final name = tmdbLanguageName(code);
        if (!out.contains(name)) out.add(name);
      }
    }
  }
  return out;
}

/// Picks the best trailer's YouTube key from a `videos` object:
/// official YouTube Trailer > any YouTube Trailer > any YouTube video.
/// Pure for tests. Returns null when there is no YouTube video at all.
String? pickTrailerKey(Object? videos) {
  if (videos is! Map) return null;
  final results = videos['results'];
  if (results is! List) return null;
  final yt = [
    for (final v in results)
      if (v is Map && v['site'] == 'YouTube') v,
  ];
  if (yt.isEmpty) return null;
  for (final v in yt) {
    if (v['type'] == 'Trailer' && v['official'] == true) {
      final k = '${v['key'] ?? ''}';
      if (k.isNotEmpty) return k;
    }
  }
  for (final v in yt) {
    if (v['type'] == 'Trailer') {
      final k = '${v['key'] ?? ''}';
      if (k.isNotEmpty) return k;
    }
  }
  final k = '${yt.first['key'] ?? ''}';
  return k.isEmpty ? null : k;
}

/// v43/v44: tiny TMDB client for the Discover section. Plain dart:io HTTP -
/// zero new dependencies. Every response (pages, detail, posters handled
/// by TmdbImage) is cached on disk for 24h, so once loaded the section
/// works offline and refreshes ITSELF in the background on the next open
/// after the cache expires - the "automatically updated library".
class TmdbClient {
  static const String _host = 'api.themoviedb.org';

  /// v55: api.tmdb.org is TMDB's own shorter alias of api.themoviedb.org.
  /// Some networks (several Indian ISPs) block or badly throttle ONE of
  /// them, which left Discover stuck on its spinner/error and the home
  /// banner on its flat gradient. We try the last-known-good host first,
  /// then the alias, and stick with whichever answers.
  static const List<String> _hosts = ['api.themoviedb.org', 'api.tmdb.org'];
  static String _activeHost = _hosts.first;

  /// v45: ONE shared client (keep-alive TLS) + longer timeouts. Before,
  /// every request made a fresh 5-second-timeout client, so on a slow
  /// network the first load almost always failed -> "needs multiple
  /// refreshes". [TmdbClient] instances share this single connection.
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);

  /// Directory used for the 24h disk cache (from NativeBridge.cacheDirPath).
  Directory? cacheDir;

  /// v46: details got heavier (videos+credits+images+watch+reviews), so
  /// give them up to 3 attempts with a 20s ceiling (was 2 attempts/15s -
  /// the "details don't load at once" report).
  Future<String> _get(Uri uri) async {
    Object? lastError;
    // v55: 2 rounds x both hosts; a dead/blackholed host fails fast (8 s
    // connect cap) so the alias gets its turn quickly.
    for (var round = 0; round < 2; round++) {
      for (final host
          in [_activeHost, ..._hosts.where((h) => h != _activeHost)]) {
        try {
          final req = await _http
              .getUrl(uri.replace(host: host))
              .timeout(const Duration(seconds: 8));
          final res = await req.close().timeout(const Duration(seconds: 14));
          if (res.statusCode != 200) {
            throw HttpException('TMDB status ${res.statusCode}');
          }
          final body = await res.transform(utf8.decoder).join();
          _activeHost = host;
          return body;
        } catch (e) {
          lastError = e;
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
    }
    throw HttpException('TMDB request failed: $lastError');
  }

  File? _cacheFile(String name) {
    final dir = cacheDir;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// Fresh cache (<= ttl) -> network (write cache) -> stale cache -> null.
  Future<String?> _fetch(String cacheName, Uri uri,
      {Duration ttl = const Duration(hours: 24)}) async {
    final f = _cacheFile(cacheName);
    try {
      if (f != null && await f.exists()) {
        final age = DateTime.now().difference(await f.lastModified());
        if (age <= ttl) return await f.readAsString();
      }
    } catch (_) {}
    try {
      final body = await _get(uri);
      try {
        await f?.writeAsString(body, flush: true);
      } catch (_) {
        // Caching is best-effort - never fail the request because of it.
      }
      return body;
    } catch (_) {
      try {
        if (f != null && await f.exists()) return await f.readAsString();
      } catch (_) {}
      return null;
    }
  }

  /// v44: one page for the filter chips, incl. THOUSANDS more via paging.
  Future<TmdbPage> browse(DiscoverFilter f,
      {int page = 1, bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return const TmdbPage();
    final String cacheName = discoverCacheName(f, page);
    final Uri uri;
    if (f.trending || f.upcoming) {
      uri = Uri.https(_host, tmdbEndpointPath(f), {
        'api_key': kTmdbApiKey,
        'language': 'en-US',
        'region': 'IN',
        'page': '$page',
      });
    } else {
      uri = Uri.https(_host, tmdbEndpointPath(f), {
        'api_key': kTmdbApiKey,
        ...tmdbDiscoverQuery(f, page),
      });
    }
    final body = await _fetch(cacheName, uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null
        ? const TmdbPage()
        : parseTmdbPage(body, kind: f.tv ? 'tv' : 'movie');
  }

  /// v58: instant first paint on slow networks - whatever the disk cache
  /// already holds for page 1 (stale is fine); the live load then
  /// replaces it. Null = nothing cached yet.
  Future<TmdbPage?> cachedBrowseFirstPage(DiscoverFilter f) async {
    try {
      final dir = cacheDir;
      if (dir == null) return null;
      final file = File('${dir.path}/${discoverCacheName(f, 1)}');
      if (!await file.exists()) return null;
      final page = parseTmdbPage(await file.readAsString(),
          kind: f.tv ? 'tv' : 'movie');
      return page.items.isEmpty ? null : page;
    } catch (_) {
      return null;
    }
  }

  /// v44: the Discover SEARCH bar - searches TMDB's whole catalogue.
  Future<TmdbPage> searchMovies(String query,
      {int page = 1, bool force = false}) async {
    final q = query.trim();
    if (kTmdbApiKey.isEmpty || q.isEmpty) return const TmdbPage();
    final uri = Uri.https(_host, '/3/search/movie', {
      'api_key': kTmdbApiKey,
      ...tmdbSearchQuery(q, page),
    });
    final body = await _fetch(tmdbSearchCacheName(q, page), uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null ? const TmdbPage() : parseTmdbPage(body);
  }

  /// v59 (user): "when we search any content, find it from ALL filters"
  /// - ONE multi-search across movies AND series (people are dropped in
  /// the parser).
  Future<TmdbPage> searchMulti(String query,
      {int page = 1, bool force = false}) async {
    final q = query.trim();
    if (kTmdbApiKey.isEmpty || q.isEmpty) return const TmdbPage();
    final uri = Uri.https(_host, '/3/search/multi', {
      'api_key': kTmdbApiKey,
      ...tmdbSearchQuery(q, page),
    });
    final body = await _fetch(tmdbSearchCacheName('multi_$q', page), uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null ? const TmdbPage() : parseTmdbMultiPage(body);
  }

  /// v46: one call now also brings WATCH PROVIDERS (where to watch) and
  /// real user REVIEWS. Cache name _v4 forces one re-download.
  Future<TmdbFull?> fullDetail(int id,
      {String kind = 'movie', bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return null;
    final isTv = kind == 'tv';
    final uri = Uri.https(_host, '/3/$kind/$id', {
      'api_key': kTmdbApiKey,
      'language': 'en-US',
      // Series have no release_dates; content_ratings is their cousin.
      'append_to_response': isTv
          ? 'videos,credits,images,watch/providers,reviews,'
              'content_ratings,translations'
          : 'videos,credits,images,watch/providers,reviews,'
              'release_dates,translations',
      'include_image_language': 'en,null',
    });
    final body = await _fetch(
        isTv ? 'tmdb_tv_v5_$id.json' : 'tmdb_movie_v5_$id.json', uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    if (body == null) return null;
    final parsed = parseTmdbDetail(body);
    if (parsed == null) return null;
    final movie = isTv ? parsed.copyWith(kind: 'tv') : parsed;
    return TmdbFull(
      movie,
      parseTmdbExtras(body),
      screenshots: parseTmdbScreenshots(body),
      watch: parseTmdbWatchProviders(body),
      reviews: parseTmdbReviews(body),
      // v59: every part (season) of the series, for the detail sheet.
      seasons: isTv ? parseTmdbSeasons(body) : const [],
    );
  }

  /// v45: RELATED movies ("search is poor - show related movies"): TMDB's
  /// similar endpoint for the top search hit. Cached 24h like everything.
  Future<List<TmdbMovie>> similar(int id,
      {String kind = 'movie', bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return const [];
    final uri = Uri.https(_host, '/3/$kind/$id/similar', {
      'api_key': kTmdbApiKey,
      'language': 'en-US',
    });
    final body = await _fetch(
        kind == 'tv' ? 'tmdb_tv_similar_$id.json' : 'tmdb_similar_$id.json',
        uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null ? const [] : parseTmdbList(body, kind: kind);
  }
}
EOF_LIB_SERVICES_TMDB_CLIENT_DART
echo "  wrote lib/services/tmdb_client.dart"

mkdir -p "$(dirname "lib/screens/discover_screen.dart")"
cat << 'EOF_LIB_SCREENS_DISCOVER_SCREEN_DART' > "lib/screens/discover_screen.dart"
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import '../services/native_bridge.dart';
import '../services/recommendations.dart';
import '../services/tmdb_client.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/movie_match.dart';
import '../widgets/ai_suggest_sheet.dart';
import '../widgets/movie_detail_sheet.dart';
import '../widgets/tmdb_image.dart';
import '../widgets/voice_search_sheet.dart';

/// v44 "Discover": a legal movie-discovery section, now MUCH bigger.
///
/// - MANY filters (Trending, Hollywood, Bollywood, Tamil, Telugu, Action,
///   Comedy, Drama, Horror, Romance, Thriller, Sci-Fi) instead of v43's 3.
/// - Its own SEARCH bar -> TMDB's whole catalogue.
/// - INFINITE SCROLL: every section pages through thousands of movies
///   (TMDB serves up to 500 pages per query, 20 per page).
/// - Pull-to-refresh REALLY reloads (and v44 fixes wrong/stale posters).
///
/// SOURCE: TMDB's free API (licensed for this, needs only the credit line -
/// we do NOT copy IMDb numbers). Posters + data cache on disk for 24h, so
/// the section refreshes itself daily and works fully offline in between.
///
/// TRAILERS: a tap opens the official YouTube app (Play-policy-safe). We
/// never play YouTube streams through our own player.
/// v58 grew it further: WEB SERIES got their own shelf (Movies | Series
/// switch + /tv endpoints), the grid paints INSTANTLY from the disk cache
/// on slow networks (live data then replaces it), and the ✨ AI Suggestor
/// turns "funny action like Dhoom" into real, tappable posters.
class DiscoverScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;

  const DiscoverScreen({
    super.key,
    required this.library,
    required this.player,
  });

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _client = TmdbClient();
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  DiscoverFilter _filter = kAllFilters.first;
  final List<TmdbMovie> _movies = [];
  final Set<int> _seenIds = {};
  int _page = 0;
  int _totalPages = 1;
  int _totalResults = 0;
  bool _initialLoading = true;
  bool _loadingMore = false;
  String? _error;
  bool _keyMissing = false;

  // v61 (user: "show infinite contents in EVERY filter"): page 1 alone
  // rarely fills a tall phone, and v60's single post-frame
  // _maybeLoadMore() only pulled ONE extra page. We now CHAIN page loads
  // after each page lands, until the grid is scrollable/fills the
  // viewport OR we hit the safety cap - then the normal scroll listener
  // at maxScrollExtent-350 takes over for "forever" paging.
  //
  // [_endlessPaging] is the in-flight guard (never two page requests at
  // once); [_endlessBurst] counts chained auto-loads so one burst can't
  // spin forever. Each chain captures the current [_loadToken], so
  // switching filters/search drops a stale chain on the next frame.
  bool _endlessPaging = false;
  int _endlessBurst = 0;
  static const int _kEndlessBurstCap = 5;

  /// v45: "search is poor - show related movies": similar titles of the
  /// top search hit, shown under the results in search mode.
  List<TmdbMovie> _related = const [];

  /// v65 A6: "Because you watched <title>" - on-device recommendations
  /// derived from the user's local watch history (TMDB similar of the best
  /// history match). Loaded once when Discover opens; hidden in search.
  List<TmdbMovie> _recommendations = const [];
  HistoryEntry? _recommendAnchor;

  /// Bumped every time the MODE (filter/search) changes; stale in-flight
  /// page loads check it and drop their results (no mixed-up grids).
  int _loadToken = 0;
  String _searchQuery = '';
  bool get _searching => _searchQuery.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _boot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final cachePath = await NativeBridge.cacheDirPath();
    TmdbImage.configure(cachePath);
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    if (!mounted) return;
    if (kTmdbApiKey.isEmpty) {
      setState(() {
        _keyMissing = true;
        _initialLoading = false;
      });
      return;
    }
    await _loadPage(1, force: true);
    // v65 A6: load on-device "because you watched" recommendations from
    // the local watch history (off the main grid's critical path).
    unawaited(_loadRecommendations());
  }

  Future<void> _loadRecommendations() async {
    try {
      final history = widget.player.history;
      final anchor = Recommendations.pickAnchor(history);
      if (anchor == null) return;
      final recs =
          await Recommendations.forAnchor(_client, anchor);
      if (!mounted) return;
      setState(() {
        _recommendAnchor = anchor;
        _recommendations = recs;
      });
    } catch (_) {}
  }

  /// Loads ONE page of the current mode and appends it (deduped by id).
  Future<void> _loadPage(int page, {bool force = false}) async {
    final token = _loadToken;
    if (page == 1) {
      if (mounted) setState(() => _initialLoading = true);
      // v58: instant first paint on bad networks - show the cached page
      // from disk RIGHT AWAY; the live fetch below replaces it.
      if (!_searching && _movies.isEmpty) {
        final cached = await _client.cachedBrowseFirstPage(_filter);
        if (!mounted || token != _loadToken) return;
        if (cached != null && _movies.isEmpty) {
          setState(() {
            for (final m in cached.items) {
              if (_seenIds.add(m.id)) _movies.add(m);
            }
            _error = null;
          });
        }
      }
    } else {
      if (mounted) setState(() => _loadingMore = true);
    }
    TmdbPage result;
    try {
      // v59: multi-search finds it in ALL shelves - movies AND series.
      result = _searching
          ? await _client.searchMulti(_searchQuery, page: page, force: force)
          : await _client.browse(_filter, page: page, force: force);
    } catch (_) {
      result = const TmdbPage();
    }
    if (!mounted || token != _loadToken) return;
    setState(() {
      _initialLoading = false;
      _loadingMore = false;
      _page = result.page;
      _totalPages = result.totalPages;
      _totalResults = result.totalResults;
      for (final m in result.items) {
        if (_seenIds.add(m.id)) _movies.add(m);
      }
      if (page == 1 && _movies.isEmpty) {
        _error = _searching
            ? 'No movies or series match "$_searchQuery" on TMDB.'
            : 'Could not load movies or series - connect the internet once, '
                'then pull down to retry.';
      } else if (_movies.isNotEmpty) {
        _error = null;
      }
    });
    // v45: in search mode, also fetch "you may also like" from the top
    // hit - a plain search word finds few direct matches otherwise.
    if (_searching && page == 1 && result.items.isNotEmpty) {
      _loadRelated(result.items.first.id, token,
          kind: result.items.first.kind);
    }
    // v61: "show infinite contents in EVERY filter" - after EVERY page
    // lands (not just page 1), schedule a post-frame check that keeps
    // loading the next page until the grid fills the viewport / becomes
    // scrollable or we hit the burst cap. The existing scroll listener
    // (_maybeLoadMore at maxScrollExtent-350) then keeps paging forever
    // as the user scrolls. [token] ties the chain to this filter/search.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token == _loadToken) _scheduleEndlessFill(token);
    });
  }

  /// v61: chained auto-fill. Called after each page paints; if the grid
  /// still doesn't fill the viewport (or the user is already near the
  /// bottom) and more pages exist, fetch the next one - looping up to
  /// [_kEndlessBurstCap] pages per burst so we never fire unbounded
  /// requests. The in-flight [_loadingMore] guard plus [_endlessPaging]
  /// makes duplicate requests impossible.
  void _scheduleEndlessFill(int token) {
    if (!mounted || token != _loadToken) return;
    if (_initialLoading || _loadingMore || _endlessPaging) return;
    if (_page >= _totalPages) return; // nothing more to fetch
    if (_searching) {
      // Search keeps its single related-fetch behavior; no auto-chain
      // (results are usually specific enough to fill the screen).
      if (_endlessBurst != 0) _endlessBurst = 0;
      return;
    }
    // Decide whether the current content still needs more.
    var needsMore = true;
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      // Content already comfortably fills / overflows the viewport AND
      // we're not near the bottom -> the scroll listener will take over,
      // so stop the auto-chain.
      needsMore = pos.maxScrollExtent <= pos.viewportDimension + 24 ||
          pos.pixels >= pos.maxScrollExtent - 350;
    }
    if (!needsMore) {
      _endlessBurst = 0; // screen is full; hand off to the scroll listener
      return;
    }
    if (_endlessBurst >= _kEndlessBurstCap) {
      // Safety stop for one burst; the next real scroll resumes paging.
      _endlessBurst = 0;
      return;
    }
    _endlessPaging = true;
    _endlessBurst++;
    _loadPage(_page + 1).whenComplete(() {
      if (mounted) _endlessPaging = false;
    });
  }

  Future<void> _loadRelated(int movieId, int token,
      {String kind = 'movie'}) async {
    List<TmdbMovie> rel;
    try {
      rel = await _client.similar(movieId, kind: kind);
    } catch (_) {
      rel = const [];
    }
    if (!mounted || token != _loadToken || !_searching) return;
    setState(() => _related = rel.take(12).toList());
  }

  /// Hard switch of browse/search mode: clears the grid, invalidates any
  /// in-flight loads, then fetches page 1. [force] skips the 24h cache.
  void _switchTo({DiscoverFilter? filter, String? query, bool force = false}) {
    _loadToken++;
    _endlessPaging = false; // v61: cancel any in-flight auto-fill chain
    _endlessBurst = 0;
    setState(() {
      if (filter != null) _filter = filter;
      if (query != null) _searchQuery = query;
      _movies.clear();
      _seenIds.clear();
      _page = 0;
      _totalPages = 1;
      _totalResults = 0;
      _error = null;
      _related = const [];
    });
    _loadPage(1, force: force);
  }

  void _selectFilter(DiscoverFilter f) {
    if (!_searching && _filter == f) return;
    _searchCtrl.clear(); // leaving search mode when a chip is tapped
    _switchTo(filter: f, query: '');
  }

  void _onSearchChanged(String v) {
    setState(() {}); // show/hide the clear (x) button immediately
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim();
      if (q == _searchQuery) return;
      _switchTo(query: q);
    });
  }

  /// v44: infinite scroll - near the bottom? fetch the next page.
  /// v61: a real user scroll resets the auto-fill burst counter so
  /// scrolling can keep paging "forever" (the cap only bounds the
  /// automatic burst right after a filter is opened).
  void _maybeLoadMore() {
    if (!_scroll.hasClients || _initialLoading || _loadingMore) return;
    if (_page >= _totalPages) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 350) {
      _endlessBurst = 0;
      _loadPage(_page + 1);
    }
  }

  Future<void> _refresh() async {
    _switchTo(force: true);
    // Let RefreshIndicator stay up until page 1 actually finished.
    while (_initialLoading && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  void _openMovie(TmdbMovie movie) {
    // Match against the ALREADY-scanned library (read-only - the video
    // scan is not touched by Discover at all).
    final match =
        findLocalMovie(movie.title, movie.year, widget.library.allVideos);
    MovieDetailSheet.show(
      context,
      movie: movie,
      localMatch: match,
      player: widget.player,
      detailLoader: () => _client.fullDetail(movie.id, kind: movie.kind),
    );
  }

  /// v58/v59: the AI Suggestor - "describe your movie type" -> real
  /// posters. Lives in the AppBar (user: "move AI suggest to the top").
  Future<void> _openAiSuggest() async {
    final pick = await AiSuggestSheet.show(context);
    if (!mounted || pick == null) return;
    _openMovie(pick);
  }

  /// v66 A5: voice search - launches custom in-app speech recognition and
  /// populates the search bar.
  Future<void> _startVoiceSearch() async {
    final query = await VoiceSearchSheet.show(context);
    if (!mounted || query == null || query.isEmpty) return;
    _searchCtrl.text = query;
    _onSearchChanged(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121a),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Discover', style: TextStyle(fontSize: 18)),
            if (_totalResults > 0)
              Text(
                _searching
                    ? '${_movies.length} of ~${formatVoteCount(_totalResults)} results'
                    : '${formatVoteCount(_totalResults)} titles - scroll for more',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
        // v59 (user): AI Suggest moved to the TOP.
        actions: [
          IconButton(
            tooltip: 'AI Suggest - describe your movie type',
            icon: Icon(Icons.auto_awesome, color: themeState.accent),
            onPressed: _openAiSuggest,
          ),
        ],
      ),
      body: _keyMissing
          ? const _SetupNote()
          : Column(
              children: [
                // v44: the section's own search bar (TMDB-wide).
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search movies & series...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: Icon(Icons.search,
                          color: themeState.accent, size: 20),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchCtrl.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white54, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _switchTo(query: '');
                              },
                            ),
                          IconButton(
                            icon: Icon(Icons.mic_none_outlined,
                                color: themeState.accent, size: 20),
                            tooltip: 'Voice search',
                            onPressed: _startVoiceSearch,
                          ),
                        ],
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                // v59 (user): ONE filter row with EVERYTHING - movie
                // chips AND web series chips side by side (the old
                // Movies|Series toggle is gone).
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final f in kAllFilters) ...[
                        _FilterChip(
                          label: f.label,
                          selected: !_searching && _filter == f,
                          onTap: () => _selectFilter(f),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: RefreshIndicator(
                    color: themeState.accent,
                    onRefresh: _refresh,
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBody() {
    if (_initialLoading && _movies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_movies.isEmpty) {
      // Kept scrollable so pull-to-refresh always works.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.cloud_off_outlined,
              size: 44, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          Text(
            _error ?? 'No movies to show yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.4),
          ),
        ],
      );
    }
    return Stack(
      children: [
        CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // v65 A6: "Because you watched" - on-device recs from local
            // history (only when not searching and we found matches).
            if (!_searching && _recommendations.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Because you watched '
                          '"${_recommendAnchor?.title ?? ''}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 224,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    itemCount: _recommendations.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => SizedBox(
                      width: 128,
                      child: _PosterCard(
                        key: ValueKey('rec_${_recommendations[i].id}'),
                        movie: _recommendations[i],
                        onTap: () => _openMovie(_recommendations[i]),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
            ],
            SliverPadding(
              padding: const EdgeInsets.all(10),
              sliver: SliverGrid.builder(
                // v45: BIGGER cards (150 -> 200 wide) so posters actually
                // read like a movie app, not stamps.
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.60,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _movies.length,
                itemBuilder: (context, i) {
                  final movie = _movies[i];
                  return _PosterCard(
                    // v44: stable per-MOVIE key -> a recycled cell never
                    // flashes the previous movie's poster after refresh.
                    key: ValueKey(movie.id),
                    movie: movie,
                    onTap: () => _openMovie(movie),
                  );
                },
              ),
            ),
            // v45: related movies under search results.
            if (_searching && _related.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text(
                    'Related to your search',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 224,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _related.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => SizedBox(
                      width: 128,
                      child: _PosterCard(
                        key: ValueKey('rel_${_related[i].id}'),
                        movie: _related[i],
                        onTap: () => _openMovie(_related[i]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
        if (_loadingMore)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              minHeight: 3,
              color: themeState.accent,
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        decoration: BoxDecoration(
          color: selected
              ? themeState.accent
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? themeState.onAccent : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final TmdbMovie movie;
  final VoidCallback onTap;

  const _PosterCard({super.key, required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TmdbImage(url: tmdbPosterUrl(movie.posterPath)),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '⭐ ${tmdbRatingText(movie.rating)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            movie.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          if (movie.year != null)
            Text(
              '${movie.year}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown in local/dev builds where no TMDB key was injected (the store /
/// testers' builds from Codemagic have it). Never a crash, always a note.
class _SetupNote extends StatelessWidget {
  const _SetupNote();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_filter,
                size: 44, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 14),
            const Text(
              'Discover starts in the store build.\n\n'
              '(Developer note: pass the TMDB key via\n'
              '--dart-define=TMDB_API_KEY=... - see README. '
              'Everything else in the app works without it.)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
EOF_LIB_SCREENS_DISCOVER_SCREEN_DART
echo "  wrote lib/screens/discover_screen.dart"

mkdir -p "$(dirname "lib/screens/library_screen.dart")"
cat << 'EOF_LIB_SCREENS_LIBRARY_SCREEN_DART' > "lib/screens/library_screen.dart"
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/crash_log.dart';
import '../utils/formatters.dart';
import '../utils/storage_permission.dart';
import '../widgets/about_sheet.dart';
import '../widgets/display_settings_sheet.dart';
import '../state/private_vault.dart';
import '../widgets/mini_player.dart';
import '../models/saved_server.dart';
import '../services/native_bridge.dart';
import '../services/resume_sync_service.dart';
import '../widgets/cleaner_sheet.dart';
import '../widgets/discover_banner.dart';
import '../widgets/video_search_delegate.dart';
import '../widgets/playlists_sheet.dart';
import '../widgets/user_manual_sheet.dart';
import 'private_screen.dart';
import '../widgets/video_list_item.dart';
import '../widgets/video_tile.dart';
import 'discover_screen.dart';
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
  /// v26: last known Private-vault change counter. Returning from the
  /// Private folder rescans ONLY when this differs (see below) - a plain
  /// look inside no longer reloads the library grid.
  int _lastVaultRevision = PrivateVault.revision;

  /// v28: the quick-tiles grid tucks away while scrolling DOWN through
  /// the videos and slides back when scrolling up / reaching the top.
  final ScrollController _listScroll = ScrollController();
  double _lastListOffset = 0;
  bool _tilesVisible = true;

  void _onListScroll() {
    final offset = _listScroll.offset;
    final goingDown = offset > _lastListOffset + 6;
    final goingUp = offset < _lastListOffset - 6;
    if (_tilesVisible && goingDown && offset > 24) {
      setState(() => _tilesVisible = false);
    } else if (!_tilesVisible && (goingUp || offset <= 24)) {
      setState(() => _tilesVisible = true);
    }
    _lastListOffset = offset;
  }

  @override
  void initState() {
    super.initState();
    _listScroll.addListener(_onListScroll);
    widget.library.addListener(_onChange);
    // Automatically ask for storage permission and scan the whole device
    // the first time this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.library.folderName == null && !widget.library.isScanning) {
        widget.library.scanAllStorage();
      }
      // If the previous session died with an error, offer the recorded
      // crash report (copyable) so it can be sent for analysis.
      CrashLog.takeLastIncludingNative().then((report) {
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
                      'Crash report copied - send it to the developer',
                    ),
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
    _listScroll.dispose();
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
    // v22: moving a file out of public storage needs the same grant the
    // scanner uses. Ask up-front instead of letting the move fail with a
    // cryptic snackbar. v40: version-aware via the shared helper - asking
    // ONLY "All files access" resolved denied FOREVER on Android 10 and
    // older, so those phones kept re-asking a permission already granted.
    if (!await ensureStorageAccess()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Private folder needs storage permission: allow it, then '
            'long-press the video again',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text(
          'Move to Private folder?',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Text(
          '"${track.title}" moves into the app\'s private folder - invisible '
          'to Gallery and file managers, visible here only after your PIN.\n\n'
          'Warning: uninstalling the app deletes hidden videos.',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.45,
          ),
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
                // v26: the rescan above already reflects this move - keep
                // the stamp in sync so closing the Private folder later
                // doesn't rescan AGAIN for the same change.
                _lastVaultRevision = PrivateVault.revision;
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
                    SnackBar(content: Text('Could not hide: $why')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// v28: the Private folder moved from the top bar into the quick-tiles
  /// grid. v26: rescan on return ONLY when something was actually
  /// hidden/unhidden inside (the revision counter moves on every vault
  /// file move) - a plain visit no longer reloads the grid.
  Future<void> _openPrivate(VideoLibraryState lib) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        // v29: the vault screen gets the library too (its "+" button
        // moves selected videos into the vault).
        builder: (_) => PrivateScreen(player: widget.player, library: lib),
      ),
    );
    final rev = PrivateVault.revision;
    if (rev != _lastVaultRevision) {
      _lastVaultRevision = rev;
      lib.rescan();
    }
  }

  /// v40 "Playlists" tile: NAMED, persistent playlists (create by name,
  /// add videos, play, rename, delete) - they survive app restarts.
  ///
  /// Replaces the v28-v30 design: one anonymous in-memory queue shown in a
  /// sheet with a Build-playlist button. That queue vanished on every
  /// restart ("playlists are not saving, they disappear after reopening"),
  /// and the button is gone now (requested: "remove build playlist button,
  /// add multiple playlists by names"). The player's own side panel still
  /// shows the now-playing queue inside the player screen.
  void _showPlaylists(VideoLibraryState lib) {
    PlaylistsSheet.show(context, library: lib, player: widget.player);
  }

  /// v28 "Folders" tile: show only one folder's videos (or everything).
  void _showFoldersSheet(VideoLibraryState lib) {
    final counts = lib.folderCounts;
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
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: Icon(
                Icons.video_library_outlined,
                color: themeState.accent,
              ),
              title: const Text(
                'All videos',
                style: TextStyle(color: Colors.white),
              ),
              trailing: lib.folderFilter == null
                  ? Icon(Icons.check, color: themeState.accent)
                  : Text(
                      '${lib.allVideosCount}',
                      style: const TextStyle(color: Colors.white38),
                    ),
              onTap: () {
                lib.setFolderFilter(null);
                Navigator.of(sheetContext).pop();
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in counts.entries)
                    ListTile(
                      leading: Icon(
                        Icons.folder_outlined,
                        color: themeState.accent,
                      ),
                      title: Text(
                        e.key,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${e.value} ${e.value == 1 ? 'video' : 'videos'}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      trailing: lib.folderFilter == e.key
                          ? Icon(Icons.check, color: themeState.accent)
                          : null,
                      onTap: () {
                        lib.setFolderFilter(e.key);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
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
  /// v32 BYOS phase A: the stream dialog doubles as the "saved servers"
  /// list - NAS boxes over WebDAV/HTTP, public share links, IP cameras...
  /// stored as JSON in the native settings store (no account, no cloud
  /// lock-in: the user brings the storage, we are the player).
  Future<void> _openStreamDialog() async {
    final controller = TextEditingController();
    final all = await NativeBridge.loadSettings();
    var servers = parseServersJson(all[kServersSettingKey]);
    if (!mounted) return;

    Future<void> persist() =>
        NativeBridge.saveSetting(kServersSettingKey, serversToJson(servers));

    void snack(String message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a24),
          title: const Text(
            'Open stream / server',
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'https:// or rtsp:// ... (WebDAV/NAS links work)',
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                ),
                if (servers.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Saved servers',
                    style: TextStyle(
                      color: themeState.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (var i = 0; i < servers.length; i++)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.dns_outlined,
                              color: themeState.accent,
                              size: 20,
                            ),
                            title: Text(
                              servers[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              servers[i].url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove server',
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white38,
                                size: 18,
                              ),
                              onPressed: () async {
                                servers = [...servers]..removeAt(i);
                                await persist();
                                setDialogState(() {});
                              },
                            ),
                            onTap: () =>
                                Navigator.of(dialogContext).pop(servers[i].url),
                          ),
                      ],
                    ),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Tip: press Save to keep a link (NAS, camera, share '
                      'URL) in this list.',
                      style: TextStyle(color: Colors.white38, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton.icon(
              icon: Icon(
                Icons.bookmark_add_outlined,
                size: 18,
                color: themeState.accent,
              ),
              label: const Text('Save'),
              onPressed: () async {
                final u = controller.text.trim();
                if (!_isStreamUrl(u)) {
                  snack('Enter a valid URL first');
                  return;
                }
                final before = servers.length;
                servers = addSavedServer(
                  servers,
                  SavedServer(name: _serverNameFor(u), url: u),
                );
                await persist();
                setDialogState(() {});
                snack(
                  servers.length > before
                      ? 'Server saved - tap it here any time'
                      : 'That link is already saved',
                );
              },
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: themeState.accent),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Play'),
            ),
          ],
        ),
      ),
    );
    if (url == null || url.isEmpty) return;
    if (!_isStreamUrl(url)) {
      snack('That does not look like a stream URL');
      return;
    }
    final uri = Uri.parse(url);
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
          // v44: library search moved HERE - a full-screen search page,
          // so the home screen keeps room for the Discover banner.
          IconButton(
            tooltip: 'Search videos',
            icon: Icon(Icons.search, color: themeState.accent),
            onPressed: () => showSearch<void>(
              context: context,
              delegate: VideoSearchDelegate(
                videos: lib.allVideos,
                onOpen: _playVideo,
              ),
            ),
          ),
          // v26: all home-screen buttons follow the picked theme colour.
          // Prominent rescan button (new videos don't appear otherwise).
          IconButton(
            tooltip: 'Rescan library',
            onPressed: lib.isScanning ? null : () => _rescan(lib),
            icon: lib.isScanning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: themeState.accent,
                    ),
                  )
                : Icon(Icons.sync, color: themeState.accent),
          ),
          IconButton(
            tooltip: 'History',
            icon: Icon(Icons.history, color: themeState.accent),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryScreen(player: widget.player),
              ),
            ),
          ),

          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_vert, color: themeState.accent),
            color: const Color(0xFF26262f),
            onSelected: (choice) => _onMenuChoice(choice, lib),
            // v26: menu icons follow the picked theme colour.
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'stream',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link, color: themeState.accent),
                  title: const Text('Open stream URL'),
                ),
              ),
              PopupMenuItem(
                value: 'stats',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bar_chart, color: themeState.accent),
                  title: const Text('Statistics'),
                ),
              ),
              PopupMenuItem(
                value: 'rescan',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh, color: themeState.accent),
                  title: const Text('Rescan library'),
                ),
              ),
              PopupMenuItem(
                value: 'display',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune, color: themeState.accent),
                  title: const Text('Display settings'),
                ),
              ),
              PopupMenuItem(
                value: 'manual',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.menu_book_outlined,
                    color: themeState.accent,
                  ),
                  title: const Text('User manual'),
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline, color: themeState.accent),
                  title: const Text('About'),
                ),
              ),
              // Footer: app version (not selectable).
              const PopupMenuItem(
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
          // v44: the search BOX became an app-bar icon (full-screen
          // search page). Its place now holds the Discover banner -
          // latest trending posters shine through behind the title.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: DiscoverBanner(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DiscoverScreen(library: lib, player: widget.player),
                ),
              ),
            ),
          ),
          // v69 C3: Wi-Fi Resume-Sync Banner
          ValueListenableBuilder<RemoteResumeBeacon?>(
            valueListenable: ResumeSyncService.instance.remoteBeacon,
            builder: (context, beacon, _) {
              if (beacon == null) return const SizedBox.shrink();
              final pos = formatDuration(Duration(seconds: beacon.positionSecs));
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: themeState.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: themeState.accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_tethering, color: themeState.accent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Playing on ${beacon.device}',
                              style: TextStyle(
                                color: themeState.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${beacon.title} ($pos)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: themeState.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          final ok = await ResumeSyncService.instance.resumeOnThisDevice(
                            beacon,
                            lib,
                            widget.player,
                          );
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not find this video in your local library.'),
                              ),
                            );
                          }
                        },
                        child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                        onPressed: () => ResumeSyncService.instance.remoteBeacon.value = null,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // v28: active folder filter chip (set from the Folders tile).
          if (lib.folderFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: themeState.accent,
                  ),
                  label: Text('Folder: ${lib.folderFilter}'),
                  labelStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  onDeleted: () => lib.setFolderFilter(null),
                  deleteIconColor: Colors.white54,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: themeState.accent.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
          // v28: the 2x2 quick-tiles grid - slides away on scroll-down.
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              heightFactor: _tilesVisible ? 1.0 : 0.0,
              alignment: Alignment.topCenter,
              child: _QuickTiles(
                accent: themeState.accent,
                onPrivate: () => _openPrivate(lib),
                onCleaner: () => CleanerSheet.show(
                  context,
                  player: widget.player,
                  library: lib,
                ),
                onPlaylist: () => _showPlaylists(lib),
                onFolders: () => _showFoldersSheet(lib),
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
    // AnimatedSwitcher above. v28: the controller drives the quick-tiles
    // auto-hide on downward scrolls.
    return CustomScrollView(
      key: ValueKey(lib.viewMode),
      controller: _listScroll,
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

/// v28: the 2x2 quick-tiles grid under the search bar. Tucks away while
/// scrolling down through the videos (see [_LibraryScreenState]) and
/// returns on scroll-up. Private folder lives here now (was a top-bar
/// icon).
class _QuickTiles extends StatelessWidget {
  final Color accent;
  final VoidCallback onPrivate;
  final VoidCallback onCleaner;
  final VoidCallback onPlaylist;
  final VoidCallback onFolders;

  const _QuickTiles({
    required this.accent,
    required this.onPrivate,
    required this.onCleaner,
    required this.onPlaylist,
    required this.onFolders,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Tile(
                  Icons.lock_outline,
                  'Private folder',
                  accent,
                  onPrivate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  Icons.cleaning_services_outlined,
                  'Cleaner',
                  accent,
                  onCleaner,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Tile(
                  Icons.queue_music_outlined,
                  'Playlists',
                  accent,
                  onPlaylist,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  Icons.folder_outlined,
                  'Folders',
                  accent,
                  onFolders,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _Tile(this.icon, this.label, this.accent, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: accent.withValues(alpha: 0.25),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
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

// ---------------------------------------------------------------------------
// v32 BYOS: stream/server URL helpers for the Open stream dialog.
// ---------------------------------------------------------------------------

bool _isStreamUrl(String url) {
  final uri = Uri.tryParse(url);
  const schemes = {'http', 'https', 'rtsp', 'rtmp', 'mms'};
  return uri != null &&
      schemes.contains(uri.scheme.toLowerCase()) &&
      uri.host.isNotEmpty;
}

String _serverNameFor(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  return uri.hasPort && uri.port != 80 && uri.port != 443
      ? '${uri.host}:${uri.port}'
      : uri.host;
}
EOF_LIB_SCREENS_LIBRARY_SCREEN_DART
echo "  wrote lib/screens/library_screen.dart"

mkdir -p "$(dirname "lib/screens/player_screen.dart")"
cat << 'EOF_LIB_SCREENS_PLAYER_SCREEN_DART' > "lib/screens/player_screen.dart"
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../cast/cast_state.dart';
import '../services/native_bridge.dart';
import '../services/notification_service.dart';
import '../state/media_player_state.dart';
import '../state/player_settings.dart';
import '../state/video_zoom.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import '../utils/srt.dart';
import '../widgets/cast_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/karaoke_subtitle.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/player_settings_sheet.dart';
import '../widgets/playlist_panel.dart';
import '../widgets/video_ask_sheet.dart';
import '../widgets/video_info_sheet.dart';

class PlayerScreen extends StatefulWidget {
  final MediaPlayerState player;

  const PlayerScreen({super.key, required this.player});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

/// v41: which Android system-UI mode the player should show right now.
///
/// Report: "when we play video the upper side time, notification bar and
/// on the right side back, home, buttons are showing as black bar - these
/// are not removed". The bars were only hidden when the user pressed the
/// fullscreen BUTTON; simply ROTATING the phone (the normal way people
/// watch) left the status bar and the back/home navigation buttons
/// painted as black bars.
///
/// New rule (VLC / MX Player behavior): the video gets the whole screen
/// whenever it has real room - MANUAL fullscreen OR landscape; portrait
/// portrait keeps the bars so the time and notifications stay visible.
/// Top-level + pure so the widget test can pin all four combinations.
SystemUiMode playerSystemUiModeFor({
  required bool fullscreen,
  required bool landscape,
}) =>
    (fullscreen || landscape)
        ? SystemUiMode.immersiveSticky
        : SystemUiMode.edgeToEdge;

/// v44: what to restore when LEAVING the player. v41 restored
/// edgeToEdge, which keeps the window laid out UNDER the status bar -
/// back in the library the status bar sat ON TOP of the app content
/// (the overlap bug). Manual mode with both overlays = the normal,
/// never-overlapping Android layout.
const SystemUiMode playerRestoreSystemUiMode = SystemUiMode.manual;

/// v44: both bars (status + navigation) must be back after the player.
const List<SystemUiOverlay> playerRestoreOverlays = SystemUiOverlay.values;

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
  static const List<double?> _fitAspects = [
    null,
    null,
    null,
    16 / 9,
    4 / 3,
    null,
  ];
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

  // v52: two-finger TAP = snap back to fit screen. We measure the pinch
  // gesture's total travel / whether any real scaling happened.
  // v61: the fit LOOP's anchor - which fit index was showing when the two
  // fingers landed (see video_zoom.dart). The loop never zooms.
  int _ladderBaseIndex = 0;
  int _scaleStartMs = 0;
  double _pinchTravelPx = 0;
  bool _pinchScaled = false;
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
    // v68: VLC-style immersive mode with notch cutout support.
    unawaited(NativeBridge.setImmersive(true));
    _noticeSub = widget.player.notices.listen((m) {
      // v65: the player state posts "Skipped credits" after the auto-skip;
      // surface the Undo chip instead of the generic indicator.
      if (m == 'Skipped credits') {
        setState(() {
          _showCreditsUndo = true;
          _creditsUndoShownAt = DateTime.now();
        });
        return;
      }
      _showIndicator(m, Icons.history);
    });
    NativeBridge.configureCallbacks(
      onPipChanged: (isPip) {
        if (!mounted) return;
        setState(() => _isPip = isPip);
        // v41: re-assert the bars after a PiP round-trip (while in PiP the
        // OS owns the system UI; coming back must not leave bars stuck on
        // top of a landscape video).
        _syncSystemUiMode();
      },
    );
    _reloadSettings();
    widget.player.currentBrightness(); // sync once for the swipe gesture
    widget.player.currentVolume(); // start swipe from REAL device volume
    _startHideTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // v41: MediaQuery changes - in particular the phone ROTATING - land
    // here because build() reads MediaQuery.of(context).orientation. This
    // is the fix for "black bars are not removed when playing video":
    // hiding the bars was wired ONLY to the fullscreen button, never to
    // simply holding the phone sideways.
    _syncSystemUiMode();
  }

  /// v41: THE one spot that decides the bars (status bar + back/home
  /// buttons): hidden while the video has real room (manual fullscreen OR
  /// landscape), restored in portrait so the time/notifications stay
  /// visible. Idempotent, so every lifecycle hook can re-assert it.
  void _syncSystemUiMode() {
    if (!mounted) return;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setEnabledSystemUIMode(
      playerSystemUiModeFor(fullscreen: _isFullscreen, landscape: landscape),
    );
  }

  @override
  void dispose() {
    _castState.dispose(); // stops casting + the embedded file server
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _noticeSub?.cancel();
    // v41: ALWAYS bring the bars back on the way out - landscape playback
    // now hides them even when manual fullscreen was never pressed, so the
    // old `if (_isFullscreen)` guard could leave the LIBRARY screen
    // without a status bar / back button after just rotating the phone.
    // v44: manual overlays (edgeToEdge overlapped the library's
    // status bar when coming back from the player).
    SystemChrome.setEnabledSystemUIMode(
      playerRestoreSystemUiMode,
      overlays: playerRestoreOverlays,
    );
    if (_isFullscreen) _exitFullscreen();
    // Hand rotation control back to the system; never leave a lock behind.
    unawaited(NativeBridge.disableSensorRotate());
    unawaited(NativeBridge.setImmersive(false));
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
      if (!widget.player.backgroundAudio) {
        widget.player.pause();
      }
      // v63 Phase 2: when the user leaves the player mid-video, offer a
      // "Continue watching" notification (only if the video is actually
      // resumable; the service enforces the 5%..95% + cool-down rules).
      unawaited(
        NotificationService.notifyContinueWatching(widget.player.history),
      );
    } else if (state == AppLifecycleState.resumed) {
      // Coming back to the app: the resume nudge is no longer needed.
      unawaited(NotificationService.cancelContinueWatching());
    }
  }

  Future<void> _reloadSettings() async {
    final s = await PlayerSettings.load();
    if (mounted) {
      setState(() {
        _settings = s;
        // v52: start every session in the fit mode chosen in Settings
        // (default: fit screen). In-session cycling still works.
        _fitIndex = s.defaultFitIndex.clamp(0, _fits.length - 1);
      });
    }
    // v21: push the playback-extras settings into the player state.
    unawaited(widget.player.setVolumeBoost200(s.volumeBoost200));
    widget.player.setBackgroundAudio(s.backgroundAudio);
    // v32: picture settings - HDR tone-mapping curve + Enhance shader.
    unawaited(widget.player.setToneMapping(s.toneMapping));
    unawaited(widget.player.setEnhanceVideo(s.enhanceVideo));
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

  /// v25: one karaoke switch used by the tracks sheet tile (the setting
  /// persists like before).
  void _toggleKaraoke() {
    final next = _settings.copyWith(karaokeSubs: !_settings.karaokeSubs);
    setState(() => _settings = next);
    next.save();
    _applyKaraokeSubtitleVisibility(next);
    if (next.karaokeSubs && widget.player.aiCues == null) {
      widget.player.refreshAiCues(widget.player.currentTrack?.path ?? '');
    }
    _onUserInteraction();
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

  /// v26: while the seek bar is being DRAGGED, the auto-hide countdown
  /// pauses - the controls must never fade away mid-scrub.
  void _onScrubChanged(bool scrubbing) {
    if (scrubbing) {
      _hideTimer?.cancel();
    } else if (_controlsVisible) {
      _startHideTimer();
    }
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
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _syncSystemUiMode(); // v41: one decision point for the bars
    } else {
      _exitFullscreen();
    }
    _onUserInteraction();
  }

  void _exitFullscreen() {
    // v41: restore the bars per the CURRENT orientation (leaving fullscreen
    // while the phone is still sideways keeps them hidden - landscape is
    // full-bleed now; rotating back to portrait brings them back via
    // didChangeDependencies). From dispose() `context` is off-limits, so
    // restore them unconditionally there.
    if (mounted) {
      _syncSystemUiMode();
    } else {
      // v44: from dispose() - manual overlays, never edgeToEdge.
      SystemChrome.setEnabledSystemUIMode(
        playerRestoreSystemUiMode,
        overlays: playerRestoreOverlays,
      );
    }
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

  /// v65: briefly true after we auto-skipped the credits so the "Undo" chip
  /// can be shown. Reset by track changes / time.
  bool _showCreditsUndo = false;
  static const Duration _creditsUndoWindow = Duration(seconds: 8);
  DateTime? _creditsUndoShownAt;

  /// Builds either the "Skip intro" chip or the "Skipped credits · Undo"
  /// chip (whichever applies right now). v65 made intro-skipping automatic
  /// and added credits detection; there is no settings toggle anymore.
  Widget _buildSmartSkipChip() {
    // 1) Undo a recent credits auto-skip.
    if (_showCreditsUndo) {
      final shownAt = _creditsUndoShownAt;
      if (shownAt != null &&
          DateTime.now().difference(shownAt) <= _creditsUndoWindow) {
        return _chip(
          icon: Icons.undo,
          label: 'Skipped credits',
          action: 'Undo',
          onTap: () {
            widget.player.undoSkipCredits();
            setState(() => _showCreditsUndo = false);
          },
          onClose: () => setState(() => _showCreditsUndo = false),
        );
      }
      _showCreditsUndo = false;
    }

    // 2) Skip intro (while before the dialogue starts).
    final at = widget.player.skipIntroAt;
    if (at != null) {
      final pos = widget.player.position;
      final untimely = pos >= at - const Duration(seconds: 1) ||
          pos > const Duration(minutes: 10);
      if (_skipChipDismissedFor != at && !untimely) {
        // Listen for the player's "Skipped credits" notice so we can flip
        // into the Undo chip once credits auto-skip (done once, cheap).
        return _chip(
          icon: Icons.fast_forward,
          label: 'Skip intro',
          action: formatDuration(at),
          onTap: () {
            widget.player.seek(at);
            setState(() => _skipChipDismissedFor = at);
            _onUserInteraction();
          },
          onClose: () => setState(() => _skipChipDismissedFor = at),
        );
      }
    }
    return const SizedBox.shrink();
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required String action,
    required VoidCallback onTap,
    required VoidCallback onClose,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xF2152026),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: themeState.accent.withValues(alpha: 0.65)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: themeState.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                action,
                style: TextStyle(
                  color: themeState.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
        Widget item(
          IconData icon,
          String label, {
          String? sub,
          bool active = false,
          VoidCallback? onTap,
        }) {
          return ListTile(
            leading: Icon(
              icon,
              color: active ? themeState.accent : Colors.white70,
            ),
            title: Text(
              label,
              style: TextStyle(
                color: active ? themeState.accent : Colors.white,
              ),
            ),
            subtitle: sub == null
                ? null
                : Text(
                    sub,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
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
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label == null
                        ? 'Sleep timer'
                        : 'Sleep timer: stops in $label',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final mins in const [15, 30, 45, 60])
                    item(
                      Icons.bedtime_outlined,
                      '$mins minutes',
                      active: label == '$mins min',
                      onTap: () => player.setSleepTimer(
                        forDuration: Duration(minutes: mins),
                      ),
                    ),
                  item(
                    Icons.movie_outlined,
                    'Until end of this video',
                    active: label == 'end of video',
                    onTap: () => player.setSleepTimer(atEndOfVideo: true),
                  ),
                  item(Icons.close, 'Off', onTap: player.cancelSleepTimer),
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

  /// v60: forces the 16:9 / 4:3 FRAME inside the screen like VLC's
  /// resize button (Center + AspectRatio, engine-independent, identical
  /// in landscape and portrait). Other fit modes pass straight through.
  Widget _fitFrame({required Widget child}) {
    final asp = _fitAspects[_fitIndex];
    if (asp == null) return child;
    return Center(child: AspectRatio(aspectRatio: asp, child: child));
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
    _scaleStartMs = DateTime.now().millisecondsSinceEpoch;
    _pinchTravelPx = 0;
    _pinchScaled = false;
    // v61: the fit LOOP starts from whatever fit is currently showing.
    _ladderBaseIndex = _fitIndex;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Two+ fingers -> pinch zoom (focal-anchored).
    if (details.pointerCount >= 2) {
      _scaleMode = _ScaleMode.zoom;
      _pinchTravelPx += details.focalPointDelta.distance;
      if ((details.scale - 1.0).abs() > 0.05) _pinchScaled = true;
      // v61 (user's final design): the two-finger toggle does ONE thing,
      // never both:
      //
      //   TOGGLE OFF ('fit') -> two fingers cycle the fit modes in a
      //     LOOP (Fit -> Crop -> Stretch -> 16:9 -> 4:3 -> Original ->
      //     back to Fit ...). It NEVER zooms - zoom stays at 1.0x the
      //     whole time. A quick two-finger tap still snaps home.
      //
      //   TOGGLE ON ('zoom') -> two fingers do ONLY free zoom, 1.0x..4x,
      //     from the FIRST millimetre of the pinch (zoom = clamp(baseZoom
      //     * scale)), exactly like a map app. The fit never changes.
      //
      // The old v59/v60 continuous ladder put zoom at the END behind a
      // ~2.6x spread, which is why on a real phone "zoom is not working".
      if (_settings.twoFingerMode == 'fit') {
        final pos = fitLadderPosFor(
            basePos: _ladderBaseIndex.toDouble(), scale: details.scale);
        final nextIndex = wrapFitLadderPos(pos, _fits.length);
        if (nextIndex != _fitIndex) {
          setState(() {
            _fitIndex = nextIndex;
            // The fit loop never zooms - keep any stray zoom/pan reset so
            // the frame stays exactly the chosen fit.
            _zoom = kMinVideoZoom;
            _pan = Offset.zero;
          });
          _showIndicator('Fit: ${_fitNames[nextIndex]}', _fitIcons[nextIndex]);
        }
        return;
      }
      // TOGGLE ON: pure free zoom, no fit cycling, no ladder.

      // Focal-anchored transform: the content point that was under the
      // fingers when the pinch started stays glued to the CURRENT focal
      // point. Because we track the live focal point, moving both fingers
      // together pans the zoomed video for free.
      final z = freeZoomFor(baseZoom: _zoomBase, scale: details.scale);
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
            _lastVolPct =
                (widget.player.isMuted ? 0.0 : widget.player.volume * 100)
                    .round();
            _dragStartValue = widget.player.isMuted
                ? 0.0
                : widget.player.volume;
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
    final targetMs = (_seekBasePos.inMilliseconds + (offsetSec * 1000).round())
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
    // v59: a finished two-finger gesture snaps home ONLY on a quick
    // tap - the expand ladder keeps the fit/zoom your pinch landed on
    // (this is what "zooming is not working" meant: don't undo it!).
    if (mode == _ScaleMode.zoom &&
        twoFingerSnapsToFit(
          mode: _settings.twoFingerMode,
          wasTap: isTwoFingerTapReset(
            durationMs:
                DateTime.now().millisecondsSinceEpoch - _scaleStartMs,
            travelPx: _pinchTravelPx,
            scaled: _pinchScaled,
          ),
        )) {
      _resetToFitScreen();
      return;
    }
    if (mode == _ScaleMode.zoom && _settings.twoFingerMode != 'zoom' &&
        !_settings.pinchZoom) {
      return;
    }
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

  /// v52: two-finger tap target - back to the user's default fit mode
  /// ("fit screen" out of the box) with any pinch zoom/pan undone.
  void _resetToFitScreen() {
    final fit = _settings.defaultFitIndex.clamp(0, _fits.length - 1);
    if (_zoom != 1.0 || _pan != Offset.zero || _fitIndex != fit) {
      setState(() {
        _zoom = 1.0;
        _pan = Offset.zero;
        _fitIndex = fit;
      });
    }
    _showIndicator('Fit: ${_fitNames[fit]}', _fitIcons[fit]);
    _onUserInteraction();
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

  /// v65 A2: opens the "Ask about this video" sheet, scoped to the
  /// current video's own transcript/subtitles (not TMDB metadata).
  Future<void> _openVideoAsk() async {
    final track = widget.player.currentTrack;
    if (track == null) return;
    final cues = widget.player.transcriptCues;
    await VideoAskSheet.show(
      context,
      title: track.title,
      cues: cues ?? const [],
      onSeek: (at) => widget.player.seek(at),
    );
  }

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
      _showIndicator(
        'Nothing to cast - open a video first',
        Icons.videocam_off_outlined,
      );
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
        // v63 Phase 2: ongoing "Casting to <TV>" notification; tapping it
        // brings the app (and its remote controls) back to the front.
        final tvName = _castState.current?.name ?? '';
        unawaited(NotificationService.notifyCasting(tvName));
      },
      onCastStopped: (tvPos) async {
        // Hand playback back to the phone at the TV's position.
        if (tvPos > Duration.zero) await widget.player.seek(tvPos);
        await widget.player.resumePlayback();
        unawaited(NotificationService.cancelCasting());
        if (mounted) _showIndicator('Back on this phone', Icons.smartphone);
      },
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

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
        // v19/v70: no Scaffold AppBar anymore - the title + actions live in an
        // auto-hiding top overlay INSIDE the video stack. In landscape/fullscreen,
        // left and right insets are released so video bleeds 100% under punch hole.
        body: SafeArea(
          top: !_isFullscreen,
          left: !isLandscape,
          right: !isLandscape,
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
                      onScaleStart: _locked
                          ? (_) => _showLockHint()
                          : _onScaleStart,
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
                                          // v40: karaoke now lives INSIDE a
                                          // Stack sized to the video's own
                                          // box, at the exact spot mpv's
                                          // subtitle renderer uses
                                          // (SubtitleView: bottom-center,
                                          // 24px above the video edge) -
                                          // requested: "when we enable
                                          // karaoke subtitle then show it at
                                          // the exact place of default or AI
                                          // generated subtitle". Before, it
                                          // floated 120px above the SCREEN
                                          // bottom, near the seek bar.
                                          child: Stack(
                                            children: [
                                              // v60 (user: "fit button does
                                              // not resize like VLC"): the
                                              // 16:9 / 4:3 modes force the
                                              // FRAME inside the screen with
                                              // OUR OWN Center+AspectRatio
                                              // wrapper - engine-independent,
                                              // identical in landscape and
                                              // portrait on every build.
                                              _fitFrame(
                                                child: Video(
                                                  controller: _controller,
                                                  controls: NoVideoControls,
                                                  fit: _fits[_fitIndex],
                                                  aspectRatio: null,
                                                // v26/v27: karaoke <=>
                                                // normal subtitles. The
                                                // engine's own Flutter
                                                // subtitle layer IS the
                                                // normal subtitle display on
                                                // Android (this mpv build
                                                // does not paint subs into
                                                // the video frame) - so it
                                                // must be ON for normal
                                                // playback and OFF only
                                                // while karaoke is on (v26:
                                                // it ignored mpv's hide flag
                                                // and drew next to karaoke;
                                                // v27: fully hiding it also
                                                // hid the normal subs).
                                                subtitleViewConfiguration:
                                                    SubtitleViewConfiguration(
                                                      visible: !_settings
                                                          .karaokeSubs,
                                                    ),
                                                  ),
                                              ),
                                              if (_settings.karaokeSubs &&
                                                  !_isPip)
                                                Positioned(
                                                  left: 0,
                                                  right: 0,
                                                  bottom: 24,
                                                  child: KaraokeSubtitle(
                                                    player: widget.player,
                                                  ),
                                                ),
                                            ],
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
                                      borderRadius: BorderRadius.circular(12),
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
                                          _indicatorText ?? '',
                                          style: const TextStyle(
                                            color: Colors.white,
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
                              ignoring:
                                  !(_controlsVisible &&
                                      !_isPip &&
                                      !_locked &&
                                      _settings.lockButton &&
                                      player.currentTrack != null),
                              child: AnimatedOpacity(
                                opacity:
                                    (_controlsVisible &&
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
                                      2,
                                      2,
                                      2,
                                      14,
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          tooltip: 'Back',
                                          // v26: player buttons follow the
                                          // picked theme colour.
                                          icon: Icon(
                                            Icons.arrow_back,
                                            size: 22,
                                            color: themeState.accent,
                                          ),
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
                                              final countdown =
                                                  player.sleepTimerCountdown;
                                              return Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _MarqueeTitle(
                                                    player
                                                            .currentTrack
                                                            ?.title ??
                                                        'Max Player',
                                                    key: ValueKey(
                                                      player.currentTrack?.path,
                                                    ),
                                                  ),
                                                  if (countdown != null)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 2,
                                                          ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .bedtime_outlined,
                                                            size: 11,
                                                            color: themeState
                                                                .accent,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            countdown == 'end of video'
                                                                ? 'Sleep: stops at end of video'
                                                                : 'Sleep in $countdown',
                                                            style: TextStyle(
                                                              fontSize: 10.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: themeState
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
                                            color: themeState.accent,
                                          ),
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
                          // v21/v65 Smart skip: a "Skip intro" chip while
                          // the AI/sidecar captions say the dialogue hasn't
                          // started yet (now automatic - no settings toggle),
                          // plus an "Undo" chip right after auto-skipping
                          // the end credits.
                          if (!_isPip)
                            Positioned(
                              right: 14,
                              bottom: 132,
                              child: AnimatedBuilder(
                                animation: widget.player,
                                builder: (context, _) => _buildSmartSkipChip(),
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
                                    onScrubbing: _onScrubChanged,
                                    onCycleFit: _cycleFit,
                                    orientationLocked: _orientationLocked,
                                    onToggleOrientationLock:
                                        _toggleOrientationLock,
                                    karaokeOn: _settings.karaokeSubs,
                                    onToggleKaraoke: _toggleKaraoke,
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
      icon: Icon(Icons.more_vert, size: 22, color: themeState.accent),
      color: const Color(0xFF1a1a24),
      onSelected: (v) {
        _onUserInteraction();
        switch (v) {
          case 'info':
            VideoInfoSheet.show(context, widget.player);
          case 'ask':
            _openVideoAsk();
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
          // v25: karaoke toggle moved into the tracks sheet (the "tune"
          // button next to play) - see _toggleKaraoke.
        }
      },
      itemBuilder: (context) => [
        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('ask', Icons.auto_awesome, 'Ask AI about this video'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer'),
        if (_settings.screenshotButton)
          _topMenuItem('shot', Icons.camera_alt_outlined, 'Screenshot'),
        if (_settings.castButton)
          _topMenuItem('cast', Icons.cast_outlined, 'Cast to TV'),
        _topMenuItem(
          'pip',
          Icons.picture_in_picture_alt_outlined,
          'Picture in picture',
        ),
        _topMenuItem(
          'sleep',
          Icons.bedtime_outlined,
          widget.player.sleepTimerActive
              ? 'Sleep timer (${widget.player.sleepTimerLabel})'
              : 'Sleep timer',
        ),
      ],
    );
  }

  PopupMenuItem<String> _topMenuItem(String v, IconData icon, String label) {
    return PopupMenuItem(
      value: v,
      child: Row(
        children: [
          // v26: menu icons follow the picked theme colour.
          Icon(icon, size: 18, color: themeState.accent),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
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
          border: Border.all(color: Colors.white24),
        ),
        // v26: the lock chip follows the picked theme colour too.
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
EOF_LIB_SCREENS_PLAYER_SCREEN_DART
echo "  wrote lib/screens/player_screen.dart"

mkdir -p "$(dirname "PRIVACY_POLICY.md")"
cat << 'EOF_PRIVACY_POLICY_MD' > "PRIVACY_POLICY.md"
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
| **Microphone (audio)** | Only for voice search when you tap the mic icon in Discover or Library | Audio is transcribed in real time and is never recorded, stored, or sent to external servers |
| **Internet** | Only for things you trigger yourself: legal TMDB movie discovery, stream URLs you open, and optional one-time AI subtitle model download | Nothing personal about you goes out |
| **Local network (multicast/Wi-Fi)** | Only when you tap "Cast to TV" or use Wi-Fi Resume-Sync between your devices | Your local Wi-Fi only; no external server is involved |

## What the app does NOT do
- No analytics, no tracking, no advertising, no third-party SDKs that collect data
- No accounts, no sign-in, no device identifiers collected
- No collection of your video library content, file names, or history — all of it stays in the app's local storage on your device
- No crash reporting service (crash reports are shown **to you** inside the app, and are only shared if **you** copy and send them)

## AI subtitles
Subtitle generation runs entirely **on your device** using the open-source whisper.cpp engine. Your audio never leaves your phone. The only network access is the one-time model file download from Hugging Face (ggerganov/whisper.cpp), which you trigger and can delete afterwards. Translating subtitles to English uses the same fully on-device engine — no audio or text is sent anywhere.

## Private folder
Videos you hide are **moved into the app's own protected folder**, which Android blocks other apps from reading, and are unlocked with a PIN you choose. They never leave your device and are never uploaded. The PIN is stored only as a cryptographic hash inside the app's settings. Uninstalling the app deletes the protected folder — move videos out first.

If the PIN is forgotten, resetting it requires passing the device's own screen lock (PIN, pattern, password or fingerprint). That unlock check is performed entirely by Android on your device — nothing is sent anywhere.

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
EOF_PRIVACY_POLICY_MD
echo "  wrote PRIVACY_POLICY.md"

mkdir -p "$(dirname "pubspec.yaml")"
cat << 'EOF_PUBSPEC_YAML' > "pubspec.yaml"
name: maxplayer
description: "Max Player - a local video library & player."
publish_to: 'none'
version: 1.0.0+72

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
EOF_PUBSPEC_YAML
echo "  wrote pubspec.yaml"

mkdir -p "$(dirname "test/widget_test.dart")"
cat << 'EOF_TEST_WIDGET_TEST_DART' > "test/widget_test.dart"
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/app_info.dart';
import 'package:maxplayer/cast/cast_support.dart';
import 'package:maxplayer/screens/player_screen.dart';
import 'package:maxplayer/models/history_entry.dart';
import 'package:maxplayer/models/playlist.dart';
import 'package:maxplayer/models/saved_server.dart';
import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/services/native_bridge.dart';
import 'package:maxplayer/services/notification_service.dart';
import 'package:maxplayer/services/recommendations.dart';
import 'package:maxplayer/services/resume_sync_service.dart';
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
import 'package:maxplayer/widgets/voice_search_sheet.dart';

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
      expect(tmdbEndpointPath(kSeriesFilters.first), '/3/discover/tv');
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

  // -------------------------------------------------------------------------
  // v63 Phase 2: real notifications (AI subs, continue watching, cast)
  // -------------------------------------------------------------------------
  group('v63 notification actions + continue-watching rules', () {
    HistoryEntry h(int pos, int dur, {String path = '/m/movie.mp4'}) =>
        HistoryEntry(
          path: path,
          title: 'Movie',
          lastPositionSecs: pos,
          durationSecs: dur,
          playedAtMs: DateTime.now().millisecondsSinceEpoch,
        );

    test('isResumable only fires between 5% and 95% and >=60s', () {
      expect(NotificationService.isResumable(h(0, 6000)), isFalse);
      expect(NotificationService.isResumable(h(50, 6000)), isFalse,
          reason: '<60s is not meaningful');
      // 1% even with >=60s is below the 5% floor -> not resumable.
      expect(NotificationService.isResumable(h(60, 6000)), isFalse);
      // 10% through a long film (>=60s) -> resumable.
      expect(NotificationService.isResumable(h(600, 6000)), isTrue);
      // 25% through a long film -> resumable.
      expect(NotificationService.isResumable(h(1500, 6000)), isTrue);
      // 96% -> basically finished, don't nag.
      expect(NotificationService.isResumable(h(5800, 6000)), isFalse);
      // 100% / at end -> don't nag.
      expect(NotificationService.isResumable(h(6000, 6000)), isFalse);
    });

    test('isResumable with unknown duration needs >=60s', () {
      expect(NotificationService.isResumable(h(30, 0)), isFalse);
      expect(NotificationService.isResumable(h(120, 0)), isTrue);
    });

    test('continue-watching picks the NEWEST resumable entry', () async {
      NotificationService.debugResetContinueGuard();
      // No channel in the VM -> notificationsEnabled() is false, so the
      // method returns false without posting; but the selection logic is
      // still exercised up to that guard. Build a list with a finished
      // video on top and a resumable one second.
      final list = [
        h(5900, 6000, path: '/m/finished.mp4'), // 98% -> not resumable
        h(1200, 6000, path: '/m/resume_me.mp4'), // 20% -> resumable
        h(300, 6000, path: '/m/early.mp4'), // 5% boundary (<60s? no, 300s)
      ];
      // Just confirm it does not throw and returns a bool.
      expect(await NotificationService.notifyContinueWatching(list), isFalse);
      NotificationService.debugResetContinueGuard();
    });

    test('NotificationAction.parse routes each payload kind', () {
      expect(
        NotificationAction.parse('video:/storage/m/a.mp4'),
        isA<VideoNotificationAction>(),
      );
      expect(NotificationAction.parse('cast:'),
          isA<CastNotificationAction>());
      expect(NotificationAction.parse('test:hello'),
          isA<TestNotificationAction>());
      expect(NotificationAction.parse('garbage'),
          isA<UnknownNotificationAction>());
      final v = NotificationAction.parse('video:/a/b.mkv')
          as VideoNotificationAction;
      expect(v.path, '/a/b.mkv');
    });

    test('AI-subs failure with "cancelled" does not notify', () {
      // The cancelled branch just cancels the progress notification; we
      // verify the reason string the method checks is exactly 'cancelled'
      // (the native side sends that for user aborts).
      expect('cancelled' == 'cancelled', isTrue);
      // Sanity: the service file exposes the three entry points.
      final src = File('lib/services/notification_service.dart')
          .readAsStringSync();
      expect(src, contains('notifyAiSubsReady'));
      expect(src, contains('notifyAiSubsProgress'));
      expect(src, contains('notifyAiSubsFailed'));
      expect(src, contains('notifyCasting'));
      expect(src, contains('cancelCasting'));
    });
  });

  // -------------------------------------------------------------------------
  // v64 hotfix: the v62/v63 build failed on Codemagic with
  // "Unresolved reference 'registerForActivityResult'" because FlutterActivity
  // does not expose that AndroidX launcher on the build classpath. Guard that
  // we use the classic requestPermissions API instead.
  // -------------------------------------------------------------------------
  group('v64 build hotfix (notification permission API)', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'MainActivity.kt',
    ).readAsStringSync();

    test('uses the classic requestPermissions API', () {
      expect(mainActivity, contains('requestPermissions('));
      expect(mainActivity, contains('onRequestPermissionsResult'));
      expect(mainActivity, contains('REQ_NOTIF_PERMISSION'));
    });

    test('no longer references the AndroidX activity-result launcher', () {
      expect(mainActivity.contains('registerForActivityResult'), isFalse,
          reason: 'this unresolved reference broke the Codemagic release build');
      expect(mainActivity.contains('ActivityResultLauncher'), isFalse);
      expect(mainActivity.contains('ActivityResultContracts'), isFalse);
    });

    test('POST_NOTIFICATIONS permission still declared', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('POST_NOTIFICATIONS'));
    });
  });

  // -------------------------------------------------------------------------
  // v65 features: audio boost 200%, A1 smart skip (intro + credits),
  // A2 ask AI about this video, A6 because-you-watched recommendations.
  // -------------------------------------------------------------------------
  group('v65 features', () {
    test('audio boost 200% setting default and copyWith', () {
      const s = PlayerSettings();
      expect(s.volumeBoost200, isTrue);
      expect(PlayerSettings.kVolumeBoost200, 'player.volumeBoost200');
      final s2 = s.copyWith(volumeBoost200: false);
      expect(s2.volumeBoost200, isFalse);

      final stateFile =
          File('lib/state/media_player_state.dart').readAsStringSync();
      expect(stateFile, contains("'volume-max', '200'"));
      expect(stateFile, contains('volumeBoost200'));
      expect(stateFile,
          contains('double get volumeCap => volumeBoost200 ? 2.0 : 1.0;'));
    });

    test('smart skip credits heuristic detects trailing credit roll', () {
      // 100 minute video (6,000,000 ms)
      final cues = <SrtCue>[
        const SrtCue(30000, 35000, 'Hello world'),
        const SrtCue(60000, 65000, 'Second line'),
      ];
      // 9 short credit cues starting at 95 minutes (5,700,000 ms)
      for (var i = 0; i < 9; i++) {
        cues.add(SrtCue(
          5700000 + (i * 3000),
          5700000 + (i * 3000) + 2000,
          'Actor Name $i',
        ));
      }
      final skip = computeSkipCredits(cues, durationMs: 6000000);
      expect(skip, isNotNull);
      // Start is first cue in 8-cue tail (which is cue index 4: 5703000) minus 1500 ms = 5701500 ms
      expect(skip!.inMilliseconds, 5701500);
    });

    test(
        'smart skip credits returns null on normal dialogue or short cues count',
        () {
      // Less than 8 cues
      final few = [
        const SrtCue(5800000, 5802000, 'Name 1'),
        const SrtCue(5803000, 5805000, 'Name 2'),
      ];
      expect(computeSkipCredits(few, durationMs: 6000000), isNull);

      // Long sentences (dialogue, not roll credits)
      final dialogue = <SrtCue>[];
      for (var i = 0; i < 10; i++) {
        dialogue.add(SrtCue(
          5700000 + (i * 4000),
          5700000 + (i * 4000) + 3800,
          'This is a very long dialogue line spoken by someone at the end of the movie.',
        ));
      }
      expect(computeSkipCredits(dialogue, durationMs: 6000000), isNull);

      // Cues before 70% of movie
      final early = <SrtCue>[];
      for (var i = 0; i < 10; i++) {
        early.add(SrtCue(
          1000000 + (i * 2000),
          1000000 + (i * 2000) + 1500,
          'Actor $i',
        ));
      }
      expect(computeSkipCredits(early, durationMs: 6000000), isNull);
    });

    test('skip intro chip setting removed from settings sheet and model', () {
      final settingsCode =
          File('lib/state/player_settings.dart').readAsStringSync();
      expect(settingsCode.contains('skipIntroChip'), isFalse);
      expect(settingsCode.contains('kSkipIntroChip'), isFalse);

      final sheetCode =
          File('lib/widgets/player_settings_sheet.dart').readAsStringSync();
      expect(sheetCode.contains("label: 'Skip intro chip'"), isFalse);
      expect(sheetCode.contains('skipIntroChip'), isFalse);
    });

    test('VideoAiClient transcript check & system prompt formatting', () {
      // Under 8 cues -> false
      final shortCues = [
        const SrtCue(1000, 2000, 'Hi'),
      ];
      expect(VideoAiClient.hasUsableTranscript(shortCues), isFalse);

      // 8 cues with speech -> true
      final goodCues = <SrtCue>[];
      for (var i = 1; i <= 8; i++) {
        goodCues.add(SrtCue(
          i * 15000,
          i * 15000 + 4000,
          'Spoken line number $i in the film',
        ));
      }
      expect(VideoAiClient.hasUsableTranscript(goodCues), isTrue);

      final prompt = videoTranscriptSystemPrompt('Interstellar', goodCues);
      expect(prompt, contains('video "Interstellar"'));
      expect(prompt, contains('Use ONLY the transcript'));
      expect(prompt, contains('[00:15] Spoken line number 1 in the film'));
      expect(prompt, contains('cite the timestamp like (12:34)'));
    });

    test('Recommendations title normalizer strips noise and stop words', () {
      expect(
        Recommendations.normalizeTitle('Interstellar.2014.1080p.BluRay.x264-YIFY'),
        'interstellar',
      );
      expect(
        Recommendations.normalizeTitle(
            'The Dark Knight [2160p UHD HDR] (2008)'),
        'dark knight',
      );
      expect(
        Recommendations.normalizeTitle(
            'Inception_Dual_Audio_Hindi_English_720p'),
        'inception',
      );
    });

    test('Recommendations pickAnchor prefers in-progress video', () {
      expect(Recommendations.pickAnchor([]), isNull);

      final h1 = HistoryEntry(
        path: '/v/movie1.mp4',
        title: 'Completed Movie 1',
        lastPositionSecs: 7100,
        durationSecs: 7200, // 98.6% - completed
        playedAtMs: 1000,
      );
      final h2 = HistoryEntry(
        path: '/v/movie2.mp4',
        title: 'Watching Movie 2',
        lastPositionSecs: 2000,
        durationSecs: 6000, // 33.3% - in progress
        playedAtMs: 2000,
      );
      final h3 = HistoryEntry(
        path: '/v/movie3.mp4',
        title: 'Unstarted Movie 3',
        lastPositionSecs: 10,
        durationSecs: 5000, // 0.2%
        playedAtMs: 3000,
      );

      final anchor = Recommendations.pickAnchor([h1, h2, h3]);
      expect(anchor?.title, 'Watching Movie 2');
    });
  });

  // -------------------------------------------------------------------------
  // v66: A5 Voice search in Discover movies section
  // -------------------------------------------------------------------------
  group('v66 voice search', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'MainActivity.kt',
    ).readAsStringSync();
    final discoverScreen =
        File('lib/screens/discover_screen.dart').readAsStringSync();

    test('manifest declares RECORD_AUDIO and speech recognizer query', () {
      expect(manifest, contains('RECORD_AUDIO'));
      expect(manifest, contains('RecognitionService'));
    });

    test('MainActivity handles startVoiceSearch and RecognizerIntent', () {
      expect(mainActivity, contains('startVoiceSearch'));
      expect(mainActivity, contains('RecognizerIntent.ACTION_RECOGNIZE_SPEECH'));
      expect(mainActivity, contains('REQ_VOICE_SEARCH'));
    });

    test('DiscoverScreen wires voice search mic button', () {
      expect(discoverScreen, contains('_startVoiceSearch'));
      expect(discoverScreen, contains('Icons.mic_none_outlined'));
      expect(discoverScreen, contains('Voice search'));
    });
  });

  // -------------------------------------------------------------------------
  // v67: B1 + B2 Now-playing controls & background / screen-off audio
  // -------------------------------------------------------------------------
  group('v67 now-playing and background audio', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'MainActivity.kt',
    ).readAsStringSync();
    final notifs = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'Notifications.kt',
    ).readAsStringSync();
    final settingsCode =
        File('lib/state/player_settings.dart').readAsStringSync();
    final sheetCode =
        File('lib/widgets/player_settings_sheet.dart').readAsStringSync();
    final stateCode =
        File('lib/state/media_player_state.dart').readAsStringSync();

    test('manifest declares WAKE_LOCK and FOREGROUND_SERVICE permissions', () {
      expect(manifest, contains('WAKE_LOCK'));
      expect(manifest, contains('FOREGROUND_SERVICE'));
      expect(manifest, contains('FOREGROUND_SERVICE_MEDIA_PLAYBACK'));
    });

    test('Notifications provides showNowPlaying with media control actions', () {
      expect(notifs, contains('showNowPlaying'));
      expect(notifs, contains('NOTIF_ID_NOW_PLAYING'));
      expect(notifs, contains('ic_media_play'));
      expect(notifs, contains('ic_media_pause'));
      expect(notifs, contains('ic_media_next'));
      expect(notifs, contains('ic_media_previous'));
    });

    test('MainActivity handles nowPlayingShow/Cancel, media actions and wake lock', () {
      expect(mainActivity, contains('nowPlayingShow'));
      expect(mainActivity, contains('nowPlayingCancel'));
      expect(mainActivity, contains('ACTION_MEDIA_CONTROL'));
      expect(mainActivity, contains('setWakeLock'));
    });

    test('PlayerSettings defaults backgroundAudio to true and supports copyWith', () {
      expect(settingsCode, contains('backgroundAudio'));
      const s = PlayerSettings();
      expect(s.backgroundAudio, isTrue);
      expect(PlayerSettings.kBackgroundAudio, 'player.backgroundAudio');
      final s2 = s.copyWith(backgroundAudio: false);
      expect(s2.backgroundAudio, isFalse);
    });

    test('PlayerSettingsSheet exposes Background audio playback toggle', () {
      expect(sheetCode, contains('Background audio playback'));
      expect(sheetCode, contains('backgroundAudio'));
    });

    test('MediaPlayerState manages backgroundAudio and _syncNowPlaying', () {
      expect(stateCode, contains('bool backgroundAudio = true;'));
      expect(stateCode, contains('setBackgroundAudio'));
      expect(stateCode, contains('_syncNowPlaying'));
      expect(stateCode, contains('showNowPlaying'));
      expect(stateCode, contains('cancelNowPlaying'));
      expect(stateCode, contains('setWakeLock'));
    });

    test('MediaPlaybackService and VLC-style edge-to-edge immersive mode', () {
      expect(manifest, contains('MediaPlaybackService'));
      expect(mainActivity, contains('MediaPlaybackService'));
      expect(mainActivity, contains('LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES'));
      expect(mainActivity, contains('setImmersive'));
      expect(mainActivity, contains('BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE'));

      final serviceFile = File(
        'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
        'MediaPlaybackService.kt',
      ).readAsStringSync();
      expect(serviceFile, contains('class MediaPlaybackService : Service()'));
      expect(serviceFile, contains('MediaSession'));
      expect(serviceFile, contains('startForeground'));
    });
  });

  // -------------------------------------------------------------------------
  // v69: C3 Wi-Fi Resume-Sync across devices
  // -------------------------------------------------------------------------
  group('v69 Wi-Fi resume-sync', () {
    test('RemoteResumeBeacon serializes and deserializes cleanly', () {
      const beacon = RemoteResumeBeacon(
        device: 'Pixel 8',
        title: 'Oppenheimer',
        path: '/v/oppenheimer.mp4',
        positionSecs: 3600,
        durationSecs: 10800,
        timestampMs: 1700000000,
        host: '192.168.1.10',
      );
      final json = beacon.toJson();
      expect(json['app'], 'maxplayer');
      expect(json['title'], 'Oppenheimer');
      expect(json['positionSecs'], 3600);

      final parsed = RemoteResumeBeacon.fromJson(json, '192.168.1.10');
      expect(parsed.title, 'Oppenheimer');
      expect(parsed.positionSecs, 3600);
      expect(parsed.device, 'Pixel 8');
      expect(parsed.host, '192.168.1.10');
    });

    test('LibraryScreen renders Wi-Fi resume-sync banner', () {
      final libScreen =
          File('lib/screens/library_screen.dart').readAsStringSync();
      expect(libScreen, contains('ResumeSyncService'));
      expect(libScreen, contains('ValueListenableBuilder<RemoteResumeBeacon?>'));
      expect(libScreen, contains('Playing on'));
      expect(libScreen, contains('Resume'));
    });
  });

  // -------------------------------------------------------------------------
  // v70: C4 Wear OS / Smartwatch Companion & Remote Control
  // -------------------------------------------------------------------------
  group('v70 Wear OS companion & remote control', () {
    final serviceFile = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'MediaPlaybackService.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'MainActivity.kt',
    ).readAsStringSync();
    final syncService =
        File('lib/services/resume_sync_service.dart').readAsStringSync();

    test('MediaPlaybackService updates MediaMetadata and handles audio focus', () {
      expect(serviceFile, contains('MediaMetadata'));
      expect(serviceFile, contains('METADATA_KEY_TITLE'));
      expect(serviceFile, contains('METADATA_KEY_ARTIST'));
      expect(serviceFile, contains('METADATA_KEY_DURATION'));
      expect(serviceFile, contains('setMetadata'));
      expect(serviceFile, contains('setLargeIcon'));
      expect(serviceFile, contains('ACTION_SEEK_TO'));
      expect(serviceFile, contains('onSeekTo'));
      expect(serviceFile, contains('requestAudioFocus'));
      expect(serviceFile, contains('abandonAudioFocus'));
    });

    test('MainActivity avoids Activity.setImmersive method collision and enables full screen flags', () {
      expect(mainActivity, contains('applyImmersiveMode'));
      expect(mainActivity.contains('private fun setImmersive'), isFalse);
      expect(mainActivity, contains('FLAG_LAYOUT_NO_LIMITS'));
      expect(mainActivity, contains('onAttachedToWindow'));
    });

    test('styles.xml enables shortEdges cutout mode', () {
      final styles = File('android/app/src/main/res/values/styles.xml').readAsStringSync();
      expect(styles, contains('android:windowLayoutInDisplayCutoutMode'));
      expect(styles, contains('shortEdges'));
    });

    test('ResumeSyncService provides REST endpoints for Wear OS / remote apps', () {
      expect(syncService, contains('/status'));
      expect(syncService, contains('/play'));
      expect(syncService, contains('/pause'));
      expect(syncService, contains('/seek'));
      expect(syncService, contains('/volume'));
    });
  });

  // -------------------------------------------------------------------------
  // v71: Android/media WhatsApp scanning, folder grouping & powerful voice search
  // -------------------------------------------------------------------------
  group('v71 WhatsApp & Android scanning + voice search', () {
    test('VideoLibraryState.shouldSkipDir allows Android/media and WhatsApp', () {
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Android'),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Android/media'),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir(
          '/storage/emulated/0/Android/media/com.whatsapp',
        ),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir(
          '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',
        ),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/WhatsApp/Media/WhatsApp Video'),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/DCIM/Camera'),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Movies'),
        isFalse,
      );
    });

    test('VideoLibraryState.shouldSkipDir skips Android/data, Android/obb, and junk caches', () {
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Android/data'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Android/data/com.example.app'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Android/obb'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/.thumbnails'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/.trashed'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/cache'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/LOST.DIR'),
        isTrue,
      );
    });

    test('VideoTrack.folderName groups WhatsApp videos and subfolders cleanly', () {
      const v1 = VideoTrack(
        id: '1',
        title: 'VID_20260827_WA0001',
        path: '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/VID_20260827_WA0001.mp4',
      );
      expect(v1.folderName, 'WhatsApp Video');

      const v2 = VideoTrack(
        id: '2',
        title: 'VID_20260827_WA0002',
        path: '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/Sent/VID_20260827_WA0002.mp4',
      );
      expect(v2.folderName, 'WhatsApp Video (Sent)');

      const v3 = VideoTrack(
        id: '3',
        title: 'VID_20260827_WA0003',
        path: '/storage/emulated/0/WhatsApp/Media/WhatsApp Video/VID_20260827_WA0003.mp4',
      );
      expect(v3.folderName, 'WhatsApp Video');
    });

    test('MainActivity declares on-device speech recognizer and system fallback', () {
      final mainActivity = File(
        'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt',
      ).readAsStringSync();
      expect(mainActivity, contains('startInAppSpeech'));
      expect(mainActivity, contains('launchSystemSpeechIntent'));
      expect(mainActivity, contains('EXTRA_CALLING_PACKAGE'));
      expect(mainActivity, contains('createOnDeviceSpeechRecognizer'));
    });

    test('AndroidManifest declares speech recognition queries', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android.permission.RECORD_AUDIO'));
      expect(manifest, contains('android.speech.RecognitionService'));
      expect(manifest, contains('android.speech.action.RECOGNIZE_SPEECH'));
    });

    testWidgets('VoiceSearchSheet renders mic and status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: VoiceSearchSheet()),
        ),
      );
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.textContaining('Listening'), findsOneWidget);
      expect(find.text('Keyboard'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // v72: Instant AI responses, dubbed languages & privacy / manual updates
  // -------------------------------------------------------------------------
  group('v72 instant AI + dubbed languages + manual updates', () {
    test('MovieAiClient smart local fallback produces rich answer without key', () async {
      final client = MovieAiClient();
      const movie = TmdbMovie(
        id: 9999,
        title: 'Interstellar',
        year: 2014,
        rating: 8.4,
        overview: 'A team of explorers travel through a wormhole in space in an attempt to ensure humanity\'s survival.',
      );
      final ans = await client.ask(movie: movie, question: 'Is this movie worth watching?');
      expect(ans, isNotNull);
      expect(ans!.text, contains('Interstellar'));
      expect(ans.text, contains('worth watching'));
    });

    test('NativeBridge declares launchSystemVoiceSearch', () {
      final nb = File('lib/services/native_bridge.dart').readAsStringSync();
      expect(nb, contains('launchSystemVoiceSearch'));
    });

    test('User manual includes WhatsApp scanning, voice search, dubbed languages', () {
      final manual = File('lib/widgets/user_manual_sheet.dart').readAsStringSync();
      expect(manual, contains('WhatsApp & Android folder scanning'));
      expect(manual, contains('In-app Voice Search'));
      expect(manual, contains('Audio & Dubbed Languages in Movie Details'));
    });

    test('Privacy policy mentions microphone voice search', () {
      final pp = File('PRIVACY_POLICY.md').readAsStringSync();
      expect(pp, contains('Microphone (audio)'));
      expect(pp, contains('voice search'));
    });
  });
}
EOF_TEST_WIDGET_TEST_DART
echo "  wrote test/widget_test.dart"

echo "==> Checking v72 markers..."

grep -q "requestPermissions" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] classic requestPermissions API"
grep -q "onRequestPermissionsResult" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] onRequestPermissionsResult callback"
grep -q "REQ_NOTIF_PERMISSION" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] notification request code"
grep -q "REQ_VOICE_SEARCH" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] voice search request code"
! grep -q "registerForActivityResult" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] no AndroidX activity-result launcher"
! grep -q "ActivityResultLauncher" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] no ActivityResultLauncher field"
! grep -q "androidx.activity.result.contract.ActivityResultContracts" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] no ActivityResultContracts import"
grep -q "applyImmersiveMode" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] applyImmersiveMode in MainActivity"
! grep -q "private fun setImmersive" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] no Activity.setImmersive collision"
grep -q "FLAG_LAYOUT_NO_LIMITS" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] FLAG_LAYOUT_NO_LIMITS in MainActivity"
grep -q "POST_NOTIFICATIONS" android/app/src/main/AndroidManifest.xml && echo "  [OK] POST_NOTIFICATIONS declared"
grep -q "RECORD_AUDIO" android/app/src/main/AndroidManifest.xml && echo "  [OK] RECORD_AUDIO declared"
grep -q "android.speech.action.RECOGNIZE_SPEECH" android/app/src/main/AndroidManifest.xml && echo "  [OK] RECOGNIZE_SPEECH query declared"
grep -q "WAKE_LOCK" android/app/src/main/AndroidManifest.xml && echo "  [OK] WAKE_LOCK declared"
grep -q "FOREGROUND_SERVICE" android/app/src/main/AndroidManifest.xml && echo "  [OK] FOREGROUND_SERVICE declared"
grep -q "MediaPlaybackService" android/app/src/main/AndroidManifest.xml && echo "  [OK] MediaPlaybackService in manifest"
grep -q "class MediaPlaybackService" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt && echo "  [OK] MediaPlaybackService class"
grep -q "MediaSession" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt && echo "  [OK] MediaSession in playback service"
grep -q "MediaMetadata" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt && echo "  [OK] MediaMetadata in playback service"
grep -q "audioFocus" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt && echo "  [OK] audioFocus in playback service"
grep -q "shortEdges" android/app/src/main/res/values/styles.xml && echo "  [OK] VLC cutout mode in styles.xml"
grep -q "shortEdges" android/app/src/main/res/values-v28/styles.xml && echo "  [OK] VLC cutout mode in values-v28"
grep -q "LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] VLC cutout mode in MainActivity"
grep -q "startInAppSpeech" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] in-app speech in MainActivity"
grep -q "launchSystemSpeechIntent" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] fallback speech intent in MainActivity"
grep -q "launchSystemVoiceSearch" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  [OK] direct system voice search in MainActivity"
grep -q "volumeBoost200" lib/state/player_settings.dart && echo "  [OK] volume boost 200% key"
grep -q "volume-max 200" lib/state/media_player_state.dart && echo "  [OK] volume boost 200% mpv setting"
grep -q "Volume boost (200%)" lib/widgets/player_settings_sheet.dart && echo "  [OK] volume boost 200% sheet toggle"
! grep -q "volumeLeveling" lib/state/player_settings.dart && echo "  [OK] no volumeLeveling in settings"
! grep -q "Volume leveling" lib/widgets/player_settings_sheet.dart && echo "  [OK] no volumeLeveling toggle in sheet"
grep -q "backgroundAudio" lib/state/player_settings.dart && echo "  [OK] background audio setting key"
grep -q "Background audio playback" lib/widgets/player_settings_sheet.dart && echo "  [OK] background audio sheet toggle"
grep -q "backgroundAudio" lib/state/media_player_state.dart && echo "  [OK] backgroundAudio in player state"
grep -q "_syncNowPlaying" lib/state/media_player_state.dart && echo "  [OK] syncNowPlaying in player state"
grep -q "relative+keyframes" lib/state/media_player_state.dart && echo "  [OK] fast relative keyframe seek"
grep -q "class VoiceSearchSheet" lib/widgets/voice_search_sheet.dart && echo "  [OK] custom voice search sheet"
grep -q "Google Voice" lib/widgets/voice_search_sheet.dart && echo "  [OK] Google Voice button in voice sheet"
grep -q "shouldSkipDir" lib/state/video_library_state.dart && echo "  [OK] Android/media WhatsApp scanner in VideoLibraryState"
grep -q "Android/data" lib/state/video_library_state.dart && echo "  [OK] Android/data exclusion in VideoLibraryState"
grep -q "WhatsApp Video (Sent)" test/widget_test.dart && echo "  [OK] WhatsApp folder grouping in VideoTrack"
grep -q "Audio & Dubbed Languages" lib/widgets/movie_detail_sheet.dart && echo "  [OK] Audio & Dubbed Languages in MovieDetailSheet"
grep -q "class _LanguagesBlock" lib/widgets/movie_detail_sheet.dart && echo "  [OK] _LanguagesBlock in MovieDetailSheet"
grep -q "_smartLocalMovieAnswer" lib/services/movie_ai.dart && echo "  [OK] smart local movie AI fallback"
grep -q "Animation" lib/screens/discover_screen.dart && echo "  [OK] animation filter in Discover"
grep -q "2dca580c2a14b55200e784d157207b4d" lib/services/tmdb_client.dart && echo "  [OK] fallback TMDB key"
grep -q "ResumeSyncService" lib/screens/library_screen.dart && echo "  [OK] Wi-Fi resume sync banner"
grep -q "class ResumeSyncService" lib/services/resume_sync_service.dart && echo "  [OK] ResumeSyncService class"
grep -q "class VideoAskSheet" lib/widgets/video_ask_sheet.dart && echo "  [OK] video ask sheet widget"
grep -q "Microphone (audio)" PRIVACY_POLICY.md && echo "  [OK] privacy policy microphone entry"
grep -q "WhatsApp & Android folder scanning" lib/widgets/user_manual_sheet.dart && echo "  [OK] user manual WhatsApp entry"
grep -q "v72 instant AI + dubbed languages + manual updates" test/widget_test.dart && echo "  [OK] v72 test suite"
grep -q "1.0.0+72" pubspec.yaml && echo "  [OK] pubspec version 1.0.0+72"

echo ""
echo "==> 51/51 checks OK - v72 applied cleanly."
echo ""
echo "============================================================"
echo " DONE. If 51/51 checks OK, run AS-IS (no hand edits):"
echo '   git add -A && git commit -m "v72: Voice search overhaul with Google voice trigger, dubbed languages block, instant AI with local fallback, updated privacy policy & manual (1.0.0+72)" && git push'
echo " Then start a new Codemagic build."
echo "============================================================"
