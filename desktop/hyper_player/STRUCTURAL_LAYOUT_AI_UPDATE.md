# Structural layouts, playback/input correction, onboarding and opt-in AI

This update requires the previous `hyper_player_design_media_update.sh` delivery.
It changes only the separate desktop application. Android source/package/signing
and Android notification sender/rules are NOT modified.

## What changed

| Report | Implementation / actual limit |
|---|---|
| Thumbnails slow/missing | Persistent application cache; cached files checked before decoder queues;3 Shell lanes instead of one serial15s queue;5s handler deadline; skip queued work for scrolled-away cards; short failure cooldown; independent muted native-decoder frame fallback for Shell codec failures. Native Windows codec/performance behaviour is NOT certified. |
| Layouts were only presets | Android dashboard; Compact sidebar/icon-rail + library workspace without dashboard tools/banner; Cinema horizontal navigation + horizontal video shelves. Shared destination screens retain Android-adapted settings and inherited design. Not three independent rewrites of every destination. |
| Missing Display settings | Name, Date Added, File Size, Video Length in both directions, grid/list, folder grouping, queue-all/play-single, favourites, Android local accent palette, layout selector. Date Added = import order. File sizes populate asynchronously. Length uses decoded durations; unknown/unplayed durations sort last, not fabricated zeros. |
| Player opens blank/not instantly playing | Explicit play=true; allow windowed Video to attach for a frame before native open; stale-request checks; opening flag rebuilds reliably. Actual disk/network/codec latency cannot be guaranteed instant. |
| Unwanted brightness/sound button | Removed the dedicated edge button. B still opens optional sliders; swipe and keyboard control remain. |
| Welcome/use screens | Actual Android3-page welcome/how-to/player-guide port, desktop-corrected descriptions, separately persisted first-run flag. Guide completion saves before closing. Replay from Compact/Cinema navigation. |
| Double-tap fullscreen conflict | Both mouse and touch: left/right thirds seek; centre play/pause. Fullscreen is F or the fullscreen control, no longer double-click. |
| Windowed gestures | Mouse/touch drag allowed in the windowed surface, same settings/bounds as fullscreen. Trackpad wheel still controls volume; a trackpad is not treated as a physical multi-finger touchscreen. |
| Gesture shortcuts unclear | Player Settings shows equivalents beneath double-tap/brightness/volume/pinch controls; full shortcut dialog retained. B opens sliders, [ darker / ] brighter (video only), I zoom in / O zoom out, Z changes fit, Shift+arrows pans. |
| AI subtitles | Real local process pipeline: optional verified tool/model downloads, FFmpeg audio extraction, whisper.cpp inference, SRT generation and Load generated subtitles. Available in player overflow and Extras. Windows execution is integrated but not run in this Linux environment. |
| More powerful model | Base142MiB, Small465MiB, Medium1463MiB, all multilingual. Android source currently lists quantized base/base/small; Medium is a higher-capacity option, not an accuracy guarantee. Tools add about92MB download plus extracted files. No tool/model binaries are bundled in the installer. |
| Discover mic | Invokes Windows installed offline System.Speech recognizer/default microphone for up to10seconds, fills query and searches. Errors explain microphone permission/device/language prerequisites. Native recognition accuracy/support is untested here. |
| Discover AI | Ported Android free-model recommendation chain and title resolution against TMDB. Optional OpenRouter key entered in the dialog, retained only for that request; no key baked into this delivery. Without key/provider availability, catalogue matching is explicitly labelled NOT generative AI. No paid model fallback. |
| Home playback pop-up | Real thumbnail, live play/pause icon via playback notifier, actionable play/pause and completed-media restart. |

## Notifications — unresolved external integration, not a fake enabled switch
Android uses Firebase Messaging topic `all`. The old Firestore broadcast reader
cannot be reused: current rules explicitly deny `/broadcasts`, and admin-only
`/notices` is not a public feed. The Windows app does not currently have Android
FCM's native receiving service. This update does NOT claim working tray push,
background push when closed, notification permission/delivery or admin-targeted
Windows tokens. It does not weaken Firestore rules, embed service-account secrets,
add an inbox/bell, publish private/admin notices or pretend polling is FCM.
A supported Windows delivery channel plus sender registration/credentials (or an
explicitly configured web-push bridge) is still required. This item is NOT fixed.

## AI download and privacy details
- Choose AI subtitles -> model -> Download if needed & generate subtitles.
- Processing is local; no video/audio upload. Initial downloads contact GitHub and
  Hugging Face. Default audio stream is extracted to mono16kHz PCM; source language
  is detected automatically. Optional translate flag outputs English subtitles.
- Downloads are streamed to partial files, size/hash checked, then atomically
  renamed. Cached models/archives are hash checked again before reuse. Archives
  reject traversal/symlink/oversize entries; extraction is off the UI isolate.
- Whisper executable/DLLs and FFmpeg are extracted from verified archives. Generated
  SRT is saved under app support/local-ai-v1/subtitles, not beside/over the source.
- Cancel terminates the current child or network request. Archive preparation may
  finish before cancellation is observed. Temporary job audio is removed; successful
  SRT and cached models/tools are retained. Failed jobs never replace media files.
- Full-film PCM audio and larger models need considerable free disk/RAM. CPU
  transcription may take longer than the film. Recognition is not guaranteed.
- Sources pinned: whisper.cpp v1.8.3 x64 release (MIT), Gyan FFmpeg7.1.1 essentials
  ZIP (GPL build), ggerganov/whisper.cpp ggml-base/small/medium weights (Whisper MIT).
  SHA256 digests are in `lib/player/local_ai.dart`. Downloaded code is third-party
  executable code; use trusted OS policies. Neither model weights nor those tools
  are included in this source patch or the portable application's assets.
- API keys are not a substitute for a trusted backend. Do not distribute a funded
  private API key in a compiled app. This update leaves the Windows workflow key
  handling unchanged; optional recommender key is entered locally, never in chat.

## Tests and remaining checks
New tests cover layout compositions/navigation/narrow rail, onboarding completion,
sort order/unknown metadata, accent persistence, AI result parsing, real loopback
verified-download/cache/tamper/partial cleanup, cancelled downloads, unsafe archive
rejection, windowed mouse double-click seek/no-fullscreen, windowed drag brightness,
and removal of the dedicated brightness button. Previous regressions remain.

Linux analyzer/unit/widget tests are not Windows end-to-end evidence. Both Windows
ZIP archives were separately downloaded and audited for exact hash/expected
executable entry, but their executables were NOT run here. Native thumbnail speed,
first-frame latency, microphone, long-film inference/cancellation, audio mixer,
HDR/effects, mini-window behaviour and rendered DPI/layout need a new Windows build
and real media. Notifications remain unresolved as described above.
