#!/usr/bin/env bash
# =============================================================================
# HOTFIX: Codemagic build failure in update v5
# Error was: AAPT: ... |screenDensity|... incompatible with configChanges
# Cause: manifest had the invalid flag "screenDensity" instead of the
# valid "screenLayout". This script rewrites the manifest with the fix.
# Run from your flutter project root:  cd ~/IdeaProjects/maxplayer
# =============================================================================
set -e

mkdir -p android/app/src/main

cat > 'android/app/src/main/AndroidManifest.xml' << 'MAXPLAYER_EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
        tools:ignore="ScopedStorage" />
    <application
        android:label="Max Player"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
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

            <!-- "Open with Max Player": video mime type via content:// and file:// -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="content" android:mimeType="video/*" />
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="file" android:mimeType="video/*" />
            </intent-filter>

            <!-- Fallback for file managers that don't set a mime type: match
                 common video extensions on any host/scheme. -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="file" />
                <data android:scheme="content" />
                <data android:host="*" />
                <data android:pathPattern=".*\\.mp4" />
                <data android:pathPattern=".*\\.mkv" />
                <data android:pathPattern=".*\\.webm" />
                <data android:pathPattern=".*\\.avi" />
                <data android:pathPattern=".*\\.mov" />
                <data android:pathPattern=".*\\.m4v" />
                <data android:pathPattern=".*\\.3gp" />
                <data android:pathPattern=".*\\.flv" />
                <data android:pathPattern=".*\\.wmv" />
                <data android:pathPattern=".*\\.ts" />
                <data android:pathPattern=".*\\.mts" />
                <data android:pathPattern=".*\\.m2ts" />
                <data android:pathPattern=".*\\.vob" />
                <data android:pathPattern=".*\\.ogv" />
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
MAXPLAYER_EOF

echo "Manifest fixed. Now run:"
echo "  git add -A && git commit -m \"fix: valid configChanges flags (screenLayout) - AAPT build failure\" && git push"
