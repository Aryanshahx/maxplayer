import 'package:flutter/material.dart';

/// Seamless full-width poster motion, independent of mouse scrolling. Respects
/// reduced-motion and TickerMode. Children are supplied so offline tests need no
/// network and an empty API response never fabricates film posters.
class MovingPosterStrip extends StatefulWidget {
  final List<Widget> posters;
  final double posterWidth;
  const MovingPosterStrip(
      {super.key, required this.posters, this.posterWidth = 100});
  @override
  State<MovingPosterStrip> createState() => _MovingPosterStripState();
}

class _MovingPosterStripState extends State<MovingPosterStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion =
      AnimationController(vsync: this, duration: const Duration(seconds: 45));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      motion.stop();
    } else if (!motion.isAnimating) {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posters.isEmpty) return const SizedBox.shrink();
    final cycle = widget.posters.length * widget.posterWidth;
    return ClipRect(child: LayoutBuilder(builder: (context, size) {
      final copies = (size.maxWidth / cycle).ceil() + 2;
      return AnimatedBuilder(
          animation: motion,
          builder: (_, __) => OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Transform.translate(
                    key: const ValueKey('poster-motion'),
                    offset: Offset(-motion.value * cycle, 0),
                    child: Row(children: [
                      for (var repeat = 0; repeat < copies; repeat++)
                        for (final poster in widget.posters)
                          SizedBox(
                              width: widget.posterWidth,
                              height: size.maxHeight,
                              child: poster)
                    ])),
              ));
    }));
  }
}
