# Android +85 — opaque white player controls

Enabled video-overlay glyphs, title, speed/time labels and seek thumb/active track are white in both light and dark themes, independent of the theme accent. Genuine unavailable actions stay dimmed and non-interactive. Accent is retained for pressed/active feedback, not the resting glyph colour. Small glyph shadows help on bright video without adding any covering bar or gradient. Popup menus and settings sheets retain their own theme-safe text colours. No video/subtitle recolouring.

This cumulative guarded update accepts recognised +83 or +84 file baselines and includes +84's single spectrum slider, live hex and welcome/picker text corrections. It does not discard those pending fixes. Version becomes 1.0.1+85. Desktop, signing, package identity, APK/AAB workflows and VPN implementation are unchanged.

Default script operation is apply. Run from the existing repository root. --check preflights, --verify checks installed hashes. Unrecognised local edits stop before overwriting; backups are under Git metadata. No builds or Git operations are performed by the script. Build Android only via the existing GitHub Actions.

Dart/widget tests do not establish physical-device rendering or real VPN routing. Check overlay visibility on bright/dark videos after the Actions build. White controls cannot guarantee contrast against every frame, but no tinting panel is reintroduced.
