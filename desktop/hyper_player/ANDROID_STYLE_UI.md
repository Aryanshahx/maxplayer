# Android-style Windows UI update
Native Flutter home screen adaptation, not a browser wrapper.
Uses Android theme colours and brand gradient #A78BFA -> #8B5CF6 -> #22D3EE.
Gradient shader bounds follow the title text, not an expanded header container.
Android quick tile order is preserved. PC layout shows 2/4/8 columns by width.
Local file/folder import, queue persistence, streams and native media_kit playback
are retained. Library grid/list toggle and back-to-library playback bar are added.
Cards use generic media icons, not generated thumbnails.
Playlists tile opens the current queue, not a named-playlist manager.
Audio tile opens the existing media picker, not a separate music library.
Open Stream accepts direct HTTP(S) media URLs, not full IPTV catalogue import.
Construction-marked features and unsupported menu entries explicitly explain
that their Windows integrations are pending. Discover is not live yet.
No Android file, version or application name is modified.

Build: Actions -> Windows desktop preview -> Run workflow on updated main.
Download and fully extract the artifact and inner ZIP. Keep DLLs/data together.
Run hyper_player.exe. This is still an unsigned portable test application.
Not yet a signed EXE/MSI installer or Microsoft Store submission package.

Verification: shell syntax/static diff checks only in this environment.
Flutter analyzer/tests and Windows compilation have NOT been executed here.
CI must pass before use. Test playback, queue completion, grid/list, resizing,
folder picker, invalid URL, clear queue and library/player switching on Windows.
