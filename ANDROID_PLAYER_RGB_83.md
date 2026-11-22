# Android +83 — remove covering bars and preset accent buttons

Baseline: +82 (`5150d32`). Version: 1.0.1+83.

- Player top and bottom control containers have no background decoration: no solid panel, tint, scrim or translucent gradient. Buttons, seeking, menus and video/subtitles remain intact. Actual video and letterboxing are unchanged.
- Display Settings has one custom RGB section (three channel sliders and hex preview). Preset colour buttons and their widget implementation are removed. Existing saved colours are retained as the initial slider values, so upgrades do not reset appearance.
- Appearance Light/Dark/System choices are unaffected; only the old accent swatches are removed.
- Manual updated to match. VPN, package identity, desktop, signing and APK/AAB workflows untouched.

Run the single embedded .sh from the existing repository root. Default is apply. --check performs compatibility preflight; --verify checks installed file hashes. Unknown local edits stop before overwrite. The script does not build or commit/push.

With completely transparent control containers, contrast naturally depends on the video underneath. This update deliberately does not add another covering scrim. Check real-device playback in both themes after the GitHub Actions build. No native/device rendering or real VPN connection has been tested here.
