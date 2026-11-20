# Latest correction boundary

See **STRUCTURAL_LAYOUT_AI_UPDATE.md**: three structural library compositions, optional downloadable local speech pipeline, Android onboarding, input/thumbnail/mini-player corrections. Windows notifications are NOT implemented; native execution/performance needs Windows validation. This section supersedes conflicting older claims below.

# Consolidated Windows update — implementation and verification status

Prepared 2026-09-05. Starting desktop baseline:
`ec10d8eb96993f03c9d327f87324f3d86f0feb54`.

## Latest media/design correction
**DESIGN_MEDIA_UPDATE.md** supersedes older rows for the new Home Open File button,
video/audio separation, saved-playlist vs playback-queue behaviour,3design presets,
all-local-drive scanning choice, illustrated manual, moving Discover background,
brightness/volume shortcuts, karaoke and native Enhance/HDR property integration.
These implementations are NOT a native Windows validation/whole-app parity claim.

## New player/input/scanning follow-up
Read **PLAYER_FOLLOWUP.md** for the latest changes. Its more specific status
supersedes the original rows below for gesture settings, recursive selected-root
scanning, sleep badge, hover decoder, Windows mini-player and system wireless-
display chooser. These integrations are not proof of native Windows acceptance.
The original all-features/native-release caveats still apply.

## Read first
This delivery consolidates the desktop work into ONE root-applied script. It does
**not** mean all Android features are implemented or visually/native verified.
Unimplemented requirements below remain real gaps, not successful integrations.
Android source/package/signing/version are not included in the update payload.

## Implemented in source, Linux checks available
| Area | Included behaviour | Verification boundary |
|---|---|---|
| Home/library | Eight Android-organised tiles; existing Home Search/Rescan/menu; local-thumbnail hookups throughout applicable collections; no Home Open files/Current playlist header buttons | Shell thumbnail extraction/codec coverage and exact desktop visual parity need Windows review |
| Display Settings | Saved grid/list, name sorting, queue-order view, folder grouping, favourites filtering, Queue All/Play Single; failed-save feedback | No file-size/date-added/duration sort. View operations preserve actual queue indices and playback order |
| Video player | Android-adapted overlay, transport, timeline, mute/volume, queue, six fits, shuffle/repeat traversal, speed, sleep/until-end, A–B, control lock, track/subtitle entries, screenshot and EQ/filter hooks, saved resume/autohide settings | MPV properties, frame capture, actual track switching, fullscreen and input focus are not verified on a Windows laptop |
| Audio player | Separate audio composition, transport, timeline, queue and repeat/shuffle | No full embedded artwork/tag database or Android audio-service integration |
| Discover | Cinematic components, Android rail definitions, paged category route, details/cast/provider/review/season/episode metadata, bundled fonts and conservative local-file match | API/images/trailers need live Windows check; not all Android recommendations/voice/AI interactions are implemented |
| Manual/About/Privacy | Five-section Android-adapted manual with PC input diagrams; developer About; truthful desktop Privacy | Source/widget checks do not prove pixel-identical layouts at every DPI/window size |
| Playlists/history/search/folders/statistics/language | Existing separate screens retained with broader thumbnail coverage; known-library scope, saved collections and UI-language route | Full Android action/translation/metadata/onboarding parity is not certified |
| Cloud Storage | Windows/provider picker copy, progress/cancellation, local imports, save-copy action | Not cloud OAuth/API integration; provider hydration and uninstall behaviour need Windows check |
| Network Storage | Persisted validated locations; UNC direct-directory browsing through existing Windows session; direct HTTP(S) files | Not an authenticated SMB protocol client, FTP/FTPS client or full WebDAV browser |
| Quick Share | Consent, selected files, random-token temporary HTTP server, manifest/browser page, receive picker, progress/cancellation, safe names/no-overwrite handling | Real Linux loopback tests only; Firewall/LAN/VPN/mobile/native interoperability pending; no native other-app sharing, discovery, QR or resume |
| Private Space | Windows-only experimental password + CurrentUser DPAPI-wrapped AES-GCM encrypted-copy store; authenticated chunks/metadata, lock/cancel, export/delete, no reset bypass, setup race protection | Test protector in Linux tests is NOT DPAPI verification. No in-app playback. No security audit, guaranteed secure deletion, malicious same-account race protection or portable recovery |
| Workflow | Existing Windows preview workflow retained with generated-runner branding; analyzer/tests/build/artifact stages | Workflow has NOT been remotely triggered or passed as part of this delivery |

