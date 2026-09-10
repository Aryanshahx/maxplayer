import 'package:flutter/material.dart';

import '../theme.dart';

/// Static info screens: User Manual & Privacy Policy. Bundled, offline.

class UserManualScreen extends StatelessWidget {
  const UserManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocScreen(
      title: 'User Manual',
      sections: {
        'Library': [
          'Videos on your device appear automatically after you grant media access.',
          'Tap the search icon to filter by name.',
          'Long-press any video for actions: add to playlist, private space, properties, delete.',
          'Delete is always confirmed by Android\u2019s own system dialog.',
        ],
        'Player gestures': [
          'Single tap — show or hide controls.',
          'Double tap left / right — jump back / forward 10 seconds.',
          'Long press and hold — 2\u00d7 speed; release to return to normal.',
          'Swipe up / down on the LEFT — screen brightness.',
          'Swipe up / down on the RIGHT — volume.',
          'Swipe left / right across the screen — seek through the video.',
          'Pinch with two fingers — zoom into the picture.',
        ],
        'Resume': [
          'Positions are saved continuously. Kill the app, reopen a video, and you\u2019re offered to resume where you left.',
          'Finishing a video clears its resume point automatically.',
        ],
        'Folders, Playlists, Private Space': [
          'Folders groups videos by storage folder.',
          'Playlists are yours: create, then long-press any video to add.',
          'Private Space hides videos behind your PIN \u2014 they disappear from the library and folders.',
          'History shows your last 25 opened videos.',
        ],
        'Display Settings': [
          'Grid or list layout, sorting, grouping, favourite-only view and the accent colour wheel \u2014 all from the \u22ee menu \u2192 Display settings.',
          'Playback action "Queue All" automatically plays the next video in your current view when one ends.',
        ],
      },
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocScreen(
      title: 'Privacy Policy',
      sections: {
        'The short version': [
          'Max Player works offline. Your videos, playlists, history, favourites and settings never leave your device. There are no accounts, no analytics, no tracking, and no ads.',
        ],
        'What we store': [
          'Media access permission is used only to list and play the videos already on your device.',
          'Playlists, favourites, private-space flags, watch history and resume points are stored locally in the app\u2019s private storage.',
          'The Private Space PIN is stored locally on-device only. Never share it.',
        ],
        'What we never do': [
          'No personal data is collected, sold or shared.',
          'No crash telemetry leaves the device \u2014 diagnostic logs stay in the app\u2019s documents folder for you alone.',
          'No internet connection is required for any core feature.',
        ],
        'Your control': [
          'Clear history any time from the History screen.',
          'Uninstalling the app removes all local data with it.',
        ],
      },
    );
  }
}

class _DocScreen extends StatelessWidget {
  const _DocScreen({required this.title, required this.sections});

  final String title;
  final Map<String, List<String>> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 32),
        children: [
          for (final entry in sections.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
              child: Text(entry.key.toUpperCase(),
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1)),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in entry.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('\u2022 ',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    height: 1.45)),
                            Expanded(
                              child: Text(line,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13.5,
                                      height: 1.45)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
