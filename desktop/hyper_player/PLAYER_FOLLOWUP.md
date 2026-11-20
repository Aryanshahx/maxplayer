# Player/input/scanning correction — consolidated follow-up

This follows the delivered 54-file consolidated update. It includes the Windows
network-test path assertion fix; no separate application of that fix is needed.
Android source, package, signing and build workflows remain untouched.

## Included changes
- Ported the actual Android Player Settings composition and preference model into
  the separate desktop project, with scoped desktop preference keys. Gesture
  switches, seek step, hold rate, auto-hide delay, resume, screen-lock visibility,
  sound boost and low-end frame-dropping preference now connect to the player.
  Added default fit and an explicit **User manual · keyboard & mouse** button.
- Touchscreen: configurable side double-tap seek (5/10/15/30s), centre double-tap
  play/pause, left vertical video brightness, right vertical in-app volume,
  horizontal seek (90s per screen width), hold-to-speed-up with exact previous-rate
  restoration, fit-ladder pinch or 1–4x focal zoom/pan and two-finger tap reset.
  One-finger drag pans when zoomed. Mouse double-click remains fullscreen.
- Keyboard/mouse: Space, arrows, M, F, Escape and mouse-wheel volume. Ctrl+O and
  Ctrl+L remain app-level open-file/stream shortcuts. Keyboard focus matters;
  typing in modal fields must not operate underlying playback. Boost allows up to
  200% amplification and can distort audio; disabling boost caps at100%.
- Transport layout follows the Android rows: timeline; centred shuffle/previous/
  play/next/repeat; mute/speed/extras on left, queue/fit/window action on right.
  Removed the extra desktop volume slider that displaced Android controls. Screen
  lock is on the edge; PC fullscreen deliberately replaces phone rotation.
  Pixel-perfect Windows/DPI acceptance remains pending.
- Sleep timer countdown/until-end indicator under title. Start, cancel, expiry and
  end-of-item transitions refresh the indicator; countdown has a scoped ticker.
- Timeline hover UI: debounce, time label, actual frame decoder callback, loading/
  unavailable states, stale-response rejection and bounded memory. A separate
  muted, paused local-file decoder never seeks or records the main playback.
  Only one request runs plus one latest pending request; the decoder is released
  after15s idle. No frames written to disk, stream requests or vault playback.
- Windows PiP adaptation: an always-on-top 480x320 mini-window using the SAME
  playback engine, with accessible Play/Pause and Return to full player. Window
  bounds/maximized/fullscreen/topmost state are retained and restored; failed entry
  attempts rollback. This is a Windows mini-player, not Android's PiP API.
- Cast to TV: same *type of action as Android's source* (open system mirroring
  chooser). The app first explains screen exposure, then opens Windows wireless
  display via `ms-settings-connectabledevices:devicediscovery`. Requires Miracast-
  capable PC/TV/adapter. Failure gives Windows+K guidance. This does NOT implement
  Chromecast/DLNA discovery, media-only casting or verify a TV connection.
- Scanning: top-bar Scan opens Choose folder/drive or Rescan saved roots. Main
  library and Folders include accessible nested folders, not only direct children.
  Add a drive root such as C: or D: to include that drive, then add other roots.
  Progress/Cancel, per-directory errors, no link traversal,20k-media/100k-directory
  bounds,10s directory inactivity timeout and partial-result messages are included.
  Existing library entries are retained. Explicit roots only; no silent automatic
  whole-device indexing, protected-folder bypass or guarantee every device file
  is reachable. Large/locked/disconnected folders can produce partial results.
- Fixed the Windows CI folder assertion to compare filesystem identity rather
  than `/` versus `\` path spelling; no tests disabled to bypass this failure.

## Verification and limits
Linux analyzer and regression tests cover settings persistence/fallback, touch
swipe/hold/pinch callbacks, zoom maths, sleep states, manual opening, recursive
scanning/link/limit handling, mini-window state transitions through a fake native
port, and preview debounce/stale/fallback UI. They do NOT validate native Windows
rendering, actual frame contents or seek precision, audio boost/frame drop/zoom
properties, actual topmost/focus/resize behavior, wireless-display opening or TV
connections. Those need the Windows workflow and real Windows fixtures/laptop.

The user's supplied previous Windows log confirms the DPAPI fixture smoke test
passed on that CI account; this is not a vault audit or laptop recovery guarantee.
The previous run failed only the path-spelling assertion, now corrected here.

No claim of full Android parity or production/security readiness. Private-vault
playback, Whisper/AI model integration, karaoke, verified HDR enhancement,
Chromecast/DLNA, native Android permissions/background services and remaining
screen/metadata/translation parity gaps are still outside the completed scope.

## Build and test on Windows
Use the existing Windows desktop preview workflow on the new pushed commit.
`window_manager` supplies native mini-window integration and is resolved by the
workflow; no manual DLL download, paid service or local Android build is needed.
Do not rerun an OLD failed workflow commit and expect new code.

Test these specifically after extracting the complete portable ZIP:
1. Touch gestures and their ON/OFF settings, touchscreen versus mouse double-click,
   long-press release/cancellation, pinch/pan reset, keyboard focus and screen lock.
2. Sleep countdown under title and until-end badge, including cancel/expiry.
3. Hover a local MP4/MKV timeline without altering main position/audio; rapid hover,
   source changes, unsupported codecs and missing files must not show stale frames.
4. Mini-player entry from normal/maximized/fullscreen, topmost behavior, resize,
   Play/Pause and restore; repeated entry/restore and source changes.
5. Cast confirmation, Windows chooser/fallback, actual compatible Miracast hardware
   and stopping projection through Windows. Do not assume Chromecast support.
6. Choose each drive/folder root, nested media, permission failures, cancellation,
   duplicate roots, large scans, inaccessible subfolders and restart persistence.

After this follow-up, use its own --verify. The original update's --verify is a
snapshot of older files and is expected to report differences after a newer update.
Do not force or reapply the old update to undo the correction.
