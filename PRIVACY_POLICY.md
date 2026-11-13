# MAX PLAYER - PRIVACY POLICY

**Effective date:** 5 September 2026  
**Developer:** Hyper Tech Labs (Aryan Shah)  
**App policy update:** 1.0.1+70

## The short version
Max Player plays media locally. It also uses online services for aggregate usage statistics, diagnostics, Android push notifications, optional online features and advertising. Your media library is not uploaded by the analytics or notification features. The data described below does leave the device; this policy replaces older statements that the app has no analytics or identifiers.

## Media access and private folder
Storage permissions let the app find/play local media and save screenshots. Local watch lists, file organisation and private-folder settings remain on-device. Private-folder PIN protection uses local storage and Android device authentication; it does not upload the hidden videos. Uninstalling or clearing app data removes app-private settings; move protected files out first as appropriate.

## Aggregate activity and diagnostics (Firebase)
The app records aggregate opens, install registrations, play events, ad impressions, playback failures, device-local hour buckets and foreground session duration. Captured error reports may include error text, a failure category, app version and failing stream host. Full stream URLs, video titles and library filenames are not intentionally included in the aggregate counters. Diagnostic text is best-effort and may contain technical details. Offline Firebase writes may be queued locally for later transmission. Abrupt termination can leave activity unrecorded.

Firebase Anonymous Authentication creates a pseudonymous installation UID. Notification registration stores that UID and FCM tokens in Firebase; it is not a verified personal identity. Clearing app data or reinstalling can change the UID and cause a new registration. Aggregate counters are not verified counts of people or current installs. Firebase privacy: https://firebase.google.com/support/privacy

## Approximate IP country (starting with +69)
The app requests https://api.country.is/ to estimate the country of the connection. That provider necessarily receives the connection IP. The app extracts only the returned two-letter country code; it does not retain or forward the provider's returned IP field to Firebase. Country data is recorded as a best-effort aggregate sample, once per successful registration in local app storage, including upgrades. GPS permission, coordinates, city and address are not requested by this feature.

If the request fails, country remains unknown and may be retried on a later app launch. Locale is not used as a fallback. VPNs, proxies, mobile routing and provider inaccuracies can change the result. The sample describes the first successful lookup, not a continually tracked location or historical download country. Old locale-based country totals are no longer shown in the new panel. Provider information: https://country.is/

## Android push notifications
Max Player requests Android notification permission after the media permission request finishes and checks it when the app is foregrounded. Android controls repeat prompts and permanent denial. There is no separate app notification switch or inbox; use Android's system notification settings to allow/block notifications.

Permitted installations subscribe to general FCM notices, and their tokens can be used for installation-specific notices. FCM processing uses Google services. Notice pictures are downloaded from publisher-selected HTTPS hosts, including public GitHub image URLs; those hosts receive the network connection IP. External links open only when selected through the app/notification flow. Delivery is not guaranteed. The app does not currently report a confirmed-delivery/read counter to the admin panel.

## Advertising and online features
Google AdMob may process advertising identifiers, approximate location and device information under Google's policy: https://policies.google.com/privacy. Users in supported consent regions are presented Google's UMP consent flow. Advertising choices may also be available in Android's Google/Ads settings.

Movie discovery, AI features, partner links and network streams use their respective providers when invoked. Stream hosts and linked websites receive network requests. Clearly labelled partner links may earn a commission. Review those providers' policies before sharing information.

## Cloud storage import
Cloud imports use Android's file picker and your installed storage provider. The app receives the file access grant chosen by you rather than a cloud account password. The media picker/provider handles its own sign-in. Anonymous Firebase registration for notifications is separate from cloud storage access.

## Children and Google Play Data Safety
The app includes analytics, diagnostics, approximate country lookup, identifiers and advertising as described here; it must not be described as collecting no data. The developer must keep Google Play Data Safety and any applicable audience/consent configuration consistent with the actual app and SDK behaviour. This policy is not a claim of certification or legal compliance.

## Contact and requests
Contact Hyper Tech Labs (Aryan Shah) through https://github.com/Aryanshahx/maxplayer. Do not post passwords, tokens or private information in public issues. Ask for a private channel for data-related requests. Pseudonymous token/installation records and aggregate counters have different identification and deletion limitations; aggregates may not be attributable to a particular person. Policy changes are published in this repository and bundled in the app.

## Feature and error diagnostics update (+70)
Aggregate counters now include opens of Discover, Private folder, Folders, Playlists, Audio, Network storage, Cloud storage and Quick Share from the library. They do not contain media names, private-folder contents, queries or network credentials. A private-folder screen open does not mean the folder was unlocked.

Captured Flutter/uncaught Dart errors include bounded exception text, stack trace, timestamp, app version and a random report ID. This technical text can contain application context; avoid putting secrets in exception messages. The most recent pending report is kept locally until acknowledged where possible and retried after reopening the app. Playback failures are no longer uploaded as app-crash reports. This is not guaranteed capture of native crashes, ANRs or process kills.

### Remote appearance and admin maintenance (+72)
Compatible installations read a public, non-secret published appearance configuration and cache its validated palette/header settings locally. Theme reads use the existing Firebase project; no additional theme-image/font host is used. Admin theme templates are access-controlled. Notification data can contain an allowlisted internal screen destination or an external HTTPS link; the private vault's existing authentication still applies. Admins may export recorded analytics/diagnostics, including full captured technical report text; such exports must be handled privately. An explicit privileged maintenance action can delete stored analytics counters and diagnostic reports without deleting device tokens, admin accounts, themes or notices. Connected/offline devices may subsequently send queued or new events, so resetting stored data does not erase local installation identifiers or revoke notification registration.
