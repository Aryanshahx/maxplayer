package com.maxplayer.maxplayer

import android.app.ActivityInfo
import android.app.OrientationEventListener
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private var orientationListener: OrientationEventListener? = null
    private var autoRotateEnabled = false

    private val pipSupported: Boolean
        get() = packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "maxplayer/native",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> enterPip(call.argument<Int>("w"), call.argument<Int>("h"), result)
                "startAutoRotate" -> {
                    startAutoRotate()
                    result.success(true)
                }
                "stopAutoRotate" -> {
                    stopAutoRotate()
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

    private fun startAutoRotate() {
        if (autoRotateEnabled) return
        autoRotateEnabled = true
        if (orientationListener == null) {
            orientationListener = object : OrientationEventListener(this) {
                override fun onOrientationChanged(orientation: Int) {
                    if (!autoRotateEnabled || orientation == ORIENTATION_UNKNOWN) return
                    val target = when {
                        orientation >= 315 || orientation < 45 -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                        orientation >= 45 && orientation < 135 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                        orientation >= 135 && orientation < 225 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
                        else -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    }
                    if (requestedOrientation != target) requestedOrientation = target
                }
            }
        }
        orientationListener?.enable()
    }

    private fun stopAutoRotate() {
        autoRotateEnabled = false
        orientationListener?.disable()
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }

    private fun enterPip(width: Int?, height: Int?, result: MethodChannel.Result) {
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
                .setAspectRatio(Rational((ratio * 1000).toInt(), 1000))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setSeamlessResizeEnabled(true)
                builder.setAutoEnterEnabled(false)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                builder.setSourceRectHint(Rect(0, 0, window.decorView.width, window.decorView.height))
            }
            enterPictureInPictureMode(builder.build())
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    override fun onDestroy() {
        stopAutoRotate()
        super.onDestroy()
    }
}
