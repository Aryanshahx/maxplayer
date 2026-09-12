package com.maxplayer.maxplayer

import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.app.RecoverableSecurityException
import android.app.RemoteAction
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.hardware.SensorManager
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
import android.util.Rational
import android.view.OrientationEventListener
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {

    private var pipPlaying = true
    private var methodChannel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

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

    companion object {
        private const val REQ_SAF_PICK = 47
        private const val REQ_MEDIA_DELETE = 48
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

                else -> result.notImplemented()
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
}
