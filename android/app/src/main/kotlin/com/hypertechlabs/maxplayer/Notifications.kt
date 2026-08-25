package com.hypertechlabs.maxplayer

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
    const val CHANNEL_GENERAL = "general"

    private val channels = listOf(
        Triple(CHANNEL_AI_SUBS, "AI subtitles", NotificationManager.IMPORTANCE_LOW),
        Triple(CHANNEL_CONTINUE, "Continue watching", NotificationManager.IMPORTANCE_DEFAULT),
        Triple(CHANNEL_NEW_EPISODES, "New episodes", NotificationManager.IMPORTANCE_DEFAULT),
        Triple(CHANNEL_PLAYBACK, "Playback", NotificationManager.IMPORTANCE_LOW),
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
                if (channel == CHANNEL_AI_SUBS || channel == CHANNEL_PLAYBACK)
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
