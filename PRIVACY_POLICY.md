# Privacy Policy — Max Player

**Effective date:** 5 September 2026
**Developer:** Hyper Tech Labs (Aryan Shah)
**Contact:** https://github.com/Aryanshahx/maxplayer (see the repository profile for contact details)

## The short version
Max Player is a local video player. **It does not collect, store, transmit, or share any personal data.** Everything the app does happens on your device.

## What the app accesses and why

| Permission / access | Why | Where the data goes |
|---|---|---|
| **Storage (videos / all files)** | To find and play the videos stored on your device, play videos you pick in Android's file picker, save screenshots to *Pictures/Max Player*, save picked videos to *Movies/Max Player* (only when you tap Save), and write AI subtitle files next to your videos | Never leaves your device |
| **Microphone (audio)** | Only for voice search when you tap the mic icon in Discover or Library | Audio is transcribed in real time and is never recorded, stored, or sent to external servers |
| **Internet** | Only for things you trigger yourself: legal TMDB movie discovery, stream URLs you open, cloud videos you import, and optional one-time AI subtitle model download | Nothing personal about you goes out |
| **Local network (multicast/Wi-Fi)** | Only when you tap "Cast to TV" or use Wi-Fi Resume-Sync between your devices | Your local Wi-Fi only; no external server is involved |

## What the app does NOT do
- No analytics, no tracking, no advertising, no third-party SDKs that collect data
- No Max Player accounts and no device identifiers collected (cloud video imports go through Android's own file picker — strictly between you and the storage app)
- No collection of your video library content, file names, or history — all of it stays in the app's local storage on your device
- No crash reporting service (crash reports are shown **to you** inside the app, and are only shared if **you** copy and send them)

## Cloud storage — Android's file picker
Library → Cloud Storage opens **Android's built-in file picker**, which lists the storage apps installed on your device — your Google Drive app, Dropbox, OneDrive, and others. There is no sign-in, account, or OAuth of any kind inside Max Player, and the app never sees your cloud file list; the system hands Max Player a one-time, read-only grant for just the one video file you choose. While the file imports, a progress bar shows the copy in real time. The imported bytes live in the app's private cache purely so the video can play, and the copy is discarded when replaced or cleared. Tapping **Save to device** stores a permanent copy in *Movies/Max Player* — nothing is uploaded anywhere; the bytes travel only from the storage app (e.g. Google) to your own phone, exactly like a download in your browser.

## AI subtitles
Subtitle generation runs entirely **on your device** using the open-source whisper.cpp engine. Your audio never leaves your phone. The only network access is the one-time model file download from Hugging Face (ggerganov/whisper.cpp), which you trigger and can delete afterwards. Translating subtitles to English uses the same fully on-device engine — no audio or text is sent anywhere.

## Private folder
Videos you hide are **moved into the app's own protected folder**, which Android blocks other apps from reading, and are unlocked with a PIN you choose. They never leave your device and are never uploaded. The PIN is stored only as a cryptographic hash inside the app's settings. Uninstalling the app deletes the protected folder — move videos out first.

If the PIN is forgotten, resetting it requires passing the device's own screen lock (PIN, pattern, password or fingerprint). That unlock check is performed entirely by Android on your device — nothing is sent anywhere.

## Playback extras (karaoke, skip intro, thumbnails)
Karaoke highlighting and skip-intro detection only *read* subtitle files already on your device (AI-generated .srt files or the video's own subtitle file) while you play a video. Library thumbnails are decoded from your own videos into the app's cache folder, which the system or you can clear at any time. None of this data leaves the device or is shared anywhere.

## Children's privacy
The app collects no data from anyone, including children.

## Google Play Data Safety (short answers)
This section matches the app's Play Console Data Safety form:
- **Data collected:** none — there is nothing to list per category
- **Data shared with third parties:** none
- **Data sent off the device:** only what you trigger — a picked cloud video's bytes travel from the storage app (e.g. Google Drive) to your phone while you import it; everything else (AI subtitles, history, bookmarks, settings) is local-only
- Because no data leaves the device, "encryption in transit" and "account/data deletion requests" are **not applicable** — nothing is transmitted and there is nothing on any server to delete.

## Changes
Any change to this policy will be committed to this file in the public repository, with the new effective date above.

## Contact
Questions: open an issue on the GitHub repository above.
