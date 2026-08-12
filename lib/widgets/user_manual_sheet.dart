import 'package:flutter/material.dart';

import '../state/theme_state.dart';

/// Shown in the sheet footer so support conversations can pin down exactly
/// which build is installed. Bump together with pubspec.yaml's version.
const String kAppVersion = '1.7.0';

/// In-app user manual, opened from the home screen's ⋮ menu
/// ("User manual"). Pure static content - no platform calls.
class UserManualSheet extends StatelessWidget {
  final ScrollController? scrollController;

  const UserManualSheet({super.key, this.scrollController});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            UserManualSheet(scrollController: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
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
            const Text(
              'User manual',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final section in _sections) ...[
          const SizedBox(height: 14),
          Text(
            section.title.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          for (final item in section.items)
            Padding(
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
            ),
        ],
        const SizedBox(height: 22),
        const Center(
          child: Text(
            'Max Player v$kAppVersion',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ManualSection {
  final String title;
  final List<_ManualItem> items;
  const _ManualSection(this.title, this.items);
}

class _ManualItem {
  final IconData icon;
  final String title;
  final String description;
  const _ManualItem(this.icon, this.title, this.description);
}

const List<_ManualSection> _sections = [
  _ManualSection('Home screen', [
    _ManualItem(
      Icons.sync,
      'Rescan button',
      'Tap the ⟳ button in the top bar whenever you download or copy new '
          'videos - they show up immediately (same as ⋮ → Rescan library).',
    ),
    _ManualItem(
      Icons.search,
      'Search',
      'Type in the search bar to filter your library by file name.',
    ),
    _ManualItem(
      Icons.favorite_border,
      'Favourites',
      'Tap the ♥ on any video to star it. ⋮ → Display settings → '
          '"Show only favourites" lists just your starred videos.',
    ),
    _ManualItem(
      Icons.tune,
      'Sort, group, view, accent colour',
      '⋮ → Display settings: sort by name / length / date added / size, '
          'group by name or folder, switch list ↔ grid, and pick the app '
          'accent colour.',
    ),
    _ManualItem(
      Icons.open_in_new,
      'Playing videos from other apps',
      'In your Gallery or Files app: tap a video → "Open with" → Max Player. '
          'If the gallery only shows "Share", use Share → Max Player instead. '
          'Untitled cloud videos may take a moment while they copy over.',
    ),
    _ManualItem(
      Icons.link,
      'Network streams',
      '⋮ → Open stream URL: paste an http(s), rtsp or rtmp link to play it '
          'directly.',
    ),
    _ManualItem(
      Icons.history,
      'History & resume',
      'The 🕘 button lists recently watched videos. Videos reopen exactly '
          'where you stopped watching (can be turned off in the player '
          'settings).',
    ),
    _ManualItem(
      Icons.bar_chart,
      'Statistics',
      '⋮ → Statistics shows how much you watched each day this week.',
    ),
  ]),
  _ManualSection('Gestures on the video', [
    _ManualItem(
      Icons.touch_app_outlined,
      'Single tap',
      'Show or hide the controls.',
    ),
    _ManualItem(
      Icons.replay_10,
      'Double-tap left / right third',
      'Jump back / forward (10 seconds by default).',
    ),
    _ManualItem(
      Icons.play_circle_outline,
      'Double-tap the middle',
      'Play / pause.',
    ),
    _ManualItem(
      Icons.brightness_6_outlined,
      'Swipe up-down on the LEFT half',
      'Change screen brightness (resets when you leave the player).',
    ),
    _ManualItem(
      Icons.volume_up_outlined,
      'Swipe up-down on the RIGHT half',
      'Change volume.',
    ),
    _ManualItem(
      Icons.pinch_outlined,
      'Pinch in / out',
      'Zoom the video up to 4× anywhere on the screen, then move it around '
          'with one finger.',
    ),
    _ManualItem(
      Icons.fast_forward,
      'Hold a finger on the video',
      'Speed boost while held (2× by default - change it in player '
          'settings). The speed badge stays on screen until you let go.',
    ),
  ]),
  _ManualSection('Player buttons', [
    _ManualItem(
      Icons.queue_music,
      'Playlist / queue',
      'Opens the queue side panel. Use the »| button at its top to collapse '
          'it again.',
    ),
    _ManualItem(
      Icons.fullscreen,
      'Fullscreen',
      'Fills the screen; double-taps and swipes keep working there.',
    ),
    _ManualItem(
      Icons.screen_rotation,
      'Rotation lock',
      'The player follows your phone\'s rotation. Tap the rotate icon to '
          'lock the current orientation; tap again if it is locked.',
    ),
    _ManualItem(
      Icons.aspect_ratio,
      'Fit',
      'Cycle Contain → Crop → Stretch for the picture size.',
    ),
    _ManualItem(
      Icons.graphic_eq,
      'Equalizer',
      '5-band equalizer with presets (in the top bar of the player).',
    ),
    _ManualItem(
      Icons.timer_outlined,
      'A-B loop',
      'Tap "A→B" once at the loop start, again at the end; tap a third '
          'time to clear.',
    ),
    _ManualItem(
      Icons.picture_in_picture_alt_outlined,
      'Picture-in-picture',
      'Puts the video in a floating mini window that keeps playing while '
          'you use other apps. Tap the window for a play/pause button.',
    ),
    _ManualItem(
      Icons.speed,
      'Playback speed',
      'Tap the "1.0x" label in the controls to pick a constant speed.',
    ),
    _ManualItem(
      Icons.subtitles_outlined,
      'Subtitles & audio tracks',
      'Switch subtitle language or audio track (e.g. Hindi / English '
          'dual-audio).',
    ),
    _ManualItem(
      Icons.settings_outlined,
      'Player settings (⚙ top bar)',
      'Turn each gesture on/off, change the seek step, auto-hide delay, '
          'speed boost multiplier and resume behaviour.',
    ),
  ]),
  _ManualSection('Tips', [
    _ManualItem(
      Icons.info_outline,
      'A video does not appear in the library?',
      'Press the ⟳ rescan button. If it is still missing, check that the '
          'file ends in a common video extension (.mp4, .mkv, ...).',
    ),
    _ManualItem(
      Icons.info_outline,
      'Max Player does not show in "Open with"?',
      'Some galleries hide video apps under Share: long-press the video → '
          'Share → Max Player. Also check Android Settings → Apps → '
          'Max Player → Open by default.',
    ),
  ]),
];
