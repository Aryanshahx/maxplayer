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
 * Background playback foreground service (v31).
 *
 * Deliberately simple and crash-proof: the v29-style media notification
 * (framework MediaStyle WITHOUT a MediaSession token — the exact shape
 * that was proven to show on real devices), plus a last-resort plain
 * notification fallback so `startForeground` can never fail. Play/pause
 * routes through [PipActionReceiver.ACTION_TOGGLE], which reaches either
 * the live activity or the cached Flutter engine.
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

        /** Live service instance (for the static entry points). */
        @Volatile
        private var instance: PlaybackKeepAliveService? = null

        fun isRunning(): Boolean = running && instance != null

        fun start(context: Context, title: String, playing: Boolean) {
            lastTitle = title
            lastPlaying = playing
            running = true
            val intent = Intent(context, PlaybackKeepAliveService::class.java)
                .putExtra("title", title)
                .putExtra("playing", playing)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Throwable) {
                // A service failure must never take playback down.
            }
        }

        /** Refresh the notification's state (icon + text) while it runs. */
        fun updatePlaying(context: Context, playing: Boolean) {
            lastPlaying = playing
            if (!running || instance == null) return
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                nm.notify(NOTIFICATION_ID, buildNotification(context, lastTitle, playing))
            } catch (_: Throwable) {
            }
        }

        fun stop(context: Context) {
            running = false
            try {
                context.stopService(Intent(context, PlaybackKeepAliveService::class.java))
            } catch (_: Throwable) {
            }
        }

        /**
         * Tap-to-open intent: the system launcher intent, so the existing
         * app task is brought to the front (or cold-started) exactly like
         * the home-screen icon.
         */
        fun openAppIntent(context: Context): PendingIntent {
            val base = try {
                context.packageManager.getLaunchIntentForPackage(context.packageName)
            } catch (_: Throwable) {
                null
            } ?: Intent(context, MainActivity::class.java)
            base.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
            return PendingIntent.getActivity(
                context,
                REQ_OPEN,
                base,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun buildNotification(
            context: Context,
            title: String,
            playing: Boolean,
        ): Notification {
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
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val built = try {
                builder
                    .setSmallIcon(R.drawable.ic_stat_notify)
                    .setContentTitle(title)
                    .setContentText(if (playing) "Playing in background" else "Paused")
                    .setContentIntent(openAppIntent(context))
                    .setOngoing(playing)
                    .setOnlyAlertOnce(true)
                    .setStyle(Notification.MediaStyle().setShowActionsInCompactView(0))
                    .addAction(action)
                    .build()
            } catch (_: Throwable) {
                // Last resort: plain notification without the media style.
                val plain = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Notification.Builder(context, CHANNEL_ID)
                } else {
                    @Suppress("DEPRECATION")
                    Notification.Builder(context)
                }
                plain
                    .setSmallIcon(R.drawable.ic_stat_notify)
                    .setContentTitle(title)
                    .setContentText(if (playing) "Playing in background" else "Paused")
                    .setContentIntent(openAppIntent(context))
                    .setOngoing(playing)
                    .setOnlyAlertOnce(true)
                    .addAction(action)
                    .build()
            }
            return built
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: lastTitle
        val playing = intent?.getBooleanExtra("playing", true) ?: true
        lastTitle = title
        lastPlaying = playing
        running = true
        val notification = buildNotification(this, title, playing)
        try {
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
        } catch (_: Throwable) {
            // If foreground promotion ever fails, keep the service alive
            // anyway; never crash the app over a notification.
        }
        return START_STICKY
    }

    /**
     * The user swiped the app away from recents: re-assert the foreground
     * service so background audio survives the task removal.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        try {
            val restart = Intent(applicationContext, PlaybackKeepAliveService::class.java)
                .putExtra("title", lastTitle)
                .putExtra("playing", lastPlaying)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(restart)
            } else {
                applicationContext.startService(restart)
            }
        } catch (_: Throwable) {
        }
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun createChannel() {
        try {
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
        } catch (_: Throwable) {
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
