import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../services/native_bridge.dart';
import '../theme.dart';
import '../utils/privacy_policy.dart';

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

  /// v31: reads live native state (notification grant, keep-alive service,
  /// cached engine, continue-watching store) so background-playback and
  /// notification issues can be diagnosed on-device without guesswork.
  static Future<void> _showDiagnostics(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101018),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _DiagnosticsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
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
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Max Player',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'by Hyper Tech Labs',
              style: TextStyle(color: Colors.white54, fontSize: 13),
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
        Center(
          child: TextButton.icon(
            onPressed: () => showPrivacyPolicyDialog(context),
            icon: const Icon(Icons.privacy_tip_outlined, size: 16),
            label: const Text('Privacy policy'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
              textStyle: const TextStyle(fontSize: 12.5),
            ),
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: () => _showDiagnostics(context),
            icon: const Icon(Icons.bug_report_outlined, size: 16),
            label: const Text('System diagnostics'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
              textStyle: const TextStyle(fontSize: 12.5),
            ),
          ),
        ),
        const Center(
          child: Text(
            'Version $kAppVersion',
            style: TextStyle(color: Colors.white38, fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 4),
        // Honest engine note: playback runs on MPV (libmpv + FFmpeg).
        const Center(
          child: Text(
            'Playback engine: MPV (libmpv + FFmpeg)',
            style: TextStyle(color: Colors.white24, fontSize: 11),
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
    'Adjust playback speed (up to 4×), subtitles, audio tracks, and more to '
        'fit your preferences.'
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

/// v31: live native-state readout for background-audio / notification
/// issues. Tap-to-copy so the report can be shared with support.
class _DiagnosticsSheet extends StatefulWidget {
  const _DiagnosticsSheet();

  @override
  State<_DiagnosticsSheet> createState() => _DiagnosticsSheetState();
}

class _DiagnosticsSheetState extends State<_DiagnosticsSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await NativeBridge.diagnostics();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  String _fmt(dynamic v) {
    if (v == null) return '–';
    if (v is bool) return v ? 'YES' : 'NO';
    return v.toString();
  }

  String _report() {
    final b = StringBuffer()..writeln('Max Player $kAppVersion — diagnostics');
    (_data ?? const {}).forEach((k, v) => b.writeln('$k: ${_fmt(v)}'));
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data ?? const <String, dynamic>{};
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: const BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.bug_report_outlined,
                  color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Text(
                'System diagnostics',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loading
                    ? null
                    : () async {
                        await Clipboard.setData(
                            ClipboardData(text: _report()));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Diagnostics copied')),
                          );
                        }
                      },
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Copy'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Reads live on-device state. Share this (Copy → paste) if '
            'background audio or notifications misbehave.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _row('App version', kAppVersion),
                    for (final k in d.keys) _row(k, _fmt(d[k])),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    final interesting = label == 'notificationsGranted' ||
        label == 'serviceRunning' ||
        label == 'engineCached';
    final bad = interesting && value == 'NO';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: bad
                    ? const Color(0xFFFF8A80)
                    : (interesting
                        ? const Color(0xFF7CE7A8)
                        : Colors.white70),
                fontSize: 12.5,
                fontWeight: interesting ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
