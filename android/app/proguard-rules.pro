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
# v1.0.1+65: the SDKs ship their OWN consumer ProGuard rules inside the
# AARs — blanket '-keep ** { *; }' here kept 100% of GMS and tanked the
# shrink/obfuscation scores. Only silence warnings.
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.ump.**
-dontwarn com.google.ads.**

# --- Firebase (consumer rules ship in the AARs) ------------------------
-dontwarn com.google.firebase.**
-dontwarn com.google.firestore.**

# --- media_kit / libmpv JNI surface (player engine) -------------------
-keep class com.alexmercerind.** { *; }
-dontwarn com.alexmercerind.**
-dontwarn io.flutter.**

# Reflection/metadata R8 needs for generics across plugins
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*

# --- whisper/FFmpegKit JNI (on-device AI subtitles) -------------------
-keep class com.arthenica.** { *; }
-keep class dev.ffmpegkit.** { *; }
-dontwarn com.arthenica.**
-dontwarn dev.ffmpegkit.**
