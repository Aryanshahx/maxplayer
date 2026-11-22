import '../utils/app_language.dart';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../theme.dart';
import 'gesture_illustrations.dart';

/// In-app user manual, opened from the home screen's ⋮ menu
/// ("User manual"). Static content only - no platform calls. Gesture
/// entries are illustrated with drawn vector diagrams
/// ([GestureIllustration]) so no image assets are bundled.
class UserManualSheet extends StatelessWidget {
  final ScrollController? scrollController;

  const UserManualSheet({super.key, this.scrollController});

  static Future<void> show(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: LText('User manual')),
            body: const UserManualSheet(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final accent = AppColors.accent;
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_outlined, color: accent),
            SizedBox(width: 10),
            LText(
              'User manual',
              style: TextStyle(
                color: AppColors.textPrimary,
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
        _SectionTitle('Gesture controls', accent),
        Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: LText(
            'All gestures work both in windowed and full-screen mode, on '
            'every video. Each one can be switched off individually in the '
            'player\'s ⚙ settings sheet.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ),
        for (final g in _gestureItems) _GestureCard(item: g),

        // --- Player buttons ---------------------------------------------
        _SectionTitle('Player buttons', accent),
        for (final item in _playerItems) _IconRow(item: item),

        // --- Smart features ---------------------------------------------
        _SectionTitle('Smart features', accent),
        for (final item in _smartItems) _IconRow(item: item),

        // --- Tips & FAQ ---------------------------------------------------
        _SectionTitle('Tips & answers', accent),
        for (final item in _tipItems) _IconRow(item: item),

        SizedBox(height: 22),
        Center(
          child: Text(
            'Max Player v$kAppVersion  ·  Hyper Tech Labs',
            style: TextStyle(color: AppColors.border, fontSize: 12),
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
      padding: EdgeInsets.only(top: 18, bottom: 6),
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
      padding: EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 20, color: AppColors.textSecondary),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  item.description,
                  style: TextStyle(
                    color: AppColors.textSecondary,
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
      margin: EdgeInsets.symmetric(vertical: 6),
      padding: EdgeInsets.fromLTRB(10, 6, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          GestureIllustration(kind: item.kind),
          SizedBox(height: 8),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            item.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
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
  final GestureKind kind;
  final String title;
  final String description;
  const _GestureItem(this.kind, this.title, this.description);
}

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

final List<_Item> _homeItems = [
  _Item(
    Icons.sync,
    'Rescan button (⟳ top bar)',
    'New videos you download or copy do not appear by themselves - tap the '
        '⟳ button in the top bar (or pull the list down) and the whole '
        'device is re-scanned. While scanning, a progress bar shows how '
        'far along it is.',
  ),
  _Item(
    Icons.search,
    'Search',
    'Tap the search icon in the top bar to open the full-screen search '
        'page. Type any part of a file name and the list filters live as '
        'you type; clear the text to see everything again.',
  ),
  _Item(
    Icons.favorite_border,
    'Favourites',
    'Tap the ♥ on any video to star it. Then open ⋮ → Display settings '
        'and enable "Show only favourites" to see just your picks. Stars '
        'are remembered between launches.',
  ),
  _Item(
    Icons.tune,
    'Sort, group, grid & accent colour',
    '⋮ → Display settings lets you: switch between list and grid view, '
        'sort by name / length / date added / size (tap again to flip the '
        'direction), group by folder, and change the '
        'app\'s accent colour with the Red, Green and Blue sliders.',
  ),
  _Item(
    Icons.grid_view_rounded,
    'Quick tiles under the Discover banner',
    'Two slideable 2x2 shortcut grids sit under the Discover banner: '
        'Private Space, Playlists, Folders and Audio on the first '
        'page; Network Storage, VPN, Open Stream (IPTV) and '
        'Quick Share on the second. The grid slides away when you scroll '
        'down through your videos and returns when you scroll back up.',
  ),
  _Item(
    Icons.movie_outlined,
    'Discover (trending movies & series)',
    'The poster banner under the title opens the Discover section: '
        'trending, upcoming and genre-wise movies and series powered by '
        'TMDB, with an "Ask AI" helper that suggests what to watch based '
        'on your taste. Movies already on your device play straight from '
        'the details sheet.',
  ),
  _Item(
    Icons.history,
    'History & resume',
    'The 🕘 button in the top bar lists your recently watched videos. '
        'Resume restores saved progress when available. Turn '
        'this off in the player\'s ⚙ settings → Resume playback.',
  ),
  _Item(
    Icons.bar_chart,
    'Statistics',
    '⋮ → Watch statistics shows how much you watched each day of the '
        'last week as a bar chart, plus cards: today, daily average, best '
        'day, last 30 days total and your day-by-day watching streak. '
        'The "Most watched" list ranks the videos you have spent the '
        'most time on.',
  ),
];

final List<_GestureItem> _gestureItems = [
  _GestureItem(
    GestureKind.singleTap,
    'Single tap - show / hide controls',
    'Tap once anywhere on the video: the seek bar and all buttons slide '
        'in. Tap again (or wait a few seconds) and they hide so nothing '
        'covers the picture. The auto-hide delay can be changed in ⚙ '
        'settings.',
  ),
  _GestureItem(
    GestureKind.doubleTapSides,
    'Double-tap the sides - seek ±10 seconds',
    'Double-tap the LEFT third of the video to jump back 10 seconds, the '
        'RIGHT third to jump forward 10 seconds. Each extra double-tap '
        'adds another 10 seconds. The 10-second step is configurable in '
        '⚙ settings (5s-30s).',
  ),
  _GestureItem(
    GestureKind.doubleTapMiddle,
    'Double-tap the middle - play / pause',
    'Double-tap the CENTER of the video to pause and resume - no need to '
        'aim for the small button.',
  ),
  _GestureItem(
    GestureKind.swipeBrightness,
    'Swipe on the LEFT half - brightness',
    'Put a finger on the left half of the video and slide UP to brighten '
        'or DOWN to dim (a percentage shows at the top while you swipe). '
        'This is app-local: your normal brightness is restored the moment '
        'you leave the player.',
  ),
  _GestureItem(
    GestureKind.swipeSeek,
    'Swipe SIDEWAYS - scrub through the video',
    'Drag one finger LEFT or RIGHT anywhere on the video to scrub: the '
        'pill at the top shows how far you are jumping and the video '
        'follows live while you drag. Release to land exactly there. '
        'When zoomed in, the same drag moves the picture instead. Can be '
        'turned off in ⚙ settings → Gesture controls.',
  ),
  _GestureItem(
    GestureKind.pinchZoom,
    'Pinch with two fingers - zoom up to 4×',
    'Place TWO fingers on the video and spread them apart to zoom in, '
        'pinch them together to zoom out (1.0× to 4.0×). The zoom anchors '
        'at your fingers, and while zoomed you can drag with ONE finger '
        'to move the picture around. If you pinch back almost to 1×, the '
        'video snaps back to normal on its own.',
  ),
  _GestureItem(
    GestureKind.holdSpeed,
    'Hold your finger - speed boost',
    'Press and HOLD anywhere on the video to play faster (2× by default) '
        'for as long as you keep holding; lift your finger to return to '
        'normal speed. The badge stays visible for the whole boost. The '
        'multiplier (1.5×/2×/2.5×/3×) is set in ⚙ settings.',
  ),
];

final List<_Item> _playerItems = [
  _Item(
    Icons.queue_music,
    'Playlist / queue',
    'Opens the side panel with everything queued up. Tap any row to jump '
        'to that video, and the ✕ to remove one.',
  ),
  _Item(
    Icons.screen_rotation,
    'Rotation lock',
    'By default the player follows your phone - tip it sideways and the '
        'video rotates with you. Tap the rotate button to LOCK the '
        'current orientation; tap again to release the lock.',
  ),
  _Item(
    Icons.aspect_ratio,
    'Fit (picture size)',
    'Cycles Fit → Crop → Stretch → 16:9 → 4:3 → Original. Fit shows the '
        'whole frame with bars, Crop zooms to fill the screen (edges '
        'cut), Stretch fills exactly (may distort).',
  ),
  _Item(
    Icons.graphic_eq,
    'Equalizer (⋮ menu)',
    'Five-band equalizer with presets (Bass, Vocal, Treble, Rock...), '
        'dialogue boost and HDR tone-mapping. Your last setting is '
        'remembered and applied to every video.',
  ),
  _Item(
    Icons.info_outline,
    'Video info (⋮ menu)',
    'Player ⋮ menu → Video info: full technical card for the current '
        'video - container format, resolution and aspect ratio, frame '
        'rate, video codec, audio codec with channels and sample rate, '
        'bitrate, file size and modified date.',
  ),
  _Item(
    Icons.timer_outlined,
    'A→B loop',
    'Tap at the start of the part you want to repeat (A lights up), tap '
        'again at the end (B lights up) - that section loops until you '
        'tap a third time to clear.',
  ),
  _Item(
    Icons.picture_in_picture_alt_outlined,
    'Picture-in-picture (⋮ menu)',
    'Shrinks the video to a floating window that keeps playing while you '
        'use other apps. Tap the window for a play/pause button and tap '
        'the expand icon to come back full-screen.',
  ),
  _Item(
    Icons.speed,
    'Playback speed',
    'Tap the "1.0×" label in the bottom controls to pick a constant '
        'speed from 0.5× up to 4× (drag the slider or tap a preset).',
  ),
  _Item(
    Icons.subtitles_outlined,
    'Subtitles & audio tracks',
    'Switch between embedded subtitle languages or turn them off, and '
        'pick a different audio track for dual-audio files (e.g. Hindi / '
        'English).',
  ),
  _Item(
    Icons.camera_alt_outlined,
    'Screenshot (⋮ menu)',
    'Saves a current-frame PNG into Pictures/Max Player for your gallery. '
        'Capture and subtitle inclusion depend on the playback backend; '
        'check the saved image. Not available for online streams.',
  ),
  _Item(
    Icons.lock_outline,
    'Screen lock / kids mode (left edge)',
    'The lock button on the left edge of the video locks EVERY button '
        'and gesture - safe to hand the phone to a child or keep in a '
        'pocket. To unlock, double-tap (or long-press) the lock on the '
        'right edge. The button can be hidden in ⚙ settings → Player '
        'buttons.',
  ),
  _Item(
    Icons.settings_outlined,
    'Player settings (⚙ top bar)',
    'Every gesture can be turned on/off individually (including '
        'horizontal swipe-to-seek), plus: seek step, auto-hide delay, '
        'speed-boost multiplier, resume playback, and the screen-lock '
        '(kids mode) button.',
  ),
];

final List<_Item> _smartItems = [
  _Item(
    Icons.folder_special_outlined,
    'Whole-device scanning',
    'Scan media exposed to the app by Android permissions and MediaStore - WhatsApp Video, '
        'Telegram, Android/media folders, internal storage and external '
        'SD cards - via Android\'s MediaStore. Access your folders '
        'cleanly from the "Folders" quick tile.',
  ),
  _Item(
    Icons.speed,
    'Playback speed up to 4x (remembered)',
    'Tap the "1.0×" button in the player controls: 0.5× … 4×. The speed '
        'you pick now stays applied for the next video and the next time '
        'you open the app.',
  ),
  _Item(
    Icons.lock_outline,
    'Private folder (PIN)',
    'Long-press any video → "Move to Private Space". Hidden videos '
        'disappear from Gallery and file managers. Open them from the '
        '"Private Space" tile after your PIN. Forgot the PIN? Tap '
        '"Forgot PIN?" → unlock your PHONE once (device password, '
        'pattern or fingerprint) → set a new PIN - hidden videos are '
        'never wiped.',
  ),
  _Item(
    Icons.live_tv_outlined,
    'Open Stream (IPTV)',
    'Paste a direct video link (http/https) or a live stream '
        '(rtsp/rtmp/mms) and try playback. Availability and codec support vary. M3U playlists open as '
        'a channel list.',
  ),
  _Item(
    Icons.vpn_lock_outlined,
    'VPN — optional connection',
    'Open the VPN tile, read and accept the disclosure, choose WARP, '
        'Riseup, VPN Gate or a trusted custom profile, then Connect and '
        'approve Android VPN permission. Max Player only is the default; '
        'full-device routing is optional. Disconnect here when finished. '
        'Only one Android VPN can be active. Providers and volunteer '
        'servers may be unavailable; no speed, country or anonymity is '
        'guaranteed. There is no in-app kill switch. Use Android always-on '
        'and block-without-VPN settings only if supported. Custom profile '
        'secrets use Android Keystore-backed local storage; deleting a '
        'profile removes it locally. Check the status and exit information '
        'rather than assuming the connection succeeded.',
  ),
  _Item(
    Icons.dns_outlined,
    'Network Storage',
    'Choose SMB, FTP/FTPS or WebDAV, enter the host and direct media path, '
        'and supply credentials if required. Save then select the location '
        'to play. This is a saved direct connection, not a full NAS browser. '
        'Credentials are saved in local preferences, not the VPN encrypted '
        'store; use limited-access accounts and trusted networks. Support '
        'depends on your server, URL and playback backend.',
  ),
  _Item(
    Icons.share_outlined,
    'Quick Share',
    'Select files and share on the local network. Keep devices reachable '
        'on the same trusted network, open the displayed link or QR code '
        'on the receiving device, and stop sharing when done. Anyone with '
        'access to the active link may download selected files; local '
        'sharing is not end-to-end encrypted. VPN routing or Wi-Fi client '
        'isolation may prevent access.',
  ),
  _Item(
    Icons.palette_outlined,
    'Appearance, accent and Android TV',
    'Use Appearance for System default, Light or Dark. Display Settings '
        'contains one custom-colour section with three sliders for any opaque RGB '
        'colour, including greys. Choices are saved locally. Text contrast adapts, so very '
        'pale accents may look darker on light surfaces and dark accents lighter on dark surfaces. On Android TV '
        'use D-pad to move focus, OK to activate and Back to return. Touch '
        'gestures require a touch device; codec and platform feature '
        'availability varies by device.',
  ),
  _Item(
    Icons.translate_outlined,
    'Language and subtitles',
    'Choose the interface language in the menu. Bundled translations, '
        'including Pashto and Uzbek, work offline and do not translate '
        'videos or caption tracks. AI subtitle generation requires a '
        'supported local model download first and can be slow. Online '
        'Ask AI recommendations instead send your submitted prompt to '
        'OpenRouter and its selected model provider.',
  ),
  _Item(
    Icons.movie_filter_outlined,
    'Discover + Ask AI',
    'Browse trending movies and series from TMDB. "Ask AI" describes '
        'your taste and suggests real titles, with a trailer button and '
        '"In My Library" when the movie is already on your device.',
  ),
  _Item(
    Icons.bedtime_outlined,
    'Sleep timer',
    'Player ⋮ menu → Sleep timer: pauses playback after 15/30/45/60 '
        'minutes, or exactly at the end of the current video. While it '
        'runs, the remaining time shows under the video title.',
  ),
  _Item(
    Icons.graphic_eq_outlined,
    'Dialogue boost',
    'Player equalizer sheet: Dialogue boost lifts quiet speech. On-device '
        'audio filter, off by default.',
  ),
];

final List<_Item> _tipItems = [
  _Item(
    Icons.privacy_tip_outlined,
    'Privacy, permissions and notifications',
    'Open Privacy policy in the menu/About for details. The app has no '
        'advertising SDK but uses analytics, diagnostics, installation IDs, '
        'approximate country lookup and push services. There is no in-app '
        'analytics opt-out. Manage media, microphone and notifications in '
        'Android app settings. Blocking notifications does not disable '
        'analytics or erase existing provider records. Support and privacy '
        'requests: techlabs.hyper@gmail.com; never send passwords or keys.',
  ),
  _Item(
    Icons.rate_review_outlined,
    'Reviews and local data',
    'After meaningful use the app may request a Google Play review. Play '
        'decides whether its native dialog appears; reviews are optional '
        'and do not unlock features. Back up valuable media before moving '
        'it or clearing app data. Uninstalling can remove local settings '
        'and app-private files, not provider-side records.',
  ),
  _Item(
    Icons.info_outline,
    'A new video does not appear in the library?',
    'Press the ⟳ rescan button in the top bar or pull the list down. If '
        'it is still missing, check the file extension is a common one '
        '(.mp4, .mkv, .webm, ...) and that Max Player has storage '
        'permission.',
  ),
  _Item(
    Icons.info_outline,
    'Max Player does not show in "Open with"?',
    'Some galleries only offer Share: long-press the video → Share → Max '
        'Player. You can also open Android Settings → Apps → Max Player → '
        '"Open by default" and enable it for videos.',
  ),
  _Item(
    Icons.info_outline,
    'Can it play 8K video?',
    '8K playback (HEVC, VP9 or AV1) depends on decoder support. Smooth playback '
        'depends on your phone: recent flagships decode 8K in hardware, '
        'while mid-range chips may stutter at 8K. Even 1080p or 4K can stutter with unsupported codecs or slow storage.',
  ),
  _Item(
    Icons.info_outline,
    'A video will not play at all?',
    'Very rarely a file uses an unusual codec. Try playing it from its '
        'share menu (Share → Max Player) or re-encode it to H.264/AAC - '
        'the most compatible combination.',
  ),
];
