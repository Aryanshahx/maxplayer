import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

abstract interface class MiniWindowPort {
  Future<Rect> bounds();
  Future<bool> maximized();
  Future<bool> fullscreen();
  Future<bool> topmost();
  Future<void> setBounds(Rect value);
  Future<void> setMaximized(bool value);
  Future<void> setFullscreen(bool value);
  Future<void> setTopmost(bool value);
}

class WindowsMiniWindowPort implements MiniWindowPort {
  @override
  Future<Rect> bounds() => windowManager.getBounds();
  @override
  Future<bool> maximized() => windowManager.isMaximized();
  @override
  Future<bool> fullscreen() => windowManager.isFullScreen();
  @override
  Future<bool> topmost() => windowManager.isAlwaysOnTop();
  @override
  Future<void> setBounds(Rect value) => windowManager.setBounds(value);
  @override
  Future<void> setMaximized(bool value) =>
      value ? windowManager.maximize() : windowManager.unmaximize();
  @override
  Future<void> setFullscreen(bool value) => windowManager.setFullScreen(value);
  @override
  Future<void> setTopmost(bool value) => windowManager.setAlwaysOnTop(value);
}

/// Windows always-on-top mini-window, not an Android PiP API or a new decoder.
/// Existing playback stays in the same player. Original native window state is
/// retained until restoration succeeds, allowing a failed restore to be retried.
class MiniPlayerWindow {
  final MiniWindowPort port;
  MiniPlayerWindow(this.port);
  ({Rect bounds, bool maximized, bool fullscreen, bool topmost})? saved;
  bool busy = false;
  bool get active => saved != null;
  Future<void> enter() async {
    if (busy || active) return;
    busy = true;
    try {
      final snapshot = (
        bounds: await port.bounds(),
        maximized: await port.maximized(),
        fullscreen: await port.fullscreen(),
        topmost: await port.topmost()
      );
      saved = snapshot;
      try {
        if (snapshot.fullscreen) await port.setFullscreen(false);
        if (snapshot.maximized) await port.setMaximized(false);
        await port.setBounds(
            Rect.fromLTWH(snapshot.bounds.left, snapshot.bounds.top, 480, 320));
        await port.setTopmost(true);
      } catch (_) {
        try {
          await restore();
        } catch (_) {/* State kept for retry. */}
        rethrow;
      }
    } finally {
      busy = false;
    }
  }

  Future<void> restore() async {
    final snapshot = saved;
    if (snapshot == null) return;
    await port.setFullscreen(false);
    await port.setMaximized(false);
    await port.setTopmost(snapshot.topmost);
    await port.setBounds(snapshot.bounds);
    if (snapshot.maximized) await port.setMaximized(true);
    if (snapshot.fullscreen) await port.setFullscreen(true);
    saved = null;
  }
}

class MiniPlayerControls extends StatelessWidget {
  final String title;
  final bool playing;
  final VoidCallback onPlayPause, onRestore;
  const MiniPlayerControls(
      {super.key,
      required this.title,
      required this.playing,
      required this.onPlayPause,
      required this.onRestore});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
            color: Colors.black87,
            child: Row(children: [
              IconButton(
                  tooltip: playing ? 'Pause' : 'Play',
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: onPlayPause),
              Expanded(
                  child: Text(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(
                  tooltip: 'Return to full player',
                  icon: const Icon(Icons.open_in_full),
                  onPressed: onRestore),
            ])),
      );
}
