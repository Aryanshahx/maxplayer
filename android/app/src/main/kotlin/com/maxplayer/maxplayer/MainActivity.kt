package com.maxplayer.maxplayer

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private var rotationLocked = false

    private val pipSupported: Boolean
        get() = packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE,
        )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "maxplayer/native",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "toggleRotationLock" -> result.success(toggleRotationLock())

                "enterPip" -> {
                    enterPip(
                        call.argument<Int>("w"),
                        call.argument<Int>("h"),
                        result,
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

            result.success(enterPictureInPictureMode(builder.build()))
        } catch (_: Exception) {
            result.success(false)
        }
    }

    override fun onDestroy() {
        rotationLocked = false
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        super.onDestroy()
    }
}
