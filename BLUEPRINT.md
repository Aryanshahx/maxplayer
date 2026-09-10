# MaxPlayer — Rebuild Blueprint

Fresh start. Same app, clean foundation. This document is the contract for the rebuild:
what we keep as *decisions* (not code), the target architecture, and the build order.

---

## 1. Non-negotiables (carried forward from v148)

These were earned through months of device firefighting. The rebuild keeps all of them:

1. **Local-first, ad-free.** No accounts, no analytics, no tracking. Internet permission never abused.
2. **Multi-engine from day one** — not bolted on later:
   - **MPV (media_kit) = the default workhorse.** libmpv/ffmpeg underneath.
   - **ExoPlayer (video_player) = secondary route** only when it proves safe per-device.
   - Every engine route's preflight is **wrapped in try/catch** → crumb → snackbar → failover.
   - **No silent tap failures, ever.** A tap must either play or visibly report why not. *(v148 lesson)*
3. **Crash forensics from day one:** crash_log with play-stones, strike tracking, and `report.last`
   persistence — evidence must survive even when the reopen dialog doesn't. *(v140–v148 lesson)*
4. **Resume must survive process kill** (position stone persisted on pause/track-end/tick).
5. **System-consent deletes only** (MediaStore deleteRequest on Android 11+).
6. **Glassmorphism UI** aesthetic, dark-first.
7. **Never auto-start playback on launch.**
8. **Tests from day one** — every shipped fix gets a pin test. No reaching 148 versions before a
   test suite exists.

## 2. Hard-won device knowledge (design inputs, not code)

- Realme/MTK and Samsung/Exynos MediaCodec stacks have different HW-decode quirks; OEM
  task-killers reap background/headless work. Any engine choice logic must be per-device
  learned (strikes) rather than assumed.
- "Tap → nothing, no dialog, all devices" = Dart-level silent abort, not native crash.
  Guard every async preflight.
- First-play on a fresh install may need a "learning probe" strategy before trusting a codec path.
- Unfiltered logcat is useless; structured crumbs + persisted reports are the diagnostics.

## 3. Target architecture

```
lib/
├── main.dart              # bootstrap: media_kit init, crash_log arm, routing
├── screens/               # library (grid), player, settings  (glass UI, dark-first)
├── engines/               # EngineRouter (pure decision fn) + per-engine adapters
│                          #   MpvEngine, ExoEngine — behind one PlayerEngine interface
├── models/                # Track, ResumePoint, EngineChoice, CrashReport
├── utils/                 # crash_log, prefs, file_scanner, thumbnails
└── widgets/               # glass cards, player controls, snackbar reporter
```

Rules:
- **EngineRouter is a pure function** (inputs: path, codec, strikes, flags → EngineChoice). Unit-testable, no I/O.
- **PlayerEngine interface** so engines are swappable; screens never touch engine APIs directly.
- **State management:** plain `ChangeNotifier`/ValueNotifier until proven insufficient — no BLoC ceremony for v0.1.
- All persistent state via shared_preferences + JSONL crash log in app documents dir.

## 4. Dependencies (already in pubspec)

| Package | Role |
|---|---|
| media_kit / media_kit_video / media_kit_libs_video | MPV core engine |
| video_player | ExoPlayer route |
| shared_preferences | strikes, settings, resume index |
| path_provider | crash log + thumbnails dir |

Add later (only when needed): file scanning, thumbnails, permission handler, wakelock,
volume/brightness gesture helpers.

## 5. Build order (each step = shippable + tested)

1. **v0.1  Skeleton:** library screen lists videos (MediaStore scan), tap → MPV plays. Crash log armed. ~5 tests.
2. **v0.2  Glass player UI:** controls, seek, gestures (brightness/volume), wakelock.
3. **v0.3  Resume:** position stones, survive kill, "resume from X?" affordance.
4. **v0.4  Forensics:** strikes, report.last, reopen dialog.
5. **v0.5  Multi-engine:** EngineRouter + Exo route + failover, guarded preflights.
6. **v0.6  Gallery polish:** thumbnails, folders, sort/filter, delete with consent.
7. **v0.7  Settings + edge formats** (avi/flv/ts → MPV forced), network streams (later).
8. **v1.0  Play Store hardening:** release build, both-device soak test, listing.

## 6. Release checklist (before any user install)

- [ ] analyzer clean
- [ ] all tests pass
- [ ] release APK installed on Realme **and** Samsung
- [ ] tap every playable format once
- [ ] kill mid-play → reopen → resume offered
- [ ] crash report written to report.last when forced
