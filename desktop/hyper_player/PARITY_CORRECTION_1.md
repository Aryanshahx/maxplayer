# Parity correction 1 — partial response to thumbnail/menu/player feedback

Root cause: Home/Search local media cards were drawing fixed icons, not extracting
thumbnails. New Windows Shell IShellItemImageFactory bridge via local PowerShell
requests thumbnail-only images (not generic file icons). Serial requests, 15-second
handler timeout, temp disk PNG cache keyed by path/mtime/size; no uploads or extra
binary downloads. Applied to Home grid/list and Search grid/list. Unsupported
codecs/blocked PowerShell retain an honest fallback. Linux tests cannot validate
Shell COM or image extraction. This is an implementation, NOT confirmed Windows fix.
Other local collection/folder/audio card surfaces still require thumbnail wiring.

Home menu now has Android's eight entries (Windows app name adapted) plus version;
History and player/import/queue commands removed from Home popup only. Player
popup keeps existing tools. Direct player row exposes Previous, Play/pause, Next,
Audio track, Subtitles, Speed, Fit, A–B, Sleep, Info, Subtitle delay, Favourite.
AdaptiveVideoControls retained for seek/volume/fullscreen. New row scrolls on PC.
This is NOT all Android player controls: EQ, screenshot, casting, PiP, gesture
lock, enhancement/HDR, karaoke, dialogue boost, Whisper/settings parity remain.
No inactive buttons pretending those features work. Home header removal preserved.

About now ports actual Android AboutSheet brand header, sections, feature list,
mission/story/team/looking-ahead layout. Windows name/version and basic OS
diagnostics replace Android native diagnostics. Brand copy is not a guarantee
of Windows preview stability. Privacy now uses actual Android AlertDialog style
with Windows-accurate policy text, not Android Firebase/advertising disclosures.
Manual section/row metrics copied from Android (uppercase12 headings,14 titles,
12.5 descriptions); Windows keyboard guidance retained. Android touch gesture
illustrations not copied as working Windows features. Complete manual parity
still unfinished, not claimed complete. About title is Hyper Player by Hyper Tech
Labs, not a separate company application.

Discover details/seasons remain from previous batches. No additional Discover
screen implemented here: need user identify missing page or provide screenshot.
Android source untouched. Flutter3.47 analyzer clean, 59 tests pass on Linux.
Windows build, Shell extraction, codecs and native behavior remain unverified.
