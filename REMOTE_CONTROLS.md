# Notifications, reset and detailed PDF (+74)

Remote theme features were removed in +74. See RELEASE_74.md for current deployment/build steps and ADMIN_DATA_GUIDE.md for using the data. Specific movie/series notifications remain supported: choose that destination and paste its TMDB details URL/title in the composer.

## Notification tap → screen
Composer's **When tapped, open** selector supports Home, Discover movies, Private folder, Folders, Playlists, Audio, Network storage, Cloud storage, Quick Share, Open stream, IPTV, Watch statistics and External HTTPS link.
- Screen names are allowlisted in the browser, sender, app and Firestore rules. Private folder uses its existing PIN/biometric gate; no unlock bypass is added.
- Discover opens its existing screen with an initially empty local-library matching input; it still fetches its normal online content. A private-folder screen opened this way also has no scanned library input for add-file shortcuts; its normal vault authentication remains intact. Specific movie/playlist-item links are not part of this version.
- Invalid destinations fall back to Home. Older notices containing a safe HTTPS link but no screen retain external-link behaviour.
- The Link input is enabled only for External HTTPS link. Do not enter maxplayer:// URLs.
- +72 reads a local cold-start notification tap before Firebase sign-in/token/topic networking. Previously that networking could delay the external link. Browser/server/redirect/network loading time is outside the app's control and cannot be guaranteed faster.
- Android force-stop, denied permissions, OEM battery restrictions and offline devices can prevent or delay delivery. FCM acceptance is not delivery confirmation.

## Reset: exactly the selected scope
The button deletes **analytics counters (`stats`) and diagnostic records (`reports`) only**. It preserves admins/auth accounts, device tokens, notices/history, saved themes, published theme, image branch, secrets and rate-limit/control records.

- Export first. Type `RESET ANALYTICS` exactly, then confirm the destructive action. No undo or automatic backup is provided.
- Browser queues a protected job. The trusted GitHub sender workflow now processes admin maintenance jobs before pending notices. Existing dispatch settings start it; a scheduled run is the fallback. A reset is limited to once/hour.
- Browser cannot directly delete the collections or alter job status. Worker rechecks admin membership, claims the request transactionally and uses a hardcoded two-collection allowlist.
- Per-document update-time preconditions preserve records changed during deletion. Status can be partial if records changed, writes failed or a runner stopped. A stopped job is not automatically retried destructively. There is no cross-collection atomic reset.
- Live/offline apps can subsequently submit fresh or queued old events. Counters can repopulate immediately. Install/country one-shot preferences on phones are NOT remotely erased, so those totals will not magically recount all existing installations after reset; they are not a current-install census.
- The full workflow may take longer for large data sets and consumes normal Firestore/GitHub quotas. Check its recorded status. Do not queue resets casually.

## Detailed PDF export
The PDF button fetches **all stored analytics and diagnostic documents through pagination**, rather than only the latest 100 diagnostic rows. It includes:
- 13 selected-range metric charts (5 core metrics + 8 feature opens), with titles, totals, date ranges and aggregation notes;
- hourly chart and exact hourly table;
- feature comparison bars/counts/shares and all received IP-country sample bars/tables;
- selected-range daily core and feature tables;
- full raw appendices for all fetched stats and reports, including old dates/legacy fields and full captured report text.

Charts follow the selected range, while raw appendices include all fetched dates. It intentionally excludes credentials, device tokens, admin account records, saved themes and notice history. Some old diagnostic records may contain technical context: treat exported reports as private. This is not an atomic database backup; data can change during pagination. Deleted or never-recorded data cannot be recovered. Very large exports can be slow or exceed a browser's memory/printing capacity; a failed fetch shows an error rather than claiming completion. Use your browser's Save as PDF destination. No external PDF library is loaded.
