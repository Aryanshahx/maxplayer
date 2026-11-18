# Android visual alignment — Video fit and Subtitle delay

Reuses Android player sheet visual language from player_screen_impl.dart track/
extras sheets: surface background, rounded22 top corners, handle, 18px semibold
heading, 16px option names, secondary labels and checked-circle selection.
Android fit itself cycles modes, not this exact panel. These are PC-specific
panels styled consistently with Android, not claims of pixel-identical screens.
No matching dedicated Android subtitle-delay sheet was present in the inspected
player source; existing Windows timing functionality is retained and restyled.

Video fit replaces SimpleDialog; Fit/Crop/Stretch callbacks still set the same
BoxFit values. Explanatory subtitles and current-mode check added. Android's
16:9/4:3/Original modes are explicitly noted as unimplemented, not fake options.

Subtitle delay replaces generic askText dialog. Signed whole-millisecond input,
-60000..60000 validation, 100ms steps, reset-to-zero and Apply. Positive = later.
Existing native mpv sub-delay property uses seconds conversion unchanged.
Backend errors stay in the sheet, allow retry, and do not falsely report success.
Input starts blank because current backend delay is not queried. Reset edits
input only; Apply sends it. No new preference persistence or live sync claimed.

PC sheets width capped at1000, scroll-safe and keyboard-inset aware. Previous
screens, Home header, Android app, CI/signing and playback backend preserved.
Full Android playback/settings feature parity is not claimed.

Validation Flutter3.47 analyzer clean, all55 tests pass on Linux including four
fit/input/step/failure tests. Native Windows fit rendering and subtitle timing
still require Actions + laptop checks with actual video/subtitle media.
