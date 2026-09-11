package com.maxplayer.maxplayer

import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.app.RemoteAction
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.os.Build
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private var rotationLocked = false
    private var pipPlaying = true
    private var methodChannel: MethodChannel? = null

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
                "toggleRotationLock" -> result.success(toggleRotationLock())

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

                else -> result.notImplemented()
            }
        }
    }

    /*
     * Rotate button = rotation lock.
     * Unlocking returns control to Android's sensor orientation handling.
     * No raw sensor-angle mapping is used, so landscape left/right cannot be
     * accidentally reversed by the app.
     */
    private fun toggleRotationLock(): Boolean {
        if (!rotationLocked) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
            rotationLocked = true
        } else {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR
            rotationLocked = false
        }
        return rotationLocked
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

    override fun onDestroy() {
        rotationLocked = false
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        super.onDestroy()
    }
}
