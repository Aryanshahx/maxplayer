# MaxPlayer 1.0.1+72 — named remote themes, notification destinations, reset and detailed PDF

## Required steps
1. Apply the update script from the +71 repository root. Run your normal Flutter checks, commit and push. APKs remain built only in GitHub Actions.
2. **Publish the complete new `firestore.rules` in Firebase Console → max-player-cd43d → Firestore `(default)` → Rules.** This update adds protected themes, appConfig and adminJobs paths and allows a validated screen field on notices. Do not open database-wide write access.
3. Wait for Pages deployment and hard-refresh https://aryanshahx.github.io/maxplayer/admin/ . Sign in with your existing Firebase admin account. The same GitHub dispatch token and FIREBASE_SERVICE_ACCOUNT secret are used. No additional paid service or new secret is required.
4. Install the new +72 CI-built APK on test phones. Old APKs cannot render these remote themes or route to the new screen targets. Test text/picture notifications, a private-folder destination, a cold-start external URL and Publish/Default before releasing broadly.

## Theme code: generate → paste → save → publish
Use **Themes** in the sidebar, or scroll below sender settings on mobile. The editor also offers Christmas and Diwali presets. Loading a preset does NOT publish it.

1. Paste schema-version-1 JSON in the editor, or load a preset.
2. Preview validates supported keys, colours, text contrast and decoration values.
3. Save named theme writes it to your protected library. Choose a saved entry and Load to edit it later. Selecting an entry before Save updates that entry; clear selection to save another named entry.
4. Publish applies the editor's validated configuration to compatible online apps. The app uses a Firestore document listener and caches the last known-good configuration.
5. Switch to Default publishes enabled:false. Compatible online apps restore their ordinary palette and user-selected local accent. Offline apps retain their previous cached theme until they reconnect. No instant change is promised for disconnected devices.

Example code you can paste (not executable Dart/JavaScript):
```json
{
  "schemaVersion": 1,
  "name": "Christmas",
  "palette": {
    "background": "#081810",
    "surface": "#10251B",
    "surfaceAlt": "#173322",
    "border": "#32533D",
    "accent": "#FFD98A",
    "textPrimary": "#FFF8E8",
    "textSecondary": "#C6D8C9",
    "danger": "#E5484D"
  },
  "decoration": "christmas",
  "headerLabel": "Merry Christmas"
}
```

Supported decoration presets are `none`, `christmas` (snowflake header symbols) and `diwali` (festive star header symbols). These are static, lightweight header decorations, not an arbitrary animation engine. Palette tokens are shared across app surfaces/components; fixed media artwork, player video, native Android permission UI, launcher icon and individually hard-coded specialist styles are not all recoloured. Shared tokens were made dynamic and widget theme dependencies were added without restarting navigation. This is a bounded theme renderer, NOT a way to execute pasted code, invent layouts, replace app logic or bypass Play updates. New unsupported layouts/decorations need an app renderer update. No remote image/font host is introduced by these JSON themes.

The admin preview is illustrative, not a complete device emulator. Dark-background/light-text contrast is validated. Saved templates and published settings contain no secrets. Firestore reads/quotas still apply; this is not unlimited free infrastructure.

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

## Verification boundary
- Dart analysis: no issues. 272 Flutter tests passed, including JSON validation/default restoration/cache and local cold-start tap reading without Firebase login.
- 24 admin tests and 20 sender tests passed; sender dependency audit reported zero known vulnerabilities when checked.
- Firestore emulator: 16 positive/negative rule assertions passed. Reset worker emulator integration removed seeded test stats/reports and preserved seeded admins, tokens, themes, configuration and notices. No production data was deleted during development.
- Chromium with mocked HTTP passed theme save/publish/default, invalid-code rejection, internal screen payloads, typed reset queue, ADMIN header, mobile overflow and PDF content. A test PDF was generated with 14 SVG charts plus comparison/country sections and full data sentinels.
- Live publication to devices, native route rendering/protection, link latency, production reset and Android notification delivery still require controlled integration tests. No local APK build is claimed; CI/toolchain versions are unchanged.
