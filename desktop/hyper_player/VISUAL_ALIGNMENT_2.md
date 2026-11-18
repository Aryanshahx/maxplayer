# Android visual alignment — Audio, Folders, Display Settings

Native Windows screens based on the corresponding Android source layouts.

Audio: Android app bar with count/sort/rescan, rounded search field, circular
music icons, compact rows and indented separators. Source files are chosen
folders, previously opened queue/history audio, and files selected with the +
control. Selections persist across restarts. Newest means file modification time;
row subtitle shows actual file size, not invented duration/artist metadata.
Selecting a track opens the existing Windows player, not yet Android Now Playing.
No whole-laptop MediaStore-style indexing or unsupported Longest sort is claimed.

Folders: Android folder cards with icon/name/count/chevron, back navigation and
responsive media grid. Windows Add folder chooses a directory and persists it
in the same list used by Home Rescan. Lists direct-child media only, not nested
folder traversal. Counts include audio and video (labelled media items).
Missing folders are labelled unavailable; generic media icons stand in for thumbnails.

Display Settings: full route with Android section headings, outlined Grid/List
mode cards, sorting rows, and grouping/action section. Grid/List choice persists.
A–Z/Z–A sort changes current queue without changing the active media. Unsupported
in-library grouping and Play Single options are explained without fake controls.
No additional Android-only settings are represented as functional.

These are PC layout adaptations, not a claim that every Android screen is now
pixel-identical or all Android features are implemented. Watch Statistics,
Discover detail presentation, Now Playing and remaining unsupported feature
screens still need further alignment. Existing group-one routes are preserved.
Home Open files/Current playlist header buttons remain absent.

Scan safety/privacy: selected directories only; no recursive/symlink traversal;
20,000 media-entry limit reported explicitly. Paths/settings persist locally;
no media is uploaded by these browsing screens. Unreadable entries may be skipped.

Verification: Flutter 3.47.0 analyzer clean; all 23 tests passed on Linux,
including six new scan/widget tests. Windows build, native file/folder pickers,
visual rendering and playback still require GitHub Actions and laptop validation.
No Android source/name/version changes, secrets or CI signing changes.
