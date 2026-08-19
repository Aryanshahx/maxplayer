# Max Player

**The offline AI video player for Android.** Plays every local video with a
modern, gesture-driven player - and generates subtitles **on your device**
with AI, even for videos that have none. No account, no ads, no tracking.

Made by **Hyper Tech Labs** (Aryan Shah), Deoria, Uttar Pradesh, India.

## Highlights

- **Every format, hardware decoded** - mpv-based playback engine
  (media_kit) with subtitle & audio track switching, playback speed,
  A-B loop, shuffle/repeat and Picture-in-Picture.
- **AI subtitles, 100% offline** - whisper models run on the phone
  itself; generate subtitles for any video that has none.
- **Karaoke mode** - word-by-word highlighting of the current line.
- **Private folder** - PIN + on-device unlock (biometric / screen lock),
  hidden videos move out of the gallery and out of other players.
- **Advanced Cleaner with graphs** - scans every cache (thumbnails,
  preview strips, AI temp files, gallery cache), draws device-storage
  and reclaimable-space graphs, and frees everything with one
  **Clean cache** button. Largest videos & duplicate copies included.
- **Playlists** - create any number of named playlists ("Movies",
  "Songs", ...), add videos to them and play them in order. Saved on the
  phone - still there when you reopen the app.
- **Scans every storage** - internal storage AND SD cards (any mounted
  volume), on Android 7 through 15.
- **Every device welcome** - Android 7.0+ (minSdk 24) on arm64, 32-bit
  ARM and x86_64; every bundled native library is verified 16KB
  page-size ready; Android TV/non-touch devices can install it too.
- **True full-screen video** - the status bar and the back/home buttons
  auto-hide the moment the phone turns sideways (and with the fullscreen
  button), VLC-style; they return in portrait.
- **Statistics** - watch-time graphs, day streaks, most-watched videos.
- **Cleaner library** - folder views, sort/group, list/grid, themes
  (7 accent colours), network streams (http/rtsp/rtmp), DLNA casting.
- **Open with / Share to** from any gallery or file manager.
- **Self-diagnosing** - if the app ever closes unexpectedly ("has stopped"),
  the next launch shows a copyable crash report - no PC or logcat needed.

## Building

```bash
flutter pub get
flutter analyze        # must print: No issues found!
flutter test           # pure-Dart unit tests (no device needed)
flutter build appbundle --release
```

Release builds run on [Codemagic](https://codemagic.io) (see
`codemagic.yaml`); signed Android App Bundle (AAB) for the Play Store.

## Privacy

Everything happens on the device: no servers, no analytics, no internet
permission requirement for playback. See [PRIVACY_POLICY.md](PRIVACY_POLICY.md).

## Source

<https://github.com/Aryanshahx/maxplayer>
