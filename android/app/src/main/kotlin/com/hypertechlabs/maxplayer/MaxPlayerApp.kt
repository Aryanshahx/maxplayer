package com.hypertechlabs.maxplayer

import android.app.Application
import android.os.Build
import android.os.Process
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/**
 * v34: catches JVM-level uncaught exceptions - the "Max Player has
 * stopped" case - anywhere in the app, INCLUDING crashes that happen
 * before MainActivity exists (provider/plugin init, window inflation).
 * The stack trace is written to internal storage; the next app launch
 * shows it in a copyable dialog (see nativeCrashGet/nativeCrashClear in
 * MainActivity and takeLastIncludingNative() in crash_log.dart).
 *
 * The previous handler is chained afterwards, so the system crash
 * dialog, process teardown and Play Console crash stats keep working.
 *
 * NOTE: a hard native abort (SIGSEGV inside a .so such as libmpv)
 * bypasses the JVM exception channel by design; those still need
 * adb logcat. JVM throws are the common "has stopped" cause though.
 */
class MaxPlayerApp : Application() {

    override fun onCreate() {
        super.onCreate()
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
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
        File(filesDir, CRASH_FILE).writeText(trimmed)
    }

    companion object {
        const val CRASH_FILE = "maxplayer_native_crash.txt"
    }
}
