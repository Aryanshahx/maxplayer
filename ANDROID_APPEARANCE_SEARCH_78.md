# Android 1.0.1+78 — adaptive appearance, full pages, recent search and AAB guard

## Why the AAB run failed

The posted run reached the final Advertising ID inspection after `bundleRelease`, bundle signature verification and bundletool download. The old `verify_ad_id.py` still treated AD_ID as mandatory and raised `Advertising ID declaration is Yes, but AD_ID is missing from this manifest`. That was the wrong assertion for the new ad-free app. It does not mean the app must add advertising back.

This update changes the source/final-manifest verifier and its tests. Source merger-removal directives are allowed. The FINAL AAB check uses `--final` and rejects ANY actual advertising-ID/ad-services permission, even one with a surviving tools directive. Missing permissions PASS. AdMob application metadata is also rejected. The existing repository-resolution fix, checksum-pinned bundletool, signing verification and upload-key secrets remain intact. Build Android via GitHub Actions only; no native APK/AAB has been built locally for this update.

## Appearance

- Default preference is System, including for existing installs with no appearance preference.
- Home three dots opens a full-screen Settings and more page, with Appearance → System default / Light / Dark.
- The choice is persisted locally. System mode responds to device brightness changes; an explicit choice overrides it.
- UI surfaces, text, settings, ordinary dialogs and navigation use adaptive palettes. White default accent becomes charcoal in light mode; other light-mode accents are adjusted for readable foreground contrast.
- Video pixels/poster images are not inverted or colour-filtered. Player overlays/media artwork can remain dark for legibility. QR backgrounds stay white rather than becoming unreadable in light mode.
- All eight Home shortcuts (Folders, Private Space, stream, cloud, network, Quick Share, playlists, audio) have opaque surface backgrounds, borders, ripple and TV focus feedback.

## Full-screen routes

Home settings menu, Privacy policy, User manual and About Max Player use full-page routes with app bars and normal back navigation. The diagnostics page from About is also a full-page route. Language, Display settings and Watch statistics remain ordinary full pages. Report/email and Instagram still open their external destinations, not an embedded fake page. 'Full screen' here means full app page, not hiding Android status/navigation bars.

## Recent searches

The local-library, Discover, audio, IPTV and language search fields show up to 3 recent queries per category in a focused-field dropdown. Queries are trimmed, deduplicated case-insensitively, saved after a typing pause/submission/leaving the field, and can be recalled or cleared. History persists locally; nothing is added to analytics for this feature. Discover's existing online search still sends user-selected/typed queries to its provider as before. PIN, password, network-address and stream-URL entry fields are NOT history-enabled. New labels may fall back to English in existing translations; this release does not claim full translation coverage.

The public policy, bundled policy text and HTML copy now disclose local search and appearance preferences. Re-publish the public HTML copy with your release.

## In-app review: already present, retained

Yes: the +77 native Play review integration remains wired at app startup and after leaving the video player. It waits for at least 3 days since first use of that integration, 3 qualifying playback visits (at least 60 counted seconds each), and 20 minutes total counted foreground/non-buffering playback. It requests only after leaving playback, with a 120-day cooldown and at most 3 local attempts. Google controls whether the card is displayed and does not reveal whether a rating was submitted. Sideloaded APK installs are not a reliable review test; install from Play's internal testing track. No pre-rating satisfaction gate or repeated startup popup is added.

## Delivery and validation

One guarded script, `update_android_appearance_search_78.sh`, contains the actual Dart, Python, workflow, policy and documentation payload. Run it from the existing IntelliJ Git repository root. No argument means apply; `--check`, `--apply` and `--verify` are also supported. It backs up files, checks original hashes, refuses conflicting edits and is safe to rerun. It expects the current +77 baseline with the prior AAB repository fix. No Android package/signing changes, no admin-backend changes and no Windows changes. Version code increases to 78 for the next upload; use a higher unused code if Play already has 78.

Run this simple block (git add -A stages ALL pending repository changes; review unrelated work first):

```sh
bash update_android_appearance_search_78.sh &&
git add -A &&
git commit -m "Add Android adaptive themes, full-screen settings and recent searches; fix AAB ad-free check" &&
git push
```

Then use the NEW COMMIT'S Play Store AAB workflow run, not a rerun of the old failed commit:
https://github.com/Aryanshahx/maxplayer/actions/workflows/release-aab.yml

On a successful run, download `maxplayer-release-aab`, extract the AAB and test via Play internal testing before production. The script does not alter Play Console answers or publish the privacy URL. Keep the ad-free Ads/Advertising-ID declarations consistent with all currently distributed builds.

Workspace cleanup removed obsolete local validation/checkouts and redundant SDK directories, not uploads or delivered scripts. That cleanup applies only to the assistant workspace and is not embedded as deletion commands for your repository.
