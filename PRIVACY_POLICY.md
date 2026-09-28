# Max Player — Privacy Policy

**Effective date: 5 September 2026**
**Developer: Hyper Tech Labs (Aryan Shah)**

This is the public copy of the in-app privacy policy (also bundled inside the
app under ⋮ → Privacy policy). Link this file (or a hosted copy) in the Play
Console listing's "Privacy policy" field.

---

## The short version

Max Player is a local video player. It does not collect, store, transmit, or
share any personal data. Everything the app does happens on your device.

## What the app accesses, and why

- **Storage (videos / all files):** to find and play the videos stored on your
  device, play videos you pick in Android's file picker, and save screenshots
  to `Pictures/Max Player`. None of it ever leaves your device.
- **Microphone:** only for the voice-search button on the Discover screen.
  Speech is processed by Android's system speech service; the app does not
  record or store audio.
- **Internet:** only for features you trigger yourself — TMDB movie discovery,
  the Ask AI feature, and stream URLs you open. Nothing personal about you is
  sent anywhere.

## What the app does NOT do

- No analytics, no tracking, no advertising, and no third-party SDKs that
  collect data.
- No Max Player accounts and no device identifiers collected (cloud imports go
  through Android's file picker — strictly between you and the storage app).
- No collection of your video library contents, file names, or watch history —
  all of it stays in the app's local storage on your device.
- No crash-reporting service. Crash reports are shown to you inside the app
  and are only shared if you copy and send them yourself.

## Cloud storage import (Android file picker)

Library → Cloud Storage opens Android's built-in file picker, which lists the
storage apps installed on your device — your Google Drive app, Dropbox,
OneDrive, and others. There is no sign-in, account, or OAuth of any kind inside
Max Player, and the app never sees your cloud file list: the system hands Max
Player a one-time, read-only grant for just the one video you choose. Nothing
is uploaded anywhere.

## Private folder

Videos you hide are removed from the library and unlocked with a PIN you
choose. They never leave your device and are never uploaded; the PIN is stored
only as a cryptographic hash inside the app's settings. Uninstalling the app
removes the app's private data — move videos out first if you want to keep
them.

If the PIN is forgotten, resetting it requires passing the device's own screen
lock (PIN, pattern, password or fingerprint); that unlock check is performed
entirely by Android on your device — nothing is sent anywhere.

## Watch statistics

The Statistics screen counts your watch time (per day and per video) in the
app's own local storage so the weekly chart and "Most watched" list work. This
data never leaves the device and is deleted when you uninstall the app.

## Ask AI

The Ask AI feature (Discover screen) sends the question you type, together with
the movie's title/year/rating/overview, to a third-party AI provider
(OpenRouter) so it can answer. This happens only when you submit a question,
and the text is not stored by Max Player. When no AI key is configured or there
is no internet, the answer is generated locally on your device instead.

## Children

The app collects no data from anyone, including children.

## Google Play Data Safety (short answers)

- **Data collected:** none (except your Ask AI question text, sent only to the
  AI provider you trigger it with — never stored).
- **Data shared with third parties:** only the Ask AI question you submit,
  sent to OpenRouter for answering.
- **Data sent off this device:** only what you trigger — Drive file listings
  and streams travel between your phone and Google while you use Cloud
  Storage; everything else is local-only.
- Because no personal data is stored, "encryption in transit" and
  "account/data deletion requests" do not apply: there is nothing on any
  server to delete.

## Changes

Any change to this policy is published in this file in the public repository
with a new effective date.

## Affiliate links

The app shows clearly-labelled "Partner link" buttons (for example Prime
Video and pCloud). Tapping one opens that service's website; we may earn a
commission at no extra cost to you. These links carry only our public
partner tag — no personal data is sent through them.

## Contact

Questions: open an issue on github.com/Aryanshahx/maxplayer
