import 'package:flutter/material.dart';

/// The app's privacy policy, bundled so it can be read offline (also what
/// Play reviewers see when they open the app during review).
///
/// Play Console still needs the public-URL copy: PRIVACY_POLICY.md at the
/// repo root. Keep the two in sync when either changes - the widget test
/// checks that both carry the same anchors (effective date, developer).
const String kPrivacyPolicyText =
    'MAX PLAYER - PRIVACY POLICY\n'
    'Effective date: 5 September 2026\n'
    'Developer: Hyper Tech Labs (Aryan Shah)\n'
    '\n'
    'THE SHORT VERSION\n'
    'Max Player is a local video player. It does not collect, store, '
    'transmit, or share any personal data. Everything the app does happens '
    'on your device.\n'
    '\n'
    'WHAT THE APP ACCESSES, AND WHY\n'
    '\n'
    '- Storage (videos / all files): to find and play the videos stored on '
    'your device, play videos you pick in Android\'s file picker, and save '
    'screenshots to "Pictures/Max Player". None of it ever leaves your '
    'device.\n'
    '\n'
    '- Internet: only for features you trigger yourself - TMDB movie '
    'discovery, the Ask AI feature, and stream URLs you open. Nothing '
    'personal about you is sent anywhere.\n'
    '\n'
    'WHAT THE APP DOES NOT DO\n'
    '\n'
    '- No analytics, no tracking, no advertising, and no third-party SDKs '
    'that collect data.\n'
    '- No Max Player accounts and no device identifiers collected (cloud '
    'imports go through Android\'s file picker - strictly between you and '
    'the storage app).\n'
    '- No collection of your video library contents, file names, or watch '
    'history - all of it stays in the app\'s local storage on your '
    'device.\n'
    '- No crash reporting service. Crash reports are shown to you inside '
    'the app and are only shared if you copy and send them yourself.\n'
    '\n'
    'CLOUD STORAGE IMPORT (ANDROID FILE PICKER)\n'
    '\n'
    'Library - Cloud Storage opens Android\'s built-in file picker, which\n'
    'lists the storage apps installed on your device - your Google Drive\n'
    'app, Dropbox, OneDrive, and others. There is no sign-in, account, or\n'
    'OAuth of any kind inside Max Player, and the app never sees your\n'
    'cloud file list: the system hands Max Player a one-time, read-only\n'
    'grant for just the one video you choose. Nothing is uploaded\n'
    'anywhere.\n'
    '\n'
    'PRIVATE FOLDER\n'
    '\n'
    'Videos you hide are removed from the library and unlocked with a PIN '
    'you choose. They never leave your device and are never uploaded; the '
    'PIN is stored only as a cryptographic hash inside the app\'s '
    'settings. Uninstalling the app removes the app\'s private data - move '
    'videos out first if you want to keep them.\n'
    'If the PIN is forgotten, resetting it requires passing the device\'s '
    'own screen lock (PIN, pattern, password or fingerprint); that unlock '
    'check is performed entirely by Android on your device - nothing is '
    'sent anywhere.\n'
    '\n'
    'WATCH STATISTICS\n'
    '\n'
    'The Statistics screen counts your watch time (per day and per video) '
    'in the app\'s own local storage so the weekly chart and "Most '
    'watched" list work. This data never leaves the device and is deleted '
    'when you uninstall the app.\n'
    '\n'
    'CHILDREN\n'
    '\n'
    'The app collects no data from anyone, including children.\n'
    '\n'
    'GOOGLE PLAY DATA SAFETY (SHORT ANSWERS)\n'
    '\n'
    '- Data collected: none.\n'
    '- Data shared with third parties: none.\n'
    '- Data sent off this device: only what you trigger - Drive file '
    'listings and streams travel between your phone and Google while '
    'you use Cloud Storage; everything else is local-only.\n'
    '- Because no data leaves the device, "encryption in transit" and '
    '"account/data deletion requests" do not apply: nothing is transmitted '
    'and there is nothing on any server to delete.\n'
    '\n'
    'CHANGES\n'
    '\n'
    'Any change to this policy is published in PRIVACY_POLICY.md in the '
    'public repository with a new effective date.\n'
    '\n'
    'CONTACT\n'
    '\n'
    'Questions: open an issue on github.com/Aryanshahx/maxplayer';

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
