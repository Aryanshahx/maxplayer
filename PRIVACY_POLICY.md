# Privacy Policy — Max Player

**Effective date:** 13 August 2026
**Developer:** Hyper Tech Labs (Aryan Shah)
**Contact:** https://github.com/Aryanshahx/maxplayer (see the repository profile for contact details)

## The short version
Max Player is a local video player. **It does not collect, store, transmit, or share any personal data.** Everything the app does happens on your device.

## What the app accesses and why

| Permission / access | Why | Where the data goes |
|---|---|---|
| **Storage (videos / all files)** | To find and play the videos stored on your device, save screenshots to *Pictures/Max Player*, and write AI subtitle files next to your videos | Never leaves your device |
| **Internet** | Only for two things you trigger yourself: (1) the one-time download of the AI subtitle model (a ~142 MB file from huggingface.co), (2) playing stream URLs you paste/open | The model file comes in; nothing about you goes out |
| **Local network (multicast/Wi-Fi)** | Only when you tap "Cast to TV": discovering DLNA TVs on your own Wi-Fi and serving the video file from your phone to your TV | Your Wi-Fi only; no external server is involved |

## What the app does NOT do
- No analytics, no tracking, no advertising, no third-party SDKs that collect data
- No accounts, no sign-in, no device identifiers collected
- No collection of your video library content, file names, or history — all of it stays in the app's local storage on your device
- No crash reporting service (crash reports are shown **to you** inside the app, and are only shared if **you** copy and send them)

## AI subtitles
Subtitle generation runs entirely **on your device** using the open-source whisper.cpp engine. Your audio never leaves your phone. The only network access is the one-time model file download from Hugging Face (ggerganov/whisper.cpp), which you trigger and can delete afterwards. Translating subtitles to English uses the same fully on-device engine — no audio or text is sent anywhere.

## Private folder
Videos you hide are **moved into the app's own protected folder**, which Android blocks other apps from reading, and are unlocked with a PIN you choose. They never leave your device and are never uploaded. The PIN is stored only as a cryptographic hash inside the app's settings. Uninstalling the app deletes the protected folder — move videos out first.

## Children's privacy
The app collects no data from anyone, including children.

## Google Play Data Safety (short answers)
This section matches the app's Play Console Data Safety form:
- **Data collected:** none — there is nothing to list per category
- **Data shared with third parties:** none
- **Data sent off the device:** none (AI subtitle generation, history, bookmarks and settings are all local-only)
- Because no data leaves the device, "encryption in transit" and "account/data deletion requests" are **not applicable** — nothing is transmitted and there is nothing on any server to delete.

## Changes
Any change to this policy will be committed to this file in the public repository, with the new effective date above.

## Contact
Questions: open an issue on the GitHub repository above.
