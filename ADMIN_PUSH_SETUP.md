> **Updated by +69:** See ADMIN_REDESIGN.md. Notification history was removed and locale-based country charts replaced with new IP samples. Authentication and token instructions below still apply.

# Update 3 — authenticated admin panel

The app version stays **1.0.1+67**. No app, toolchain, sender or Firestore rules changes are included. Apply after the app/rules and GitHub sender updates.

## 1. Deploy
Commit and push the update to main. Keep GitHub Pages configured to publish the existing site. When deployment completes open:
https://aryanshahx.github.io/maxplayer/admin/
If it still asks for the old PIN, hard-refresh/clear the site's cached files or open once in a private tab. Do not open index.html directly from a file:// URL; use GitHub Pages (the page loads local JavaScript modules).

## 2. Sign in
Use the email/password account you created under Firebase Authentication → Users in **max-player-cd43d**, NOT your Google account password unless that is separately the password you deliberately set for this Firebase email account.
- Enable Email/Password sign-in in Firebase Authentication.
- Firestore `(default)` must contain `admins/{that user's UID}`. Current rules use document existence as membership. Delete the document to revoke; enabled:false does not revoke.
- Keep the push update's published rules. No public notice permissions are needed.
- The page verifies membership, sends Firebase ID tokens on Firestore requests and refreshes expired tokens. Firebase refresh token is stored in sessionStorage so the same tab stays signed in after refresh. Password is not saved by page code (your browser may separately offer its password manager).
- Sign out clears the page session and dispatch token, including an explicitly remembered token. Use only a trusted browser/device.
- If a web API-key restriction blocks Firebase Auth, inspect the error and verify this project's API-key restrictions support this web client. Do not expose private credentials or blindly disable restrictions.
- This REST-based page does not provide App Check attestation. If you have enforced App Check for these browser API calls, tell us before changing enforcement. The sender's service-account access does not prove the browser is allowed.

## 3. Add a GitHub dispatch token (for immediate start requests)
1. In GitHub open your profile picture → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token. Direct page: https://github.com/settings/personal-access-tokens/new
2. Choose yourself as Resource owner and a sensible expiration.
3. Repository access: Only select repositories → **maxplayer**.
4. Repository permissions: **Actions → Read and write**. Metadata read is implicit. Do not add Contents write to this browser token.
5. Generate and copy the token. Do not share it in chat or commit it.
6. In the admin panel open **Sender settings**, paste the token and click **Save token**.
7. Default storage is sessionStorage (this tab). Optional Remember stores it in localStorage until forgotten, sign-out, expiration or revocation. Both are readable by scripts on the same origin. This page loads no third-party JavaScript and uses a restrictive CSP, but browser storage is NOT a secure vault. Other same-origin GitHub Pages sites under your account may share access.
8. The Firebase service-account JSON belongs ONLY in GitHub Secrets. NEVER paste it in this token field.

Missing/expired/insufficient dispatch token does not undo a successfully queued notice. The panel says queued, reports the dispatch failure and warns not to submit again. Scheduled sender runs can still process it. GitHub dispatch acceptance means the run was requested, not that it started immediately or sent the message.

## 4. First phone test
1. Install the CI-built +68 app and open it. Complete the media permission request, then allow Android notification permission when requested. There is no notification bell, inbox or in-app switch. Devices need compatible Google Play services.
2. Individual targeting needs a previously recorded installation UID. This simplified app no longer exposes an inbox/ID screen; otherwise use Everyone for a deliberate controlled test.
3. Sign in to the panel. If you have the installation UID, choose **One installation** and paste it. Otherwise choose Everyone, remembering that all registered installations can receive the test. The UID is not a username, email, FCM token or admin UID.
4. Enter a short title/message. For the first test omit a picture. Click Queue and Send and confirm the target.
5. Watch the status/history. Pending means awaiting a sender (including hourly throttling), sending means processing, sent means accepted by FCM, failed shows the recorded error.
6. Confirm the phone notification manually. FCM acceptance is not proof of phone delivery. Foreground, background and process-not-running tests should be separate; force-stop and battery restrictions can prevent delivery.
7. Next test a gallery picture; only after individual testing use Everyone.

## Pictures
Browser decodes the selected image, resizes its long side to at most 1080 px, flattens transparency on white and exports JPEG quality 0.8. If still over 300 KiB, it refuses and asks for a smaller picture. It does not silently upload the original.
The complete draft is checked under a safe 900,000-byte Firestore budget; imageData is under 420,000 characters. Sender uploads it to the public notice-images branch, then deletes imageData from Firestore. Never select private images. No free/unlimited storage guarantee.

## Reliability / history
- Creation uses a REST commit with server-side createdAt (REQUEST_TIME) and exists:false precondition, matching the rules.
- A saved attempt reuses the same UUID after an interrupted commit; retry first checks the same ID, rather than silently duplicating the message. After reload the original draft is restored. When an attempt is saved, retry uses that original draft, not later edits. Check history before replacing an uncertain attempt.
- Live history queries at most 30 notices with selected status fields (not large imageData), roughly every 15 seconds while the tab is visible. This is polling, not a WebSocket listener. It consumes Firestore reads. Analytics refreshes every minute; reports fetch the newest 100; older reports are not guaranteed in the PDF. Legacy stats pagination is retained.
- Status details can mention uncertain delivery after an interrupted runner. Never automatically resend such notices; check the phone/logs first.
- Anonymous installation IDs can change when app data is cleared/reinstalled. Topic sends do not return a phone count. Individual counts refer to FCM token acceptance, not verified people or devices.

## Existing analytics
Custom dates, charts, locale-country table, reports and print-to-PDF are preserved and now use authenticated requests. The print report uses your browser's Save as PDF destination; no external PDF library. All-time installs/countries are still labelled all-time. This update does NOT implement date-based historical installs, exact uninstall/current-install counts, or geographic correction of locale-based country data.

## Validation boundary
13 pure Node tests and JavaScript syntax checks; Chromium tests with mocked Firebase/GitHub HTTP cover non-admin rejection, login, refreshed login, expired-token refresh, gallery resizing, server timestamp commit, targeting, dispatch success/failure, lost-commit-response recovery, XSS-safe history, print report, mobile overflow and sign-out. No real password, dispatch token or service-account key was used locally. Live email login, production rules, workflow dispatch, image-branch upload and device delivery require the first real test above. Automated browser fixtures are not shipped as live data.
