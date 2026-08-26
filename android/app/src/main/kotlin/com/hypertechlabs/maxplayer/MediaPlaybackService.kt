package com.hypertechlabs.maxplayer

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * v68: Native Foreground Service & MediaSession for reliable background /
 * screen-off audio playback (B2) and system-wide Now Playing media controls (B1).
 *
 * Runs as a foreground service with type "mediaPlayback" so the Android OS
 * never sleeps or kills the playback process when the screen is locked or
 * the user switches apps.
 */
class MediaPlaybackService : Service() {

    private var mediaSession: MediaSession? = null
    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val NOTIF_ID = 1001
        const val ACTION_PLAY = "com.hypertechlabs.maxplayer.service.PLAY"
        const val ACTION_PAUSE = "com.hypertechlabs.maxplayer.service.PAUSE"
        const val ACTION_PREV = "com.hypertechlabs.maxplayer.service.PREV"
        const val ACTION_NEXT = "com.hypertechlabs.maxplayer.service.NEXT"
        const val ACTION_STOP = "com.hypertechlabs.maxplayer.service.STOP"
        const val ACTION_UPDATE = "com.hypertechlabs.maxplayer.service.UPDATE"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_SUBTITLE = "extra_subtitle"
        const val EXTRA_IS_PLAYING = "extra_is_playing"
        const val EXTRA_PATH = "extra_path"

        var onMediaAction: ((String) -> Unit)? = null

        fun startOrUpdate(
            context: Context,
            title: String,
            subtitle: String,
            isPlaying: Boolean,
            path: String
        ) {
            val intent = Intent(context, MediaPlaybackService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_SUBTITLE, subtitle)
                putExtra(EXTRA_IS_PLAYING, isPlaying)
                putExtra(EXTRA_PATH, path)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {}
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, MediaPlaybackService::class.java))
            } catch (_: Exception) {}
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannels(applicationContext)
        acquireWakeLock()
        initMediaSession()
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MaxPlayer::MediaPlaybackService")
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(24 * 60 * 60 * 1000L)
            }
        } catch (_: Exception) {}
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
    }

    private fun initMediaSession() {
        try {
            mediaSession = MediaSession(applicationContext, "MaxPlayerMediaSession").apply {
                setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
                setCallback(object : MediaSession.Callback() {
                    override fun onPlay() {
                        onMediaAction?.invoke("play_pause")
                    }

                    override fun onPause() {
                        onMediaAction?.invoke("play_pause")
                    }

                    override fun onSkipToNext() {
                        onMediaAction?.invoke("next")
                    }

                    override fun onSkipToPrevious() {
                        onMediaAction?.invoke("prev")
                    }

                    override fun onStop() {
                        onMediaAction?.invoke("stop")
                    }
                })
                isActive = true
            }
        } catch (_: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_PLAY || action == ACTION_PAUSE) {
            onMediaAction?.invoke("play_pause")
            return START_STICKY
        } else if (action == ACTION_NEXT) {
            onMediaAction?.invoke("next")
            return START_STICKY
        } else if (action == ACTION_PREV) {
            onMediaAction?.invoke("prev")
            return START_STICKY
        } else if (action == ACTION_STOP) {
            onMediaAction?.invoke("stop")
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Max Player"
        val subtitle = intent?.getStringExtra(EXTRA_SUBTITLE) ?: ""
        val isPlaying = intent?.getBooleanExtra(EXTRA_IS_PLAYING, true) ?: true
        val path = intent?.getStringExtra(EXTRA_PATH) ?: ""

        updateSessionPlaybackState(isPlaying)
        updateSessionMetadata(title, subtitle)
        val notif = buildNotification(title, subtitle, isPlaying, path)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIF_ID, notif)
            }
        } catch (_: Exception) {}

        return START_STICKY
    }

    private fun updateSessionPlaybackState(isPlaying: Boolean) {
        val state = if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        val actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SKIP_TO_NEXT or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS or
            PlaybackState.ACTION_STOP
        mediaSession?.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(state, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1.0f)
                .build()
        )
    }

    private fun updateSessionMetadata(title: String, subtitle: String) {
        try {
            val metadata = MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, if (subtitle.isNotEmpty()) subtitle else "Max Player")
                .putString(MediaMetadata.METADATA_KEY_ALBUM, "Max Player")
                .build()
            mediaSession?.setMetadata(metadata)
        } catch (_: Exception) {}
    }

    private fun buildNotification(
        title: String,
        subtitle: String,
        isPlaying: Boolean,
        path: String
    ): android.app.Notification {
        val tapIntent = Notifications.createLaunchIntent(
            applicationContext,
            if (path.isNotEmpty()) "video:$path" else null
        )

        fun makeServicePendingIntent(action: String, reqCode: Int): PendingIntent {
            val intent = Intent(applicationContext, MediaPlaybackService::class.java).apply {
                this.action = action
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getService(applicationContext, reqCode, intent, flags)
        }

        val prevPending = makeServicePendingIntent(ACTION_PREV, 201)
        val playPausePending = makeServicePendingIntent(
            if (isPlaying) ACTION_PAUSE else ACTION_PLAY,
            202
        )
        val nextPending = makeServicePendingIntent(ACTION_NEXT, 203)
        val stopPending = makeServicePendingIntent(ACTION_STOP, 204)

        val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseLabel = if (isPlaying) "Pause" else "Play"

        val builder = NotificationCompat.Builder(applicationContext, Notifications.CHANNEL_PLAYBACK)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(if (subtitle.isNotEmpty()) subtitle else "Max Player")
            .setContentIntent(tapIntent)
            .setOngoing(isPlaying)
            .setAutoCancel(!isPlaying)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_media_previous, "Previous", prevPending)
            .addAction(playPauseIcon, playPauseLabel, playPausePending)
            .addAction(android.R.drawable.ic_media_next, "Next", nextPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)

        return builder.build()
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            mediaSession?.isActive = false
            mediaSession?.release()
            mediaSession = null
        } catch (_: Exception) {}
        releaseWakeLock()
        stopForegroundCompat()
        super.onDestroy()
    }
}
