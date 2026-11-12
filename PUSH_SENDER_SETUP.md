# Update 2: GitHub Actions sender (app version stays 1.0.1+67)

## What this update does
- Adds `.github/workflows/send-notices.yml` and a locked Node.js 22 sender using the official firebase-admin SDK.
- Uses FIREBASE_SERVICE_ACCOUNT exclusively from GitHub Actions secrets. Checks project_id equals max-player-cd43d.
- Processes pending notices, atomically claims each, and enforces at most 10 starts in a rolling hour. Rate-limited notices stay pending.
- Accepts browser-resized JPEG data (max 300 KiB decoded). Commits images to a separate orphan `notice-images` branch with the workflow's GITHUB_TOKEN, preserving prior images. A new branch is created automatically.
- Uses `https://raw.githubusercontent.com/Aryanshahx/maxplayer/notice-images/notices/<noticeId>.jpg`. Verifies availability before sending. Deletes imageData after upload and records imageUrl.
- All-users sends use topic `all`, not token enumeration. Individual sends use users/{uid}/tokens, in batches up to 500, with an explicit 1000-token safety cap per installation. Deletes only permanently invalid tokens.
- Publishes successful shared history in publishedNotices or personal history in users/{uid}/inbox. Never exposes the private queue to ordinary app users.
- Never automatically retries a notice after an uncertain send. A terminated runner is marked failed/uncertain after 20 minutes during a later run. Exactly-once delivery cannot be guaranteed; examine an uncertain notice before creating a replacement.
- Counts FCM acceptance, not phones reached. Partial individual success is sent with failedTokens/errors retained.

## Hand setup
1. Confirm the repository Actions secret FIREBASE_SERVICE_ACCOUNT exists and belongs to max-player-cd43d. Never commit the JSON file.
2. Commit/push this script's changes to main. Repository Settings → Actions → General must permit GitHub Actions. The workflow requests contents: write to create/update the image branch. Organization/repository restrictions can still block it; if so, review the job error rather than exposing a personal token.
3. GitHub → Actions → **Send MaxPlayer notices** → **Run workflow** → branch main → Run workflow.
4. Open the job. With no pending queue records, it should report 'Checked 0 pending notice(s)'. That verifies backend access without sending a test notification.
5. If the job fails with a project mismatch, replace the secret with a key from the correct Firebase project. If it reports IAM permission errors, confirm the service-account identity has the required Firestore data access and FCM send permissions; do not make Firestore rules public. Server SDK authorization uses IAM, not the client rules.
6. Do not create production test notices accidentally: the sender is live as soon as scheduled/manual runs find pending records. Wait for the authenticated admin page to send a deliberate test.

The workflow is manually runnable and scheduled every five minutes. GitHub may delay or skip scheduled runs; schedules can be disabled after prolonged inactivity in a public repo. This is not an instant-delivery guarantee. The schedule checks the default branch; main is used by this repository.

## Admin page comes next
The old PIN-only panel is still incompatible with the protected queue. The next update adds email/password login, admin membership validation, gallery picker, preview, status/history and workflow dispatch.

For dispatch later, create a fine-grained GitHub token limited to Aryanshahx/maxplayer with Actions read/write (metadata read is implicit). It belongs only in your browser settings, never in source. It is NOT used to commit pictures; the sender uses built-in GITHUB_TOKEN.

## Queue contract
Admin creates notices/{noticeId} with title (max80), message (max900), target ('all' or anonymous installation UID), status 'pending', createdAt server timestamp. Optional HTTPS link; optional JPEG data URL in imageData. No browser-written status changes. Sender fields include sending/sent/failed, claimedAt, runId, finishedAt, acceptedRequests, acceptedTokens, failedTokens, tokenCount, errors/warnings or error/outcomeUncertain.

FCM data: noticeId, title, message, optional image (HTTPS public URL), optional link. All values are strings. Data-only Android high-priority messages, TTL 24h. A conservative UTF-8 byte check can reject a message under 900 characters if it exceeds FCM's payload budget; shorten it and create a new notice. Phones may block/delay delivery when force-stopped, permissions denied or affected by battery restrictions.

## Branch/build safety and storage
Existing APK workflow triggers only main pushes, AAB only version tags. Neither triggers on image-branch commits. The orphan branch contains only images, not main's app files or workflows. GitHub-token pushes also have GitHub's normal recursion protection. Keep Pages publishing from its existing main/admin source or Actions workflow; do not change it to notice-images.

Images are PUBLIC. Never upload private pictures. No automatic deletion is included in this update. Optional 60-day cleanup is deferred: removing branch history does not guarantee immediate removal of GitHub's retained objects, and breaks pictures in older notices. GitHub repository/storage limits still apply. Spark, Actions and FCM have limits; no unlimited-use promise.

## Validation
17 tests (including an SDK import smoke check) cover notice fields, targeting, links, JPEG envelope/byte caps, rolling window, UTF-8 message budget, token-error classification and app payload contract. Node 22 syntax and SDK imports are checked. Dependency audit had zero reported vulnerabilities when tested. No real Firebase credentials or device were used locally; Firestore transactions, GitHub writes and FCM delivery require the first real workflow/integration test. Credentials are not requested in chat.
