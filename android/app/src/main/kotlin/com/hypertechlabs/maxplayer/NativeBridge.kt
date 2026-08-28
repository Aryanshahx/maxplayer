package com.hypertechlabs.maxplayer

import android.content.Context
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class NativeBridge(private val context: Context, flutterEngine: FlutterEngine) {

    companion object {
        const val CHANNEL = "maxplayer/native"
    }

    init {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageRoots" -> result.success(getStorageRoots())
                "getThumbnail" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val thumb = ThumbnailExtractor.getCachedThumbnail(context, path)
                        if (thumb != null) {
                            result.success(thumb)
                        } else {
                            ThumbnailExtractor.extractAsync(context, path) { result.success(it) }
                        }
                    } else {
                        result.success(null)
                    }
                }
                "preloadThumbnails" -> {
                    val paths = call.argument<List<String>>("paths")
                    if (paths != null) ThumbnailExtractor.preloadThumbnails(context, paths)
                    result.success(null)
                }
                "launchVoiceSearch" -> {
                    try {
                        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                            putExtra(RecognizerIntent.EXTRA_PROMPT, "Search videos...")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getStorageRoots(): List<String> {
        val roots = mutableListOf("/storage/emulated/0")
        context.getExternalFilesDirs(null)?.forEach { file ->
            file?.absolutePath?.let { path ->
                val root = path.substring(0, path.indexOf("/Android"))
                if (!roots.contains(root)) roots.add(root)
            }
        }
        return roots
    }
}
