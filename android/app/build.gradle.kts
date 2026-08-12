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

        // APK SIZE: the default Flutter/media_kit build bundles native libs
        // for FOUR CPU architectures (arm64-v8a, armeabi-v7a, x86, x86_64) -
        // that alone was ~60 MB of the ~93 MB APK. Every phone from ~2017
        // onward is arm64-v8a, so shipping just that cuts the APK to ~1/3.
        // (Also matches the whisper-android AAR, which is arm64-only.)
        ndk {
            abiFilters += "arm64-v8a"
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
