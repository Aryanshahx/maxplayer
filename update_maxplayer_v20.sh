#!/usr/bin/env bash
# =============================================================
#  Max Player - v20 FEEDBACK FIXES + APP ICON
#  Repo: https://github.com/Aryanshahx/maxplayer   Version: 1.0.0+18
#
#  YOUR REPORT                                    -> FIX
#  fit does not offer different screen sizes      -> Fit button now cycles 6
#                                                    modes: Fit / Crop / Stretch /
#                                                    16:9 / 4:3 / Original
#  delay on play AND pause                        -> pause() was saving to disk
#                                                    BEFORE pausing; now instant
#  A-B / audio / subtitle button glitches         -> popup replaced by a proper
#                                                    bottom sheet (no flicker)
#  controls too high in landscape                 -> moved flush to the bottom
#                                                    edge in landscape
#  title moves too slow                           -> marquee ~2.5x faster
#  want 2x sign in middle of video                -> big centred 2x sign while
#                                                    long-pressing
#  video info sheet cannot slide to view all      -> now draggable + scrollable
#                                                    (30%..90% of screen)
#  apk/aab named "app-release"                    -> artifacts become
#                                                    MaxPlayer-release.apk / .aab
#  add this image as app icon                     -> new neon icon baked in
#                                                    (all densities + adaptive)
#  update the privacy policy                      -> added Play Data Safety section
#                                                    (repo copy + in-app copy)
#
#  FILES: 12 text + 10 icon PNGs (Android needs one image per screen
#  density - that is why the icon alone is 10 files, not one).
#
#  HOW TO USE:
#    cd ~/IdeaProjects/maxplayer
#    nano update_maxplayer_v20.sh      # paste, save, exit
#    bash update_maxplayer_v20.sh
#    git add -A && git commit -m "v20: fit modes, instant pause, tracks sheet,
#        landscape controls, faster marquee, 2x sign, info sheet, app icon+name"
#    git push
# =============================================================
set -e
cd "$HOME/IdeaProjects/maxplayer" || { echo "ERROR: project folder not found"; exit 1; }

if ! grep -q "^name: maxplayer" pubspec.yaml 2>/dev/null; then
  echo "ERROR: This does not look like the maxplayer project folder."
  exit 1
fi
if grep -q "archivesName.set" android/app/build.gradle.kts 2>/dev/null; then
  echo "v20 looks already applied (build.gradle.kts has archivesName). Nothing to do."
  exit 0
fi

# v17/v19 cleanup (idempotent): drop v16s temporary CI diagnostics step.
if grep -q "^      - name: Diagnose signing secrets" codemagic.yaml 2>/dev/null; then
  echo "==> removing v16 temporary CI diagnostics step from codemagic.yaml"
  sed -i '/^      - name: Diagnose signing secrets/,/^      - name: Clean build/{/^      - name: Clean build/!d}' codemagic.yaml
  sed -i '/^      - name: Clean build/i\      # after it confirmed CI signing is green (CI KEYSTORE CHECK: OK).' codemagic.yaml
  sed -i '/after it confirmed CI signing is green/i\      # v16'"'"'s temporary "Diagnose signing secrets" step was removed in v17' codemagic.yaml
fi

echo "==> v20: writing 12 text files + 10 icon images ..."

mkdir -p "$(dirname 'android/app/build.gradle.kts')"
cat > 'android/app/build.gradle.kts' <<'EOF_MARKER_0'
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
EOF_MARKER_0

mkdir -p "$(dirname 'android/app/src/main/AndroidManifest.xml')"
cat > 'android/app/src/main/AndroidManifest.xml' <<'EOF_MARKER_1'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
        tools:ignore="ScopedStorage" />

    <!-- Network: one-time AI model download + streaming URLs + DLNA cast control -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <!-- DLNA/UPnP casting: SSDP device discovery needs the multicast lock -->
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <application
        android:label="Max Player"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:resizeableActivity="true"
            android:supportsPictureInPicture="true"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />

            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>

            <!-- ================= Open with / Share ================= -->
            <!-- "Share -> Max Player" from any gallery, file manager, chat app -->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="video/*" />
            </intent-filter>

            <!-- Properly typed local videos (galleries, file managers) -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="content" android:mimeType="video/*" />
                <data android:scheme="file" android:mimeType="video/*" />
            </intent-filter>

            <!-- Typed video links in browsers -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="http" android:mimeType="video/*" />
                <data android:scheme="https" android:mimeType="video/*" />
            </intent-filter>

            <!-- Live streaming protocols -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="rtsp" />
                <data android:scheme="rtmp" />
                <data android:scheme="mms" />
            </intent-filter>

            <!-- Untyped URIs (FileProvider & friends): any mime, but the path
                 has a video extension. Lower- and upper-case patterns because
                 Android's pattern matching is case-sensitive. -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="file" />
                <data android:scheme="content" />
                <data android:host="*" />
                    <data android:pathPattern=".*\\.mp4" />
                    <data android:pathPattern=".*\\.MP4" />
                    <data android:pathPattern=".*\\.webm" />
                    <data android:pathPattern=".*\\.WEBM" />
                    <data android:pathPattern=".*\\.mkv" />
                    <data android:pathPattern=".*\\.MKV" />
                    <data android:pathPattern=".*\\.avi" />
                    <data android:pathPattern=".*\\.AVI" />
                    <data android:pathPattern=".*\\.mov" />
                    <data android:pathPattern=".*\\.MOV" />
                    <data android:pathPattern=".*\\.wmv" />
                    <data android:pathPattern=".*\\.WMV" />
                    <data android:pathPattern=".*\\.flv" />
                    <data android:pathPattern=".*\\.FLV" />
                    <data android:pathPattern=".*\\.m4v" />
                    <data android:pathPattern=".*\\.M4V" />
                    <data android:pathPattern=".*\\.3gp" />
                    <data android:pathPattern=".*\\.3GP" />
                    <data android:pathPattern=".*\\.3gpp" />
                    <data android:pathPattern=".*\\.3GPP" />
                    <data android:pathPattern=".*\\.ogv" />
                    <data android:pathPattern=".*\\.OGV" />
                    <data android:pathPattern=".*\\.ts" />
                    <data android:pathPattern=".*\\.TS" />
                    <data android:pathPattern=".*\\.mts" />
                    <data android:pathPattern=".*\\.MTS" />
                    <data android:pathPattern=".*\\.m2ts" />
                    <data android:pathPattern=".*\\.M2TS" />
                    <data android:pathPattern=".*\\.vob" />
                    <data android:pathPattern=".*\\.VOB" />
                    <data android:pathPattern=".*\\.mpg" />
                    <data android:pathPattern=".*\\.MPG" />
                    <data android:pathPattern=".*\\.mpeg" />
                    <data android:pathPattern=".*\\.MPEG" />
                    <data android:pathPattern=".*\\.rmvb" />
                    <data android:pathPattern=".*\\.RMVB" />
                    <data android:pathPattern=".*\\.divx" />
                    <data android:pathPattern=".*\\.DIVX" />
                    <data android:pathPattern=".*\\.f4v" />
                    <data android:pathPattern=".*\\.F4V" />
            </intent-filter>

            <!-- Videos wrongly typed as application/octet-stream (common on
                 Xiaomi/Oppo/Vivo/Realme galleries & some file managers). -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="file" />
                <data android:scheme="content" />
                <data android:scheme="http" />
                <data android:scheme="https" />
                <data android:host="*" />
                <data android:mimeType="application/octet-stream" />
                    <data android:pathPattern=".*\\.mp4" />
                    <data android:pathPattern=".*\\.MP4" />
                    <data android:pathPattern=".*\\.webm" />
                    <data android:pathPattern=".*\\.WEBM" />
                    <data android:pathPattern=".*\\.mkv" />
                    <data android:pathPattern=".*\\.MKV" />
                    <data android:pathPattern=".*\\.avi" />
                    <data android:pathPattern=".*\\.AVI" />
                    <data android:pathPattern=".*\\.mov" />
                    <data android:pathPattern=".*\\.MOV" />
                    <data android:pathPattern=".*\\.wmv" />
                    <data android:pathPattern=".*\\.WMV" />
                    <data android:pathPattern=".*\\.flv" />
                    <data android:pathPattern=".*\\.FLV" />
                    <data android:pathPattern=".*\\.m4v" />
                    <data android:pathPattern=".*\\.M4V" />
                    <data android:pathPattern=".*\\.3gp" />
                    <data android:pathPattern=".*\\.3GP" />
                    <data android:pathPattern=".*\\.3gpp" />
                    <data android:pathPattern=".*\\.3GPP" />
                    <data android:pathPattern=".*\\.ogv" />
                    <data android:pathPattern=".*\\.OGV" />
                    <data android:pathPattern=".*\\.ts" />
                    <data android:pathPattern=".*\\.TS" />
                    <data android:pathPattern=".*\\.mts" />
                    <data android:pathPattern=".*\\.MTS" />
                    <data android:pathPattern=".*\\.m2ts" />
                    <data android:pathPattern=".*\\.M2TS" />
                    <data android:pathPattern=".*\\.vob" />
                    <data android:pathPattern=".*\\.VOB" />
                    <data android:pathPattern=".*\\.mpg" />
                    <data android:pathPattern=".*\\.MPG" />
                    <data android:pathPattern=".*\\.mpeg" />
                    <data android:pathPattern=".*\\.MPEG" />
                    <data android:pathPattern=".*\\.rmvb" />
                    <data android:pathPattern=".*\\.RMVB" />
                    <data android:pathPattern=".*\\.divx" />
                    <data android:pathPattern=".*\\.DIVX" />
                    <data android:pathPattern=".*\\.f4v" />
                    <data android:pathPattern=".*\\.F4V" />
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
EOF_MARKER_1

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')"
cat > 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml' <<'EOF_MARKER_2'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
EOF_MARKER_2

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml')"
cat > 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml' <<'EOF_MARKER_3'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
EOF_MARKER_3

mkdir -p "$(dirname 'android/app/src/main/res/values/colors.xml')"
cat > 'android/app/src/main/res/values/colors.xml' <<'EOF_MARKER_4'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Adaptive launcher icon backdrop: white, matching the new neon icon art. -->
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
EOF_MARKER_4

mkdir -p "$(dirname 'lib/state/media_player_state.dart')"
cat > 'lib/state/media_player_state.dart' <<'EOF_MARKER_5'
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:media_kit_video/media_kit_video.dart';

import '../models/history_entry.dart';
import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../utils/formatters.dart';
import '../utils/srt.dart';
import 'player_settings.dart';

/// Mirrors the web app's useMediaPlayer hook, backed by media_kit's Player.
class MediaPlayerState extends ChangeNotifier {
  final Player player = Player();

  /// ONE video controller for the app's lifetime, created lazily.
  /// PlayerScreen used to construct a new VideoController on every visit and
  /// (with media_kit_video 1.3.x having no public dispose) those stacked up
  /// on the same player - one source of the fullscreen glitches.
  late final VideoController videoController = VideoController(player);

  List<VideoTrack> playlist = [];
  int currentIndex = 0;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 0.75; // 0..1
  bool isMuted = false;
  double playbackRate = 1.0;
  RepeatMode repeatMode = RepeatMode.none;
  bool isShuffled = false;
  bool isLoading = false;
  List<int> _shuffledOrder = [];

  // Available tracks of the currently loaded media (populated from streams).
  List<AudioTrack> audioTracks = [];
  List<SubtitleTrack> subtitleTracks = [];
  AudioTrack? currentAudioTrack;
  SubtitleTrack? currentSubtitleTrack;

  /// Short user-facing notices ("Resumed 12:34" etc) - the player screen
  /// shows these as a transient overlay indicator.
  final _notices = StreamController<String>.broadcast();
  Stream<String> get notices => _notices.stream;

  /// Periodic bookmark saver ("resume from where you left off").
  Timer? _bookmarkTimer;

  /// Last-used app-local brightness (left-half swipe in the player).
  double brightness = 1.0;
  bool _brightnessSynced = false;

  // --- A-B loop ---
  Duration? loopA;
  Duration? loopB;
  bool get abLoopActive => loopA != null && loopB != null;

  // --- Long-press speed boost ---
  double? _preBoostRate;

  /// True while the long-press speed boost is engaged; the player shows a
  /// persistent "Nx" badge for the whole boost, not just a flash.
  bool get isSpeedBoosting => _preBoostRate != null;

  // --- Equalizer (libmpv lavfi filter chain) ---
  static const List<int> eqFrequencies = [60, 230, 910, 3600, 14000];
  List<double> eqGains = List.filled(eqFrequencies.length, 0);
  bool eqEnabled = false;

  // --- Watch-time stats ---
  int _watchTodaySecs = 0;
  String _todayStatsKey = '';

  // --- Watch history (drives the home History screen + resume playback) ---
  final List<HistoryEntry> _history = [];
  bool _historyLoaded = false;
  static const String _kHistoryKey = 'history';
  static const int _kHistoryMax = 150;

  List<HistoryEntry> get history => List.unmodifiable(_history);

  VideoTrack? get currentTrack =>
      playlist.isNotEmpty && currentIndex < playlist.length
      ? playlist[currentIndex]
      : null;

  final _rand = Random();
  Timer? _uiTicker;
  late final List<StreamSubscription> _subs;

