# Android ad-free release: Play Console guide

Prepared for source update **1.0.1+77**, package **com.hypertechlabs.maxplayer**. This is guidance based on the audited source, not a submission or a claim that Google approved the answers. Review the actual AAB, enabled SDK settings, provider contracts and every currently distributed Play version before submission. Windows is untouched.

## 1. Apply, review and build

After applying the guarded script, review `git diff --check` and `git status`. Stage only the changed Android/shared root files, NOT desktop files or private keys. Commit/push using your normal workflow. Build Android ONLY using the existing GitHub Actions workflows:

- APK: https://github.com/Aryanshahx/maxplayer/actions/workflows/android-apk.yml
- Signed Play AAB: https://github.com/Aryanshahx/maxplayer/actions/workflows/release-aab.yml

Use the existing signing secrets; do not replace the upload key or put credentials in chat. Version code is 77. If Play already has code 77 or higher, choose a strictly higher unused version code in pubspec.yaml, update the diagnostic version tag to match and rebuild. Package, app name and signing configuration are unchanged.

## 2. Test through Play internal testing before production

Upload the signed AAB to an internal test release. Inspect the merged artifact permissions in App Bundle Explorer: `com.google.android.gms.permission.AD_ID` and the ad-services permissions must be ABSENT, not merely absent from your hand-written manifest. The source uses `tools:node="remove"` specifically to prevent transitive Firebase/measurement manifests from restoring them. Check that Google Mobile Ads is absent from the dependency report.

Test Library, Discover, Private Space, cloud import and stream opening: there should be no ad banner, interstitial, pCloud promotion or tagged Amazon CTA. Test language selection for Pashto (RTL) and Uzbek (LTR), persistence after reopening, native text rendering and long labels. New catalogs are machine-assisted translations of the existing 366-key UI inventory; a fluent-speaker review is recommended. Some existing hard-coded/technical text remains English. Pashto framework-owned Material/Cupertino labels use English fallback because Flutter has no Pashto implementation; app strings and widget direction are Pashto/RTL. Media/captions are not translated.

Review prompt: after at least 3 days, 3 qualifying playback visits (at least 60 seconds each) and 20 minutes counted foreground, non-buffering playback, the app may request Play's native review after leaving the player. At least 120 days between attempts; max 3 attempts in current local storage. Counters are local and reset with app data. No pre-rating question, positive-only gating or forced stars. Google may not show the card; the app cannot detect submission. Sideloaded APKs are not a reliable review test. Use an eligible Google account and install from Play's internal testing track.

## 3. Publish the privacy policy

The update synchronizes `PRIVACY_POLICY.md`, bundled app text and `privacy/index.html`. There are no admin-panel descriptions, internal release notes or version-labelled disclosure headings. Real data collection is still disclosed plainly.

A Play privacy URL must be public, readable without login, non-geoblocked, and not an editable document or PDF. Use the HTML file, not a GitHub editor page. Free option:
1. After pushing, open repository Settings → Pages.
2. If Pages already hosts your site, preserve its existing source and add `/privacy/` there. Otherwise choose Deploy from a branch → main → /(root), then Save. Do not overwrite an existing publishing configuration blindly.
3. Once deployed, visit **https://aryanshahx.github.io/maxplayer/privacy/** in a signed-out browser. This URL is only live AFTER Pages is enabled and deployment succeeds; the script does not enable Pages.
4. Play Console → select app → Policy and programs → App content → Privacy policy → enter the verified public URL → Save.
5. Keep the in-app and public versions synchronized on future updates.

## 4. Ads and Advertising ID declarations (separate from Data safety)

App content → Ads: for this ad-free build, **No, my app does not contain ads**. The pCloud and tagged Amazon promotions were also removed, not just AdMob.

App content → Advertising ID: for this build, **No**. Do not select an advertising purpose merely because an installation identifier/FCM token remains: these are different identifiers. Verify the final AAB first.

Important: don't make a global "no ads/no advertising-ID" declaration while older ad-bearing builds remain distributed in other active tracks/device variants. Review/update/deactivate superseded test releases and coordinate declarations with your release rollout. Data safety must cover relevant current distribution, not just a local unreleased patch. An update does not remove ads from APKs already installed by users who have not updated.

## 5. Data safety overview

App content → Data safety → Manage/Edit → follow the questionnaire.

- **Does your app collect or share required user data? YES.** Removing ads does not remove Firebase Analytics, Anonymous Auth, Firestore counters/reports, IP-country lookup or FCM.
- **All collected data encrypted in transit? Do not assert YES for the entire app without resolving scope and transport.** Firebase and the country lookup use secure transport, but Quick Share is HTTP and arbitrary user media URLs may be HTTP. Conservative answer for the current build is NO; if you determine those explicitly user-directed transfers are outside this declaration's collection scope, document that assessment before changing the answer. The app must not promise universal encryption.
- **Deletion requests:** the policy provides a contact email, but there is no automatic in-app deletion service or guaranteed per-installation lookup flow. Do not claim a working account/data-deletion URL or verified deletion capability unless you actually establish and test it. Answer follow-up questions according to your real process. Aggregated statistics may not be attributable to a person.
- **Account creation:** ordinary users do not create a named account or log in. Firebase nevertheless creates a pseudonymous UID. Review Google's account-deletion applicability rather than treating anonymous IDs as "no data".
- Do not claim independent security review, Families certification or legal compliance unless obtained.

