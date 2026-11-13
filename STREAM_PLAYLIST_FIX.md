# 1.0.1+75 — HLS mistaken for IPTV channels

## Confirmed fault
The public Mux test manifest at https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8 contains HLS quality variants named url_0/... through url_8/... . Those exactly match the screenshot. They are alternative qualities of ONE stream, not five TV channels.

Open Stream previously treated any URL containing .m3u as an IPTV channel list when its title was empty. The generic M3U parser ignored HLS tags and returned each relative variant path as a channel. The player then attempted to open that bare path in Android's app-private directory, explaining the empty host and “No such file or directory”. This is a confirmed playlist-routing/parser bug, not evidence that the free-channel catalogue or apple.com changed playback globally.

## Changes
- Inspect .m3u/.m3u8 response contents rather than assuming every such link is an IPTV list.
- Recognise HLS #EXT-X- tags. Master variants and media segments stay under the single network manifest; the player handles their quality/segment selection.
- Resolve IPTV channel and logo references against the fetched playlist URL, including its redirect chain. Network-list file/data channel entries are not accepted as local Android paths.
- Handle titled/saved playlist URLs consistently. Actual channel taps skip redundant list parsing and open their resolved network URL.
- Discard stale playlist results if the input changes; disable repeated play submissions while a playlist is loading.
- Provide explanatory errors for non-M3U responses, HTTP failures and failed/oversized playlist fetches. Website homepages are still not direct media URLs.
- Keep the free-channel catalogue, existing player, admin, analytics, movie notifications, and +74 APK/AAB workflows intact. No Firestore rule change is needed for this release.

## Apply / verify
Apply the single script from the +74 repository root, run the normal Flutter checks, commit and push. Both Android workflows remain on GitHub Actions; no local Android build was performed.

Install the CI-built +75 APK, then paste the ORIGINAL full test URL into Open Stream and press Play Stream. It should route to the player as one HLS stream, not list five Channel entries. If you previously saved the broken bare url_2/... entry, delete that entry using the existing saved-stream control and reopen the original full URL; this update does not invent a base URL for old invalid saved rows or erase your saved servers.

Also test a real IPTV M3U list (including a relative channel entry where available), an ordinary MP4 stream and a saved titled HLS link. Server/network restrictions and unsupported/DRM streams can still fail; no all-host playback guarantee is claimed. The Mux manifest was fetched and inspected during diagnosis, but native decoding on a real Android device was not tested here.

## Checks
Clean analysis; 281 Flutter tests and 24 admin JavaScript tests passed. Nine new regression tests cover HLS master/media classification, BOM, IPTV preservation, relative/parent/scheme-relative references, file/data rejection, HTML responses, final-redirect URL resolution and a local HTTP HLS fetch. No production records or signing secrets were changed. Source and installer checks are not a claim of a completed APK/AAB build.
