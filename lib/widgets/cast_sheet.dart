import 'package:flutter/material.dart';

import '../cast/cast_state.dart';
import '../cast/cast_support.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// "Cast to TV" sheet: scans the Wi-Fi for DLNA renderers, connects, and
/// then turns into a little remote (play/pause, seek slider, disconnect).
///
/// Pure UI - all network logic lives in [CastState]. The parent passes
/// [videoPath]/[title]/[subsPath] for the currently loaded video and
/// [onCastStarted]/[onCastStopped] hooks so the local player can pause
/// while the TV plays and resume (at the TV position) afterwards.
class CastSheet extends StatefulWidget {
  final CastState cast;
  final String videoPath;
  final String title;
  final String? subsPath;

  /// Local playback should pause once the TV takes over.
  final VoidCallback onCastStarted;

  /// Casting fully stopped (user pressed "Stop casting"); resume locally
  /// from [CastState.tvPosition].
  final Future<void> Function(Duration tvPosition) onCastStopped;

  const CastSheet({
    super.key,
    required this.cast,
    required this.videoPath,
    required this.title,
    required this.subsPath,
    required this.onCastStarted,
    required this.onCastStopped,
  });

  static Future<void> show(
    BuildContext context,
    CastState cast, {
    required String videoPath,
    required String title,
    String? subsPath,
    required VoidCallback onCastStarted,
    required Future<void> Function(Duration tvPosition) onCastStopped,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CastSheet(
        cast: cast,
        videoPath: videoPath,
        title: title,
        subsPath: subsPath,
        onCastStarted: onCastStarted,
        onCastStopped: onCastStopped,
      ),
    );
  }

  @override
  State<CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<CastSheet> {
  Color get _accent => themeState.accent;

  Future<void> _connect(DlnaDevice d) async {
    await widget.cast.connect(
      d,
      videoPath: widget.videoPath,
      title: widget.title,
      subsPath: widget.subsPath,
    );
    if (widget.cast.phase == CastPhase.casting) {
      widget.onCastStarted();
    }
  }

  Future<void> _stop() async {
    final pos = widget.cast.tvPosition;
    await widget.cast.stopCast();
    await widget.onCastStopped(pos);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: widget.cast,
        builder: (context, _) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 8,
              right: 8,
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
                      color: _accent.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                  child: Row(
                    children: [
                      Icon(Icons.cast_connected, color: _accent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cast to TV',
                          style: TextStyle(
                            color: _accent,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.cast.phase == CastPhase.scanning)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                _body(),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _body() {
    final cast = widget.cast;
    switch (cast.phase) {
      case CastPhase.scanning:
        return _message(
          Icons.wifi_find,
          'Searching for TVs…',
          'Make sure the TV is ON and on the same Wi-Fi as this phone.',
        );

      case CastPhase.connecting:
        return _message(
          Icons.cast_connected,
          'Connecting to ${cast.current?.name ?? 'TV'}…',
          'Handing the video over - this takes a second.',
        );

      case CastPhase.casting:
        return _castingView();

      case CastPhase.error:
        return Column(
          children: [
            _message(Icons.error_outline, 'Connection problem', cast.error),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: cast.scan,
              icon: Icon(Icons.refresh, color: _accent, size: 20),
              label: Text('Scan again',
                  style: TextStyle(color: _accent, fontSize: 15)),
            ),
          ],
        );

      case CastPhase.scanDone:
      case CastPhase.idle:
        if (cast.devices.isEmpty && cast.phase == CastPhase.scanDone) {
          return Column(
            children: [
              _message(
                Icons.tv_off,
                'No TVs found',
                cast.repliesSeen == 0
                    ? 'Nothing on this Wi-Fi answered the search (${cast.repliesSeen} replies). '
                        'Check the phone and TV are on the SAME Wi-Fi (not '
                        'mobile data / guest network), then scan again.'
                    : '${cast.repliesSeen} device(s) answered, but none offer '
                        'DLNA video playback. Many newer Samsung/LG TVs '
                        'dropped DLNA - try opening the video in a DLNA '
                        'renderer app on the TV (e.g. VLC for Android TV) '
                        'and scan again.',
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: widget.cast.scan,
                icon: Icon(Icons.refresh, color: _accent, size: 20),
                label: Text('Scan again',
                    style: TextStyle(color: _accent, fontSize: 15)),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in widget.cast.devices)
              ListTile(
                leading: Icon(Icons.tv,
                    color: themeState.accent.withValues(alpha: 0.75)),
                title: Text(
                  d.name,
                  style: TextStyle(color: themeState.accent, fontSize: 15),
                ),
                subtitle: Text(
                  'Tap to start casting',
                  style: TextStyle(
                      color: themeState.accent.withValues(alpha: 0.5),
                      fontSize: 12),
                ),
                onTap: () => _connect(d),
              ),
            if (widget.cast.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton.icon(
                  onPressed: widget.cast.scan,
                  icon: Icon(Icons.wifi_find, color: _accent, size: 20),
                  label: Text('Search for TVs',
                      style: TextStyle(color: _accent, fontSize: 15)),
                ),
              ),
          ],
        );
    }
  }

  Widget _castingView() {
    final cast = widget.cast;
    final total = cast.tvDuration;
    final pos = cast.tvPosition;
    final max = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
    final value =
        pos.inMilliseconds.clamp(0, total.inMilliseconds).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.connected_tv, color: _accent, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cast.current?.name ?? 'TV',
                      style: TextStyle(
                        color: themeState.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Playing on your TV - this phone is the remote',
                      style: TextStyle(
                          color: themeState.accent.withValues(alpha: 0.5),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                formatDuration(pos),
                style: TextStyle(
                    color: themeState.accent.withValues(alpha: 0.75),
                    fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  max: max,
                  onChanged: (v) {},
                  onChangeEnd: (v) =>
                      cast.seekTo(Duration(milliseconds: v.round())),
                  activeColor: _accent,
                  inactiveColor: _accent.withValues(alpha: 0.18),
                ),
              ),
              Text(
                formatDuration(total),
                style: TextStyle(
                    color: themeState.accent.withValues(alpha: 0.75),
                    fontSize: 12),
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 52,
              icon: Icon(
                cast.tvPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: themeState.accent,
              ),
              onPressed: cast.togglePlayPause,
            ),
          ],
        ),
        TextButton.icon(
          onPressed: _stop,
          icon: const Icon(Icons.cast_connected,
              color: Colors.redAccent, size: 20),
          label: const Text(
            'Stop casting',
            style: TextStyle(color: Colors.redAccent, fontSize: 15),
          ),
        ),
      ],
    );
  }

  Widget _message(IconData icon, String title, [String? body]) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Icon(icon,
              color: themeState.accent.withValues(alpha: 0.5), size: 42),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: themeState.accent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: themeState.accent.withValues(alpha: 0.6),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
