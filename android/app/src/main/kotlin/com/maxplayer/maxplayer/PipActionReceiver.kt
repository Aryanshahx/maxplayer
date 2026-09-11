package com.maxplayer.maxplayer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PipActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TOGGLE = "com.maxplayer.maxplayer.PIP_TOGGLE"
        private var activity: MainActivity? = null

        fun bind(mainActivity: MainActivity) {
            activity = mainActivity
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            activity?.handlePipToggle()
        }
    }
}
