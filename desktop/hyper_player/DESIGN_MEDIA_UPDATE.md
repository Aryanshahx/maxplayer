# Three designs / media separation / effects / full-local-drive scanning

This correction builds on `hyper_player_player_followup.sh`. It is NOT a claim of
full Android parity or native Windows certification. Android source/signing remain
unchanged. Follow this file instead of older instructions where UI differs.

## Visible changes and how to use them
- **Home top bar: Open File (Ctrl+O)** replaces Scan, as newly requested. Home
  filters recognised audio extensions out without deleting them from the library
  or altering the actual playback queue. Audio screen already filters for audio.
- **Saved Playlists is separate from Playback queue.** The player playlist icon
  opens user-created saved playlists. A new playlist starts EMPTY unless Include
  current queue is explicitly checked. More actions -> Playback queue is the
  temporary playback order, clearly named, not a fabricated saved playlist.
- **Scan all local drives:** Folders -> computer/Scan system icon -> Scan all local
  drives. First empty Windows library also offers scan choices once. Enumerates
  Windows fixed-drive roots (not network/removable drives), then scans accessible
  subfolders breadth-first; choose a folder/drive manually for other locations.
  Progress/Cancel and partial-result errors remain visible.20k media/100k directory
  safety bounds still apply. This covers all local roots but does not promise
  access to protected/offline files or unlimited results; no admin bypass.
- **Brightness and volume:** left player-edge sun button or B opens sliders.
  Brightness is video-only dimming, NOT Windows monitor/backlight control.
  [ / ] change it by5%; Up/Down or mouse wheel change media volume by5%.
  Main-player volume explicitly clears native mute for nonzero volume and checks
  native readback. This is not control of the Windows master mixer/output device.
- **Gesture/fit feedback:** visible icon+text feedback retained briefly after
  gesture release. Fit button and Z show the selected fit; seek/volume/brightness/
  hold-speed/zoom have feedback. These are real actions, not only manual text.
- **3 app-wide design presets:** Display Settings -> APP DESIGN · ALL SCREENS:
  Android style (default), Compact Desktop and Cinema. They change the inherited
  design system across routes/dialogs: density, type scaling, surface/button/input
  geometry, list spacing, media grid extent and settings content width. They do
  not create three separate navigation trees or independently rewritten versions
  of every hard-coded cinematic/player component. Media data is not reset.
- **Illustrated manual:** actual Android vector gesture illustrations are ported
  for tap/double tap/swipe/pinch/hold. They are resolution-independent drawings,
  like Android's own manual, not external image downloads. Touch and keyboard
  descriptions and Player Settings' keyboard manual include the shortcuts below.
- **Discover banner:** expands nearer the screen edges (6px versus old16px inset),
  taller156px panel, larger title and seamless moving poster background. Real
  posters require the configured TMDB build key and connectivity. Offline/no data
  uses a gradient, not fabricated posters. Reduced-motion/TickerMode pauses motion.

## Effects are now source-integrated, not disabled placeholders
- **Karaoke subtitles:** Extras -> Karaoke. Uses the active/selected text subtitle
  track and real native cue start/end times, replacing normal subtitle rendering
  while active. Word timing is estimated by character weighting, matching Android's
  helper; it is NOT speech recognition or exact word alignment. Text subtitles are
  required; bitmap subtitles/no captions cannot be converted into lyrics. Select/
  load a subtitle track first if no usable track exists. Seek/source changes clear
  stale cues. No AI subtitle generation has been enabled.
- **Enhance:** Extras -> Enhance video applies native lavfi unsharp plus contrast,
  saturation and gamma values. Prior values are retained for disabling/rollback;
  unsupported filters produce failure feedback rather than a fake active flag.
- **HDR:** Extras -> HDR tone-mapping selects auto/clip/mobius/reinhard/hable/
  bt.2390 through the native renderer. It only affects HDR sources on a supporting
  renderer. It does NOT make SDR into HDR or guarantee a visible effect on SDR.
- Native property setter readback is checked because media_kit1.2.6 does not check
  the libmpv return code in its public setter. Readback acceptance still does NOT
  prove correct pixels/audio on every Windows renderer/device.

## Keyboard/mouse map (player focus required)
| Key | Action |
|---|---|
| Space | Play/pause |
| Left/Right | Seek configured5/10/15/30s |
| Up/Down; mouse wheel | Media volume |
| M | Mute/restore |
| B | Brightness and volume sliders |
| [ / ] | Video-only brightness down/up |
| Z | Next fit mode |
| I / O | Zoom in/out |
| Shift+arrows | Pan while zoomed |
| Hold R / release R | Temporary configured speed / restore previous rate |
| H | Show/hide controls |
| L / Escape | Lock/unlock controls |
| F; mouse double-click | Fullscreen |
| Ctrl+O / Ctrl+L | Open files / streams (app-level) |

Touch equivalents are illustrated in User manual and configurable in Player
Settings. Brightness minimum15%, zoom1–4x, volume100% or200% according to boost.
Boost can distort audio. Typing in a modal is not a player shortcut context.

## Verification boundary
Linux tests cover design persistence/different inherited geometry, fixed-drive
mask/type filtering, karaoke timings/overlay, native-property readback matching,
poster movement, vector-illustration rendering, brightness/volume shortcut callback,
playlist empty-default and existing regressions. Native Windows enumeration,
master/output-device audio, actual rendered karaoke/filter/HDR appearance, screen
DPI/layout acceptance and the prior preview/PiP/Cast integrations need Windows
runtime checks. No new Windows Actions run has been triggered by this delivery.

Read `PLAYER_FOLLOWUP.md` for earlier preview/mini-window/Cast boundaries. New
instructions above supersede its older scan-button/playlist/manual descriptions.
Private playback, Whisper, Chromecast/DLNA and remaining parity/native-release
requirements are not certified or declared complete by this update.
