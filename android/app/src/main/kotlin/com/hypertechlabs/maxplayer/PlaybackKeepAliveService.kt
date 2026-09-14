package com.hypertechlabs.maxplayer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Background playback foreground service (v30).
 *
 * The notification is a system MEDIA notification bound to a framework
 * [MediaSession] — Android renders it with the device's default media
 * player UI (shade media panel, lock-screen controls, Android 11+ media
 * controls) instead of a plain custom notification. Title + a play/pause
 * action are kept; both route through [PipActionReceiver.ACTION_TOGGLE],
 * which reaches the player through the live Flutter engine even when the
 * activity itself has been destroyed (app swiped away).
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

        /** Live service instance (needed by the static entry points). */
        @Volatile
        private var instance: PlaybackKeepAliveService? = null

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

        /** Refresh the notification + media session state while it runs. */
        fun updatePlaying(context: Context, playing: Boolean) {
            lastPlaying = playing
            if (!running) return
            val service = instance ?: return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.notify(NOTIFICATION_ID, service.buildNotification(title = lastTitle, playing = playing))
            service.updateSessionState(lastTitle, playing)
        }

        fun stop(context: Context) {
            running = false
            context.stopService(Intent(context, PlaybackKeepAliveService::class.java))
        }

        /**
         * Tap-to-open intent for the media notification and the session's
         * media controls: the system launcher intent, so the existing app
         * task is brought to the front (or cold-started) exactly like the
         * home-screen icon does.
         */
        fun openAppIntent(context: Context): PendingIntent {
            val base = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
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
    }

    private var session: MediaSession? = null
    private val sessionHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        createChannel()
        instance = this
        // Framework MediaSession (API 21+, minSdk is 24): registers the
        // playback with Android's media framework so the device's DEFAULT
        // media player UI (notification shade media panel, lock screen,
        // quick-settings media controls, headset buttons) takes over.
        val s = MediaSession(this, "MaxPlayer")
        s.setCallback(
            object : MediaSession.Callback() {
                override fun onPlay() = forwardToggle()

                override fun onPause() = forwardToggle()

                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    forwardToggle()
                    return true
                }
            },
            sessionHandler,
        )
        s.setSessionActivity(openAppIntent(this))
        s.isActive = true
        session = s
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: lastTitle
        val playing = intent?.getBooleanExtra("playing", true) ?: true
        lastTitle = title
        lastPlaying = playing
        val notification = buildNotification(title = title, playing = playing)
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
        updateSessionState(title, playing)
        return START_STICKY
    }

    /**
     * The user swiped the app away from recents: re-assert the foreground
     * service so background audio survives the task removal (the Flutter
     * engine itself is cached and keeps running).
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        val restart = Intent(applicationContext, PlaybackKeepAliveService::class.java)
            .putExtra("title", lastTitle)
            .putExtra("playing", lastPlaying)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(restart)
            } else {
                applicationContext.startService(restart)
            }
        } catch (_: Throwable) {
            // Best effort only.
        }
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        try {
            session?.isActive = false
            session?.release()
        } catch (_: Throwable) {
        }
        session = null
        super.onDestroy()
    }

    private fun forwardToggle() {
        // Same broadcast the notification action and the PiP button use;
        // the receiver reaches the live activity or, when the app is
        // closed, the cached Flutter engine directly.
        sendBroadcast(
            Intent(this, PipActionReceiver::class.java).apply {
                action = PipActionReceiver.ACTION_TOGGLE
            },
        )
    }

    private fun updateSessionState(title: String, playing: Boolean) {
        val s = session ?: return
        try {
            s.setMetadata(
                MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, "Max Player")
                    .build(),
            )
            s.setPlaybackState(
                PlaybackState.Builder()
                    .setState(
                        if (playing) PlaybackState.STATE_PLAYING
                        else PlaybackState.STATE_PAUSED,
                        PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                        1.0f,
                    )
                    .setActions(
                        PlaybackState.ACTION_PLAY or
                            PlaybackState.ACTION_PAUSE or
                            PlaybackState.ACTION_PLAY_PAUSE,
                    )
                    .build(),
            )
            s.isActive = true
        } catch (_: Throwable) {
        }
    }

    private fun buildNotification(title: String, playing: Boolean): Notification {
        val action = Notification.Action.Builder(
            if (playing) android.R.drawable.ic_media_pause
            else android.R.drawable.ic_media_play,
            if (playing) "Pause" else "Play",
            PendingIntent.getBroadcast(
                this,
                REQ_TOGGLE,
                Intent(this, PipActionReceiver::class.java).apply {
                    action = PipActionReceiver.ACTION_TOGGLE
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        ).build()
        // MediaStyle bound to the session token: Android draws this with
        // the device's default media controls (compact view keeps the
        // play/pause button visible).
        val style = Notification.MediaStyle()
            .setShowActionsInCompactView(0)
        session?.let { style.setMediaSession(it.sessionToken) }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(if (playing) "Playing in background" else "Paused")
            .setContentIntent(openAppIntent(this))
            .setOngoing(playing)
            .setOnlyAlertOnce(true)
            .setStyle(style)
            .addAction(action)
            .build()
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
