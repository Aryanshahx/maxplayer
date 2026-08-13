import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';

/// 5-band equalizer backed by libmpv's lavfi `equalizer` filters, applied via
/// NativePlayer.setProperty('af', ...). Changes apply live during playback.
class EqualizerSheet extends StatefulWidget {
  final MediaPlayerState player;

  const EqualizerSheet({super.key, required this.player});

  static const surface = Color(0xFF1a1a24);

  static Future<void> show(BuildContext context, MediaPlayerState player) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EqualizerSheet(player: player),
    );
  }

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  late List<double> _gains;
  late bool _enabled;

  static const _presets = <String, List<double>>{
    'Flat': [0, 0, 0, 0, 0],
    'Bass': [6, 4, 0, -1, -2],
    'Vocal': [-2, 0, 3, 3, 0],
    'Treble': [-2, -1, 0, 4, 6],
    'Rock': [4, 2, -1, 2, 4],
  };

  static const _bandLabels = ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];

  @override
  void initState() {
    super.initState();
    _gains = List.of(widget.player.eqGains);
    _enabled = widget.player.eqEnabled;
  }

  void _apply() {
    widget.player.applyEqualizer(_gains, _enabled);
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: themeState.accent.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Equalizer',
                      style: TextStyle(
                        color: accent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    activeThumbColor: accent,
                    onChanged: (v) {
                      setState(() => _enabled = v);
                      _apply();
                    },
                  ),
                ],
              ),
            ),
            // Preset chips
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final p in _presets.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(p.key),
                        labelStyle: TextStyle(
                            color: themeState.accent.withValues(alpha: 0.75)),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        side: BorderSide.none,
                        onPressed: () {
                          setState(() {
                            _gains = List.of(p.value);
                            _enabled = true;
                          });
                          _apply();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Band sliders
            Opacity(
              opacity: _enabled ? 1 : 0.4,
              child: IgnorePointer(
                ignoring: !_enabled,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < _bandLabels.length; i++)
                      _BandSlider(
                        label: _bandLabels[i],
                        value: _gains[i],
                        accent: accent,
                        onChanged: (v) {
                          setState(() => _gains[i] = v);
                          _apply();
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  final String label;
  final double value; // dB, -12..+12
  final Color accent;
  final ValueChanged<double> onChanged;

  const _BandSlider({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value.toStringAsFixed(0),
            style: TextStyle(
                color: themeState.accent.withValues(alpha: 0.5),
                fontSize: 11)),
        SizedBox(
          height: 140,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: accent,
                thumbColor: accent,
                inactiveTrackColor: accent.withValues(alpha: 0.18),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.clamp(-12.0, 12.0),
                min: -12,
                max: 12,
                divisions: 24,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        Text(label,
            style: TextStyle(
                color: themeState.accent.withValues(alpha: 0.6),
                fontSize: 11)),
      ],
    );
  }
}
