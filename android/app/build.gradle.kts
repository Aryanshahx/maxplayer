plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.maxplayer.maxplayer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.maxplayer.maxplayer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // AI subtitles need minSdk 24 (whisper-android / ffmpeg-kit).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // CPU architectures: arm64 (modern) + armeabi-v7a + x86_64.
        // The whisper engine ships arm64-only native libraries; 32-bit
        // phones get a clean decline from the native side before any
        // model download.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    // whisper-android bundles libc++_shared.so, and so does media_kit's
    // native stack -> mergeReleaseNativeLibs aborts with "2 files found
    // with path 'lib/<abi>/libc++_shared.so'". Keep exactly one copy per
    // ABI; both native stacks run against one LLVM STL runtime. ABI list
    // mirrors abiFilters above - keep in sync if that ever changes.
    packaging {
        jniLibs {
            pickFirsts += listOf(
                "lib/arm64-v8a/libc++_shared.so",
                "lib/armeabi-v7a/libc++_shared.so",
                "lib/x86_64/libc++_shared.so"
            )
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // AI SUBTITLES (on-device): prebuilt whisper.cpp engine. Plain Maven
    // artifact (NOT a Gradle/Flutter plugin) = no toolchain conflicts.
    // Runs 100% offline & free after the one-time model download (64-bit).
    implementation("dev.ffmpegkit-maintained:whisper-android:1.0.0")
    // The AAR only exports coroutines on the runtime classpath; we call its
    // suspend functions from Kotlin, so we need it explicitly at compile
    // time. Same version as the AAR's -> no conflict.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
