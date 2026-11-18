import 'package:flutter/material.dart';
import '../utils/app_language.dart';
import 'playback_sheets.dart';

class DesktopTrackChoice {
  final String id;
  final String label;
  const DesktopTrackChoice(this.id, this.label);
}

String desktopTrackLabel(
    {required String id, String? title, String? language, String? codec}) {
  final parts = [
    if (title?.isNotEmpty ?? false) title!,
    if (language?.isNotEmpty ?? false) language!.toUpperCase(),
    if (codec?.isNotEmpty ?? false) codec!
  ];
  return parts.isEmpty ? 'Track $id' : parts.join(' • ');
}

class DesktopTrackSheet extends StatefulWidget {
  final bool subtitle;
  final String selected;
  final List<DesktopTrackChoice> tracks;
  final Future<void> Function(String) onSelect;
  final VoidCallback? onExternal;
  const DesktopTrackSheet(
      {super.key,
      required this.subtitle,
      required this.selected,
      required this.tracks,
      required this.onSelect,
      this.onExternal});
  @override
  State<DesktopTrackSheet> createState() => _DesktopTrackSheetState();
}

class _DesktopTrackSheetState extends State<DesktopTrackSheet> {
  bool busy = false;
  String? error;
  Future<void> choose(String id) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSelect(id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not select track. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget row(String id, String name) => ListTile(
      title: Text(name, style: const TextStyle(fontSize: 16)),
      trailing: Icon(
          widget.selected == id
              ? Icons.check_circle_rounded
              : Icons.radio_button_off_rounded,
          color:
              widget.selected == id ? Colors.white : const Color(0xff9296a0)),
      onTap: busy ? null : () => choose(id));
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlaybackSheetHandle(),
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: LText(widget.subtitle ? 'Subtitles' : 'Audio track',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700))),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            if (widget.subtitle) row('no', 'Off'),
            for (final track in widget.tracks) row(track.id, track.label),
            if (widget.tracks.isEmpty)
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Text(
                      widget.subtitle
                          ? 'No embedded subtitle tracks available.'
                          : 'No audio tracks available. Start playback to load tracks.',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13))),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12))),
            if (widget.subtitle) ...[
              const Divider(height: 16, color: Colors.white12),
              ListTile(
                  enabled: !busy && widget.onExternal != null,
                  leading: const Icon(Icons.folder_open_rounded, size: 20),
                  title: const LText('Load subtitle file'),
                  subtitle: const Text(
                      'Choose an external subtitle from your PC',
                      style: TextStyle(fontSize: 12, color: Colors.white54)),
                  onTap: busy ? null : widget.onExternal),
              const Tooltip(
                  message:
                      'On-device AI subtitle generation is not implemented in this Windows build',
                  child: ListTile(
                      enabled: false,
                      leading: Icon(Icons.auto_awesome, size: 20),
                      title: LText('Generate with AI ✨',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      subtitle: Text('Not available on Windows yet',
                          style: TextStyle(fontSize: 12)))),
            ],
          ]));
}
