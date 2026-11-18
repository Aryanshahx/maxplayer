import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_language.dart';

Future<void> showAndroidInfoSheet(
        BuildContext context, String title, String body) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff14141c),
      constraints: const BoxConstraints(maxWidth: 1000),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .85,
          minChildSize: .4,
          maxChildSize: .95,
          builder: (context, controller) => AndroidInfoContent(
              title: title, body: body, controller: controller)),
    );

class AndroidInfoContent extends StatelessWidget {
  final String title, body;
  final ScrollController? controller;
  const AndroidInfoContent(
      {super.key, required this.title, required this.body, this.controller});
  Widget heading(String value) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: LText(value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)));
  Widget item(IconData icon, String name, String description) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 21, color: Colors.white70),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LText(name,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(description,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 12, height: 1.45)),
        ])),
      ]));
  @override
  Widget build(BuildContext context) {
    final manual = title == 'User manual';
    final about = title == 'About Hyper Player';
    return ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)))),
          Row(children: [
            Icon(manual
                ? Icons.menu_book_outlined
                : about
                    ? Icons.info_outline_rounded
                    : Icons.privacy_tip_outlined),
            const SizedBox(width: 10),
            Expanded(
                child: LText(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20))
          ]),
          if (manual) ...[
            heading('Home screen'),
            item(Icons.search, 'Search',
                'Search filenames from the queue, history and favourites.'),
            item(Icons.sync, 'Rescan',
                'Look for new direct-child media in folders you chose. This is not whole-PC indexing.'),
            item(Icons.more_vert, 'More options',
                'Language, Display Settings, Statistics, History, support and playback tools.'),
            heading('Your library'),
            item(Icons.folder_outlined, 'Folders',
                'Choose a folder, browse its media cards, then select a file to play.'),
            item(Icons.music_note_outlined, 'Audio',
                'Search and sort chosen audio files. Selecting a track opens the Windows player.'),
            item(Icons.playlist_play_rounded, 'Playlists',
                'Create a list with or without the current queue. Use the playlist detail button to add the current queue.'),
            heading('Keyboard & mouse'),
            item(Icons.keyboard, 'Ctrl + O',
                'Open local video or audio files using the Windows file picker.'),
            item(Icons.link, 'Ctrl + L',
                'Open the network-stream screen. HTTP(S) direct media is supported.'),
            item(Icons.mouse_outlined, 'Playback controls',
                'Use the visible media_kit controls for seeking, volume, fullscreen and available tracks. Android touch gestures are not claimed here.'),
            heading('Playback tools'),
            item(Icons.subtitles_outlined, 'Subtitles',
                'Load an external subtitle file; adjust timing through Subtitle delay.'),
            item(Icons.speed, 'Speed', 'Select 0.5×–4× from Playback speed.'),
            item(Icons.repeat, 'A–B repeat',
                'Set A, seek forward, then set B. Looping uses one-second polling, not frame-accurate boundaries.'),
            item(Icons.bedtime_outlined, 'Sleep timer',
                'Pause after the chosen time. The timer resets when the application exits.'),
            heading('Online features'),
            item(Icons.movie_outlined, 'Discover movies',
                'Browse TMDB metadata, cast, seasons and reviews. Trailers open on YouTube in your browser. Full films are not supplied.'),
            item(Icons.live_tv_outlined, 'IPTV import',
                'Import your own M3U file or URL. It is not the complete Android Live TV/channel-browser implementation.'),
            heading('Availability'),
            const Text(
                'Construction-marked screens are not implemented. Vault security, Windows Whisper, cloud integration, casting and Quick Share are not available simply because their tiles appear.',
                style: TextStyle(
                    color: Colors.white54, fontSize: 12, height: 1.5)),
          ] else if (about) ...[
            const SizedBox(height: 14),
            const LText('Hyper Player',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: .3)),
            const SizedBox(height: 2),
            const LText('by Hyper Tech Labs',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            heading('About this Windows preview'),
            SelectableText(body,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.45)),
            heading('Diagnostics'),
            item(Icons.desktop_windows_outlined, 'Platform',
                '${Platform.operatingSystem} · ${Platform.operatingSystemVersion}'),
            OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(
                      text:
                          'Hyper Player Windows preview 0.2.0\nOS: ${Platform.operatingSystem}\nVersion: ${Platform.operatingSystemVersion}'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Basic OS diagnostics copied.')));
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy basic diagnostics')),
            TextButton(
                onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Hyper Player - All Formats',
                    applicationVersion: '0.2.0 preview'),
                child: const Text('Open-source licenses')),
          ] else ...[
            const SizedBox(height: 14),
            SelectableText(body,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.6)),
          ],
        ]);
  }
}
