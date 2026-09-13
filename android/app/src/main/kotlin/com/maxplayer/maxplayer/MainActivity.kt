package com.maxplayer.maxplayer

import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.app.RecoverableSecurityException
import android.app.RemoteAction
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.hardware.SensorManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.speech.RecognizerIntent
import android.util.Rational
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

    companion object {
        private const val REQ_SAF_PICK = 47
        private const val REQ_MEDIA_DELETE = 48
        private const val REQ_VOICE_SEARCH = 49
    }

    private val pipSupported: Boolean
        get() = packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE,
        )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PipActionReceiver.bind(this)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "maxplayer/native",
        )
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
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

                "setBackgroundAudio" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        PlaybackKeepAliveService.start(
                            this,
                            call.argument<String>("title") ?: "MaxPlayer",
                        )
                    } else {
                        PlaybackKeepAliveService.stop(this)
                    }
                    result.success(true)
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

                "getMediaVolume" -> {
                    // DEVICE media volume (the player's swipe drives this,
                    // like MX Player / the old app, so it can always reach
                    // the phone's true maximum loudness).
                    try {
                        val am =
                            getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            .coerceAtLeast(1)
                        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                        result.success(hashMapOf("level" to cur, "max" to max))
                    } catch (_: Exception) {
                        result.success(hashMapOf("level" to 1, "max" to 1))
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

                "renameVideo" -> {
                    val path = call.argument<String>("path")
                    val newName = call.argument<String>("newName")
                    if (path.isNullOrEmpty() || newName.isNullOrEmpty()) {
                        result.error("bad_args", "path and newName are required", null)
                    } else {
                        executor.execute {
                            val ok = renameVideoSync(path, newName)
                            mainHandler.post { result.success(ok) }
                        }
                    }
                }

                "launchSystemVoiceSearch" -> {
                    try {
                        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                            .apply {
                                putExtra(
                                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                                )
                                putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to search\u2026")
                                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
                            }
                        pendingVoiceSearchResult = result
                        startActivityForResult(intent, REQ_VOICE_SEARCH)
                    } catch (_: Exception) {
                        pendingVoiceSearchResult = null
                        result.success(null)
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
    private fun renameVideoSync(path: String, newName: String): Boolean {
        val file = File(path)
        // Pre-scoped-storage (or a non-indexed file): plain file rename.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return try {
                val parent = file.parentFile ?: return false
                file.renameTo(File(parent, newName))
            } catch (_: Exception) {
                false
            }
        }
        val uri = resolveVideoUri(path)
        if (uri == null) {
            // Not indexed by MediaStore (app-private / vault / Downloads on
            // some builds): fall back to a direct rename, best effort.
            return try {
                val parent = file.parentFile ?: return false
                file.renameTo(File(parent, newName))
            } catch (_: Exception) {
                false
            }
        }
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, newName)
            }
            contentResolver.update(uri, values, null, null) > 0
        } catch (_: RecoverableSecurityException) {
            // API 29 needs user consent for this update — fall back to a
            // direct rename attempt (legacy-storage devices often allow it).
            try {
                val parent = file.parentFile ?: return false
                file.renameTo(File(parent, newName))
            } catch (_: Exception) {
                false
            }
        } catch (_: Exception) {
            false
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

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
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

    // ---------------------------------------------------------------------------
    // Drop 5: system document picker (cloud import) + vault helpers
    // ---------------------------------------------------------------------------

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SAF_PICK) {
            finishSafPick(resultCode, data)
        } else if (requestCode == REQ_MEDIA_DELETE) {
            finishMediaDelete(resultCode == RESULT_OK)
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

    // Only the accurate models stay ("tiny" removed for good). Speed comes
    // from all-core threading instead of a weaker model. Unknown ids
    // (including a "tiny" id saved by older builds) fall back to "base".
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
                    val pcmData = readWavPcm(wav) ?: ByteArray(0)
                    val spans = speechSpans(pcmData)
                    // spans empty = no voice anywhere -> empty result, and
                    // Dart shows its friendly "No speech detected" snack.
                    spans.forEachIndexed { i, span ->
                        if (aiCancelled) return@forEachIndexed
                        val spanWav = File(cacheDir, "ai_span_${jobId}_$i.wav")
                        try {
                            writeSpanWav(spanWav, pcmData, span[0], span[1])
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
     * Speech-gate for the AI pipeline: finds voiced spans in 16 kHz mono
     * 16-bit PCM (raw little-endian bytes, no header) and returns them as
     * [startSample, endSample) pairs - padded, gap-merged and chunked to
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
}
