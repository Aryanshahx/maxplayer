import 'package:flutter/material.dart';
import '../utils/app_language.dart';
import 'playback_sheets.dart';

String mediaClock(Duration value) {
  final seconds = value.inSeconds.clamp(0, 999999999);
  return '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class MediaInfoSheet extends StatelessWidget {
  final String title;
  final List<MapEntry<String, String>> rows;
  final Map<String, List<String>> tracks;
  const MediaInfoSheet(
      {super.key,
      required this.title,
      required this.rows,
      this.tracks = const {}});
  static Future<void> show(BuildContext context, MediaInfoSheet content) =>
      showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: const Color(0xff101013),
          constraints: const BoxConstraints(maxWidth: 1000),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          builder: (_) => content);
  @override
  Widget build(BuildContext context) => SafeArea(
      child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .62,
          minChildSize: .35,
          maxChildSize: .92,
          builder: (context, controller) => Column(children: [
                const PlaybackSheetHandle(),
                const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: LText('Video info',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)))),
                Expanded(
                    child: ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      for (final row in rows)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(row.key,
                                      style: const TextStyle(
                                          color: Color(0xff9296a0),
                                          fontSize: 11.5)),
                                  const SizedBox(height: 2),
                                  SelectableText(row.value,
                                      style: const TextStyle(fontSize: 12.5))
                                ])),
                      const Divider(color: Color(0xff26262c)),
                      for (final section in tracks.entries)
                        if (section.value.isNotEmpty) ...[
                          Padding(
                              padding:
                                  const EdgeInsets.only(top: 10, bottom: 5),
                              child: LText(section.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700))),
                          for (final track in section.value)
                            Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(track,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.white70))),
                        ],
                      const SizedBox(height: 14),
                      const Text(
                          'Snapshot taken when opened. Source URLs may contain credentials; review before sharing.',
                          style:
                              TextStyle(fontSize: 11, color: Colors.white38)),
                    ])),
              ])));
}

class RepeatControlSheet extends StatelessWidget {
  final Duration? a;
  final Duration? b;
  final ValueChanged<String> onAction;
  const RepeatControlSheet({super.key, this.a, this.b, required this.onAction});
  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlaybackSheetHandle(),
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: LText('A–B repeat',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Text(
                    a == null
                        ? 'Off · Set A to mark the start of a loop.'
                        : b == null
                            ? 'A ${mediaClock(a!)} · Seek forward, then set B.'
                            : 'Loop ${mediaClock(a!)} – ${mediaClock(b!)}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12.5))),
            ListTile(
                leading: const Icon(Icons.first_page_rounded),
                title: const LText('Set A at current position'),
                onTap: () => onAction('a')),
            ListTile(
                leading: const Icon(Icons.last_page_rounded),
                title: const LText('Set B at current position'),
                onTap: () => onAction('b')),
            ListTile(
                leading: const Icon(Icons.repeat_rounded),
                title: const LText('Disable repeat'),
                onTap: () => onAction('off')),
            const SizedBox(height: 18),
          ]);
}