## 6. Data-type worksheet

The rows below describe collection, not a blanket claim that every provider is only a service provider. Select these types as applicable to all enabled features. Firebase is not Crashlytics here: crash reporting is custom Dart/Flutter reports sent to Firestore.

| Play data type | What remains | Collected / purpose | User control / ephemeral |
|---|---|---|---|
| Location → Approximate location | IP-derived country sample; Firebase Analytics geographic metadata | Yes; Analytics | Required (no in-app opt-out); not ephemeral because country/statistics are retained |
| Personal info → User IDs | Firebase Anonymous Auth UID | Yes; App functionality (installation/notification registration) | Required in this implementation; not ephemeral |
| Device or other IDs | Firebase/Analytics installation IDs and FCM registration tokens | Yes; Analytics and App functionality; Developer communications where notification notices apply | Base installation/analytics required; notification delivery can be denied; do not label the entire data type optional; not ephemeral |
| App activity → App interactions | Opens, feature taps, playback/session counts/duration, SDK events | Yes; Analytics | Required; not ephemeral |
| App info and performance → Crash logs | Bounded captured exception/stack reports | Yes; Analytics (reliability/diagnosis) | Required; not ephemeral |
| App info and performance → Diagnostics | Failure kinds/hosts, device/app details and technical report context | Yes; Analytics | Required; not ephemeral |
| App activity → In-app search history | User-entered catalogue searches sent to TMDB; queries are not intentionally logged in custom analytics | Yes when used; App functionality | Optional feature; do not claim ephemeral unless provider retention is verified |
| App activity → Other user-generated content | Descriptions/questions sent for optional online AI recommendations | Yes when used; App functionality | Optional feature; do not claim ephemeral without provider verification |

**Sharing must be assessed per recipient:**
- Firebase processing solely on your behalf may qualify for Play's service-provider exception. Verify Analytics data-sharing/advertising settings and your agreements; SDK inclusion alone does not justify a blanket "No sharing" or "Yes sharing" answer. This release disables ad-ID collection/ad-personalization signals in the manifest; check server-side Analytics settings too.
- country.is receives an IP and derives a country. Do not assume it is your contracted service provider. Conservatively disclose approximate location as shared for Analytics unless you document a valid exemption based on actual provider terms/practices.
- TMDB/OpenRouter requests transfer submitted input and connection data to those providers. Conservatively disclose the relevant optional search/content types as shared for App functionality unless a documented Play exception applies. Inspect OpenRouter's selected model/provider retention settings; do not claim inputs are never retained.
- Explicit user-directed Quick Share/media transfer can qualify for Play's user-initiated transfer exception if users reasonably expect that transfer. Confirm the actual flow before excluding media/audio categories. Local library scans alone are not off-device collection.
- Android speech recognizer may use network recognition. Audit the configured recognizer and behaviour before ruling out Audio files → Voice or sound recordings for voice-search handling. The app does not itself store/upload microphone recordings; that does not prove every recognition service is offline.

Do NOT select GPS/precise location, contacts, SMS, payment details or a user's name/email solely because of the Firebase SDK. They are not requested from ordinary users by this implementation. Assess any separate support email handling and enabled provider behaviour. There is no ad-targeting data purpose in the new build. Notification developer communications may still apply; don't conflate it with ad targeting.

Where the console asks whether collection is required, use **Required** for the default analytics/identifier/report flows because there is no user analytics opt-out. Notification denial does not disable these other flows. Mark optional input only where users can avoid the relevant feature. Stored counters/reports/tokens are not ephemeral merely because event payloads are small or aggregate.

## 7. Final release checklist

- Verify public policy URL, contact mailbox and actual deletion-request handling.
- Verify Data safety against current SDK documentation/settings and every active build; resolve the provider/speech-sharing questions above before submitting.
- Keep media/microphone/notification permission declarations accurate. Removing ads does not remove media permissions or Firebase collection.
- Update any Play description/screenshots claiming advertisements or 40 languages as appropriate. Use "42 interface language options" rather than "fully translated".
- Save declarations, review the internal test AAB, then submit your normal production update for review. No Play Console setting has been changed by this script.

## Official references

- Google Play Data safety definitions (including IP-inferred location and sharing exceptions): https://support.google.com/googleplay/android-developer/answer/10787469?hl=en
- Firebase Android data disclosures, including Anonymous Auth IDs and FCM: https://firebase.google.com/docs/android/play-data-disclosure
- In-app review requirements and quotas: https://developer.android.com/guide/playcore/in-app-review
- Testing reviews via Play: https://developer.android.com/guide/playcore/in-app-review/test
