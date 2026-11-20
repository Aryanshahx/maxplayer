# Current playback/network correction

Read **PLAYBACK_NETWORK_CORRECTION.md** first: current shortcuts, secure AI download fallback, Android AI/settings restoration, import/gesture fixes, stream/channel detection, FTP/FTPS, sharing, branding and native verification limits. Windows push notifications remain unresolved. This supersedes conflicting older sections below.

# Latest correction

Read `STRUCTURAL_LAYOUT_AI_UPDATE.md` first for structural layouts, input/thumbnail corrections, onboarding, optional local AI and the unresolved Windows notification integration. Older docs describe earlier snapshots.

# Hyper Player - All Formats — consolidated Windows preview

Separate Flutter desktop project by Hyper Tech Labs. Android package, source,
signing configuration and version are not changed by this update.

**This is an unsigned Windows preview, NOT full Android feature parity or a
security-audited release.** Read `DESIGN_MEDIA_UPDATE.md`, `PLAYER_FOLLOWUP.md` and `CONSOLIDATED_STATUS.md` before building or using
Private Space. The application name is not a guarantee of every codec/format.

## Build and launch
1. In the repository, run the **Windows desktop preview** Actions workflow.
2. Keep the existing repository Actions secret `TMDB_API_KEY` configured for
   Discover. Never paste credentials into chat or source. The workflow fails if
   this secret is absent. Client-side API credentials cannot be considered secret
   from a person inspecting the built application.
3. Download `Hyper-Player-Windows-x64-preview` from the successful run. Extract the
   artifact ZIP and the portable application ZIP completely. Run `hyper_player.exe`
   on Windows 10/11 x64 with every DLL and the `data` directory beside it.
4. Do not run inside the ZIP or copy only the EXE. This is not an EXE/MSI installer,
   a signed release, an MSIX package or a Store submission.

The workflow generates a Windows runner, applies product branding, runs analyzer
and tests, then builds. Source checks in Linux do not prove that workflow succeeds
or that Windows playback, Shell thumbnails, fullscreen, filters or networking work
on a particular laptop. A Windows-only DPAPI fixture smoke test is included for the
next Windows run; it has not been executed in the Linux preparation environment.

## Usage
- Home now has Search, Open File and the three-dot menu. System scanning is in Folders -> Scan system / folders. Its eight tiles open Private
  Space, Playlists, Folders, Audio, Network Storage, Cloud Storage, Open Stream and
  Quick Share. No Open files/Current playlist buttons in the Home header.
- **Ctrl+O:** open files. The empty-library action also opens the picker.
- **Ctrl+L:** open a direct HTTP(S) stream. A web page is not necessarily playable.
- Folders/rescan include accessible subfolders of chosen folder/drive roots. Add every drive root you want scanned; progress/cancel and partial-result bounds apply.
- Display Settings saves three app-wide design presets, grid/list, name sort, folder grouping, favourites filter
  and Queue All/Play Single. View sort/filter/group never remove/reorder the actual
  playback queue. Play Single stops automatic advance including queue repeat;
  manual next/previous still work.
- The player has Android-adapted video controls and a separate audio composition.
  Player Settings now ports the Android gesture/hold/zoom/sound/playback sections and includes a keyboard manual. See PLAYER_FOLLOWUP.md for the Windows mini-player, wireless-display launcher and local timeline-frame decoder integration; native validation is pending.
- Discover provides metadata, external trailers and conservative local-library
  matching, not full movie/episode streaming or downloads.

## Important storage and privacy boundaries
- Queue paths/URLs, history, favourites, playlists, settings and saved network
  location metadata are stored locally **without encryption**. Avoid saved signed
  URLs or credentials. Local thumbnails use Windows Shell handlers; placeholders
  remain when a matching handler/codec is missing.
- Network Storage uses existing Windows-authenticated UNC sessions and explicit
  HTTP(S) file locations. Sign in using Explorer. No app SMB password storage,
  FTP/FTPS client, LAN scan or full WebDAV directory browser is provided.
- Cloud Storage copies files exposed by the Windows/provider picker. It does not
  implement Google Drive/OneDrive OAuth or cloud account APIs. Copies are local
  and unencrypted; save an external copy before uninstalling or clearing app data.
- Quick Share uses **unencrypted local HTTP**, explicit selected files and a
  temporary random session link (maximum 15 minutes). Anyone holding a reachable
  link can download the selected files. Use trusted networks, Stop when done and
  never publicly share session links. Current Android native Receive strips the
  Windows token path; open the Windows link in the Android browser instead.
- Private Space creates experimental encrypted **copies**; originals remain
  outside the vault and may remain visible in the ordinary library. It requires
  the password, vault key files and original Windows account protection. There is
  **no password reset bypass**. Export writes plaintext. In-app private playback
  is disabled; no private thumbnails/history are generated. Do not keep the only
  copy of important media there. It is not independently security-audited.
- Discover/streaming/explicit sharing contact their hosts; host/provider privacy
  policies apply. This desktop project does not integrate Android advertising,
  Firebase analytics or push notifications. Language selection changes UI only,
  not spoken media or subtitles; not every new string is translated.

## Before using as a release
See the runtime checklist in `CONSOLIDATED_STATUS.md`. Native Windows verification,
installer generation, trusted code signing, version-specific HTTPS distribution,
licence review and Store certification are still separate work. No paid service,
Firebase Storage or Android build is required by this script.

Support: techlabs.hyper@gmail.com
