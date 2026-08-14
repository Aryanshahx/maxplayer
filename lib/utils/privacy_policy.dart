import 'package:flutter/material.dart';

/// The app's privacy policy, bundled so it can be read offline (also what
/// Play reviewers see when they open the app during review).
///
/// Play Console still needs the public-URL copy: PRIVACY_POLICY.md at the
/// repo root. Keep the two in sync when either changes - the widget test
/// checks that both carry the same anchors (effective date, developer).
const String kPrivacyPolicyText =
    'MAX PLAYER - PRIVACY POLICY\n'
    'Effective date: 13 August 2026\n'
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
    'your device, save screenshots to "Pictures/Max Player", and write AI '
    'subtitle files next to your videos. None of it ever leaves your '
    'device.\n'
    '\n'
    '- Internet: only for two things you trigger yourself - (1) the '
    'one-time download of the AI subtitle model (~142 MB from '
    'huggingface.co) and (2) playing stream URLs you paste or open. '
    'Nothing about you is sent anywhere.\n'
    '\n'
    '- Local network (Wi-Fi / multicast): only when you tap "Cast to TV" - '
    'discovering DLNA televisions on your own Wi-Fi and serving the video '
    'file from your phone to the television. Your Wi-Fi only; no external '
    'server is involved.\n'
    '\n'
    'WHAT THE APP DOES NOT DO\n'
    '\n'
    '- No analytics, no tracking, no advertising, and no third-party SDKs '
    'that collect data.\n'
    '- No accounts, no sign-in, no device identifiers collected.\n'
    '- No collection of your video library contents, file names, or watch '
    'history - all of it stays in the app\'s local storage on your '
    'device.\n'
    '- No crash reporting service. Crash reports are shown to you inside '
    'the app and are only shared if you copy and send them yourself.\n'
    '\n'
    'AI SUBTITLES\n'
    '\n'
    'Subtitle generation runs entirely on your device using the '
    'open-source whisper.cpp engine. Your audio never leaves your phone. '
    'The only network access is the one-time model file download from '
    'Hugging Face, which you trigger and can delete afterwards. Translating '
    'subtitles to English uses the same fully on-device engine - no audio '
    'or text is sent anywhere.\n'
    '\n'
    'PRIVATE FOLDER\n'
    '\n'
    'Videos you hide are moved into the app\'s own protected folder, which '
    'Android blocks other apps from reading, and are unlocked with a PIN '
    'you choose. They never leave your device and are never uploaded; the '
    'PIN is stored only as a cryptographic hash inside the app\'s '
    'settings. Uninstalling the app deletes the protected folder - move '
    'videos out first.\n'
    'If the PIN is forgotten, resetting it requires passing the device\'s '
    'own screen lock (PIN, pattern, password or fingerprint); that unlock '
    'check is performed entirely by Android on your device - nothing is '
    'sent anywhere.\n'
    '\n'
    'PLAYBACK EXTRAS (KARAOKE, SKIP INTRO, THUMBNAILS)\n'
    '\n'
    'Karaoke highlighting and skip-intro detection only read subtitle '
    'files already on your device (AI-generated .srt files or the video\'s '
    'own subtitle file) while you play a video. Library thumbnails are '
    'decoded from your own videos into the app\'s cache folder, which the '
    'system or you can clear at any time. None of this data leaves the '
    'device or is shared anywhere.\n'
    '\n'
    'CHILDREN\n'
    '\n'
    'The app collects no data from anyone, including children.\n'
    '\n'
    'GOOGLE PLAY DATA SAFETY (SHORT ANSWERS)\n'
    '\n'
    '- Data collected: none.\n'
    '- Data shared with third parties: none.\n'
    '- Data sent off this device: none - AI subtitles, watch history, '
    'bookmarks and settings are all local-only.\n'
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
/// "Privacy policy" button.
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
