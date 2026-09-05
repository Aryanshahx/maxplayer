package com.hypertechlabs.maxplayer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * v62 (Phase 1): the NOTIFICATION FOUNDATION used by every later feature
 * (AI-subs-ready, continue watching, new episodes, now-playing).
 *
 * Zero new Flutter packages - this is plain AndroidX (core-ktx ships with
 * the Flutter embedding already) behind the existing `maxplayer/native`
 * MethodChannel. Channels are created lazily/once; all calls are safe on
 * old Android (notification channels are an API 26 no-op below that).
 *
 * Channels:
 *  - ai_subs        : "AI subtitles"        (low/urgency - finished job)
 *  - continue       : "Continue watching"   (default)
 *  - new_episodes   : "New episodes"        (default)
 *  - playback       : "Playback"            (low, ongoing now-playing)
 *  - general        : "General"             (default)
 */
object Notifications {
    const val EXTRA_PAYLOAD = "maxplayer.notification.PAYLOAD"

    const val CHANNEL_AI_SUBS = "ai_subs"
    const val CHANNEL_CONTINUE = "continue"
    const val CHANNEL_NEW_EPISODES = "new_episodes"
    const val CHANNEL_PLAYBACK = "playback"

    // v110: fresh channel id for now-playing. Android freezes a channel's
    // lock-screen visibility at CREATION time, so devices that already hold
    // the old "playback" channel could never gain PUBLIC visibility on it.
    const val CHANNEL_PLAYBACK_V2 = "playback_v2"
    const val CHANNEL_GENERAL = "general"

    private val channels = listOf(
        Triple(CHANNEL_AI_SUBS, "AI subtitles", NotificationManager.IMPORTANCE_LOW),
        Triple(CHANNEL_CONTINUE, "Continue watching", NotificationManager.IMPORTANCE_DEFAULT),
        Triple(CHANNEL_NEW_EPISODES, "New episodes", NotificationManager.IMPORTANCE_DEFAULT),
        Triple(CHANNEL_PLAYBACK, "Playback", NotificationManager.IMPORTANCE_LOW),
        Triple(CHANNEL_PLAYBACK_V2, "Now playing", NotificationManager.IMPORTANCE_DEFAULT),
        Triple(CHANNEL_GENERAL, "General", NotificationManager.IMPORTANCE_DEFAULT),
    )

    /**
     * Creates every notification channel once. Safe to call repeatedly and
     * on any API level (channels are ignored below Android 8.0). Called from
     * Activity.onCreate so channels exist before the first notify.
     */
    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        for ((id, title, importance) in channels) {
            if (nm.getNotificationChannel(id) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(id, title, importance).apply {
                        description = "Max Player notifications"
                        if (id == CHANNEL_PLAYBACK_V2) {
                            // A media channel must stay SILENT but VISIBLE:
                            // importance DEFAULT (IMPORTANCE_LOW rows are
                            // minimized or hidden on the lock screen by
                            // several OEM skins) with sound and vibration
                            // switched off, no badge, and explicitly
                            // lock-screen PUBLIC - this is only honored
                            // because the channel id is brand-new.
                            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                            setShowBadge(false)
                            setSound(null, null)
                            enableVibration(false)
                        }
                    }
                )
            }
        }
    }

    /**
     * Posts (or replaces) a notification. Returns the id used so callers can
     * cancel it later. [payload] is an opaque string delivered to Dart via
     * the onNotificationTap callback when the user taps the notification;
     * use it like a deep-link (e.g. "video:/path" or "ai:jobid").
     *
     * The small icon is the monochrome glyph in res/drawable (required on
     * Android 5+; a color/photo icon would render as a white square).
     */
    fun show(
        context: Context,
        channel: String,
        id: Int,
        title: String,
        body: String,
        payload: String?,
        ongoing: Boolean,
        progress: Int?,
    ): Int {
        val notifId = if (id != 0) id else ((System.currentTimeMillis() and 0x7FFFFFFF).toInt())
        val tap = createLaunchIntent(context, payload)
        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(!ongoing)
            .setOngoing(ongoing)
            .setPriority(
                if (channel == CHANNEL_AI_SUBS ||
                    channel == CHANNEL_PLAYBACK ||
                    channel == CHANNEL_PLAYBACK_V2)
                    NotificationCompat.PRIORITY_LOW
                else
                    NotificationCompat.PRIORITY_DEFAULT
            )
            .setContentIntent(tap)
        if (progress != null && progress in 0..100) {
            builder.setProgress(100, progress, progress <= 0)
        }
        try {
            NotificationManagerCompat.from(context).notify(notifId, builder.build())
        } catch (_: SecurityException) {
            // Android 13+ without POST_NOTIFICATIONS - the Dart side asks
            // for the permission first; if it was denied we simply no-op.
        }
        return notifId
    }

    fun cancel(context: Context, id: Int) {
        NotificationManagerCompat.from(context).cancel(id)
    }

    fun cancelAll(context: Context) {
        NotificationManagerCompat.from(context).cancelAll()
    }

    /** Whether the app may post notifications (granted, or pre-API-33). */
    fun areEnabled(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()

    const val NOTIF_ID_NOW_PLAYING = 1001

    /**
     * v67 (B1): Rich now-playing notification with Play/Pause, Next, Previous,
     * and Stop action buttons. Tap brings the player back to foreground.
     */
    fun showNowPlaying(
        context: Context,
        title: String,
        artist: String,
        isPlaying: Boolean,
        payload: String?,
    ): Int {
        val tap = createLaunchIntent(context, payload)

        fun makeActionIntent(action: String, reqCode: Int): PendingIntent {
            val intent = Intent(MainActivity.ACTION_MEDIA_CONTROL).apply {
                setPackage(context.packageName)
                putExtra(MainActivity.EXTRA_MEDIA_ACTION, action)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getBroadcast(context, reqCode, intent, flags)
        }

        val prevPending = makeActionIntent("prev", 101)
        val playPausePending = makeActionIntent("play_pause", 102)
        val nextPending = makeActionIntent("next", 103)
        val stopPending = makeActionIntent("stop", 104)

        val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseLabel = if (isPlaying) "Pause" else "Play"

        val builder = NotificationCompat.Builder(context, CHANNEL_PLAYBACK_V2)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(artist)
            .setContentIntent(tap)
            .setOngoing(isPlaying)
            .setAutoCancel(!isPlaying)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_media_previous, "Previous", prevPending)
            .addAction(playPauseIcon, playPauseLabel, playPausePending)
            .addAction(android.R.drawable.ic_media_next, "Next", nextPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)

        try {
            NotificationManagerCompat.from(context).notify(NOTIF_ID_NOW_PLAYING, builder.build())
        } catch (_: SecurityException) {
        }
        return NOTIF_ID_NOW_PLAYING
    }

    /**
     * Builds the tap intent: opens/reuses MainActivity (singleTop) and
     * carries [payload] as [EXTRA_PAYLOAD]. MainActivity reads it in
     * onCreate/onNewIntent and hands it to Dart via onNotificationTap.
     */
    fun createLaunchIntent(context: Context, payload: String?): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (!payload.isNullOrEmpty()) putExtra(EXTRA_PAYLOAD, payload)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(context, payload?.hashCode() ?: 0, intent, flags)
    }
}
