package com.hypertechlabs.maxplayer

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Process
import android.os.SystemClock
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/**
 * v34/v36/v37: two crash-diagnosis tools that need NO PC and NO app
 * reopen on the failing phone:
 *
 *  (1) CRASH REPORT (v34/v36): catches JVM-level uncaught exceptions -
 *      the "Max Player has stopped" case - anywhere in the app,
 *      INCLUDING crashes before MainActivity exists. Saved to both:
 *       a) internal storage (shown in-app on next launch via
 *          nativeCrashGet/nativeCrashClear + takeLastIncludingNative),
 *       b) Android/data/<package>/files/maxplayer_crash.txt - readable
 *          with ANY file manager, no permission needed (v36).
 *
 *  (2) STARTUP TRACE (v37): a breadcrumb stage log that survives even
 *      when the app dies before Dart or the UI ever comes up:
 *      Android/data/<package>/files/maxplayer_start.log
 *      Records: app_create -> activity_create_begin/ok -> channel_ready
 *      -> dart_main -> mediakit_ok -> player_ok/player_FAIL -> scan_*
 *      plus a final "CRASH: <exception>" line from the handler above.
 *      The LAST stage line tells us exactly which component killed a
 *      phone that "never opens".
 *
 * The previous default handler is chained afterwards, so the system
 * crash dialog, process teardown and Play Console crash stats keep
 * working. A hard native abort (SIGSEGV inside a .so) bypasses the JVM
 * channel by design - but the trace file still shows the last stage.
 */
class MaxPlayerApp : Application() {

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        // Install as EARLY as possible - attachBaseContext runs before
        // content providers and before onCreate.
        installCrashHandler()
    }

    override fun onCreate() {
        super.onCreate()
        installCrashHandler()
        CrashCrumbs.reset(this)
        CrashCrumbs.mark(this, "app_create")
    }

    private fun installCrashHandler() {
        if (handlerInstalled) return
        handlerInstalled = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            val msg = error.message ?: ""
            if (msg.contains("FlutterJNI is not attached to native")) {
                // Ignore late ImageReader callbacks during engine teardown / activity stop
                return@setDefaultUncaughtExceptionHandler
            }
            try {
                CrashCrumbs.crash(
                    this,
                    "${error.javaClass.simpleName}: ${
                        error.message?.lineSequence()?.firstOrNull() ?: ""
                    }",
                )
            } catch (_: Throwable) {
            }
            try {
                writeCrashReport(thread, error)
            } catch (_: Throwable) {
                // Reporting must never crash the crash handler itself.
            }
            // Chain so the system dialogue + Play crash stats still work.
            if (previous != null) {
                previous.uncaughtException(thread, error)
            } else {
                Process.killProcess(Process.myPid())
            }
        }
    }

    private fun writeCrashReport(thread: Thread, error: Throwable) {
        val trace =
            StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
        @Suppress("DEPRECATION")
        val versionName = try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "?"
        } catch (_: Throwable) {
            "?"
        }
        val text = buildString {
            appendLine("Max Player crash report (Android layer)")
            appendLine("time-ms: ${System.currentTimeMillis()}")
            appendLine("app: $versionName")
            appendLine("device: ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("thread: ${thread.name}")
            appendLine()
            append(trace)
        }
        val trimmed = if (text.length > 12000) text.substring(0, 12000) else text
        // 1) internal storage: the app itself reads it on the next launch.
        try {
            File(filesDir, CRASH_FILE).writeText(trimmed)
        } catch (_: Throwable) {
        }
        // 2) app-specific external folder: browsable with any file
        //    manager on Android 10 and older, no permission needed.
        try {
            val ext = getExternalFilesDir(null)
            if (ext != null) File(ext, CRASH_FILE).writeText(trimmed)
        } catch (_: Throwable) {
        }
    }

    companion object {
        @Volatile
        private var handlerInstalled = false
        const val CRASH_FILE = "maxplayer_crash.txt"
    }
}

/** v37: tiny append-only startup trace, dual-written like the crash
 *  report. Reset on every cold start (Application.onCreate). */
internal object CrashCrumbs {
    private const val START_FILE = "maxplayer_start.log"

    @Volatile
    private var t0: Long = -1

    /** Fresh log for a cold start. */
    fun reset(context: Context?) {
        if (context == null) return
        t0 = SystemClock.elapsedRealtime()
        val header = buildString {
            appendLine("Max Player startup trace (v37)")
            appendLine("app-create @ ${System.currentTimeMillis()}")
            appendLine(
                "android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}), " +
                    "${Build.MANUFACTURER} ${Build.MODEL}",
            )
            appendLine("stages:")
        }
        write(context, header, append = false)
    }

    fun mark(context: Context?, stage: String) {
        if (context == null) return
        if (t0 < 0) t0 = SystemClock.elapsedRealtime()
        val ms = SystemClock.elapsedRealtime() - t0
        write(context, "  $stage  (+${ms}ms)\n", append = true)
    }

    fun crash(context: Context?, short: String) {
        val single = short.lineSequence().firstOrNull() ?: short
        write(context, "  CRASH: ${single.take(300)}\n", append = true)
    }

    private fun write(context: Context?, text: String, append: Boolean) {
        if (context == null) return
        try {
            val f = File(context.filesDir, START_FILE)
            if (append) f.appendText(text) else f.writeText(text)
        } catch (_: Throwable) {
        }
        try {
            val ext = context.getExternalFilesDir(null)
            if (ext != null) {
                val f = File(ext, START_FILE)
                if (append) f.appendText(text) else f.writeText(text)
            }
        } catch (_: Throwable) {
        }
    }
}
