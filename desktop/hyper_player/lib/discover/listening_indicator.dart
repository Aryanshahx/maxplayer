import 'dart:math' as math;
import 'package:flutter/material.dart';

class ListeningIndicator extends StatefulWidget {
  const ListeningIndicator({super.key});
  @override
  State<ListeningIndicator> createState() => _ListeningIndicatorState();
}

class _ListeningIndicatorState extends State<ListeningIndicator>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();
  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
        animation: motion,
        builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.mic, size: 18),
              const SizedBox(width: 6),
              for (var i = 0; i < 5; i++)
                Container(
                    width: 3,
                    height: reduce
                        ? 12
                        : 6 +
                            14 *
                                (.5 +
                                    .5 *
                                        math.sin(
                                            motion.value * math.pi * 2 + i)),
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(2))),
            ]));
  }
}

Route<T> discoverOpeningRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, animation, secondary) => page,
      transitionsBuilder: (context, animation, secondary, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final eased =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
            opacity: eased,
            child: ScaleTransition(
                scale: Tween<double>(begin: .94, end: 1).animate(eased),
                child: child));
      },
    );
