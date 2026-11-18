# Android visual alignment — first screen group

This update replaces simplified desktop dialogs with native full-page routes:
- History / favourites / source lists: Android-style app bar, back navigation,
  96x54 neutral thumbnail slots, compact rows, separators, remove and clear.
  History has Android's empty-state icon/message. No invented timestamps,
  resume progress or generated thumbnails: those data are not available yet.
- Playlists: Android card list, playlist icon/count/delete, New floating button,
  styled create dialog, grid detail page. Create optionally includes current queue;
  detail toolbar adds current queue, and items can be removed without deleting files.
- Open Stream: Android #14141C background, 17px title, protocol badges, rounded
  URL field with clipboard action, optional saved title, Play Stream, saved/recent
  rows and deletion. Saved titles/URLs persist locally without encryption.

PC-only adjustments: wider viewport, max stream content width 1100, responsive
media grids and existing desktop shortcuts. Native back navigation returns to Home.
Selecting media closes these routes and uses the existing native player.

Function limits are labelled rather than hidden. HTTP(S) and HLS media opening
remain supported; other protocol badges are muted with explanatory tooltips.
The Android LIVE TV catalogue is not implemented; its action is not falsely enabled.
Existing IPTV importer is accessible from the stream page. It remains a separate
import workflow, not Android's inline grouped channel browser.
History does not claim Android's resume-time data. Images remain placeholders.
No claim of complete pixel-identical design or full functional parity for all screens.
Discover, statistics, settings, audio/folders and other screens are not visually
redesigned by this first group. No browser preview update is included.

Home's Open files and Current playlist header buttons remain removed, even if
the earlier header-only patch was not applied. Ctrl+O and the Playlists tile remain.
No Android source/version/name, CI credentials or signing configuration changes.

Validation: Flutter 3.47.0 analysis clean. 17 tests passed on Linux, including
four widget regressions for History, playlists and stream URL validation.
Windows compilation and visual/playback checks still require Actions + laptop.
