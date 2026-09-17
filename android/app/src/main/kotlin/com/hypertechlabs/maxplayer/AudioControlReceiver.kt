package com.hypertechlabs.maxplayer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * v1.0.11 background-audio controls: the persistent notification's
 * Play / Pause / Loop / Close buttons broadcast into this receiver, which
 * simply forwards the action into the live [MainActivity] (Dart owns the
 * mpv player, so all state changes originate there). No-op when the
 * activity is gone (e.g. process restored without the player).
 */
class AudioControlReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_PLAY = "com.hypertechlabs.maxplayer.BG_AUDIO_PLAY"
        const val ACTION_PAUSE = "com.hypertechlabs.maxplayer.BG_AUDIO_PAUSE"
        const val ACTION_LOOP = "com.hypertechlabs.maxplayer.BG_AUDIO_LOOP"
        const val ACTION_CLOSE = "com.hypertechlabs.maxplayer.BG_AUDIO_STOP"

        /** Set while MainActivity is alive; cleared in onDestroy. */
        var activity: MainActivity? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        activity?.handleBackgroundAudioAction(action)
    }
}
