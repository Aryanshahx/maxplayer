import 'package:flutter/material.dart';

/// The app's privacy policy, bundled so it can be read offline (also what
/// Play reviewers see when they open the app during review).
///
/// Play Console still needs the public-URL copy: PRIVACY_POLICY.md at the
/// repo root. Keep the two in sync when either changes - the widget test
/// checks that both carry the same anchors (effective date, developer).
const String kPrivacyPolicyText =
    "MAX PLAYER - PRIVACY POLICY\n\nEffective date: 5 September 2026  \nDeveloper: Hyper Tech Labs (Aryan Shah)  \nApp policy update: 1.0.1+69\n\nThe short version\nMax Player plays media locally. It also uses online services for aggregate usage statistics, diagnostics, Android push notifications, optional online features and advertising. Your media library is not uploaded by the analytics or notification features. The data described below does leave the device; this policy replaces older statements that the app has no analytics or identifiers.\n\nMedia access and private folder\nStorage permissions let the app find/play local media and save screenshots. Local watch lists, file organisation and private-folder settings remain on-device. Private-folder PIN protection uses local storage and Android device authentication; it does not upload the hidden videos. Uninstalling or clearing app data removes app-private settings; move protected files out first as appropriate.\n\nAggregate activity and diagnostics (Firebase)\nThe app records aggregate opens, install registrations, play events, ad impressions, playback failures, device-local hour buckets and foreground session duration. Captured error reports may include error text, a failure category, app version and failing stream host. Full stream URLs, video titles and library filenames are not intentionally included in the aggregate counters. Diagnostic text is best-effort and may contain technical details. Offline Firebase writes may be queued locally for later transmission. Abrupt termination can leave activity unrecorded.\n\nFirebase Anonymous Authentication creates a pseudonymous installation UID. Notification registration stores that UID and FCM tokens in Firebase; it is not a verified personal identity. Clearing app data or reinstalling can change the UID and cause a new registration. Aggregate counters are not verified counts of people or current installs. Firebase privacy: https://firebase.google.com/support/privacy\n\nApproximate IP country (starting with +69)\nThe app requests https://api.country.is/ to estimate the country of the connection. That provider necessarily receives the connection IP. The app extracts only the returned two-letter country code; it does not retain or forward the provider's returned IP field to Firebase. Country data is recorded as a best-effort aggregate sample, once per successful registration in local app storage, including upgrades. GPS permission, coordinates, city and address are not requested by this feature.\n\nIf the request fails, country remains unknown and may be retried on a later app launch. Locale is not used as a fallback. VPNs, proxies, mobile routing and provider inaccuracies can change the result. The sample describes the first successful lookup, not a continually tracked location or historical download country. Old locale-based country totals are no longer shown in the new panel. Provider information: https://country.is/\n\nAndroid push notifications\nMax Player requests Android notification permission after the media permission request finishes and checks it when the app is foregrounded. Android controls repeat prompts and permanent denial. There is no separate app notification switch or inbox; use Android's system notification settings to allow/block notifications.\n\nPermitted installations subscribe to general FCM notices, and their tokens can be used for installation-specific notices. FCM processing uses Google services. Notice pictures are downloaded from publisher-selected HTTPS hosts, including public GitHub image URLs; those hosts receive the network connection IP. External links open only when selected through the app/notification flow. Delivery is not guaranteed. The app does not currently report a confirmed-delivery/read counter to the admin panel.\n\nAdvertising and online features\nGoogle AdMob may process advertising identifiers, approximate location and device information under Google's policy: https://policies.google.com/privacy. Users in supported consent regions are presented Google's UMP consent flow. Advertising choices may also be available in Android's Google/Ads settings.\n\nMovie discovery, AI features, partner links and network streams use their respective providers when invoked. Stream hosts and linked websites receive network requests. Clearly labelled partner links may earn a commission. Review those providers' policies before sharing information.\n\nCloud storage import\nCloud imports use Android's file picker and your installed storage provider. The app receives the file access grant chosen by you rather than a cloud account password. The media picker/provider handles its own sign-in. Anonymous Firebase registration for notifications is separate from cloud storage access.\n\nChildren and Google Play Data Safety\nThe app includes analytics, diagnostics, approximate country lookup, identifiers and advertising as described here; it must not be described as collecting no data. The developer must keep Google Play Data Safety and any applicable audience/consent configuration consistent with the actual app and SDK behaviour. This policy is not a claim of certification or legal compliance.\n\nContact and requests\nContact Hyper Tech Labs (Aryan Shah) through https://github.com/Aryanshahx/maxplayer. Do not post passwords, tokens or private information in public issues. Ask for a private channel for data-related requests. Pseudonymous token/installation records and aggregate counters have different identification and deletion limitations; aggregates may not be attributable to a particular person. Policy changes are published in this repository and bundled in the app.\n";

/// Dialog showing [kPrivacyPolicyText]. Opened from the About sheet's
/// "Privacy policy" button and the home ⋮ menu.
void showPrivacyPolicyDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1b1b24),
      title: const Text(
        'Privacy policy',
        style: TextStyle(color: Colors.white, fontSize: 17),
      ),
      scrollable: true,
      content: const Text(
        kPrivacyPolicyText,
        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
