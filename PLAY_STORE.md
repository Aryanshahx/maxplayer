# Updating "Max Player" on Google Play (new app replaces the old build)

Your situation:

- The app already on Play is **Max Player**, package **`com.hypertechlabs.maxplayer`**
  (version 1.0.0, versionCode 148).
- This new app has been **renamed to `com.hypertechlabs.maxplayer`** and
  **versionCode 149** (version 1.0.1), so Play accepts it as an update.
- You do **not** have the old signing key — so the FIRST step is to check
  Play Console's App Signing page. Everything depends on it.

---

## STEP 1 — Check App Signing (this decides everything)

Play Console → your app → **Setup → App integrity** (or **Setup → App signing**).

Look at which mode is active:

### A. "Play App Signing" (Google manages your key)  ← most likely
Google holds the release key; you only need an *upload key*. Since you don't
have the old upload key, request a new one:

1. **Setup → App signing → Request upload key reset** → choose *Create new
   upload key* (Google generates a new key certificate and gives you a file +
   instructions).
2. Build your keystore around that certificate (the on-screen command looks
   like `keytool -genkeypair … -alias upload` then import the cert).
3. The resulting keystore's values become your 4 secrets (STEP 2).

### B. "Use my own signing key" (self-managed)  ← rare for recent uploads
If this is set AND you have no key backup, **Play will reject the update and
Google cannot reset a self-managed key.** In that case you cannot update this
listing — you'd unpublish it and create a new app with a new package name.
(Fingers crossed this isn't you; Play App Signing has been mandatory for new
apps since August 2021.)

---

## STEP 2 — Create the signing values (one time, on any machine with a JDK)

```bash
cd ~/maxplayer
bash scripts/make_upload_keystore.sh
```
It creates `android/app/upload-keystore.jks` + `android/key.properties`
(both gitignored) and prints the fingerprints and base64.

The 4 values map like this:

| Secret | Value |
|---|---|
| `CM_KEYSTORE` | the long base64 line printed (or `base64 -i android/app/upload-keystore.jks`) |
| `CM_KEYSTORE_PASSWORD` | the keystore **store** password you chose |
| `CM_KEY_ALIAS` | `upload` (the alias) |
| `CM_KEY_ALIAS_PASSWORD` | the **key** password you chose |

If you did the upload-key **reset** in STEP 1A, generate the keystore around
Google's new certificate instead of `make_upload_keystore.sh` (Google's page
shows the exact command), then read the 4 values from that keystore the same
way.

**Back up the keystore + passwords in two places** (drive + offline disk):
`bash scripts/backup_keystore.sh`. Losing it again means another reset.

## STEP 3 — Put the values in GitHub Actions

GitHub → repo → **Settings → Secrets and variables → Actions** → **Secrets**
tab (NOT "Variables" — Variables are for non-secret config and appear in logs).

Create these 4 **Secrets** (exact names — the workflow reads them):
`CM_KEYSTORE`, `CM_KEYSTORE_PASSWORD`, `CM_KEY_ALIAS`, `CM_KEY_ALIAS_PASSWORD`.
Also add `TMDB_API_KEY` and `OPENROUTER_API_KEY`.

(The same 4 names are what Codemagic's `keystore_credentials` group expects, so
one set of credentials works in both CI systems.)

## STEP 4 — Build the AAB

- **GitHub Actions:** Actions → **Play Store AAB** → Run workflow → download
  `maxplayer-release-aab` from Artifacts.
- **Codemagic:** configure the `keystore_credentials` env group, run
  `android-release`, grab the AAB.
- **Local:** needs Android SDK + JDK:
  ```bash
  flutter build appbundle --release \
    --dart-define=TMDB_API_KEY=... --dart-define=OPENROUTER_API_KEY=...
  ```

## STEP 5 — Upload to Play

Play Console → the existing app → **Production → Create release** → upload the
`.aab`. Play verifies the signature matches its stored key; if it says
"signature mismatch", you skipped STEP 1A (register the upload key first).

If it says "version code must be higher": the old app's current versionCode in
Play is above 149 — bump `version:` in `pubspec.yaml` (e.g. `1.0.1+150`) and
rebuild.

## STEP 6 — App content (for this update you may also need)

1. **Privacy policy URL** — link `PRIVACY_POLICY.md` (hosted or raw GitHub).
   Required because the app uses the microphone.
2. **Sensitive permissions:**
   - Microphone (`RECORD_AUDIO`) → *Voice search on the Discover screen; no
     audio is recorded or stored.*
   - Foreground service (`mediaPlayback`) → *Background/lock-screen playback.*
   - Photos & videos → *Finding and playing device videos.*
   - Biometric → *Unlocking the Private Space.*
3. **Data safety:** everything is local except **Ask AI question text**, sent
   to OpenRouter when you submit a question (never stored). Declare
   "User messages" → shared with OpenRouter → purpose: app functionality.
4. If your Play account was created after Nov 2023: run the required
   **closed test (20 testers, 14 days)** before production.

---

*The single most important fact: you don't have the old key, so an update is
only possible if the old app is on **Play App Signing**. Check that page
first — it's in your Play Console, not something I can change from here.*