## Explicitly incomplete / unavailable
- Safe in-app encrypted-vault playback and full native lifecycle/recovery testing.
- Whisper/AI subtitle generation/model management, karaoke timing/rendering.
- Chromecast/DLNA receiver discovery/control; native validation of the Windows wireless-display launcher and always-on-top mini-player.
- Verified HDR tone mapping/video enhancement and full advanced player preferences.
- FTP/FTPS, direct app-managed NAS credentials, complete WebDAV browsing.
- Cloud account OAuth/API integrations; native other-app sharing/discovery/QR/resume.
- Complete Android metadata sorting, onboarding, Discover voice/AI/local-watch
  recommendation interactions and every screen/action/translation detail.
- Windows installer/signing/Store certification. No EXE/MSI installer is generated.

## Storage security specifics
Private Space copies rather than moves originals. Password length 12–128;
PBKDF2-HMAC-SHA256 (600000 iterations in production) password wrapping plus Windows
CurrentUser DPAPI; AES-256-GCM with per-file keys, encrypted metadata and 1MiB
bounded chunks. Sensitive key input is sent over stdin to system PowerShell, not
command arguments. Whole-operation timeout and bounded response handling are used.
Files are limited to 100GB each. File count/size/timing and ordinary filesystem
metadata are not a claimed secrecy boundary. The vault is not protection against
malware running as the same account, process-memory inspection or all filesystem
races. Backup loss/account loss/password loss can make copies unrecoverable.
Stale setup.lock fails closed; no automatic recovery/removal bypass is provided.
Plaintext export is explicit, not secure deletion or encrypted playback.

Quick Share is link-access-controlled plaintext local HTTP, not authenticated
end-to-end encryption. Session Stop/expiry/closing ends hosting. Current Android
Receive does not preserve Windows token paths; use Android browser for that
transfer direction. Never expose the port publicly or use sensitive media on an
untrusted network. No session links are saved in application preferences.

## Checks performed during preparation
- Flutter/Dart formatter, analyzer and unit/widget suite in Linux. See the final
  test count and SHA-256 in the delivery guide accompanying the script.
- Loopback HTTP tests use a real Linux HTTP server/client, separate from widget
  HTTP mocking. No LAN or Windows runtime success is inferred.
- Vault corruption, original preservation, no-overwrite, cancellation, setup
  concurrency and lock-during-setup; gate/recovery UI tests. Tests use a deliberately
  test-only identity protector and lower KDF cost, never used by the production UI.
- A Windows-only DPAPI nonsecret-fixture smoke test is added for the NEXT Windows
  workflow run; skipped during Linux testing. This is not a security audit.
- Installer script is checked on a clean baseline, with rerun/verification and
  conflict refusal. Payload is desktop files plus the Windows workflow only.

## Windows acceptance checklist — NOT YET PASSED
1. Run the Windows workflow with the existing Discover secret. Download/extract
   the whole portable ZIP; launch on Windows 10/11 x64 without a development SDK.
2. MP4/MKV/AVI and audio fixtures; corrupt/missing/changed files; slow or large
   chosen folders; Shell thumbnail unsupported-codec fallback and cache refresh.
3. Multiple audio/subtitle tracks, external subtitle file/offset, rate, all six
   fit modes, fullscreen, screenshot save, EQ/dialogue boost reset/failure paths.
4. End-of-file Queue All/Play Single, repeat/off/all/one, shuffle/previous history,
   A–B validation, sleep timer/until-end, resume and persistence after clean exit.
5. Grid/list/filter/sort/group at narrow/wide/high-DPI sizes; mouse/keyboard focus,
   control lock/Escape, modal navigation/back, audio/video player transitions.
6. Offline/live Discover, category retry/paging, seasons selection/stale requests,
   local-match false positives, image fallback, external trailers/providers.
7. Windows picker/cloud hydration/cancel/disk-full and save-copy errors; UNC share
   authenticated/disconnected/unreachable; HTTP/M3U failures with no credentials
   leaked in diagnostics.
8. Quick Share Windows Firewall consent, trusted LAN two-device send/receive,
   Stop/expiry/cancel/interruption/file-change, Android-browser transfer direction.
9. DPAPI smoke test, actual Private Space create/restart/unlock/import/export,
   wrong password, lock/minimise/close during operations, corruption and missing
   key, original retention, explicit plaintext export, uninstall/reinstall/key
   backups. Keep independent original copies throughout testing.
10. Confirm Android-only paths are unchanged. Build Android only through existing
    Actions if desired; the update script never runs a local Android build.

A passing Actions build is a compilation/automated-test check, NOT completion of
this native acceptance checklist. Do not label this preview production-ready,
secure/audited or full Android parity on that basis.
