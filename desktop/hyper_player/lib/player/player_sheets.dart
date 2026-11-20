import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../screens/playback_sheets.dart';
import 'fit.dart';
import 'mpv_filters.dart';

class SixModeFitSheet extends StatelessWidget {
  final FitMode selected;
  final ValueChanged<FitMode> onSelect;
  const SixModeFitSheet(
      {super.key, required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlaybackSheetHandle(),
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Video fit',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            for (final mode in FitMode.values)
              ListTile(
                  leading: Icon(mode.icon),
                  title: Text(mode.label),
                  trailing: Icon(mode == selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_off_rounded),
                  onTap: () => onSelect(mode)),
            const SizedBox(height: 18),
          ]);
}

class EqualizerSheet extends StatefulWidget {
  final List<double> initial;
  final bool dialogue;
  final Future<void> Function(List<double>, bool) onApply;
  const EqualizerSheet(
      {super.key,
      required this.initial,
      required this.dialogue,
      required this.onApply});
  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  late List<double> bands;
  late bool dialogue;
  late List<double> applied;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    bands = [...widget.initial];
    applied = [...widget.initial];
    dialogue = widget.dialogue;
  }

  Future<void> apply(List<double> next, bool boost) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onApply(next, boost);
      if (mounted) {
        setState(() {
          bands = [...next];
          applied = [...next];
          dialogue = boost;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          bands = [...applied];
          error = 'Audio filter unavailable. Previous settings kept.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlaybackSheetHandle(),
            const Text('Equalizer & Audio FX',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final preset in equalizerPresets.entries)
                ChoiceChip(
                    label: Text(preset.key),
                    selected: listEquals(bands, preset.value),
                    onSelected:
                        busy ? null : (_) => apply(preset.value, dialogue))
            ]),
            for (var i = 0; i < 5; i++)
              Row(children: [
                SizedBox(
                    width: 56,
                    child: Text(
                        const [
                          '60 Hz',
                          '230 Hz',
                          '910 Hz',
                          '3.6 kHz',
                          '14 kHz'
                        ][i],
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12))),
                Expanded(
                    child: Slider(
                        value: bands[i],
                        min: -12,
                        max: 12,
                        divisions: 24,
                        activeColor: Colors.white,
                        onChanged:
                            busy ? null : (v) => setState(() => bands[i] = v),
                        onChangeEnd:
                            busy ? null : (_) => apply([...bands], dialogue))),
                SizedBox(
                    width: 44,
                    child: Text(
                        '${bands[i] >= 0 ? "+" : ""}${bands[i].round()} dB',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)))
              ]),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dialogue boost',
                    style: TextStyle(fontSize: 15)),
                subtitle: const Text('Lifts quiet speech (1–4 kHz)',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                value: dialogue,
                onChanged: busy ? null : (v) => apply(bands, v)),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            if (error != null)
              Text(error!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ]));
}

class DesktopPlayerSettings extends StatelessWidget {
  final bool autoHide, resume;
  final ValueChanged<bool> onAutoHide, onResume;
  const DesktopPlayerSettings(
      {super.key,
      required this.autoHide,
      required this.resume,
      required this.onAutoHide,
      required this.onResume});
  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlaybackSheetHandle(),
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Player settings',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text('PLAYBACK',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.bold))),
            SwitchListTile(
                title: const Text('Auto-hide controls'),
                subtitle: const Text('Hide after four seconds during playback'),
                value: autoHide,
                onChanged: onAutoHide),
            SwitchListTile(
                title: const Text('Resume playback'),
                subtitle:
                    const Text('Remember position for local files on this PC'),
                value: resume,
                onChanged: onResume),
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text('KEYBOARD & MOUSE',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('User manual · keyboard & mouse'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                        title: Text('Player keyboard & mouse'),
                        content: SingleChildScrollView(
                            child: Text(
                                'Space: play/pause\nLeft / Right: seek 10 seconds\nUp / Down: volume 5%\nM: mute / restore volume\nF: fullscreen\nEscape: unlock player controls\nDouble-click video: fullscreen\nMove mouse: reveal controls\n\nApp shortcuts: Ctrl+O opens files; Ctrl+L opens streams.\n\nShortcuts apply while the player has focus, not while typing in a text field or using a modal.')),
                      )),
            ),
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                    'TOUCHSCREEN: Double-tap left/right: seek 10s; centre: play/pause. Swipe horizontally: seek; swipe vertically on right: volume, left: video-only brightness. Pinch cycles fit once per gesture (not free zoom).',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12.5, height: 1.6))),
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Text(
                    'Space: play/pause · Left/Right: seek 10s\nUp/Down: volume · M: mute · F: fullscreen\nDouble-click: fullscreen · Escape: unlock controls\nMove mouse: show controls',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12.5, height: 1.6))),
          ]);
}
