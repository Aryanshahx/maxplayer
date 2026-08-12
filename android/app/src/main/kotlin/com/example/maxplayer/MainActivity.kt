package com.example.maxplayer

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
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
 *    brightness for the player's left-half swipe gesture. This only changes
 *    THIS window's brightness (WindowManager.LayoutParams), so unlike the
 *    screen_brightness plugins it needs no WRITE_SETTINGS permission.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "maxplayer/native"
    private val executor = Executors.newFixedThreadPool(4)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
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
                    else -> result.notImplemented()
                }
            }
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
        executor.shutdown()
        super.onDestroy()
    }
}
