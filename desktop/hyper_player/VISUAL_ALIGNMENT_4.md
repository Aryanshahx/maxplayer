# Android visual alignment — Home Search and Discover browsing

Home Search is now a full native page, not an input dialog followed by another
list dialog. Android-style app-bar search field/back button, 200 ms debounce,
clear control, empty/no-result states and grid/list media cards. Searches known
queue/history/favourites and saved playlist entries only, not the entire disk.
Filename matches are deduplicated and sorted. Selected result uses existing player.

Discover browsing now adopts Android's #0A0A10 canvas, rounded pill search bar,
poster layout, featured carousel/dots, social row, Top 10 and horizontal category
rails. Featured carousel has PC previous/next buttons in addition to dragging.
Poster title reserves two lines, year one line, score sits over the poster.
Movie and series filters, grid search results, paging, details, trailer links,
seasons, provider metadata, reviews and local metadata cache are retained.
Bollywood, Hollywood, Animation and Action shelves fetch real TMDB first pages
in parallel; SEE ALL opens their paged category. All existing filters remain.
Empty shelves show retry controls. Top 10 means first ten from TMDB weekly
trending, NOT app usage rankings. No invented media or user recommendations.

Search focus with an empty query shows hot-search suggestions from loaded items.
350 ms debounce searches TMDB. Canceling timers on disposal is retained.
Voice and AI controls match the Android header placement but are disabled with
explicit availability tooltips; this update does not implement these integrations.
The top search bar stays visible on PC rather than using Android scroll-hide.
No cinematic boot curtain, neon ticker, automatic hero advance or personalised
recommendation parity is claimed. Detail-page composition and Windows playback
screen still need further Android-style visual alignment.

Instagram and Telegram buttons open public existing project social URLs via
browser. TMDB credit remains visible. Trailers open YouTube externally; no full
movies supplied. No workflow/token, Android source/name or signing changes.
Home Open files/Current playlist header buttons remain absent.

Validation: Flutter 3.47.0 analyzer clean; all 33 tests passed on Linux, including
four new search/poster/carousel widget tests. Live TMDB data, Windows compilation,
mouse/scroll behavior and actual image/layout rendering still need Actions/laptop.
This patch changes the native Windows project, not the HTML browser prototype.
