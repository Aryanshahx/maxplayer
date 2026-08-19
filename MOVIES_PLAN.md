# Max Player v43 — "Discover" section (movie banners, ratings, in-app trailers)

Plan for adding a browsable movie catalogue (Hollywood / Bollywood / South /
Anime …) with poster banners, ratings, and trailers that play **inside** Max
Player. Written for the current tree: `1.0.0+40`, Flutter 3.44.9 (pinned),
media_kit playback, Codemagic-only builds.

---

## 1. The two hard questions first (data + trailers)

### 1.1 Where the ratings and banners come from — **TMDB, not IMDb**

IMDb has **no free public API**, and scraping imdb.com (ratings, posters,
banners) breaks their Conditions of Use — the layout also changes constantly,
so a scraper silently dies and every user sees an empty screen. Using IMDb
artwork/branding in a Play Store app is also a real takedown risk.

**Use TMDB (The Movie Database).** It is the standard free replacement:
free key, ~50 req/s soft limit, hosted posters + backdrops, ratings, cast,
genres, **and the YouTube trailer keys** — one API gives us the whole feature.
Free for non-commercial use *with attribution*; commercial use needs a mail to
TMDB. ([FAQ](https://developer.themoviedb.org/docs/faq))

Required, non-negotiable, and already in the plan below:

> "This product uses the TMDB API but is not endorsed or certified by TMDB."
> — placed in the **About** sheet, with the TMDB logo shown less prominently
> than the Max Player logo.

**About the actual IMDb number:** if you specifically want the *IMDb* 8.8 and
not the *TMDB* 8.4, the only clean route is the **OMDb API** (free tier,
1,000 requests/day, needs its own key) called *only on the detail screen* and
cached for 7 days. My recommendation: **ship TMDB ratings first** (labelled
"TMDB" so it is honest), keep an OMDb hook in the code, and turn it on later
if you want. 1,000 req/day dies fast once the app has users.

### 1.2 Playing the YouTube trailer inside the app — **official IFrame embed**

Two ways exist, and only one is safe:

| Approach | Verdict |
|---|---|
| Extract the raw googlevideo stream URL and feed it to mpv/media_kit | ❌ **Do not.** Violates YouTube ToS + Google Play's "unauthorised downloading" policy → app removal. Also technically fragile (signature ciphers change weekly) and mpv on Android has no `ytdl_hook`. |
| Official **YouTube IFrame Player** embedded in the app (`youtube_player_iframe`) | ✅ Allowed, ads/analytics served as YouTube requires, plays **inside our UI** — own fullscreen, own back button, no jump to the YouTube app. |

So: `youtube_player_iframe` (Flutter port of the official IFrame API, uses
`webview_flutter` under the hood — first-party plugin, so no repeat of the
`file_picker` AGP mess). We enable `privacyEnhanced: true`, which routes to
`youtube-nocookie.com` — keeps the "no tracking" promise as close to true as
an embed can be.

**Fallback path is built in:** if the WebView is missing/broken on some cheap
device, the trailer button falls back to an Android intent that opens the
YouTube app or browser, so the screen is never a dead end.

---

## 2. What the user sees

**New bottom-nav tab: "Discover"** (icon: `movie_filter`), next to Library /
History / Stats. First open shows a one-time consent card:

> **Discover uses the internet.** Movie posters, ratings and trailers are
> loaded from TMDB and YouTube. Your library, your private folder and playback
> stay 100% offline. — [Not now] [Turn on Discover]

Kept opt-in on purpose: it protects the "offline, no account, no tracking"
identity of the app and keeps the Play Data-Safety form trivial.

### Screen 1 — Discover (`movies_screen.dart`)

* **Hero banner** — auto-rotating backdrops of the top 5 trending titles,
  large title + rating chip + "Play trailer".
* **Search bar** — TMDB search, debounced 400 ms.
* **Horizontal rails**, each a lazy row of poster cards with a rating badge:
  1. Trending this week
  2. Hollywood — Popular (`with_original_language=en`)
  3. Bollywood — Popular (`with_original_language=hi`, `region=IN`)
  4. In cinemas now (`now_playing`, `region=IN`)
  5. South Indian (`te,ta,ml,kn`)
  6. Top rated of all time
  7. Upcoming
  8. Anime (`ja` + genre 16), Korean (`ko`)
  9. By genre: Action / Comedy / Horror / Romance / Sci-Fi / Thriller chips
* **"See all"** on every rail → paginated grid (infinite scroll).
* **Watchlist** rail at the top once the user saves anything.

### Screen 2 — Movie detail (`movie_detail_screen.dart`)

Backdrop header → poster + title + year + runtime + genre chips → rating ring
(TMDB score, vote count) → overview → **Trailers & clips** (official trailer
first) → top cast strip → "More like this" rail → Watchlist button.

**The Max-Player-only touch:** if the title matches a file already in the
user's library (fuzzy match on filename + year), the detail screen shows a
green **"In your library — Play"** button that opens *our* mpv player. No
other movie-info app can do that, and it turns Discover from decoration into
a real feature of a *player*.

### Screen 3 — Trailer player (`trailer_player_screen.dart`)

`YoutubePlayerScaffold` in our own dark theme: title bar, related trailers
below, rotate-to-fullscreen using the same orientation logic the main player
already has.

---

## 3. Code plan

### New files (`lib/`)

| File | Purpose | ~lines |
|---|---|---|
| `models/movie.dart` | `Movie`, `MovieDetails`, `CastMember`, `MovieVideo` + `fromJson` | 220 |
| `services/tmdb_api.dart` | `dart:io HttpClient` client (**no new HTTP package**): trending / discover / now_playing / top_rated / upcoming / search / details(`append_to_response=videos,credits,external_ids,similar`) | 260 |
| `services/movie_cache.dart` | Disk JSON cache (lists 12 h, details 7 d) + poster file cache in `<cache>/movies/`, keyed with the existing `utils/sha256.dart` | 200 |
| `state/movies_state.dart` | `ChangeNotifier`: rails, paging, search, watchlist, opt-in flag, offline mode | 380 |
| `screens/movies_screen.dart` | Discover tab | 420 |
| `screens/movie_detail_screen.dart` | Detail page | 400 |
| `screens/trailer_player_screen.dart` | In-app YouTube player | 160 |
| `widgets/movie_card.dart` | Poster card + rating badge | 120 |
| `widgets/movie_rail.dart` | Titled horizontal rail + "See all" | 130 |
| `widgets/network_poster.dart` | Disk-cached image (reuses `widgets/fade_in_image.dart`), 4-at-a-time fetch queue | 150 |
| `widgets/movie_grid_screen.dart` | "See all" paginated grid | 160 |

≈ **2,600 new Dart lines.**

### Edited files

* `pubspec.yaml` → `1.0.0+41`, add `youtube_player_iframe`
* `lib/screens/library_screen.dart` → new nav destination
* `lib/widgets/cleaner_sheet.dart` → new **"Movie posters & data"** cache
  bucket in the existing graphs + one-tap clean
* `lib/widgets/about_sheet.dart` → TMDB attribution + logo
* `lib/utils/privacy_policy.dart` + `PRIVACY_POLICY.md` → disclose that
  Discover contacts TMDB and YouTube; everything else stays offline
* `README.md` → feature bullet + TMDB key setup
* `codemagic.yaml` → `--dart-define=TMDB_KEY=$TMDB_KEY` on both build steps
* `test/widget_test.dart` → ~12 new pure-Dart tests (JSON parsing, cache TTL,
  rating formatting, library-match fuzzy logic)

### The API key — never committed

```dart
const kTmdbKey = String.fromEnvironment('TMDB_KEY');
```

Empty key → Discover shows a friendly "not configured" card instead of
crashing. You add `TMDB_KEY` once in **Codemagic → Environment variables**
(group `keystore_credentials` or a new `api_keys` group, mark it secure), and
every build picks it up. Nothing secret ever lands in Git.

**Your one manual step:** create a free TMDB account →
Settings → API → "Developer" → copy the **API Key (v3 auth)**. Desktop browser;
approval is instant. Send it to Codemagic, not to me.

---

## 4. Build order (matters, because Codemagic minutes are finite)

| Step | Content | Risk |
|---|---|---|
| **v43a** | Models + TMDB client + cache + tests. No UI, no new dependency. | none — cannot break the app |
| **v43b** | Discover tab, rails, detail screen. Trailer button opens the YouTube app for now. | UI only |
| **v43c** | `youtube_player_iframe` + in-app trailer screen. **Isolated commit** so a single `git revert` undoes it if the plugin fights the toolchain. | the only real build risk |
| **v43d** | Watchlist, Cleaner bucket, About/privacy/README, "In your library — Play". | low |

I would put **a–d in one script but four commits**, and you run **one**
Codemagic build. If it fails, the log names the step and we revert exactly one
commit.

---

## 5. Low-end-device care (your users are on POCO C51-class phones)

* Posters requested at `w342`, backdrops at `w780` — not the originals.
* Max 4 concurrent image downloads, `cacheWidth` set on every decode so the
  Skia raster cache does not blow up (remember Impeller is off).
* Every rail is `ListView.builder` with `addAutomaticKeepAlives: false`.
* Poster cache hard-capped at **80 MB**, LRU-evicted, and visible/clearable in
  the Cleaner.
* Cached rails render with **zero network** — Discover still works on a train.
* "Load posters on Wi-Fi only" toggle in settings.

---

## 6. Play Store notes

* Store listing must say **trailers and information**, not "watch movies" —
  review teams flag player apps that look like streaming/piracy front-ends.
* No IMDb logo, no IMDb wordmark, no scraped IMDb data.
* TMDB attribution in About (§1.1). If Max Player ever earns money
  (ads/IAP/paid), mail TMDB for a commercial licence first.
* Data Safety form gains: "App info & performance → diagnostics: no",
  "Data collected: none; data shared: none" stays true — TMDB/YouTube requests
  are disclosed in the privacy policy as third-party services.
* Optional later: TMDB `/watch/providers` ("Where to watch") — has its own
  JustWatch attribution rules, so it is deliberately out of v43.

---

## 7. Delivery to your Raspberry Pi

You do **not** need to paste a 500 KB script into `nano` again. I push the
work to the branch `arena/01a01ae6-maxplayer`, and on the Pi you paste one
line:

```bash
cd ~/IdeaProjects/maxplayer && git fetch origin && git checkout arena/01a01ae6-maxplayer && git pull
```

IntelliJ picks the changes up instantly, and Codemagic can build that branch
directly (Workflow → branch pattern). If you would rather keep the old habit,
I can also emit `update_maxplayer_v43.sh` alongside it — same content, full
file writes, prints `OK` per file.

---

## 8. How new movies arrive automatically (no app update, no server)

Your question: *"how will it automatically fetch new movies?"* — nothing in
the app is a hardcoded list. Four mechanisms do the work:

**1. Every rail is a live query, not a stored list.**
`/trending/movie/week`, `/movie/now_playing`, `/discover/movie?...` are
answered by TMDB at the moment of the call. TMDB's editors and studio feeds
add new titles, posters and trailers continuously, so the same query returns
`Coolie` today and whatever releases in October in October. The app ships
*questions*, not *answers*.

**2. Date windows slide with the calendar.**
The "New releases" and "Coming soon" rails build their filter from
`DateTime.now()` on every call:

```dart
DateWindow recentWindow(DateTime now, {int days = 75}) =>
    DateWindow(tmdbDate(now.subtract(Duration(days: days))), tmdbDate(now));
```

So on 19 Aug 2026 that rail asks for `2026-06-05 … 2026-08-19`, and on
19 Sep 2026 the very same code asks for `2026-07-06 … 2026-09-19`. A phone
that never updates the app still shows this month's films. (Unit-tested — see
`v43 discover: new movies arrive without an app update`.)

**3. Stale-while-revalidate caching — instant screen, quiet refresh.**
Each rail has a TTL (Trending 6 h, releases/cinema 12 h, evergreen rails
24 h, Top rated 3 days, movie details 7 days). Opening Discover:

```
read <cache>/movies/json/<hash>.json  →  paint immediately (even offline)
        │
        └── older than the TTL?  →  fetch in the background  →  swap in + re-cache
```

Result: no spinner on a repeat visit, at most one request per rail per TTL no
matter how often the app is opened, and a working catalogue with the Wi-Fi
off. Pull-to-refresh sets `force: true` and re-fetches everything.

**4. "NEW" ribbons without any push server.**
Ids returned by a rail are compared against a persisted `movies.seen.v1` set
(capped at 800 ids). Anything unseen gets a ribbon; the set updates after the
fetch. First-ever run marks nothing new. No FCM, no background service, no
battery cost — the check rides along with the normal refresh.

**When does the refresh run?** On opening the Discover tab, on pull-to-refresh
and when a rail's TTL expires while you are in the tab. Deliberately *not* a
periodic `WorkManager` job: background data on a metered Indian connection is
exactly the kind of thing that gets a "battery drain" one-star, and it buys
nothing for a screen the user only sees when they open it.

### Status: shipped in this branch (data layer, step v43a)

| File | What it does |
|---|---|
| `lib/models/movie.dart` | `Movie`, `MovieDetails`, `MovieVideo`, `CastMember` + tolerant parsers, trailer ranking |
| `lib/services/tmdb_api.dart` | `dart:io` TMDB client, sliding date windows, `--dart-define` key, readable errors |
| `lib/services/movie_cache.dart` | `<cache>/movies/` JSON + poster cache, 4-at-a-time downloads, 80 MB LRU cap |
| `lib/state/movies_state.dart` | rail catalogue, stale-while-revalidate, paging, NEW ribbons, watchlist, opt-in flag |
| `MainActivity.kt` | new `cacheDirPath`; Cleaner now reports/clears the `movies` bucket |
| `test/widget_test.dart` | +20 pure-Dart tests (parsing, windows, URI building, cache policy) |

Next steps are the UI (`movies_screen`, `movie_detail_screen`) and the in-app
YouTube trailer player.

## 9. Decisions taken

* Ratings: **TMDB only** (labelled "TMDB"), no OMDb, no IMDb scraping.
* **Movies only** — no TV shows in v43.
* Discover is an **opt-in tab** with a one-time consent card.
* Catalogue language: **`language=en-IN`, `region=IN`** — English titles and
  descriptions with Indian release dates and cinema listings, so Bollywood
  rows read "Jawan" rather than "जवान" and "In cinemas now" means *here*. One
  constant (`TmdbApi.language`) flips it later if you want Hindi text.

## 10. Open questions for you

1. ~~Ratings source~~ — decided: TMDB only.
2. ~~TV shows~~ — decided: movies only.
3. ~~Opt-in tab~~ — decided: yes.
4. ~~Catalogue language~~ — decided for you: `en-IN` + `region=IN` (see §9).
5. Do you want the **"In your library — Play"** match, and should Discover
   also be able to **fetch posters/metadata for the local files** you already
   have (Plex-style library artwork)? That is the biggest win in this whole
   feature, but it is another ~400 lines.
