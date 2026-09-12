package com.maxplayer.maxplayer

import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.app.RemoteAction
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.hardware.SensorManager
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Rational
import android.view.OrientationEventListener
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {

    private var pipPlaying = true
    private var methodChannel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

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
}
