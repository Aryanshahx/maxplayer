package com.maxplayer.maxplayer

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val CHANNEL = "maxplayer/native"
    }

    private var rotationLocked = false
    private var pipPlaying = true
    private var methodChannel: MethodChannel? = null

    private val pipSupported: Boolean
        get() = packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE,
        )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation =
            ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "toggleRotationLock" ->
                    result.success(toggleRotationLock())

                "enterPip" ->
                    enterPip(
                        call.argument<Int>("w"),
                        call.argument<Int>("h"),
                        result,
                    )

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
                        result.success(false)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == PipActionReceiver.ACTION_PIP_TOGGLE_ACTIVITY) {
            methodChannel?.invokeMethod("pipToggle", null)
        }
    }

    private fun toggleRotationLock(): Boolean {
        if (!rotationLocked) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
            rotationLocked = true
        } else {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
            rotationLocked = false
        }
        return rotationLocked
    }

    private fun buildPipAction(): RemoteAction {
        val broadcast = Intent(this, PipActionReceiver::class.java).apply {
            action = PipActionReceiver.ACTION_TOGGLE
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            4101,
            broadcast,
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE,
        )

        val icon = if (pipPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }

        return RemoteAction(
            Icon.createWithResource(this, icon),
            if (pipPlaying) "Pause" else "Play",
            if (pipPlaying) "Pause video" else "Play video",
            pendingIntent,
        )
    }

    private fun pipBuilder(
        width: Int?,
        height: Int?,
    ): PictureInPictureParams.Builder {
        val w = (width ?: 16).coerceAtLeast(1)
        val h = (height ?: 9).coerceAtLeast(1)
        val ratio = (w.toFloat() / h.toFloat()).coerceIn(0.42f, 2.38f)

        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational((ratio * 1000).toInt(), 1000))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setActions(listOf(buildPipAction()))
        }
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
        return builder
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
            result.success(
                enterPictureInPictureMode(pipBuilder(width, height).build()),
            )
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            !isInPictureInPictureMode
        ) return

        try {
            setPictureInPictureParams(pipBuilder(16, 9).build())
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        rotationLocked = false
        methodChannel = null
        requestedOrientation =
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        super.onDestroy()
    }
}
