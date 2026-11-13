# MaxPlayer 1.0.1+74 — remove remote themes; APK + signed AAB delivery

## Scope
- Removed the entire remote-theme feature: admin studio, theme navigation, named JSON editing, country/religion-labelled theme presets, application listeners/cache reads, festive Home vector decorations, runtime theme tokens and examples.
- Normal black/white appearance is restored. The existing on-device accent setting still works. Old cached theme preferences are ignored; they do not override the normal palette.
- Updated Firestore rules deny client reads/writes to retired themes/configuration paths. Existing database records are retained inert; the installer does not delete production records. No theme-related Firestore reads or country-for-theme refreshes are made by the +74 app.
- Kept +73 specific movie/series notification destinations, private-folder gate, HTTPS links, gallery notification pictures, early local tap handling, ADMIN branding, core/eight-feature metrics, five-item fixed navigation, detailed PDF and analytics/reports-only reset.
- Added a collapsed **How to use these numbers** guide in the admin overview; a detailed weekly checklist is in ADMIN_DATA_GUIDE.md.

## Apply and deploy
1. Run the single +74 update script from your existing +73 repository root. Run the usual Flutter clean/pub get/analyze/test commands, then commit/push.
2. Publish the complete root `firestore.rules` in Firebase Console → max-player-cd43d → Firestore `(default)` → Rules. Keep all other protections; do not use allow-all rules. This retires theme-path client access while retaining movie notifications and protected reset jobs.
3. Wait for GitHub Pages, then hard-refresh https://aryanshahx.github.io/maxplayer/admin/ . Themes is gone; Overview/Send/Countries/Errors/Settings remain.
4. Install the CI-built +74 app to remove remote appearance on each phone. An older APK still has its old renderer/cache; removing a webpage or denying rules does not erase offline caches in already-installed older APKs. No forced remote replacement of an installed binary is possible. If retiring the old look before devices upgrade is important, restore Default to All from the OLD admin before deploying this update/rules; only connected old apps can observe that.

## APK + AAB: what is configured, and what still requires a build
Both workflows now run on a push to `main`, and both keep manual **Run workflow**:
- [Android APK](https://github.com/Aryanshahx/maxplayer/actions/workflows/android-apk.yml): artifact `maxplayer-release-apk`, containing `app-release.apk`.
- [Play Store AAB](https://github.com/Aryanshahx/maxplayer/actions/workflows/release-aab.yml): artifact `maxplayer-release-aab`, containing `app-release.aab`. Tag-triggered AAB builds also remain available.

**No AAB/APK was compiled in this assistant workspace and no remote build was triggered here.** Actual binaries only exist after a successful GitHub Actions run. The AAB workflow is configured, not a claim of a completed build.

### Signing setup — required for AAB
In [repository Actions secrets](https://github.com/Aryanshahx/maxplayer/settings/secrets/actions), the AAB workflow needs:
- `CM_KEYSTORE`: base64 of your existing Play upload keystore.
- `CM_KEYSTORE_PASSWORD`
- `CM_KEY_ALIAS`
- `CM_KEY_ALIAS_PASSWORD`

Keep these only in GitHub Secrets; do not paste them into chat, admin settings, commits or public logs. **Use the upload key accepted by your existing Play listing. Do not generate/replace it casually.** If you lost the key, follow Google's upload-key reset process where supported; this update does not rotate signing identity.

The existing `TMDB_API_KEY` and `OPENROUTER_API_KEY` build configuration is retained. The APK workflow requires OPENROUTER_API_KEY as before. The pinned Flutter/Java/Gradle setup and application ID `com.hypertechlabs.maxplayer` are unchanged.

The AAB job fails if a signing secret is missing, restores the release keystore, builds with the existing release-signing configuration, checks the bundle manifest and JAR signature, cleans temporary key files even on failure, and uploads only the bundle. This does not independently prove that the key matches Google's currently registered upload certificate—Play Console is authoritative. Version code 74 must be greater than any code already uploaded to your Play listing; a used/lower code cannot be reused.

### Download on a phone / computer
1. Open the workflow link above and select the latest successful run for your commit. If it did not start, tap **Run workflow → main → Run workflow** while signed in to GitHub with permission.
2. Scroll to **Artifacts** and download `maxplayer-release-aab` (a ZIP). Extract it to obtain `app-release.aab`. Artifacts are retained for 14 days.
3. In [Google Play Console](https://play.google.com/console/), open your existing app → Testing → Internal testing → Create new release. Upload the `.aab`, review signing/version warnings and complete the release steps. An AAB is not directly installable like an APK; use the APK artifact for direct testing or Play's internal-testing delivery.
4. The existing APK workflow still uses its debug-key fallback where no upload keystore is restored. That testing APK's signature may differ from a Play-installed build; it may not install as an update over it. Do not uninstall casually: app-private data may be lost. The AAB uses the configured Play upload key.

These workflows build artifacts only; they do not automatically publish a Play release. No Firebase paid service or new image host is introduced.

## Using the admin data
Read the collapsed guide in Overview or ADMIN_DATA_GUIDE.md. Start with equal-length date comparisons, use feature/event trends to prioritise improvements, investigate reports rather than treating them as a complete crash census, and use country/hour patterns only as approximate planning signals. Install registrations are not current installs or unique people. Export before reset, keep diagnostic PDFs private, and do not infer personal religion or retention from aggregate counters.

## Checks performed
- Dart analysis clean; 272 Flutter tests passed, including normal appearance despite old preference values, local accent, movie route/retry and early launch-tap regressions.
- 24 admin and 21 sender JavaScript tests passed.
- Firestore emulator: 14 assertions passed for retired theme access denial and retained movie/reset/admin protections.
- Mocked Chromium: theme section removed, five-item navigation/data guide, internal/HTTPS notification handling, typed reset queue, 14-SVG-chart PDF with full fetched-data appendices, mobile overflow and sign-out passed with zero page exceptions.
- Workflow YAML and installer syntax checked. Actual signed CI builds, native Android delivery and Play acceptance remain to be verified after pushing.
