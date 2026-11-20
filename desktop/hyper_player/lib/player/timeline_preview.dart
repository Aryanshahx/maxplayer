import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'android_controls.dart' show playbackClock;

typedef PreviewLoader = Future<Uint8List?> Function(Duration position);

/// Debounced, bounded-memory hover UI. A source change/exit invalidates late
/// responses. Loading/unavailable states never substitute an unrelated frame.
class HoverTimeline extends StatefulWidget {
  final Widget child;
  final String sourceKey;
  final Duration duration;
  final PreviewLoader? loader;
  const HoverTimeline(
      {super.key,
      required this.child,
      required this.sourceKey,
      required this.duration,
      this.loader});
  @override
  State<HoverTimeline> createState() => _HoverTimelineState();
}

class _HoverTimelineState extends State<HoverTimeline> {
  Timer? debounce;
  int epoch = 0;
  Duration? target;
  Uint8List? image;
  bool loading = false;
  double x = 0;
  void clear() {
    debounce?.cancel();
    epoch++;
    target = null;
    image = null;
    loading = false;
  }

  @override
  void didUpdateWidget(covariant HoverTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.duration != widget.duration) {
      clear();
    }
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }

  void hover(double dx, double width) {
    if (widget.duration <= Duration.zero) return;
    final fraction =
        ((dx - 24) / (width - 48).clamp(1, double.infinity)).clamp(0.0, 1.0);
    final next = Duration(
        milliseconds:
            ((widget.duration.inMilliseconds * fraction / 1000).floor() * 1000)
                .clamp(0, widget.duration.inMilliseconds));
    x = dx;
    if (target == next) {
      setState(() {});
      return;
    }
    debounce?.cancel();
    final request = ++epoch;
    setState(() {
      target = next;
      image = null;
      loading = widget.loader != null;
    });
    if (widget.loader == null) return;
    debounce = Timer(const Duration(milliseconds: 220), () async {
      Uint8List? result;
      try {
        result = await widget.loader!(next);
      } catch (_) {/* Honest fallback. */}
      if (!mounted || request != epoch) return;
      setState(() {
        image =
            result != null && result.length <= 4 * 1024 * 1024 ? result : null;
        loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, box) => MouseRegion(
            onHover: (event) => hover(event.localPosition.dx, box.maxWidth),
            onExit: (_) => setState(clear),
            child: Stack(clipBehavior: Clip.none, children: [
              widget.child,
              if (target != null)
                Positioned(
                  bottom: 42,
                  left: (x - 92).clamp(
                      0.0, (box.maxWidth - 184).clamp(0.0, double.infinity)),
                  child: IgnorePointer(
                      child: Container(
                    width: 184,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: Colors.black87,
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(8)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (image != null)
                        Image.memory(image!,
                            width: 172,
                            height: 97,
                            fit: BoxFit.contain,
                            gaplessPlayback: false,
                            errorBuilder: (_, error, stack) =>
                                const Text('Preview unavailable'))
                      else
                        SizedBox(
                            height: 60,
                            child: Center(
                                child: Text(
                                    loading
                                        ? 'Loading preview…'
                                        : 'Preview unavailable',
                                    style: const TextStyle(fontSize: 11)))),
                      Text(playbackClock(target!),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white)),
                    ]),
                  )),
                ),
            ]),
          ));
}
