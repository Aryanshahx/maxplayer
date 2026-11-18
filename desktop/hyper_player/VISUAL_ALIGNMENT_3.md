# Android visual alignment — Statistics, User Manual, About and Privacy

Statistics now opens a full page matching the Android layout: #0A0A0F canvas,
large seven-day total, compact stat cards, white/neutral seven-day bars and
ranked Most watched rows. It no longer uses a plain AlertDialog.

Daily counters are real local samples from this update onward. Playing/not
buffering contributes about one sampled second per timer tick, not attention.
No old lifetime total is distributed across past dates. Last seven local
calendar days / today / average / best day / last 30 days / streak are calculated
from available daily records. Streak includes yesterday if today is not active.
Most watched combines identical filenames and retains at most 100 counters.
Daily records retain at most 366 entries. Counters save on existing 15-second
interval and best-effort shutdown; abrupt exit/system sleep can lose samples.
The legacy lifetime/starts figures are snapshots taken on opening this screen.
These are not Firebase/admin analytics or validated viewing metrics.

User Manual and About use the Android-style scrollable bottom sheet treatment:
#14141C surface, rounded top corners, grab handle, .85 starting height, icon
header, section headings and compact icon rows. PC caps sheet width at 1000.
Manual text documents actual Windows controls, not unsupported Android gestures.
About includes basic OS diagnostics copy and Flutter's open-source license page.
Privacy uses the same sheet geometry and updated Windows-only disclosure.
No claim that the license list or disclosure alone makes a Store submission compliant.

No vault, Whisper, cloud, Quick Share, casting or other unavailable feature is
made functional by this styling update. Remaining player/Discover screen visual
work is not represented as finished. Native app only: web prototype unchanged.
Earlier visual groups and simplified Home header are retained.

Validation: Flutter 3.47.0 analyzer clean; 29 tests passed on Linux including
six new counters/statistics/manual-sheet tests. Native Windows compilation,
rendering and playback still require GitHub Actions and laptop verification.
No Android source/version/name, signing keys, workflow or secrets changed.
