# =====================================================================
# v1.0.1+52 — ProGuard/R8 keep rules for release builds.
#
# RELEASE CRASH FIXED HERE:
#   FATAL EXCEPTION: main
#   java.lang.RuntimeException: Unable to get provider
#     androidx.startup.InitializationProvider
#   Caused by: java.lang.RuntimeException:
#     Failed to create an instance of androidx.work.impl.WorkDatabase
#
# Root cause: in release builds R8 minifies the Google Mobile Ads SDK.
# The ads SDK starts via androidx.startup BEFORE any Dart code runs and
# builds a Room database (WorkManager's WorkDatabase) reflectively —
# R8 strips those classes, so the app dies on the very first frame.
# =====================================================================

# --- androidx startup (runs the ads SDK init before the app) ----------
-keep class androidx.startup.** { *; }
-keep class androidx.lifecycle.** { *; }

# --- Room: keep the database impls R8 would otherwise strip -----------
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>(android.content.Context, java.lang.Class);
    <init>();
}
-dontwarn androidx.room.**

# --- WorkManager (shipped inside the AdMob SDK) -----------------------
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-dontwarn androidx.work.**

# --- Google Mobile Ads / Play services --------------------------------
-keep class com.google.android.gms.** { *; }
-keep class com.google.android.ump.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.ump.**
-dontwarn com.google.ads.**

# --- media_kit / libmpv JNI surface (player engine) -------------------
-keep class com.alexmercerind.** { *; }
-keep class io.flutter.** { *; }
-dontwarn com.alexmercerind.**
-dontwarn io.flutter.**

# --- whisper/FFmpegKit JNI (on-device AI subtitles) -------------------
-keep class com.arthenica.** { *; }
-keep class dev.ffmpegkit.** { *; }
-dontwarn com.arthenica.**
-dontwarn dev.ffmpegkit.**
