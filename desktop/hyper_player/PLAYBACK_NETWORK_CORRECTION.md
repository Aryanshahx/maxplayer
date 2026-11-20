# Playback / import / TLS / network / Android UI correction

Requires the delivered `hyper_player_structural_ai_update.sh` baseline. Only the
separate desktop app and Windows preview workflow change. Android source, version,
package, signing, backend rules and notification sender are preserved.

## Exact changes

### Imports, input and playback
- Rescan additions use a set rather than repeatedly searching the whole queue
  (previously quadratic for large libraries). Scan UI updates are throttled200ms.
  Queue JSON encoding and imported-path sorting are off the UI isolate. This removes
  identified expensive work; native file picker/codec/disk stalls are not claimed
  eliminated without a real Windows large-library run.
- Vertical gesture side is fixed from pointer-down in the actual video surface,
  not inferred later from an ancestor's dimensions. Left = video dimming, right =
  app media volume, windowed/fullscreen. Brightness is NOT Windows monitor backlight.
- **Page Up = brighter; Page Down = darker. + / − = zoom in/out** (main keyboard
  equal/plus key and numpad add/subtract supported). Old bracket and I/O mappings
  are removed. B opens optional sliders. Z loops Fit/Crop/Stretch/16:9/4:3/Original.
  The frame/controls subtree stays structurally stable across forced-aspect modes
  so changing fit no longer recreates focus/gesture state. Fit button remains.
- Software volume uses the player's `volume`, never a Windows master-volume API.
  Per-app volume is saved; drag updates are coalesced rather than flooding native
  property locks. Shared audio mode is requested. The OS device/per-app mixer can
  still limit output; this is not a native audio-device certification.
- Hover preview debounce90ms and bounded48-frame/12MiB session LRU cache reduce
  repeated decoder work. Cold decoder startup/seeks can still take time. No main
  playback seek is used to fake preview frames.
- Android-like gesture icon/text feedback remains. Player Settings/manual/sliders
  now describe the new shortcuts.

### AI subtitles — only in Extras (user selected)
- Removed all three-dot AI subtitle entries. The only launcher is player Extras ->
  AI subtitles. No AI launcher is added inside the subtitle-track screen.
- Language/autodetect, translation to English, word-flow/karaoke output and model
  choice now persist. Android Fast quantized base (~57MiB) joins Base/Small/Medium.
  Language and short-word-cue switches are passed to the real inference command.
- On Dart TLS HandshakeException, Windows downloads retry through the built-in
  System32 curl HTTPS client/Windows trust store. HTTPS-only redirect restrictions,
  certificate validation and model/tool SHA256 checks remain mandatory. There is
  NO accept-all certificate callback, --insecure, -k or revocation bypass.
- Windows fallback shows downloaded MB and supports Cancel. If the OS trust store,
  clock, proxy, antivirus inspection root or network is also broken, download still
  fails safely; do not disable certificate checks. Fix trusted roots/clock/proxy
  with your Windows administrator. Successful secure download/inference still
  requires a native Windows run; Linux tests do not reproduce your certificate chain.
- Models/tools still download only on demand. No model/engine is bundled in the
  installer. Existing verified downloads are reused; source video is never uploaded.

### Android UI / branding
- Actual Android app icon is bundled for Welcome; a multi-resolution ICO is copied
  into the generated Windows runner by Actions (EXE/taskbar icon, not just Flutter).
- First-run Welcome/How to use/Player guide stays the Android-derived flow. Existing
  seen state is respected; an update does not pretend to be a new installation.
- Replay Welcome guide buttons removed. Compact Display Settings uses the same
  tune icon as Android/default navigation, not a different dashboard icon.
- Removed flag emoji which appeared as literal IN on Windows from Home/Welcome;
  normal developer wording remains.
- Home grids now show filename plus extension, asynchronously available size and
  known decoded duration. Cinema shelves get the metadata line too. Unknown lengths
  are not fabricated. Metadata extraction for every unplayed file is not implemented.
- Accent now visibly drives icon/slider/switch/progress themes, not only ColorScheme.
  Hard-coded movie artwork/player contrast colours remain intentionally readable.
- System-scan button removed from Folders. Scanning is available from Home menu ->
  Rescan library; existing Folders refresh and Add folder remain.

