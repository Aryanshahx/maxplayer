package com.hypertechlabs.maxplayer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Background playback foreground service. The notification is a proper
 * MEDIA notification: video title + a play/pause action that toggles the
 * player through the same [PipActionReceiver.ACTION_TOGGLE] broadcast the
 * picture-in-picture button uses, so pause/resume works from the
 * notification shade while the app is in the background.
 */
class PlaybackKeepAliveService : Service() {
    companion object {
        private const val CHANNEL_ID = "maxplayer_playback"
        private const val NOTIFICATION_ID = 1901
        private const val REQ_OPEN = 1902
        private const val REQ_TOGGLE = 4102

        @Volatile
        private var running = false

        @Volatile
        private var lastTitle = "Max Player"

        @Volatile
        private var lastPlaying = true

        fun start(context: Context, title: String, playing: Boolean) {
            lastTitle = title
            lastPlaying = playing
            running = true
            val intent = Intent(context, PlaybackKeepAliveService::class.java)
                .putExtra("title", title)
                .putExtra("playing", playing)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** Refresh the notification's state (icon + text) while it runs. */
        fun updatePlaying(context: Context, playing: Boolean) {
            lastPlaying = playing
            if (!running) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.notify(NOTIFICATION_ID, buildNotification(context, lastTitle, playing))
        }

        fun stop(context: Context) {
            running = false
            context.stopService(Intent(context, PlaybackKeepAliveService::class.java))
        }

        private fun buildNotification(
            context: Context,
            title: String,
            playing: Boolean,
        ): Notification {
            val openIntent = PendingIntent.getActivity(
                context,
                REQ_OPEN,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val toggleIntent = PendingIntent.getBroadcast(
                context,
                REQ_TOGGLE,
                Intent(context, PipActionReceiver::class.java).apply {
                    action = PipActionReceiver.ACTION_TOGGLE
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val action = Notification.Action.Builder(
                if (playing) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play,
                if (playing) "Pause" else "Play",
                toggleIntent,
            ).build()
            val style = Notification.MediaStyle()
                .setShowActionsInCompactView(0)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            return builder
                .setSmallIcon(R.drawable.ic_stat_notify)
                .setContentTitle(title)
                .setContentText(if (playing) "Playing in background" else "Paused")
                .setContentIntent(openIntent)
                .setOngoing(playing)
                .setOnlyAlertOnce(true)
                .setStyle(style)
                .addAction(action)
                .build()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: lastTitle
        val playing = intent?.getBooleanExtra("playing", true) ?: true
        lastTitle = title
        lastPlaying = playing
        val notification = buildNotification(this, title, playing)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "MaxPlayer playback",
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                )
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
