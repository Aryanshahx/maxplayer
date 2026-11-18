# Windows 0.2.0: home and Discover

## Home
Search, Rescan, existing file/queue controls, three-dot menu.
Rescan remembers folders imported using Folders/Open folder. On first use it asks
for a folder. Subsequent rescans add newly found direct-child media, without
removing missing files or disturbing saved playlists/history. It is not whole-PC
indexing and does not recursively scan subfolders. Folder paths persist locally.

Menu starts with Android equivalents: Language, Display settings, Watch statistics,
History, User manual, About Hyper Player, Privacy policy, Report a problem,
Follow on Instagram. Existing Windows playback tools remain below the divider.
Display settings supports persisted grid/list and current-queue sorting.
Support email and Instagram use the configured desktop applications/browser.

40 Android offline translation catalogs are bundled. Fixed labels wrapped with
LText and the language screen are localized, with System default and RTL support.
Uncovered/new desktop text, dynamic messages, Discover metadata and this manual
can remain English; this is not a claim of full reviewed 40-language translation.

## Discover
- Reuses the Android TMDB client/parsers and its movie/series filter categories.
- Home banner retrieves trending posters (gradient fallback on failure).
- Multi-search, previous/next paging, refresh, errors/retry and poster fallback.
- Details: overview, score, genres, runtime, certification, production and languages.
- Cast, images, reviews, related titles, series seasons/episode metadata.
- Where-to-watch data for India, with TMDB / JustWatch credit and browser listing link.
- Trailer variants open YouTube externally, not inside the native player.
- Metadata caches locally for 24 hours, with stale-cache fallback on failure.
  Poster/image network loading is not an offline image-cache guarantee.
- This is metadata/trailer discovery, NOT a provider of full copyrighted films.

## Token setup
Uses the existing repository Actions secret TMDB_API_KEY (TMDB API read-access
Bearer token). If it is already set for Android, no new secret is needed.
Never paste it into source, chat or screenshots. Windows workflow now reads this
secret through a temporary dart-define JSON file and deletes that file afterwards.
Build intentionally fails with a clear message if the secret is absent.
As with any direct API client, compile-time tokens are extractable from distributed
binaries; GitHub Secrets protects the source/build handling, not the compiled app.
No pre-existing source fallback token was copied into this desktop update.
Review TMDB usage/branding terms and public Windows privacy policy before Store
submission. Text attribution included; no certification/legal-compliance claim.

## Verification
Flutter 3.47.0 / Dart 3.13.0: analyzer clean, 13 tests passed on Linux.
Tests cover existing queue/collections, TMDB parsers/categories/provider region,
and bundled language persistence. No live TMDB API test was performed with your
secret; authorization/connectivity still require the Windows release build.
Native Windows compilation, picker behavior and playback require Actions/laptop.
No local Android build or Android source/name/version changes.

## Apply/build
Run the single installer in the repository root, commit listed files, then run
Windows desktop preview on updated main. This remains a portable unsigned preview,
not an EXE/MSI Store installer. Extract all ZIP layers and keep DLLs/data together.
