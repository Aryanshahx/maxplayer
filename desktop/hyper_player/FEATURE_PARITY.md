# Windows feature parity: work in progress
This release is NOT full Android parity. Do not advertise it as such.

## Implemented source (requires Windows CI and laptop verification)
- Existing media_kit video/audio playback and adaptive desktop controls.
- Local file opening, nonrecursive folder import, HTTP(S) stream URLs.
- Current queue, grid/list, library/player switching.
- Named playlists: save current queue, view saved entries, delete by name.
  Opening a saved playlist shows its entries; selecting an entry plays that entry.
  This does not replace the queue with the complete saved playlist.
- Persistent favourites toggle for current media and favourites browser.
- Persistent recent playback history (up to 300 distinct paths/URLs).
- Search filenames in current queue, history and favourites.
- M3U import from local file or HTTP(S), 2 MB/10,000-entry limits,
  relative-entry resolution. HLS manifest detected and rejected as channel list.
  No EPG, per-channel names/logos or IPTV grouping yet.
- External SRT/ASS/SSA/VTT subtitle loading and 0.5–4x speed selector.

Access new functions from the top-right menu and search icon.
Collections are local SharedPreferences data, not encrypted. Media is not uploaded.
Stream URLs may contain tokens and persist in queue/history/favourites/playlists;
never share preference files. Network hosts see your requests/IP.
No media file is deleted by playlist deletion or queue clear.

## Not implemented
Discover/TMDB/trailers, private vault, Windows Whisper transcription,
cloud authentication/provider import, NAS browsing, Quick Share server,
Android-like audio library, file operations/thumbnail indexing, AI assistants,
40-language desktop localization, detailed statistics, notification backend,
casting, Windows compact overlay, equalizer/dialogue boost/HDR-specific UI,
A–B/sleep controls and complete Android settings parity.
Existing placeholder actions remain explicitly marked as unavailable.
No real-money gaming or Gamezop integration.
No Firebase/admin parity claim. Android version/name and code unchanged.

## Release validation
Shell/config/source checks only performed here. Flutter SDK unavailable in this
workspace; tests are included for CI, not claimed passed. Run Windows desktop
preview workflow on updated main. Only install after analysis/tests/build succeed.
Verify each new function on Windows including missing files and malformed M3U.
Do not submit to Microsoft Store yet: installer, signing, licenses, privacy,
real screenshots and certification remain separate requirements.
