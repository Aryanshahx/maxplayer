# Max Player user manual

## Start and permissions
Open the app and grant the media access you want it to have. Android version and selected-media permissions affect which files can appear. Use the Home rescan button or pull down to refresh after copying or downloading files. A scan is not a guarantee that Android exposes every folder. Check permission and file format if something is missing.

Notification permission is separate from media permission. You can deny it or change it in Android app settings. Notices appear in Android's notification tray, not an in-app inbox. Voice search uses the installed Android recognition service and needs microphone permission when requested; the service may process speech online.

## Home and library
- Tap a video to play it; long-press for available file actions.
- Use Search to filter. Up to three recent searches are saved locally per category; recall or clear them in Recent searches.
- Display Settings controls grid/list layout, sort order, folder grouping and favourite filtering.
- History lists recently watched media; resume restores saved progress when enabled and available. Missing or moved files may not reopen.
- Playlists organise references to local videos; they do not create backups of those files.
- Folders depends on Android storage access. Use Android's picker where offered to open a document from a storage provider. A provider can require its own sign-in.
- Watch statistics shows locally tracked viewing information, not all viewing outside this app.
- Quick tiles include Private Space, Playlists, Folders, Audio, Network Storage, VPN, Open Stream and Quick Share. Swipe shortcut pages where applicable.

## Appearance and custom accents
Open the menu → Appearance to choose System default, Light or Dark. Open Display Settings → Theme accent color for one colour-spectrum slider, not separate RGB channels or preset buttons. Slide or use the focused slider with your remote/keyboard to choose a hue.

The selected-colour swatch and selectable #RRGGBB text update live. “Theme accent” shows the contrast-adjusted colour actually used in the current theme; this may differ from the selected hex to keep text readable. The saved choice is restored after restart. Existing custom RGB/preset colours remain until you move the new slider; the single slider chooses hues, not independent saturation/brightness or every possible RGB combination. No hex typing is required: this is a live preview, not an editor.

## Player
Tap the picture to show or hide controls; auto-hide timing is configurable. There are no top/bottom covering panels or gradient bars in either theme; only controls are drawn over the picture. Video and letterbox areas remain media content, not theme surfaces.

- Use play/pause, previous/next and the seek slider where the media supports seeking.
- Tap the speed control for presets or a slider; the selected speed can be remembered.
- Fit modes change cropping/stretching. Crop can cut off picture edges; Stretch can distort.
- The queue panel changes or removes queued items. This is not file deletion.
- Audio/subtitle controls select tracks supplied by the file or stream. Not every source has multiple tracks.
- The equalizer has audio presets, dialogue boost and tone-mapping controls. Actual support depends on the decoder and source.
- Use A→B loop to set the start and end of a repeat section; clear it to stop looping.
- Sleep timer pauses playback at the selected time or, where offered, end of media.
- The menu offers technical video information, screenshot and picture-in-picture where supported. Screenshots save to Pictures/Max Player; stream/protected content and backend limitations can prevent capture. Verify the saved image before relying on subtitle capture.
- Picture-in-picture depends on Android device support and permission. Cast/external playback requires a compatible installed receiver/player; it is not a guarantee of native Chromecast support.
- Player settings control available gestures, seek interval, boost speed, resume, auto-hide and lock-button visibility.

### Touch gestures
- Double-tap left/right: seek backwards/forwards by the configured step.
- Double-tap centre: play/pause.
- Swipe vertically on the left: app brightness; the previous brightness is restored on leaving playback.
- Swipe horizontally: seek; while zoomed it can pan instead.
- Pinch with two fingers: zoom and pan within the supported range.
- Hold: temporary playback-speed boost; release to restore speed.
- Screen lock suppresses ordinary player interactions. Use the unlock gesture on the lock control; it is not Android device security.

Gestures can be disabled in player settings. Live streams may not support seek or speed changes. Codec, resolution, HDR, 4K/8K and smoothness depend on the device, decoder, file and network.

## Discover movies and series
Discover uses TMDB for artwork and metadata; initial requests need internet. Cached artwork is not a complete offline movie catalogue. The featured carousel and movie cards open details. The Play action can use a matching local library item or an available external source; Discover is not a subscription streaming library and does not guarantee a full playable film.

Trailers depend on their providers and availability. Language/season options only appear when available. Ask AI recommendations submit the prompt you choose to OpenRouter and its selected provider. Do not submit secrets or private media. Do not confuse online recommendations with on-device subtitle processing.

