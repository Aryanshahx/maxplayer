import 'package:flutter/material.dart';

import '../app_info.dart';
import '../state/theme_state.dart';

/// "About Max Player" sheet, opened from the home screen's ⋮ menu.
/// Brand copy by Hyper Tech Labs. Static content - no platform calls.
class AboutSheet extends StatelessWidget {
  final ScrollController? scrollController;

  const AboutSheet({super.key, this.scrollController});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            AboutSheet(scrollController: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        // Grab handle.
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: const BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
        // Brand header.
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.play_circle_fill, color: accent, size: 32),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Max Player',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'by Hyper Tech Labs',
                  style: TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Max Player is a next-generation media player designed to make '
          'watching and listening effortless. Built from the ground up with '
          'performance, simplicity, and reliability in mind, Max Player '
          'brings together powerful playback technology and a clean, '
          'intuitive interface - so you can focus on your content, not on '
          'fighting with your player.\n\n'
          'Whether you\'re binge-watching your favorite series, enjoying '
          'high-definition movies, or listening to music on the go, Max '
          'Player is engineered to handle it all smoothly, without lag, '
          'crashes, or unnecessary clutter.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        _Heading('Our mission', accent),
        const Text(
          'At Max Player, our goal is simple: to create the most seamless, '
          'distraction-free media experience possible. We believe great '
          'software should feel invisible - it should just work, every time, '
          'without getting in your way. That philosophy drives every design '
          'and engineering decision behind Max Player.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        _Heading('Key features', accent),
        for (final f in _features)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 16, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: '${f.$1} - ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: f.$2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        _Heading('Our story', accent),
        const Text(
          'Max Player was created out of a simple frustration: too many '
          'media players were bloated, slow, or filled with intrusive ads '
          'and unnecessary features. We set out to build something '
          'different - a player that respects your time, your device, and '
          'your experience.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        _Heading('The team behind Max Player', accent),
        const Text(
          'Max Player is proudly developed and maintained by Hyper Tech '
          'Labs, a technology company focused on building thoughtful, '
          'high-quality applications for everyday use. Founded by Aryan '
          'Shah, Hyper Tech Labs is driven by a passion for clean design, '
          'efficient engineering, and solving real problems through '
          'software.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        _Heading('Looking ahead', accent),
        const Text(
          'We\'re constantly working to improve Max Player - adding new '
          'features, refining performance, and listening closely to our '
          'users. This is just the beginning, and we\'re excited to keep '
          'building a player that truly puts you first.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        const SizedBox(height: 22),
        const Divider(color: Colors.white12),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Version $kAppVersion',
            style: TextStyle(color: Colors.white38, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  final Color accent;
  const _Heading(this.text, this.accent);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

const List<(String, String)> _features = [
  (
    'Universal Format Support',
    'Play almost any video or audio file without needing extra codecs or '
        'converters.'
  ),
  (
    'Smooth, High-Performance Playback',
    'Optimized for speed and stability, even with large or high-resolution '
        'files.'
  ),
  (
    'Clean, Intuitive Interface',
    'A minimal design that keeps the focus on your content.'
  ),
  (
    'Customizable Controls',
    'Adjust playback speed, subtitles, audio tracks, and more to fit your '
        'preferences.'
  ),
  (
    'Lightweight & Efficient',
    'Built to run smoothly without draining your device\'s resources.'
  ),
  (
    'Regular Updates',
    'Continuously improved based on user feedback and evolving technology.'
  ),
];
