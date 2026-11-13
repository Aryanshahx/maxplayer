# 1.0.1+70 — feature-open graphs, app theme and app-error diagnostics

## Dashboard
- Eight feature metrics in the activity selector and side-by-side horizontal comparison: Discover movies, Private folder, Folders, Playlists, Audio, Network storage, Cloud storage and Quick Share.
- These are screen opens from the library/banner/quick tiles, counted after an interstitial gate proceeds. They are NOT unique users, unlocked-private-folder counts, playback minutes, successful transfers or completed searches. They start from +70; historical feature counts cannot be invented.
- Streams and IPTV cards move below the primary cards (including videos/registrations). Ad-impression and play-failure cards are removed, including from feature mix and PDF metrics. Legacy counters are not destructively erased.
- Streams and IPTV remain separate because they count different entry points (direct stream opens vs IPTV channel plays), not separate engines. Their counters can describe overlapping behaviour and must not be summed as unique users.
- Match lib/theme.dart: true-black background #060608, surface #101013, borders #26262c and the app's DEFAULT white accent. App users can customise their phone accent; this static administrator site does not read an individual phone's accent preference.
- No notification history, bell, inbox or notification switch is reintroduced.

## Diagnostics: distinguish player failure from app failure
- Playback failures no longer upload reports from the player failure dialog. The dialog still lets users copy a useful report; the hard-coded '+64' is replaced with the actual app build tag. A '+64' label in previous reports did not reliably identify the installed APK.
- Flutter framework errors and uncaught Dart errors are captured separately from ordinary CrashLog.error playback/network logs. The new crash.last file stores a bounded error description, stack, timestamp, random report ID and fatal flag synchronously.
- Framework errors are labelled nonfatal because Flutter can recover from them; an error does not prove process death. Uncaught Dart errors are separately labelled.
- The latest saved app-error report is uploaded when Firebase is ready, immediately for a captured framework error where possible, or on next launch. It is cleared only after successful acknowledgement. A stable random report document ID avoids creating another report for the same saved record. An acknowledgement lost at process death can leave the local retry record even though the server has the report; existing create-only rules may reject the retry, but no additional duplicate document is created.
- Generic player errors cannot overwrite the dedicated app-error record. The panel/PDF filters out player_fail reports and shows expandable captured error/stack details and app version.
- The panel checks the newest 100 reports in the existing collection, then filters to app errors. No new Firestore index/rule change is required. Very old reports outside that window may not appear.
- This is NOT full native crash/ANR coverage. OS kills, native MPV/FFmpeg crashes, out-of-memory termination or a process dying before capture/flush can prevent reporting. Only one latest pending local report is retained, not an unlimited crash journal. No promise of 'every crash from every device' is made. Reports arrive in the admin panel, not by email or an administrator push alert.

## Playback investigation remains open
'Failed to recognize file format' from unified-streaming.com alone does not reveal what was downloaded. An HTML page, redirect/authentication response, inaccessible resource, DRM or unsupported media can all require different fixes. A complete PUBLIC failing media URL and reproduction on the current APK are needed before changing engine/network behaviour. Do not submit signed/private URLs, passwords or tokens. This update fixes the stale report version string, not an unverified stream-decoding cause.

## Apply
Run the script from the +69 repository root. Use the usual Flutter check/commit/push commands. Wait for GitHub Pages and CI, install the +70 APK, then open the eight features and refresh the panel. Website-only updates cannot make old APKs record these new counters. Existing country sampling, Firebase rules/secrets and GitHub sender remain unchanged.

## Tests
No analyzer issues; 265 Flutter tests and 19 Node tests passed. Added tests cover the eight feature keys, persistence of a stack-bearing app error, protection against ordinary playback logging overwriting that record, and safe clearing. Browser checks with mocked Firebase/GitHub cover graph selectors/comparison labels, app background colour, removed metrics, filtering playback reports, login, sending, country separation, responsive layout and PDF. Live error upload and device playback still need integration testing. No local APK build is claimed; CI/toolchain files are unchanged.
