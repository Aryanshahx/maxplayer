package com.hypertechlabs.maxplayer

import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.app.RecoverableSecurityException
import android.app.RemoteAction
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.hardware.SensorManager
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Rational
import android.view.KeyEvent
import android.view.OrientationEventListener
import dev.ffmpegkit.whisper.Whisper
import dev.ffmpegkit.whisper.WhisperConfig
import dev.ffmpegkit.whisper.WhisperModel
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.Executors
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.runBlocking

class MainActivity : FlutterFragmentActivity() {

    private var pipPlaying = true
    private var methodChannel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    // AI subtitles (on-device whisper.cpp) job state. One job at a time;
    // the Dart side refuses to start a second while one is running.
    @Volatile
    private var aiCancelled = false
    private var aiJobCounter = 0

    private class AiCancelledException : Exception("cancelled")

    // Drop 5 storage channel: system document picker (cloud import),
    // vault directory, system delete-consent, thumbnails. Separate from
    // `maxplayer/native` so its `onPickProgress` events never collide with
    // the player's `pipToggle` handler.
    private var storageChannel: MethodChannel? = null

    // System document picker (SAF) round-trip in flight.
    private var pendingSafPickResult: MethodChannel.Result? = null

    // Flipped by the "abortPickCopy" call (progress dialog's Cancel); the
    // streaming copy loop polls it between chunks.
    @Volatile
    private var safCopyAborted = false

    // System delete-consent round trip (vault hide flow). API 30+ needs no
    // retry list (createDeleteRequest handles the whole batch); API 29
    // consents per file, so remember what is left to delete.
    private var pendingMediaDeleteResult: MethodChannel.Result? = null
    private var pendingMediaDeletePaths: ArrayList<String>? = null

    // Voice search round-trip (system speech dialog, Discover screen).
    private var pendingVoiceSearchResult: MethodChannel.Result? = null

    // In-app SpeechRecognizer (Discover voice search; the old app's custom
    // mic path — more robust than the system dialog on most devices).
    private var inAppSpeechRecognizer: SpeechRecognizer? = null

    // MediaStore rename consent round-trip. Shared-storage files may require
    // the Android system write dialog before DISPLAY_NAME can be updated.
    private var pendingRenameResult: MethodChannel.Result? = null
    private var pendingRenamePath: String? = null
    private var pendingRenameName: String? = null
    private var pendingRenameId: String? = null

    // Real codec dimensions per path (v29 quality-badge fix). MediaStore's
    // WIDTH/HEIGHT columns are 0 for many MKV/WebM/AVI files, so the badge
    // probed the real size once through MediaMetadataRetriever and caches
    // it here for the rest of the app run.
    private val dimsCache = HashMap<String, IntArray?>()

    private enum class RenameKind { success, failed, needsConsent }
    private data class RenameAttempt(
        val kind: RenameKind,
        val sender: IntentSender? = null,
    )

    companion object {
        private const val REQ_SAF_PICK = 47
        private const val REQ_MEDIA_DELETE = 48
        private const val REQ_VOICE_SEARCH = 49
        private const val REQ_MEDIA_WRITE = 50

    }

