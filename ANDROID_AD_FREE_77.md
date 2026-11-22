# Android 1.0.1+77 — ad-free, languages and review update

Windows development is paused; no desktop source or Windows workflow is changed by this update.

## Delivered changes
- Removed Google Mobile Ads/UMP Flutter integration, initialization, banners, interstitial gates, the dependency/lock entries and new ad-impression reporting. Features open directly with no replacement ad gate.
- Also removed pCloud promotional banner and tagged Amazon/Prime affiliate CTA/helpers. Neutral catalogue watch-provider information remains.
- Removed AdMob app metadata. Manifest merger rules remove AD_ID/ad-services permissions even if another SDK transitively declares them; Analytics ad-ID collection/ad-personalization defaults are disabled. Verify the built AAB merged manifest in Actions/Play; native packaging was not executed in this workspace.
- Pashto (`ps`, RTL) and Uzbek (`uz`, LTR), each with all 366 existing UI catalog keys; 42 language options total. Catalogs are machine-assisted and key playback terminology was adjusted. Fluent-speaker/device review is recommended; existing untranslated hard-coded strings and English framework fallback labels in Pashto remain. Filenames and captions are not translated.
- Native Google Play in-app review request after meaningful use, only after leaving playback in the foreground, with persisted cooldown and attempt cap. No "Do you like us?" gate and no assumption that Play displays/submits a review. Full trigger details and internal-testing steps are in PLAY_CONSOLE_AD_FREE_77.md.
- Rewritten public, bundled and HTML privacy policy: internal admin descriptions/version notes removed; real analytics, country lookup, notification IDs, error collection and optional online inputs still disclosed in plain language.
- Replaced stale local-only Data safety advice in PLAY_STORE.md; added a source-specific Play Console worksheet with explicit provider/recognizer/transport decisions that require verification. No console settings have been submitted or changed.
- Version code 76 → 77 so a Play update can be uploaded. Package com.hypertechlabs.maxplayer, version name, signing setup and existing Android APK/AAB workflows are preserved.

## Still present by design
Firebase analytics, pseudonymous Auth IDs, Firestore counters/reports, approximate IP country and FCM remain. This is not a no-collection release. No admin backend access/rules are removed or exposed by this change. Existing historical ad counters are not deleted. Already installed older apps keep their old behaviour until updated.

## Apply from existing IntelliJ repository root
The script embeds the actual changed Dart/JSON/manifest/docs/lock payload and explicit deletions. It checks original hashes before changing anything, backs up files, refuses conflicting edits and can be rerun safely. It requires the Android +76 baseline. Desktop-only updates do not affect its checks.

Run each command separately:

```sh
bash update_android_ad_free_77.sh --check
bash update_android_ad_free_77.sh --apply
bash update_android_ad_free_77.sh --verify
git diff --check
```

Review and stage only this script's Android/root policy files (not unrelated desktop work), commit and push. Use the existing GitHub Actions Android APK and Play Store AAB workflows; no local Android build is required. Install via Play internal testing to validate the review flow and languages before production.

See PLAY_CONSOLE_AD_FREE_77.md for the policy URL, Ads/Advertising-ID answers, Data safety worksheet and release checks. The public HTML URL does not exist automatically: deploy/verify it first. If Play already uses version code 77 or higher, stop and choose a higher unused code before building.