### Network, streams and sharing
- Network Storage has an i/help button and FTP/FTPS session entry. Explicit FTPS
  (TLS on port21) is default; plain FTP requires switching TLS off and is insecure.
  This is NOT SFTP or implicit FTPS. Credentials remain in-memory and go to curl via
  stdin, not process arguments or saved locations. TLS validation is not disabled.
- FTP directory browsing and download-before-play use the Windows transfer tool.
  Remote files download to temporary app cache; no authenticated streaming URL is
  written to history.5GiB per-file and listing/time limits protect storage/memory.
  Cancellation kills the transfer. Temporary completed media persists until cache
  cleanup. Actual FTP/FTPS server interoperability needs Windows testing.
- Open Stream probes HTTP(S) responses: extended M3U channel playlists open a named
  channel list; HLS master/media manifests remain one playable stream. Binary/direct
  media links play directly. Relative channel URLs resolve after redirects. Web pages
  fail with a clear message rather than masquerading as media. Probe size2MiB,
  channel limit10k, bounded timeouts. RTSP/RTMP(S)/UDP/RTP go directly to the native
  player without an HTTP probe. Not all protocols/codecs/devices are certified.
- This does NOT bypass DRM, subscription logins, expired links, provider geo-blocks,
  or arbitrary websites. Provider-specific channel headers/EPG/accounts are not a
  claim of full Android IPTV parity. Failed range probes can still fall back to native
  playback. Playlist content must be accessible under the supplied URL.
- Quick Share -> Via other apps invokes native Windows file sharing via share_plus
  for selected local files. Installed share targets decide what they accept/send.
  Direct send/receive are retained. Native share-sheet operation needs Windows testing.

### Discover, AI and partner links
- Main title opening has a fade/slide transition. Mic adds currently loaded catalogue
  titles as grammar hints and gives an editable confirmation before searching. The
  installed Windows recognizer/default input/language still determines accuracy.
- AI button is labelled AI. The suggestion screen and Ask AI movie screen are ported
  from actual Android sheets (prompt chips, layouts, result/history presentation),
  not disabled placeholders. Local catalogue/movie-data fallback is explicitly
  labelled NOT generative AI; it must not be represented as a real model answer.
- Windows Actions now passes optional OPENROUTER_API_KEY alongside TMDB_API_KEY,
  matching Android's existing configuration approach. Without an available key/model,
  online generative AI cannot work and falls back honestly. Model IDs are free-tier;
  rates/availability remain provider-controlled. No new paid hosting/backend is added.
- IMPORTANT: dart-define API keys become extractable from a distributed client.
  Use only a restricted/free-service key; never embed service accounts or privileged
  credentials. A protected backend is needed for strong production secret protection.
  Do not paste keys into chat. Workflow temporary define file is removed after build.
- Cloud includes the actual pCloud referral https://partner.pcloud.com/r/157632 with
  Partner link disclosure. Prime availability restores the Android tagged Amazon
  link (maxplayer0a-21), with Associate disclosure, when provider data confirms Prime.
- Removed Provider listings · India button. Provider names remain useful information.
  Removed repeated per-card/detail attribution; one Discover footer retains required
  TMDB/availability credit. Attribution is not removed altogether.

## Still unresolved: Windows notifications
Android FCM is not a Windows native receiving service. Existing /broadcasts reads
are explicitly denied; /notices is admin-only. No insecure public feed, weakened
rules, embedded service-account credentials or fake notification toggle was added.
Working background delivery requires a provisioned Windows push channel + sender
or explicitly configured web-push bridge. This update DOES NOT fix Windows push.
No Windows receiver registration/credentials were provided or deployed here.

## Verification boundary
New tests exercise both-side gesture routing, new keys, two full fit loops, secure
Windows download argv/no TLS bypass, actual inference flags, real loopback HTTP
IPTV/HLS/media/web-page detection, quoted playlist metadata, allowed URL schemes,
FTP config-injection rejection, Android AI/settings sheets, pCloud disclosure,
bundled PNG and reactive accent controls. Existing tests remain.

Native Windows certificate fallback, FTP/FTPS transfers, file sharing, recognizer,
large imports, first-frame/preview latency, renderer brightness, app-volume isolation,
model execution and actual link/provider availability need a new Windows build and
real-media testing. No native success or complete feature parity is asserted here.
