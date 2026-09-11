import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/player_settings.dart';

String _speedLabel(double rate) =>
    '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}x';

/// Full player-behaviour settings page opened by the gear icon in the player.
/// The layout intentionally follows the compact reference: grouped sections,
/// muted descriptions, right-side dropdowns and large Material switches.
class PlayerSettingsScreen extends StatelessWidget {
  const PlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = PlayerSettings.instance;
    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Player settings'),
        leading: const BackButton(),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
          children: [
            const _Section('Gesture controls'),
            _ToggleRow(
              icon: Icons.touch_app_outlined,
              title: 'Double-tap sides to seek',
              subtitle: 'Double-tap left/right edge',
              value: s.doubleTapSides,
              trailing: _ChoiceText(
                text: '${s.seekStep}s',
                onTap: () => _pickSeekStep(context, s),
              ),
              onChanged: s.setDoubleTapSides,
            ),
            _ToggleRow(
              icon: Icons.play_circle_outline_rounded,
              title: 'Double-tap middle to play/pause',
              value: s.doubleTapMiddle,
              onChanged: s.setDoubleTapMiddle,
            ),
            _ToggleRow(
              icon: Icons.volume_up_outlined,
              title: 'Swipe right side for volume',
              value: s.swipeVolume,
              onChanged: s.setSwipeVolume,
            ),
            _ToggleRow(
              icon: Icons.brightness_6_outlined,
              title: 'Swipe left side for brightness',
              value: s.swipeBrightness,
              onChanged: s.setSwipeBrightness,
            ),
            _ToggleRow(
              icon: Icons.swap_horizontal_circle_outlined,
              title: 'Horizontal swipe to seek',
              subtitle: 'Drag sideways anywhere to scrub (±90s per screen)',
              value: s.horizontalSeek,
              onChanged: s.setHorizontalSeek,
            ),
            _ToggleRow(
              icon: Icons.zoom_out_map_outlined,
              title: 'Two-finger pinch to zoom',
              subtitle:
                  'OFF (default): spread 2 fingers = Fit, Crop, Stretch, 16:9… then keep spreading to zoom in. ON: pinch zooms straight away. 2-finger tap = Fit.',
              value: s.pinchZoom,
              onChanged: s.setPinchZoom,
            ),
            _ToggleRow(
              icon: Icons.fast_forward_rounded,
              title: 'Long-press to speed up',
              subtitle: 'Hold finger on the video',
              value: s.longPressSpeed,
              trailing: _ChoiceText(
                text: _speedLabel(s.longPressRate),
                onTap: () => _pickSpeed(context, s),
              ),
              onChanged: s.setLongPressSpeed,
            ),
            const _Section('Playback'),
            _ToggleRow(
              icon: Icons.visibility_off_outlined,
              title: 'Auto-hide controls',
              subtitle: 'Hide during playback after inactivity',
              value: s.autoHide,
              trailing: _ChoiceText(
                text: '${s.autoHideDelay}s',
                onTap: () => _pickAutoHide(context, s),
              ),
              onChanged: s.setAutoHide,
            ),
            _ToggleRow(
              icon: Icons.history_rounded,
              title: 'Resume playback',
              subtitle: 'Continue videos where you left off',
              value: s.resume,
              onChanged: s.setResume,
            ),
            const _Section('Player buttons'),
            _ToggleRow(
              icon: Icons.lock_outline_rounded,
              title: 'Screen lock (kids mode)',
              subtitle: 'Lock button on the video edge locks every touch',
              value: s.screenLock,
              onChanged: s.setScreenLock,
            ),
            const _Section('Sound & subtitles'),
            _ToggleRow(
              icon: Icons.volume_up_rounded,
              title: 'Volume boost up to 200%',
              subtitle: 'ON by default - swipe continues past 100% for quiet videos',
              value: s.volumeBoost,
              onChanged: s.setVolumeBoost,
            ),
            _ToggleRow(
              icon: Icons.headphones_outlined,
              title: 'Background audio playback',
              subtitle: 'Keep playing audio when screen is turned off or app is in background',
              value: s.backgroundAudio,
              onChanged: s.setBackgroundAudio,
            ),
            _ToggleRow(
              icon: Icons.speed_rounded,
              title: 'Performance mode (low-end)',
              subtitle: 'Drops late frames instead of lagging, auto-detects low-RAM phones when left enabled',
              value: s.performanceMode,
              onChanged: s.setPerformanceMode,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSeekStep(BuildContext context, PlayerSettings s) async {
    final value = await _pick<int>(
      context: context,
      title: 'Seek amount',
      values: PlayerSettings.seekSteps,
      selected: s.seekStep,
      label: (v) => '${v}s',
    );
    if (value != null) await s.setSeekStep(value);
  }

  Future<void> _pickSpeed(BuildContext context, PlayerSettings s) async {
    final value = await _pick<double>(
      context: context,
      title: 'Long-press speed',
      values: PlayerSettings.speedRates,
      selected: s.longPressRate,
      label: _speedLabel,
    );
    if (value != null) await s.setLongPressRate(value);
  }

  Future<void> _pickAutoHide(BuildContext context, PlayerSettings s) async {
    final value = await _pick<int>(
      context: context,
      title: 'Auto-hide delay',
      values: PlayerSettings.autoHideSeconds,
      selected: s.autoHideDelay,
      label: (v) => '${v}s',
    );
    if (value != null) await s.setAutoHideDelay(value);
  }

  Future<T?> _pick<T>({
    required BuildContext context,
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T value) label,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            for (final value in values)
              ListTile(
                title: Text(
                  label(value),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                trailing: value == selected
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.of(context).pop(value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ChoiceText extends StatelessWidget {
  const _ChoiceText({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(icon, color: AppColors.textSecondary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (trailing != null) SizedBox(child: trailing),
                    const SizedBox(width: 2),
                    Switch.adaptive(
                      value: value,
                      activeThumbColor: AppColors.accent,
                      activeTrackColor: AppColors.accent.withValues(alpha: 0.45),
                      onChanged: onChanged,
                    ),
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.5,
                        height: 1.25,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
