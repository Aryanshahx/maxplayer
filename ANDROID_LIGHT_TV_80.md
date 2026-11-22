# Android +80 — light appearance and remote-friendly TV layout

## Apply from your existing IntelliJ repository root

Save `update_android_light_tv_80.sh` in the repository root. Run:

```bash
bash update_android_light_tv_80.sh && git add -A && git commit -m "Fix light appearance and improve Android TV remote layouts" && git push
```

`git add -A` stages unrelated pending changes too; review them first.
The script applies by default. It validates every touched file before writing,
refuses unknown local edits, keeps originals under `.git/android80-backups/`,
and supports `--check` and `--verify`. Already-applied files are safe to rerun.
It does not install dependencies, build, commit, push or change Play Console.

## Appearance corrections

- Home's Max Player logo keeps the purple/cyan brand gradient in both themes.
  The mask uses `srcIn` and opaque glyphs rather than multiplying the gradient
  by dark text in light mode.
- Playback top/bottom control surfaces become translucent white in light mode,
  with dark readable labels and icons. Dark mode keeps dark control surfaces.
  The actual video, black letterboxing, subtitle presentation and on-video
  transient overlays are not recoloured. Accent controls still respect the
  chosen accent, adapted for contrast on the light surfaces.
- Switches share one thumb/track/border/focus/disabled-state palette. Removed
  per-screen accent thumb overrides that made selected thumbs blend into tracks.
- Home Discover banner changes its fallback gradient, poster scrim and copy to
  light colours. Movie poster imagery itself is preserved, not inverted.
- Discover's featured carousel uses adaptive background veils and title/meta
  colours instead of permanent black backgrounds and white-only copy.
- Top 10 outlined rank numbers use a visible neutral stroke in both themes.

## Android TV changes

The repository already has a TV launcher category, TV banner and optional
leanback/touchscreen/microphone declarations. These are retained, not duplicated.

- Native Android UI-mode detection distinguishes TVs from large tablets.
- TV routes receive a 24 logical-pixel overscan margin.
- Wide Home layouts show all eight quick actions together; no swipe is needed
  to reach the second page. Phone layouts keep the existing paged tiles.
- TV quick actions do not disappear when the video grid scrolls. Their focus
  ring is painted above the opaque tile, and redundant background blurs have
  been removed to reduce GPU work.
- Wide video grids use larger cards rather than packing phone-sized tiles.
- Previously touch-only carousel artwork, Top 10 cards, discovery filters,
  discovery-section posters and video grid cards support remote focus/OK.
  Accent choices, IPTV retry, AI suggestion moods/cards and AI prompt chips
  are also keyboard/remote reachable.
- Remote targets have a visible focus ring without changing layout size and
  scroll into view when focused. Context Menu opens long-press video actions.
- Directional focus traversal and the remote Select/OK key work alongside
  standard Material buttons, text input and sliders.
- Player keys no longer intercept OK/arrow events belonging to focused controls.
  Media play/pause/rewind/fast-forward retain their playback functions.
- Playback controls do not auto-hide while an actionable control has focus.
- Featured-carousel rotation/zoom pauses while a remote target inside it has
  focus, so the selected movie does not change underneath the user.
- Denied local-media permission no longer traps users on a dead-end page:
  Home navigation, quick actions and Discover remain reachable, without
  bypassing the media permission or exposing protected local videos.
- Home poster auto-scrolling honours reduced-motion settings and pauses on focus.

## Preserved

Unified phone/tablet/TV package `com.hypertechlabs.maxplayer`, existing signing,
APK/AAB workflows and dependency-download retry fix, ad-free state, review
eligibility, offline interface languages, persistent menu Back stack and inline
recent-search history. Windows/desktop remains paused and unchanged. Android
build number is incremented to `1.0.1+80`; no dependencies are upgraded.

## Verification and device checks

Regression coverage includes both switch palettes and multiple accent colours,
light player chrome, gradient-mask configuration, native TV detection fallback,
launcher/banner retention, remote arrow + OK activation, and light Discover
layouts at phone / 960×540 / 1920×1080 logical viewport sizes.

Local checks are Flutter tests, static analysis and Python release tests only.
Native APK/AAB builds are deliberately left to GitHub Actions:

- APK: https://github.com/Aryanshahx/maxplayer/actions/workflows/android-apk.yml
- AAB: https://github.com/Aryanshahx/maxplayer/actions/workflows/release-aab.yml

This update is not a claim of Google Play TV certification or hardware-tested
parity. Test a real Android TV/Google TV remote: launch from TV Home, deny/allow
media access, traverse all quick actions, browse/search Discover, open/close
settings, play local/network media, focus and activate transport/settings/seek,
and use Back to return. Device file pickers, speech recognition and external
YouTube apps depend on what the TV manufacturer installs. Play may require a
separate TV opt-in/review; adding or retaining a launcher does not publish it.
Also check phone light/dark modes, all switch transitions, portrait/landscape
rotation and large text. Third-party poster artwork and video remain original.
