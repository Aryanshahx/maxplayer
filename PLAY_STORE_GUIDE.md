# Play Store Checklist — Max Player

Everything needed to pass Google Play review, step by step.

## 1. Package name
`com.hypertechlabs.maxplayer` (renamed from the default `com.example.maxplayer`
— Google accepts `com.example.*` technically, but it is unprofessional and the
first-to-claim risk is real). **Once you publish, the package name can never
change again.**

## 2. Versioning
`pubspec.yaml` → `version: 1.0.0+14`. The part after `+` (versionCode) must
**go up by at least 1 on every upload**. Never decrease it.

## 3. App signing (required)
The Play Console rejects debug-signed builds. One-time setup on the Pi:

```bash
cd ~/IdeaProjects/maxplayer
keytool -genkey -v -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias maxplayer
cp android/key.properties.template android/key.properties
nano android/key.properties   # fill in the two passwords you chose
```

Both files are git-ignored. **Back up the .jks + passwords somewhere safe
(cloud/USB). Losing them means you can never update the published app again**
(without Play's reset process).

### For Codemagic CI signing
1. `base64 -w0 android/upload-keystore.jks > /tmp/key.b64` and copy the text.
2. Codemagic → app settings → **Environment variables** → create a group
   named exactly `keystore_credentials` with:
   - `CM_KEYSTORE` = the base64 text
   - `CM_KEYSTORE_PASSWORD` = your store password
   - `CM_KEY_ALIAS` = `maxplayer`
   - `CM_KEY_ALIAS_PASSWORD` = your key password
3. `codemagic.yaml` already turns those into `android/key.properties` at
   build time and signs both APK + AAB with it.

## 4. Build files Codemagic now produces
- `app-release.apk` (sideload/testing)
- `app-release.aab` (**this is the file you upload to the Play Console**)

## 5. Play Console fields (what to answer)
- **Data safety:** No data collected, no data shared. (All offline — see
  `PRIVACY_POLICY.md`.) The only network calls: optional one-time AI model
  download, optional user-opened stream URLs.
- **Privacy policy URL:** host `PRIVACY_POLICY.md` — easiest free option is
  the GitHub repo itself:
  `https://github.com/Aryanshahx/maxplayer/blob/main/PRIVACY_POLICY.md`
  (Play accepts GitHub blob URLs), or GitHub Pages later. The same text is
  also bundled inside the app (⋮ → About Max Player → Privacy policy), so
  reviewers can read it offline during review.
- **Target audience:** 13+ (it's a media player, not child-directed).
- **Content rating questionnaire:** answer honestly — app plays user content,
  no generated/social content features → low ratings everywhere.
- **Permissions declaration:** v112 removed all-files access entirely (Play
  rejected the justification as non-core). The app uses scoped media access
  only: the library scans through MediaStore, cloud imports arrive via
  Android's file picker (SAF), and the Private folder deletes originals
  through the per-file system consent dialog. If the Console still shows an
  old **All files access** declaration from a previous release, open that
  form and state the permission is no longer used before resubmitting - a
  stale form keeps failing review even with the manifest cleaned.
- **Ads declaration:** No ads.
- **News apps / COVID etc.:** all No.

## 6. Android version targeting
`targetSdk 36` ✓ (Play's requirement for new apps as of 2026). `minSdk` comes
from Flutter defaults; whisper needs 24+ and media_kit 21+ — the low floor is
fine.

## 7. 16 KB page-size support (Play requirement)
AGP 9 + NDK default output is 16 KB-aligned, the Flutter 3.44 engine supports
16 KB, and the bundled whisper library is 16 KB-native. **Verify once after
the first CI AAB:** download the AAB from Codemagic, then on the Pi:

```bash
unzip -o app-release.aab -d /tmp/aab >/dev/null
# every .so should print "2**14" (16384) alignment:
find /tmp/aab -name "*.so" -exec sh -c 'objdump -p {} | grep -m1 LOAD' \;
```

If any library shows `2**12` (4096), report which `.so` and I'll pin/fix the
offending lib version.

## 8. Store listing assets needed (not code)
- App icon: already shipped in the app (mipmap). Also upload 512×512 PNG.
- Feature graphic 1024×500 PNG.
- At least 2 phone screenshots (take them from your Samsung).

## 9. Testing tracks
Upload the AAB to **Internal testing** first → install from Play on your own
phone → verify everything works → then promote to production. This catches
"works on my sideload APK but not on Play" issues for free.
