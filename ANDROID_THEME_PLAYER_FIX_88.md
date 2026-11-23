# Android 1.0.1+88 — theme-colour player controls, white preset, recent-search contrast

Baseline: `1.0.1+87` (RunX Player rename + Instagram/Telegram links).
This update fixes the three issues reported from the device screenshot.

## 1. Player buttons now follow the theme colour

Before: overlay controls were hard-wired to white (`AppColors.playerForeground =>
Colors.white`), so picking a theme colour changed the app but never the video
player chrome.

Now (`lib/theme.dart`):

- `playerForeground` returns the **adaptive accent** — the same contrast-checked
  colour the rest of the UI uses — so it stays readable on the dark video surface
  in dark mode and on light surfaces in light mode.
- `playerMuted` is white70 in dark / dark grey in light.
- The transport trio (previous / play-pause / next), mute, speed label, queue,
  fit, rotate, lock, subtitle/settings glyphs, the karaoke highlight and the
  scrubber track/thumb all take the accent.
- The elapsed/remaining clock stays neutral white so the glyphs carry the colour
  (pure-white clock text was chosen for legibility over bright video).

## 2. White preset + five recent presets (Display Settings → Theme accent colour)

`lib/utils/settings.dart`:

- `useWhitePreset()` — restores the default (white) look in one tap.
- `recentAccents` — newest-first list of the last **5** custom colours, persisted
  in `disp.recentAccents.v1`; picking a colour you already used moves it to the
  front instead of duplicating it.
- `accentPresets` — always `[white, ...recent]`; white is never consumed by the
  recent list, so "back to default" is always one tap away even after six picks.

`lib/screens/display_settings_screen.dart`:

- New **RECENT COLOURS** row of circular swatches under the wheel. Index 0 is the
  white preset (check mark + `accent-preset-white` key), then up to five recent
  colours. Tapping any swatch applies it immediately; the selected one shows a
  tick and an accent ring.
- Short helper copy under “Theme colour” explaining white = default and that the
  five latest colours stay below the wheel.

## 3. Recent-search chips were white-on-white (screenshot)

`lib/widgets/recent_search_field.dart`:

- The chips relied on the global `chipTheme`, whose label style falls back to the
  accent (white by default) — so in light mode the query text was invisible.
- Each chip now sets `label.style.color = colorScheme.onSurface` (dark text in
  light mode, light text in dark mode) and an explicit `onSurfaceVariant` arrow
  avatar; the fill/border stay `surfaceContainerLow` / `outlineVariant`.

## Version

`pubspec.yaml` and `kAppVersionTag` stay on **1.0.1+87** so this rides along with
the RunX Player rename build (one Play upload). The `runx88_test.dart` suite is
included either way.

## New tests — `test/runx88_test.dart`

- Player glyph colour equals the theme accent in dark and light, and is not white
  once a colour is chosen.
- Recent presets: newest-first, capped at five, no duplicates, white always first,
  white preset restores the default while keeping history.
- Widget: white preset chip renders and switches the accent back.
- Widget: recent-search chip label uses `onSurface` and contrasts with its fill
  in both themes.

## Not verified here

No Android build or device run in this sandbox. After the GitHub Actions build,
check on-device: pick a colour → open a video (icons + scrubber take the colour),
Display Settings → tap White to return, and the search screen's Recent searches
chips in light mode.
