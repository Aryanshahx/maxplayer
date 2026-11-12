# Push update 1 — 1.0.1+67

This update contains Android app support and Firestore rules only. It does NOT yet contain the GitHub sender or authenticated admin page. The old in-app broadcast dialog is removed. The old dashboard broadcast sender is retired by the new rules; it cannot send tray pushes.

## Console setup now
1. Open Firebase project **max-player-cd43d**.
2. Authentication → Get started → Sign-in method → enable **Anonymous** and **Email/Password**. If you restrict API keys, ensure Firebase Authentication is permitted.
3. Authentication → Users → Add user. Create your admin email with a unique long password. Do not put that password in code or share it in chat.
4. Copy that user's UID. Firestore → `(default)` → create collection `admins`, document ID exactly that UID, field `enabled` boolean `true`. The current rules treat existence of the document as membership; delete the document to revoke membership, not just its field.
5. Publish the repository's complete `firestore.rules`. Admin SDK will bypass these rules; a browser cannot edit notice status.
6. Project Settings → Cloud Messaging → verify Firebase Cloud Messaging API (V1) is enabled. If disabled, enable it for this project in Google Cloud Console.
7. Build using your existing GitHub APK workflow, install on a phone with Google Play services, open the bell button on the library screen, then turn on Android notifications. This is the only point the app requests permission. Copy the installation ID for individual targeting.

Existing project client values are reused in `android/app/src/main/res/values/firebase_config.xml` and AppAnalytics; no service-account keys are in these files. No google-services Gradle plugin or project toolchain upgrade is added. Do not also add a generated resource file with duplicate names without replacing this configuration approach.

## Next update's sender contract
- Private queue: `notices/{noticeId}`. Admin creates `title` (1–80), `message` (0–900), `target` (`all` or anonymous UID), `status: pending`, `createdAt` server timestamp. Optional `link` (HTTPS) and `imageData` (`data:image/jpeg;base64,...`). Rules cap imageData at 420,000 characters. Browser must also cap decoded JPEG to ~300 KB and check full UTF-8 document payload comfortably below 1 MiB.
- Workflow: use firebase-admin, enforce max 10 notices/hour, claim transactionally, explicit duplicate/retry policy, publish `imageData` to orphan `notice-images` branch using GITHUB_TOKEN, set imageUrl and delete imageData, then send **data-only**, high-priority Android messages.
- FCM data keys (all strings): `noticeId`, `title`, `message`, optional `image` (HTTPS imageUrl), optional `link` (HTTPS). Topic `all`. Personal sends read `users/{uid}/tokens`, using token fields, NOT document IDs.
- Successful all-users history: `publishedNotices/{noticeId}`. Personal history: `users/{uid}/inbox/{noticeId}`. Fields: title, message, imageUrl, link, createdAt timestamp. Do not publish private queue/error fields to users. Use the same notice ID everywhere.
- Status fields are service-account-only. Record FCM acceptance, not 'phones reached'. Invalid tokens may be deleted only for permanent token errors, not transient failures.
- Add workflow_dispatch and schedule, concurrency control, branch filters so image commits do not build APKs or deploy Pages. There are no time guarantees for dispatch or schedules.

## App behavior
- Anonymous Firebase UID identifies an installation, not a verified person. It can change after clearing app data or reinstalling.
- Enable subscribes to `all` and stores an own token document. Disable unsubscribes, removes current token, deletes the token and cancels local notifications. Offline disable can fail and shows an error; it is not silently claimed successful.
- HTTPS image fetch: 10-second total deadline, 1 MiB byte cap, image MIME type, no redirects. Any failure falls back to text. The app is independent of the hosting provider.
- Foreground/background data messages use flutter_local_notifications. Force-stopped apps, OEM restrictions, Doze, FCM throttling and denied permissions can prevent/delay display. No guaranteed delivery.
- Notification tap opens the inbox and asks before opening an external HTTPS link.
- Inbox fetches at most the latest 50 shared notices and 50 private notices; local read dots are installation-local. Automatic pagination can be added later.
- Small icon is a white play symbol; accent is #8b5cf6. No scheduled notifications or exact-alarm permission.

## Security / migration notes
- New notices queue and tokens are protected by Firebase Authentication rules. Admin existence checks are not a browser PIN.
- Reports now require admin authentication to read. Until the authenticated dashboard update is deployed, the old dashboard's reports refresh may show 403. Existing stats reads/writes remain public for backward compatibility and are not trustworthy install counts; hardening that unrelated legacy analytics requires migration.
- No private sending credential in the APK or website. Service-account JSON and GitHub dispatch token will be configured in the next sender/admin updates, not this app update.
- Spark/FCM/GitHub quotas still apply. No promise of unlimited free users or precise delivery counts.

## Validation boundary
Dart analysis and Flutter tests are run locally. Android compilation is intentionally left to GitHub Actions; no APK was built locally. Real FCM delivery, Firebase Auth configuration, Firestore rule behavior on the deployed project and notification rendering on a device still require integration testing. No emulator rule test is claimed.