  MediaPlayerState() {
    _subs = [
      player.stream.playing.listen((v) {
        isPlaying = v;
        notifyListeners();
        // Keep the PiP window's play/pause remote action in sync
        // (native side ignores this when not in PiP).
        NativeBridge.setPipPlaying(v);
      }),
      player.stream.position.listen((v) {
        position = v;
        // Enforce the A-B loop window.
        final a = loopA;
        final b = loopB;
        if (a != null && b != null && b > a && v >= b) {
          player.seek(a);
        }
        notifyListeners();
      }),
      player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
        // Kick off scrub-preview thumbnail generation (idempotent - runs
        // once per file, cached on disk afterwards).
        _ensureThumbStrip();
      }),
      player.stream.buffering.listen((v) {
        isLoading = v;
        notifyListeners();
      }),
      player.stream.completed.listen((completed) {
        if (completed) _handleEnded();
      }),
      // Repopulates whenever a new media is opened.
      player.stream.tracks.listen((t) {
        audioTracks = t.audio;
        subtitleTracks = t.subtitle;
        notifyListeners();
      }),
      player.stream.track.listen((t) {
        currentAudioTrack = t.audio;
        currentSubtitleTrack = t.subtitle;
        notifyListeners();
      }),
    ];
    // libmpv stays at 100%: loudness is driven by the DEVICE media volume
    // (MX Player / VLC style) so the swipe can always reach the phone's
    // true maximum, no matter where the system volume started.
    player.setVolume(100);
    // Play/pause from the picture-in-picture window's own button.
    NativeBridge.configureCallbacks(onPipAction: togglePlay);
    _init();
    // Persist the resume point + watch time every few seconds.
    _bookmarkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveBookmark();
      _trackWatchTime();
    });
    // v19: guaranteed UI pulse - the mini player / scrub bar / time labels
    // keep ticking even if the position stream coalesces (the home-screen
    // mini player's progress bar looked frozen because of that).
    _uiTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!isPlaying) return;
      final p = player.state.position;
      if (p != position) {
        position = p;
        notifyListeners();
      }
    });
  }

  Future<void> _init() async {
    await _ensureHistoryLoaded();
    final s = await NativeBridge.loadSettings();
    // Restore today's accumulated watch time.
    _todayStatsKey = statsKeyFor(DateTime.now());
    _watchTodaySecs = int.tryParse(s[_todayStatsKey] ?? '') ?? 0;
    // Restore equalizer.
    eqEnabled = s[_kEqEnabledKey] == 'true';
    final gainsRaw = (s[_kEqGainsKey] ?? '').split(',');
    for (var i = 0; i < eqFrequencies.length && i < gainsRaw.length; i++) {
      eqGains[i] = double.tryParse(gainsRaw[i]) ?? 0;
    }
    if (eqEnabled) _applyEqFilter();
  }

  // ---------------------------------------------------------------------------
  // Watch history
  // ---------------------------------------------------------------------------

  Future<void> _ensureHistoryLoaded() async {
    if (_historyLoaded) return;
    _historyLoaded = true;
    try {
      final s = await NativeBridge.loadSettings();
      final raw = s[_kHistoryKey];
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _history
        ..clear()
        ..addAll([
          for (final e in list)
            HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        ]);
      notifyListeners();
    } catch (_) {
      // Corrupt payload -> start with an empty history.
    }
  }

  void _persistHistory() {
    final capped = _history.length > _kHistoryMax
        ? _history.sublist(0, _kHistoryMax)
        : _history;
    NativeBridge.saveSetting(
      _kHistoryKey,
      jsonEncode([for (final e in capped) e.toJson()]),
    );
  }

  HistoryEntry? _historyEntryFor(String path) {
    for (final e in _history) {
      if (e.path == path) return e;
    }
    return null;
  }

  /// Move the just-opened video to the top of the history, preserving its
  /// previous resume position.
  Future<void> _recordOpen(VideoTrack track) async {
    try {
      await _ensureHistoryLoaded();
      final prevPos = _historyEntryFor(track.path)?.lastPositionSecs ?? 0;
      _history.removeWhere((e) => e.path == track.path);
      _history.insert(
        0,
        HistoryEntry(
          path: track.path,
          title: track.title,
          thumbnailPath: track.thumbnailPath,
          durationSecs: track.duration?.inSeconds ?? 0,
          lastPositionSecs: prevPos,
          playedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _persistHistory();
      notifyListeners();
    } catch (_) {}
  }

  void clearHistory() {
    _history.clear();
    _persistHistory();
    notifyListeners();
  }

  void removeHistoryEntry(String path) {
    _history.removeWhere((e) => e.path == path);
    _persistHistory();
    notifyListeners();
  }

  /// Play a single video straight from a history row.
  Future<void> playHistoryEntry(HistoryEntry entry) async {
    final track = VideoTrack(
      id: entry.path,
      title: entry.title,
      path: entry.path,
      thumbnailPath: entry.thumbnailPath,
      duration: entry.durationSecs > 0
          ? Duration(seconds: entry.durationSecs)
          : null,
    );
    await setPlaylistAndPlay([track], 0);
  }

  /// Play a network stream URL (http/https/rtsp/rtmp). Handled directly by
  /// libmpv - the local-file metadata pipeline is skipped upstream.
  Future<void> playStream(String url, String title) async {
    final track = VideoTrack(id: url, title: title, path: url);
    await setPlaylistAndPlay([track], 0);
  }

  List<int> _generateShuffledOrder(int length, int currentIdx) {
    final indices = List.generate(length, (i) => i)..remove(currentIdx);
    indices.shuffle(_rand);
    return [currentIdx, ...indices];
  }

  int _getNextIndex({required bool forward}) {
    if (playlist.isEmpty) return 0;
    if (isShuffled && _shuffledOrder.isNotEmpty) {
      final pos = _shuffledOrder.indexOf(currentIndex);
      final len = _shuffledOrder.length;
      return forward
          ? _shuffledOrder[(pos + 1) % len]
          : _shuffledOrder[(pos - 1 + len) % len];
    }
    final len = playlist.length;
    return forward ? (currentIndex + 1) % len : (currentIndex - 1 + len) % len;
  }

  /// Replace the whole queue and start playing at [startIndex].
  Future<void> setPlaylistAndPlay(
    List<VideoTrack> videos, [
    int startIndex = 0,
  ]) async {
    playlist = videos;
    currentIndex = startIndex.clamp(0, videos.isEmpty ? 0 : videos.length - 1);
    notifyListeners();
    await _loadCurrent(autoplay: true);
  }

  Future<void> playTrack(int index) async {
    if (index < 0 || index >= playlist.length) return;
    currentIndex = index;
    notifyListeners();
    await _loadCurrent(autoplay: true);
  }

  Future<void> _loadCurrent({required bool autoplay}) async {
    final track = currentTrack;
    if (track == null) return;
    // A new file invalidates any A-B loop points from the previous one.
    loopA = null;
    loopB = null;
    await player.open(Media(track.path), play: autoplay);
    await player.setRate(playbackRate);
    await _attachSidecarSubtitles(track.path);
    await _recordOpen(track);
    await _restoreBookmark(track);
  }

  /// Re-attaches previously generated AI subtitles ("<video>.maxai.srt"
  /// next to the video) so they survive closing/reopening the app - they
  /// are written to disk, only the player session forgot them.
  Future<void> _attachSidecarSubtitles(String videoPath) async {
    if (videoPath.contains('://')) return; // no sidecars for streams
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      final srt = srtPathForVideo(videoPath);
      if (File(srt).existsSync()) {
        // "select" makes it the active track right away.
        await platform.command(['sub-add', srt, 'select']);
      }
    } catch (_) {
      // Missing/unreadable sidecar is not fatal.
    }
  }

  /// Jump to where the user left off last time this file was open. The saved
  /// position lives in the watch history; honours the "Resume playback"
  /// player setting.
  Future<void> _restoreBookmark(VideoTrack track) async {
    try {
      final settings = await NativeBridge.loadSettings();
      if (settings[PlayerSettings.kResumePlayback] == 'false') return;
      final secs = _historyEntryFor(track.path)?.lastPositionSecs ?? 0;
      if (secs < 10) return; // ignore tiny offsets

      var d = duration;
      if (d == Duration.zero) {
        // Wait briefly for the demuxer to report the length.
        d = await player.stream.duration
            .firstWhere((v) => v > Duration.zero)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => Duration.zero,
            );
      }
      if (d == Duration.zero) return;
      // Almost-finished videos start from the beginning again.
      if (secs >= d.inSeconds - 15) {
        final e = _historyEntryFor(track.path);
        if (e != null) {
          e.lastPositionSecs = 0;
          _persistHistory();
        }
        return;
      }
      // User may have switched tracks while we waited.
      if (currentTrack?.path != track.path) return;
      await player.seek(Duration(seconds: secs));
      _notices.add('Resumed ${formatDuration(Duration(seconds: secs))}');
    } catch (_) {
      // Resume is best-effort.
    }
  }

  void _saveBookmark() {
    final track = currentTrack;
    if (track == null || !isPlaying) return;
    final secs = position.inSeconds;
    if (secs <= 0) return;
    final entry = _historyEntryFor(track.path);
    if (entry != null && entry.lastPositionSecs != secs) {
      entry.lastPositionSecs = secs;
      _persistHistory();
    }
  }

  // ---------------------------------------------------------------------------
  // Brightness (left-half swipe in the player)
  // ---------------------------------------------------------------------------

  /// Reads the current override once so the first drag starts from the real
  /// screen brightness instead of a guess.
  Future<double> currentBrightness() async {
    if (!_brightnessSynced) {
      brightness = await NativeBridge.getBrightness();
      _brightnessSynced = true;
      notifyListeners();
    }
    return brightness;
  }

  Future<void> setBrightness(double v) async {
    brightness = v.clamp(0.0, 1.0);
    notifyListeners();
    await NativeBridge.setBrightness(brightness);
  }

  Future<void> resetBrightness() async {
    brightness = 1.0;
    _brightnessSynced = false;
    notifyListeners();
    await NativeBridge.resetBrightness();
  }

  Future<void> togglePlay() async {
    // v19: optimistic UI - flip the icon instantly; the playing stream
    // confirms (or corrects) a moment later. Kills the visible tap->icon
    // lag that made the play/pause button feel delayed.
    final wantPlay = !isPlaying;
    isPlaying = wantPlay;
    notifyListeners();
    if (wantPlay) {
      await player.play();
    } else {
      await pause();
    }
  }

  /// Unconditional resume (used when handing playback back from a TV cast
  /// session - togglePlay would pause if the user already resumed).
  Future<void> resumePlayback() => player.play();

  /// Saves the CURRENT video frame exactly as shown (subtitles included)
  /// as a PNG into /storage/emulated/0/Pictures/Max Player and registers it
  /// with the media scanner so gallery apps see it immediately.
  ///
  /// Returns the saved path, or null when there is nothing to capture
  /// (no video, or a network stream) or the capture failed.
  Future<String?> captureScreenshot() async {
    final track = currentTrack;
    if (track == null) return null;
    if (track.path.startsWith('http')) return null; // stream: nothing on disk
    final platform = player.platform;
    if (platform is! NativePlayer) return null;
    try {
      final dir = Directory('/storage/emulated/0/Pictures/Max Player');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final out =
          '${dir.path}/MaxPlayer_${DateTime.now().millisecondsSinceEpoch}.png';
      // libmpv command; plain (non-async) screenshot-to-file blocks mpv's
      // core until the PNG is written, then we verify from Dart.
      await platform.command(['screenshot-to-file', out]);
      final f = File(out);
      for (var i = 0; i < 20; i++) {
        if (f.existsSync() && f.lengthSync() > 0) {
          await NativeBridge.scanFile(out);
          return out;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> pause() async {
    // v20: pause FIRST so the video freezes instantly. The previous order
    // (boost cleanup + bookmark disk write BEFORE pausing) added a visible
    // delay between tapping pause and the video actually stopping.
    await player.pause();
    // Pausing always ends an active long-press boost (and its badge).
    await stopSpeedBoost();
    _saveBookmark();
  }

  Future<void> seek(Duration to) => player.seek(to);

  /// Relative seek (e.g. ±10s), clamped to the media bounds.
  Future<void> seekBy(int seconds) async {
    if (currentTrack == null) return;
    var target = position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await player.seek(target);
  }

  // ---------------------------------------------------------------------------
  // Volume (device MEDIA volume, MX Player / VLC style)
  // ---------------------------------------------------------------------------

  bool _volumeSynced = false;
  double _preMuteVolume = 0.5;

  /// Reads the real device media volume once so the player swipe starts
  /// from the true level (mirrors [currentBrightness]).
  Future<double> currentVolume() async {
    if (!_volumeSynced) {
      volume = await NativeBridge.getMediaVolume();
      isMuted = volume <= 0;
      _volumeSynced = true;
      notifyListeners();
    }
    return volume;
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    if (volume > 0) {
      isMuted = false;
      _preMuteVolume = volume;
    }
    await NativeBridge.setMediaVolume(isMuted ? 0 : volume);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    if (isMuted) {
      isMuted = false;
      if (volume <= 0) volume = _preMuteVolume;
      await NativeBridge.setMediaVolume(volume);
    } else {
      if (volume > 0) _preMuteVolume = volume;
      isMuted = true;
      await NativeBridge.setMediaVolume(0);
    }
    notifyListeners();
  }

  Future<void> setPlaybackRate(double rate) async {
    playbackRate = rate;
    await player.setRate(rate);
    notifyListeners();
  }

  /// Switch to a different audio track (e.g. Hindi / English in dual-audio
  /// files). Pass an entry of [audioTracks].
  void selectAudioTrack(AudioTrack track) => player.setAudioTrack(track);

  /// Switch subtitle track; pass SubtitleTrack.no() to turn subtitles off.
  void selectSubtitleTrack(SubtitleTrack track) =>
      player.setSubtitleTrack(track);

  /// True when a real subtitle track (not "no"/off) is currently active.
  bool get subtitlesActive =>
      currentSubtitleTrack != null && currentSubtitleTrack!.id != 'no';

  // ---------------------------------------------------------------------------
  // A-B loop
  // ---------------------------------------------------------------------------

  /// Button callback: 1st tap sets A, 2nd sets B (loop starts), 3rd clears.
  /// Returns a short message for the on-screen indicator.
  String tapLoopPoint() {
    if (loopA == null) {
      loopA = position;
      notifyListeners();
      return 'A set ${formatDuration(position)}';
    }
    if (loopB == null) {
      // Ignore a B that's not after A (user double-tapped by accident).
      if (position <= loopA! + const Duration(seconds: 1)) {
        loopA = position;
        notifyListeners();
        return 'A set ${formatDuration(position)}';
      }
      loopB = position;
      notifyListeners();
      return 'Looping ${formatDuration(loopA!)} → ${formatDuration(loopB!)}';
    }
    loopA = null;
    loopB = null;
    notifyListeners();
    return 'A-B loop cleared';
  }

  // ---------------------------------------------------------------------------
  // Long-press speed boost (customizable multiplier)
  // ---------------------------------------------------------------------------

  Future<void> startSpeedBoost(double multiplier) async {
    if (_preBoostRate != null) return; // already boosting
    if (!isPlaying) return; // no boost/badge while paused
    _preBoostRate = playbackRate;
    playbackRate = multiplier;
    await player.setRate(multiplier);
    notifyListeners();
  }

  Future<void> stopSpeedBoost() async {
    final restore = _preBoostRate;
    if (restore == null) return;
    _preBoostRate = null;
    playbackRate = restore;
    await player.setRate(restore);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Equalizer (libmpv `af` lavfi chain)
  // ---------------------------------------------------------------------------

  static const String _kEqEnabledKey = 'eq.enabled';
  static const String _kEqGainsKey = 'eq.gains';

  /// Builds the lavfi audio-filter chain, skipping bands at 0 dB.
  /// Pure + testable.
  static String buildEqualizerFilter(List<double> gains) {
    final parts = <String>[];
    for (var i = 0; i < eqFrequencies.length && i < gains.length; i++) {
      if (gains[i] == 0) continue;
      parts.add(
        'equalizer=f=${eqFrequencies[i]}:t=q:w=1.0:g=${gains[i].toStringAsFixed(1)}',
      );
    }
    return parts.isEmpty ? '' : 'lavfi=[${parts.join(',')}]';
  }

  Future<void> applyEqualizer(List<double> gains, bool enabled) async {
    eqGains = List.of(gains);
    eqEnabled = enabled;
    NativeBridge.saveSetting(_kEqEnabledKey, '$enabled');
    NativeBridge.saveSetting(
      _kEqGainsKey,
      gains.map((g) => g.toStringAsFixed(1)).join(','),
    );
    notifyListeners();
    await _applyEqFilter();
  }

  Future<void> _applyEqFilter() async {
    final platform = player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty(
          'af',
          eqEnabled ? buildEqualizerFilter(eqGains) : '',
        );
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Watch-time stats
  // ---------------------------------------------------------------------------

  /// Persisted key for a day bucket, e.g. stats.20260811. Pure + testable.
  static String statsKeyFor(DateTime d) =>
      'stats.${d.year * 10000 + d.month * 100 + d.day}';

  void _trackWatchTime() {
    if (!isPlaying) return;
    final key = statsKeyFor(DateTime.now());
    if (key != _todayStatsKey) {
      // Day rolled over while playing.
      _todayStatsKey = key;
      _watchTodaySecs = 0;
    }
    _watchTodaySecs += 5;
    NativeBridge.saveSetting(key, '$_watchTodaySecs');
  }

  /// Last 7 days of watch time (index 0 = 6 days ago, last = today).
  Future<List<WatchDay>> getWeekStats() async {
    final s = await NativeBridge.loadSettings();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    final days = <WatchDay>[];
    for (var i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = statsKeyFor(d);
      var secs = int.tryParse(s[key] ?? '') ?? 0;
      if (key == todayKey && _watchTodaySecs > secs) secs = _watchTodaySecs;
      days.add(WatchDay(d, secs));
    }
    return days;
  }

  // ---------------------------------------------------------------------------
  // Scrub preview thumbnail strip (v19)
  // ---------------------------------------------------------------------------

  /// Frames generated per video - must match the native generator
  /// (MainActivity.thumbStripEnsureSync).
  static const int thumbStripCount = 72;

  String? _thumbStripFor;
  String? _thumbStripDir;

  void _ensureThumbStrip() {
    final track = currentTrack;
    if (track == null) return;
    final path = track.path;
    if (path.startsWith('http')) return; // streams: nothing on disk to scan
    if (_thumbStripFor == path) return; // already requested for this file
    _thumbStripFor = path;
    _thumbStripDir = null;
    NativeBridge.thumbStripEnsure(path).then((dir) {
      if (dir != null && _thumbStripFor == path) {
        _thumbStripDir = dir;
        notifyListeners();
      }
    });
  }

  /// Thumbnail file for the preview bubble at [fraction] (0..1 of the
  /// video), or null while that frame hasn't been generated yet (the
  /// bubble then shows the timestamp only).
  String? scrubThumbPath(double fraction) {
    final dir = _thumbStripDir;
    if (dir == null) return null;
    final i = (fraction.clamp(0.0, 1.0) * (thumbStripCount - 1)).round();
    final f = File('$dir/f_${i.toString().padLeft(3, '0')}.jpg');
    return f.existsSync() ? f.path : null;
  }

  // ---------------------------------------------------------------------------
  // Mini player
  // ---------------------------------------------------------------------------

  /// Dismisses the mini player: clears the queue and stops playback.
  Future<void> stopMini() async {
    playlist = [];
    currentIndex = 0;
    notifyListeners();
    await player.stop();
  }

  Future<void> nextTrack() async {
    if (playlist.length <= 1) return;
    await playTrack(_getNextIndex(forward: true));
  }

  Future<void> prevTrack() async {
    if (position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (playlist.length <= 1) return;
    await playTrack(_getNextIndex(forward: false));
  }

  void toggleRepeat() {
    repeatMode = switch (repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.none,
    };
    notifyListeners();
  }

  void toggleShuffle() {
    isShuffled = !isShuffled;
    if (isShuffled) {
      _shuffledOrder = _generateShuffledOrder(playlist.length, currentIndex);
    }
    notifyListeners();
  }

  Future<void> removeFromPlaylist(int index) async {
    final wasCurrent = index == currentIndex;
    playlist = [...playlist]..removeAt(index);
    if (playlist.isEmpty) {
      currentIndex = 0;
      await player.stop();
    } else if (wasCurrent) {
      currentIndex = currentIndex.clamp(0, playlist.length - 1);
      await _loadCurrent(autoplay: false);
    } else if (index < currentIndex) {
      currentIndex -= 1;
    }
    notifyListeners();
  }

  Future<void> _handleEnded() async {
    // Completed video: reset its saved position so it replays from the start.
    final track = currentTrack;
    if (track != null) {
      final e = _historyEntryFor(track.path);
      if (e != null) {
        e.lastPositionSecs = 0;
        _persistHistory();
      }
    }
    if (repeatMode == RepeatMode.one) {
      await player.seek(Duration.zero);
      await player.play();
    } else if (repeatMode == RepeatMode.all ||
        currentIndex < playlist.length - 1) {
      await nextTrack();
    }
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    _bookmarkTimer?.cancel();
    _notices.close();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}

/// One day of watch time for the stats screen.
class WatchDay {
  final DateTime day;
  final int seconds;
  const WatchDay(this.day, this.seconds);
}
EOF_MARKER_5

mkdir -p "$(dirname 'lib/screens/player_screen.dart')"
cat > 'lib/screens/player_screen.dart' <<'EOF_MARKER_6'
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../cast/cast_state.dart';
import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/player_settings.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import '../utils/srt.dart';
import '../widgets/cast_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/player_settings_sheet.dart';
import '../widgets/playlist_panel.dart';
import '../widgets/video_info_sheet.dart';

class PlayerScreen extends StatefulWidget {
  final MediaPlayerState player;

  const PlayerScreen({super.key, required this.player});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  // Shared, app-lifetime controller owned by MediaPlayerState (this media_kit
  // version has no VideoController.dispose, so per-visit controllers leaked).
  late final VideoController _controller = widget.player.videoController;

  /// DLNA cast session for this visit to the player. Disposed with the
  /// screen (leaving the player stops casting).
  final CastState _castState = CastState();

  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _showQueue = false;
  bool _isPip = false;

  /// Screen lock (kids mode): every gesture/button is swallowed until the
  /// on-screen lock is double-tapped (or long-pressed).
  bool _locked = false;

  // Orientation lock (rotation toggle in the controls).
  bool _orientationLocked = false;
  List<DeviceOrientation> _lockedOrientations = DeviceOrientation.values;

  // Customizable behavior (persisted, edited in the Settings sheet).
  PlayerSettings _settings = const PlayerSettings();

  Timer? _hideTimer;

  // Transient center indicator ("+10s", "Volume 80%", "Resumed 12:34", ...).
  String? _indicatorText;
  IconData? _indicatorIcon;
  String? _indicatorKey; // dedupe: identical text just refreshes the timer
  Timer? _indicatorTimer;
  StreamSubscription<String>? _noticeSub;

  // v20 fit cycle with REAL size choices (the old contain/cover/fill trio
  // looked identical for 16:9 videos, so it felt like "fit does nothing").
  // aspectRatio forces the frame to that shape (stretch); null keeps the
  // video's own aspect ratio.
  static const List<BoxFit> _fits = [
    BoxFit.contain, // Fit - whole frame visible
    BoxFit.cover, // Crop - fill screen, edges cropped
    BoxFit.fill, // Stretch - fill screen, ignores aspect
    BoxFit.fill, // 16:9 - frame forced to widescreen
    BoxFit.fill, // 4:3 - frame forced to classic TV
    BoxFit.none, // Original - pixels 1:1, may overflow
  ];
  static const List<double?> _fitAspects = [null, null, null, 16 / 9, 4 / 3, null];
  static const List<String> _fitNames = [
    'Fit',
    'Crop',
    'Stretch',
    '16:9',
    '4:3',
    'Original',
  ];
  int _fitIndex = 0;
  static const List<IconData> _fitIcons = [
    Icons.fit_screen,
    Icons.crop,
    Icons.open_in_full,
    Icons.crop_16_9,
    Icons.crop_landscape,
    Icons.crop_original,
  ];

  // Pinch zoom (1x..4x), anchored at the fingers' focal point, with
  // one-finger panning while zoomed.
  double _zoom = 1.0;
  double _zoomBase = 1.0;
  Offset _pan = Offset.zero;
  Offset _panBase = Offset.zero;
  Offset _focalBase = Offset.zero;

  // Gesture plumbing (double-tap seek / unified drag handling).
  double _gestureWidth = 0;
  double _gestureHeight = 0;
  double _lastDoubleTapDx = 0;

  // --- Unified single-recognizer drag handling -----------------------------
  //
  // EVERYTHING drag-ish (volume / brightness / horizontal seek / zoom-pan)
  // is handled through the scale recognizer only. The old code ALSO
  // registered onVerticalDrag* on the same GestureDetector, and the two
  // recognizers fought in the gesture arena - whichever won was decided by
  // tiny direction differences, which is exactly what made the volume swipe
  // feel "glitchy". One recognizer = deterministic behavior.
  _ScaleMode _scaleMode = _ScaleMode.undecided;
  Offset _dragAccum = Offset.zero;
  Offset _focalStart = Offset.zero;
  double _dragStartValue = 0;

  // Horizontal seek drag.
  Duration _seekBasePos = Duration.zero;
  Duration? _seekTarget;
  int _seekLastAppliedSec = -1;

  // Volume drag dedupe (cuts mpv IPC + indicator reflows ~10x).
  int _lastVolPct = -1;

  // NOTE: no addListener/setState on the player here. The ticking parts
  // (overlay, spinner, queue, title) listen via their own AnimatedBuilder,
  // so the video surface itself is never rebuilt during playback.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // v19: rotation is driven by our own accelerometer listener, so the
    // player rotates even when the phone's auto-rotate switch is OFF
    // (MX Player / VLC style). The lock chip pins the current orientation;
    // dispose() hands control back to the system.
    unawaited(NativeBridge.enableSensorRotate());
    _noticeSub = widget.player.notices.listen(
      (m) => _showIndicator(m, Icons.history),
    );
    NativeBridge.configureCallbacks(
      onPipChanged: (isPip) {
        if (mounted) setState(() => _isPip = isPip);
      },
    );
    _reloadSettings();
    widget.player.currentBrightness(); // sync once for the swipe gesture
    widget.player.currentVolume(); // start swipe from REAL device volume
    _startHideTimer();
  }

  @override
  void dispose() {
    _castState.dispose(); // stops casting + the embedded file server
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _noticeSub?.cancel();
    if (_isFullscreen) _exitFullscreen();
    // Hand rotation control back to the system; never leave a lock behind.
    unawaited(NativeBridge.disableSensorRotate());
    // Do NOT keep the audio running after leaving the player screen, and
    // hand brightness control back to the system.
    unawaited(widget.player.pause());
    unawaited(widget.player.resetBrightness());
    super.dispose();
  }

  /// Pause when the app goes to the background (sound must not keep playing
  /// with the app hidden).
  ///
  /// IMPORTANT: entering picture-in-picture maps to AppLifecycleState.
  /// inactive on Android - we must NOT pause for it, and we must skip the
  /// fully-backgrounded states while the PiP window is up. Otherwise PiP
  /// would freeze the video the moment it opens.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isPip) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.player.pause();
    }
  }

  Future<void> _reloadSettings() async {
    final s = await PlayerSettings.load();
    if (mounted) setState(() => _settings = s);
    _startHideTimer();
  }

  Future<void> _openSettings() async {
    await PlayerSettingsSheet.show(context);
    await _reloadSettings(); // apply changes immediately
  }

  // ---------------------------------------------------------------------------
  // Controls visibility (auto-hide)
  // ---------------------------------------------------------------------------

  void _startHideTimer() {
    _hideTimer?.cancel();
    final delay = _settings.autoHideSeconds;
    if (delay <= 0) return; // "never auto-hide"
    _hideTimer = Timer(Duration(seconds: delay), () {
      // Only auto-hide during playback; keep controls up while paused.
      if (mounted && widget.player.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  /// Called by the overlay on every button press / seek / menu selection so
  /// the auto-hide countdown restarts on any interaction.
  void _onUserInteraction() {
    if (_controlsVisible) _startHideTimer();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  // ---------------------------------------------------------------------------
  // Screen lock (kids mode)
  // ---------------------------------------------------------------------------

  void _lockScreen() {
    _hideTimer?.cancel();
    setState(() {
      _locked = true;
      _controlsVisible = false;
    });
    _showIndicator('Screen locked', Icons.lock);
  }

  void _unlockScreen() {
    setState(() {
      _locked = false;
      _controlsVisible = true;
    });
    _startHideTimer();
    _showIndicator('Unlocked', Icons.lock_open);
  }

  void _showLockHint() {
    _showIndicator('Locked - double-tap the lock to unlock', Icons.lock);
  }

  // ---------------------------------------------------------------------------
  // Transient indicator
  // ---------------------------------------------------------------------------

  void _showIndicator(String text, [IconData? icon]) {
    if (!mounted) return;
    _indicatorTimer?.cancel();
    _indicatorKey = '$text|${icon?.codePoint ?? 0}';
    setState(() {
      _indicatorText = text;
      _indicatorIcon = icon;
    });
    _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _indicatorText = null);
    });
  }

  /// Same as [_showIndicator] but an unchanged message only refreshes the
  /// hide timer (no setState flood while a drag gesture keeps reporting the
  /// same percentage).
  void _showIndicatorThrottled(String text, [IconData? icon]) {
    if (!mounted) return;
    final key = '$text|${icon?.codePoint ?? 0}';
    if (key == _indicatorKey) {
      _indicatorTimer?.cancel();
      _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _indicatorText = null);
      });
      return;
    }
    _showIndicator(text, icon);
  }

  // ---------------------------------------------------------------------------
  // Fullscreen, fit, zoom
  // ---------------------------------------------------------------------------

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      _exitFullscreen();
    }
    _onUserInteraction();
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Respect an active rotation lock when leaving fullscreen.
    SystemChrome.setPreferredOrientations(
      _orientationLocked ? _lockedOrientations : DeviceOrientation.values,
    );
  }

  /// Rotation toggle: sensor auto-rotate <-> pinned to portrait/landscape.
  void _toggleOrientationLock() {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (!_orientationLocked) {
      unawaited(NativeBridge.lockRotation(landscape: landscape));
      setState(() {
        _orientationLocked = true;
        _lockedOrientations = landscape
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ];
      });
      _showIndicator('Rotation locked', Icons.screen_lock_rotation);
    } else {
      _lockedOrientations = DeviceOrientation.values;
      setState(() => _orientationLocked = false);
      unawaited(NativeBridge.enableSensorRotate());
      _showIndicator('Auto-rotate on', Icons.screen_rotation);
    }
    _onUserInteraction();
  }

  // ---------------------------------------------------------------------------
  // Long-press speed boost (customizable multiplier)
  // ---------------------------------------------------------------------------

  void _onLongPressStart(LongPressStartDetails _) {
    if (!_settings.longPressSpeed) return;
    // No boost (and no badge) while the video is paused.
    if (!widget.player.isPlaying) return;
    widget.player.startSpeedBoost(_settings.longPressMultiplier);
    setState(() {}); // mount the persistent "Nx" badge
    // NOTE: no flash indicator here - the persistent purple badge IS the
    // feedback (showing both looked like a duplicated "2x" bug).
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    widget.player.stopSpeedBoost();
    setState(() {}); // remove the persistent badge
  }

  void _cycleFit() {
    setState(() => _fitIndex = (_fitIndex + 1) % _fits.length);
    _showIndicator('Fit: ${_fitNames[_fitIndex]}', _fitIcons[_fitIndex]);
    _onUserInteraction();
  }

  // ---------------------------------------------------------------------------
  // Unified scale recognizer (pinch zoom + ALL drag gestures)
  // ---------------------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails details) {
    _scaleMode = _ScaleMode.undecided;
    _dragAccum = Offset.zero;
    _focalStart = details.localFocalPoint;
    _zoomBase = _zoom;
    _panBase = _pan;
    _focalBase = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Two+ fingers -> pinch zoom (focal-anchored).
    if (details.pointerCount >= 2) {
      if (!_settings.pinchZoom) return;
      _scaleMode = _ScaleMode.zoom;

      // Focal-anchored transform: the content point that was under the
      // fingers when the pinch started stays glued to the CURRENT focal
      // point. Because we track the live focal point, moving both fingers
      // together pans the zoomed video for free.
      final z = (_zoomBase * details.scale).clamp(1.0, 4.0);
      final contentV = (_focalBase - _panBase) / _zoomBase;
      final pan = _clampPan(details.localFocalPoint - contentV * z, z);

      if (z == _zoom && pan == _pan) return;
      setState(() {
        _zoom = z;
        _pan = pan;
      });
      if (details.scale != 1.0) {
        _showIndicator('Zoom ${z.toStringAsFixed(1)}x', Icons.pinch_outlined);
      }
      return;
    }

    // One finger -> figure out WHAT the drag is once we're past the slop,
    // then stick with that mode until the gesture ends.
    switch (_scaleMode) {
      case _ScaleMode.zoom:
        return; // came from two fingers; ignore until scale end
      case _ScaleMode.cant:
        return; // all relevant gestures are disabled
      case _ScaleMode.volume:
      case _ScaleMode.brightness:
        _dragAccum += details.focalPointDelta;
        _applyLevelDrag();
        return;
      case _ScaleMode.seekH:
        _dragAccum += details.focalPointDelta;
        _applySeekDrag();
        return;
      case _ScaleMode.pan:
        _applyPanDrag(details);
        return;
      case _ScaleMode.undecided:
        _dragAccum += details.focalPointDelta;
        if (_dragAccum.distance < 14) return; // slop
        final dx = _dragAccum.dx.abs();
        final dy = _dragAccum.dy.abs();
        if (dx > dy * 1.3) {
          // Horizontal: seek (or pan when zoomed in).
          if (_zoom > 1.0) {
            _scaleMode = _ScaleMode.pan;
            _applyPanDrag(details);
          } else if (_settings.horizontalSeek &&
              widget.player.currentTrack != null &&
              widget.player.duration > Duration.zero) {
            _scaleMode = _ScaleMode.seekH;
            _seekBasePos = widget.player.position;
            _seekTarget = null;
            _seekLastAppliedSec = -1;
            _dragAccum = Offset.zero;
          } else {
            _scaleMode = _ScaleMode.cant;
          }
        } else {
          // Vertical: volume (right half) or brightness (left half).
          final rightHalf = _focalStart.dx > _gestureWidth / 2;
          if (rightHalf && _settings.volumeSwipe) {
            _scaleMode = _ScaleMode.volume;
            _lastVolPct = (widget.player.isMuted
                    ? 0.0
                    : widget.player.volume * 100)
                .round();
            _dragStartValue =
                widget.player.isMuted ? 0.0 : widget.player.volume;
          } else if (!rightHalf && _settings.brightnessSwipe) {
            _scaleMode = _ScaleMode.brightness;
            _dragStartValue = widget.player.brightness;
          } else {
            _scaleMode = _ScaleMode.cant;
            return;
          }
          _dragAccum = Offset.zero;
        }
        return;
    }
  }

  /// Volume / brightness value from the accumulated vertical movement.
  void _applyLevelDrag() {
    // Dragging up increases; a 300px sweep covers the full 0..100% range.
    final v = (_dragStartValue - _dragAccum.dy / 300).clamp(0.0, 1.0);
    if (_scaleMode == _ScaleMode.volume) {
      final pct = (v * 100).round();
      if (pct == _lastVolPct) return; // spare mpv from per-pixel IPC
      _lastVolPct = pct;
      widget.player.setVolume(v);
      _showIndicatorThrottled(
        'Volume $pct%',
        pct == 0 ? Icons.volume_off : Icons.volume_up,
      );
    } else {
      widget.player.setBrightness(v);
      _showIndicatorThrottled(
        'Brightness ${(v * 100).round()}%',
        Icons.brightness_6_outlined,
      );
    }
  }

  /// Horizontal scrub: a full screen-width drag is +-90 seconds. Seeks live
  /// in whole-second steps (mpv is fine with it) and lands exactly on end.
  void _applySeekDrag() {
    final dur = widget.player.duration;
    if (dur <= Duration.zero) return;
    final offsetSec = _dragAccum.dx / _gestureWidth * 90.0;
    final targetMs =
        (_seekBasePos.inMilliseconds + (offsetSec * 1000).round())
            .clamp(0, dur.inMilliseconds);
    final target = Duration(milliseconds: targetMs);
    _seekTarget = target;
    final diffMs = targetMs - _seekBasePos.inMilliseconds;
    final sign = diffMs >= 0 ? '+' : '-';
    _showIndicatorThrottled(
      '$sign${(diffMs.abs() / 1000).round()}s · ${formatDuration(target)}',
      diffMs >= 0 ? Icons.fast_forward : Icons.fast_rewind,
    );
    // Live-seek in 1s steps while the finger moves.
    final s = target.inSeconds;
    if ((s - _seekLastAppliedSec).abs() >= 1) {
      _seekLastAppliedSec = s;
      widget.player.seek(Duration(seconds: s));
    }
  }

  /// One-finger panning while zoomed in.
  void _applyPanDrag(ScaleUpdateDetails details) {
    if (_zoom <= 1.0) return;
    final pan = _clampPan(
      _panBase + (details.localFocalPoint - _focalBase),
      _zoom,
    );
    if (pan != _pan) setState(() => _pan = pan);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final mode = _scaleMode;
    _scaleMode = _ScaleMode.undecided;
    if (mode == _ScaleMode.seekH) {
      final t = _seekTarget;
      if (t != null) widget.player.seek(t); // exact final landing
      _seekTarget = null;
      return;
    }
    if (mode == _ScaleMode.volume || mode == _ScaleMode.brightness) return;
    if (!_settings.pinchZoom && mode != _ScaleMode.pan) return;
    // Snap back when barely zoomed.
    if (_zoom < 1.1) {
      if (_zoom != 1.0 || _pan != Offset.zero) {
        setState(() {
          _zoom = 1.0;
          _pan = Offset.zero;
        });
      }
    } else {
      setState(() => _pan = _clampPan(_pan, _zoom));
    }
  }

  /// Keep the scaled video covering the viewport (no drifting past edges).
  Offset _clampPan(Offset pan, double z) {
    final maxX = _gestureWidth * (z - 1);
    final maxY = _gestureHeight * (z - 1);
    return Offset(pan.dx.clamp(-maxX, 0.0), pan.dy.clamp(-maxY, 0.0));
  }

  // ---------------------------------------------------------------------------
  // Tap gestures
  // ---------------------------------------------------------------------------

  void _onDoubleTap() {
    final third = _gestureWidth / 3;
    if (_lastDoubleTapDx < third) {
      if (!_settings.doubleTapSeek) return;
      widget.player.seekBy(-_settings.seekSeconds);
      _showIndicator('-${_settings.seekSeconds}s', Icons.replay_10);
    } else if (_lastDoubleTapDx > _gestureWidth - third) {
      if (!_settings.doubleTapSeek) return;
      widget.player.seekBy(_settings.seekSeconds);
      _showIndicator('+${_settings.seekSeconds}s', Icons.forward_10);
    } else {
      // Middle third: play / pause.
      if (!_settings.doubleTapPlayPause) return;
      final wasPlaying = widget.player.isPlaying;
      widget.player.togglePlay();
      _showIndicator(
        wasPlaying ? 'Paused' : 'Playing',
        wasPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Screenshot + cast
  // ---------------------------------------------------------------------------

  Future<void> _takeScreenshot() async {
    final path = await widget.player.captureScreenshot();
    if (!mounted) return;
    _showIndicator(
      path == null
          ? 'Screenshot unavailable for streams'
          : 'Screenshot saved to gallery',
      path == null ? Icons.error_outline : Icons.camera_alt,
    );
  }

  Future<void> _openCast() async {
    final track = widget.player.currentTrack;
    if (track == null) {
      _showIndicator('Nothing to cast - open a video first',
          Icons.videocam_off_outlined);
      return;
    }
    // Offer AI-generated subtitles to the TV when they exist on disk.
    String? subsPath;
    if (!track.path.startsWith('http')) {
      final srt = srtPathForVideo(track.path);
      if (File(srt).existsSync()) subsPath = srt;
    }
    // Kick off the device scan right away (the sheet renders its states).
    unawaited(_castState.scan());
    await CastSheet.show(
      context,
      _castState,
      videoPath: track.path,
      title: track.title,
      subsPath: subsPath,
      onCastStarted: () {
        widget.player.pause(); // the TV is playing; phone becomes remote
        _showIndicator('Casting to TV', Icons.cast_connected);
      },
      onCastStopped: (tvPos) async {
        // Hand playback back to the phone at the TV's position.
        if (tvPos > Duration.zero) await widget.player.seek(tvPos);
        await widget.player.resumePlayback();
        if (mounted) _showIndicator('Back on this phone', Icons.smartphone);
      },
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    return PopScope(
      canPop: !_isFullscreen && !_locked,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_locked) {
          _showLockHint();
        } else {
          _toggleFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // v19: no Scaffold AppBar anymore - the title + actions live in an
        // auto-hiding top overlay INSIDE the video stack, so portrait video
        // gets the full height and a tap reveals title and controls
        // together (previously a tap surfaced only the bottom bar).
        body: SafeArea(
          top: !_isFullscreen,
          // v20: in LANDSCAPE the controls sit flush with the bottom edge
          // (requested - "one step down"); portrait keeps the gesture-bar
          // clearance so the seek bar is not touched by the system bar.
          bottom: MediaQuery.of(context).orientation == Orientation.portrait,
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _gestureWidth = constraints.maxWidth;
                    _gestureHeight = constraints.maxHeight;
                    return GestureDetector(
                      // While locked every gesture collapses to a lock hint.
                      onTap: _locked ? _showLockHint : _toggleControls,
                      onDoubleTapDown: _locked
                          ? null
                          : (d) => _lastDoubleTapDx = d.localPosition.dx,
                      onDoubleTap: _locked ? null : _onDoubleTap,
                      onLongPressStart: _locked ? null : _onLongPressStart,
                      onLongPressEnd: _locked ? null : _onLongPressEnd,
                      onScaleStart:
                          _locked ? (_) => _showLockHint() : _onScaleStart,
                      onScaleUpdate: _locked ? null : _onScaleUpdate,
                      onScaleEnd: _locked ? null : _onScaleEnd,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Video surface - pinch zoom/pan applies a matrix
                          // (scale about the finger focal point), clipped to
                          // the available area.
                          Positioned.fill(
                            child: ClipRect(
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
                                  ..scaleByDouble(_zoom, _zoom, _zoom, 1),
                                child: Center(
                                  child: player.currentTrack != null
                                      ? RepaintBoundary(
                                          child: Video(
                                            controller: _controller,
                                            controls: NoVideoControls,
                                            fit: _fits[_fitIndex],
                                            // v20: forces the frame to 16:9 /
                                            // 4:3 in those fit modes; null
                                            // keeps the video's own ratio.
                                            aspectRatio: _fitAspects[_fitIndex],
                                          ),
                                        )
                                      : const Text(
                                          'No video loaded',
                                          style: TextStyle(
                                            color: Colors.white38,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                          // Buffering spinner - follows the player stream only.
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: player,
                              builder: (context, _) => player.isLoading
                                  ? Center(
                                      child: CircularProgressIndicator(
                                        color: themeState.accent,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          // Transient indicator (seek / volume / brightness /
                          // zoom / resume / fit / play-pause) - pops in and
                          // out with a small scale+fade.
                          Positioned(
                            top: 72,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Center(
                                // v19: this sign used to BLINK during
                                // volume/brightness swipes - the old
                                // switcher re-keyed itself on every tick,
                                // replaying a scale animation each time.
                                // Now: ONE stable container, only opacity
                                // animates, text/icon swap in place.
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 120),
                                  opacity: (_indicatorText != null && !_isPip)
                                      ? 1.0
                                      : 0.0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.72,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        12,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_indicatorIcon != null) ...[
                                          Icon(
                                            _indicatorIcon,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          _indicatorText ?? '',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // v20: BIG centred "2x" sign in the MIDDLE of the
                          // video for the WHOLE long-press boost (replaces the
                          // small top badge). Follows the player state
                          // directly, so it vanishes the moment the video is
                          // paused during a boost.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: AnimatedBuilder(
                                  animation: player,
                                  builder: (context, _) => AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 160),
                                    transitionBuilder: (child, anim) =>
                                        FadeTransition(
                                          opacity: anim,
                                          child: ScaleTransition(
                                            scale: anim,
                                            child: child,
                                          ),
                                        ),
                                    child:
                                        (player.isSpeedBoosting &&
                                            player.isPlaying &&
                                            !_isPip)
                                        ? Container(
                                            key: const ValueKey('speedBadge'),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 22,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: themeState.accent
                                                  .withValues(alpha: 0.9),
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.fast_forward,
                                                  color: Colors.white,
                                                  size: 34,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${_settings.longPressMultiplier}x',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : const SizedBox.shrink(
                                            key: ValueKey('noSpeedBadge'),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Screen-lock ENTER button (left edge, shown with
                          // the controls, MX-Player style).
                          Positioned(
                            left: 4,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              ignoring: !(_controlsVisible &&
                                  !_isPip &&
                                  !_locked &&
                                  _settings.lockButton &&
                                  player.currentTrack != null),
                              child: AnimatedOpacity(
                                opacity: (_controlsVisible &&
                                        !_isPip &&
                                        !_locked &&
                                        _settings.lockButton &&
                                        player.currentTrack != null)
                                    ? 1.0
                                    : 0.0,
                                duration: const Duration(milliseconds: 180),
                                child: Center(
                                  child: _lockChip(
                                    icon: Icons.lock_open_outlined,
                                    onTap: _lockScreen,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Screen-lock EXIT chip (right edge, always visible
                          // while locked).
                          if (_locked && !_isPip)
                            Positioned(
                              right: 4,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _lockChip(
                                  icon: Icons.lock,
                                  onTap: _showLockHint,
                                  onDoubleTap: _unlockScreen,
                                  onLongPress: _unlockScreen,
                                ),
                              ),
                            ),
                          // Top bar (v19): back + marquee title + the
                          // merged more-actions menu + settings. Auto-hides
                          // with the controls, always readable over video.
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: !_controlsVisible,
                              child: AnimatedSlide(
                                offset: _controlsVisible && !_isPip
                                    ? Offset.zero
                                    : const Offset(0, -0.5),
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: AnimatedOpacity(
                                  opacity: _controlsVisible && !_isPip
                                      ? 1.0
                                      : 0.0,
                                  duration: const Duration(milliseconds: 180),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.75),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                        2, 2, 2, 14),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          tooltip: 'Back',
                                          icon: const Icon(Icons.arrow_back,
                                              size: 22),
                                          onPressed: () {
                                            _onUserInteraction();
                                            Navigator.of(context).maybePop();
                                          },
                                        ),
                                        Expanded(
                                          child: AnimatedBuilder(
                                            animation: player,
                                            builder: (context, _) =>
                                                _MarqueeTitle(
                                              player.currentTrack?.title ??
                                                  'Max Player',
                                              key: ValueKey(
                                                player.currentTrack?.path,
                                              ),
                                            ),
                                          ),
                                        ),
                                        _topMenu(context),
                                        IconButton(
                                          tooltip: 'Player settings',
                                          icon: const Icon(
                                              Icons.settings_outlined,
                                              size: 22),
                                          onPressed: () {
                                            _onUserInteraction();
                                            _openSettings();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Controls slide up + fade in instead of snapping.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              ignoring: !_controlsVisible,
                              child: AnimatedSlide(
                                offset: _controlsVisible && !_isPip
                                    ? Offset.zero
                                    : const Offset(0, 0.45),
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: AnimatedOpacity(
                                  opacity: _controlsVisible && !_isPip
                                      ? 1.0
                                      : 0.0,
                                  duration: const Duration(milliseconds: 180),
                                  child: PlayerControlsOverlay(
                                    player: player,
                                    onToggleQueue: () {
                                      setState(() => _showQueue = !_showQueue);
                                      _onUserInteraction();
                                    },
                                    onInteract: _onUserInteraction,
                                    onCycleFit: _cycleFit,
                                    orientationLocked: _orientationLocked,
                                    onToggleOrientationLock:
                                        _toggleOrientationLock,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_showQueue && !_isFullscreen && !_isPip)
                SizedBox(
                  width: 280,
                  child: Container(
                    color: const Color(0xFF12121a),
                    child: AnimatedBuilder(
                      animation: player,
                      builder: (context, _) => PlaylistPanel(
                        playlist: player.playlist,
                        currentIndex: player.currentIndex,
                        onPlay: player.playTrack,
                        onRemove: player.removeFromPlaylist,
                        onClose: () => setState(() => _showQueue = false),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The merged more-actions menu (v19): video info, equalizer,
  /// screenshot, cast and picture-in-picture behind ONE button.
  Widget _topMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: const Icon(Icons.more_vert, size: 22),
      color: const Color(0xFF1a1a24),
      onSelected: (v) {
        _onUserInteraction();
        switch (v) {
          case 'info':
            VideoInfoSheet.show(context, widget.player);
          case 'eq':
            EqualizerSheet.show(context, widget.player);
          case 'shot':
            _takeScreenshot();
          case 'cast':
            _openCast();
          case 'pip':
            NativeBridge.enterPip(playing: widget.player.isPlaying);
        }
      },
      itemBuilder: (context) => [
        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer'),
        if (_settings.screenshotButton)
          _topMenuItem('shot', Icons.camera_alt_outlined, 'Screenshot'),
        if (_settings.castButton)
          _topMenuItem('cast', Icons.cast_outlined, 'Cast to TV'),
        _topMenuItem('pip', Icons.picture_in_picture_alt_outlined,
            'Picture in picture'),
      ],
    );
  }

  PopupMenuItem<String> _topMenuItem(
      String v, IconData icon, String label) {
    return PopupMenuItem(
      value: v,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _lockChip({
    required IconData icon,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

enum _ScaleMode { undecided, volume, brightness, seekH, pan, zoom, cant }

/// Player title bar (v19): long titles scroll sideways in a slow loop
/// (marquee) instead of getting ellipsized. The widget is keyed by the
/// track path, so it restarts cleanly on track change.
class _MarqueeTitle extends StatefulWidget {
  final String text;
  const _MarqueeTitle(this.text, {super.key});

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle> {
  final ScrollController _sc = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer =
        Timer.periodic(const Duration(milliseconds: 1400), (_) => _tick());
  }

  void _tick() {
    if (!mounted || !_sc.hasClients) return;
    final max = _sc.position.maxScrollExtent;
    if (max <= 0) return; // fits on screen - nothing to scroll
    if (_sc.offset >= max - 1) {
      _sc.jumpTo(0); // hold at the end, then wrap around
    } else {
      _sc.animateTo(
        max,
        // v20: ~2.5x faster scroll ("move the title in more speed").
        duration:
            Duration(milliseconds: (max * 9).clamp(500, 5000).toInt()),
        curve: Curves.linear,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _sc,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
EOF_MARKER_6

mkdir -p "$(dirname 'lib/widgets/player_controls_overlay.dart')"
cat > 'lib/widgets/player_controls_overlay.dart' <<'EOF_MARKER_7'
import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'progress_bar.dart';
import 'track_selection_sheet.dart';

/// Controls drawn on top of the video - v19 final-polish layout:
///
///   [progress bar, with scrub thumbnail preview]
///   row 1:  previous  -  play/pause  -  next            (centered trio)
///   row 2:  mute - speed - Tracks(subs/audio/A-B) - rotation lock
///           ...  queue - fit
///
/// Removed per the final polish pass: shuffle, repeat, the dedicated
/// +/-10 s buttons (horizontal drag-seek covers them) and the fullscreen
/// button (sensor auto-rotate replaces it); the fit cycle moved to the
/// corner where fullscreen used to sit.
///
/// This widget rebuilds itself via [AnimatedBuilder] on every player tick,
/// so the parent screen does NOT rebuild (which kept recreating the video
/// surface and caused fullscreen flicker).
class PlayerControlsOverlay extends StatelessWidget {
  final MediaPlayerState player;
  final VoidCallback onToggleQueue;

  /// Fired on every control interaction; the screen uses it to restart the
  /// auto-hide countdown.
  final VoidCallback onInteract;

  /// Cycles the video fit (contain -> cover -> fill).
  final VoidCallback onCycleFit;

  /// Rotation lock toggle (auto-rotate by sensor vs pinned).
  final bool orientationLocked;
  final VoidCallback onToggleOrientationLock;

  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.onToggleQueue,
    required this.onInteract,
    required this.onCycleFit,
    required this.orientationLocked,
    required this.onToggleOrientationLock,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressBar(
                position: player.position,
                duration: player.duration,
                previewThumb: player.scrubThumbPath,
                onSeek: (d) {
                  player.seek(d);
                  onInteract();
                },
              ),
              // Row 1: previous / play-pause / next - the transport trio.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _iconBtn(
                    icon: Icons.skip_previous,
                    size: 30,
                    onTap: player.prevTrack,
                  ),
                  const SizedBox(width: 22),
                  _iconBtn(
                    icon: player.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 46,
                    onTap: player.togglePlay,
                  ),
                  const SizedBox(width: 22),
                  _iconBtn(
                    icon: Icons.skip_next,
                    size: 30,
                    onTap: player.nextTrack,
                  ),
                ],
              ),
              // Row 2 (compact): mute speed tracks rotate | queue fit
              Row(
                children: [
                  _iconBtn(
                    icon: player.isMuted || player.volume == 0
                        ? Icons.volume_off
                        : Icons.volume_up,
                    onTap: player.toggleMute,
                    compact: true,
                  ),
                  _speedMenu(),
                  _tracksMenu(context),
                  _iconBtn(
                    icon: orientationLocked
                        ? Icons.screen_lock_rotation
                        : Icons.screen_rotation,
                    active: orientationLocked,
                    onTap: onToggleOrientationLock,
                    compact: true,
                  ),
                  const Spacer(),
                  _iconBtn(
                    icon: Icons.queue_music,
                    onTap: onToggleQueue,
                    compact: true,
                  ),
                  _iconBtn(
                    tooltip: 'Fit: contain / cover / fill',
                    icon: Icons.aspect_ratio,
                    onTap: onCycleFit,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// One button opening ONE bottom sheet for everything track-shaped:
  /// subtitles, audio tracks, and the A-B loop (previously three separate
  /// buttons). v20: switched from PopupMenuButton to a bottom sheet - the
  /// popup glitched because this overlay rebuilds on every player tick
  /// while the popup was open.
  Widget _tracksMenu(BuildContext context) {
    final active = player.subtitlesActive ||
        player.audioTracks.length > 1 ||
        player.abLoopActive;
    return IconButton(
      tooltip: 'Subtitles, audio tracks, A-B loop',
      icon: Icon(
        Icons.tune,
        size: 20,
        color: active ? themeState.accent : Colors.white,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 40),
      onPressed: () {
        onInteract();
        _showTracksSheet(context);
      },
    );
  }

  void _showTracksSheet(BuildContext context) {
    final hasA = player.loopA != null;
    final hasB = player.loopB != null;
    final abSubtitle = hasA && hasB
        ? 'Looping ${formatDuration(player.loopA)} - ${formatDuration(player.loopB)} (tap to clear)'
        : hasA
            ? 'A set at ${formatDuration(player.loopA)} - tap to set B'
            : 'Off - tap to mark point A';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                player.subtitlesActive
                    ? Icons.subtitles
                    : Icons.subtitles_outlined,
                color: Colors.white70,
              ),
              title: Text(
                player.subtitlesActive ? 'Subtitles (on)' : 'Subtitles',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                TrackSelectionSheet.show(context, player, isSubtitle: true);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.audiotrack_outlined,
                color: Colors.white70,
              ),
              title: Text(
                player.audioTracks.length > 1
                    ? 'Audio track (${player.audioTracks.length} available)'
                    : 'Audio track',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                TrackSelectionSheet.show(context, player, isSubtitle: false);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.repeat_one_outlined,
                color: player.abLoopActive
                    ? themeState.accent
                    : Colors.white70,
              ),
              title: const Text(
                'A-B loop',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                abSubtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                final msg = player.tapLoopPoint();
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      duration: const Duration(milliseconds: 1400),
                    ),
                  );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _speedMenu() {
    return PopupMenuButton<double>(
      initialValue: player.playbackRate,
      color: const Color(0xFF1a1a24),
      onSelected: (r) {
        player.setPlaybackRate(r);
        onInteract();
      },
      itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
          .map((r) => PopupMenuItem(
                value: r,
                child: Text('${r}x',
                    style: const TextStyle(color: Colors.white)),
              ))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Text('${player.playbackRate}x',
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    double size = 24,
    bool compact = false,
    String? tooltip,
  }) {
    final accent = themeState.accent;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon,
          size: compact ? 20 : size, color: active ? accent : Colors.white),
      // Compact rows must fit ~7 actions on a 320dp-wide phone.
      constraints:
          compact ? const BoxConstraints.tightFor(width: 34, height: 40) : null,
      padding: compact ? EdgeInsets.zero : null,
      visualDensity: compact ? VisualDensity.compact : null,
      // Every press also restarts the screen's auto-hide countdown.
      onPressed: () {
        onTap();
        onInteract();
      },
    );
  }
}
EOF_MARKER_7

mkdir -p "$(dirname 'lib/widgets/video_info_sheet.dart')"
cat > 'lib/widgets/video_info_sheet.dart' <<'EOF_MARKER_8'
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// Bottom sheet with technical details about the video currently loaded in
/// the player (resolution, codec, bitrate, size, duration, path...).
/// Values are refreshed live from the native MediaMetadataRetriever.
class VideoInfoSheet extends StatelessWidget {
  final MediaPlayerState player;

  /// Provided by the wrapping DraggableScrollableSheet so the info list can
  /// be dragged/scrolled up to see every row (v20).
  final ScrollController? scrollController;

  const VideoInfoSheet({
    super.key,
    required this.player,
    this.scrollController,
  });

  static Future<void> show(BuildContext context, MediaPlayerState player) {
    // v20: isScrollControlled + DraggableScrollableSheet - the old
    // fixed-height sheet cropped the bottom rows on small screens and
    // could not be dragged up ("video info is not sliding"). Now it drags
    // between 30% and 90% of the screen and the rows scroll.
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => VideoInfoSheet(
          player: player,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = player.currentTrack;
    final accent = themeState.accent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        // v20: scrollable content - pairs with the DraggableScrollableSheet
        // in show() so every row can be pulled up into view.
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Video info',
              style: TextStyle(
                color: accent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (track == null)
              const Text('Nothing is loaded right now',
                  style: TextStyle(color: Colors.white38))
            else
              FutureBuilder<VideoMetadata>(
                future: track.path.contains('://')
                    ? null
                    : NativeBridge.fetchMetadata(track.path),
                builder: (context, snap) {
                  final meta = snap.data;
                  final w = meta?.width ?? track.width;
                  final h = meta?.height ?? track.height;
                  final sizeBytes =
                      track.sizeBytes ?? _fileSizeOrNull(track.path);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Row('Name', track.title),
                      _Row('Location', track.path, small: true),
                      _Row(
                        'Resolution',
                        (w != null && h != null && w > 0)
                            ? '$w × $h  ·  ${track.qualityLabel ?? ''}'
                            : 'Unknown',
                      ),
                      _Row(
                          'Duration',
                          formatDuration(
                              meta?.duration ?? track.duration ??
                                  player.duration)),
                      _Row('File size', sizeBytes == null
                          ? 'Unknown'
                          : formatFileSize(sizeBytes)),
                      if (meta?.codec != null)
                        _Row('Video codec', meta!.codec!.toUpperCase()),
                      if (meta?.bitrateBps != null && meta!.bitrateBps! > 0)
                        _Row('Bitrate',
                            '${(meta.bitrateBps! / 1000000).toStringAsFixed(1)} Mbps'),
                      _Row('Queue position',
                          '${player.currentIndex + 1} of ${player.playlist.length}'),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  int? _fileSizeOrNull(String path) {
    try {
      if (path.contains('://')) return null;
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool small;

  const _Row(this.label, this.value, {this.small = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 106,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: small ? 11.5 : 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
EOF_MARKER_8

mkdir -p "$(dirname 'lib/utils/privacy_policy.dart')"
cat > 'lib/utils/privacy_policy.dart' <<'EOF_MARKER_9'
import 'package:flutter/material.dart';

/// The app's privacy policy, bundled so it can be read offline (also what
/// Play reviewers see when they open the app during review).
///
/// Play Console still needs the public-URL copy: PRIVACY_POLICY.md at the
/// repo root. Keep the two in sync when either changes - the widget test
/// checks that both carry the same anchors (effective date, developer).
const String kPrivacyPolicyText =
    'MAX PLAYER - PRIVACY POLICY\n'
    'Effective date: 13 August 2026\n'
    'Developer: Hyper Tech Labs (Aryan Shah)\n'
    '\n'
    'THE SHORT VERSION\n'
    'Max Player is a local video player. It does not collect, store, '
    'transmit, or share any personal data. Everything the app does happens '
    'on your device.\n'
    '\n'
    'WHAT THE APP ACCESSES, AND WHY\n'
    '\n'
    '- Storage (videos / all files): to find and play the videos stored on '
    'your device, save screenshots to "Pictures/Max Player", and write AI '
    'subtitle files next to your videos. None of it ever leaves your '
    'device.\n'
    '\n'
    '- Internet: only for two things you trigger yourself - (1) the '
    'one-time download of the AI subtitle model (~142 MB from '
    'huggingface.co) and (2) playing stream URLs you paste or open. '
    'Nothing about you is sent anywhere.\n'
    '\n'
    '- Local network (Wi-Fi / multicast): only when you tap "Cast to TV" - '
    'discovering DLNA televisions on your own Wi-Fi and serving the video '
    'file from your phone to the television. Your Wi-Fi only; no external '
    'server is involved.\n'
    '\n'
    'WHAT THE APP DOES NOT DO\n'
    '\n'
    '- No analytics, no tracking, no advertising, and no third-party SDKs '
    'that collect data.\n'
    '- No accounts, no sign-in, no device identifiers collected.\n'
    '- No collection of your video library contents, file names, or watch '
    'history - all of it stays in the app\'s local storage on your '
    'device.\n'
    '- No crash reporting service. Crash reports are shown to you inside '
    'the app and are only shared if you copy and send them yourself.\n'
    '\n'
    'AI SUBTITLES\n'
    '\n'
    'Subtitle generation runs entirely on your device using the '
    'open-source whisper.cpp engine. Your audio never leaves your phone. '
    'The only network access is the one-time model file download from '
    'Hugging Face, which you trigger and can delete afterwards.\n'
    '\n'
    'CHILDREN\n'
    '\n'
    'The app collects no data from anyone, including children.\n'
    '\n'
    'GOOGLE PLAY DATA SAFETY (SHORT ANSWERS)\n'
    '\n'
    '- Data collected: none.\n'
    '- Data shared with third parties: none.\n'
    '- Data sent off this device: none - AI subtitles, watch history, '
    'bookmarks and settings are all local-only.\n'
    '- Because no data leaves the device, "encryption in transit" and '
    '"account/data deletion requests" do not apply: nothing is transmitted '
    'and there is nothing on any server to delete.\n'
    '\n'
    'CHANGES\n'
    '\n'
    'Any change to this policy is published in PRIVACY_POLICY.md in the '
    'public repository with a new effective date.\n'
    '\n'
    'CONTACT\n'
    '\n'
    'Questions: open an issue on github.com/Aryanshahx/maxplayer';

/// Dialog showing [kPrivacyPolicyText]. Opened from the About sheet's
/// "Privacy policy" button.
void showPrivacyPolicyDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1b1b24),
      title: const Text(
        'Privacy policy',
        style: TextStyle(color: Colors.white, fontSize: 17),
      ),
      scrollable: true,
      content: const Text(
        kPrivacyPolicyText,
        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
EOF_MARKER_9

mkdir -p "$(dirname 'PRIVACY_POLICY.md')"
cat > 'PRIVACY_POLICY.md' <<'EOF_MARKER_10'
# Privacy Policy — Max Player

**Effective date:** 13 August 2026
**Developer:** Hyper Tech Labs (Aryan Shah)
**Contact:** https://github.com/Aryanshahx/maxplayer (see the repository profile for contact details)

## The short version
Max Player is a local video player. **It does not collect, store, transmit, or share any personal data.** Everything the app does happens on your device.

## What the app accesses and why

| Permission / access | Why | Where the data goes |
|---|---|---|
| **Storage (videos / all files)** | To find and play the videos stored on your device, save screenshots to *Pictures/Max Player*, and write AI subtitle files next to your videos | Never leaves your device |
| **Internet** | Only for two things you trigger yourself: (1) the one-time download of the AI subtitle model (a ~142 MB file from huggingface.co), (2) playing stream URLs you paste/open | The model file comes in; nothing about you goes out |
| **Local network (multicast/Wi-Fi)** | Only when you tap "Cast to TV": discovering DLNA TVs on your own Wi-Fi and serving the video file from your phone to your TV | Your Wi-Fi only; no external server is involved |

## What the app does NOT do
- No analytics, no tracking, no advertising, no third-party SDKs that collect data
- No accounts, no sign-in, no device identifiers collected
- No collection of your video library content, file names, or history — all of it stays in the app's local storage on your device
- No crash reporting service (crash reports are shown **to you** inside the app, and are only shared if **you** copy and send them)

## AI subtitles
Subtitle generation runs entirely **on your device** using the open-source whisper.cpp engine. Your audio never leaves your phone. The only network access is the one-time model file download from Hugging Face (ggerganov/whisper.cpp), which you trigger and can delete afterwards.

## Children's privacy
The app collects no data from anyone, including children.

## Google Play Data Safety (short answers)
This section matches the app's Play Console Data Safety form:
- **Data collected:** none — there is nothing to list per category
- **Data shared with third parties:** none
- **Data sent off the device:** none (AI subtitle generation, history, bookmarks and settings are all local-only)
- Because no data leaves the device, "encryption in transit" and "account/data deletion requests" are **not applicable** — nothing is transmitted and there is nothing on any server to delete.

## Changes
Any change to this policy will be committed to this file in the public repository, with the new effective date above.

## Contact
Questions: open an issue on the GitHub repository above.
EOF_MARKER_10

mkdir -p "$(dirname 'pubspec.yaml')"
cat > 'pubspec.yaml' <<'EOF_MARKER_11'
name: maxplayer
description: "Max Player - a local video library & player."
publish_to: 'none'
version: 1.0.0+18

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # Playback engine (libmpv/ffmpeg backed) - handles mp4/webm/mkv/avi/wmv/flv/ts/vob/etc
  # which ExoPlayer (video_player plugin) does not reliably support.
  media_kit: ^1.1.11
  media_kit_video: ^1.2.5
  media_kit_libs_android_video: ^1.3.6

  # Folder scanning via a manually-entered path + broad storage permission,
  # instead of file_picker's native SAF dialog (file_picker's Android side has
  # proven incompatible with current AGP/Kotlin toolchains as of this writing).
  permission_handler: ^11.3.1

  path: ^1.9.0
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
EOF_MARKER_11

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-mdpi/ic_launcher.png')"
base64 -d > 'android/app/src/main/res/mipmap-mdpi/ic_launcher.png' <<'B64_MARKER_0'
iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAIAAADYYG7QAAAJrUlEQVR42u1Za6xcVRX+1j7POTNz
Z265LQhFBFqJhaa8AggIGKhgDQ+LRgGD/tGQQjCCRqIRjbYkSIIUDCAkJlilEAKo4aGVANWgSEEI
QhF8pA+gyIXe3nmdmTnn7M8f5z137iXxFybOj5s7556999prfetb61tXSOL99FF4n33edwaZ2W++
JgkrtlEg77mUSF7672JOkKCmDiECy1OjBoEQUgCIgBm0JD5ZknNZeAhACtZwXnPzy0n+GjOzSm/k
BlmA5CdLthVFkKwpHikoO0ggROESkr+Y/IkQKZgVfzFolIORY0hJukAY2yNCCoWESL6f5GYUMpRM
7BeBcFyAJN09XpzbLhA1zkPFqycnxbGS5EYgc48IYrdldhQsm2NMcqV8i9JhquQiNQdoJChSfpJE
RRLQSAadzEQWjZIRXCUpwuyblOA4T5bl4WW8KD473iZxmIYQICkpTtQ4SBNzTcsSlylIc8wVX5sT
MhFJXJLgMnsQQkIyjHS8jTKUKTAIQ0SNSUAgR1zmTxbyjiWb5sdQkhdJ6GOXQAJgSA4NEcsMgRAI
h5Ed0VbKAS3AADJoJphLnDGa9CILMVeJhwqmZ7kPECHga+0r2dsNf3PTn3dv37P8vBXHX3RkDbC6
QV2JZ4hNMQWGMM15pvGPdyIT7BcyE0noS97IUldrUqfEiDiDIEBE9ohZrbu2edsX7599bceq1cue
uX97MDlx2vfXHH/moU3C6wSeEleJLTBFRJIEGOFUyXfO7isxIpUlYwxKebPoWwnJluY+y/jbm+3b
T9v49d9d1jlsam+rv2vj48/c+XT9hGWf/N6aVUdNVXvaGYRVUzlKlMBQUEoSzDODQYHuU2YiKSLK
lPFpH18PyasAqYGQGApm/KHlqN1i3hvozY7T+s6atX+6+kNLzE3n3Hjb5Q/seMtnzfaH6PlRGDAK
qEMiBHSJUHJUCThSRsYYFN9BsugmjzQwIPqAaLaAf1rqBXBLJ9yypPHBWy++7OF15htvrT9jw10b
tnR6tC172NFBR+s+OdQIiChj05zlpZh38xNjcoek9hR4IyKGRKR1JOgDPaJjGNM9vW063Lls6Wce
WPfVn3zhpd9uu/IT6x/62TNWaDuhFcwEUUvDpwwoIUUnuZfEjuPbBIU5hMYSwZOEJgHEGLOBKjAV
ohnADmAMZe+e4cuv9RvHrtjwq29devnqTbf++iufv/65x1+tBRWrLcG7ge5E6BNDIoyvmbpLZMG0
z6mMhbBKRgMKJOgAiyIEASaHnBzA69PpUw349tsdhDj9tFPPOvG4e+9+7Jrv/vT4FYd+7ZJzl35k
qR4MIi9UdUNcBREYScAK8crpSo1CqFBtshswKUXUhENZFGHxgIv7XOzrpq/rPV3p0GlBpqM9z+7t
vjS84qxP3fODb5j0Lrpm4y0/ui/Y2be6NvelftIFH82pZXNClhVJkVJzAQigSZeYjLBkwKk+m340
6UeNHic6utaK3Bltv4tw9/D1rf+e3G5ef9Ylt3xu3dPP777gqh8+8cttZsdkJ4oxLhzJrgXaDwKS
lDJJvRo7VIEadIjJANLXjT4bvp7osdFjvcVqm5VZurOR0w7dDgfdbri9e7R9wC8+dtUD7zx97W33
3VR3jzt3ZTgMVcyeCT1yodIhWThjCkrJXvKuihbYCKEGrPU50WO9o6tterNRpa29Dt0OKzN02qHp
Uw2UH3W4K1q7+qS/dnY9+tSzx52zikGh0BIiQlDG85AkfU0an9HwxktdojFkw+dEl/UOay1WZ6PK
bOTO6korqrYjt62tnhhDxSHswPIOqu3o7X3ileeOOvBAhEw3FWFu1oL9ELP6J4UOME97R6Ppa3a0
12Ktq2tt7bXpteF1WGlrp63NIRAIIuXuv99g0ti4+5G7Nz2y9sgV5516ShT1DcNMKqzKIbFAP5SV
PUnZKJYgIBG3RXYo9QGCWe21tNeG22GlzUqb1S7crqihIuHuX8PB9YenX7jhic1TwjvPu/iYk1fp
KYqnYEkMhLi5QaETmA9DaX1mqUdWSUMiVgCvw/67utKG10Wlh0oHXhe2TwnhNipY3nxl8Ob6x+7Y
tfMfV56w+rOnfxwHOsF+obHERl3BEhjlZJ83ZKkAGpFkpV5SxOizMsPqDJw2XJ+uD6cvZgDTNdyV
k7MN/8Yn73lo69a1y1fese7b1UMXRxMDLqIx5aIhqAhsgZGLJClLprkNGqUgc7KQxUEXAkLTh5pl
ZRZOF85AOcPQJpvL6zjc2fziUzffcd/hbuPuL11+xMojWB8EjUA1bZlQrClxBI7AHEkWsqybzDEq
aE7znZIlKTD7kJZ2u3B8cUPut6hSOcZ9ft/ODTdvmn59+uo153/61JOlCb/WN5uWTCh4Iq7AFlhJ
0WBBSnChkJV1VdxRxY6J648SIWgO6AQShlK3jQNWeXsn/PUPbnr0yT+efdJHb/jyFUsOqHW8vt00
zJojFZGKwBJYgCmQslYaI0zmw1CqByTtpAyIIRAdiYGqa1VdtWhFzZqSzdv+8ON771+89APXXfvN
VcsPgeX364NKw1KeElfEEpgQU6CQWFMSEgkxzp9lZWMlRXcsvgzN5mTV7w32tGaOOuPgv/x+x/XX
/fxf/r4Lr7zo7JNPnJAgMn2vZjhVZbiiLIgtEnf8I45h3itKkekwt6eORlrK5EtIdIl3gmjas+7a
8OCrt2897MMHvfj314+88JQLLj3/kJpTC/26oyq2sm2YjihTVKyJVGFKEvfERV3GNHM1BaLseQxi
WVYKJAL7Gi3N6Yhvm+ZTW1584+U3jj7j2BXL9q91h02DDcdwDVgGDEOUAWVIIRGSHCmJ78LQRESg
KRAZa1BhVFOC/pDwNTsa+0Ldc6xQYPXoDodNy/AMcWK2UxARpUZEYap1snumeMk1OyEQSWWQOQ/m
M5ErAC0RCkTRtFR/GGhN01COZ7hKbMAUKCWSDiPGzRE4yicjjb7MA+qCT1kcmSnAFgjEFHqWiqWe
CZgihkClc65cq0semkKk4pdYltdZAyYLzofKjo93s4QmhSkahNmMKxmUzNU0WVySzMo1WQFLhOA9
mDrnoSKmFOJxWoG/S2TKMYyfqp4ELcKsvKMwKCy6TM2tuiMzQyZLWKx0BTEgmdQq/izmdmpvSo3M
5yOiIZrjlStJ6mwYldQOQXEaMjp9YjrcyPbIkBvPuxJZLlLqSqUM9wiIxoVMRyCpIFBlhxYygjm3
EVIeHSSGZ0uI4hiyPLBKZisEInAIKI4xSFItJqWWWuaKtnkLY2l0V1iRVvUM/MUEg1kYdRWJ8f//
6/gfMeg/JYtirGyhzGUAAAAASUVORK5CYII=
B64_MARKER_0

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png')"
base64 -d > 'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png' <<'B64_MARKER_1'
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
PxF0uElaeamMAAAAAElFTkSuQmCC
B64_MARKER_1

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-hdpi/ic_launcher.png')"
base64 -d > 'android/app/src/main/res/mipmap-hdpi/ic_launcher.png' <<'B64_MARKER_2'
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
B64_MARKER_2

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png')"
base64 -d > 'android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png' <<'B64_MARKER_3'
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
B64_MARKER_3

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png')"
base64 -d > 'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png' <<'B64_MARKER_4'
iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAIAAABt+uBvAAAgKElEQVR42u18a7RlVZXe96219t7n
3AcFCIUlKMjDAineNIg8RMTGt6jDtm07YmLTMTEZxv7diSTpJCM9RiedkdFJj1ZsRVsl8cGwbRWQ
h1ggykNQoATkqVBCUUCVde85+7W+/Fj7sfa5t6h7HfnRP+oMuFW37rn77D3XfHxzzm9OSsL+195f
Zr8I9gtov4D2C2i/gP7xvtzKf6qEUrIAm/9IABQEEGi+/H98tdeTwPCtAEIA2ghLIkRbRr/SvYHd
FQZ/DD+ieTeBPm4LUvNVtWxqjFuDgEppT62UMIIjDWSg+N7Y3wZjwTU3xuZu2m+bH3XPGN12LIX4
Z92/cPht97S+k4oAwBNU/yvtB7cyJdChGQUBSQB9DdWSII861+gAGsd9C8gCGZGAhjAAoaBCkVzU
P7ugcE9q39MIrjtOgWzutj0+gmL7POxlQUHh/dGxx9IhKIX7afQt/K4Gx9X+MsmhjoZLdk9jABnK
Sx4QV/U3q/wbCQca9NJhf1wSpIFGs31cIn5P0N348DlQ+SAWAlQvBwHtQ4kDAxl8p+Z/tAfTvEP9
rTHSRvWq21gk2Z65AYyhsaTpLXUfGkTBCJbhoEAxOiqQFCKFQOs3wp30DxNpu9jpWPPW8D6yf0DN
HHNkchJINpJsPrBVwO56kckiiGrWpjlQyfAggmnOydg1O2kCho3itGdAQQTZnFBrBsFkRDHIpr31
oZmwER0bl9g7Jai3is4Jz/g2dfbay3tg5M1lemnG6hifYKSp4eEGDpurR59VBUQ2Gq6ZB5Zab83e
DTfyC6omBFnGjyyuHlbUypTs7FatEmvm2GOJKI53/WFEV+x/dWhrkQE2h2UAH9R5zSYGwpCRQ43i
KFsxIGhG55Y5vInoyIOrVHx/kTIgsleiUcXBBXshtqYTXXJgORoE2oGVrvzsKPBQQPvIa9Og+MKt
ONpDDBbVWUmnLn386mMqe4fTx5lglf0T99Cgd7jqYlQbdhTd3Kw+dsInETQY6hEEhz5xGBqjy0YP
um8kLak3kDjIxm9pQEXzRrVmHDnjVhvU3j6H99Y7Fqn3AiLI3mqiB4miohQZUqS1jMFGH8PEyIMP
tEpY+WxrTjVESdEBtdG0eZ7ODzfhopFqZ81s/R4j9Y1gSusGhv6Vq8HsoEjdZaJQqShgND9uL6vV
nluRrjQnwf731yggxmrZQyBIHMTqzpO3QTc6YkapgOIcIEZGHOp4Z329fXaSHXhQYcbhgivzi9U9
EJooEsP0BspyjWG+A5tqHzx4T3ZQtoE26iTBEKg4YzgdBlRngY1D7tBMa1O9lflGUaWhIXCVaNtG
2KEoAlSLMEGX/TSnre70+lACrRkHdZoYBd4mYoVn622rcdPt5TWAIr6VtHp00NhjcEfss86AxJuw
KPUP0eBRRgioxXgDj6NI1uqRmobpGdTZVwxdCWgd2XwsfEYuphM0pSFcjm0KEjwpwAO+1YtYfkG8
BiRk1OpVyGzUJ9wdmGuQgjqPxe4+ejwWq3z/0MIMem6xUhMyqFgd1yGg5tgacTMCuFAEOvp8M9gi
5QURdSuauvNMisKOZAhDGCFkfEY0bJw2g+7Gp9obWVCcCHJzpo4wSJGjQ9UAnPUwP2DOQbq2RhML
foXd3zvAzpUIolUBCQIryVMeqKFKrIHaywseCAkhQStYwAbpQBawoiGpYGsDWB1jn0ad2cAqdVo+
9EQrcosZF6Y+exxWZdYooNYP9HrbS4qt9XY4ug0+8qAHaqKGarAUS6/K0GTWAzVQ1h6lJ2mBFDSA
BRyYQJ6w6nVKgOEqDxjj9Mh/sYXWBFbx6SSHLjmyOEbWsY4oFgEwRmXEGOB3hxBUzYs1UEGVUIEF
UHgxs8uVHvvxM/mOnBvSxZMOPnBDitLb0qcWBkiAFKiBBLCQAwxoW20wnKn4tJnJ0LM0biUoVgQd
1GpWHKI0tIAWp2ldJtbifkZRucNnagJnC08pwEserKFSKIASmHoVmX3yJ8/e8O9/9OAdDxfLpXV8
+ebDNn/41BM/tOWAeWcmlfMYWVZADdRACgqyUHDYao3cMM6zsJoWMJJGf5CtbxwoVeTjhwWQvQho
FdFJUt1a08BAe2tri8YMDtgDlVBAU6AAJ977xD760Iufu/RLTz3xhDuo3nT4ATt37H7+6fLA7MCj
Xnf8ln991lHvOHbRIFuqxsSIHAEZkba+ybF1UiRbTM6ZUk6TDrLHO/HjRM8/qN024Fed129EVsM4
Q7vWKDYAFG3OOlN5YQeGgw+uwBIopFyYGt76l3c++8unD9uS/elf/dH8CZv2PPubH/7t1ms+d+s9
N9/+y7sfOvLiE0/55HlHvW5TWaNYLivDmgy25gJWAES4AJHUuhFG9kAM6vDkrI+JfcEAA0vD1Ix7
x6Ora5Cvmzq0OjgWl37ZB7kgnUosqKkwkZakaWK375h85uK/eeaJJ//T1f/8FW/d/PNJVabu5RbY
9uz1f/Hd6792V74Lhx2+8Zj3nnbGvzr38OM2pBO/UNQjwwxIgZRIwEaV2uqdIUxwuCZSJa2M+rO1
6kHk6fsgw0p2DeNIy7WF+b4mFikmojLHEHl5wku1ggahMHxu5/LuF3cvLozmjjzoQa9nPXZO65/I
L2ze+LrPfPj8f3rB3//5P2z93v3P/e/nfnXtg8df9jtnfPRMbRxVu6qq8rIGhIdSAIYIoAnwDTYD
a9IM6zKKy7NxvOtkJM1qlQYAcT1RrAlh7EQhxQ2BGHwFeQnyCFaGSqiAiXxV1yns1GOH4WPks4ZT
2nRa/1I66tyj3v2Nj7/5m/d9/S+vvePW+399xROPXnPPKZefe9r7Tj5kIcXusoYyYwDICAY2NB1C
mkMZAoIxBPsyfVQUUBTaI+2KgHVUnQL3Ykn7AIpdvbID/Yhzjrgs05wY6xY9FwBJr8oYK2ufA54B
niL3EKnFori0VD8LnHjplssvOeHNX/zh1f/j2vt+fM/2Bx7f9n9+fP7HLjz1TZuNoOWchrQGaNBR
yGQNISuQPqQgjKH+jBudSWuxAk+q8zNaZy6mPnmMy7rs8j3NHFyoGtRSJdVCIUGecBWwB9hF7iB2
EYbYUKO0lNfkN9UvrTnz8vOueNdpW//6xq9/9vv3fO+uJ+965O6LTnzzxy46+axX+kk9WS5HztAG
QchQNJQPbSmJaLyGiSpHfVkDLQ5qkpSophlpDdeNpDHAqX01uE2UuhCGKGsEBNSCB0qgDOUP7wXk
wB5iD/AiQKAmKXigNhzVuPvF8unFudd96p3n//451/y3a7919W0/+Ootj97+0FnvOuNNf3jBscce
4idFkVd0loYhwfUGtIABjegB03aGTHtrjCJLV7zqawBxqhCVZlZ72SuuuGJVBeoSv/YiZJ8Ptu0v
EkDIMCogh3Jo2WPq7M4dSw9cdVtGc85lr3v40LlfV9pJLhO1YMRESETnQQ8HovQv7qlx6OKF7zn5
gvNOWHp+cv9PH3ng9ge2bX2wnOKIV2/asDBXTUqVngI9KKAWfVed6rJl9vfVlAlbQMs4hnM1agBo
SMO1CKivsLRtwh4fDlM2KAhIKEL8EidSntgdO/Zs+/ztI/Ccy8559NC5ZyrtBgvBiqkw8hh5JDUy
j7SmreGEalK9sKd+2TGHvO39v7PltYc/+9TuB+97/N5b73vg9l+kbvzqozdlLimXSlPLeLAGvVi3
VQeR8fOrRYntH6s+wGyVcDUB7SUX6xpPcdF8FUeIvh6mIKzmVH0LvKyBAxyQAWMPCnMeIy9X09RA
rbpGUWPikQojYvv26R7D177t9P9+0UnX/91tX/ir6+6+c9sjDz1587dP+MCHLj7rjNewqspJkSQW
jnJAJSSkoxwZclwrGDatSjOwAnHY+o5g9/rCvGJDazsQM/IJdryy8NtUXVpMZoAUGAmZsCBYj6zG
XI1RjayGq2AqsZJq1V6FUIKl9OSu5QMS8/Z/8oaL3nb61Z+56WtX3XLj9Xf89N6fX3TBmX/4gYuP
P+YV+SSvULnU0hEplIqOSgyTUApQU0wBYcQB0QE9Uuq605I8Ydfsg0KOwz6jIWc4ElGeL4Q8vskz
ph5FYp/fsbTtC7eOjDnvI+c8fcjcC6WWRApZrbkKczXGFUYl5kqMS2SlktKnFVwhU8hOlRRwUy3v
yEfKLnrTa9/wu6fkhR68f/s99/5864/v3fPC5LhNmw4cL/hJpcIbkQGG9UCETc7fWp7iBgk4LEs0
yTftWn1QlIxGvqYjRXQwP2TSTQ1IKIAcnHrlid25Y+n+q7aOmFzwkdc/c8jc84XPRdZIK8zXmCsx
X2Gu0rhSViurkJXKKiQlkhIu9y6XnXibQ3vq5e35xtHiO95y+slnH/v8zvLBbU/dfs/9t959f1LY
4zduStPMTytUYiMm9eQWxnyO2Tyh/6cuz7Nr9UERx6RrQAwIATGeb3sfkcWFv0gCTGdic16saWuM
SsyXmqs0qjGqNKqUVcpKJRVcJVvCFEIh1fI1akHArt3L+ROTc17+6rP+60e/dcO9V1110/0PPfyp
T3/p27fecfk7LznnzBMgXxUlxhbjUOkGtYIv0ie6HLamtN6CGdU0X/qucMvciB3NQG4xRcMAvvXc
RkiAsZB52Mrbilml+VrjGlnlR6XmamWlRiWyUlmptJTLvS3EMlRtUVWyHjX13Au75q1793GnvvHf
Hf+lm3509bduue3eR+5/7DMXnXbSR9918bGbX4lJWUmm6QmE2BWgU5/1B5gS1+h71ol+i1SDsTCi
zD60wthTN7QKlas5rBGQCmMPX8OUGlcaVcgqjUuNKqWVslJZEFCBNFdaIslhc5kSKIBKvvZ1DetR
oPJP71oYpR87+41vOeWkz35763e2/vBrt9z+420Pvf8N533w7edt2HRA5UtjDIwHCWtgCN/UjdQz
mtT1ifvww3Ukq3ENquv89JQ2dR8BcQWTsHWMXpAFRkAmLHiUNWwdhIKs9FmlrMKoxKiXjk9znxZw
OZIcZupNIVZAVaOQStY1jDjl1DxVHLW4+B/e8J63HnfSlbfcdNfDD/yvb373+jt/8icfvPTci7bU
SyWNRULUkAFtoyMdXOzaWl0Pbm8oaW9hvq3M92Q5dk0AdoqkmK7UNPKDRrc/JIVUmPNYrmQquUpp
8M2VskJZhXGlrERWMMt9ViApmOQ+mcrlclOf5HKlbOFNLlvSlFDdmH2+c2Ieqc952XFnXXrMNx/7
yZU3fPvhXz31p5/+8v9c/MiWs46tispUhAck1SFZIwSaLo3SoCW+l9az2XvXZ8AsafoYipgYGnQL
4lKJ7zEUAFghFbI6GFdjYqNKo1KjQmmhdKp06pNcyVTJ1LtcrlCS+6SgK5BMlC4rmchOvFnyZqnG
7gov1NzluUflE1PeVb9ndMbnL//khae+/tc7X7jym9dh4pkLlVD70OHFwEuKfbbUkjK0DnZH14bv
q6td1hNRgaBhESpkQHGB38sTSoBEGtUY1xjVGtXIKqUlgt9JCqTB9Ux9MvVu4pMcSY6koCvUSk1u
Irtc22llJzWXPJY8Jl4Tz1x+Wfmvpi8rFi675IL57IBtT27f9eyLtjbKFXqYDR0jcqUxBfWlsxC3
eqaBgVDVtjsV024CMGrg2KB52UQRycOHMJ96jD3KSrZCVikplOXKSqWFskJJjiAIm/ukQJIrK5EU
sIVcjiSnncLmMhVMDZZkFfCOAMmABiY19S6/4dC5LBst5S9MimKDJ7xQx+wv07f8B1xbxVydNWhQ
W+gQA99FMd2s5xpw4K84JEOGli5JAyQhO600rjAukRUaFcpKJbnSXEmjO3JT73LZqdzU22lt8zop
lBTe5d7l3payFU1F1qBIER6oSRgZ2sTY483tTz76/O7nDlycP3i0qNpzQM8bUI36/k3sf9YV5rvW
SsPdHmZjan+sDhZ2tUsIgA+0IUMKice4Vl7KljKFT3KkBbICack0V5ojLZDkPsmRFHC5TwrZQq5Q
UsjmcoVsCZQ0IurgPQyNhRIhIY07PJkcW33lllu/svXmXfWOt5x4bjpeqJAbY3uqE3pW7sr+hSSu
qzfPJpXp+A8zHAkOyWDqvHdQnzoq9xsw88gqZZWqUiyQ5EoKpSGuF0pzJYWSAkmBZKqkDGJCUsDm
3uUyFehJkXVQegNjoQRIk8PmcDi+99y2L331h3f84u4d5ePvPfnsP7rorR5T4yyG8yYdMS7uGO0z
od97ybVt7sTpXK+tEbZiS9EJ7/Pq2x1B9dIaaYlxgTwXp0pypLlPCqUlg7BcriSHy31aICngCiQF
3dTbEqaGERtSuwGtBa1o3eIcjsgecNuvuuu26++5bfvyo686+KBPnPr7H3nDxXYxUQKmVMuOaPsM
LcId0N+izGA9JsY4vvcs+3AdDsdM2NEB1YAftezBUDuukZYY5cJUyJVOleRKcrkSLogjh5sqDUG9
UFIizWFKsqaRIWksYQlnYKwZpebo+RcOmnzhthu+evtNj73wyNzIX3by6z9+2iVHHHOkP7DSHDi2
SgjXDJt03idEmyAjSXun6e2zNx+1CFtMEzV4hbjXip5X0Ji2QUt3IinYqrGaNBemPpmG0E6Xo5VI
0CO4UraCK2EqGU/CEKQ1zAyckTXuyHm/iX//i59edc2NP3n8pzmfP/dVx/7J6e8668STkJbl/NQe
nGHRaUyMDdIg05h3yZ76Ho0FvUSl0e2NBUwgaon1KqMVY1jqa4rNbbT1NRKkYEuE4O0n4rJcjqRg
UiiIxhVwwe8USiq5QqaAEY0FaWkIRyXGbRzj6Oyu55/47NU3/+Cnd+zIn3zNIRs/ftqH33/iOTx4
VGaF2eDcotMBFotW82RKJKblIK2AyX3lTDMzZ2vmKM6y06P+YUOI6zkk7Ft4ca0/cOToCtipTyby
S8ASkkIuuOEaScUgIFcwrbwr5SpaA2NpjGFilcod7HDcwtP+xS9ee/M1N9/8xO5fHLTAf3PKWy4/
5XcP3nRIPc61UNnFFPNW8xaLBnOGYyJjU+sNbVkzZMlFc1i/hYl1Q06RFsUtTPW09YYgLcWxtG2A
GEH0sMG+psBUPofL6QrYAq6GreRKuBK2kvW0MsaBjkwNEoMx3XFz05fX39h6x9/93xvue+p+ZL95
5+bTP3H2O0446hikZblQ2sWUY4M5g3mLOaM5ckSM2Lb3Kdt4Ir/X1rOI9ZlYhBNinveQBaGeCasZ
XpcXbGN+HrVsDpfDTakp/BQuh6uQlHAlXAVXw1WwHpawmTEJbUaM6I4c4dXJLdse/ts/u/FHP7t3
l7afcsQrP3H2hy95zRk4gMWosAvOLViNicxgbDBHjQ3SwKNhYNCoHwpcARJnrGqdJtbPGnR84KFD
GwwvhfmSJjAoKmMSRjQ53FRuKk3hc7hcSUVX0VZwlZyH9bSWNoXJyIzJxhRbRo/ufu7Kv7nluzdu
fXrpkU0HLfzLM9932ZlvXjx4PndTLlo7l3JkNTYYUxkwMhgRGZm0lhUoRm2YZzvN2HOmOzNY0X7Y
dy42UB2iRdIrLLVnMoJ+WC1rGQSsYSvZXK6UCvgcrmBS09W0tRIhsUwzuoxuTLuBbvP8b+anV1+7
9StfuvHB7T8bLdYfOPP8j73+nce/8vBJmi+PymQx45gYGbVCQQok7dekpV65lmrMeCxHjCpkiruO
69UgDl278FJsT7SV1q6869tQRg9bwRayhVRCBV2JpEYiJWCa2iwzyRztGOnRGY6zN9z54JV/fd0d
992VJzvPPOGEPz7v0gs2b+HY787yZN7ZscXYYARkRhmRAWmjNUyojp5mGrjRRZE2N4yafeyLrfpt
evN7scyOo9TPPEUEnA6U2dAIl4zgSricdWh6VbAeDkwsRw6jsUnmmL3C4sTk4Z07rvyz73/nuu8/
Vzz+qk2Hfujcj1565oWLG5IlN83GNplPMSIygxGVEpkJKsMEcKQjbODNxuCwbR/2SXw8Ct17JGq9
QLEjhw7SdGpAeewH5brakyFNp9RBkh6uQlLD1zCeJKxhZjEamWzEbMG416S7D8m//M1bv/z56x97
5oG5DXrfOZd86KJ3HXXYoSWn07lytJDZETkiMzIjEiJtDIq2NSgrGCKQQEyfCzAiMzW8Dg4nbIiX
0p+XYJhpBlINprYGhBE2Y4gwTUeh4aV6eZCskQgJAUOf0IiJYZYxHWF8bIbjcP3Whz79b6+99+f3
lG7nqaec+MGL33f65uNtUi4nk/G8S8bWjI0ZkRlNBjrCha+kAwxgSRumbEEziLn9UzCmVmHI/nzp
jv1eRjJXqEzHBm3yCnJYQAl1VoKCab+CXpAxcJaZM25OHnSVccT8YY5bzANPb//sf/zB92+649k9
D738iEPee8nHLjrr3IU5W9s8zVw2tm5MMzJMO90xtArhiTasPBAsQtmJiMde4oUG/VMMbEBtyZ2c
xcX7TDW4Ys1C75R9Wwxh7N08CSMSTQrddzQTwwrZyMhAKZxhenjy4tzkK9+48+ov3vTYM/fMHWjf
+r53v+2Stx9+0EFOU5PWo1GWZnQpbEaT0aRogreVkpC4AsGSjWkJLz3SGexk6OPpkFStGbS319bh
3pPV4W6DuLM6nHpqAmVoZgQn4IBx5kxClbbyteZl5mEyuqMTHIjrvr/tM1def8/P7lay+8TzTr7k
996/ZfPxWTUFpqPMjTPjHFwKl9GmtAlNAjrQkBbhP5km6+vnsuLUcfX502g4HRHRVf2g23rYHWrn
5jlcARGdUzwz2M5/yQCpNctFdfARB2889ohf3fb4NV+785OfuiQ9MEWKhx557tNX3Hz9dT/YPXny
kKM3nv8H/+K8N1+4aJEUk/HYzqd2ZJEkdI42kU1pHY0DnaEVjWjIjhPcTa6z3SIQTzwPC3rkiioO
V9CcsB6gyKiyMWD8zvh99m0yA1jQQQ5w3h+8mJ78zy588Af/5erP3bRzx/KJpx3xy0d3fucbdzz5
1P3jA3n2773jgj947+EbD0omS5nj4nwy55gapY7OwFnYxFgL42iC1hjQEmQzvjFIi3v6WNwu1yBn
bpxn7I/ayjpbbVjPKIKvxZkp4b0PLoY5hBIoPCbQksce6flKL2buuv/89a1//pXpNHdYrDBJnD/y
/FPP++MPbj59c7pczKk6IDPzlnOWI4vEwBk6C2tgLYztpNNM3vaN7q7D2607aBEg+0H+FUCNK0IW
25ExARVMSrq1Me1Va7XMdUaJms/0kA8CknJhIuzx+o3Xnhq7s+Tu7/3s0X/40a7tO0cHLLz6/DO2
vPGsRcNksryYuAWLOcOxw9gxIZyBNbSENc1kmbE0hn1DJpZOt9hi6AJiEmsjI64gDkTfNvmHB2ow
WaOAvOQV9wfjKgqHg1fhA2qhAkqpFCfCRFr22l1rT+nzNJsIe5aUWY6BZCkfSfPOzBuMDTLLzDCx
SAhHGqPAEwwzh8aw71jNrLiJBne71SH9Gc7IacVRQ4M5MgqoVheQ29fIasxI1+yId4cm2JDewvxA
QEqySGknZZEU9ZxoS2RkNmcyckyNiMyEsg8tm5mMpvjHZj0GuYIy0s/o9xKJ6JpxCb0pL2g4uNr1
zDWo+a0rWe3H1uM+KmZW3ESUkTbGg55K2iETJ06hJDFja7wXhIRMCQelQGaYEq7NFhwVJNKszWlp
q4MdN83Q9cqpeHFYkuFAGoNNXxjso9pHCHupcsfMwLyGKxOaMBuNuxtCoG17GgQtZMnEwBvJU5Al
EsCADkibBDMMhcm2BD/GELXtzq0YXx5wwGdOMUY9A3IpFZFU9p2W7zOb12AErSvCxjxh9QuGTLeH
Qk0x1hDWIAk9bNswTywQBNfkmCG7pGknC/ulcv2Aw+rxoqfNRygtUOHaxKibGe+bWNLQbHun5EG7
vlyMEYWq3/M0cHidI+j2OEVAJABrp4FlBt63JVzbAglhynDVkgJmMr5+Kp1R7Xc4u99NRXapV7zl
bJi7t4GuX2Gw3npQlHhgGMW6/n3fO2tzAAiGJkx2KkogWyoIDGjYjzMwIq+1xtKPTMY+RRxWtzqm
e7cUiIqHgLsJVfXMYM0srdJqWeeaTIzDdYWazWMjLyDE4dW0KC2ICV3ByvSsGjYBK+LMRht/ogJO
PHcpDId0OUv2GerBTIOwK50Nd+JQq86Sr8FJR7/TB9jZukfcP2lnaEz400QdyHj6PmK7R+OL0qzn
1TA2z5obZ0Ac+/qetEqpZ7jYa7jIKfxlfSzXCISh61z0LOhBpXFF5IBhM2zmpVhRBmOQ0V6vTtKr
zVkOIZ8wsNjVusdtzsVo05FmthV1cgyiWRcFrxNxVFPo1bud0W4ay4O1iuy9SvcBLdzrd5owGlni
bI7cXUdRTDPs0dmgsjFwlfGnM86kB3udFPMH4/WDaxWQBlTFjvM46A+q37EVlR1jupBmmFvxFjj1
M3mDPkCMLrr5bXVtdA0HLXsY0O227AnhipZOtnxWzmKogTtaB5Fc0fad2W2NPY1mBlVr9e4HIira
amfQE7pj8vpwD4ZWILN4tJKrtH0HttpHqUHRvv/q28H/tZtYS53pRc9IfxkbWs8cJyMH0eG3gN3Y
kSQjpCxosJBxEJpi/k2/vYamn0LS4HYwqDC2LmCVHW6D1SPtDXuoXt3M9uKDmv2vwyCv2fiI4d2v
2EHTEV9b9UfLiu0zg3Y7b1THUuxBY0cVVdcVhQoOlq7FNMQWXnXVVQ3rAmL/XB5rFVBnz/KQX0Ec
Wp0wwghKxtuforomY1IXsaprVETGGuxMW42Uw9lbXrFHUJH/m21c9EcRtGHtAoLg1e9dllffG+OK
MvhwRpEkVi45HvQY2kkpDmZhBxtGQwWxp0ZQM5/IwVilZhwv4yOYWZzZ7x9uOD3B+wjyWHV43q2u
QRU9QMoYQgrzTYMZhdnSXFPZ04xH5yxFaUDEjTYgxNBOqyzfXqXD160ppGad+uxGzH4qJ5p88kAt
eaiWajS0/LXUpL2HKkWOFy9BfvhH+OJLd0s1wAdtIJNqMLBn9img/a81RLH9r/0C2i+g/QLaL6B/
DK//B/Y3T+IcXrEnAAAAAElFTkSuQmCC
B64_MARKER_4

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png')"
base64 -d > 'android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png' <<'B64_MARKER_5'
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
QCHClgAAAABJRU5ErkJggg==
B64_MARKER_5

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png')"
base64 -d > 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png' <<'B64_MARKER_6'
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
gg==
B64_MARKER_6

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png')"
base64 -d > 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png' <<'B64_MARKER_7'
iVBORw0KGgoAAAANSUhEUgAAAUQAAAFECAYAAABf6kfGAACVtElEQVR42u29aZguZ3UduvZbVd/X
3efoaGKSkEASiEkgRjGIybIBA2Y0YDuOiWMnTuwkju3kxo+Te5M7ZHhuBsdxboyTmNFMwXYwGDBm
NLJABiEkRjEIMCAJCSHpTD18Q9W774932vutagE6/dw/d2+eRn2+7v7GqlV7WHstwMLCwsLCwsLC
wsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLC
wsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLC
wsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLC
wsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLC
wsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLC
wsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLC
wsLCwsLi/1dB9hbsH7cuB24ovEkERgPAEYU3jQFHgItvIQFwCD8gIoB59AYTETjdTgDnn8fb6e4+
GAoPCvl3AIMBpvCY4icMDs+7PJUc4bdI/KsKJoDK7czluROFv+XR36V/O/E89COF+xKvgapXyhx/
4oD4voPLqy6PS/nfE08eLN+v6n2p3rzxc6PyjDl+lix/l9L7kd5XFjeK+yUaPaPySab3ksrj8vSr
yJ89T35SYGZwzyC48H18C5kB9vH7gfNtp53T2Tl/N9HaW3B3VwuGi6eHi4CWwRDIP0vAQ8zjU1Sc
JJyBEQJGfQRRl086pnQ68wiwEsQQx58TRWDxCshIglsEzfTkKYNVQgcNdvH8K6evAEekx02PkHBH
/B0xZTDJz5k19pWLRgQd1q+yPGR4fewjTjLl9yBDX/x7CcGcADTdcX7tAMf3gqprjQSx/FoTcMnr
R77YkbgAibuSQDdxhcvvjXjv2LH6SIjEh5A/PnHB4/I+kkt4HD9Hh3h8hNfKDMDz+PVZGCD+INEQ
0GQAE8AYTwYnjnMnzyzmMSZK5OT66s/5hM15D8s/LFkJqVwxnCSUobvOpsQ9pqeW7j+DFUm8ACdA
ZQpYKkEqQ2l8vl4+i/JzmdVgIjus8uaJ9yP+qYvAz6yeC9VZM9eXMdb3m8ClpKX6b1i98yUPF9li
+v302nWuzpMJqPrwa3AUVwim9BnFZ+6oylrjz5nyJ+pcBHZmMKULUKhaEC8acAzyDNcA7ChkihYG
iPc0XDgnw1WYGS5nEazAiTJiqWREn1AIWU4uE+u0Kac4MptLV3oq2QGzKKfSmVkehRgqeyNR47FA
0lIepkQy/h5LEJB1YlXIyddL4Tnmn5IANdKpMXGVfYpsB/m9LWVqzoI5XWhIgBFUe4Bzxk2j35CA
Vt5mEkCv8i8BrhNthQSqnuurk744EClwLYA8bm3kixNxepky5VTfU8z883sZWzfpyKD4NhAAdgB5
sgaZAeIBvDmpHI2lcEMFAVKJLPthJKGJqu4ai9qnKgsLUKUrvjiBxYlUToCSfZE4aUvpyLl0Ve25
qoou5W8E+tgnZOL4t1S/AN0HI93ZlAmZyo5kRkVV/49kacsTPcnwuvP1oMrBRM4awZd0WV6XriDR
G+QKzLj0C+ufywtM/hwneqnpQkGlvCZHOcOXnwULAA3HGJXXId8BVy5WohcS3g/PcPl1hs8ktT/K
5x3v29k5/f0kQRb79hAJjgkNKF6By/Ak9QtJ9QT3GYckYKVSkpZ2lMjKmDWwEgVgIlQAUM0IIpiV
7K8kRYxyJpJs/BNNVq+5lKbq5JvojU5le1TO5whkPMrSSjlfnkDpX9LoPtPz4eo+y/1QLvNLpjzd
v5M3UOo/UvWLBJXlAfJix3FYwfkNUO//RM9YgmHpEoQLIoljhKteLcnXy/I4EhdVgvq8CAGAY5M7
9xhBGiQtLEO8B4CIqm+oG9sla5CTSa8hNaITqyxPngmcUzaSAFcPYuKVPjfhucpCqjMpF5cp0wGX
sjihWdXoD2UWgTHZCNNFKHN+PRJMS6YnsieGKkGpLmWJ1NMqeSCP5tQymx6XxOU1MpXRURmAl54k
RFJOE20AVa6TmunnNnBJBPUUu5T88e9Vhs6iNSxbEPKCJC4eBPnGiMRb9zZJ/F/6G59SHh/A1oYq
liEeCCBCgaG+MstJoOzn5QGEKBdThiYBL6UnLMrXdF81KyVnQCxKbq57aaQnpp7rdC/246Cmw6UM
lr1FHg88RNugZG6ivJUZXsycSGaQXEA8ZMyUJ6RUvfM8OZyhnAmlNy5M/6n0BNWHw+VpsyxT9dyq
fu/Tc0/vK6MMdlj0HDnPVPbJoiXYCiBm0kMrJknCopIN1qhHVRuExgeqpnaFTDb0wm2oYoB4KoDI
iXoTSxEKPERH5dh0VF2l6++YFDjonpQAiwQesWbmWF4TV5xBcSLJTI5F7U45cyNUI+sMaky6vE4N
QWJN9yA1NShd/ARsVNFlMvSNKEicWwSZIwnSf88TPUSqs1U5UCo9v1wuioGQ7krK6b3mgkoAEVMy
/XjiAkK59zkxaEFVAYgLqMTpfFGavAxw1Sut+7myFUMToEia4lUBqYUB4j3MEGMuwDzdYYyZV+r/
JADLGVDKCGvOCCfgidDApTRk2XhigiysWE0tWZTHJfvwMlkdlfeU+5ilnJzmGKbsg6nwLzXZuKDE
mJoiXydnICcFbgT2+pnqka0GSRL/UxcU9foF1Uj0/sozZdWfFal5VYJTVRFAZYsKpFhnZSrLVK2C
kmESkXhF0HQm1JxMyhkqJvqiXB2bTOM+eAZNO9sNEE8JEAlw+epeTkaV2aQeHsuOEtf5BXS/XPPq
aswqfUQxMmBZxgJpZBjK6HJKySGPTkB41AygeJJQvfNRtQNSVsdcn/EluVSvl2QpLvppFWbkTIYE
ZLEgnxNFTh3rR0x9QEmQFsTrET+RNdAGYPTVxYBHIxfmAsUuMQsmclVUrQudqaXn6OJrEpcT0g1E
lY0z1HFUHygs2i/j5I/V557ePauYDRAPpIvIquvEYXBCdSXDYmBR+j0k+YZ5AKJLxXSisABAluiS
BzOsprZUs+ZY97xINuCp7jvy6KWy3HKh8XBWdt5Y5VJcpYc8MSigEXsnZd4kp+NiGMKexSibS342
AoKSWTErqrl4fnr8y7KvOlpQ4VEZXN5vUphTsM/pknhUgpeLQpmK68w905KoTM01qx8T2bOevOnX
Xp4EWYZogHjqbw7HsrkupXRfrZxbJAa4ksJB1bW6Jp2IU1GV25Qzs3JKO30SVWt+qlCsl0C4nvwK
Lp1sysviVaSZTDRRVHJOExnjE1RiIolyMb1vVAPQRKalS0xSIEdVxikzWjmPyZs4GXMq8nrV3y3T
ci5YxiJbpjJp37fnyfoipfgIk6lmhXekL4D6Ok1gXfGrL3lRo4lKxMIA8R7lh+lcKX1pqqa2Mk/j
6juIJQVWfTgmPQXUR7Cup2mfZIahBQlYnLmpxKfE2Kj6mLIkL/2+8qVKWRLgKIFEpZIMGmVlpdXJ
1epbXeepbFbk5XJKK9/hDEhTdEOVtPJEBgglpiEpSqqHxxgLSJAusVlWEsSqtaIAuXq9sv2QLiqs
gHiEjhh3LMSigCYnlfFWKvUnS2sLA8QfqIdYDRNY8mE47p7KPhap5K1ec5NbEGU3Na69ZTCispmC
auBJpCAYog/Hksc4QXweI0J5LKrY2TLTSycriT1t9fq4HrGzIoNDlO91GZqzxQklFxZXJEa1Zph6
e44grxac6VD65E8ATy7+TcrkSQOI3O4mxT+cUJ8RFwwivaOds1Ous/ExIsoN8PrzlvkwCTIji6UA
fc/VljdxNW02RDRAPJVglVLpEzRmXaR4Lzo9zAowBD0hjbVOmvaW7Q7Sp176gSOV/XBNC6n4zyzb
Zeyn8tYCekTT/bNMlJaZJOUTXaqtqLGynGmInmoevHC1qUOoRBRYTU4zOTopuUD0ZhXJnavnQVpt
B/I5xX/7fT5wSmCimxvMrHiKqofL5djIAy514fCx/cGjjJExVhAiwrjNQjrbZEyTrSlMA0MFYpMU
A8SDrJlHmjC0jw7faEwr9+f0NJVz/4xGjT6uthK4GmlMVIDlJJBiDkpLSjxW2llOyipclWBULWGP
dxOrLJjV1gVFOhJLhQLRXxxxD9NrI0zsAetyOa+8QRLCa+I2j1eiR9Pc9D7XfUOM6IeieSgyLej3
F4IzKuXW8pBnNPXYJ1tk0W9G9S/SMmRVpcCo9tKrto+FAeIB4KHQC5TnAOsTMR+MNdc2N/fLlDjf
o5wIq8pKq9rs18NKwEJCMUZRb1hDKktyHJf1scSf5JxNTCi7sOjniYlwGWQEECQq2oo6Vyv0oHE6
W0CM1coiVyUkT4CeUkVU71HO4qkueSWnr1IoonGiW981cyVjxlq5puIJ5F9RYrJ1mU5j6hONSNms
smcifYEd6WYyT1B3LFs0QDyAqpnZl2Z3vSYle4jqcKdRz07+nu7N6eZ5bpTHTKuUWgVUR1Ue7VPt
T2azYhw52kYpmWI9EOCJTIwUNnAl2ipFwXTOUw+idBZGQTA3Z3K6b5foR/m+q7U4CapyFMvjzkGl
yk25d0iohhjVyqJ8L6UwRd1+IDkUEwM2rulJ1eVvqhxm0df0zKPMUD5hkltLliEaIB5cC1GeQZUC
M497T5qxPe4zseoyQeQTolvFFTZK8jWJhjkVyk8CTVZUEylYS5P6gCWbmFglIwIj9L5oslSv00Xd
N83Uy4pYXYbeNOqbkVC/GT1WNV0tQ6r9er93M0yIO9SKSM5ai5BqPVsa90CpOlb0QE1zmQiYOH5Y
0IrEJUPZTdSthvjEPUehYjdO/gjf6wYLA8R7kh7Wogq6rFNAKbcdmKLyTRkKKHmteMapwUK1ikZT
nh9c7r8MIfTz0qBEiswcTiRkEQhFWuOxtKrSIiQBbNUqmyzRdFVbiTZQvUw3oaJd02FYN3UVwJF4
PrUEl04eoZuAPMrm8ndeizko2wCqJcGqC4po9JIgP6qdY3X20XTzWvYVhRakZJtiUu8x/nxqVcpS
RQPEU+ohZg1DCOoHoTbkINTGS4JrJ71DUAQjRnQankqIiggW15sSKYWMd0pcLfurD5k07cWl5+pV
nzSLoqbeFDOCQQepgQMJ4K0pQBAgKPfAgzkXF2UYJeBS5PPrzFvSb/KUfx/DJXVBkmoKFcVGbRRN
XOgK2NH+BGquH1JyCcXzZDGx5vGFtl6vVK2Xip1QskRWoK4oQtUkWpkiGB4aIJ4yKCpnNYx2ctPw
gyc0AEly6ERmyKMNEpbSK+pkDmuCJACX9XwzTTOreYVWyBZQzSwoPmUPh+S2DZd1LxJnvQLASilG
9+REzxMFHDIYUpHB30c4azxNJ4UkavAdrgnjrimNMlTZihDZaVUKT+wsFlAViXXIIjWIUVKr5qm+
sBClhVgzrLPainql2y08vugJEJTvhapKyIrm7ydMIPbuwFBRVopKjOSzlX3lWCJz2UKRKx+SQpFc
6Ur/ixS1JCOx0FdMtA7JQWRpUFVllFShCTFPeIaI5GZKYEKu+lFo5BPdjX2pXvorCKC8BVhbizL0
WEo7mJbSnscmBjxSo+Fxxp0MqpQArf58p14GqwYil881S/2TBj6pbygm57WnVbj2CR8Vlra1Y4kv
pol3loukl/LR4moFkiQLwcQdDBAPooeoypnqeyllJfpxxJWGICqLTJJ9NtI5kuBi5P6UNC9i2ods
KwRT9QMK4B7TPiQccTWp1f4tPPZgkWmcIz3JrTJLuaJWxFpF5p14kSSnyWMqijYjpEISl3L+o76H
EEetsrcM+lQ7+JF6T7KndsIaV4FW7RcgrB+0gC4qcvZ4zKZWIVmr/FC+WApdn6mdaoXNhoQGiAeJ
h5XYqtqyFe5ySeNQa33R9DqZ7P9X+7uKb6xEBBKBmaAWRIiqCWa1+JzvT4s+aOMjPfOuQZK0GaDQ
cJTTC1R7yly52SVXOWlsFe97n9kKC5uEkXNdlcRB0IPyxJaEN/GU3qIYNrE0imFJfWGdeMn3jEh4
acuaWk/784WNCvFIWrdKYyiqDpCcZBPpNUhofqhkNCiDrZGQr4UB4j2rmQF4vS8rTzYWR6tIjRLH
jCpJfarakVoOnkdgqc7CakONlUUoa6oN6z1qEpNmFpw81R6trDSLoafOYJl1+Q8aT4dptCIoNnJq
OSw1HWYNOBLNawvVKbCpci1CNLhP1qTS4U+oCWk3wzEzm+tpC7PKIHnUMGDtwCgLXpZlc73XPc6S
1c/rIVyuFmis5zhBu2EjZhsgnnq4yUY/TR1gkjuW/k7OSyTPUJt8yC7a2LJZdSG58mwe00fkXrAX
PsSoi3hJ5aAKIdU8gUYnu+TZhdKWJ4h7MoHj6jVyJfRQSNjjCjCAulfTedLjB2EdypX1E4seI0Mr
Cyl9HrkFAtL2sDIzc1AXQBKAPbIAlT48qKiepHermUVpDk2IH9GvlO1hrTdu4xMDxP8v6mdVN3GW
1UorbzxxhVYUOB53FKfSQhKZVO3xNJKmrgQVwGKqrAyVRrshCmoLrtA4k8VUW45QF3DScY4qkEbF
dMnAKIdJzJmKojiX8jogenUVXqkepbTBzh7STKIFkToakvAsy18B5FLvQpnRazAs3tisqEeldNcH
CHM1dJMXCNYDF6bKEKx6TsyybK8ubFT3wC0MEE8FBcWYknMJjconTnphUNXPK54okCbylUQVRC9J
7bnIPlo+wr3WKIzTTw+9bZG+8Sqp4RGpVxW5rGXEIKgkOlssiOkiEDpU0mCJfxh/7qXgFVeNzgl8
T1l3ERsiBWggUlkokZ6MUzXW0cOI8npJaUqODwGaaG8wtJ56gjapRqMGPeJKk8GOJJWKdQ8xc0Gh
bVFZVAKEfUrhqWasxffVJbOYjr4fmLgeS6aD0UUeGSkVlrE2XymBx9tVVWagmLtOJZKszNl5bJUc
f8+LAUy62adMLA8PtJq07D96VE1/Pecpw5WKwCz1+hzi0JmLDFZ90FGVjfHowiAEdCf0hXTWWU3O
lb8oa5tVYDx1rYYZWuKRcylPrMtgycmEzOhGLQzZw6sGaOIiVPdw1e3VxTX9m3hs0zXyXkm/7oFm
o7Fz3jLEe3q1oImrqygzaaqcrQyDuNrCQNX/k8KfmbJDo+xC/T9R3SETAFeI2l48Y079NSKNoSTp
NuF/PmdFnLNAmQ2lcpWECyCJeYlHAsOSORNVWxOiUchA8I8mUbITq8EQi0xz1IvA2MSdo/3DKDFi
rhCYSgYseq8yEyXZt0PFXxQcSU0Zqp8dKwtU5qrBLDJarpuGTq5Vku5nkNbSHJXLAhitaDZAPMWC
WTfZlbk7SsalsxSRGbDMTLxa1dIZkRiZRPoOTa1LKK3W4nPCaTMkKaGk8pSlfakuy+otk7IzW/uu
aDo3cfSpjuWfkzBHQFMT0YWYa62APXKCk31LOcGf4k9zlfVF0jSPsi8JRrIhWVko1Lvg6qbpjBIj
IYgEdoQpE7DJDRgJ0EkCTYrpisk959ScdAVeZZNE9XDNzmUDxIPqKKRNB9QkYzl1FaUPcZ4wp02S
AHBOnAOsEhbpqUJiEqoEQAlVX6w6zoniZrJWembBnZSlM3PYZC64Vyaa2mGVtJ9MPHmb+LS9wBli
YMjbHOEHTkxRiQmO9KRZqWADVW9tnIGPJq6iz8vq80IRnWXZ6tC6i6olMVLGKRmjyoan+g2izC8P
y2prpGTMDMUwqHhZEuTTumPmuqqeaxGhTc9dam7K48wxGS4aIB5M2cyi1Mm37ju5o0oOnsBVEqIG
B3LoUhlRjQtCrsCk3CqFr31WpymZoUchqQy530j5xE0EZq8mx1R2dbWeADwCKKbX4VjvFLsoROCZ
4Sj4GmeSsFp7K5QWpYrtxhUgyxU3qsVmWTjOke5N7pfBY7zGzDwphiOAenqKTkIco8x7xDGghD9I
DWvqPqMayNF0b3JKAFNJwY4a1mQbKwaIp1ozJ+l2QZgV8tZlsZ8rQzrSPh4aIgvJlqpBijyLqX4M
0ebnMq2tExWP4l+SMk3PwJBc64gwxEzLU5ko+wj6nit/D9XPDyem4/D7PYCGIi2vEsBtiJUKdRk6
adnIDPCelTuc8myRIFENSnQSNqVESALQqgZfumB4yXvUn2WeShNGAw1dYrOazNPdrdLVxCcirS1B
kjx+tz2dqqcsl3Yo+unQ9P66hQHiD54eyv05L3aRBU+NtNQrZfK1miToDEU27dMGBddmIqTtRSG3
yhS8KnrKaJjCKTskDBH4mICBCQMXwEygmHqfCSyzJk4iTnvOMn4ult0NMBK89xyaBC7WuY7khYIz
Pafs6Dplw0DVDrn6f9JbL1wNYUhcXGppXNn2gBBgVQMrRasJbn31fvZ4C5D273dO/4HuAwq6FSqX
QaVenmk7U73S0qbZbzpvYYB4QNhYAKxMW8ueMleT16r/Db2IpieCJNm1oLFZvJgLqBU2ogxwzEnb
umSQHMHOg+Bj9ujzbQxPQO85Zoycf6cMjQL1x5EE6NSTCiWzZ0aPyD+kCIIRhB0BjSjnHcf7YmBA
7CdyLUQGZSiv1aoL6blcLGr98fImMWsVIZWdyb5dZTeqaFCy0pSbLHw3xwihNhbVJISJqpeoFt2I
x4FnbUGKKFEJvUYqWwdUC8dmVy7LEg0QT61mhjISospyVJTEWb2QqRI0rYGRKomvsiJWZ5FcK1mT
9NIIYIjYp0ulcgC98Dx8BKaBSmboQeijlnffM4YGcLMGTvQEPYAFgKVn+OWAlsJJ6EBoRLerAaEV
EOTiRcFROLBSdtqgAGPpGZZLgwRZQlmWZGHE5SQxe5xjBfAe+apMqQiVHvCk17JQ5VE0w2oQRtG+
oUikxU/PVU5+4Klm8OgY0wLArJTQk1FZHtYxj1oBzNMgW7yh2QSzDRAPAA/VXsZ+9qNU9Z60E1y9
9cFUr1VpqkQlrpN/z4sMKJfFxKIk5tgrDD8fIrgNHL5PmWPPjN4R2o0Gw8Lj69ffjm9/4Q70d64w
71q0Rzrw/Tdx+iPvhXufu4U1gGF3jc45dI4i8IXTc0gAxoWQ7QQQpv5iALUA0i4OXRKfMSl6e0F0
L6UvhCiFHrFnkk1NvJ4qUeVmi0f1N5IXlK5OrNR+tDG2vt9MpwKXfsV+ZHBSXIJK/5EnwEzQnmq/
6jo7nRj3KKlFSxANEE+pTNbEP5E5kFKeUb0cz0IgFoUzyALsWKGgkpjKmofipOJq9Vny2kr/L5W8
YVLsY8+wj2VyAsXlwJhtNGgGxrVv/RqueePncNuXb8dyexeOHGZuE+wHrLCHw/c7goufezEe/NOP
xBmXnoXeA8u9Ho0jdI7Rxvt3gpTdcPhqCRjAaCNgccwgU5aZ2gounuiO4voflyw425AwFXqPLAsl
YFRT1tqoCTopF2R4uRQsvWRc+RlpgCKhQKQcJRha7FU67VW75iqtY5YzvFEZzcJKYUoKJF2I5fqn
UgrnccJsgX07vRb7xLAeuOQqkjtTq4tIhRtWatPyoCa50VCdNAweDWDkMoP3ZcF/SPZVTBjiZDiD
n/jqAfTg/LPlwMBGi7u+egJ//s+vxleuvAlDs0QzDxmRcw0adFgPKwx+BawBLAndGXOc/7KH47F/
9zLc64LDGNYezcpj1qSeIaOJ/cMGQBczwyZecR2AjtJtYXzSxNflUL5o4iu9q8oygMPkH5JjvU/W
XmdRozXIapI78o6mSm5bCswQVQIT1XqlBMnUWGHtBa2NG9V+YB7mKAPXuvSXGaNsvcipuUe2tG03
bXXPAPGeAmIfjybUkvLlxNQadj/AbI9F4ZOB1mNszabFBJgDIHIakIDRxyHFEEvYXCpHQOwB7A1A
v9Hg25++A2//uT/ByW8fx9aRLayGNbb7O7Dw23DUwqGF5x7MHhvNYWzNjgCDx/LEAkfufy888m8/
ERe98hJsndkBewPagdE1hBYhK2w4ZIUtlUyxFeVz+D3K2aKcODfxQpH+nf8r1/Z4vHBClQU2VYKx
4wYbK7kwWQqXDSBUe8I63aO8Tjj+nGhkBVv3CqukVG0MysEMjXuQ9e43aFRCKwGOLBAbsu9209k5
b4B4z6LvPZNQxC4lUbWhUtmI1DKlXPXG0lkw9jUSt5PuHSXQHTgOTMBxWMKhx8eEgSIgcihXexA8
AWtmrBvCnd9d4M0vexuO3Xg72tNa7C63sed3sbc+ib2dBcANGAN6v8Ks63D48GnY6E7D3G1i3szB
K2DYA858xH1xyT+4DBe99GFoZwTe6dEBmDeEGRcA7PJAJQIhAj8xDGNStliGMWlh0cUhStr3cSgb
LlQbVWWj+NKTy/L+1USXK4uBscF7+eUR7zu1RtK0O8HbSJ0HldTZBAhWGSRIW0zU/UJZPksRYqL9
T2OuVgLTimizYYBogHhPAXHdc57skQexU++aBjqdHbI69CsL0TRdrj+IylyoqH5x1rvzIHjmmAVy
LIvl9JiwZkYPxhqEgQgrz5jPG7znNz6GT7zuk2iPeBzb+S62h2NY7va4733OwQ8979F46KPOQdsQ
vn3zXbjmqhvx2Wv/CoDHxlaLBjNsdkewMduEX/RAT7jfUy7AQ/7+k3GfZ52PGQPdzhqbzmHmwvS5
ZQGEIHQA2pgRNuD4Myo2qcyZ6E1cgDENXhwxiFx9XdGq3iT6DJGPWIt6f89WmrQ2kJap3w+YVmX7
hPIlxhb3Fe1nVHLrJo1sn9YOtsnNMJuSAcpCwNRuDBBPKUMMJx5XfSlSu7FSnp1Gb2ul+zV1UqEY
QGlSsgZEX/UIhwh6PTMGIvQIGykDAWuOLUAP8LzBbTfciT94+TtBfsCJ1Z24Y/cWbG+fxJMufwz+
9//nlTj/YWdjAeAkgBmArR742J98Hr/3H96Hz1/3NXQbwObWFjq3iXm7gda16Ld7uKbFeT/2cDzy
Hz4V9730bFDP6BYD5o7QEaGLwNgR0InssQFlUGxEeZx6jBSn1SnZa+KOtHMkSN3lIK5X29J2UdJp
TOWwBBsFJvWmCPaT5q+nuYJZymMCOE/a21SaiOpoqV1t4q1SRMQhLaYLJXDJhKgm0yJLbKyHaIB4
zwFxKFKprEhpI3+j4tmR6+Zy+JMGRqp0wHJ1k83cSx8ryUR5IJbKgWc4cMwGAfQR/PoMkqF0XoOw
HDzWmy0+8K8+hut+6yocvtdpOLZ3B46dvBMXP/z+eNWf/CoW95rjlr01tj1wPPYkz+oaXDJvsLWz
xntefw1+/3f/HN/6+q3YPNSg7Tq0mGGj3UKDFrztsXH26bj4rz8OD/6Fx+DI/bfgFh4ba495EzPD
2E/sGDFTjEAYs8ImZYEJMBMAprI6ZYgxw3RSiCGvWJZtljLlp9oEb5wNyt5hBp4CWvtmjuokon3L
XCUKIUWHaUKIfarkrSg/qvxPGzo8obMYid050/SExnqIBoinAoh6I4C0HB+L8oZI7NVqrw2uHOII
VbYJvRdd7r9kMwOK+MJAMRNEyArXca+4J8aKJUAS1uSxQw3e/JI34zuf/DqaQw32VifRLwi/+aaf
x0OfdzE+eXKFbtag50DI7hlYMtAz45yZw6M7B/rOLv7wVVfhra+9ErfffjsOnTbHrN3EjDYxn23B
scOwu8bhB56Oi3/+yXjIzzwWR05v0ewOmHtGRw4NGB0z5kSYIQxdHBiOQ4kdJtUB8Nq4My25jY7K
VktDNDJqQsw0a6sCqvcK9wNGYDLTm2Q+89j7mquKYKSyTaW031cQ9m76iHXLWnm5COitPV4sQzRA
PDhATAKvSptUnBT7TvkqVWU5r5SVd84UfM5EWZCC070OKUOM/L4krrBi2UcElgBWHP67ZgbPHO78
zh5+/9mvxe7RoxiaJbZ3t3HhAx+I13zo7+Obp81w29pjTYQFGAsOf7+Or3NgBrzH+ZsdLmuA3S/e
hdf9pw/gPf/zGix3l9g6bQbnGnRuhtlsDlp6YOlw78dehEt/+Sl4wAsehFkD0IkeMyJsEDADYwZC
y3HAwhym0khlcgC8MIQJF5qmBkVCLq0lGyqVz1K1X1oxJA4gTfX7ppz99qHwaCDl/TS9UYvOjqV9
NXWGRCnNtZgtplb8qlOZOdB1EA4I1QO1DPF7hrO34Pu5ZAimddalKkRqbcZUVJWnVEaEi2VVc5N+
PHmM58SDq73lUowlio1H2UnuGVg7h+PHF1hsL+DJB9Kzb3DG2YeArRnu8Iw9IuwA2ObQQzwBwlEA
d4BxjIDjjcN1ywGv2+nxlYefhX/8334Sr3/Pr+E5L3wiFrseJ06exGLYxt7yBNbNgOb0FnfdcDOu
+sW344M/9T/xV1fegsWRFqvNBnsDY+kJex7Y4wDaPQNrD/Q+7ll7wuBDW6D3HIZIQ2wTCCGK9Lue
C086v1deCROF9yv/MfRiMY+HWnpIMbXxgsqCFqOxSdktRgGpfFQQNIuAlc0Es55Co9rrZq6HcaVV
kF8nsaU/P2DYpsr3CM7NeH0Vl+uuRXiFMmDljg5xdeIloyApKgu1nSKNycueWckAivZhEU4IAEiZ
g5jOkyWA48seq34Zp7INGjdD4xx6ME4C2EUolbcB7IKwC2AZy/G0YdESMBDh47sDvgSPJz3pPPyf
b/sbeMm7L8Or/u178elP3oiNzQEbW4x+uca83YJ3Hb754c/hlr+8ERe/7HF47N97Iu790DOwu8Nw
ix6bjcvCBQOLx4rvXZ+yxfRucuBeameH0pOjerOHGd5REW2NWZPL1zRS8mQqb6sEEkj2gu/mWIHT
CuGktmhkXih9VEp6S/Cxl6z9ttXxiMrkjJTOktJQpJQV+3GP08IA8QdPEDXzNtMa8knDLLpHLJzp
wu3K70JNmOWAhUc+xeqyTmUfWEp9JRDx0ULAR61DL0AyDF04aOMJ9WoXM94lGHsRFE+AcJKBPQBL
IqzFWlgHYM7ApiMcRYP37fa4lgiXv+Dh+N0feSg+/OZP4fdf9RF89Us3Y745oJ+v4LjFbGuOhlb4
yls+gVs+8GVc/JOPwUN//nE487xD2DsxwPce3oXyOHDgw/vQxKxvQKWlkS05Y9ZFyH4sUictg6Nn
sTEUhjTso6Crg+aPssdoewgCZBUlRpfRUkShXrOTO+o82WKJ+OwjoCZ9xMq7VG5d6zVOUuuD6lji
eqvKwgDxlFJEKVhapsf5BInAUrvuUWUqXzYohG4eVyDKYyc2lQmKYzwLwjLnn2fnPc+ZgpOpJyk9
Yg/vPRrn4BxhxQEQd2K5fBzAHhEWlAjf4SCZRVDcBbABYMM5rBh418keF3WEH/rbl+GKl12Kd7z6
43jzf/8IbvrWTdg6rcOAJXqaY+PQFk6evAuf/O3346vv+iwe8wuX4xEvvxTNaR12TvSYpewqvg8N
wtZLE0E+r//GjNIRwUdpLBffFM+ExglbUaq0D6XXNSVhWMp93PT7PgtwYKTbpdb0pN+T5yL8G8Fa
VQ7VfVGqHkRmHFLXkt2qfUVokWImqiwRWB9bVf1u2aH1EA8EDLOqMiUD+EpiPymjUDXCzJL30cs5
X72VJ59uwdPI7l71kUhOMlEGPF70MQNYpjW+cB+5x85R9oEdGtcCFKbJuwzsgLDDwA6Ak2CcAOEY
E44TcIyAowhfdwG4E8BdDOwQ4FuHbw3AH2z3uPrIDC/4J8/EGz74q/j5X/4xzLstbB/fw3LYw/bi
GPaGHbgjhJO33oGP/m/vxh+/4vX43B/fgHXXgrY6rAfGqmesB0LfA/1A8APgBw49RQ/4IUzb2QP9
wBj60F/0kZfnkw7agLTbGP7LZYKc7BeYE8fTC9P4CkBYiEpIQ3vSvipOzCqyurjM4bgy1IIWsJDq
DEq+bMIjuqjnULG49eXBJRj6KaqXhWWI96xe1tsClVNvBqQk905VjZ2VWeAqAQfZzxGpj1LE0eVa
XWwnia+UvPj42GGLhbPqDdIMgX2ZNBCBnAMDWBGwoFAmL+LXDhF2ibEkisrXaT+Z0XlgixCpP2G6
fboLw6bPLxk3+gGPOv90/L3/8FK85JVPxqv//QfxgXddi91+F1uHB/jFgFm3gdnhDrd+4Wv49j/8
Or7yjEvwjF98Bi568nkYVox+d4UZOXSJWhN5gckLZhjCxSZJaTAFzHOOdMvVi2I1tTdc6evBCTtU
lmuTgffoWVixSoShfbSvU8anKFZF5IOVnFm5aBJXzjIT1gDp/lkITagBHU0M6JQshGWIBoin3D+k
SiSgOgFGNsG1cKzmoqn+Y21cTkVQNXea1D7tROaoDnvkKezAOSmKdB0G8zCZKfQAVvFrScAeCLsU
Sug1AX08qR0zulg6p/6kF4+98IwNAN45XL874OtgXPboc/Av3/RKvOTPnoTf/bfvwaf+8suYbwzw
rseybzCbzTBvZvirK2/ATR//Oi55waV46i88FedcfDbW2wPQ92iaJoOiAzBEKklDxW86/TwndSQp
TvGTcaVdwWCQc+GNipk/CS/n8tnSaEfdVWRr6Xw35W2SAFepZdf2pftMq5XFxMjMXoKm6B9OkcPZ
8NAA8SAqZta0BkXelVLzFcwUfTrh6JHEIVAJhSqVZ3Etd0qNcSQCIFkZTKisAyjTUpL6TUpdKDkp
x/5ij7TVAqxAWCKW0URYxsozAdCM46AlDW7ycIexAGErPpdDLpTfH98e8DXHeNxzH4L/esWD8cH/
cS1e99sfxFe++FfYPDQDiNH3PWbzGQZa4FNvuxo3fOAzeMJPPAlP/xtPxX3OPYT+ZA8ePKiJQ5E8
9yjWm8mH2kVuoqfScyQqQyg4KGpAErZlJ6T6XQRNR7LeFHREub+uVwG5Mo9SWd4IzIoQbRaLmBBz
JdH3pEotXN6vBmjWpvcgM90zQDyI8EAyP5JAKJvccCOp+ion1KUxZEYB1dsqgEtlcpr6jaTZjzI1
TVYBnsuqHyKBu8/lNAqXUfHzQvm7BrAEY8UBFFcA9uKONCPsGPfx/hKsp0l3D8JG1vtLT53QOuAu
Jnz4RI/zOsLTfvaJeMYLL8Uf/beP4n+8+krcfutd2DzcYuABDg6zQx0Wuyfxkd/5AL70vi/gGT//
NDz1pY/D7NAcyxMLDAC6yJlJvTefnPqEDWnaVgnlM2f1mzBEDtNl9gC72D4YoKQICSNfvOrCp137
IH8qPJ5zu4MJEwQayO0WklqJ9aYLj02ppdJSkR0TwsPpgs4YrdNb2FDlnmWIQl2klCZStlSYwhMr
M/lUujH72FAXpxLVB29Zv0gDlzobkJ4r2XdErGYlNZz05SOPr2xjuzLNFJlnJnVT2H1eR3Bcx9uW
CJzEVewvLmPmuESYOO9R6j0SFsxY+DKoOeGBHWbAOXynBz5wbI0vH5rhZ/7ps/CG9/9j/MTP/zCI
Z9g+scRqWGB3tYM1D5id0eHOb9+Ot//v78B/+bnX4Nr33QB0c6DrsFj0WK85DFc84AePYfAB4KIs
OCcxyCgayQOFYUu8avAQE7Ool8Y+kLY5k7YZ5Dlk+JEFzp5BaWADArGrBi1lYJMKAiVqWzkwZuI+
a6FayjvZhWZVy4bUHcFybRyDLsOGKpYhHlQPUda/Mt9jSaSVXe06TWThTlkXVyRbkSMNJ+n0xiCV
jXDVjlJ0nGwzqrPAUrX77EaXjasyeIaMcKCktF2I3gk8G4TVviS4kOgxwT4gCDnscaEUpbb+FgDn
HG5aeNy5N+DBF5yB3/gvL8OLf+aJ+L1/9z58+M8+BXI9Dp3WYG+5i67p0B3q8NXrvoyvXvcVPPKZ
j8Kzf+5HcPGjzwP6NVarHtwQOkd5E4UQyl8Imgu78L659LM4Ms40mST8kDTHqDjboRaf5ZJtSmVD
io+fjxPSwxGlLRtLdOK6VzhqYJdPOh2D8bWoi2vKLkkaY5VjxtJDA8QDhUQmry2mZF9Q+uNWTnwq
+xMmRsqUkisnKaXCXNVvpdefW/+epL9w6BOFoYregy6kbhYq36ykpdIJ5KvM0YtMZYjqOi0C2bsH
5ZK54SAs0UY1aSfKwGxDGsvHJRG+dLLHzQRc/OTz8R//59/GR999OV79m+/HZz5xI2YbDTBfY9Uv
0XYNGufw6Q99CjdecyOe/tIn4dk/fTnOPf9srHeXWC09OufyoH4YGM4Jwy9PgYcpACPPGShQ/7Lv
spNDWq5sULX9AIhAaeJMVMz2uPSXs7yXNMGhcpEj6bmTL3c+93n1hVKoICnbA+HaKO0OwOq4sQai
AeJB1MwZ1KgaExZubplOFgUSUqKcpd807chSruxjs6RaM34sFC+2XSrDKfkyfPQsZcVXFIRzfSoJ
eft4AfA82rgYYkk+cBSeYMY6TqN7ACtflGzWCNQeIGzUbCDsT3/uzh7fboHHvvARePWzH4r3vPFT
eO1/+iC+fuM3sXm4gWcPAmF+eAbGGn/+1r/Ap//88/iRV1yOH3rxZThyZBPrnUV45k0E3ThVSU6G
TFllVusPupgtJ+eGJlmJlmGLTLTIARgYnEbcVMjQLKgviofIsmKgEb1mVMpSdQwISTNF1VIXVoz3
XkQ70ot1UwvrIZ5SzUz7crhq2S5xcOf1rSwrEE4QlnWt1tmT4EkVSJWHI+Ws5sVdcVW2yzwzCUGU
32XVj5JDinRQJOWZhinKdAV169ykV9p9RWyBOVBjBh/6doMH1p6wHoDVACwGwrL32BsYiz4A9/Ee
+NR31/jaGnjBLzwRr//Qr+Dv/JMXYnPjEHaOrcAgrPs19volaItw/K5jeOt/eif+zd95Fa5653Vw
3KLrZuhXHr4HuAd4Hf47rAG/YnAfSJO8Dt/7nsF9HKP3QTON1gndIV26wv3l/mIYwpAvlqMss7FI
BCcmreSdrz7FLmEkc1ttsqS/yZBYU7xqzQnmMX0nZuVUz/gsDBDvcaLIcgiBqlckMzppW8kV5JTS
kxR4ihKKxdbC1O/KjRRdSesWEur+ofRFleITQi5L9EyJo9QWB2HXxjNaJjQe4StajToPkE+bEhyU
Z3wadgDsw3pdPzCWQ3D9Ww6MRQ+seo91z1j2jPUQXvMdC49P3bbE9pEt/Oq/fgHe+MFfx0tf+cOg
YQN72wM8D9hd7GLRL9BtOdz09Vvwu//qLfj3v/5GfPFT38DW1ia6psFq2WNYcQDCNQL4rRlYJ2Dk
bFjN6zBk4SH8XhKY5L4AI0V+EuclcS4DlYG1moYAvnDhkMYmQiOJZT+5Tv8nbAR5H4FhrprKpMgM
4SY3wZO1sJL5nqLh2J0NI0sMnmJV5PUsV5mMQ3Yly9oea4W80u0Te80T/uuKjgNthO5zRigFKIoS
SjJ1KgZPwhgq3rkDKYBMVgAUS2JixAlsQmAO7oA+ldI+6DdyuN91zDbXSdMw7jHPCWjg8J3jPY4d
9zj/onvjX77mp/DjP/tkvPrffQBXf/iz8O0Ks40W60WPeTvHfNbh85/6Ir7yua/jKVc8Ei/9qWfi
ggvuh9Vigb736LKiTgBtl3uHZaiCBrmkZh/+Tem1uPAaiEoJrNgEVAQjOJtTMdhLCTcX3jyG6hvW
eohFA9ODRK4yqhIm5snyl8fCIWGf3Vsf0QDx1JuIUN6W9QaJ8lTj4uWhhB3EQKRIQ5HyZFHq25Jg
WycPLJzPxRYLZy3pcjp4aYBep4+Otbk8FSBMjnlDSWwyIM4Y6JjRMQVg5JA1tgy0PtBVwmygZEhB
s7AQugcfeoouPSYDPfnsl9LEyfdNty9xuyM85CkX4Lff8Qv40B99Dq/5zffjhs9+DbNNBrklhuUa
s26GAQu8/90fwyev/jye98LL8eKXPhVn3+sw9raX6L1H17qi+NVQSatdAT5Q9E714clxW0qDNL0m
sfIX1HaoTKk5KdhqCwkg9jVRpuHT+RpnARBWlgJiKJdbJ1z5u/DEHK4AoLcGogHigTQRVRoo/ZlR
+ackaJo63KP720RFlLeNI5+DhBufqsDE37FQ3FFDEebqJCvjVNGJUplE8i9J7njJTzmBXOpppp7i
TJXR8ffCfCL4MMcSM2dY3heeZMWbTFapLaKLIHFeJWQAcxcUwb/+jQUObzj8yE88Ck973sPw9td8
Am951Udw8023YH7YB2I3Ndg8NMPe3i7e/IY/xdV/8Rm87GU/hCue8RhsbsyxWC4AR3nfOY68w0Wk
iVUAhdQ3e7D4OGhxHADRIQxU5GeYy9OQRbIvxtEcaVlSBVt5ppQZitZVl1Nu0aLR8nA06hXn+6sp
PURWMFsP8WAyREaltReZz3marNm3o2ke8X6HokwbxbRQWJyqYSJBqWlzLGXruTOp84a1KMTIZzi5
31H2Tm48hz4hgA6MGQcXvhkHPcTWA60P/sudD+Vz48PtzhNc7DXSALghrNrRwKA+9OV4XQYcYWDB
GHqg74H1itGvGKulx3rlsVowhmX4vcWOx9e/vMDuNuGV/+hpeP2HfwV/8x+8AIfas7A4EXqVe6sl
VkOPjcMtbrrlNvyH33wz/uk//a+49hNfxqH5HLOmxXo5gFcMv/Tw2oAmbKysY79xCP3HYFgTvrjn
aGfI4XcHvSbEYiCTBD+YhYI1l0yRWKuIFUZrGVyRcjGYFnhl6FUUnrIR9DwSz7awDPGe5YgkjOrj
wcoVtSxrJkLsjorlY+IRkUaX1SNZJ1l1yYGHNHQPjXnS6qnKM9pB9ghLdpu3IbKzXSRZM9BFcOwi
JWSgsKHhmEIW6BkzJrRMOVNsPEUw5JgpEtqBQ5nty1fa/sgDBY69xvi6XNRBdD5syaTdZEfRr9kR
tu8asDja46x7H8I//s0fw4t+5jK87t9/BB96z7VYDNuYHwKG5YDWOWxsNvjcl76Kf/Gvb8HTn3Ip
/tpLnomHP+j+WK6XWPc9mpbAjYNrIs/GESj2E8khl8zsKRO10TLStiY5YQSTCNex/A4cxahQE1W0
WailJ15k6U+zsi3VGzAo200sa5Epk4qq/52m097OZQPEA2ojUk2A5nH5msFSXLcTYZuh+0kMne1J
gwxiLVWvOoPaqE+VvwkMUxbhqGxRJIJ5UER18SHz/DlQaoSpfBtLZI6Ahjg4aTiUyTPmnBW2Pgq5
pu99BDYBgi5mSC71GDlwJQfPGQSDl1UQimii9FaSMuzjfnLjOJSlRDh60wonbwUeeN698W/e+BO4
+n2Pw2v/3ftx/TU3guYebg4sVms0LQFNj/dd+Zf4+LWfwYue9VT85Aufjvve63TsLhYYVgOojf1A
RwG8nAC3AaAWxeWKY3+BQ/OTPceyOn7+8Xfy5osj4Z8srE7TRTNxGFM7Zn8K6veaoFR9GGElYAWz
AeLBzVSEGCwJPqEoU9PPMvNMHsix/qEJYKz7lcUnRDwFktQNAdKV5p1sHo39iQJxPA02ZFbhCGg8
ZTB02QlP0CVjWdwglMktE1rPGRBzL3HgnDVSBMqSIYbskIZI2WHOk2mO+4ZJstFHV0Ef+4wU/V3y
NohjdA4Y1oQ7vryH+abD5Zc/GJe98yK8523X4y2/81Hc+JVvYH5oDnLAcrXCbO6wt17gje/8EK68
5vN4xY8+FS94xhNw+NAGdvcWYZ7SOlBDYejSBDSmJpbDjsPtbTwmnJYf4obz8ZIFZ1yxLQhbMPHC
6YpnDhOPuijjoldunVTKmDRB8JcOhEAFxBYGiKc0VBEkBtn2q3+T9QAmr21BNsRLk3Bkdk6ajsNS
skkqsWhngopfVhzd1MZWpHgEz444Solk8GT72cb1O8eEzge+sosbKOw5ErQpTJh96Rt28avxHEzo
47/bWGYHUCQ4H//LHuQJ5BOVhyNfMWRk7AvhPGSR4fkN0W41eKHEaSsxWiIMPeO71+5g60iDl7z8
8fih5z0Cb/3dj+KPX/9xHD2+jflpc/hhD557bM5b3Hr7d/HvX/uH+NMrr8XPvfBZ+KHHPBzkgMVi
CTdrQDMHakJmyFFY0rnwPgQV7phCe4CalBXGAQzivnOaXif7BmlD4GWHV5Bj1HVPH2yjdcA4oGFW
jlb5mM1WA1Ub2sKGKqeAh2VvmVkzXzU5mitmWC30LyaCVZUsndl0CQwhQw/Ftq10SwV0R84ZWJkN
cO7bJeoGZWoHxZ5h2kppmdERMI99xMw7ZM5ZYTMEUJwNwMwz2vjvLv1cfLkhZIdNKp+HMGRxcfBC
fRrAIA9aKIgzBhWJlQcvPfyC4ZeMYenh9zyGPY9h4eHjFzxjeeeAE5/YwWl3dvilf/ps/Pf3/BJe
9IonA8sO650OXXMY657gecDGRoMvfuNb+I3feQP+yW//Pm744k3YaDbQDYRhdwiSPUsGLX30mvag
aHpNq7DVwisfBjDJGHsIijvsWavn+rLZQtIGtbIZUOZlYjhH6YJbD+hypeCESg4XmTdAT6gNES1D
PKgksVxxxXI/i7KFlX2bxNPJckjKy+tVOtq3QQ6qlW6qHRlSrgfIfX1Sfm2QLm0OHGg2CEOQjoBZ
XLnzEbQQBx2hLC5Z4CwBYJw+d4mO4wNXsfHl3+lvE6Unl9FebL0M8fHiFgm8XonLfsxRBDbIGPo4
fYm0FzjsfXMJ9+0lLrjwLPzz334pnvvjl+J1v/XnuO5TfwV0Dk3Xou8XaBuGaxgf+vT1uOZLN+JF
lz8RP/Ocp+J+9783eL1G3w9oOhfArg1erFT01UqjlZ1izDMzqKUyyErmWEnn0mmV6yQsoS6hwqg+
CQZPD1QEf5VJLaTXuo5WMhsgHgAaFtc6ZgGOaZE/TkolkJGQmafRhoqkX7PKGid7SJJHJtDPVyU9
QYNyKqUq7yTUqFo2U9J0mfOQJFuwcCh5WzFISWVyy8gldCqb29HPGM0gQHIoYJkn0TFzTF95n9gX
2ko2haLYb0Qsq6ls3oSGp4PrCYvP76L5qsNlF1+Ex7/2Qrz/XZ/Dm159Fb70tZsw2zoMgke/XmBz
NkPPa7z5wx/BlZ/+PP76s5+OFz/zCdg8soVhsQA7guuicYuPhjKdy1prJKxHgdh3BIPj2UUNBUpO
LqUjE17aTMjhCsTrEaJISluda1DExAqghQHigcOhHNoVoJH7W7rTqFs6TOMtAgjhWSkMOuohRdEG
Yl3+FqpPOJHSEIK5dKacSCyTVSmUj0s4IZNwAzHnEjkNWJIFQqLTuJwBpk2VOFzhMmluOIBfG+8v
fZ9/b0ABRY7/FWW1GxjUezhPYU868hgz/SgCJCeJswiSAatCltjTAGqA1hHcElh9YhvtGQ2e+7RH
42mXXow/evu1+KN3fhy33XUU881DYF7D+yUOb3S4a+c4/uMfvRt/ds1n8LPPfgauePzDgZlDv1yD
2MGxi6KyoRfKMxRdzESCZ+HjkgZuTl5QoWS5mMQaE43tKDQAaufFLB0mSgRSNC5Ux6uFAeI9jOTf
S2INYKR+M2UWBMSsMfX7qEhRsZyOlCFKpkgQqfqXGNo1jUgpzYzMkBgjyVpO4AuxxieayImgnVz1
wpZKyN4S9SQJOaTBScspmwwre+lvZGbYirK54QB2ha4TOYtDySBz5ihI3VlgwXMpVYNzVgBCHy0+
ETZdEly4tEKXBi/f6TF8+wQOn9Xhb/70M/AjP3IJfv/Nf4H3fvB6LHuPzUOnwQ9LgHpszghfuvlb
+I3XvAlP/fjD8fM/dgUe+YgLAN+j3x3guiaNkZXJGEmvbk+h1G5iHzrvU8en5YVgrfDnYVFZ5OyR
iho31ZvuaetGVhNpfZSnejUWBoinjopibCGzuZIKqt6iuI4n0rYCP0CbCIk0VN5PGlTWwg56/Utf
/SU4OpT9B59FHfT5kcrlDhxoN/EcbpM3SgQk52V/MAJaouN4yplj7hNmbuI+vcQEhkO5zWUgDCV6
HrhwyhI52wOwTzQdzkMjH+lNREH9O3w0DkSEJr7R/S1r4PYe5593Ov7Xf/RSPP+5j8Pr3nAlrrn+
q2hnLdysx3q9ByKPpnO46oYv4PqvfRMveOLj8DPPuRz3Pede4PUKA4dWCsR6Y/6AHPJqoBSqBUW+
o0f28mbBtSrfVs1n1tPmTOhO+/XSowfSkKrivloYIJ5qzUwcicxZ97Dey9tvCKKzhpi3lAM+iTmw
NJHiuNJFSsRVXuylNH9d3odeZxA9TYPMRNBm9pkIjJLI5hW9NGl2kVEyi4CYeJd5qOIZrSd0kXCd
954HH8tiitsrLKbNnEGwzT1EiuVyLJkHX4ElwfXh5wEQS58RPlFgClmSvRBr5TgQip+bjxcGRwR2
gFsDwxf3gK8THvuQB+DR//pn8L4PfQG//5aP4cZbbsZscxOuaTCsl5i3DTwv8QdX/gU+9rkv4id/
+HK8+IonYGNrC8NyFbLnwYHnrnwQDcC9D+V+R8X+MGWBTaHQJBBNZXNps0g81DwrEsiXLoA5w5yY
nExJw1kYIN6D7FBOMkj0aSCMN1CMgvI0j5Toa+UsmfthCWTT3jJVjUsp0u0gEkEmJSNPUoOsVE26
qmeq6EEsADFuoKV/x5VAz7FXloYqXECxSbqJ8d+dzBRZTJNFmUyDyCoHUSbH/7qhUHUSNccNFAct
ANLQJe1Hx2QsyXYzouxWnFSHoYsvWbmLxHlHcM7BLYHhkztwZzZ43mWPwlMe+SC89Y8/gbe//2oc
3e0x3zwMPywxDCtsbc5wdPckXvXOD+Aj130JP/2jT8HTH/NwoGEM7RC5hy48oVUc17cRDLP7V+KC
Tnh6qz5IPQgr2X9Wscm+paJaUH9fKSBaimiAeDBTlSjNRaUXVFtUUkWezk1uJWWSJsWCSCgEP1mq
JIsSnKqFFLWwkL7x8pjX7mwkJLzqvDINX/KkOQ5UZhHshji8IFEet3F3OVFlwnAk9hJzT1HTdNq4
tpeGKm7QoOgGRtOHfxPH0rlPHMbwPfVlAk2RrkPZe9VnNz0MsZSOoOgh1cjDIMpRAq8GzjnwLQOG
m7dxxn1m+KUXXIEffcIleP07r8KHrvssBgdsbG5gtV7AUY951+GGm7+Bf/Z7X8cPP+pR+JWfej7O
Ou8I+vUA1whnPaJyFfNxs8VT0jarJnaSWF2cCbR1M2nBD9mWUc712kIlyYmZr4oB4sGkiFymswR9
UNUHrlplEUc9ZcLtaPyXdfVI+KlQNRGslUpST0oblXPR++NUKhcqSiiltTElBBAmMOySdWmiukQV
m8Ad9GWSrAYpAfDcEMppF4Gv80UAoo33kQYn7VD2nZsIfg1TAMKeM3AmcKSB4Xofs8ewBUORr5hW
AinakGY+Y1Ij98WNkBA4i168uUTBP3D42gD+5h4uuuBe+L9+7mX4sac9Fm/606tx/Ve/AZo3QLPC
9t4eupYxm7X40Gc/j1uP7eBf/corcJ/7no5+MYQpNLnwhg5lKJSrAk49P4qqbzyqZUm1r5UtmTC+
T5UItE0BNFHBCxkx9gaI3ytsU+V7p4j5RGLNnUES6mSw9l8hjgb2yP1HprRSp4X0SK126eywAJ18
3DhEiCjJwomcENzu8gBHTsAzc5GUJoATYNhmAdgi+Jq+GvZx/Y7V7a0YprQRGNMmS+t9Hqa0ntAO
FICxDyDYDoy2j7vUPoBhE4HV9Ywmfrneh+/TIKZnuJWHWw1oegatCLRiuFW4vVnHv10z3DJsloSt
EwZWDN7zwJ4H73n4nQF+24O3PbBiuB3C8Lk1/CfWeNK5F+G3fv2v4df/xgtx7pH7YnfHg7nFuifs
7q1xaHOGL9/8bfyb//p2LI4u4NYArxOrnfNEPGey8hobjWiYWYm0KfYANMlGe3WL1g3TKFHMzCpC
5cpnYYB4qrDIEKA3LqmltSdrvFRua7qdwwJsRWIZQZKUzWRlkoFibp8GKFOKJix6isxyuY+U1ijF
bZWkbdhwyvigBiNFGTsCXLptCGt7ZUgiMsjUH+wZbvC5p5gyv0S7SRQc6gHXU8waQ4mcskVah4GI
G6iU1esIfGuGW8e1vzWL/0YwXDF4BWDJ4AiQvPDgPc5f2GXwXhiS0HGH4S97NJ/0eNElj8arfvln
8TeeeQW2sAXuN9C4TezsLTGfMz72pS/gbe/7CziegXsfUuw+TnYi6KX+IXHscYomYU3eHy2BTmzd
KSkwkk3n+pI+AZYWBoinVjhHYOFKP0TaQrKm5kAYmhNzZUfJ6n6UZ7AUok2PUfV+FL0CtXhzKc28
1G4kFPd1cea5tImS2CIcQShxDllMlgUHsY0ezJmCI3uGiU4TgTGUwT6Xwk1fskBKYJlvKzJhoX+Y
gDRkkll4Nv3dmtH0ISuU94HewyUx13UQqKWVD9Z/Sw9eDMCezzvLSKC4YPAuA0sPtwL420B/9RL3
umkLv/Kc5+O//erfw2Mf8AhQfwiOZthd7mLWEf7gyqtxx23fRcsuZIlxt1mvH7J26JOQxbrWrXvH
dQ+QRx9+fZETxwTbUMUA8UAL55FQey6Dc3pH2laUxd5zMg6quTTF5a7wyUYOBLKhFB9LTaVRLCpJ
bTlQ2dLLorWx9CdWQxtXbIvDCp/YTe6Sig1z+fKM1vtCvOay4xykweLwJO4nBxCkUB73PpfMzQC0
EQwDoBW+YuIeujh9Tl+NWPXLfcae0PQUS2VkUKQeGSRp7cPXKpXOIZsM5bQPStgrD44ZJO+FDBJ9
yEiH2wasv7DCQ+53Lv71b7wCF9zr/qBhA947OCLcdMcduPLzXwCaGXgVs8QhgqLcy/ZQrQvaLyvM
wzBShP6pfXepuJ0/TMV3tfTQAPHAOojVdLa2SmGo4Uah59RlDI36hFy7AuU/qa0pSTn7UXVKpBNC
GdRL90sibTwkfJXLpkrIDoseYhFukJzCtGLXMEWqDItNFKAZfOEh9mVanPt/68A5bBPHMGZ5FHuF
IWsMINT0iCo5lFVzVHaYBjC9eKyVz+CH1RC+79NtAfQQ1Wqwjmo1Q+AN8oBic7ACsCJgGf5LzqF1
DdZfXePs0w/hZT/2eAwrwqzZCnoN3OHTN34DWA9BscdzpgPl4Uq6IPoiEpvmJpk1EHuNPjN1vK5U
xgenUNxG5rGq38s+NpYmfq+wKfPdlco84WabWTOuaoVzMRXPkl6UZePlHY0UbSKtghhApZqcOIW+
Bk7hviZ5hyTOu2SJSSkN9EnwwUPKQySjqcJDRO55JS/iAoRy7zgNUeRAJQ5qEq+wF9spQyFYO5H9
5bI56SR6iMwwgCFFgE1/n7ZcUhZIPmSKmZYzFK4ixWyVOVJfMvAksbS48iensU147QQCtXFqHcGd
b2Y87pILcOaRwzixPgoGoW1a3PSdoxj2Vmg6Cv4rHbLfCgYq7n77XXrjrmfuoDiqHBOFbS2H6bjk
ydaHY1XUWKZoGeJBZYmklYqFFZ5ctWOpSiN9MOKNRKQ8k7XwDBeJKMjyt/gnZxMpdYyXHmMt9xQq
qCSC4FUJncC+jSAYDefy2l6eNLO4LSvdUMjgPKGLgNX0jC7yExONpqhpl8wuDV2S8RT1EfhiFtj2
QLMO0+cwuIHabw5AGB7fxQl1oOsIgI19SJeNnULKRUkwIq8BUjRgiu0KHzTPiCOn0QsT+ijPRQNA
RwecvrWJM4+cBh/X8Jh6HNs9gb31MqjbJAkzQCj38H5XXj0Uo8pgTxTLzEKlXdjPVnenCPhJX9Hg
0DLEU+4dBqBiLe8VV62k7aeehXDp/6hVPCkAVsvICsNyKm58peVIEyrZLHT4GFpYh/Lucn4dzEWu
OZ5xaVWviWIOaQ8ZiZgtd5m5kKwprutlIYbU3xuq6XLiGUbgK5mdBMMAbC7e7qTI7AAg9QFT/zAP
YcRWy0ChNE4KOZFQnmkp8b/qtnTxivvHOUFPfThyui8cVbLRO/jeY/BhE5yZseYFBr+MdgGcKwTy
ad4Wr5A+WBHkT51L60VK4QQ+qRd2ZTzeXolPWG5CUeXR7ClsGcESRAPEAymbMU2akUfYyFMv+SaL
wQeN7NS4GErJFT+qS/aJTiZN6Cxy8V1OeSioLPoXEVvZnJd6iNFPJQ5UihahEHJNAOfloKPsKTsh
1lBK3ijS0DNoCOUwpX5fr9Wz8zDEF3WdtJ2SNRPTECaDYABWxJU+DBEM44YHCVDP/TUJkun9H6JY
Ayh7cVG1ykMt4BuAz3K47c6T+O7Ru+Cch+cBg/c44/BhbLYb8IMPdgKcHe4njin9FEbHVz4Y0i56
nS2yvmhLKpWv8M/F4Y4hopXMpwaGckpcu1OwPii57g5KsCzKx+HcrK71yRJUgiHV7IzaMkiU5XKi
XFpRuXwaYiMwe3EIn+eUvDimTK0JIg2cOYdZsktkg61Uq+FSBrtMqxEreT3nPecwOPElY0xg2PsA
lDGzpCEMQ9D7TPZ2YmATwNJnrqKLgJjtTj1AQxBzLVkhi6lr2ioqn13YaCE4Cgo55AjUUtxLDt4p
/iwGXQJ8+JobsL04iQF76HmNfiA85P7ng5o2+D2DqqXycd9Y2qboPh+pDvV4FqLtZmWVwJ4VEdal
1cHpO7KwDPEHayASCxEGpe4pqtYEWELDLlNdUmY2YWGaM0eaaICzNq5PisrZhYP1lFr72kfdPC5a
ehDletZ1TFlUzAxnAHqmUCrHUtZHGS7ni+l8O1AujcsXCbHX+L2k13g5HeZMy3Ge4kpe6gFG6S+x
t+w8ZYJ2KqlJaCYmMVkkIJQlsgDAJP+fcunSmnBhs4hcWOOLQyhqHTAHuAV869Hcx8E93uHqv/wr
vO+qL2Bzq8XR1Un0WALk8dQHPSRwGttyUUt+KDkvp4l0sTxD8StciYtUTUIJmII5gIlucuVlb2GA
eKojFcqgV4zqhWwrlQV8Ke1VfJK1XmEiYhfh2CpBEP7OikcWV/A4L+sX7+ViZl8pJecqnoP/CBVL
hFwRRoOpJm2bMDDk3lwcBkTFmVZyAvNX2nXWkl5JsKH1JWuktGGS+pIJGCPIOgmEOYPkDH6UympR
smehhwGZIJ85nkI4g7IDPeAoqUWGPWZCA7j41VCQ7WoB7gCcw2ge2GJ7tcQ73nY9/uBDn8CyX2DF
e/C8ws5qG4849wG4/MKHgdcruA0Xze5JSXklseDxZGx6GDzSYxBqR6MujmAwsHQHl/vQhogGiAeD
idVQhStVExQtQ66OcmkWlEBQ8xFFBphOYLUrHfiFJXPI6KsAkErlHaluXMpu1qW+xFjHQBt5hy6K
NjgfylT2sdyMgNj0ggLjS4bWcil120S96aX6taTaFGK1G7gAW1TRcYOP/UoBln3xd079SCdUvCn3
CEls+CDz/coOb+wQuSZCR3CkJzRA04CaCIZNJK9vDGge2QEPBD7+mZvwxvd9DJ+55UvoOo8172G7
vzP3in/lh1+IjcOb6Ns1mjaa3stGrRPLTJADFO2imMtgmupYT/WsoQ3LqrKY1bFriGiAeAAjlcrk
eKJ3iFrYvZRAOdMjJcGldl9YZI/VsCUVxh5Fr9tzKcmlepQTExofV2mT6EM689K0m4SKiovGUlnE
NUpo+SjGCqFPWOS7OEv/p8ywzdNiLhQZL1VrKINo2TIR//bBFzpzEocCtEFBO2aZXmSGXChJ0sku
DbFYrlUmW4FkmhBVbkANqGuALkhjDHNGe24D3M/hyydvxx+99npc/eWvY+GPo52tcWJ1B5b+BFrX
4OhiD7/6zBfiWY+6DINfoOm68D47aOZ7JffFVG+fs5B343zRHQnGovioqF7oqOWC0jdmTPcxLQwQ
T6V0ZuWJTGN9QZI0Gy5G4kSxj8ST/aOQ9JEGVi73QTI75NrbNBkc1UooJUN00tRc7IURIKg2ckc5
/MrAwWeYokE7CWEGEqTspIuYy96+gGEGsWgNIAEzZZE5Y4wTbMorf0nYIRKu+4D0bog9w2rvm5Ih
l9jEIScRKQKiSz3DBnAt0DVA6+DngLuPQ3tRg6OrXfzBVZ/Cn3z6Gpxc7aDrgL3hOHb6u+CxwGJY
YLX0+OWnPx+/9qwXYfArUNeAHcUJdaTpBClzPdYfLR2XoRiFD6w8f5rO9ooZY6HljDGvBkPLEA0Q
DwQPOe+JJvezxDFUWglcySCrBJEFNYZG02Bt1Vd6TtmThcsa19TaXhm0iE2VzODQ5TJzyV6byENM
PibNwOiGKLDah1U29Az0lGkueaASe3mJhpP6h2UAI3mCukymPGVOQ5SS9TURfHMGKfqElOS0UlXp
BRG+3mwjApErZCRysSRuQFTKZG4c/BGguaSDP4vxZ9fcgP/xkY/ja3fdjMatMNAeTi6Ow2OFHgN2
Vis88Mi98GuXvwgvefxT4DGAZg3QhpIbTTyzEqdJHg5ufFzlARdpO1me6h1OJnosBkdV+Z1aPt5O
YwPEgyiZVTkLoUmI0SodCYVs2dTXJlQYOe9xJToL2SkSgOkoCptO2O+m+/DRdlQmJogTaeax7Ekx
iuJMkA4eKCFF9AODY98u9/XS7rB0yGNdDktVmkYMYZwgZOfsMk2Kc9bpYyZZ7APIp5aAUHDJU9mk
W1mtwBHFCXICQxeyw64JAAaHoSO05zfAeQ7X3fJNvPWPr8V1X/sGeuzAuQVOru/Eym+DqcdOv8ZZ
G2fg559wBf7mo5+Js88+Cz2WcLM2U3OoRQRFys+DHeeeYsoAy66lLntZ9Ivj2rMiNmSnvX0q4Dz8
k71ISwwNEA+uVFbGFyVbFFPe5InBYreURgYZVFErKuFPvbQqSvDUf5TcR5nxFXqPtKosWWLybRE+
A8nTGWXK7JhyCdz0AQQxEPpEeo6mT22W9+dCyk5ZYez/YRBgKYBTZpcuKmsni4C0CZP2l/OWykBR
FbtQWCjt8aaMm6KXSSJcu0ibSeWxiyrWrQPNXMgIZ4TmvAbt/VrceucJvOlPPo73fuZa7PV7mHXA
bn8Ce+tjIFpjp9+DxxrPOf8x+LUnvAiPeMCFAK2xdks0Wx2w4YAOoBkBrQM38TlUJTORAENRHtQX
vmQ4lT9pFpmktKxnrnqKYkCnLurWOzRAPCBAHClyZcGGfOzFg9LlpftsOUDCnzn1+1ieBMKqNIGY
0kSUZTQLFWVUI5ssT5ArsvKcSZ9sIjNNPUTyWlKrja52nMyb+tC/K0KvMavLQw4qoBizuiaLKlCZ
LsdtldRPLJqI4jlEbUbqffhdoSXoEAUS2InpvYu+xJR83gOgpGywcUDbgLpQLnNHwH0cmofPsGp7
vOtDn8ZbPvwx3HL8Vsw6D++2cXR5Aowea/TYWw147P0uxN9/1LPwnPMuBTaAFe+i2Zqh2WpBGw14
TqCNeN8NgDb0EbmJWWMTqVqOsjcPhAJR/saxuF14NQvldfV5sq44iEpLJ3s5s21fGCAeJCTSVAXt
1JYIKxFXnRlqs3hXfFPiz0etHdYresy6qS6thVikFj7vxIaeoxPVko+qzcp+KtNuuGRq0SJASmsh
Z2kebS+EE9LqXSp5B8qKME3MNhXVJlNlNPWG5GaJZzVgSeIKxBSmwd5nn2WO8j/kXB5GUFP4fxQB
EfMGNHfg1sFvMdoLW+C8Fp/83Dfxpnd+HJ/+xtfgmz24dg8n1icw+D30vMKJ1S7O3Tob/+Sy5+CV
j3k65u0c634BzB3ajRmw2QCbDtgk0IYDz6LLnvzKMkKByjMaqEBwRxVvClpImIoIUhmsjK1oSyum
7jHbTMUA8YBaiArfsnduXdpWAgxJx44ddBqAPFGuV/VzjzJmlB5caSSGe/fxqs+6gSiGlWOTqmJo
L4YNqZEfxVidTwRrRi80CZNxE3oq/L8MhC54rAiHvAxwoyly6S+G7DKoYCdSeD2IcVmJJlWXofzN
FJoGRcWlibYLGXxC2UpzAuYEv0Fo7tfAXdDiptuP4o3/7eP48HWfwcLvoml77K2PYum3weix3S/R
OcJfu/ip+IePfB4ecO454HaNdbtGc2gWgK4L94uN+DV3wCzengjdLYDOlV1oJwCPqmydSJOxIW1t
x1Vv2XqZXj9Rw73EfLBNFQPEg+ggTmV7STGbBO+PKnZtoHXI7LCUM/LaTkwZUXUlJJz+oG1EWTbj
MxeIq+fLBVgJSoVUTamjsAH5UvI2A8H3oVTmHkFNOivMROmvNGkeqCJcixU9XziDjSidFRUHiLJc
wjHPS39pytPXbMiFSCVyUYGhQViza1wAoVnYQfYtQPdr0Dx0jhM7C7zj3dfi3Vd+GrccuxXULbDi
XewtTwDosRiW2BsWeNo5D8evXfZjeNL9Hw6wx4pWaDZatBtN2G3sAO5cAMENB8xcKJXjF88INEP4
t0MRmoyUG5aiERVfXLR4pwfJLFZHSV6Nq8xQyNMpzz7bZTZAPLUEUXifkCY0QxKrSewoM8SqmPQT
H4OhfiTCiG+LiawAeiAjxR/SAAV520VSfAQPT/Y+k+H8kMQXAuG6H3yY8K5DGYy1L17JTIVkLcpe
15eJcSqPU3+QBrmeJ0ptkJpEZyvR9NwEGAbsEFlWE4YYQdW2Ac0CUHED8CFC85A5cBbwoau+jDe+
46P46m23oGl7cHcCJ9fHMPgFBh6w3a/w4DPPwS9d+my8/MLL0Gx2WLdLuI0W7WwGzALIcgfQhgvD
kxmBZw6cssNZ2HtGR+A2ru1FqmMqm3Mfw4mhmfTurhZtUGPelGueYCyQLJsjeIb/cJHXsTBAPOUG
Ipdmt+a/sj4o0zQ5Sd+hgJKSPh7t3CGv7mGyf8gKnpOIComd5yQ+S6I8ZtEr9OA44NSlGMmStpcK
NQD3FAyTVgzqSfUBM7VG7SPHn0UdwLRxkgco0a0vyXo1adI8iJIbFDzkxcodJTUgp0tjbhCGJTMK
YNg5DJuE9vwOOK/BF79+G37/1R/FVdd/Ab5ZoukGnFwfxdKfBDDgZL/AoXYDv/TIZ+EXH/ejOPv0
M7H2Cwxtj3arCwOTWZggcxtBcO5AXQDDAJQI2WIbs8IOhYuops3FwyZNnovuImeaECURDynIkw84
segu95en6Fsimy7TeDulDRBPsYeYzOXLemkBNWm6p7fytbl4kRGL98chM5BsCc4m94JkC7lTMi2U
onjdUutQrkzHTZnSiyprYYk/mHUH065wVK7mNcAxS6SByv5x9FdOggvZuU+s1TnvlCJNXruDsDpN
vUMueoW5rZblymKG2LiQcbUAzRAoNDFbG2aE5j4N2otnuPPObfzh6z+Nd3/kU7hz7w608zXWwzZO
rE4AvMJuvwvA4fkXPg6//Ojn4pJ7Xwh2PVZuifZQl4GN55QBj1sCdRH0Zq70EWdUftbGwU5bpsuh
fxivYA6Zr8ryg8rHguAjTgGYotlM+EdRReoWK3xWMRsgHtxgRbS4a4n+UoWS1vZU6V/J4jJJRmVq
lQWASDwn+0nQFJwErF7LK0YydgRE56LYQTgzXAJtoWPosmVnyBCxBnwfvuoVvCD8GsnUicPIhUtI
TEXJWqzj5V4lCxDkUAqTeC85ZYMyK2wJFEtXbBKwSWF4cnqD9qFz9K3Hn77nM/iDd3wC37rzDjSz
FajbxvHVXYFG49fYXu3gMfe+EL/8hBfhuRdcCjSMJVZoNhq0G23I9ubhsbiNg5lZUr8JQMgZGCn3
K0PZThkMs+puE+EtZrij3ebiDKUUjmhKEk41WPB9iDYo42aTuzFAPKDRChU6SwavZAxVZWdcH6hM
4wM5Zgg5KfSsybX1yrIYNxcxBxrd/+gcokLJIXEKeRZknwxukU+YRB0iCA5xSILELxxcNnWiVDbH
bC9wBEtJHIAxDl5ENuikojULNkr8huI+cKKrUBM4hIhAmDh//jRC+9A5cF+HT330W3jzm/8S197w
ZaDr4WcrnFjfibXfBmPA9rrH/baO4Nce93y88tFX4NChQ1iu90Azh25jVjK/DQFy6StRarpYLncI
QhBdGLIgbqdQF1JfbuPfuzI8oaaQs5ni1kpZZ9L0K9lLlqVyMhYbd5Cr2wXrgSRJx2pmA8RTHasI
iSYAI2+V0hOU1gHCeF7Iv1OleJL8m7XEP3K/p5hZxS2Uil+mlKRyacyilxmVspUyd/jy7LObnnSy
G4aodtNz2WeO/sIUjZ1oGA9OHFMug2lI9qXFujQ74ImvhihxqgEiuCb6kUQAcZ3LwETz2K9rEWg0
D+zgHtLhlm8fx1v/zSfxwY98Bif6o2g2euyuT2C5PgnvVthe72Cz2cBPP+zp+MVHPRsX3Pd+WDdL
LJslmo0u9CDn8f47B54hqmQjDmyoUG1mJUtEBD90KXuNZ1MbAB2iVwjHAeCp9I/J0d20rklZ25Kw
gkjreMo/Rf43bz1VSSFZgmiAeADJYa2FyMnPJClkSwMqKg3sKZ9wViUtFW9egl7vY10rjftJlMvh
sK5Hqo/EYHgv7AHIgQiRwxiMpjjW10WAAUD0R0YkYNMacGtEv2KxYuddKbOZis9Kotl4ziZPcgOF
8iphEjooK3ZEXEpPF0pUmjcBcDYAbMQhxFkOzSPm2OnXeMcbPoF3vP1afOf4UbQbPQZ3EieWxwD0
WPoV9lZLPPW8S/BrT3wRnnzuQ+AxYK9boN1s0abtlUiR4XmcHsfnwLNCm+GulMwcM0JukSfc3JQd
Zm5idkuRYuN0ecxavihz/PerduWwhCXtBmI3mkpvJU2j07ofExvrxgDxAPuHE20aQcbJFgNqLEiB
AZgO0izlRSRM6Am1Xp3YTFbmU2XAo/36JDxGuVNRMpXtFJfzxCILkx43GzP1hRaTQBIDwQ8ceogD
RQ8Tyhsl2TpA9QcLSOb/ZpAswxLXxOfdOJAjOGJQi5AVzlwoPzcJFPuE/jChfdgMOMPhyvffiDe9
4Src8FffQLPBGOZ7OLE8hp53MXCPnfUaDzzj3vi7j3sufuKRT8WsbbDXL+E2HbrNWeAqtpTpNEGU
IYBi6B3GNy1lp00hXAcw5JI9JrmgNlJoxJpQyRSTYGzZY2aOPPNsCJacESFWQ6U6kqTTxAs1k3YZ
SNjHPCqmo/SHndMGiKeYIvIYfFime9Bah0WbsOgaFotQaUPKImusVI4r4Qgi1UEspZJcHQTyFku5
HyqUFWCklUcQYBizvCEq2WCNLAxLPYUMMQo8UOwNOk/BvjTtQXNRsA6CEcgT5PTeOAq0Gko0mjYI
WFPjQK0DzR3cJgUvk44wbBHaBzZwD+jwlS99F2/6v/8Sf3H157Ckk3Aba5zsT2Dtd8HocWK1gyPz
w/i7T3gefu7SH8G5Z52JPVphz/VhejyLmyVpr3lWhjWJXE1d5DE2nMt1rkpibsUqXkNlWOIAivvI
RdhBZoasZBkVuTp9vlRb8ZFS0JYdF96nBs5LADkzZOHnbGGAeEop4n7TvXqWTPVRGTmBPvv7snTY
ZVmSV48kvZ0rTyshowxJSJMMIKmFmM5Dlm7O4gSjKM6QZbaStWek4PieioVoVqtOGorx5UU+YR6m
eCHqkrjIsV9IkaMX5AhjdtY5uBnBzeNQY8PBzxh0vwbtIzocP7bAH/6Xa/HOd3wSd+3egWajx7o/
id3lMQArLIY1mIFnXfQ4/PLTXoLHnnMRFv0K290S3byNVBgG4s5xHph0kScYByZl5S6AHKdBThvL
+DZyHxPPUFiUphecymSKsl+c6ENV6VzGIhXZn+VKHk+0cEpDsLbHlQM9muj+WMVsgHgAOaK0DNBX
7FSqstrJZyFhLyS6sl8Kjw5TrgeAmkSmnoP0U3Hxdqd+mwuXD0UbUY6B5HCoiC/EnmFc0eMhqmUn
o6moPuOit3IiX2dtwoGjex/BSWUeAhwxHBycc2g6oOkA18TssAtUGtoM2Ru3BD6L0Fw6B28AH3zn
jXjjq6/El7/1TXSbA3y3i+3FcQxYoscSO8sFHn6fC/B3L3shnvfQx6PddDjOe2gPNWjnkVPowhYJ
zWI53LhCkUngNkMZoLSx/9cWxRo00RYgDn4QfVNSdpg+bsp6ahEExfGRWyakxbyUUAgwcuLLXRXm
iQs1KxsJ2XMslQRZA9EA8aB6iBJmkEsRVgOTmDvWOnSiHMqHLmuAVeTaNKhhVnalyhW6ctXL5kJ1
+iGAT+qJkiiliZHluIohfPjKya2nYLw+UCFkZ0GI0Ld0PoIyFyxoEDLC1hEaYjhHIMdoOkIzd3At
geYAbUSuX0Pwm0B7UQc8qMENn74Nb/ovH8dffvwGrNoTcBtLnFgdR489AB7bqz2ctXUGfvHJL8FP
PeYKnLl5CHu8h75r0HVdGIJk0jQBswbccaDxZK/lCFotwk6yK71DbqrsL4Igu3gfTfFN4UZ81JEu
lH6W+4MOpXUy8mjWlykWmydpMYBi74SV4ZgqSEr/cVThTP+NhQHiD95DlKaOJI1J685iLIbJRQwV
5bHYwcpWlNIhzcXhjFzIF37Mmt4dBygVi7tYB4jCiZOUICtpqCwmm0pesYaXFGjSzzhKeyXhhUYM
SJq0ncJURF1cnDMQ0DYOTQO4xqFpCdQwXAc0G03YNNkMgxOeAXRui/aiFnfcuo23/otr8N4/vR4n
lsfRbK6x6k9gd3UcjDV2VrtomwYveMTl+NtPeiEedu552OMldt0Ks/ks24dSHJBQGwUfOpSMMO0b
NykDLFkgHAeAk/vHGRSTtBjlbJCThmFOhyNwyVIZab5GefspK2GDVDsDzFVCR3o/WeGomCDvt+bM
yXbWMkQDxAPqIZKadohsj2q3vdKvyyKfXOvLsJZ2QsUPm5g68wQEJ6VtYoCgy2KMCyrd0BM5pxuC
O5/zLPxO0jAllMucNAm5TJLbWBo3IjNsKGSDjSM0TfhyLdDMHFzn0HQMNyfQJkDzMNTg+xCax3YY
GHjvW27AW173MXz95m+h2eyx7nZwYhm8TFZ+gdV6wKPPvwR/6/IX4GkXXAJuehzDLuYbDWazNpff
KfsjAYB5QuxijzBL/YvbY68QrQt9wAZlMtwUQGSpwkuCgO2ogJ/Yn2TyahDGlep5aG0kEQbBPkjh
SKwhCRCl8XZT3TDU5mIWBogHlinWZUhtJsXKFD31DbnaNc3ahBRKSFXmUGUitI9jGgkkpQqoSfAm
iarMMovIFjUex0m/MABh4iJS2keOhlPS1yRnhYLW0xACEDpC2xCaltC0jGbm0ERJLLfRwG0BmAPD
JqN9UAc8kPC5q2/F7/+nq3Htp7+IYbYHbO3hxOoY1ryHgVfYXS5w/zPPwV9/8o/hxY99BrbmLfb8
HtqZw6zr4NJaXSROUwc9AEnyXCl1TX3BKBCRV+1cGZaw2kOGEHhFnh5TtDUlFwj8iRFAlQ9O+llt
G5pvY87806SorQ3LGMpBAmPrAKKJFiML4DVBRAPEg8sRRbkpdpCpViCReVytepwKa5k5sBSGFQd+
5atH+aQg2RIqlAoFilX2mcq5nBemfJMKcTsaPAWbgGgfkEvm6M2c+YQRROM+dHA25oAzDaFpgKZ1
6GZAM2vgZoDbiOVxB/g5wV3g0D60wXdv3sFbf/0avOfdn8Tx9Z1o5mvsDSex6LdB5LG3XmKj6/AT
T34efvopL8J5Z56Nhd/FbrvEbN7BtQTXEVytVC0mxUhbJ6kMbuKedFd6hCmTZGEqT4kgnvoAaQDs
OFOZUl+QiaSyWj44KJKz86YRpAUAKzCTAMmFULjv9ZkqgeLRHHmCZmNVswHiqeWFlCVWkWW9anAS
gxIp717KGUnKkXpO49U7JgGu2pG0kHNYFrykeo6OizSY1AxNmypSTCKXzKlcjj3BwFlLoMggT3lq
LrdMAp8wlsgUssI2UmnajtDOCc2mC0B4COCOgTMdmke1WJPHe9/wOfzh6z+Jb916K7CxC48dnFwd
A9BjNSyx7ns86cGPxd+84qW49PyL0fsVdmgXs0MNmjiddmmDpKHcO0T0NeEIfi5liJIi00Y5r0aU
wFGCh9L2jCs+KAnsSFgAUBOBy5WsXnmekFA2J91Tye8i83QRIn10RjUwqV5yoXGN74tZXx5tqGKA
eGrZ4UiUk0R1KgxRqGSI4nAHxAyY6xYhaxEIrhhkZUACNSQR+qJANVsOP+NRVkgkp9HIwqHFQiBq
FnofM8bQJwQLw/T4dy6CYQOgaYCucWgcoWsITQs0nUMzJzRzwG0BvEnwhz3aR3bABYTr33sr3vBb
V+G6z38JPFvBbyywszqKHkt4XmFnsYMH3Ps8/NQzXoxnXfoUzDuHXd5FN2vQdQ2aGQXOYkdwbZAD
oxZh1S/1DVsuPiZpquy4bJakLRTHGQxzJtikvl36b7QQhZgYN9VEn0TWRhOcP7mvjrrhhxGXtXBF
pSp6XUVUTRQSUksKR8svW4JogHiKGeL48NVKhbFzyDwqVjVZR4w44snBVJrdUwOTlKEyV3aTFMpZ
oV0TpLMEdBLrQZDPBva655TEHVjsGzdZTCLwB+FIiRI0ERTbBmhbQutcyAg7REoNwW2EI8vPgOYc
gnvEDLfduY23/cp1eP+7PoMT/R3gjT3srI9itd4BY8BiucDW/BBe8bQX4yWXPw/n3PtMLIddrBpg
3rVoWgcXByFuo4CfaxFLZmQeoWtcLnsLiToORVpXpsdJmLEprzGVuUxiD5kKGyCBY07yxOcybnYU
RfWsnM56OCL1C8dk6rSzrO9b8VZT/5FqIJzqPlsYIB5UDzF7JOvmOFUZJSnfErFCBZq0xGC1gqX3
s4oYBEWZLIYXKUjecuACvDXnUGebkrBLERBDedwQ4ClMjZkJbXL8hAuNfgc4dnBJ/zRlhDOgnQHt
3KHZCtxCdh44k9A8uMOy7/Gu13wGb/8fn8Itd3wHbmuJNY5je3knGD1W/Qr90ONxD3k0fvKKl+KS
Cy5G75fY5V3MNxt0sRdIcd/YzVwukV2aFjuRIYqyGA2KDmFcpeMmZs9tEm0ltWqX/WoalB4Ex15g
3SvMK5ETq5cIrVfZCVYqSDyR5YnLqGzLUO5Bigul2EnPVCt1kRXPhTGZmVoYIP7gWaK4wivZEEoC
DPv1gbQpFAlxh3KwioOYaN9ZtrwfZi5iqnHfmSoATOVbE7dEQnXvMTLEinSZ5O3exJubNEVNq3Ug
OB/2YpyLYNgA7Sz2CjcQsrY5wKcDzcM64L6ET3/4Vrz2P1+FT33ui3DzNfxsDzt7xzBgFcrjvW08
8JwL8LIfeSme8sjL0DYeu7yDza0WXdehbUoG6JrSM3SJXxhBzwmSNUlhVinImvqCkiJDRXdRmcfL
fqEj1RbJy5ouXticrmQZasY2OhaUWk01VKmLaGbdFpE+zHkYN36ECJJBXCQJe4ACa8DCAPGU0FBv
iAiKA4rEUna9S9mE7PwRj/RpWElrUzC5Z61wkjlr9c0oGy91eeaqgQoQuIFBk3Eoqt+CAJ4l+4jQ
kAvZXcNwLcGnxyAK5bQLINu0QDMntLNQHrtZIFe78wh4pMNt39nGH/6z6/GB93wex5bfhdvcwfb6
KFarHYA8lqs1Dm8exnOf/Vz86FOfg3udcTp6vwC3wEbXoW0d2tbBNVH4IWaDrokqObNA8iYntk4c
okBrGYqQoslwzA7L9JcUEMa+Y27UkhLWKCTrmm5VwG+0glm1DElcWJOARzGaL9zDkesyje3JuGrH
ZMoX1asDNO4BWRgg3tN6Oa9EiYNai65OCluLurWcKRRPgtLRkyonCfx8PosdAQMLl96cFepzjkhu
JTAcUzatYgbaCLoBnAvYggLgIE6Lg5NdyLg8RatVotCLS/Q9R6FXuEmgLQ7eI6cDzcMbLLjHO151
Pd7+lmtw+13H0GyssXZ3YXt1FAMvsVztgD1w2WOfgpf+6I/jQec9EOv1Hla0wMZWKI/bJmy4uFSS
iz6hi99Tk5RyXPYtSdxDRZKmpD4TU1vpj4zgd5DLz5gZ5qmy5AXQGFek8VO+0ND0QSR7wRkUvXhs
UQZTZdBMk1smSVHJV57OpPuT0OZnphBrgHjKUxXloUy6c60yPUxkBoLzlxqGpTUUjaa4bDUEDUNS
JlGKjytPlCo3KHqjlDPFcN6FB2hcg74fcpeRclkctA4QTZzQBXJw4yINqAnyZiGDjDzDjcDj84eB
9pEtcB5wzZ99C6/9rT/HZ7/wNTRbPXi+wvHVMfRYYvBrLPcWOPf8C/H8H30xnvSYyzBvgZXfwWyr
Rdc0aBsEQOwoiEA4juRuEpkiYp8wWQugqM60lPeKXdprjJsmebjCiAo0QrHalasaU/pbgSHCHpQY
E9NaMXARJXXuFzrNnskEeRKrd8KmtioQRsMXfYDR2HOlxkEu5mXGQzRAPMXwgkg7bhRqe1ENgaj7
PqhQjbSwp3bZ45GT32i/gagYNQnHFAKjAavJsyyQFcUjKT3HfiPiWptzIVMih+Avgsg7jODpHaM5
18Fd2uC2W0/ibf/403j/u6/Hyf4utKetsL26C6t+G6ABy90VTjtyJp77whfjiiuejSObh7Be7MK3
DpvdDLM2PHbbhuzQNYHT6LoiF0aplyiGJdTEK0lbeoVJeoujDQELgnVYpxMrcUmNIg0jqHjQpH3v
kfkXkgJ17apYgCd9nzM7pvEQTZbRIzk4qPKZpRIOc8WBrWr3aqScdRGZp1rcFgaI92ikonuKsrE+
eZhV4Eha1CGZ1he6TUFMpurvhTNpojqWCkmIPMihSjJ6QtlSI/Zg35d1PdehcW0xe3ch82pm8flG
JRdq44S7Lb1JPkxoL2ywbAa889XX4n++6Vrc+t070W726NuTOLG8Ax57WC/24Nnj0ic9Fc//8Z/A
hRecD7/YQ+/3MD/cYkZx37mlSN8JQNw4hP3nOEghlwRkA4C7NuoNxn4iXHrOcZrvigI15f1jCAEG
CEP4CGCu/Cy7FBKUrJuycM3gCCXdlbfY1aERbx/LZRbPnDgJlxPizE6giT8U2Kd2nlmIDlNpQJfs
1lJEA8SDwkRVqpIyvtPinJE3xrUenS6ha/7sNHOWUKnJizaQzlRDe0z0Iin0DmcgzOcdvPOBtEMO
reuwXjG85wiGCHqADnArCp4qMyGNRSErbO/fAvcDrr/yZrzmP38E133uy2g3GX5jibtWR9HzAsPQ
Y7m7wP0uPB/P+cmfxKOf+CQ0fY/FYgebsxZz59A5QgcKKvydi1suBCIP5+IUOWZ3rkl8wlDOUgst
NBv5hOSovE/khNMdi6lxzBorFzvp5Upi3TJliQyZTUr1GdXSq4Q+eIx+Y+zalxGTs7v92tskupwp
m5RT5JgZsulkGyAe4ExFSXnlPowoZ+RMT0nAp3FJ1QtiuV4HKd9E6iwZ0Sq4UIAC77BQN1yEWCeG
LC55HfcDts46jI2ztrB3yx4wIzSzBrd98y6cuGsXp29tgXcZtAXQKk5eB8T1N4YnoDnDob2wwW1/
tY23/MYn8P4/ux47wza603psr45i0Z8E84B+d4lDZ5yFH/7JH8eTn/9sHDl0GLy3g651mM06dBQ2
WmYNoSNC46I1Scz2nAvDFIr6ialMTpli/kp8QypSXPIrCpRHSg3yWl1u5VbWnrUFbAIaL2kuAgwV
KMqpmwQ+ucs+NWxLFhE0brFomhZGpTuRNr3Ngh0iw03cVGkfwDZlNkA8xZmK8IoSk2KRoMktEmU+
j2pqyHUmGDPFeP9q6kgjplplUFXOO4c0iU58Yhd7iOEE8esem2du4d4PuwDf+uZRePZw3RI33fQd
XPXeG/HCn30M+mNDoOc0MYPiQNLGFtA+oMW693jX730Gb3vtx3Dzd25DszWgxy52FseCNNfeNrz3
uOTpz8CzXvlyPODBD8Cwuwvf72Jzs8W8IXRMQYGriTxGB3RpF9qFNUDXUhwCuyCi0MpMMJXPyaYU
gl/I2t/LpY0TwfMjmvJtFXJtpQeYS+VUwiZvGojPXBktVvqWrEtZVlwotbsJPabTn3/aZyYhGJs/
eyrTa5VRquc5Wh2wk9oA8RRTxHHrWjmdkbAEheAHKhkw4Z4m952BKVM/qrLCICaKCLiZNyil41HM
rVqErK4XgilbM8LDfvSx+OaffhYDr7DTfxcbs7Pw+v/457j0aQ/AA594FvhrA/zxCCozQnO/Bjgb
+MyHb8Pr/8PVuO66LwGzPWBrgePLu9BjD+w91rsr3PuiC/C0n3k5HvG0J2HOA1Y729jsGrRdi5mj
aG4XhycU+oVdHNCEPmfKACPoxUwwlctpoFNk+SNICREGSkMSKtzPZHpfGzeRmCpn72yQEhoq/V+e
5haKfxQzMAlckpBK+/ZjFFE/Z6yp/K2IjRNbThBTbVJK21AaETZWuUdTAwsZw9oXKjQlnxRByagA
kituofJgqRrisvOo/kXCm5k5kWQwRGAMrqGMgYEehN4zBgBLMHo4rBlYsceCgT0G9gbG0jmcPLGL
33vOv8SJb90MPxtw+uy+mPX3xgUXno9f/D9+CI9/xvmYdU2gsSyBb37tGN7x3z+DP3v7Z7G9PIZm
tsROfwwLfwLs11hsn8T8yBE88eUvxpNe/nwcObIFv7ODuSPMmwbBUpnQETB3wDxqJTYIZXJLIStM
ZG+K5HByjCbyHl1TVuWci0TsOHxJtBmKElxQgFiyQpkxkSBDg1hkgvucCVNeJAJUdUam74RHG0xS
yUjbUchjhGjieqw4sNL6W1DAJjLJbDAWl5SYgfZQY+e8AeI9B8QRP6y6Wk9cx3W7iPQBylVWMepZ
QpdywQIgHPo+gmIfAdEzoY//XiFkhav4tQRjycDSAzvrAcOROT7ymg/hPb/4m9g66wgcZjh7fgGa
4RBaanDhw87GAx9yX2wd2sB3vnkcX7j+G7jz6HE0Wx6r4SR218fAbo1hsYbvPR70zCfgKT/3Cpz7
4AvhFnuY+SFkhRSywVkT/pu0WWdNzAqJoulU6SHmDTtXPJtd7P0py9KUOTrRTHMsSuXC4SzDkupA
J7kzjLGJIfRQhScBcex3NxbxmEzuRGlfe/DoHmPOYr0GVkLVV3Q0MrVXA5m0sWmAaIB4qtH3A1Pm
LNA0BWy/apsmskbmsgMrrur5AHdTzfd4TDPBc8wOIzAOHOYfAwgrACtmrBlYMrAGY8WMJRN2PXBi
8NiZt/iTv/87+OLrP4jTzj4bDGCzPYyONrBeMTB0aHgOND24W4Bpjb31NtZYwPcLrLcXuM9DLsYT
/9bLccmznozOM3hvL2SEjjB30fs9lslhmhzFIOK/26b0Phsgg19DlBdKUn+slM+UAQ/E4T9OCK2S
yBhpQoKLeERRUdq9IsubZKbUmyATP+fK9Ev+vvKzKXst04R+NZej7LEiMDDe5uKqXvlDnkgtiSmo
TMThigGiAeI9B8T1IDa0ZDNcT/ZUqYR6c4oneoQ8SjHL9gpy5pBKPB83WDgOUAYK2eLAwMCEAQEA
1wysmbFmwoqAJTMWHthlYK9nLCmU2e/6X16Hz7/ug+gOR9l9Bhrq0LlNELXwvMZy2IXHAAyMfmeJ
9rRNXPqK5+Lxf/1FOP3sI6CdXczJhVIYoSzuHCIoElriUDI7Sr7waKkMUbK3e+T85UwQWWUr8A5z
aUzRc6RkjBmoREYlBwxSB23E2RtVx+OfaSATpTVP/A1VBl/ycxflQs5GPX9/ZyNjupGNyqSKMSqZ
87HlSwumPdTaOW+AeE8zRM85y1N1FSngY55ge9ViDHenTCd/7EhJeyXZJ45mValsHhI4MmLZHErm
NRg9h4xxEQFxyQi9xd5j5RzWsxZX/c578fHffht2b7sdTTeH6zq4tgnzVu8xrJcYlgvMto7gQVc8
BY//hZfgnIddANpZoO0HzNsmlMKRUzh3QEc+AmACRKBzLnjAx0GQS1lhMq5PtCEXSmmKtyf6TF4s
keWxowKCCRiEX7X8KDzxvoA3FqIWUFYPU/YBKX1BFNsq4o6lo6K6tqIakqiSfJytMnPmWzKP+5xT
PcTceI7HlAGiAeKpl8xqcY4nDMDFrXklb9xVnMoSc7HDpdxTUlLx58yApyj2ysAQhR+G2GNcM2Mg
wpp9yBA5lNBLAGtf+ou7g8dOz1htzXHzl2/DF//oz/Hdj96A7Zvuwu7JE2DfY7axia17n4EzL30Q
Hv6CH8JFlz0Cjfeg3QU22wYdBcALdsaEWbBARhezwoZieZxK5YaisCxn3QXn0pZNvC31CHPPllX5
S3HgkjZOCHrVTrcrpJ3rmI6iQYk0tSWDIQnlaox2hmmqa1yZiuU+YOV6V5RpxpUzCYuA/Vozqc1C
afedWB9NUoNW9RANEA0QT7FkpmrAQaqcokzqLZo0Ra2G6skjqpmyuO/s2UJanEQwD+GZ8gXfR65g
6CNSzhTXnErn8H1PcdDiGSsfhix7nrGzGLBqW/h5h/5kj93bj+Lo7cewWPU47bTTcMZ9z0J7ZAvd
wGj3FgHwnAs9QQCzlAGSC/3CCJCBVhO9nZw0qy90oZARFuEZR2VdLgtVkDjxxR6yS57HKG9S8jLJ
mZGDGOhODcRockaW+nNcJX1Tw5U6M+RRSVvtkqchB8kSt1a/1n8/QkLev8zfb8osARHMaAwQDRBP
CRBrfo0AM0w0sVUvJx/XXNtMSTlPaK9mQdPNQ5VEyA0nk0foG3owfMwSAyA69MyxbE4lNLD2IVNc
DrG/yIxlz1gPHsu1Rw8Hdg3WTFh7QuM9usGj8R4tCBuNC5oKzNnErk3lctRmnSUVf9kvdMmrOZXI
XvQNEwk7ml2BsgUnSeog6bI5T+1dEbRIFBoJDFobQ4w6eFw+j2hRPB7C8ASlQA/GBJOAhLXoqMQW
GSDXwCvkYKv7HQFipcxeA2OZMscHiWt9zZYNVe4ujJh9d1EIhmV3NPERs9ledaKMrfS03H9F1d53
3MLSV42UajYwdlNzCAMLlqtfuYVE6BAMlZKnctcCK+fQkUPvGeu+R9szNgA4uKBC4xo0HG2N42O0
iK6eRLlMbiiWx+DMK2yJkntnHJIwCE73DePEOGXKUm4LVbJEYiCRyfA0njRIkdVCbWFFq1HZlNJS
4zzYkhmneqNJNzNQl9Wk1W1qaVf52BK4OZHJmSeHOiNv5RHlQbYChNEZubKLbYrZBoinnD8L4Av4
ON7QlydqDaiqTIKWjCKxhpdObu0nXnan00lDIuVwyumPo1WoRxORxQPoKk2+pKC1jsbybRt6jC0c
uCl7ry2Fr5AVUlblD66eYSOmlMiULUhaRzlLTNmgo9JEcBT8nJPILuULTblgKBkulQWKCwrRPvVN
6alJsjNXPUCuhiYZAKkqpGU5LikxVGhYcitJ9ytJ7RhPAh3zuGSu1qRJikcItSQJijxlQyoLF9va
M0A8dTxMzf1Qru4/eSQlDcZZaGvcpWKBoCyVHiqyMJRHB0cL0LCWh5jl+QQqKUukkKFppZ1SJrqY
MQ4ENCAMHEENQNfGXbZ44menzuSylzxaEDJB6QmfZMaaKEcm/y4p71PqH5IQsxVyZ8U6NTwPIm1e
7YRCUBZ33SetVyuNNOp3TDGoMshyLJkLQFMGT2UUyzozTEMSqYyds0BlKVoOB9bXVfU01fOmsQn9
qJSPNgMyFQ7XwriRY/Z7BogHWTqL6lf0eIRrHpesoW6r837NcdqvqysGMmWPT+2u5kkrU5b9kgoH
A4eyNhXmDiGLW8dMrnGMPirQdw1hcID32r40lcKULI1jPhqyxdI/JJQs0mXDqrKR42pBmlwCS9E0
KGAcvY9pctw4uZyrMklGDTr6/c80Jq6S/FQBFP2wnC2SENaoL2717Uq/QQoAy9aKKhHGgxqe2JbJ
Wd7EKqHWZBdis5iwtrDuoQHiKeEgVdNASK9cnVXouoSF0rFITkgfyjSxN8bxREllOjmapmUI3rET
2aeTD8pJKzEMWhIZuo8kboqWAJ6D1UCwNGDRDg2ZYCPkxVwG1wCCLvULIYjWooeZMkInBiSUs0MS
pWqVTZEgXOcsh8ZlsMLA8TIkc023kTQcHpXScusvXexIZPw8utBJT+Yi1sBVpZEvmqg8nKkIgIz9
VcYXSa57ppmZUJ6DlBTxKJmu1c0GiKc+VBGEmtFlVhkfQ6xmsaZfjPaZFQMRUjt7JFPF+kTLjXkx
NPAo6jeeWNiEFMsqxDW/LBgTMw5GFtmO6116btlELxWKLoMuZ4kUS2Nk83pVIifL42RrIGxW61mA
S8ZOXHiG+fJDmtxCowVhxr4y+gIw5UALAnBq7xqdUUIIg4nPiVPvU2dkUAra0zvuxZ2xGpMRq2NH
9qqL7FddNYwvfrIeKY6QlhoaIB7QTKUsGIse9qSq+zgTSRp5krqT7UtJ94Y084OFrx+P/Df0Tm45
9ZLBnM+UjsIUptiDTMuIcxf7iZJiwnqjjFBoM9K2OJTTachCZQ0P2to0l8zplYu+Wn1NoQr88rS2
oqYwVWtpqb+r70xf0OQusCpBoTxvCsDRhCZl1QtmFkb1NLISLWrXYyUbPT1GZSehB3kkByzVND1d
C4gqRz0eT7cnE2gLA8QfKEFkXfNK5pcmUsvyV4rCVrQaIrDnqg9JRbtPFNOyB6kmnUjm44WQ7JgE
gbs8tBNlGYTbW1ql9eBgLkWFUu6h2UOOgAZFX8+hUGCE2V3+t5Pk6tgDI3FZoVGmSFpkFxUiC03C
qZOctZcDJiWEFPjwaGihwBDBlkCKqyqRBlHuKnaAAEX5/HnCI0cluCNnKHFs1FQb0StgQQFSr4AL
z5X3e2ALA8QDGaqoVBFislzLkRTeYT6puALAyjS+9BInruZcraNVw4jINMMQn4KjApAeAdBkQ76h
0Ed0TFW/jBS3r9x/fBWcVu/SsAHZviA9DydfM8TaHcb7vBn+Sf632s2lAhq5Pyc4i0WYF2Mh133t
Ycdvs7J8rZSmud4VHo1YqOpPisGLBEZZ3QsHMd0blfqZpRddtmdYe4FDADFFylE5PMvr82wpogHi
AdTMohlOhFGJm7x+ifUhSKDq4J+uXUqrXJzRviKijVCkgKyjOBBBWGtLWy1NFIIARW8QjmDFKeNM
PURW/cT8nKLEVDYvFdSdrMSVhicEOB7zB524mCQARZUhRsbgiMMpNSjViT3Vq53QqRwRouteX61Z
yGXbZfRcci9xbCQP1sO3MnlmdQyo2RmXy0U+pgSJfJTYsR6ulGERVxbNrDU6uV4ctTBAPKXwI3ls
9hgNTFA34yF7U6yoEzXi5uOap0g6PLkbWyc7JIh1SS/Ux8yOudyW7s+znGTKclurOsuePWXQ131C
WZY3pJLnnCmRXDMjHrX7KLpCjSS78hB3oqQUIC1HU/z9KAolsjtNiChQXWdPCPpOqQEr+f4CinlI
xqSpN9Cm9aP7r7iYavg2BZRTYsXy9VqCaIB4kKMVHvnaCgqGOkBJnbBlRCKpFxj9Tj19noBO1KYf
LBvyNDF8qU5lmZywOKuY9HAmk5W5ZIAJHQulpmyguCqboryPrJcU1UCqIheTEi4UrzkLrzq1OZQn
r2Dli/w93/P0a1zoKFSJq7IQM8rOiXUGR2KDRrYxSPswjj5HGpfq4H3tlzWBnFjxFKd2rUdYXTES
LAwQTwkM1Qq9IuKKjI00PZarmUDeZOBKHUUOW2QNTjXTbVqMQPWeVKbAeSvFiSksc7QVRSmRRyov
goVOxKiH6sTllSZQVBmf6O+RANHy/mHUeiCp9JpL+KopmMUSUoorSmcWToXSgJ7Ce15c79IfSaDV
wwqtWs0K2PTnRIraN8pUpbjs1PYJTyeZ+pIrFbNJdG94tO1Hop+tIVpc1G2uYoB4APMU1dIfcQIh
zKfEipbMuHiUFVUUi4oBR4TKb4Or84jy78gnKWcSoaSlfQcHcg/WY0qxRczTmRRQIA1y8veJFA7A
aQUWUlSUKpOe5BiSeuxaWUiSmWmcaursUvEEaUSc1mrWrN7D8WczNVwRtszSKqLanBnZjE7pBVf8
RfUjRTnU4F9sKiYutYyxvJyFAeI9zg9H+nJ1xsaQRm7yRNRTZDk0IDUtlTLwcjrLFc2Wq5UvHhHE
ZYFcoDt7DXNVQmcwDHvKyv95UvsP2repSjdqWo0QCiql9AR4SMVxFiU3Z/N3qHXeEe0Gsldbg77P
3iNQ0+ixMuvIIRH6NY/EE7iGH01qLAKucjDDUKKXU31ARb+S3s2VYNwIhCcm+YglgsekSK7FOJy9
BXeTHbLui8kpA4uzNFNqxJGdcy0p6DdhM8CQZOOAeD71x8grX3M9ZIHqVyVx1WKsDnWfRWW66AoC
gYKT/pt2nxPNRv0uVUs0gFrRy0KvZaZc0UPqMUXMgtmrfyuUo4lUXQIG131bUgbzGE2aZf9UAHgk
ObMwdFLDDx6ho6bRoJZj4/GBlN5HJozlaDCiDTH2qa7FoGoK4OqseUo4wsIyxFNDRFnOjriCpE3N
6w5jEmYQy7dUQ+dolzndFE9WQh5vl7KrMkeX9yyoNZ6hhSLk7yqQK0KtILEhgaoOF2eeA40NmEY1
oC73aVQGUilixcBj2t6Q1KChgIPA0ikS8pQ5E5NqVUj/mklUGi3j8T6HDGOqQ5I3luQkvcoOx3YA
0NNrlAuoytLFKmDijXJFrCSY3I1liAeBiaQ3R8qKVtXe4ympV7kDq7s8XNWjeUeDZCYlSkemsbkR
aSVnBsAumbcXodIsz5+3SMpXOFm4bJiwyPjEzymCpJTzlxSZOiNFPShBVKIeKTII2S8JjPuBoOT1
5BfO02uNNJGZVvOVuj+4XxeZxR1ICwAo7UN5SMh+Y916qcjnknojN014XE2M0tfU/uTSosiZbuRf
pezX8NAA8cCmKqx6XulKLfpqoteD6kSh0SqeKLsEPEohLDXNlGVwKkuZNP4IZGa1YFhNOUn+EauJ
MEWnOyfKX0eyLiz9UAkwmMqqhI/HuN3PFUJBTJHFsIT0lUYBitokEb3WyefD+oJFpf+LqsdJo7qe
smCFlF2rklTdTZQOfnUZDjHkINHPlTJk1TWl7l+Oc1R9keVoRiYpXdY9NEA8ECws0zkeL+VDKCzL
/dIJYZyU6SXVGIVNBLGtkuw0xeDGlTNVnvzS8L5OJSQw5xXC+Piulo8SFXXKNIq0Yvh9J+6ntkJI
vyd7XEFgtfTZGAXQa+tNXeaKHiRjPGFGWEOrwUz184iEsjUmyX9SF5GzBiKmRjaokHdMjJZgWa5a
pT+5X/9YqAHlpHHKq0fQsOqaPmWSXLV3SFQUPLFaamGAeI/7iFIOqgAJ54MtHXuOqWxVTIlykm67
l76fAJv4qcgMtIAKi8JSTmYnGZCqtK5fgNqzpgAyzBLgNGCnCwMJMQNS/S8e6z/WGTEXVZvRRgWk
avjY8F1U2MrkKU+yXY05hLH8zehBy8Y3j7eTiZwqeVWbmOsydqyKU6b748VEzS6l8e40aa1Nnno9
U+ZVzKp6yD1Nw0IDxFON+vyqD0qqijelREcaGOsyL/X2Rju2Yoqay0iqu2mkdnkVIYPqYUjVuK/o
G2nTIpfTNP0mEHT2U0+864YdTe2TkZa8Z6Kp3En1ZSEk19IgQd036T6dop5wVX5PfMCZblML0uaL
lvC94ZL1qQuK/J96rpwHKlrrkqsLx8TkWwzPZOuh9Ber40tkpMQ8Nq8nWOFsgHiAtTMX75OiwiI2
AihlPhPy2DQtZDNa1Zvw500rg0yYKL30REPTfyBTSw3jkjcpdqhr0Jb8RpXVschwOHiclBOcahM7
MTgSJzyjcsETij5Uj4RpxNHTb65YT3Okdsil3rWUHks1dR428ESeJwB15M0CniCHy/K1ZNGUZeG4
KnZ1TxA1I4fvtpczbiUo6tfEpN2yRAPEU6yWRY+K9+1pjTPJmsTL0MJRcgCi0je1o6w6asmzReID
5KBXc+QyMTr3y1gMfyrbzjJfqcorQRH3XPqo8sRTjnbTC7lydoKqZ5mpS1yyv/R80wvknKsxpD6O
yrBymcrqNWZL14riON3oFdm80DaUzydlc1wBm3wMmihvs+e0Gjpx1MesfkaCyzh1QdmnvUn6BWaA
1hdJCwPEU0oNKzqaKo9D/4knFPKgiLukeHiKvFyVZIDOSpRyti8lFFWtdYwySNbDDrlCiAnLVIjB
TiWmyirbGesEFk7keE2wZICiluRpPFJTevWeTzjPRYHcvJXD4k0UHENW2pVcWyqrx+E6NRPivaO/
YfU2V9cDLiCaf9GVQiMTq8V9iIEcVTvcY6oRZbFeN/mcOA+ynLxiWIZogHhqeEhgHp8IReUmWi4x
xFSPRplIMVWnSTdJJewAjDYkSJRXsucU91pE30yKrAqAzatqXFEEhYfHqBInRfROGdCIr8fTbUWS
VCLSel7SBqC48NVzDTHRjvJgKj3m/YYyVLb0mMflYuV7DIzTrhEIcpVNq/ZDJJaLtURNyB47CCaw
1MyqyoJAtiyqdixXPcjQsuYR8NGIf2h54vcK21T5Hvmh2k+gCb1XFkc+hGn9xIY+iRONhWWo3pHW
5vSVimkRa5FipqMTntX2AmrNHNYZk/YArnNGqHHzSOO0aiOoE5D2m7toX5ICnABN7LCR6NOWM726
QBEJ6qLmBPKkcnbh/0h7hqrTMW6FkMZPJnWV1FxTIA+tilzZVFeBqmYAqddcTKbG2SDXDZyKHE5i
6syWIlqGeCCwWPHXKtZgyQDFAKAuT0mWrJkfmO62AsmcVtQCTnJ1kFRJW/c9ofQTtVdJBkIxUy30
HYqPMd0TG5FTZH91zPoRGS7v292f3vTWWTNN4ZkE7porqt5nqq8pCngVv5QEHOUdbjFNlm544qpH
YkhTyuXy6Y/eEwmEqb+robAitmurglGrwVdTZx++4ONnmQxzLAwQ72koha0pUmuiUKiTrD4JSGn3
FQjkzM6pKTLFRzft1/JYgUb8HsFVK2ukdpFHS4PJcyVlkFxTAXliu4ZG+8Us0kCesDqo3w8leFFl
jCxIxqjX1mqgx8TadJ3/UHE+zCRpdV9jCpQmjGvxVblaSRV5vM4KiTASbx1rWtaPoknqPHrdVfon
mAVFwFZfhLIsnQfgGTTYOW2AeCq5oRiIoNoQ0W4VNJ4T7NfEroYKTIL1NjVgSIBSSZHVshP18KDe
uOAKAOpeYt2bxMjudDp71vfFak+3ZG+sS9KauC0pP0KwQfVRacJZsH5yXAE35zd4cnUvv5ckBj80
lZdXQyIaPYMRUGnw1q+b1AWBxqt9Vck/nukkwRDofcP0On3wXOGK/mAFswHiKQKinhSzIgxL8ivq
Q1WcaFB0mkIPEWbpdTY2AUNcycXsJwiqQIHrTqiARzH1zdNQ5okuwZhgLinptRegLO84TjqhLD9L
ZkpE4xOdtb1B+hyKWkz6DMSON+oVEm36nnqTOXOrBi5yHTGp0agyttYo9CKbJU2Upn2yumxuX+lN
Khk5+f6xFrKlyaxYNDJrHUT5kaY9ASuZv2fYUOV7AKLUEiVlHl/3kkhtkpTePyvvEz3slHvHYg1N
anNTLTItlbijRP50e10Xl9K0CNUggKbNmWQGBRa+Lry/FL4UJJCrZ8qPMP259yXzY+1VUjE0q59h
og9JhSZTZ5KKhMja3F78nNy0Uk6ejgtTKHF3KvNXXi9CjbvO8KvEutipTlwOWUzVRzYASgVJHGFp
mBIMuGFiN5YhHgAihvLDixOHPQPsqpOhHOxjfNAnHqksRkwtRYZDythK3o9Wuy7S/lNWpXqtj4iz
6BdN2cYpYQQp4kDaBOn7ERxlKXzLFSmbK9Mr3vc+SchuSZks+VpTj1WmRWXCqrqEE/3I8fOWW5cS
Wrki5u8r2Sj+Xd7LyeazUsWceiq+Qs6kik08MYCamFlli1njIBogHkwIFRTV/2FV/mXCNHSvUWV7
E8ID2hSdqoZ6sbCseYp8t0A2nemxRAOWnsRanUW7VmpiWy73qz3ZWtWHKKrjSNvS79mPHLcq9ukY
ivvjUbdAbnkwoVqPmURdrT4tLm6+lhSj8dbLaMsQWmghfFVZ8IgzM+4jTvadKzZBnfCDI83Go1Lz
juuN3lDRAPFUM8Qqnah27fONo98jLSDKFVWChax/HkioA78aQMgekWJl8Gh3UJfpqt5EXeUVFRop
UcajNEqCFEmh1BriCKPsL38vhBj2/VtSGK36cuX+yrBiJALLFC1LtdK0bA/IcbA2IS3plN573gfI
xXAt2RCMPispSClvTLvvzPvKg2X/a3GckXqqpDaXiHXPOpTMggpmgGg9xFPrIcp+Vr2TSqKUKZmd
XM0rxOaqbyQl4zPFhLQ9p+y7UdUfghg8EFcG66IkFko2XPkLj7xF7468vE91pnUhNa1odGdJwIFl
JqU5gDV1BOJdJaUZWdeSnI23SLw3iq+o7ElJr8Sx3Mnm4pBFY1Hf8fWFx/vrmCaEp4EKMY+kwyZL
bhTSuLRpYCG+mx/Dl4tgAD7xnkdpNxuqGCCeeoYoS2Qp+eKm+jhyaKJ7gmpIMHLOHAuYKg5d6p0z
VXZKKKCogFRsqVAlUlFlcSQUwGvPFUZtuyn6m2kqSsJuk3hcnVJNYYn3knh/VJnEs7YtVcOIyrdZ
u2Y7nbUmwV5tJ4Oa41j3AvPggkd/qLdlJriScrAvGVt1q5BFdim3kRzzqE2qgdYp8My/OzC4OnY4
ls1+iCW0N31YA8RTDO+j7miqbZ3opnlhsCQERMMB7uFFhqJsRGjUeR/3y5Khe+YqUimTxbrdyOM3
r+sJOlDNn6RxFjzVWpvKxEiIVuipacpEpi8qoMoGk6dd4dQAQ/68StKINCGFUbIu4infbGB6cU4/
CZJ9X1dK+wy8coI+hah+n/6oyEiVFQzxvtCnqgAJgvKC44XXTiWnlqcyKWPMWysW1kO8h5GW49kj
rz6V0kMcvj5tnRTunebucqVEov/No8V8vfeMSgwgc9km7DHHjagxAhYhBrr79LhqbWWBB0Dx7kp7
oc5exz21fJufpppM9m8r36lUAjJX9B753k1MjGm/8jSBXC28EW+rDZpUqzP2Gt24BSr6fVwNOOLJ
x7rrgNGWTrroCFGLCHLkE7dQyMYlMZJ0rPqQPYa/ISuZLSwsLCwsLCwsLCwsLCwsLCwsLCwsLCws
LCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCws
LCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCws
LCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCws
LCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCws
LCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCws
LCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCz2if8X
Dhhv0ES30jEAAAAASUVORK5CYII=
B64_MARKER_7

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png')"
base64 -d > 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png' <<'B64_MARKER_8'
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
AAAASUVORK5CYII=
B64_MARKER_8

mkdir -p "$(dirname 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png')"
base64 -d > 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png' <<'B64_MARKER_9'
iVBORw0KGgoAAAANSUhEUgAAAbAAAAGwCAYAAADITjAqAAEAAElEQVR42uz9abhtSXUdiI4Za+19
7r3Z0CRJkwkkfadEkCAEEq2QAIGapw51tiSLsvSVLJXt5yr7q7JfletVvefnpmxVWXbJal2ykEAS
krCEBcI0Apk+6ftOgJI+IZvbnLObtWK+HxEzYsxY++L3L/2+E5PvcE+es8/ea6+9VsyYY445BtCj
R48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48e
PXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr0
6NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGj
R48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48e
PXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr0
6NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGj
R48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48e
PXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr0
6NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGj
R48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48e
PXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr0
6NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48ePXr06NGj
R48ePXr06NGjR48ePXr06NGjR48ePXr06NGjR48e/38R0k/BXRdf2M4aBAgQAApAMUAQAEj+ZEQB
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
rkJggg==
B64_MARKER_9

echo "==> Files written. Quick sanity check..."
S=0
grep -q "archivesName.set" android/app/build.gradle.kts                 && echo "  OK gradle (MaxPlayer artifact names)"      || { echo "  FAIL gradle"; S=1; }
grep -q "_fitAspects" lib/screens/player_screen.dart                     && echo "  OK player_screen (6 fit modes + big 2x)"  || { echo "  FAIL player_screen"; S=1; }
grep -q "_showTracksSheet" lib/widgets/player_controls_overlay.dart      && echo "  OK overlay (tracks bottom sheet)"         || { echo "  FAIL overlay"; S=1; }
grep -q "DraggableScrollableSheet" lib/widgets/video_info_sheet.dart     && echo "  OK video info sheet (draggable)"          || { echo "  FAIL info sheet"; S=1; }
grep -q "GOOGLE PLAY DATA SAFETY" lib/utils/privacy_policy.dart          && echo "  OK privacy policy (Data Safety section)"   || { echo "  FAIL privacy"; S=1; }
grep -q "1.0.0+18" pubspec.yaml                                          && echo "  OK pubspec (1.0.0+18)"                    || { echo "  FAIL pubspec"; S=1; }
test -f android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png && echo "  OK launcher icons installed"             || { echo "  FAIL icons"; S=1; }
if [ "$S" -ne 0 ]; then echo "SANITY CHECK FAILED - do not push; report the FAIL lines."; exit 1; fi

if command -v flutter >/dev/null 2>&1; then
  echo "==> flutter analyze (should print: No issues found!)"
  set +e; flutter analyze; A=$?; set -e
else
  echo "==> flutter not on PATH - Codemagic will build it"
fi

echo ''
echo '=============================================================='
echo ' v20 applied.  Push it:'
echo '   cd ~/IdeaProjects/maxplayer && git add -A'
echo '   git commit -m "v20: fit modes, instant pause, tracks sheet, landscape controls, faster marquee, 2x sign, info sheet, app icon+name"'
echo '   git push'
echo ''
echo 'THEN ON YOUR PHONE - TEST AND REPORT EACH LINE:'
echo '  1. App icon is the new neon play button; name shows Max Player.'
echo '  2. Fit button cycles: Fit / Crop / Stretch / 16:9 / 4:3 / Original'
echo '     (each tap shows the mode name at the top of the screen).'
echo '  3. Pause reacts the instant you tap (same for play).'
echo '  4. Tracks button (tune icon, bottom bar) opens a clean bottom'
echo '     sheet: Subtitles / Audio track / A-B loop. No glitch.'
echo '  5. Rotate sideways: play controls sit on the very bottom edge.'
echo '  6. Long video names scroll about 2.5x faster than before.'
echo '  7. Long-press the video: a BIG 2x sign appears in the MIDDLE.'
echo '  8. Tap i (info): drag the sheet up and down; all rows reachable.'
echo '  9. Codemagic artifacts are now MaxPlayer-release.apk / .aab'
echo '=============================================================='
