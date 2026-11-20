import 'user_manual_android.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_language.dart';

Future<void> showAndroidInfoSheet(
        BuildContext context, String title, String body) =>
    title == 'User manual'
        ? UserManualSheet.show(context)
        : showModalBottomSheet<void>(
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
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: LText(value.toUpperCase(),
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)));
  Widget item(IconData icon, String name, String description) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: Colors.white70),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LText(name,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(description,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 12.5, height: 1.35)),
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
                'Language, Display Settings, Statistics, User manual, About, Privacy, Report a problem and Instagram. Playback tools are in the player, not the Home menu.'),
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
                'Construction-marked screens are not implemented. Vault security, Windows Whisper, direct cloud-account integration, casting and native app-sharing integration are not available simply because their tiles appear.',
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

void showWindowsPrivacy(BuildContext context) {
  showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            backgroundColor: const Color(0xff1b1b24),
            title: const Text('Privacy policy',
                style: TextStyle(color: Colors.white, fontSize: 17)),
            scrollable: true,
            content: const Text(
                'HYPER PLAYER — WINDOWS PREVIEW\nDeveloper: Hyper Tech Labs\n\nLocal media and settings\nLocal media is not uploaded. Queue, folder paths, history, favourites, playlists, language and playback counters are stored locally without encryption. URLs may contain credentials; do not share application data. Windows Shell is used locally for cached video thumbnails. Cloud imports copy selected provider files into the local application support folder. Provider sign-in/downloads stay in Windows or the provider. Saved network-location names, hosts and paths are also stored locally without encryption. Windows handles share-session authentication; no NAS passwords are collected by this screen. Imported files are not encrypted; save a copy before uninstalling or clearing data.\n\nPrivate Space (experimental)\nSelected files are copied into encrypted local storage using password-derived protection and Windows CurrentUser DPAPI. Original files remain untouched and may still appear in the library. Export writes an unencrypted copy to your chosen destination. Vault filenames and file keys are encrypted; no private playback, thumbnails or history are generated. There is no password-reset bypass: losing the password, key file or Windows account protection may make copies unrecoverable. This is not independently audited or validated on native Windows yet.\n\nOnline features\nDiscover sends queries/title IDs to TMDB; API and image hosts receive network connections including IP addresses. Metadata is cached locally. Network streams contact their source hosts. Quick Share starts a temporary local HTTP server only after explicit user selection and consent, with access controlled by a random session link. Anyone with the link on a reachable network can access the selected files until stopped or expired; HTTP is not encrypted. Receive sends requests to the sender address you enter and writes selected files to your chosen folder. Session links are not saved by the app. Trailers and external links open their respective apps and follow provider policies.\n\nAndroid services\nThis Windows preview does not integrate Android Firebase analytics, AdMob or FCM notifications. Android policy statements must not be assumed to describe this build.\n\nContact\ntechlabs.hyper@gmail.com',
                style: TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.45)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'))
            ],
          ));
}
