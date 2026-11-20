import '../player/fit.dart';
import '../utils/app_language.dart';
import 'package:flutter/material.dart';

import '../utils/player_settings.dart';

/// "Player settings" sheet - customize every gesture and playback behavior,
/// ported 1:1 from the old MaxPlayer sheet (sections: Gesture controls,
/// Playback, Player buttons, Sound & subtitles). Changes save immediately
/// and are picked up by the open player.
class PlayerSettingsSheet extends StatefulWidget {
  const PlayerSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PlayerSettingsSheet(),
    );
  }

  @override
  State<PlayerSettingsSheet> createState() => _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends State<PlayerSettingsSheet> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = PlayerSettings.instance;
    await s.load();
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final s = PlayerSettings.instance;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: LText(
                  'Player settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (s.saveError != null)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(s.saveError!,
                        style: const TextStyle(color: Colors.orange))),
              ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('User manual · keyboard & mouse'),
                  onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => const AlertDialog(
                          title: Text('Player keyboard & mouse'),
                          content: SingleChildScrollView(
                              child: Text(
                                  'Space: play/pause\nLeft / Right: seek configured step\nUp / Down or mouse wheel: volume\nM: mute\nB: brightness and volume sliders\n[ / ]: video brightness\nZ: cycle video fit\nI / O: zoom\nShift+arrows: pan while zoomed\nHold R: temporary speed boost\nH: show/hide controls\nL: lock controls\nF: fullscreen\nEscape: unlock\nDouble-click sides: seek; centre: play/pause. Use F for fullscreen\nCtrl+O: open files\nCtrl+L: open streams\n\nShortcuts require player focus; not active while typing in a dialog.'))))),
              if (!_loaded)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              else ...[
                const _SectionHeader('Gesture controls'),
                _SwitchTile(
                  icon: Icons.touch_app_outlined,
                  label: 'Double-tap sides to seek',
                  subtitle:
                      'Touch or mouse, windowed/fullscreen. Keyboard: Left / Right',
                  value: s.doubleTapSides,
                  onChanged: s.setDoubleTapSides,
                  trailing: s.doubleTapSides
                      ? _MiniDropdown<int>(
                          value: s.seekStep,
                          entries: const {
                            5: '5s',
                            10: '10s',
                            15: '15s',
                            30: '30s',
                          },
                          onChanged: (v) => s.setSeekStep(v ?? 10),
                        )
                      : null,
                ),
                _SwitchTile(
                  icon: Icons.play_circle_outline,
                  label: 'Double-tap middle to play/pause',
                  subtitle: 'Keyboard: Space. Fullscreen is F, not double-tap.',
                  value: s.doubleTapMiddle,
                  onChanged: s.setDoubleTapMiddle,
                ),
                _SwitchTile(
                  icon: Icons.brightness_6_outlined,
                  label: 'Swipe left side for brightness',
                  subtitle:
                      'Drag up/down on left. Keys [ darker / ] brighter; B opens sliders. Video brightness only.',
                  value: s.swipeBrightness,
                  onChanged: s.setSwipeBrightness,
                ),
                _SwitchTile(
                  icon: Icons.volume_up_outlined,
                  label: 'Swipe right side for volume',
                  subtitle:
                      'Up/Down keys or wheel. In-app volume; boost allows up to 200%',
                  value: s.swipeVolume,
                  onChanged: s.setSwipeVolume,
                ),
                _SwitchTile(
                  icon: Icons.swap_horizontal_circle_outlined,
                  label: 'Horizontal swipe to seek',
                  subtitle: 'Drag sideways anywhere to scrub (±90s per screen)',
                  value: s.horizontalSeek,
                  onChanged: s.setHorizontalSeek,
                ),
                _SwitchTile(
                  icon: Icons.pinch_outlined,
                  label: 'Two-finger pinch to zoom',
                  subtitle:
                      'Keyboard: Z fit; I zoom in / O out; Shift+arrows pan. OFF (default): spread 2 fingers = Fit, Crop, '
                      'Stretch, 16:9... then keep spreading to zoom in. '
                      'ON: pinch zooms straight away. 2-finger tap = Fit.',
                  value: s.pinchZoom,
                  onChanged: s.setPinchZoom,
                ),
                _SwitchTile(
                  icon: Icons.fast_forward,
                  label: 'Long-press to speed up',
                  subtitle: 'Hold finger on the video',
                  value: s.longPressSpeed,
                  onChanged: s.setLongPressSpeed,
                  trailing: s.longPressSpeed
                      ? _MiniDropdown<double>(
                          value: s.longPressRate,
                          entries: {
                            1.5: '1.5x',
                            2.0: '2x',
                            2.5: '2.5x',
                            3.0: '3x',
                          },
                          onChanged: (v) => s.setLongPressRate(v ?? 2.0),
                        )
                      : null,
                ),
                const _SectionHeader('Sound'),
                _BoostToggleTile(s: s),
                const _SectionHeader('Playback'),
                ListTile(
                    leading: const Icon(Icons.aspect_ratio),
                    title: const Text('Default fit mode'),
                    trailing: DropdownButton<int>(
                        value: s.defaultFit,
                        items: [
                          for (final fit in FitMode.values)
                            DropdownMenuItem(
                                value: fit.index, child: Text(fit.label))
                        ],
                        onChanged: (value) {
                          if (value != null) s.setDefaultFit(value);
                        })),
                _SwitchTile(
                  icon: Icons.timer_off_outlined,
                  label: 'Auto-hide controls',
                  subtitle: 'Hide during playback after inactivity',
                  value: s.autoHide,
                  onChanged: s.setAutoHide,
                  trailing: s.autoHide
                      ? _MiniDropdown<int>(
                          value: s.autoHideDelay,
                          entries: const {3: '3s', 4: '4s', 5: '5s', 6: '6s'},
                          onChanged: (v) => s.setAutoHideDelay(v ?? 4),
                        )
                      : null,
                ),
                _SwitchTile(
                  icon: Icons.history,
                  label: 'Resume playback',
                  subtitle: 'Continue videos where you left off',
                  value: s.resume,
                  onChanged: s.setResume,
                ),
                const _SectionHeader('Player buttons'),
                _SwitchTile(
                  icon: Icons.lock_outline,
                  label: 'Screen lock (kids mode)',
                  subtitle: 'Lock button on the video edge locks every touch',
                  value: s.screenLock,
                  onChanged: s.setScreenLock,
                ),
                const _SectionHeader('Performance'),
                _SwitchTile(
                  icon: Icons.speed_outlined,
                  label: 'Performance mode (low-end)',
                  subtitle: 'Drops late frames instead of lagging; '
                      'Windows MPV late-frame dropping; Auto uses normal defaults',
                  value: s.performanceMode != 'off',
                  onChanged: (v) => s.setPerformanceMode(v ? 'on' : 'off'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? trailing;

  const _SwitchTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          Switch.adaptive(
            value: value,
            activeThumbColor: Colors.white,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// v1.0.11 boost toggle (default ON): lets the in-app volume scale run
/// past 100% up to 200% like VLC. OFF caps everything at 100%.
class _BoostToggleTile extends StatelessWidget {
  final PlayerSettings s;
  const _BoostToggleTile({required this.s});
  @override
  Widget build(BuildContext context) => _SwitchTile(
      icon: Icons.volume_up_outlined,
      label: 'Volume boost (up to 200%)',
      subtitle:
          'In-app amplification; may distort audio. Lower volume before enabling.',
      value: s.volumeBoost,
      onChanged: s.setVolumeBoost);
}

class _MiniDropdown<T> extends StatelessWidget {
  final T value;
  final Map<T, String> entries;
  final ValueChanged<T?> onChanged;

  const _MiniDropdown({
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DropdownButton<T>(
      value: value,
      dropdownColor: const Color(0xFF26262f),
      underline: const SizedBox.shrink(),
      isDense: true,
      style: const TextStyle(color: Colors.white70, fontSize: 13),
      items: [
        for (final e in entries.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: onChanged,
    );
  }
}
