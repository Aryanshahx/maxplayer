# 1.0.1+69 — redesigned control room and approximate IP country

## What's changed
- Navy/mint responsive control room with navigation, clearer KPI labels, separated communication and diagnostic sections.
- Notification history is removed from the page, navigation and periodic queue-list queries. Only the most recently tracked notice's status is shown while needed. Historical Firestore records are not destructively deleted; the sender still keeps its administrative records. Notification sending, gallery selection, authentication and GitHub dispatch settings remain.
- Activity area chart has metric selection, readable integer axis steps, touch/hover/keyboard exact-value tooltips and a daily-numbers table. Ranges up to 45 days use daily points; 46–180 days use 7-day buckets; longer ranges use calendar months. Totals are preserved during aggregation.
- Feature mix uses labelled horizontal bars and values. Hourly opens have a clearly labelled bar chart and peak-hour summary. Empty data is explicitly labelled; there are no fabricated production/demo values.
- PDF export now uses IP-country samples, never the old locale country fields.

## Why old country data was wrong
Previous country totals used phone locale, not physical location. This update stops collecting those legacy locale counts and never shows their c_CC fields in the new country chart. It does not rename or relabel old data as accurate IP data.

The +69 app makes a best-effort request to https://api.country.is/ from the PHONE (not from the admin's browser) after Firebase initialization. That provider necessarily sees the phone's connection IP. It returns a country and IP, but the app extracts only the country code and does not persist or forward the returned IP. It stores one country code locally and increments stats/total ip_c_CC once per app-data lifetime after a successful lookup. New and upgrading installations both contribute samples.

No GPS permission or city/coordinates are requested. HTTP failures, rate limits, invalid responses and timeouts leave country unknown and retry on a later launch, never via locale fallback. The request has a 5-second deadline and 4 KiB response cap. It runs unawaited so it does not delay playback or push setup.

## What the country chart means
- Approximate network country at first successful lookup since +69, not verified download country or live location.
- Includes upgrading installations. Not a date-filtered count of new installs.
- Counts are best-effort, aggregate observations. Reinstalling/clearing app data can count again. Local queuing/crashes can also cause discrepancies; legacy stats rules permit untrusted writes.
- VPNs, proxies, mobile carrier routing and provider inaccuracies can make a country wrong. It is NOT guaranteed physical location.
- At first the table is empty, with a waiting message. Only +69 phones contribute the new series. Old locale totals cannot be corrected historically.
- App country sample totals are all-time, while activity charts use selected dates. Top 20 country entries are shown; percentages use the full sampled total. The PDF includes all received IP country entries.

## Provider and disclosure
Country.is documents a free, no-key API including commercial use with infrastructure rate limiting; availability, terms and limits can change. See https://country.is/ and https://country.is/llms.txt . No unlimited-service promise. This adds a third-party connection from devices: review the updated bundled/public privacy policy and update the Play Console Data Safety disclosure as applicable before distribution. No geolocation secret/account or Blaze plan is added.

## Apply and test
1. Run the delivered script in the +68 repo root. Usual flutter clean/pub-get/analyze/test/commit/push commands follow.
2. Wait for GitHub Pages deployment, then refresh https://aryanshahx.github.io/maxplayer/admin/ . Existing Firebase admin login and browser dispatch token remain supported. No Firestore rule changes or secret changes are required.
3. Install the NEW +69 CI-built APK on a phone and open it with internet access. Updating the panel alone cannot collect IP country data from an old APK.
4. Refresh panel data. The country sample may appear after the phone's successful lookup and Firebase sync. It is correct for the panel to remain empty before any +69 sample arrives. Test without a VPN if comparing against your expected country.
5. Switch chart metrics, test date ranges, tap/focus chart points and use the daily-numbers table for exact values.
6. Notification delivery changes from +68 are preserved; no bell, inbox or app notification toggle is reintroduced.

## Verification
- Dart analysis: no issues; 263 Flutter tests passed (including six country lookup cases).
- 19 Node tests passed, including chart aggregation, integer scales and excluding old locale country fields.
- Chromium checks with mocked HTTP passed for admin login, no history/queue listing, country-source separation, metric controls/tooltips, year aggregation, queueing with current-status tracking, PDF country source, mobile overflow, refreshed login and sign-out.
- Mock data is only in tests, not in the deployed dashboard. No real Firebase account or GitHub secret was used locally. Actual device country collection, deployment and notification delivery require live integration checks. Android compilation remains GitHub Actions-only; project toolchain is unchanged.

This document supersedes the previous panel's history/locale-country instructions. The Firebase Auth and dispatch-token setup in ADMIN_PUSH_SETUP.md still applies.
