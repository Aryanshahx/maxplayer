# 1.0.1+73 — simpler themes, country audiences and movie details notifications

## Deploy in this order
1. Apply the single update script from your +72 repository root; run your usual Flutter checks and commit/push. Android APK builds remain GitHub Actions only.
2. Publish the complete updated `firestore.rules` in Firebase Console → max-player-cd43d → Firestore `(default)` → Rules. This adds public-read/admin-write `appConfig/themeAudience` and validates movie notification fields. Do not replace the rules with open database writes.
3. Wait for Pages deployment and hard-refresh https://aryanshahx.github.io/maxplayer/admin/ . No new secret, Firebase paid service or image host is needed.
4. Install the CI-built +73 APK. Test online/offline themes and movie notifications on controlled devices before broad release.

## New theme controls — no JSON required
Open **Themes** from the fixed bottom navigation or sidebar.
1. **Choose a look:** Christmas or Diwali loads and previews immediately, or choose a saved look. Nothing publishes automatically.
2. **Choose who sees it:** All countries, or Selected countries. Optionally choose a religion/cultural starting list, then REVIEW and edit the actual countries.
3. **Publish selected theme.** The confirmation names the audience. Restore Default applies only to that same audience.

JSON and saving are in **Advanced**. Existing schema-1 themes continue to work. Save named look updates the selected saved entry; use a built-in preset first to clear the saved selection and create a new entry. Saving and loading do not publish. The Currently published section lists global and country-specific assignments.

### Country semantics — read before publishing
- These are **country-group suggestions**, NOT a religious census, a claim that all residents follow a faith, or a complete list of countries associated with a religion. No individual's religion is identified, stored or targeted.
- Christian/Christmas, Hindu/Diwali, Muslim/Eid, Buddhist and Jewish are small manually curated starting lists. They can be edited. They do NOT automatically select a matching theme; choose a suitable look separately.
- Everyone with a matching approximate country receives the look, regardless of religion. An unknown country receives the global/default look; it never silently joins a religion-labelled group.
- Country themes are independent. Publishing Christmas to IN and Diwali to NP retains both assignments. Country overrides win over the global look.
- **Restore Default for selected countries** installs an explicit Default override there, even if a global festive look exists. Other country assignments remain unchanged.
- **All countries** replaces ALL country overrides with one global look, or restores Default everywhere. The confirmation warns about this. Exported analytics are not affected by theme publishing.
- Approximate IP country uses the existing country.is HTTPS provider. A successful lookup is normally reused for 24 hours; code/time are cached locally. The old analytics country sample is a fallback when available. Travel, VPNs, failures and stale/offline caches can make matching inaccurate. This is appearance targeting, not secure geofencing.
- Themes are public non-secret configurations. Apps retain the last valid theme offline. Delivery is not instantaneous; Firestore listeners/reads and finite Spark quotas still apply.
- +72 apps do NOT support country targeting. Scoped publication leaves their old theme alone. All-countries publication gives them a schema-1 palette/header fallback; rich visuals and country selection require +73. Older apps cannot be made country-aware remotely.

## Rich but bounded visuals
Schema 2 adds a `visuals` map. No executable code, scripts, remote asset URLs, downloaded fonts or arbitrary layouts are accepted.

| Key | Supported values | Actual coverage |
| --- | --- | --- |
| buttonStyle | plain, snowcap, lantern | Home quick-action tile vector details |
| cardStyle | plain, ribbon, goldOutline | Home quick-action tile ribbon/border details |
| background | none, snow, stars | Sparse STATIC Home edge decoration, not falling particles |
| rounded | soft, pill | Home tile corners; theme-managed cards and Filled/Elevated/Outlined buttons |

Christmas uses snow caps, red corner ribbons, sparse snow crosses, rounded controls and the Christmas header. Diwali uses lantern accents, golden outlines, sparse stars and its festive header. Decorations ignore taps and are excluded from accessibility semantics. Video/player routes are NOT covered by the Home background overlay. Custom widgets with hard-coded styles, Android permission dialogs, launcher icons, ads and movie artwork are not universally restyled. The admin preview is illustrative, not a complete device rendering.

Updated ready-to-paste examples: `examples/themes/christmas.json` and `examples/themes/diwali.json`. Schema 1 still supports only palette/header decorations. Unsupported effects need another renderer update; this is not remote executable theme code.

## Notification → a specific movie / series details screen
In **Send notification**:
1. Set **When tapped, open → Specific movie / series details**.
2. Use the **Find a movie / series on TMDB** link, choose the exact title there, and copy its public details-page URL.
3. Paste a link such as `https://www.themoviedb.org/movie/550-fight-club` or a `/tv/…` link. Enter the matching title. The selection summary shows kind and ID.
4. Fill notification title/message, select its audience and optionally choose a gallery picture as before. Send a test notice to one installation first.
5. A compatible phone tap opens the app, fetches that TMDB ID and displays the same full Discover details UI. It does NOT open the website. Detail loading can fail offline or if TMDB is unavailable; Retry and Go Home are provided. Invalid destination data falls back Home.

The static admin intentionally has **no embedded TMDB search API secret**. Selection is through TMDB's public website plus validated URL/title entry, not an embedded search catalogue. The ID determines actual details; typed title is a loading label and should match it. No local-library match is supplied by this route, so it does not automatically locate/play a file from your phone. Existing Discover details actions remain as implemented; availability is not a promise of a full playable film. Old APKs do not know the new movie route and fall back Home. The app still needs its existing CI TMDB configuration. HTTPS external notifications remain a separate destination.

FCM data passes movieId, movieKind and movieTitle through the protected sender and includes these in byte-budget validation. Firestore rules allow only positive bounded string IDs and movie/tv kinds. Gallery image hosting, private-folder authentication, early local launch-tap handling, reset scope, detailed export, analytics metrics and bottom navigation remain.

## Verification
- Clean Dart analysis; 277 Flutter tests passed. New tests cover schema 2, audience precedence and Default, invalid movie fields, tap-transparent visuals, and movie loading/retry UI.
- 29 admin tests and 21 sender tests passed.
- Firestore emulator: 26 allow/deny assertions, country override preservation, and the existing stats/reports-only reset integration passed. Only emulator fixture records were deleted.
- Mocked Chromium: collapsed Advanced, automatic preview, editable country groups, independent country publication/default, All-clears-overrides, safe +72 fallback, saved library, movie composer payload, mobile overflow and zero page exceptions passed.
- No production publication/reset or Android device/FCM delivery test is claimed. No local APK build. Native visual appearance, country lookup accuracy, real cold/warm movie routing and delivery should be checked with the CI-built APK.

Older +72 instructions remain in REMOTE_CONTROLS.md for reset/export details. This document supersedes its old theme-editor workflow and schema-1-only limitations.
