# MaxPlayer 1.0.1+76 — Advertising ID release fix and 40 interface languages

## What the screenshots mean
The uploaded version-code-75 AAB is missing `com.google.android.gms.permission.AD_ID`, while Play Console's Advertising ID declaration says Yes. This update adds the unrestricted permission explicitly to the app manifest, consistent with the existing Google Mobile Ads integration. Do NOT change the form to No or turn off release errors just to bypass that mismatch.

The existing SDK consent/advertising behaviour is not replaced. The permission does not itself cause a runtime Android permission dialog and is not a new custom analytics counter. The admin's own aggregate counters still use their existing installation registration flow; do not assume all analytics uses Advertising ID.

## Apply / build / upload
1. Apply the one update script in your existing +75 repository root. Run Flutter clean/pub get/analyze/test, commit and push as usual.
2. GitHub Actions continues building APK and signed AAB. No local Android build is needed; no new signing secret or paid service is introduced. Keep the existing Play upload key and four CM_* signing secrets.
3. Open https://github.com/Aryanshahx/maxplayer/actions/workflows/release-aab.yml and select the successful run for this commit. Download artifact `maxplayer-release-aab`, unzip it and obtain `app-release.aab`.
4. Return to your Play Console draft release. Remove/replace the version-75 bundle in that draft and upload the NEW version-code-76 AAB. You cannot repair an already-uploaded artifact by changing source files or reusing its version code. If 76 has already been used, a higher unused version code is required.
5. Keep Advertising ID set to Yes for the current AdMob-enabled app. Review purposes against your actual SDK configuration; the screenshot's advertising/analytics/fraud selections should not be confused with collecting religion or using Advertising ID for admin push. Do not tick the option that turns off release errors merely to proceed.
6. Save the declaration if changed, return to Preview and confirm, and allow Play to process the new bundle. If it still flags a missing permission, inspect which artifact/version/track it names; another retained older artifact may still be involved. Do not claim approval until Play's checks complete.

Official SDK disclosure guidance: https://developers.google.com/admob/android/privacy/play-data-disclosure . This implementation fixes the specific permission mismatch, not every possible Play policy/review issue.

### Final-artifact protection in CI
The signed-AAB workflow retains its signing checks and adds a final-manifest gate. It downloads pinned bundletool 1.18.3, verifies its SHA-256, dumps the base manifest from the BUILT AAB, and fails unless unrestricted AD_ID is present. Merely having it in source is not treated as final-artifact proof. This guard has not run on a real AAB in this workspace; it runs when your next GitHub build does.

## Home → three dots → Language
- A new Language menu opens a searchable list showing native and English language names.
- There are **40 selectable languages**, plus System default. Selection applies without restarting the app and is persisted locally.
- System default uses a supported device language, otherwise English. Unsupported saved codes fall back safely.
- Flutter's built-in Material/Widgets/Cupertino localization delegates are enabled for the same locales. Arabic, Urdu, Persian and Hebrew get right-to-left layout. Android's own permission dialogs/settings still follow Android's language choices; this is not a device-language switch.
- Bundled JSON catalogs contain **366 fixed UI keys per language**. They cover fixed Home/menu labels, common actions/dialogs, display settings and many screen/form labels. Unknown keys and uncovered dynamic/technical messages fall back to their original English text. This is NOT a claim that every diagnostic sentence, dynamically assembled counter, tooltip, manual or legal paragraph has been translated.
- User media filenames, playlist/server names, movie metadata, channel titles, external content, notification messages, protocol/URL examples and the canonical English privacy policy are not machine-translated at runtime. Selecting a UI language does not select a video's audio/subtitle track or change the admin panel's language.
- Translations were initially machine-generated from public static interface strings during development, with selected Hindi labels adjusted. They are NOT professionally/native-speaker verified across all 40 languages. Native-language proofreading and real-device layout/font checks are recommended before a broad production rollout. Android/OEM font fallback determines script rendering; no remote font service is introduced.
- No runtime translation API, API key, new backend, language analytics upload or per-language Firebase document is added. Changing the language works offline after installation.

### Languages
English; Hindi; Bengali; Telugu; Marathi; Tamil; Urdu; Gujarati; Kannada; Malayalam; Punjabi; Odia; Assamese; Nepali; Sinhala; Arabic; Persian; Hebrew; Turkish; Russian; Ukrainian; German; French; Spanish; Portuguese; Italian; Dutch; Polish; Romanian; Greek; Indonesian; Malay; Vietnamese; Thai; Korean; Japanese; Simplified Chinese; Swahili; Czech; Hungarian.

## Preserved features
The +75 HLS/IPTV classification and relative-URL fix stays intact. Free channels, media playback, private access protection, movie notification routing, admin metrics/export/reset and the removed-remote-theme decision remain. No Firestore rule change is required for this update.

## Verification boundary
Dart analysis is clean. Flutter tests cover 40 unique matching offline catalogs, all 40 framework-supported locales, preference persistence/fallback, Hindi labels/form hints, Arabic RTL, untouched example media text, searchable picker selection and source AD_ID. The complete existing test suite passed after UI wrapping, including HLS and movie-route regressions. Python permission tests cover present, missing and SDK-capped manifests. Workflow YAML/shell and installer checks are performed separately.

No actual Android APK/AAB build, final compiled manifest inspection, device-wide font review or Play acceptance is claimed from the assistant workspace. Both binaries must be built in GitHub Actions and tested/uploaded as described above.
