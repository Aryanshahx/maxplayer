import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_language.dart';
import 'playback_sheets.dart';

class VideoFitSheet extends StatelessWidget {
  final BoxFit selected;
  final ValueChanged<BoxFit> onSelect;
  const VideoFitSheet(
      {super.key, required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlaybackSheetHandle(),
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: LText('Video fit',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            for (final mode in const [
              (
                BoxFit.contain,
                'Fit',
                'Show the full picture with black bars if needed',
                Icons.fit_screen_rounded
              ),
              (
                BoxFit.cover,
                'Crop',
                'Fill the window; edges may be cropped',
                Icons.crop_rounded
              ),
              (
                BoxFit.fill,
                'Stretch',
                'Fill the window without preserving proportions',
                Icons.aspect_ratio_rounded
              )
            ])
              ListTile(
                  leading: Icon(mode.$4, size: 22),
                  title: LText(mode.$2, style: const TextStyle(fontSize: 16)),
                  subtitle: Text(mode.$3,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: Icon(
                      selected == mode.$1
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_off_rounded,
                      color: selected == mode.$1
                          ? Colors.white
                          : const Color(0xff9296a0)),
                  onTap: () => onSelect(mode.$1)),
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Text(
                    '16:9, 4:3 and Original frame modes are not implemented in this Windows build.',
                    style: TextStyle(color: Colors.white38, fontSize: 11.5))),
          ]);
}

class SubtitleDelaySheet extends StatefulWidget {
  final Future<void> Function(int) onApply;
  const SubtitleDelaySheet({super.key, required this.onApply});
  @override
  State<SubtitleDelaySheet> createState() => _SubtitleDelaySheetState();
}

class _SubtitleDelaySheetState extends State<SubtitleDelaySheet> {
  final input = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void step(int delta) {
    final value = int.tryParse(input.text) ?? 0;
    setState(() {
      input.text = (value + delta).clamp(-60000, 60000).toString();
      error = null;
    });
  }

  Future<void> apply() async {
    final ms = int.tryParse(input.text.trim());
    if (ms == null || ms.abs() > 60000) {
      setState(() => error = 'Enter a whole number between -60000 and 60000.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onApply(ms);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Subtitle delay unavailable. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlaybackSheetHandle(),
            const LText('Subtitle delay',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text(
                'Positive values show subtitles later; negative values show them earlier. Enter 0 to reset.',
                style: TextStyle(
                    color: Colors.white54, fontSize: 12.5, height: 1.5)),
            const SizedBox(height: 14),
            TextField(
                controller: input,
                enabled: !busy,
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[-0-9]'))
                ],
                decoration: InputDecoration(
                    labelText: 'Delay in milliseconds',
                    hintText: 'Example: 500 or -500',
                    errorText: error,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .06),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                onSubmitted: busy ? null : (_) => apply()),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                  label: const Text('−100 ms'),
                  onPressed: busy ? null : () => step(-100)),
              ActionChip(
                  label: const Text('+100 ms'),
                  onPressed: busy ? null : () => step(100)),
              ActionChip(
                  label: const LText('Reset'),
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            input.text = '0';
                            error = null;
                          }))
            ]),
            const SizedBox(height: 14),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: busy ? null : apply,
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    child: const LText('Apply'))),
            if (busy) const LinearProgressIndicator(minHeight: 2),
          ]));
}
