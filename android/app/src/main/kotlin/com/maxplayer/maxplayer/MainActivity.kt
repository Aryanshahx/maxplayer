package com.maxplayer.maxplayer

// FlutterFragmentActivity is required by local_auth (device-password
// verification used for Private Space PIN recovery).
import android.app.PictureInPictureParams
import android.content.Intent
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val pipSupported: Boolean
        get() = packageManager
            .hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "maxplayer/native",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    // v0.8: shrink the player into a floating window.
                    if (!pipSupported) {
                        result.success(false)
                    } else {
                        val w = (call.argument<Int>("w") ?: 16).coerceAtLeast(1)
                        val h = (call.argument<Int>("h") ?: 9).coerceAtLeast(1)
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(w, h))
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: IllegalStateException) {
                            result.success(false)
                        }
                    }
                }
                "openCastSettings" -> {
                    // v0.8: real Chromecast/DLNA needs the vendor SDK; we take
                    // the user straight to the system screen-mirroring page.
                    try {
                        startActivity(Intent(Settings.ACTION_CAST_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                            result.success(true)
                        } catch (ignored: Exception) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
