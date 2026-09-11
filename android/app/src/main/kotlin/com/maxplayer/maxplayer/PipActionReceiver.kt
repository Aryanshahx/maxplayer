package com.maxplayer.maxplayer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodChannel

/**
 * Receives the Picture-in-Picture play/pause action broadcast and toggles
 * playback directly through the Flutter method channel. Launching the
 * activity here is deliberately avoided — that would bring the app back to
 * fullscreen, which is exactly the bug this class exists to fix.
 */
class PipActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TOGGLE = "com.maxplayer.maxplayer.PIP_TOGGLE"

        // Set by MainActivity.configureFlutterEngine, cleared on destroy.
        @Volatile
        var channel: MethodChannel? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            channel?.invokeMethod("pipToggle", null)
        }
    }
}
