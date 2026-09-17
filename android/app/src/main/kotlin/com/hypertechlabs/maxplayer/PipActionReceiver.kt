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
        // PiP mode keeps the activity alive, so the toggle always has a
        // live player to talk to. No cached-engine fallback: the app no
        // longer plays with the window gone, by design.
        activity?.handlePipToggle()
    }
}
