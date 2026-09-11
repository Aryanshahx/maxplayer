package com.maxplayer.maxplayer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PipActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TOGGLE = "com.maxplayer.maxplayer.PIP_TOGGLE"
        const val ACTION_PIP_TOGGLE_ACTIVITY =
            "com.maxplayer.maxplayer.PIP_TOGGLE_ACTIVITY"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE) return

        val activityIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_PIP_TOGGLE_ACTIVITY
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.startActivity(activityIntent)
    }
}
