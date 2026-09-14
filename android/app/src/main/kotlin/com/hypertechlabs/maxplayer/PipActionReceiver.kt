package com.hypertechlabs.maxplayer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PipActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TOGGLE = "com.hypertechlabs.maxplayer.PIP_TOGGLE"
        private var activity: MainActivity? = null

        fun bind(mainActivity: MainActivity) {
            activity = mainActivity
        }

        fun boundActivity(): MainActivity? = activity
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE) return
        // Prefer the live activity; when the app was swiped away the
        // activity is gone but the cached Flutter engine (and the video)
        // is still running — talk to it directly (main thread: broadcast
        // receivers already run on it).
        val act = activity
        if (act != null) {
            act.handlePipToggle()
        } else {
            MainActivity.toggleEnginePlayer()
        }
    }
}
