# Android visual alignment — Playback speed and Sleep timer

Reference: Android lib/screens/player_screen_impl.dart _showSpeedSheet and
_showSleepTimerSheet. Replaces the two Windows SimpleDialogs with rounded
bottom sheets: handle, 18px semibold left-aligned heading, speed #1A1A24
surface, large white 30px rate, 0.5–4 slider in 0.25 steps and preset chips.
Sleep uses Android list-row organisation, conditional Turn off timer, 10/15/30/
45/60-minute choices plus retained existing Windows 90/120-minute choices.
Active timer displays pause-at local time. Existing pause/cancel timer logic stays.

PC adaptation: modal width capped at 1000, content scrolls at short window heights;
speed applies on slider release or preset click rather than every drag tick.
Speed callback failure restores prior applied readout with error text. Busy controls
are disabled until completion. Current rate initializes from actual player state.
No new rate persistence is claimed. Until end is explicitly disabled with an
availability explanation: pause-at-end/queue semantics are not implemented here.
Modal dismissal does not cancel a running sleep timer. Changes are visual and
interaction refinements, not full Android playback/settings feature parity.

Android, CI, signing and Home header remain unchanged. Previous screen batches
preserved. No new paid services or API credentials needed.
Validation: Flutter 3.47 analyzer clean, 43 tests passed on Linux, including five
new sheet callback/failure/cancel/modal tests. Native Windows playback timing,
mouse/keyboard and actual Windows appearance require Actions/laptop verification.
