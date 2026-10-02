# Max Player

A local-first Android video player built with Flutter + media_kit (libmpv).
Dark cinematic UI, on-device AI subtitles (whisper), TMDB-powered movie
discovery, quick-share between devices, private vault, and more.

## Features

- **Playback:** every format libmpv understands, subtitle/audio track
  switching, PiP, aspect rotation, volume/brightness gestures, MKV seek
  thumbnails.
- **Library:** folder grouping, grid/list views, playlists, private vault,
  network storage, cloud import, Quick Share to other devices.
- **Discover movies:** TMDB trending / top-rated / by-genre rails with
  infinite scroll, trailers via YouTube, Ask-AI (OpenRouter) suggestions.
- **On-device AI subtitles:** whisper.cpp audio -> SRT, works 100% offline
  after a one-time model download.

## Monetisation & privacy

The release build shows **Google AdMob** ads: a banner on the Home and
Discover screens, plus session-capped interstitials on the Discover entry,
Private folder, and Open Stream tiles (at most 3 per session). Debug builds
always use Google's **test** ad units so development can never generate
invalid clicks against the real account. See
[PRIVACY_POLICY.md](PRIVACY_POLICY.md).

## Building

```bash
flutter pub get
flutter build apk --release \
  --dart-define=TMDB_API_KEY=your_tmdb_v3_key \
  --dart-define=OPENROUTER_API_KEY=your_openrouter_key
```

Release signing uses `android/key.properties` (gitignored) when present and
falls back to the debug key for local builds.
