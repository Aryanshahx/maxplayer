# Android visual alignment — Video info and A–B repeat

Video info follows Android player_screen_impl.dart _showVideoInfo: rounded22
surface sheet, handle, 18px semibold heading, draggable .62/.35/.92 sizing,
scroll controller, 14px title, 11.5px grey labels and 12.5px selectable values.
Open via existing three-dot menu → Video info. Shows real player snapshot:
source, position/duration, nonnegative remaining, speed, known resolution/audio
bitrate and concrete video/audio/subtitle track labels. No guessed codecs,
file sizes or metadata. Reopen for fresh state. Source URLs can contain private
credentials; a visible warning advises review before sharing.

A–B repeat replaces SimpleDialog with the same Android player-sheet frame,
heading/action rows and current Off/A/Loop status. Android has a cycle-based
A–B action rather than this separate panel; existing explicit Windows Set A,
Set B and Disable actions are intentionally retained. Existing point validation,
seek enforcement and resets remain unchanged. No new looping engine claimed.

PC sheets capped at width1000 with scroll-safe layout. Android app, CI, native
backend and Home header untouched. Previous batches preserved. Not complete
Android player parity; fit/delay and advanced settings still need alignment.

Validation: Flutter3.47 analyzer clean, all51 tests passed on Linux, four new
clock/info/status/action tests. Native Windows rendering, metadata availability
and actual A–B playback still require Actions/laptop checks.