    private val pipSupported: Boolean
        get() = packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE,
        )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleViewIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleViewIntent(intent)
    }

    // ---------------------------------------------------------------------------
    // v1.0.15: "Open with Max Player" — Gallery/Files send ACTION_VIEW.
    // The URI is parked on the intent until Dart declares itself ready (its
    // first getInitialVideo poll, right after the first frame). From then on
    // deliveries go straight over the channel. Resolving/copying the uri
    // happens off the UI thread inside resolveSharedVideo (the same
    // MediaStore/stream machinery used by the document picker).
    private var dartReadyForOpenWith = false

    private fun handleViewIntent(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        reportOpenWith(uri.toString())
    }

    private fun reportOpenWith(uri: String) {
        if (dartReadyForOpenWith) {
            methodChannel?.invokeMethod(
                "openWithVideo",
                mapOf("uri" to uri),
            )
        } else {
            intent?.putExtra("openWithUri", uri)
        }
    }

    /** Resolve + (if needed) copy an "Open with" URI for MPV. */
    private fun resolveOpenWith(uri: String): Map<String, Any?>? {
        val u = Uri.parse(uri) ?: return null
        if (u.scheme == "http" || u.scheme == "https") {
            val m = HashMap<String, Any?>()
            m["path"] = uri
            m["title"] = u.lastPathSegment ?: "Stream"
            m["stream"] = true
            return m
        }
        var path = resolveVideoPath(u)
        if (path == null) path = copyContentToCache(u)
        if (path == null) return null
        val m = HashMap<String, Any?>()
        m["path"] = path
        m["title"] = File(path).name
        m["stream"] = false
        return m
    }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PipActionReceiver.bind(this)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "maxplayer/native",
        )
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToGallery" -> {
                    // v1.0.21 direct Quick Share receive: copy a downloaded
                    // temp file into MediaStore (Movies|Music/MaxPlayer) so
                    // it shows up in the library / gallery — scoped-storage
                    // safe on API 29+, WRITE_EXTERNAL on older.
                    val srcPath = call.argument<String>("path")
                    val displayName = call.argument<String>("name")
                    val kind = call.argument<String>("kind") ?: "video"
                    if (srcPath == null || displayName == null) {
                        result.success(false)
                    } else {
                        Thread {
                            val ok = saveToGallery(srcPath, displayName, kind)
                            runOnUiThread { result.success(ok) }
                        }.start()
                    }
                }

                "getInitialVideo" -> {
                    // "Open with Max Player" cold start: Dart polls once on
                    // the first frame; this flips us into channel-push mode
                    // and returns any parked URI (null otherwise).
                    dartReadyForOpenWith = true
                    val uri = intent?.getStringExtra("openWithUri")
                    intent?.removeExtra("openWithUri")
                    result.success(uri)
                }

                "resolveSharedVideo" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.success(null)
                    } else {
                        // Copy/resolve can block for cloud URIs — thread it,
                        // deliver the result back on the main thread.
                        Thread {
                            val map = resolveOpenWith(uri)
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                }

                "setVolumeKeyIntercept" -> {
                    // v1.0.10: while intercepting, volume keys are consumed
                    // in dispatchKeyEvent and forwarded to Dart instead of
                    // touching the device media stream.
                    interceptVolumeKeys =
                        call.argument<Boolean>("enabled") ?: false
                    result.success(true)
                }

                "enableSensorRotate" -> {
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
                        ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    result.success(true)
                }

                "lockRotation" -> {
                    val landscape = call.argument<Boolean>("landscape") ?: true
                    rotateLocked = true
                    rotateListener?.disable()
                    requestedOrientation = if (landscape)
                        ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    else
                        ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    result.success(true)
                }

                "enterPip" -> {
                    enterPip(
                        call.argument<Int>("w"),
                        call.argument<Int>("h"),
                        result,
                    )
                }

                "updatePipPlaying" -> {
                    pipPlaying = call.argument<Boolean>("playing") ?: true
                    updatePipParams()
                    result.success(true)
                }

                "diagnostics" -> {
                    result.success(
                        hashMapOf(
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "activityAlive" to true,
                        ),
                    )
                }

                "openCastSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_CAST_SETTINGS))
                        result.success(true)
                    } catch (_: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }

                "thumbStripEnsure" -> {
                    val p = call.argument<String>("path")
                    executor.execute {
                        val dir = thumbStripEnsureSync(p)
                        mainHandler.post { result.success(dir) }
                    }
                }

                "whisperAvailable" -> {
                    // Proves the on-device whisper.cpp engine loaded its
                    // native library on this device. Runs off the main
                    // thread (first call may load libwhisper.so).
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
                    // whisper translate task -> English subtitles from any
                    // spoken language.
                    val translate = call.argument<Boolean>("translate") ?: false
                    if (videoPath.isNullOrEmpty()) {
                        result.error("bad_args", "videoPath is required", null)
                    } else if (!Build.SUPPORTED_ABIS.contains("arm64-v8a")) {
                        // The whisper engine ships arm64-only native
                        // libraries. On 32-bit phones decline cleanly BEFORE
                        // any model download - Dart turns the null job id
                        // into a friendly snack.
                        result.success(null)
                    } else {
                        aiCancelled = false
                        val jobId = ++aiJobCounter
                        executor.execute {
                            runAiPipeline(
                                jobId, videoPath, model, language, translate
                            )
                        }
                        result.success(jobId)
                    }
                }

                "aiSubtitleCancel" -> {
                    aiCancelled = true
                    result.success(true)
                }

                // -----------------------------------------------------------------
                // Player/device operations live on `maxplayer/native` (the Dart
                // NativeBridge calls these on _nativeChannel). Keeping them here
                // (not on maxplayer/storage) matters: a call sent to the wrong
                // channel is silently dropped, which is exactly what made
                // rename and voice search appear "dead".
                // -----------------------------------------------------------------
                "renameVideo" -> {
                    // id = the MediaStore _ID (photo_manager's AssetEntity.id).
                    // Building the content URI from the id is far more reliable
                    // than re-resolving the raw path through the DATA column,
                    // which scoped storage often hides.
                    val path = call.argument<String>("path")
                    val id = call.argument<String>("id")
                    val newName = call.argument<String>("newName")
                    if (path.isNullOrEmpty() || newName.isNullOrEmpty()) {
                        result.error("bad_args", "path and newName are required", null)
                    } else {
                        executor.execute {
                            val attempt = renameVideoSync(id, path, newName)
                            mainHandler.post {
                                when (attempt.kind) {
                                    RenameKind.success -> result.success(true)
                                    RenameKind.failed -> result.success(false)
                                    RenameKind.needsConsent -> {
                                        val sender = attempt.sender
                                        if (sender == null || pendingRenameResult != null) {
                                            result.success(false)
                                        } else {
                                            pendingRenameResult = result
                                            pendingRenamePath = path
                                            pendingRenameName = newName
                                            pendingRenameId = id
                                            try {
                                                startIntentSenderForResult(
                                                    sender,
                                                    REQ_MEDIA_WRITE,
                                                    null, 0, 0, 0,
                                                )
                                            } catch (_: Exception) {
                                                pendingRenameResult = null
                                                pendingRenamePath = null
                                                pendingRenameName = null
                                                pendingRenameId = null
                                                result.success(false)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Voice search: in-app SpeechRecognizer first (works without a
                // separate voice-input activity), system dialog as fallback —
                // the old app's exact behaviour.
                // Voice search (Discover mic): the old app launches the SYSTEM
                // speech dialog here (RecognizerIntent) — far more reliable
                // than the in-app recognizer, which silently errors on many
                // devices and produced "Speech recognition is unavailable".
                // The in-app SpeechRecognizer stays available separately via
                // `startVoiceSearch`, exactly like the old app.
                "launchSystemVoiceSearch" -> {
                    launchSystemSpeechIntent(result)
                }

                "startVoiceSearch" -> {
                    startInAppSpeech(result)
                }

                "stopVoiceSearch" -> {
                    stopInAppSpeech()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // -----------------------------------------------------------------
        // Drop 5 storage channel (cloud import + vault + delete-consent).
        // -----------------------------------------------------------------
        storageChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "maxplayer/storage",
        )
        storageChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)

                "vaultDirPath" -> {
                    val dir = File(getExternalFilesDir(null), "Private")
                    try {
                        if (!dir.exists()) dir.mkdirs()
                        result.success(dir.absolutePath)
                    } catch (_: Exception) {
                        result.success(null)
                    }
                }

                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.success(true)
                    } else {
                        try {
                            MediaScannerConnection.scanFile(
                                this,
                                arrayOf(path),
                                null,
                                null,
                            )
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                }

                "videoThumbnail" -> {
                    val path = call.argument<String>("path")
                    executor.execute {
                        val thumb = videoThumbnailSync(path)
                        mainHandler.post { result.success(thumb) }
                    }
                }

                "videoDimensions" -> {
                    val path = call.argument<String>("path")
                    executor.execute {
                        val dims = videoDimensionsSync(path)
                        mainHandler.post { result.success(dims) }
                    }
                }

                "pickVideoDocument" -> {
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
                        } catch (_: Exception) {
                            pendingSafPickResult = null
                            result.success(null)
                        }
                    }
                }

                "saveDocumentToDevice" -> {
                    val sourceUri = call.argument<String>("sourceUri")
                    val cachePath = call.argument<String>("cachePath")
                    val rawName = call.argument<String>("name") ?: "video"
                    val relPath = call.argument<String>("relativePath")
                        ?: "Movies/Max Player"
                    if (sourceUri.isNullOrEmpty() && cachePath.isNullOrEmpty()) {
                        result.error("bad_args", "sourceUri or cachePath is required", null)
                    } else {
                        executor.execute {
                            val saved = saveDocumentToDevice(sourceUri, cachePath, rawName, relPath)
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

                "abortPickCopy" -> {
                    safCopyAborted = true
                    result.success(true)
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
                                                request.userAction.actionIntent.intentSender,
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

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Renames a shared-storage video. On Android 10+ (scoped storage) the
     * rename goes through MediaStore by updating DISPLAY_NAME — a raw
     * File.rename there fails with "protected or in use". On older Android
     * (or app-owned / non-indexed files) the file itself is renamed on disk.
     */
    private fun renameVideoSync(
        id: String?,
        path: String,
        newName: String,
    ): RenameAttempt {
        val file = File(path)
        // Pre-scoped-storage (or a non-indexed file): plain file rename.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return try {
                val parent = file.parentFile ?: return RenameAttempt(RenameKind.failed)
                RenameAttempt(
                    if (file.renameTo(File(parent, newName))) RenameKind.success
                    else RenameKind.failed,
                )
            } catch (_: Exception) {
                RenameAttempt(RenameKind.failed)
            }
        }
        // Build the content URI from the MediaStore id when available (much
        // more reliable than the DATA-column query on scoped storage), then
        // fall back to resolving the raw path.
        val uri = mediaUriForId(id) ?: resolveVideoUri(path)
        if (uri == null) {
            // Not indexed by MediaStore (app-private / vault / Downloads on
            // some builds): fall back to a direct rename, best effort.
            return try {
                val parent = file.parentFile ?: return RenameAttempt(RenameKind.failed)
                RenameAttempt(
                    if (file.renameTo(File(parent, newName))) RenameKind.success
                    else RenameKind.failed,
                )
            } catch (_: Exception) {
                RenameAttempt(RenameKind.failed)
            }
        }
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, newName)
            }
            if (contentResolver.update(uri, values, null, null) > 0) {
                RenameAttempt(RenameKind.success)
            } else {
                RenameAttempt(RenameKind.failed)
            }
        } catch (e: RecoverableSecurityException) {
            // API 29 supplies its own one-shot consent sender.
            RenameAttempt(RenameKind.needsConsent, e.userAction.actionIntent.intentSender)
        } catch (_: SecurityException) {
            // Android 11+ uses a MediaStore write request for shared files.
            RenameAttempt(RenameKind.needsConsent, renameWriteSender(uri))
        } catch (_: Exception) {
            RenameAttempt(RenameKind.failed)
        }
    }

    /** MediaStore content URI from a photo_manager asset id (MediaStore _ID). */
    private fun mediaUriForId(id: String?): Uri? {
        if (id.isNullOrEmpty()) return null
        val parsed = id.toLongOrNull() ?: return null
        if (parsed <= 0) return null
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        else
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        return try {
            ContentUris.withAppendedId(collection, parsed)
        } catch (_: Exception) {
            null
        }
    }

    /**
     * In-app speech recognition (the old app's custom mic). Uses the
     * platform SpeechRecognizer — on-device on Android 12+, Google-backed
     * elsewhere — so it works without a separate voice-input activity. Falls
     * back to the system dialog when recognition is unavailable. Emits
     * onVoiceState / onVoiceRms / onVoicePartial / onVoiceResult /
     * onVoiceError on `maxplayer/native` and completes [result] with the
     * final text (or null).
     */
    private fun startInAppSpeech(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            // The Dart side asks for the mic first; a denied grant here means
            // the system dialog would fail too.
            result.success(null)
            return
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
                    SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
                ) {
                    SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
                } else {
                    SpeechRecognizer.createSpeechRecognizer(this)
                }
                inAppSpeechRecognizer = recognizer

                recognizer.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        mainHandler.post {
                            methodChannel?.invokeMethod("onVoiceState", "listening")
                        }
                    }

                    override fun onBeginningOfSpeech() {
                        mainHandler.post {
                            methodChannel?.invokeMethod("onVoiceState", "speaking")
                        }
                    }

                    override fun onRmsChanged(rmsdB: Float) {
                        mainHandler.post {
                            methodChannel?.invokeMethod("onVoiceRms", rmsdB)
                        }
                    }

                    override fun onBufferReceived(buffer: ByteArray?) {}

                    override fun onEndOfSpeech() {
                        mainHandler.post {
                            methodChannel?.invokeMethod("onVoiceState", "processing")
                        }
                    }

                    override fun onError(error: Int) {
                        mainHandler.post {
                            methodChannel?.invokeMethod("onVoiceError", error)
                            result.success(null)
                        }
                    }

                    override fun onResults(results: Bundle?) {
                        val matches = results
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull()?.trim() ?: ""
                        mainHandler.post {
                            methodChannel?.invokeMethod("onVoiceResult", text)
                            result.success(text.ifEmpty { null })
                        }
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        val matches = partialResults
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull()?.trim()
                        if (!text.isNullOrEmpty()) {
                            mainHandler.post {
                                methodChannel?.invokeMethod("onVoicePartial", text)
                            }
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                    )
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                    putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
                    putExtra(
                        RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                        1800L
                    )
                    putExtra(
                        RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                        1800L
                    )
                }
                recognizer.startListening(intent)
            } catch (_: Exception) {
                launchSystemSpeechIntent(result)
            }
        }
    }

    private fun launchSystemSpeechIntent(result: MethodChannel.Result) {
        try {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to search\u2026")
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            }
            if (intent.resolveActivity(packageManager) == null) {
                result.success(null)
                return
            }
            pendingVoiceSearchResult = result
            startActivityForResult(intent, REQ_VOICE_SEARCH)
        } catch (_: Exception) {
            pendingVoiceSearchResult = null
            result.success(null)
        }
    }

    private fun stopInAppSpeech() {
        mainHandler.post {
            try {
                inAppSpeechRecognizer?.stopListening()
                inAppSpeechRecognizer?.destroy()
                inAppSpeechRecognizer = null
            } catch (_: Exception) {
            }
        }
    }

    private fun renameWriteSender(uri: Uri): IntentSender? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            MediaStore.createWriteRequest(
                contentResolver,
                arrayListOf(uri),
            ).intentSender
        } catch (_: Exception) {
            null
        }
    }

    private fun finishRename(granted: Boolean) {
        val pending = pendingRenameResult
        val path = pendingRenamePath
        val name = pendingRenameName
        val id = pendingRenameId
        pendingRenameResult = null
        pendingRenamePath = null
        pendingRenameName = null
        pendingRenameId = null
        if (pending == null) return
        if (!granted || path.isNullOrEmpty() || name.isNullOrEmpty()) {
            pending.success(false)
            return
        }
        executor.execute {
            val attempt = renameVideoSync(id, path, name)
            mainHandler.post {
                pending.success(attempt.kind == RenameKind.success)
            }
        }
    }

    private fun enterPip(
        width: Int?,
        height: Int?,
        result: MethodChannel.Result,
    ) {
        if (!pipSupported || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }

        try {
            val w = (width ?: 16).coerceAtLeast(1)
            val h = (height ?: 9).coerceAtLeast(1)
            val raw = w.toFloat() / h.toFloat()
            val ratio = raw.coerceIn(0.42f, 2.38f)

            val builder = PictureInPictureParams.Builder()
                .setAspectRatio(
                    Rational((ratio * 1000).toInt(), 1000),
                )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setSeamlessResizeEnabled(true)
                builder.setAutoEnterEnabled(false)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val view = window.decorView
                builder.setSourceRectHint(
                    Rect(
                        0,
                        0,
                        view.width.coerceAtLeast(1),
                        view.height.coerceAtLeast(1),
                    ),
                )
            }

            addPipAction(builder)
            result.success(enterPictureInPictureMode(builder.build()))
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun addPipAction(builder: PictureInPictureParams.Builder) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        builder.setActions(listOf(
            RemoteAction(
                Icon.createWithResource(
                    this,
                    if (pipPlaying) android.R.drawable.ic_media_pause
                    else android.R.drawable.ic_media_play,
                ),
                if (pipPlaying) "Pause" else "Play",
                if (pipPlaying) "Pause video" else "Play video",
                PendingIntent.getBroadcast(
                    this,
                    4101,
                    Intent(this, PipActionReceiver::class.java).apply {
                        action = PipActionReceiver.ACTION_TOGGLE
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            ),
        ))
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isInPictureInPictureMode) {
            return
        }
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setSeamlessResizeEnabled(true)
            builder.setAutoEnterEnabled(false)
        }
        addPipAction(builder)
        setPictureInPictureParams(builder.build())
    }

    fun handlePipToggle() {
        methodChannel?.invokeMethod("pipToggle", null)
    }

    // ---------------------------------------------------------------------------
    // Sensor-driven rotation (MX Player / VLC style): the player rotates by
    // accelerometer regardless of the phone's system auto-rotate switch.
    // ---------------------------------------------------------------------------

    private var rotateListener: OrientationEventListener? = null
    private var rotateLocked = false

    private fun ensureRotateListener() {
        if (rotateListener != null) return
        rotateListener = object : OrientationEventListener(
            this, SensorManager.SENSOR_DELAY_NORMAL
        ) {
            override fun onOrientationChanged(angle: Int) {
                if (angle == ORIENTATION_UNKNOWN || rotateLocked) return
                val target = when {
                    angle in 45..134 ->
                        ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                    angle in 225..314 ->
                        ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    else ->
                        ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
                if (requestedOrientation != target) requestedOrientation = target
            }
        }
    }

    // v1.0.10 device-independent volume: while a player screen is visible,
    // hardware volume keys adjust the in-app (mpv) volume, not the device
    // media stream. Each key press is forwarded to Dart, which owns the
    // level (AppVolume store) and shows the HUD.
    private var interceptVolumeKeys = false

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (interceptVolumeKeys && event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    methodChannel?.invokeMethod("volumeKey", "up")
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    methodChannel?.invokeMethod("volumeKey", "down")
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }

    // ---------------------------------------------------------------------------
    // v1.0.21 direct Quick Share — receiver-side gallery insert.
    private fun saveToGallery(srcPath: String, displayName: String, kind: String): Boolean {
        return try {
            val isAudio = kind == "audio"
            val mime = run {
                val ext = displayName.substringAfterLast('.', "").lowercase()
                android.webkit.MimeTypeMap.getSingleton()
                    .getMimeTypeFromExtension(ext)
                    ?: (if (isAudio) "audio/*" else "video/*")
            }
            val collection =
                if (isAudio) {
                    if (Build.VERSION.SDK_INT >= 29)
                        MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                } else {
                    if (Build.VERSION.SDK_INT >= 29)
                        MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    else MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                if (Build.VERSION.SDK_INT >= 29) {
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        (if (isAudio) "Music/" else "Movies/") + "MaxPlayer",
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }
            val uri = contentResolver.insert(collection, values) ?: return false
            val wrote = contentResolver.openOutputStream(uri)?.use { out ->
                File(srcPath).inputStream().use { it.copyTo(out) }
                true
            } ?: false
            if (!wrote) {
                contentResolver.delete(uri, null, null)
                return false
            }
            if (Build.VERSION.SDK_INT >= 29) {
                val done = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                contentResolver.update(uri, done, null, null)
            }
            android.util.Log.i("MainActivity", "saveToGallery ok: $uri")
            true
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "saveToGallery failed: $e")
            false
        }
    }

    override fun onDestroy() {
        rotateLocked = false
        rotateListener?.disable()
        rotateListener = null
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        super.onDestroy()
    }

    // ---------------------------------------------------------------------------
    // Scrub thumbnail strip: N small JPEG frames for the seek-preview bubble.
    // ---------------------------------------------------------------------------

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
                    dir.setLastModified(System.currentTimeMillis())
                    return dir.absolutePath
                }
            }
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(path)
                val durMs = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION
                )?.toLongOrNull() ?: 0L
                if (durMs <= 0L) return null
                dir.mkdirs()
                for (i in 0 until count) {
                    val us = durMs * 1000L * i / (count - 1)
                    val thumb = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        try {
                            retriever.getScaledFrameAtTime(
                                us,
                                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                160,
                                90,
                            )
                        } catch (_: Throwable) {
                            retriever.getFrameAtTime(
                                us,
                                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                            )?.let { scaleToWidth(it, 160) }
                        }
                    } else {
                        retriever.getFrameAtTime(
                            us,
                            MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                        )?.let { scaleToWidth(it, 160) }
                    }
                    if (thumb != null) {
                        FileOutputStream(File(dir, "f_%03d.jpg".format(i)))
                            .use { out ->
                                thumb.compress(Bitmap.CompressFormat.JPEG, 65, out)
                            }
                        thumb.recycle()
                    }
                }
            } finally {
                retriever.release()
            }
            pruneThumbStrips()
            return dir.absolutePath
        } catch (_: Throwable) {
            return null
        }
    }

    private fun thumbStripDirs(): List<File> {
        val list = cacheDir.listFiles() ?: return emptyList()
        return list.filter { it.isDirectory && it.name.startsWith("thumbstrip_") }
    }

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

    private fun scaleToWidth(src: Bitmap, targetWidth: Int): Bitmap {
        if (src.width <= targetWidth) return src
        val targetHeight =
            (src.height * (targetWidth.toFloat() / src.width)).toInt()
                .coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, targetWidth, targetHeight, true)
    }

    private fun md5(s: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(s.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    // -----------------------------------------------------------------------
    // v29: real video dimensions (quality badge)
    // -----------------------------------------------------------------------

    /**
     * Real codec dimensions of [path] via MediaMetadataRetriever, with the
     * rotation already applied so portrait videos report their true
     * width/height. Cached per path for the rest of the app run. Null when
     * the file can't be decoded (or is a network stream).
     */
    private fun videoDimensionsSync(path: String?): HashMap<String, Int>? {
        if (path.isNullOrEmpty() || path.startsWith("http")) return null
        if (dimsCache.containsKey(path)) {
            val cached = dimsCache[path] ?: return null
            return hashMapOf("w" to cached[0], "h" to cached[1])
        }
        val retriever = MediaMetadataRetriever()
        val dims = try {
            retriever.setDataSource(path)
            var w = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            var h = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            val rot = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            if (rot == 90 || rot == 270) {
                val t = w
                w = h
                h = t
            }
            if (w > 0 && h > 0) intArrayOf(w, h) else null
        } catch (_: Throwable) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
        }
        dimsCache[path] = dims
        return if (dims != null) hashMapOf("w" to dims[0], "h" to dims[1]) else null
    }

    // ---------------------------------------------------------------------------
    // Drop 5: system document picker (cloud import) + vault helpers
    // ---------------------------------------------------------------------------

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SAF_PICK) {
            finishSafPick(resultCode, data)
        } else if (requestCode == REQ_MEDIA_DELETE) {
            finishMediaDelete(resultCode == RESULT_OK)
        } else if (requestCode == REQ_MEDIA_WRITE) {
            finishRename(resultCode == RESULT_OK)
        } else if (requestCode == REQ_VOICE_SEARCH) {
            val pending = pendingVoiceSearchResult
            pendingVoiceSearchResult = null
            if (resultCode == RESULT_OK && data != null) {
                val matches =
                    data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val query = matches?.firstOrNull()?.trim() ?: ""
                pending?.success(query)
            } else {
                pending?.success(null)
            }
        }
    }

    /**
     * Answer for the ACTION_OPEN_DOCUMENT pick. Local device files resolve
     * to a real path (instant, zero copy); cloud/provider documents (Google
     * Drive & friends) are stream-copied into the app cache first so MPV can
     * open them. The original content:// URI is kept in the result so Dart
     * can offer "Save to device" afterwards.
     */
    private fun finishSafPick(resultCode: Int, data: Intent?) {
        val pending = pendingSafPickResult
        pendingSafPickResult = null
        if (pending == null) return
        safCopyAborted = false
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
                // Stream with progress events for the import bar, honoring
                // the dialog's Cancel via the abort flag.
                resolved = copyContentToCache(uri) { done, total ->
                    mainHandler.post {
                        storageChannel?.invokeMethod(
                            "onPickProgress",
                            hashMapOf("done" to done, "total" to total)
                        )
                    }
                }
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

    private fun copyContentToCache(uri: Uri): String? {
        return copyContentToCache(uri, null)
    }

    /**
     * Progress + abortable variant. [onProgress] gets (bytesDone,
     * bytesTotal) about every 100 ms while streaming; the total is 0 when
     * the provider does not report a size. Only this pick-driven path honors
     * the abort flag.
     */
    private fun copyContentToCache(
        uri: Uri,
        onProgress: ((Long, Long) -> Unit)?
    ): String? {
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
            val total = queryDocumentSize(uri)
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(out).use { output ->
                    if (onProgress == null) {
                        input.copyTo(output)
                    } else {
                        val buf = ByteArray(128 * 1024)
                        var doneBytes = 0L
                        var lastEmit = 0L
                        while (true) {
                            if (safCopyAborted) break
                            val n = input.read(buf)
                            if (n < 0) break
                            output.write(buf, 0, n)
                            doneBytes += n
                            val now = SystemClock.elapsedRealtime()
                            if (now - lastEmit >= 100) {
                                lastEmit = now
                                onProgress.invoke(doneBytes, total)
                            }
                        }
                        onProgress.invoke(doneBytes, total)
                    }
                }
            } ?: return null
            val aborted = onProgress != null && safCopyAborted
            if (aborted || out.length() <= 0) {
                out.delete()
                null
            } else {
                out.absolutePath
            }
        } catch (_: Exception) {
            null
        }
    }

    /** Provider-reported size of a document in bytes (0 = unknown). */
    private fun queryDocumentSize(uri: Uri): Long {
        return try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.SIZE), null, null, null
            )?.use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else 0L } ?: 0L
        } catch (_: Exception) {
            0L
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Turns a content:// or file:// URI into a real filesystem path MPV can
     * open. Strategies: file:// -> direct path; MediaStore DATA column;
     * ExternalStorageProvider document URIs ("primary:Downloads/x.mp4").
     */
    private fun resolveVideoPath(uri: Uri): String? {
        when (uri.scheme) {
            "file" -> return uri.path
            "content" -> {
                try {
                    contentResolver.query(
                        uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null
                    )?.use { c ->
                        if (c.moveToFirst()) {
                            val p = c.getString(0)
                            if (!p.isNullOrEmpty()) return p
                        }
                    }
                } catch (_: Exception) {
                    // fall through to document parsing
                }
                if (uri.authority == "com.android.externalstorage.documents") {
                    val doc = uri.lastPathSegment ?: return null
                    val parts = doc.split(":", limit = 2)
                    if (parts.size == 2) {
                        val decoded = Uri.decode(parts[1])
                        return if (parts[0].equals("primary", ignoreCase = true)) {
                            "/storage/emulated/0/$decoded"
                        } else {
                            "/storage/${parts[0]}/$decoded"
                        }
                    }
                }
            }
        }
        return null
    }

    /** MediaStore content URI for a real video path (null when not indexed). */
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
     * Completes the delete-consent flow (REQ_MEDIA_DELETE). API 30+ deleted
     * everything inside createDeleteRequest itself; API 29 granted one
     * file's consent, so the pending list is retried once here.
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

    private fun openDocumentInput(
        sourceUri: String?,
        cachePath: String?
    ): java.io.InputStream? {
        if (!cachePath.isNullOrEmpty()) {
            try {
                val f = File(cachePath)
                if (f.exists()) return FileInputStream(f)
            } catch (_: Exception) {}
        }
        if (!sourceUri.isNullOrEmpty()) {
            try {
                contentResolver.openInputStream(Uri.parse(sourceUri))
                    ?.let { return it }
            } catch (_: Exception) {}
        }
        return null
    }

    /**
     * Permanent copy of a picked cloud video into Movies/Max Player. API 29+
     * goes through MediaStore (no permission needed for our own insert);
     * older versions write the public Movies directory directly and ping the
     * media scanner so gallery apps see it at once.
     */
    private fun saveDocumentToDevice(
        sourceUri: String?,
        cachePath: String?,
        rawName: String,
        relativePath: String
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
                    put(MediaStore.Video.Media.RELATIVE_PATH, relativePath)
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
                val collection = MediaStore.Video.Media.getContentUri(
                    MediaStore.VOLUME_EXTERNAL
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
                out["location"] = "$relativePath/$name"
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
        } catch (_: Exception) {
            null
        }
    }

    /** _data column for a MediaStore row we just wrote (null on stricter builds). */
    private fun queryDataColumn(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null
            )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        } catch (_: Exception) {
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
     * Cached thumbnail for a vault video: reuse the cache entry when it
     * exists, otherwise grab a small frame through MediaMetadataRetriever
     * and write it under cacheDir/thumbs/<md5>.jpg. Null when undecodable.
     */
    private fun videoThumbnailSync(path: String?): String? {
        if (path.isNullOrEmpty()) return null
        val src = File(path)
        if (!src.exists()) return null
        val out = File(File(cacheDir, "thumbs"), md5(path) + ".jpg")
        if (out.exists() && out.length() > 0) return out.absolutePath
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val durMs = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: 0L
            val seekUs = if (durMs > 2000L) 1000000L else durMs * 1000L / 2L
            val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                try {
                    retriever.getScaledFrameAtTime(
                        seekUs,
                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                        320,
                        180,
                    )
                } catch (_: Throwable) {
                    retriever.getFrameAtTime(
                        seekUs,
                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    )
                }
            } else {
                retriever.getFrameAtTime(
                    seekUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                )
            }
            if (frame == null) {
                null
            } else {
                out.parentFile?.mkdirs()
                FileOutputStream(out).use { o ->
                    frame.compress(Bitmap.CompressFormat.JPEG, 75, o)
                }
                frame.recycle()
                out.absolutePath
            }
        } catch (_: Throwable) {
            null
        } finally {
            try { retriever.release() } catch (_: Throwable) {}
        }
    }

    // -----------------------------------------------------------------------
    // AI subtitles pipeline: on-device whisper.cpp (offline & free after the
    // one-time model download). Ported from the old app.
    //
    //   video -> [MediaExtractor + MediaCodec] 16 kHz mono WAV (on device)
    //         -> speech gating (on device) -> speech slices <= 30 s
    //         -> whisper.cpp transcribe (on device) -> segments to Dart.
    // -----------------------------------------------------------------------

    private fun aiProgress(jobId: Int, stage: String, percent: Int) {
        mainHandler.post {
            methodChannel?.invokeMethod(
                "onAiProgress",
                hashMapOf("job" to jobId, "stage" to stage, "percent" to percent)
            )
        }
    }

    // "tiny" stays removed for good (user call: keep only accurate models).
    // Speed now comes from all-core threading PLUS the quantized "fast"
    // model. Unknown ids (including a "tiny" id saved by older builds)
    // fall back to "base".
    // v1.0.1+9: "fast" = the QUANTIZED base model (ggml-base-q5_1, 59.7 MB)
    // — ~1.5x quicker than fp16 base and 60% smaller to download, with a
    // barely measurable subtitle-accuracy delta. whisper.cpp loads it
    // through the same ggml loader, no engine change needed.
    private fun modelFileFor(name: String): File {
        return when (name) {
            "fast" -> File(filesDir, "models/ggml-base-q5_1.bin")
            "small" -> File(filesDir, "models/ggml-small.bin")
            else -> File(filesDir, "models/ggml-base.bin")
        }
    }

    private fun modelUrlFor(name: String): String {
        return when (name) {
            "fast" ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin"
            "small" ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
            else ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
        }
    }

    private fun aiDone(jobId: Int, segments: ArrayList<HashMap<String, Any>>) {
        mainHandler.post {
            methodChannel?.invokeMethod(
                "onAiSubtitleDone",
                hashMapOf("job" to jobId, "segments" to segments)
            )
        }
    }

    private fun aiFailed(jobId: Int, message: String) {
        mainHandler.post {
            methodChannel?.invokeMethod(
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

            // 3. Transcribe with whisper.cpp (offline), speech-gated: the
            // 16 kHz track is first split into voiced spans and only those
            // are sent to whisper. Long silent stretches of a video are
            // skipped entirely, which is FASTER and CLEANER (whisper used
            // to answer silence with "music" hallucinations). Music is
            // never treated as silence, so speech over loud background
            // music still gets transcribed.
            aiProgress(jobId, "transcribing", 0)
            val segments = ArrayList<HashMap<String, Any>>()
            runBlocking {
                var model: WhisperModel? = null
                try {
                    model = Whisper.loadModel(this@MainActivity, modelFile.absolutePath)
                    // v1.0.1+10 memory safety: the old readWavPcm loaded the
                    // WHOLE extracted WAV into RAM (~700 MB peak for a 3 h
                    // movie) and Android killed the app right around audio
                    // extraction — the "closes by itself mid-generation"
                    // bug. Now the audio is STREAMED: a few MB peak for
                    // any duration.
                    val vadFrame = 400
                    val spans = speechSpansFromRms(
                        wavRmsEnergies(wav, vadFrame), vadFrame)
                    // spans empty = no voice anywhere -> empty result, and
                    // Dart shows its friendly "No speech detected" snack.
                    spans.forEachIndexed { i, span ->
                        if (aiCancelled) return@forEachIndexed
                        val spanWav = File(cacheDir, "ai_span_${jobId}_$i.wav")
                        try {
                            writeSpanWavFromFile(wav, spanWav, span[0], span[1])
                            // The user can pin a language ("hi", "ur", "en",
                            // ...) in the Generate dialog; "auto" = detect
                            // it. Pinning is noticeably more accurate.
                            val res = Whisper.transcribe(
                                model,
                                spanWav.absolutePath,
                                WhisperConfig(
                                    language = language,
                                    translate = translate,
                                    // Use every core the phone offers -
                                    // whisper.cpp scales well to 8 threads.
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
            // those bytes to the 16-bit resampler produced noise.
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

    /**
     * Per-frame RMS energies of a 16 kHz mono 16-bit WAV, computed in a
     * STREAMED pass (v1.0.1+10): a few MB peak for ANY duration — replaces
     * the full-file read that OOM-killed long-movie generations.
     */
    private fun wavRmsEnergies(wav: File, frame: Int): DoubleArray {
        val guessed = (((wav.length() - 44) / 2) / frame).toInt().coerceAtLeast(0)
        val rms = DoubleArray(guessed)
        val frameBytes = frame * 2
        val block = ByteArray(2 * 1024 * 1024)
        val carry = ByteArray(frameBytes)
        var carryLen = 0
        var frameIdx = 0
        RandomAccessFile(wav, "r").use { raf ->
            raf.seek(44)
            while (true) {
                val n = raf.read(block)
                if (n <= 0) break
                var p = 0
                while (p < n) {
                    val take = minOf(frameBytes - carryLen, n - p)
                    System.arraycopy(block, p, carry, carryLen, take)
                    carryLen += take
                    p += take
                    if (carryLen == frameBytes) {
                        var sum = 0.0
                        var j = 0
                        while (j < frame) {
                            val idx = j * 2
                            val v = ((carry[idx + 1].toInt() shl 8) or
                                (carry[idx].toInt() and 0xFF)).toShort().toInt()
                            sum += v * v
                            j++
                        }
                        if (frameIdx < rms.size) {
                            rms[frameIdx] = kotlin.math.sqrt(sum / frame)
                        }
                        frameIdx++
                        carryLen = 0
                    }
                }
            }
        }
        return if (frameIdx == rms.size) rms else rms.copyOf(frameIdx)
    }

    /**
     * v1.0.1+10: writes samples [fromSample, toSample) of [srcWav] as a
     * standalone 16 kHz mono 16-bit WAV, copying 64 KB at a time — peak
     * memory one span chunk, not the whole track.
     */
    private fun writeSpanWavFromFile(
        srcWav: File, out: File, fromSample: Int, toSample: Int,
    ) {
        val from = fromSample * 2L
        val to = toSample * 2L
        val rafOut = RandomAccessFile(out, "rw")
        try {
            rafOut.setLength(0)
            writeWavHeader(rafOut, 16000, to - from)
            RandomAccessFile(srcWav, "r").use { rafIn ->
                rafIn.seek(44 + from)
                val buf = ByteArray(64 * 1024)
                var left = to - from
                while (left > 0) {
                    val n = rafIn.read(buf, 0, minOf(buf.size.toLong(), left).toInt())
                    if (n <= 0) break
                    rafOut.write(buf, 0, n)
                    left -= n
                }
            }
        } finally {
            rafOut.close()
        }
    }

    /**
     * Speech-gate for the AI pipeline (v1.0.1+10, streamed): takes the
     * per-25 ms frame RMS energies computed by [wavRmsEnergies] and
     * returns voiced sample ranges — padded, gap-merged and chunked to
     * <=30 s. IDENTICAL heuristics to the previous in-memory version:
     * conservative threshold (~2.2x the adaptive noise floor with a low
     * absolute floor), music is never gated out.
     */
    private fun speechSpansFromRms(rms: DoubleArray, frame: Int): List<IntArray> {
        val totalFrames = rms.size
        val totalSamples = totalFrames * frame
        if (totalFrames < 8) return emptyList() // under 0.2 s of audio at all

        val sorted = rms.sorted()
        val noise = sorted[(totalFrames * 0.2).toInt().coerceIn(0, totalFrames - 1)]
        val threshold = maxOf(noise * 2.2, 260.0)

        val raw = mutableListOf<IntArray>()
        var start = -1
        var i = 0
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
}
