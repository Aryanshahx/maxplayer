import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play Store upload key: android/key.properties holds the real signing
// credentials when present (generated per PLAY_STORE_GUIDE.md); CI injects
// it. When absent (local dev, old clones) release falls back to the debug
// key so nothing breaks - a debug-signed build just can't go to the Play
// Console.
val uploadProps = Properties().apply {
    // Conventional location: android/key.properties (git-ignored).
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasUploadKey = uploadProps.getProperty("storeFile")?.isNotEmpty() == true

android {
    namespace = "com.hypertechlabs.maxplayer"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("playStore") {
            keyAlias = uploadProps.getProperty("keyAlias") ?: ""
            keyPassword = uploadProps.getProperty("keyPassword") ?: ""
            storePassword = uploadProps.getProperty("storePassword") ?: ""
            uploadProps.getProperty("storeFile")?.let {
                // Resolved relative to the android/ project dir.
                storeFile = rootProject.file(it)
            }
        }
    }

    defaultConfig {
        // Unique application ID (renamed from com.example.* for Play Store;
        // a published app can never change this again).
        applicationId = "com.hypertechlabs.maxplayer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // CPU architectures: arm64 (modern) + armeabi-v7a + x86_64.
        // v39: a 32-bit-only USERSPACE still exists in 2026 - Android Go
        // phones (POCO C51/C65, Redmi A-series, even Android 14 Go
        // devices) plus every Android 7-10 budget phone. The startup
        // trace from a POCO C51 (Android 13!) showed the arm64-only APK
        // dying with: Could not find 'libflutter.so'. Looked for:
        // [armeabi-v7a, armeabi], but only found: [arm64-v8a].
        // (AI subtitles still need 64-bit - the whisper engine ships an
        //  arm64-only library; on 32-bit devices playback works normally
        //  and the AI feature declines gracefully instead of crashing.)
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    buildTypes {
        release {
            // Real upload key when android/key.properties exists, otherwise
            // the debug key so `flutter run --release` still works.
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("playStore")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// v20: name the build artifacts "MaxPlayer-release.apk" /
// "MaxPlayer-release.aab" instead of the generic "app-release.*".
// (Gradle 9 removed the old archivesBaseName; base.archivesName replaces it.)
base {
    archivesName.set("MaxPlayer")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // AI SUBTITLES (Phase 1): prebuilt on-device whisper.cpp engine.
    // Plain Maven artifact (NOT a Gradle/Flutter plugin) = no toolchain
    // conflicts. ~1.1 MB AAR, MIT licensed, runs 100% offline & free.
    implementation("dev.ffmpegkit-maintained:whisper-android:1.0.0")
    // The AAR only exports coroutines on the runtime classpath; we call its
    // suspend functions from Kotlin, so we need it explicitly at compile
    // time. Same version as the AAR's -> no conflict.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
