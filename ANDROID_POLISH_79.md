# Android 1.0.1+79 — light-mode, recent search and menu-navigation correction

Apply after the Android +78 update. Windows development remains paused; this update contains no Windows, signing, package-ID, admin-backend or workflow changes.

## What was wrong and what changed

### Settings navigation and tap flash
The +78 menu popped itself before pushing a selected screen. That exposed Home during the route transition and removed the menu from Back history. The new `HomeMenuScreen` stays on the navigation stack and pushes each child using its own context. Back from Appearance, Language, Display, Statistics, Manual, About or Privacy returns to Settings and more. Back from that menu returns to Home. Scroll position is retained. A per-menu guard ignores repeat taps while a child page or external launch is opening. External Instagram/email launches do not pop the menu. Failures show a message rather than leaving an unhandled async error.

Theme palette changes no longer cross-fade through an intermediate mixture of old and new colours; the system/light/dark preference still works and is persisted.

### Light-mode audit
Fixed remaining hard-coded dark canvases or white-on-white captions in statistics, category pages, the Discover search header, Hot searches, poster captions, local video-grid filenames/sizes, movie details, AI forms, legacy Discover cards, social cards and Top 10 headings. Text, outline and surface-container roles now use consistent neutral surfaces. Secondary text no longer relies on very faint black opacity in the corrected styles.

Primary/on-primary foreground is selected using calculated black/white contrast, including purple accents where the old brightness heuristic chose an insufficiently contrasting foreground. Selected default chips keep readable text against a neutral selected surface. Rating/error accents have separate light/dark values. Video and poster pixels are not inverted or colour-filtered; their dark image overlays retain white captions as appropriate. Native player's top/bottom overlay controls and karaoke highlights use a separate media accent so the default light-mode charcoal accent cannot disappear against the black video canvas. The player settings and speed/menu surfaces remain adaptive. QR backgrounds stay white.

### Recent searches
Removed the floating overlay/follower dropdown completely. Recent queries are compact chips in the normal page layout, maximum three per category. Long values ellipsize and the chip row can scroll horizontally rather than expanding into several tall rows. Clear is available in the section header. History is hidden while entering a non-empty query, leaving the results area clean.

In Discover, recent queries occupy the first item of the SAME scrolling list as Hot searches; the Hot searches heading and items follow below them. They cannot float over or obscure Hot searches. Fixed-height search headers show only the field: their history section is placed in the page body. Library search does the same. Audio, IPTV and Language use an inline section beneath the field. Recalling a chip reuses the existing search callbacks. A clear-generation guard prevents a pending typing timer from re-adding cleared history. History remains on-device; no new telemetry is added. PIN/password/stream-address fields remain excluded.

### Instagram
Shared endpoint and visible Discover social handle updated to:
https://www.instagram.com/maxplayer_official2026?evlk=MTR6NjljZGZtZ2NvdA==

### Existing features retained
The ad-free dependency/manifest changes, strict AAB ad-permission verifier, AAB Maven repository fix, Pashto/Uzbek options and native in-app review eligibility logic are retained. This is not a new review prompt or a reset of its cooldown.

## Validation and boundaries

Regression tests cover menu → child → Back → menu, repeated taps, both palettes across all selectable accents, fixed-height search fields, a 320-pixel-wide enlarged-text layout where Recent searches ends above Hot searches, three-entry limits, recall/clear, pending-edit invalidation and the exact Instagram endpoint. The regular Flutter suite and release-verifier unit tests are run on a clean copy with the delivery script applied.

These are source/widget tests, not a guarantee of perfect native rendering, GPU-frame timing or every Android device/font size. Verify Light, Dark and System on a real Android phone, Discover with keyboard open, long recent queries and menu Back behaviour using the GitHub Actions APK. Android builds remain GitHub Actions only.

## Apply / commit / push

Put `update_android_polish_79.sh` in the existing IntelliJ repository root. The script defaults to apply, embeds all changed file contents, checks baseline hashes, backs up files, rejects conflicting edits and supports --check / --apply / --verify. Version code increases from 78 to 79; choose a higher unused code before building if Play already has 79 or higher. App package and signing configuration are unchanged.

```sh
bash update_android_polish_79.sh &&
git add -A &&
git commit -m "Polish Android light theme, inline recent searches and settings navigation" &&
git push
```

`git add -A` stages every pending change, including unrelated work; review it first. Use the NEW commit's Android APK/AAB Actions run, not a rerun of an older commit. Re-publish `privacy/index.html` if your public policy site is hosted from another source; policy wording now refers to the Recent searches section, not the removed dropdown.
