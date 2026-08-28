package com.hypertechlabs.maxplayer

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

object ThumbnailExtractor {

    private val cache = mutableMapOf<String, String>()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun getCachedThumbnail(context: Context, videoPath: String): String? {
        val cacheKey = videoPath.md5()
        
        if (cache.containsKey(cacheKey)) {
            val cachedPath = cache[cacheKey]!!
            if (File(cachedPath).exists()) return cachedPath
        }

        val thumbDir = File(context.filesDir, "thumbnails")
        if (!thumbDir.exists()) thumbDir.mkdirs()

        val thumbFile = File(thumbDir, "$cacheKey.jpg")
        return if (thumbFile.exists()) {
            cache[cacheKey] = thumbFile.absolutePath
            thumbFile.absolutePath
        } else null
    }

    fun extractAsync(context: Context, videoPath: String, callback: (String?) -> Unit) {
        scope.launch {
            val cached = getCachedThumbnail(context, videoPath)
            if (cached != null) {
                withContext(Dispatchers.Main) { callback(cached) }
                return@launch
            }

            val thumbnail = extractThumbnail(context, videoPath)
            withContext(Dispatchers.Main) { callback(thumbnail) }
        }
    }

    private fun extractThumbnail(context: Context, videoPath: String): String? {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(videoPath)
            
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val timeUs = (duration * 1000 * 0.1).toLong()
            
            val bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            retriever.release()

            bitmap?.let {
                val cacheKey = videoPath.md5()
                val thumbDir = File(context.filesDir, "thumbnails")
                val thumbFile = File(thumbDir, "$cacheKey.jpg")

                FileOutputStream(thumbFile).use { out ->
                    it.compress(Bitmap.CompressFormat.JPEG, 85, out)
                }
                
                cache[cacheKey] = thumbFile.absolutePath
                thumbFile.absolutePath
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun String.md5(): String {
        val md = MessageDigest.getInstance("MD5")
        val digest = md.digest(toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun preloadThumbnails(context: Context, videoPaths: List<String>) {
        scope.launch {
            videoPaths.forEach { path ->
                if (getCachedThumbnail(context, path) == null) {
                    extractThumbnail(context, path)
                }
            }
        }
    }
}
