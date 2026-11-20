import 'gesture_illustrations.dart';
import '../utils/app_language.dart';
import 'package:flutter/material.dart';

import 'input_illustrations.dart';

/// In-app user manual, opened from the home screen's ⋮ menu
/// ("User manual"). Static content only - no platform calls. Gesture
/// entries are illustrated with drawn vector diagrams
/// ([DesktopInputIllustration]) so no image assets are bundled.
class UserManualSheet extends StatelessWidget {
  final ScrollController? scrollController;

  const UserManualSheet({super.key, this.scrollController});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 1000),
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            UserManualSheet(scrollController: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final accent = Colors.white;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        // Grab handle.
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: const BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
        Row(
          children: [
            Icon(Icons.menu_book_outlined, color: accent),
            const SizedBox(width: 10),
            const LText(
              'User manual',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        // --- Home screen ------------------------------------------------
        _SectionTitle('Home screen', accent),
        for (final item in _homeItems) _IconRow(item: item),

        // --- Gestures (illustrated) -------------------------------------
        _SectionTitle('Keyboard & mouse', accent),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: LText(
            'Use keyboard/mouse on a normal PC or the configurable touch gestures on a touchscreen. Native renderer behaviour still requires Windows validation.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ),
        for (final g in _gestureItems) _GestureCard(item: g),
        _SectionTitle('Touchscreen gestures', accent),
        for (final entry in const <GestureKind, (String, String)>{
          GestureKind.singleTap: ('Tap', 'Show or hide player controls.'),
          GestureKind.doubleTapSides: (
            'Side double-tap',
            'Seek by the configured 5/10/15/30-second step. Keyboard: Left/Right.'
          ),
          GestureKind.doubleTapMiddle: (
            'Middle double-tap',
            'Play or pause. Keyboard: Space.'
          ),
          GestureKind.swipeBrightness: (
            'Brightness / volume swipe',
            'Left side controls video brightness; right side controls volume. B opens sliders; Page Down and Page Up adjust brightness; Up/Down changes volume.'
          ),
          GestureKind.swipeSeek: (
            'Horizontal seek',
            'Drag to scrub. Keyboard: Left/Right.'
          ),
          GestureKind.pinchZoom: (
            'Pinch / pan',
            'Enable pinch zoom in Player Settings for focal zoom. + / − zoom; Shift+arrows pan. Z cycles screen fits.'
          ),
          GestureKind.holdSpeed: (
            'Hold to speed up',
            'Temporarily accelerate, then restore the previous rate on release. Keyboard: hold R.'
          ),
        }.entries)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    GestureIllustration(kind: entry.key),
                    Text(entry.value.$1,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(entry.value.$2, textAlign: TextAlign.center)
                  ]))),

        // --- Player buttons ---------------------------------------------
        _SectionTitle('Player buttons', accent),
        for (final item in _playerItems) _IconRow(item: item),

        // --- Smart features ---------------------------------------------
        _SectionTitle('Smart features', accent),
        for (final item in _smartItems) _IconRow(item: item),

        // --- Tips & FAQ ---------------------------------------------------
        _SectionTitle('Tips & answers', accent),
        for (final item in _tipItems) _IconRow(item: item),

        const SizedBox(height: 22),
        const Center(
          child: Text(
            'Hyper Player Windows preview  ·  0.2.0  ·  Hyper Tech Labs',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color accent;
  const _SectionTitle(this.text, this.accent);

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Text row with a small leading icon (non-illustrated entries).
class _IconRow extends StatelessWidget {
  final _Item item;
  const _IconRow({required this.item});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gesture guide card: drawn illustration on top, title + detailed
/// step-by-step description underneath.
class _GestureCard extends StatelessWidget {
  final _GestureItem item;
  const _GestureCard({required this.item});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          DesktopInputIllustration(kind: item.kind),
          const SizedBox(height: 8),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final IconData icon;
  final String title;
  final String description;
  const _Item(this.icon, this.title, this.description);
}

class _GestureItem {
  final DesktopInputKind kind;
  final String title;
  final String description;
  const _GestureItem(this.kind, this.title, this.description);
}

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

const List<_Item> _homeItems = [
  _Item(Icons.video_file_outlined, 'Open File & system scanning',
      'Open File in the top bar opens the picker. In Folders choose Scan system / folders, then Scan all local drives or specific roots, including accessible subfolders. Add each drive root to cover a device. Progress/Cancel and partial results are shown; 20,000 media and 100,000 directory bounds apply. Protected folders/links are skipped; missing entries are not deleted.'),
  _Item(Icons.search, 'Search',
      'Search filenames in the queue, history, favourites and saved playlists. Media names remain in their original language.'),
  _Item(Icons.tune, 'Display settings',
      'Switch grid/list view and supported filename sorting. Other Android display settings are not automatically enabled on Windows.'),
  _Item(Icons.grid_view_rounded, 'Quick tiles under Discover',
      'Open your library, playlists, folders, audio, cloud import or network stream. Construction-marked integrations remain unavailable.'),
  _Item(Icons.movie_outlined, 'Discover movies & series',
      'Browse the cinematic hero, category shelves, Top 10, search and title details. SEE ALL opens a paged category. TMDB supplies metadata, not full movies.'),
  _Item(Icons.history, 'History & resume',
      'Playback records recent sources. Local resume positions are sampled and saved; abrupt termination can lose recent progress. Turn resume off in Player settings.'),
  _Item(Icons.bar_chart, 'Statistics',
      'Watch statistics shows recorded daily playback, a seven-day chart and most-watched filenames. No historical viewing time is invented.'),
];
const List<_GestureItem> _gestureItems = [
  _GestureItem(
      DesktopInputKind.keyboard,
      'Brightness, fit, zoom & hold shortcuts',
      'H: show/hide controls. L: lock controls; Escape unlocks. B: brightness/volume sliders. Page Down / Page Up: video brightness. Z: next screen fit. + / −: zoom in/out. Shift+arrows: pan while zoomed. Hold R: temporary speed boost; release restores the previous rate. These apply with the player focused; OS display brightness is unchanged.'),
  _GestureItem(DesktopInputKind.click, 'Touchscreen gestures',
      'Configure side double-tap seek, centre double-tap play/pause, left brightness, right volume and horizontal seek in Player settings. Long-press temporarily speeds up and restores the prior rate on release. Pinch mode OFF cycles fits; ON enables 1–4x focal zoom and pan. A quick two-finger tap resets to the default fit. Brightness is video-only dimming, not system brightness.'),
  _GestureItem(DesktopInputKind.click, 'Single click — show / hide controls',
      'Click the video background to show or hide the overlay. Move the mouse to show controls. During playback, auto-hide uses the configured 3–6 second delay unless disabled in Player settings.'),
  _GestureItem(DesktopInputKind.keyboard, 'Space / Left / Right',
      'With the video focused, Space toggles playback. Left and Right seek the configured 5/10/15/30-second step. For live streams without a known duration, seeking may be unavailable.'),
  _GestureItem(DesktopInputKind.keyboard, 'Volume, mute & fullscreen',
      'Up/Down change volume, M toggles mute and F toggles fullscreen. Double-click the video background also toggles fullscreen.'),
  _GestureItem(DesktopInputKind.click, 'Lock / unlock controls',
      'The lock button hides player controls. Click the video to reveal the unlock button, or press Escape to unlock. This is an input lock, not a secure vault.'),
];
const List<_Item> _playerItems = [
  _Item(Icons.auto_fix_high, 'Karaoke, Enhance & HDR',
      'Extras includes timed-text karaoke (estimated word timing, not generated captions), native sharpen/contrast enhancement and HDR tone-mapping algorithms. HDR mapping only affects HDR sources on supported renderers. Readback/error checks do not replace native Windows visual validation.'),
  _Item(Icons.image_search_outlined, 'Timeline frame preview',
      'Hover the progress bar to request a local-file frame with a separate muted decoder. It does not seek main playback, fetch network streams, save frames to disk or use private-vault files. Loading and Preview unavailable are explicit. Codec/native renderer support must be checked on Windows.'),
  _Item(Icons.play_circle_outline, 'Playback & queue',
      'Use Previous, Play/Pause and Next. Shuffle visits queue entries without repeating within a cycle; Previous follows playback history. Repeat cycles Off / All / One.'),
  _Item(Icons.volume_up, 'Volume',
      'Use touch right-side swipe, mouse wheel or Up/Down; M or the mute button toggles sound. The Sound setting allows amplification up to 200%, which can distort audio; disabling boost caps volume at 100%.'),
  _Item(Icons.speed, 'Playback speed',
      'The rate pill opens the speed sheet. Choose a preset or release the slider from 0.5× to 4×. Actual rate support depends on the media/backend.'),
  _Item(Icons.tune, 'Subtitles, audio tracks & A–B',
      'Open Extras for actual track selection, Subtitle Off, external subtitle files, timing adjustment and loop controls. Missing tracks are not fabricated.'),
  _Item(Icons.aspect_ratio, 'Video fit',
      'Cycle Fit, Crop, Stretch, 16:9, 4:3 and Original. Forced ratios change the picture frame; Original renders without scaling.'),
  _Item(Icons.playlist_play, 'Playlists',
      'The player queue sheet highlights the selected item and links to your saved playlists. Select an item to play it.'),
  _Item(Icons.more_vert, 'More actions',
      'Video info, Equalizer & Audio FX, Screenshot, Sleep timer, Windows wireless display and Windows mini-player. Cast opens the system Miracast chooser, not Chromecast/DLNA media casting. PiP is an always-on-top mini-window with Return to full player. Both native integrations require Windows validation.'),
  _Item(Icons.settings_outlined, 'Player settings',
      'Auto-hide and local-file resume are saved on this PC. Rotation is a phone feature, not a Windows toggle.'),
];
const List<_Item> _smartItems = [
  _Item(Icons.ios_share_rounded, 'Quick Share',
      'Select known videos or add files, confirm a trusted network and start Direct send. The temporary private browser link works only while the session is open (15-minute maximum). Receive loads a sender manifest and saves checked videos to a folder you choose. HTTP is not encrypted; do not share the link publicly. Current Android Receive does not retain Windows token paths, so use its browser to receive a Windows link. Native Via other apps is unavailable.'),
  _Item(Icons.dns_outlined, 'Network Storage',
      'Save an SMB location using a server and share path. Sign in to that server through Windows File Explorer first. Browse one folder at a time; there is no automatic LAN or recursive scan. HTTP(S)/WebDAV file entries open a direct media resource, not a WebDAV folder browser. FTP/FTPS and app-stored network passwords are unavailable.'),
  _Item(Icons.repeat_one, 'A–B loop',
      'Set A, seek forward and set B more than one second later. Disable repeat to clear both points. Loop boundaries use sampled position checks, not frame-accurate editing.'),
  _Item(Icons.graphic_eq, 'Equalizer & dialogue boost',
      'Five bands and Android presets are connected to the native filter backend. A rejected setting shows an error; native Windows audio verification is still required.'),
  _Item(Icons.camera_alt_outlined, 'Screenshot',
      'Captures an available video frame and opens Save As for a PNG. An audio-only source cannot produce a video screenshot.'),
  _Item(Icons.bedtime_outlined, 'Sleep timer',
      'Choose a duration or Until end. Until end pauses before automatic queue advance. The timer is not an operating-system sleep/shutdown command.'),
  _Item(Icons.music_note, 'Audio Now Playing',
      'Audio files use the disc/title/count layout, with queue, shuffle, repeat, speed, progress and volume. Back pauses audio; the Home mini player can reopen it.'),
  _Item(Icons.video_library, 'In My Library',
      'A conservatively matched known local video can be opened from Discover details. Explicitly different-year remakes are rejected. A match does not download any film.'),
];
const List<_Item> _tipItems = [
  _Item(Icons.folder_open, 'Open media',
      'Ctrl+O opens files and Ctrl+L opens network streams. Folders are scanned only after you choose them. Supported extensions are not a guarantee that every codec will decode.'),
  _Item(Icons.image_outlined, 'Missing thumbnails',
      'Windows Shell supplies local thumbnails when a matching handler exists. Unsupported codecs or blocked handlers retain a neutral placeholder. Network streams do not use local extraction.'),
  _Item(Icons.cloud_outlined, 'Cloud provider files',
      'The Windows picker can access files exposed by installed/synced providers. Provider sign-in/download is handled by Windows or that provider, not by Hyper Player.'),
  _Item(Icons.privacy_tip_outlined, 'Privacy & credentials',
      'Do not share stream URLs, saved application data or diagnostics containing private details. Discover uses online providers; local media is not uploaded by thumbnail generation.'),
  _Item(Icons.lock_outline, 'Private Space (experimental)',
      'Use a 12–128 character password. Encrypted copies require the original Windows account and vault key file; there is no password reset. Original files remain outside the vault. Export creates an unencrypted copy. In-app private playback is unavailable. Windows lifecycle and DPAPI validation are pending. Do not remove setup.lock or recovery files blindly after a failed setup.'),
  _Item(Icons.construction_outlined, 'Availability',
      'Private Space encrypted-copy storage is experimental and has no in-app playback yet. FTP/FTPS uses a Windows transfer session and local downloads; credentials are not saved. Direct NAS passwords remain managed by Windows. Local Whisper supports fast/base/small/medium opt-in downloads; native execution needs Windows validation. Chromecast/DLNA casting is not implemented. Karaoke needs text subtitles; native Enhance/HDR integration and actual rendering require Windows validation. Windows wireless-display/mini-player and preview-frame decoding are source-integrated but need native validation. Their presence in Android does not make them working Windows features.'),
];
