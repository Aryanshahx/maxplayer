import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/onboarding.dart';
import '../widgets/gesture_illustrations.dart';

/// First-run onboarding: three pages shown one-by-one (Welcome → How to
/// use → Video player guide). Pushed automatically the first time the app
/// opens.
///
/// "Done / Skip" stores the [Onboarding] flag so the automatic trigger
/// never fires again.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _page = PageController();
  int _index = 0;
  static const int _count = 3;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _finish() {
    Onboarding.markSeen();
    Navigator.of(context).pop();
  }

  void _next() {
    if (_index == _count - 1) {
      _finish();
      return;
    }
    _page.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: const [
                  _WelcomePage(),
                  _HowToPage(),
                  _PlayerGuidePage(),
                ],
              ),
            ),
            _OnboardingBar(
              index: _index,
              count: _count,
              onSkip: _finish,
              onNext: _next,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom bar: Skip · dots · Next / Get started.
// ---------------------------------------------------------------------------

class _OnboardingBar extends StatelessWidget {
  final int index;
  final int count;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  const _OnboardingBar({
    required this.index,
    required this.count,
    required this.onSkip,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Row(
        children: [
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
              minimumSize: const Size(64, 44),
            ),
            child: const Text('Skip', style: TextStyle(fontSize: 14)),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: 7),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: i == index ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == index ? accent : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ],
            ),
          ),
          FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: AppColors.onAccent,
              minimumSize: const Size(118, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              index == count - 1 ? 'Get started' : 'Next',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 1 — Welcome.
// ---------------------------------------------------------------------------

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      children: [
        // Brand mark — the real Max Player app icon (bundled asset).
        Center(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/icon.png',
                width: 104,
                height: 104,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFA78BFA),
                        Color(0xFF8B5CF6),
                        Color(0xFF22D3EE),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 60, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        Center(
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF22D3EE)],
            ).createShader(bounds),
            child: const Text(
              'Max Player',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            'Proudly Developed in India 🇮🇳',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'One player for every video on your phone.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15.5),
          ),
        ),
        const SizedBox(height: 26),
        _FeatureRow(
          icon: Icons.movie_outlined,
          title: 'Plays every format',
          subtitle: 'MP4, MKV, AVI, WebM, FLV, IPTV streams and more.',
        ),
        _FeatureRow(
          icon: Icons.lyrics_outlined,
          title: 'Karaoke & AI subtitles',
          subtitle: 'Word-by-word lyrics overlay and on-device whisper captions.',
        ),
        _FeatureRow(
          icon: Icons.psychology_outlined,
          title: 'Discover & Ask AI',
          subtitle: 'Trending movies from TMDB, with an AI assistant that works offline too.',
        ),
        _FeatureRow(
          icon: Icons.lock_outline_rounded,
          title: 'Private Space',
          subtitle: 'Keep personal videos in a PIN-protected folder.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 2 — How to use.
// ---------------------------------------------------------------------------

class _HowToPage extends StatelessWidget {
  const _HowToPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      children: [
        const Text(
          'How to use',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Get to know your video library.',
          style: TextStyle(color: Colors.white54, fontSize: 13.5),
        ),
        const SizedBox(height: 20),
        _FeatureRow(
          icon: Icons.sync,
          title: 'Rescan',
          subtitle:
              'New videos do not appear by themselves — tap ⟳ in the top bar (or pull the list down) to re-scan the device.',
        ),
        _FeatureRow(
          icon: Icons.search,
          title: 'Search',
          subtitle: 'Find any file from the top bar — the list filters as you type.',
        ),
        _FeatureRow(
          icon: Icons.favorite_border,
          title: 'Favourites',
          subtitle:
              'Tap the ♥ on a video, then ⋮ → Display settings → "Show only favourites".',
        ),
        _FeatureRow(
          icon: Icons.tune_rounded,
          title: 'Display settings',
          subtitle: '⋮ → sort, group, list/grid view and accent colour.',
        ),
        _FeatureRow(
          icon: Icons.movie_outlined,
          title: 'Discover',
          subtitle: 'Trending movies & series, plus Ask AI to find what to watch.',
        ),
        _FeatureRow(
          icon: Icons.history,
          title: 'History & resume',
          subtitle: 'Every video reopens exactly where you stopped watching.',
        ),
        _FeatureRow(
          icon: Icons.playlist_play,
          title: 'Playlists',
          subtitle:
              'Build your own lists of videos — only the playlists you create appear here.',
        ),
        _FeatureRow(
          icon: Icons.cloud_outlined,
          title: 'Cloud storage',
          subtitle:
              'Open videos straight from Google Drive & other providers, then save them to your device.',
        ),
        _FeatureRow(
          icon: Icons.lan_outlined,
          title: 'Network streams',
          subtitle:
              'Play HTTP / HLS / IPTV streams and M3U playlists with Open Stream.',
        ),
        _FeatureRow(
          icon: Icons.lock_outline_rounded,
          title: 'Private Space',
          subtitle: 'Hide personal videos behind a PIN or fingerprint.',
        ),
        _FeatureRow(
          icon: Icons.picture_in_picture_alt_outlined,
          title: 'Background audio & PiP',
          subtitle:
              'Keep listening in the background or shrink the player into a floating picture-in-picture window.',
        ),
        _FeatureRow(
          icon: Icons.subtitles_outlined,
          title: 'Subtitles & karaoke',
          subtitle:
              'Sidecar .srt subtitles, word-by-word karaoke overlay, and offline AI captions.',
        ),
        _FeatureRow(
          icon: Icons.notifications_outlined,
          title: 'Continue-watching alerts',
          subtitle:
              'Leave a video halfway? A notification reminds you where you stopped.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 3 — Video player guide.
// ---------------------------------------------------------------------------

class _PlayerGuidePage extends StatelessWidget {
  const _PlayerGuidePage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      children: const [
        Text(
          'Video player',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Tap, swipe and pinch — every gesture works in full-screen too.',
          style: TextStyle(color: Colors.white54, fontSize: 13.5),
        ),
        SizedBox(height: 18),
        _GestureRow(
          kind: GestureKind.singleTap,
          title: 'Single tap',
          subtitle: 'Show / hide the controls.',
        ),
        _GestureRow(
          kind: GestureKind.doubleTapSides,
          title: 'Double-tap the sides',
          subtitle: 'Jump back / forward 10 seconds.',
        ),
        _GestureRow(
          kind: GestureKind.doubleTapMiddle,
          title: 'Double-tap the centre',
          subtitle: 'Play / pause.',
        ),
        _GestureRow(
          kind: GestureKind.swipeBrightness,
          title: 'Swipe the left half',
          subtitle: 'Up = brighter, down = dimmer.',
        ),
        _GestureRow(
          kind: GestureKind.swipeVolume,
          title: 'Swipe the right half',
          subtitle: 'Up = louder, down = quieter (all the way down mutes).',
        ),
        _GestureRow(
          kind: GestureKind.swipeSeek,
          title: 'Swipe sideways',
          subtitle: 'Scrub through the video.',
        ),
        _GestureRow(
          kind: GestureKind.pinchZoom,
          title: 'Pinch with two fingers',
          subtitle: 'Zoom in up to 4×.',
        ),
        _GestureRow(
          kind: GestureKind.holdSpeed,
          title: 'Hold anywhere',
          subtitle: 'Temporary speed boost while you hold.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared rows.
// ---------------------------------------------------------------------------

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
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

class _GestureRow extends StatelessWidget {
  final GestureKind kind;
  final String title;
  final String subtitle;

  const _GestureRow({
    required this.kind,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureIllustration(kind: kind, height: 58),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
