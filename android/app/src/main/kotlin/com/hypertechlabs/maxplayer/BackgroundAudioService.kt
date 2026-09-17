package com.hypertechlabs.maxplayer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * v1.0.11 continuous background audio: a lightweight foreground service
 * whose only job is to keep the process (and the mpv audio render loop)
 * alive while the app is minimized or the screen is locked.
 *
 * Position 1: the Flutter engine + player always live in Dart-land, so this
 * service owns NO playback state. All state (title / playing / looping) is
 * PUSHED in through start/update Intents from MainActivity, and all control
 * actions (play / pause / loop / close) are BROADCAST to the
 * [AudioControlReceiver], which MainActivity forwards into Dart.
 *
 * Position 2: a PARTIAL wake lock is held for the lifetime of the service —
 * Android dozes audio decode threads in a backgrounded process otherwise,
 * which was exactly why "screen off = playback dies" before.
 */
class BackgroundAudioService : Service() {

    companion object {
        const val CHANNEL_ID = "maxplayer.background_audio"
        const val NOTIFICATION_ID = 7101

        const val ACTION_UPDATE = "com.hypertechlabs.maxplayer.BG_AUDIO_UPDATE"
        const val ACTION_CLOSE = "com.hypertechlabs.maxplayer.BG_AUDIO_CLOSE"

        const val EXTRA_TITLE = "title"
        const val EXTRA_PLAYING = "playing"
        const val EXTRA_LOOPING = "looping"

        fun startIntent(
            context: Context,
            title: String,
            playing: Boolean,
            looping: Boolean,
        ): Intent = Intent(context, BackgroundAudioService::class.java).apply {
            action = ACTION_UPDATE
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_PLAYING, playing)
            putExtra(EXTRA_LOOPING, looping)
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var title: String = "Max Player"
    private var playing: Boolean = true
    private var looping: Boolean = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CLOSE) {
            stopSelf()
            return START_NOT_STICKY
        }

        title = intent?.getStringExtra(EXTRA_TITLE) ?: title
        playing = intent?.getBooleanExtra(EXTRA_PLAYING, playing) ?: playing
        looping = intent?.getBooleanExtra(EXTRA_LOOPING, looping) ?: looping

        ensureChannel()
        ensureWakeLock()
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onDestroy() {
        runCatching {
            wakeLock?.let { if (it.isHeld) it.release() }
        }
        wakeLock = null
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                mgr.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "Background playback",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        description =
                            "Keeps audio playing while Max Player is in the background"
                        setShowBadge(false)
                    }
                )
            }
        }
    }

    private fun ensureWakeLock() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "maxplayer:bgAudio",
            )
        }
        runCatching {
            wakeLock?.let { if (!it.isHeld) it.acquire() }
        }
    }

    /** Broadcast control actions from the notification into the receiver. */
    private fun actionIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, AudioControlReceiver::class.java).apply {
            this.action = action
            setPackage(packageName)
        }
        val flags =
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(this, requestCode, intent, flags)
    }

    private fun contentIntent(): PendingIntent {
        val intent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.apply { addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) }
        val flags =
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(this, 0, intent, flags)
    }

    private fun buildNotification(): Notification {
        val playPauseAction = NotificationCompat.Action.Builder(
            if (playing) android.R.drawable.ic_media_pause
            else android.R.drawable.ic_media_play,
            if (playing) "Pause" else "Play",
            actionIntent(
                if (playing) AudioControlReceiver.ACTION_PAUSE
                else AudioControlReceiver.ACTION_PLAY,
                1,
            ),
        ).build()

        val loopAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_rotate,
            if (looping) "Loop: on" else "Loop: off",
            actionIntent(AudioControlReceiver.ACTION_LOOP, 2),
        ).build()

        val closeAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_close_clear_cancel,
            "Close",
            actionIntent(AudioControlReceiver.ACTION_CLOSE, 3),
        ).build()

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(
                if (playing)
                    "Playing in background${if (looping) " · looping" else ""}"
                else "Paused"
            )
            .setContentIntent(contentIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .addAction(playPauseAction)
            .addAction(loopAction)
            .addAction(closeAction)
            .build()
    }
}
