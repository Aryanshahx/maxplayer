#!/usr/bin/env bash
# ============================================================
#  update_v4.sh — MaxPlayer v0.4.1+5: PERMISSION HOTFIX
#
#  AndroidManifest.xml declared NO media permissions, so on
#  Android 13+ the storage-permission dialog NEVER appeared and
#  access was refused silently. This writes the full permission
#  set (READ_MEDIA_VIDEO / READ_MEDIA_IMAGES / legacy storage)
#  plus the proper app label "Max Player".
#
#  USAGE:
#    bash update_v4.sh
#    git add -A && git commit -m "v0.4.1: media permission fix" && git push
#    -> install the new APK; OPEN it -> permission dialog appears
#  NOTE: if the dialog still doesn't show, uninstall the app once
#  and reinstall (Android remembers a silent-deny across updates).
# ============================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f pubspec.yaml ] || { echo "ERROR: no project here - apply update_v1.sh first."; exit 1; }
echo ">> Writing v0.4.1 files ..."
mkdir -p "$(dirname "android/app/src/main/AndroidManifest.xml")"
cat > "android/app/src/main/AndroidManifest.xml" <<'MP_EOF_android_app_src_main_AndroidManifest_xml'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- ===== Media permissions (must be DECLARED or the system dialog
         never appears and access is refused silently) ===== -->
    <!-- Android 13 (API 33+) granular media permission -->
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <!-- Thumbnails on some Android 13+ builds touch the images bucket -->
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <!-- Android 10–12L (API 29–32) -->
    <uses-permission
        android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <!-- Android 9 (API 28) and below: legacy write for deletes -->
    <uses-permission
        android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28" />

    <application
        android:label="Max Player"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:requestLegacyExternalStorage="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
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
MP_EOF_android_app_src_main_AndroidManifest_xml
mkdir -p "$(dirname "pubspec.yaml")"
cat > "pubspec.yaml" <<'MP_EOF_pubspec_yaml'
name: maxplayer
description: "A new Flutter project."
# The following line prevents the package from being accidentally published to
# pub.dev using `flutter pub publish`. This is preferred for private packages.
publish_to: 'none' # Remove this line if you wish to publish to pub.dev

# The following defines the version and build number for your application.
# A version number is three numbers separated by dots, like 1.2.43
# followed by an optional build number separated by a +.
# Both the version and the builder number may be overridden in flutter
# build by specifying --build-name and --build-number, respectively.
# In Android, build-name is used as versionName while build-number used as versionCode.
# Read more about Android versioning at https://developer.android.com/studio/publish/versioning
# In iOS, build-name is used as CFBundleShortVersionString while build-number is used as CFBundleVersion.
# Read more about iOS versioning at
# https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
# In Windows, build-name is used as the major, minor, and patch parts
# of the product and file versions while build-number is used as the build suffix.
version: 0.4.1+5

environment:
  sdk: ^3.12.0

# Dependencies specify other packages that your package needs in order to work.
# To automatically upgrade your package dependencies to the latest versions
# consider running `flutter pub upgrade --major-versions`. Alternatively,
# dependencies can be manually updated by changing the version numbers below to
# the latest version available on pub.dev. To see which dependencies have newer
# versions available, run `flutter pub outdated`.
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  # Use with the CupertinoIcons class for iOS style icons.
  cupertino_icons: ^1.0.8
  media_kit: ^1.2.6
  media_kit_video: ^2.0.1
  media_kit_libs_video: ^1.0.7
  video_player: ^2.14.0
  shared_preferences: ^2.5.5
  path_provider: ^2.1.6
  photo_manager: ^3.12.0
  wakelock_plus: ^1.8.0

dev_dependencies:
  flutter_test:
    sdk: flutter

  # The "flutter_lints" package below contains a set of recommended lints to
  # encourage good coding practices. The lint set provided by the package is
  # activated in the `analysis_options.yaml` file located at the root of your
  # package. See that file for information about deactivating specific lint
  # rules and activating additional ones.
  flutter_lints: ^6.0.0

# For information on the generic Dart part of this file, see the
# following page: https://dart.dev/tools/pub/pubspec

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
  #   - images/a_dot_ham.jpeg

  # An image asset can refer to one or more resolution-specific "variants", see
  # https://flutter.dev/to/resolution-aware-images

  # For details regarding adding assets from package dependencies, see
  # https://flutter.dev/to/asset-from-package

  # To add custom fonts to your application, add a fonts section here,
  # in this "flutter" section. Each entry in this list should have a
  # "family" key with the font family name, and a "fonts" key with a
  # list giving the asset and other descriptors for the font. For
  # example:
  # fonts:
  #   - family: Schyler
  #     fonts:
  #       - asset: fonts/Schyler-Regular.ttf
  #       - asset: fonts/Schyler-Italic.ttf
  #         style: italic
  #   - family: Trajan Pro
  #     fonts:
  #       - asset: fonts/TrajanPro.ttf
  #       - asset: fonts/TrajanPro_Bold.ttf
  #         weight: 700
  #
  # For details regarding fonts from package dependencies,
  # see https://flutter.dev/to/font-from-package
MP_EOF_pubspec_yaml
echo ">> Resolving packages ..."
flutter pub get > /dev/null
echo ">> Analyzer ..."
if dart analyze; then
  echo
  echo "==============================================="
  echo "  v0.4.1 applied (permission fix)."
  echo "  Ship it:"
  echo "    git add -A"
  echo "    git commit -m \"v0.4.1: media permission fix\""
  echo "    git push"
  echo "  Install the APK, open the app -> the SYSTEM"
  echo "  permission dialog must appear now."
  echo "==============================================="
else
  echo "applied but analyzer reported issues - paste them in chat."
  exit 1
fi
