# 1.0.1+68 — tray notifications only

This update replaces the app-side inbox/bell and enable-switch design. It needs a NEW APK installed on the phone; updating the website alone cannot change app behavior.

## Changes
- Remove the floating notification bell and delete NotificationsScreen. No in-app notification list or switch remains.
- Ask Android for notification permission after the initial media-permission request resolves. Check again on app foregrounding if still blocked. A once-per-foreground guard and short cooldown prevent dialog/lifecycle loops. Android controls repeated prompts and permanent denial; there is no forced settings redirect and no bypass of denied permission. Android notification settings remain the system-level way to block or allow notices.
- Use Android permission as the only display gate. An old `push.enabled:false` preference no longer silently suppresses notices.
- Fix the dynamic notice-ID fold runtime type error found by the new display regression test. This could throw before local notification posting.
- Register permitted installations automatically and subscribe to topic `all`; there is no in-app opt-in switch. Keep anonymous auth and existing Firebase rules.
- Post text immediately. Download a picture for at most 10 seconds and 1 MiB, then update the SAME tray ID with BigPicture plus a collapsed large-icon thumbnail. Image failure leaves the text notification present. The second update uses onlyAlertOnce.
- Image bytes are checked for JPEG/PNG/WEBP signatures instead of relying solely on host MIME. Follow at most three redirects, always HTTPS without URL credentials. Keep at most ~20 cached image files rather than deleting immediately after posting. The Android decoder is still the final validity check; malformed images fall back to text.
- A tray tap opens the app; an explicitly supplied HTTPS link opens externally. No inbox route.
- Remove the requested playback-engine text from About without changing the playback engine.
- The admin site's history remains an administrative status log, not an in-app inbox. No sender or Firestore rules changes are required.

## Apply
Run the delivered shell script from the repo root at 1.0.1+67, then use the usual clean/pub-get/analyze/test/commit/push commands. The script deletes lib/screens/notifications_screen.dart. CI compiles the APK; do not build it on the Raspberry Pi.

## Real phone verification (required)
1. Wait for the existing APK workflow to build +68, then install that new APK over the old app. Do not just refresh the website.
2. Open MaxPlayer. Complete the media permission prompt if shown; allow Android notification permission when requested. If you denied permanently, Android may no longer offer the popup. We cannot override that decision.
3. Send ONE short text notice from the admin panel, then ONE picture notice. Previously accepted notices are not resent automatically.
4. Check the phone notification tray. Expand the picture notice: the full picture belongs in Android's expanded layout. The collapsed thumbnail may be small or omitted by the device's Android UI.
5. Repeat in the foreground and background. Ordinary process death and force-stop are different: Android force-stop, OEM battery restrictions, network loss and FCM throttling can prevent/delay data-only delivery. We cannot guarantee every device receives it.
6. If picture loading still fails, provide whether TEXT appeared, whether expanding shows a picture, app build version, phone/Android version and the relevant workflow error if any. Do not send passwords or tokens.

No notification ID screen remains. Personal targeting continues for previously recorded installation UIDs; the simple Everyone sender is unchanged. Old shared/private history documents are not deleted automatically because that would destroy records. This update does not address the separately requested scan/thumbnail or installation-country/count work.

## Validation
Dart analysis: no issues. Flutter suite: 257 passing tests, including permission-channel orchestration, the previous hidden-off preference, and nine image-loader cases (size/header/stream cap, redirects, timeout and signatures). These are mocked/plugin-channel and transport tests, not a real-phone delivery test. A public committed notice image was checked and served HTTP 200 as image/jpeg; that confirms hosting availability for that URL, not phone download/display. No local Android build is claimed. Existing CI/toolchain versions are unchanged.
