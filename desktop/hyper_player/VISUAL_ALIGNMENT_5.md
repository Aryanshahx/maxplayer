# Android visual alignment — Movie/Series details and episode browsing

Discover detail now follows the Android MovieDetailScreen/MovieDetailSheet:
- #14141C canvas, no AppBar band or drag handle.
- Pinned circular Back control; scrollable body clears its 56px top region.
- Trailer card first, 105x155 rounded poster beside compact 18px title header.
- Movie/Series badge, amber score, year, certification and rounded genre tags.
- Storyline/metadata typography, horizontal circular cast portraits and images.
- India provider listings, expandable reviews and related-poster shelf retained.
- Ask AI has an explicit disabled/unavailable state; no fake working AI action.

Seasons now switch inline via Android-style chips, season summary container,
loading/retry and compact episode metadata cards. Episode details expand for
synopsis/still image. The separate existing SeasonScreen uses the same renderer.
These are metadata only, not playable full episodes. Trailer card/language actions
open YouTube via the existing safe launcher, not an embedded trailer player.

PC adjustments: detail width capped at 1200, trailer card height capped at 340,
wrapping metadata badges and longer rows. No in-library film matching/play button
is fabricated; that feature remains unimplemented. Complete Android player UI,
Network/Cloud/Vault/Quick Share/Whisper and other incomplete screens are not
claimed implemented by this update. Existing native playback is unchanged.
No workflow/secret, Android app/source/name or Home header changes.

Validation: Flutter 3.47.0 analyzer clean; all 38 tests passed on Linux.
Five new tests cover header/trailer callbacks, 420px layout, inline season
switching, episode expansion and pinned-Back route composition. Tests use local
fixtures, not a live TMDB token. Native Windows build, real images/catalogue and
laptop mouse/scroll testing still require Actions + laptop verification.
