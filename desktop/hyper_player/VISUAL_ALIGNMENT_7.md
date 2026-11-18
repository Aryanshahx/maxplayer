# Android visual alignment — Audio track and Subtitles sheets

Reference: Android player_screen_impl.dart _showTrackPicker, _trackRow and
_trackLabel. New Windows panels use the existing rounded player-sheet frame,
18px semibold headings, 16px track names and white checked-circle/grey radio
selection indicators. Labels use title • LANGUAGE • codec, fallback Track ID.

Open through the existing three-dot menu: Audio track / Subtitles. These panels
use actual media_kit track metadata captured when opened. Subtitle Off selects
SubtitleTrack.no(); other rows pass their actual current track to media_kit.
Successful selection closes the sheet; failures remain visible with retryable
error text. Busy rows cannot be selected twice. Synthetic auto/no entries are
excluded from ordinary rows; subtitle Off remains explicit.

External Load subtitle file action reuses the existing Windows picker, which is
also retained as a direct menu command. AI generation row is visibly disabled
with availability explanation. No Whisper/on-device generation is implemented.
Empty audio/subtitle tracks have honest explanations, not fabricated languages.
For a stream whose tracks change, reopen the panel to refresh its metadata.
No track preference persistence or automatic-language selection is claimed.

PC adaptation: existing scrollable sheet/max width 1000; no Android-only gestures.
Batch 6 speed/sleep preserved. Android source, CI, playback backend and Home
header unchanged. This is not full Android player/settings feature parity.

Validation: Flutter 3.47 analyzer clean and all 47 tests pass on Linux (including
four new track-sheet tests). Native Windows track switching, external subtitle
file picker and appearance still require Actions + laptop verification.