## VPN — optional, off by default
1. Open VPN and read the prominent disclosure and provider terms.
2. Accept only if you want to proceed. Opening the page does not automatically connect.
3. Choose WARP/WireGuard, Riseup, VPN Gate/OpenVPN or a trusted supported custom profile.
4. Keep Max Player only routing, or explicitly choose full-device routing.
5. Tap Connect and approve Android's VPN permission. Wait for the actual connection status; check exit information when available.
6. Disconnect in VPN when finished.

Only one Android VPN can be active. Provider provisioning, public/volunteer servers and custom profiles may fail or be unavailable. No country choice, speed, anonymity or permanent free availability is guaranteed. Max Player does not operate the exit servers. Operators receive connection metadata and routed traffic and can see unencrypted traffic. Use HTTPS and trusted providers.

There is no in-app kill switch. Ordinary connectivity can return when the VPN disconnects. Android always-on/block-without-VPN controls, if supported for the selected engine/device, must be configured separately and can block local sharing. App-only routing does not cover other apps; full-device routing changes other traffic too. Real routing should be checked on your device, not inferred only from a status badge.

Custom VPN secrets use Android Keystore-backed encrypted no-backup storage where supported; when secure storage is unavailable they remain session-only. Delete a custom profile to remove it locally. Clearing app data removes app-local profiles and preferences. WARP registration contacts Cloudflare; Riseup provisioning and VPN Gate directory requests contact those services. Read the privacy policy before use.

## Network Storage
Choose SMB, FTP/FTPS or WebDAV. Enter the host, port if needed, direct media path and optional username/password, save, then select the connection. This feature stores direct media connections; it is not a complete remote directory browser. Protocol support depends on the URL, server and native playback backend. Prefer encrypted protocols where supported.

**Network Storage credentials are in app-local preferences, not the VPN encrypted store.** Use limited-access accounts and trusted devices/networks. Delete a saved location to remove its entry. Do not share diagnostic exports without checking for sensitive hostnames or contextual error information.

## Open Stream and IPTV
Paste a direct supported media URL or load a supported M3U playlist. A website page is not necessarily a media URL. Filter channels/groups where available. A stream may be offline, geographically restricted, encrypted, unsupported or require authorisation. Use only sources you are entitled to access. Plain HTTP and other non-secure protocols can expose traffic.

## Quick Share
Select files and start sharing on a trusted reachable local network. Open the displayed URL or QR code on the recipient device. Anyone who can access that active link may download the selected files. Transfers are not end-to-end encrypted. Stop sharing afterward. Wi-Fi client isolation, firewalls or VPN routing can prevent access. No file transfer is guaranteed until the recipient confirms it completed.

## Private Space
Set a PIN before adding private media. Available move/hide actions depend on Android storage access. Device authentication is required for supported forgotten-PIN recovery. Private Space is local access protection, not cloud backup or a promise of strong file encryption. Keep a separate backup before moving valuable media or uninstalling/clearing app data. A PIN reset does not recover files already lost from storage.

## Language, subtitles and AI
Bundled interface translations include Pashto and Uzbek and work offline. Changing interface language does not translate the movie's audio or captions. Embedded/external subtitles must be supplied or generated separately. On-device AI subtitles require a supported model download first; processing speed, language coverage and accuracy vary. Downloading models needs internet and storage. Online Ask AI uses a different provider path described above.

## Android TV and remote
Use D-pad to move focus, OK/Select to activate, and Back to leave a child page before closing its parent menu. TV launcher/remote layouts are provided; touch gestures are not remote controls. External apps, voice input, file access, PiP and decoder capabilities vary between TV devices. Check that the correct item is focused before pressing OK.

## Privacy, notifications and reviews
Read Privacy policy in the menu/About or the published policy for details. Usage analytics, diagnostics, installation identifiers, approximate country lookup and notification services exist even though there is no advertising SDK. There is currently no in-app analytics opt-out. Notification denial does not delete existing online records or disable analytics.

After meaningful use the app may request Google Play's native review dialog. Play controls whether it appears; it may not show every time. The app does not receive the submitted rating/review text. Reviews are not required to unlock features.

## Troubleshooting and support
- Missing videos: rescan, check Android media permissions, file existence and supported format.
- Playback failure: try a known-good local file; check source authorisation, network and decoder support. Re-encode a backup to H.264/AAC if necessary.
- VPN failure: verify permission, connectivity and provider availability; another VPN may already be active. Do not assume traffic is protected after an error.
- Sharing failure: check both devices can reach the same LAN and stop/restart the share if its address changed.
- Settings persistence failure: retry and check available storage. Clearing app data resets local settings and can remove app-private files.

Support/privacy contact: techlabs.hyper@gmail.com. Do not send passwords, VPN private keys or private media. Provider-side records are not erased merely by uninstalling the app.
