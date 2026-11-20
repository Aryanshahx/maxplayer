# UI / input correction

Apply after hyper_player_playback_network_update.sh. This update affects the separate desktop app only; Android sources, version, signing and package are unchanged.

## Changes
- ON switches use a contrasting thumb over the accent track instead of mixing the same colour.
- Mouse wheel: left half = video brightness, right half = app volume; horizontal scroll = seek. Drag origin remains locked. Trackpad start records its actual half.
- Volume boost defaults OFF. A one-time safety migration resets the earlier implicit ON preference; afterwards an explicit boost choice persists. App gain is capped at 100% with boost off; no system-volume changes.
- Page Up increases video brightness 5%; Page Down decreases it 5%. Click the video to focus keyboard input; laptops may require Fn. This is video dimming, not display-backlight control. B opens sliders.
- Removed Playback queue from player three-dot choices and removed Generate with AI from Subtitles. AI remains in Extras.
- AI selection is disabled until preferences load and while starting/running. Model/language/translation/karaoke options are captured before asynchronous work. The exact captured model is passed to the download/inference job. Shared Whisper/FFmpeg tools may download first; these are not a different model.
- Android layout grid now uses an edge-to-edge thumbnail with favourite, available quality/duration/resume information and filename/size footer. Right-click or hold opens Play, Add to playlist, Favourite, Rename, Properties, Open Private Space and Delete. Rename and delete refuse the active file, confirm irreversible deletion, and maintain library references. Private Space opens the existing import flow; this is NOT Android's direct move-to-private operation.
- Home has a Rescan library button; its menu item is removed.
- Discover Home entry has a scale/fade route animation; microphone listening has animated bars. Both honour reduced-motion settings.
- User manual has separate left brightness and right volume vector illustrations, reusing the Android illustration drawing approach.
- Playing-video information adds available decoder pixel/colour/aspect/rotation, audio format/rate/channels, buffering and file-size data. Missing metadata is omitted rather than invented. Unplayed files show basic file properties; play to load decoder diagnostics.
- Native media opens are serialized and stale IPTV/channel requests are skipped. This reduces overlapping-decoder operations, but does NOT establish that a native IPTV crash is solved.

## Notifications and limitations
The desktop source has no notification permission request and no working Windows push registration/delivery transport. Android FCM is not automatically usable on Windows. This update does not invent permission success, add a misleading request, or weaken backend security. If a permission dialog appears in the installed build, its origin has not been identified here; Windows push remains incomplete.

No native Windows runtime is available in this workspace. Real trackpad/brightness rendering, switching streams/decoder crashes, model downloads/inference, Windows microphone and notification delivery are not certified by Flutter/Linux tests. This is not full Android or VLC parity. Direct move-to-private, pre-scanned codec metadata and complete native notification delivery remain outstanding.

## Apply from existing repository root
Place the script in the existing IntelliJ repository root, then run separately:

```sh
bash hyper_player_ui_input_correction.sh --check
bash hyper_player_ui_input_correction.sh --apply
bash hyper_player_ui_input_correction.sh --verify
git diff --check
```

The script is offline, embeds real file payloads, backs up changed files and refuses unrecognized edits. Review/commit/push, then run Windows desktop preview Actions on that commit. Download the full portable ZIP, not only its EXE.
