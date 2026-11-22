# Android +84 — one colour slider, live hex and readable onboarding

Baseline: +83 (`de901d1`). Android version: 1.0.1+84.

- Display Settings now contains exactly one hue/spectrum slider, no RGB-channel sliders or preset buttons. This single slider selects hues with fixed saturation/value, not every independent RGB combination. Existing saved choices remain until it is moved.
- The custom-colour widget has its own settings listener. The previous const child could retain its original channel/hex values even when the parent rebuilt. Selected swatch, selectable six-digit hex, thumb and contrast-adjusted theme-hex label now update together.
- Hex is a preview, not an editable field. Selected hex is the saved raw colour; Theme accent is the contrast-adjusted colour used in the current light/dark theme. These may intentionally differ.
- Welcome, how-to and player-guide titles, descriptions, feature cards, Skip and inactive dots now use theme text/surface roles. The gradient brand mark retains a white srcIn mask and a darker light-mode palette.
- Video-picker titles, empty state, durations, selection counts and outlines use theme roles. Discover loading/progress and page dots adapt, and the destructive delete button uses a foreground chosen for its actual danger fill. White labels over deliberately dark media overlays/QR/image content are preserved.
- Existing no-background player controls remain untouched: no player bars or gradients reintroduced. VPN, signing, Android identity, desktop and APK/AAB workflows unchanged.

Run the embedded script from the existing repository root. Default apply; --check compatibility preflight; --verify installed payload hashes. Unknown local edits stop before overwrite. Backups are under Git metadata. No build, commit or push is performed.

After GitHub Actions builds APK/AAB, verify the single slider, hex and swatch while dragging, theme changes and restart persistence. Check all three welcome pages and the empty video picker in light/dark themes. Native compile, physical-device rendering and VPN routing are not established by Dart/widget tests.
