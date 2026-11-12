# MAX PLAYER - PRIVACY POLICY

**Effective date:** 5 September 2026
**Developer:** Hyper Tech Labs (Aryan Shah)

## The short version

Max Player is a local video player. It does not collect, store, transmit, or
share any personal data of its own. Everything the app does happens on your
device. The app shows ads via Google AdMob — see "Ads (Google AdMob)" below.

## What the app accesses, and why

- **Storage (videos / all files):** to find and play the videos stored on your
  device, play videos you pick in Android's file picker, and save screenshots
  to "Pictures/Max Player". None of it ever leaves your device.
- **Internet:** only for features you trigger yourself — TMDB movie discovery,
  the Ask AI feature, stream URLs you open, and loading ads. Nothing personal
  about you is sent anywhere by Max Player itself.

## Anonymous usage statistics (Firebase)

The app counts anonymous, aggregate activity so the developer can see how
many people use the app and which free stream sources are broken: app
opens, number of plays (videos / streams / live TV channels), ad
impressions, and playback failures with a coarse reason (for example
"timeout") plus the failing HOST (for example "example.com") — never the
full URL, and never a file name, folder name, video title, or search term.
Version 1.0.1+65 adds: the COUNTRY of the install (from the device's
language/locale setting — no GPS), the device-local HOUR of app opens, the
total time spent in the app per day, and crash / playback-failure reports
(engine error text and failing stream HOST only). All of it is aggregated
or anonymised, queued offline, and sent when the network returns.

The counts are attached to a random, per-device identifier with no sign-in
and no personal information. Data lives in Google Firebase
(https://firebase.google.com/support/privacy). Nothing here can identify
you or what you watched.

## Ads (Google AdMob)

The app shows banner and occasional full-screen (interstitial) ads served by
Google AdMob. To do this, the AdMob SDK may access your device's advertising
ID, approximate (non-precise) location, and basic device information,
according to Google's policy: https://policies.google.com/privacy

You can turn ad personalisation off at any time in your device settings
(Settings > Google > Ads > Remove advertising ID) — ads will then be
non-personalised. Users in the EEA/UK are asked for consent through Google's
UMP dialog on first launch.

## Cloud storage import (Android file picker)

Opening Android's built-in file picker lists the storage apps installed on
your device (Google Drive, Dropbox, OneDrive, ...). There is no sign-in,
account, or OAuth of any kind inside Max Player; the system hands the app a
one-time, read-only grant for the one video you choose. Nothing is uploaded.

## Private folder

Videos you hide are removed from the library and unlocked with a PIN you
choose. They never leave your device; the PIN is stored only as a
cryptographic hash inside the app's settings. Uninstalling removes the app's
private data — move videos out first if you want to keep them.

## Watch statistics

Counts your watch time in the app's own local storage for the weekly chart
and "Most watched" list. This data never leaves the device.

## Children

Max Player itself collects no data from anyone, including children.

## Google Play Data Safety (short answers)

- Data collected by Max Player itself: none.
- The AdMob advertising SDK (Google) may process your advertising ID and
  approximate location as described above.

## Contact

Hyper Tech Labs (Aryan Shah) — via the GitHub repository.
