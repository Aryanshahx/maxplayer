/// Cinematic Discover UI set (v1.0.1+38) — ported to Flutter/Dart from a
/// React/Framer-Motion/Tailwind reference. Four pieces:
///  1. [CineBoot] — full-screen projector boot/loading curtain.
///  2. [CineFeaturedHero] — auto-rotating immersive featured hero.
///  3. [CineTicker] — tilted infinite neon marquee strip.
///  4. [CineTopTen] — horizontal TOP 10 rail with ghost rank numerals.
/// Pure helpers (`cineBootEase`, `cineBootWord`, …) are pinned by tests.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/tmdb.dart';
import '../utils/tmdb_image.dart';

// ---------------------------------------------------------------- tokens ---

const kCineInk = Color(0xFF050506);
const kCineBg = Color(0xFF060607);
const kCineCyan = Color(0xFF22D3EE);
const kCinePurple = Color(0xFFA855F7);
const kCinePink = Color(0xFFEC4899);
const kCineAmber = Color(0xFFF59E0B);

/// Anton display face (bundled in assets/fonts/Anton-Regular.ttf).
const kCineDisplay = 'Anton';

/// Space Mono mono face (bundled in assets/fonts/SpaceMono-Regular.ttf).
const kCineMono = 'SpaceMono';

TextStyle cineMono(
  double size,
  Color color, {
  double letterSpacing = 1.0,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: kCineMono,
  fontSize: size,
  color: color,
  letterSpacing: letterSpacing,
  fontWeight: weight,
);

TextStyle cineDisplay(double size, Color color, {double height = 1.0}) =>
    TextStyle(
      fontFamily: kCineDisplay,
      fontSize: size,
      color: color,
      height: height,
    );

// --------------------------------------------------------- pure helpers ---

/// Neon ticker items (exact copy from the reference design).
const kCineTickerItems = <String>[
  'MOVIES',
  'WEB SERIES',
  'DRAMA',
  'ANIME',
  '4K QUALITY',
  'TV SERIES',
  'NO SIGN UP',
];

/// Gate angles/durations (tunable without touching widget code).
const kCineHeroDuration = Duration(milliseconds: 7000);
const kCineHeroCrossfade = Duration(milliseconds: 1400);
const kCineBootDuration = Duration(milliseconds: 1000);
const kCineBootExit = Duration(milliseconds: 350);
const kCineTickerPeriod = Duration(seconds: 28);
const kCineTickerTiltDeg = -1.2;

/// Non-linear projector ramp for the boot percentage (pure).
///
/// Fast launch, two brief STUTTER plateaus in the middle (like a real
/// projector gaining speed), then a snap to 1.0 in the final stretch.
/// Monotonic non-decreasing; f(0)=0, f(1)=1, and plateaus are exact.
double cineBootEase(double t) {
  final x = t.clamp(0.0, 1.0);
  const knots = <(double, double)>[
    (0.00, 0.00),
    (0.16, 0.30),
    (0.32, 0.30), // stutter 1 (plateau)
    (0.55, 0.52),
    (0.62, 0.52), // stutter 2 (plateau)
    (0.78, 0.66),
    (0.90, 0.80),
    (1.00, 1.00),
  ];
  for (var i = 1; i < knots.length; i++) {
    final (t0, v0) = knots[i - 1];
    final (t1, v1) = knots[i];
    if (x <= t1) {
      final span = t1 - t0;
      final f = span <= 0 ? 1.0 : (x - t0) / span;
      if (i == knots.length - 1) {
        // final stretch: ease-out cubic snap.
        final eased = 1 - math.pow(1 - f, 3).toDouble();
        return v0 + (v1 - v0) * eased;
      }
      return v0 + (v1 - v0) * f;
    }
  }
  return 1.0;
}

/// Next hero index, wrapping (pure; empty list always yields 0).
int cineHeroNext(int current, int length) =>
    length <= 0 ? 0 : (current + 1) % length;

/// Kind chip label: movie -> FILM, anything else -> SERIES (pure).
String cineKindLabel(String kind) => kind == 'movie' ? 'MOVIE' : 'SERIES';

// ================================================================== BOOT ==

/// Full-screen cinematic boot curtain. Plays the ramp once, slides itself
/// up like a raised cinema curtain, then calls [onFinished].
/// Full-screen cinematic boot curtain (MINIMAL per field feedback:
/// no flicker, no decorative texts) — just the giant Anton percentage
/// over pure black with the glowing hairline, then the curtain-lift
/// exit. Plays once per Discover open.
class CineBoot extends StatefulWidget {
  const CineBoot({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<CineBoot> createState() => _CineBootState();
}

class _CineBootState extends State<CineBoot> with TickerProviderStateMixin {
  late final AnimationController _run =
      AnimationController(vsync: this, duration: kCineBootDuration)
        ..addStatusListener((st) {
          if (st == AnimationStatus.completed) {
            Future<void>.delayed(const Duration(milliseconds: 60), () {
              if (mounted) _exit.forward();
            });
          }
        });
  late final AnimationController _exit =
      AnimationController(vsync: this, duration: kCineBootExit)
        ..addStatusListener((st) {
          if (st == AnimationStatus.completed) widget.onFinished();
        });

  @override
  void initState() {
    super.initState();
    _run.forward();
  }

  @override
  void dispose() {
    _run.dispose();
    _exit.dispose();
    super.dispose();
  }

  Widget _cornerTick(bool top, bool left) {
    final c = Colors.white.withValues(alpha: 0.55);
    final hBar = Container(color: c, width: 26, height: 1);
    final vBar = Container(color: c, width: 1, height: 26);
    return Positioned(
      top: top ? 18 : null,
      bottom: top ? null : 21,
      left: left ? 18 : null,
      right: left ? null : 18,
      child: Row(
        crossAxisAlignment: top
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: (left ? [hBar, vBar] : [vBar, hBar]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exitCurve = CurvedAnimation(
      parent: _exit,
      curve: const Cubic(0.76, 0.0, 0.24, 1.0),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final counterSize = (w * 0.22).clamp(96.0, 240.0);
        return AnimatedBuilder(
          animation: _exit,
          builder: (context, _) {
            return Transform.translate(
              offset: Offset(0, -h * exitCurve.value),
              child: Container(
                width: w,
                height: h,
                color: kCineBg,
                child: Stack(
                  children: [
                    // v1.0.1+40: the thin white corner hairlines are back
                    // (pure line ticks, no text labels).
                    _cornerTick(true, true),
                    _cornerTick(true, false),
                    _cornerTick(false, true),
                    _cornerTick(false, false),
                    // giant counter, bottom-right
                    Positioned(
                      right: 18,
                      bottom: 22,
                      child: AnimatedBuilder(
                        animation: _run,
                        builder: (context, _) {
                          final p = cineBootEase(_run.value);
                          return RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${(p * 100).floor()}',
                                  style: cineDisplay(counterSize, Colors.white),
                                ),
                                TextSpan(
                                  text: '%',
                                  style: cineDisplay(
                                    counterSize * 0.45,
                                    kCinePurple.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // glowing hairline progress bar
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedBuilder(
                        animation: _run,
                        builder: (context, _) {
                          final p = cineBootEase(_run.value);
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: p,
                              child: Container(
                                height: 2,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [kCineCyan, kCinePurple, kCinePink],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x80A855F7),
                                      blurRadius: 15,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ================================================================== HERO ==

/// Immersive auto-rotating featured hero: crossfaded backdrops with a Ken
/// Burns push-in, staggered content entrance and realtime countdown pills
/// at the bottom. Tapping the ART opens the detail page ([onOpen]); the
/// PLAY NOW button starts playback ([onTap]).
class CineFeaturedHero extends StatefulWidget {
  const CineFeaturedHero({
    super.key,
    required this.items,
    required this.onTap,
    required this.onOpen,
  });

  final List<TmdbMovie> items;
  final void Function(TmdbMovie) onTap;
  final void Function(TmdbMovie) onOpen;

  @override
  State<CineFeaturedHero> createState() => _CineFeaturedHeroState();
}

class _CineFeaturedHeroState extends State<CineFeaturedHero>
    with TickerProviderStateMixin {
  int _index = 0;
  Timer? _timer;
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: kCineHeroDuration,
  );
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant CineFeaturedHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    // v1.0.1+39: re-arm ONLY when the item set actually changed. Parent
    // setStates (search bar slide, rail fills) must NEVER restart the
    // Ken Burns / entrance animations — that was the "touches restart
    // the hero" bug.
    if (!_sameMovieSet(oldWidget.items, widget.items)) {
      _index = 0;
      _arm();
      return;
    }
    if (_index >= widget.items.length) setState(() => _index = 0);
  }

  static bool _sameMovieSet(List<TmdbMovie> a, List<TmdbMovie> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _arm() {
    _slide
      ..stop()
      ..reset()
      ..forward();
    _enter
      ..stop()
      ..reset()
      ..forward();
    _timer?.cancel();
    if (widget.items.length > 1) {
      _timer = Timer(
        kCineHeroDuration,
        () => _goTo(cineHeroNext(_index, widget.items.length)),
      );
    }
  }

  void _goTo(int i) {
    if (i == _index || widget.items.isEmpty) return;
    setState(() => _index = i);
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slide.dispose();
    _enter.dispose();
    super.dispose();
  }

  Widget _staggered(int i, Widget child) {
    final begin = (i * 0.09).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _enter,
      curve: Interval(
        begin,
        (begin + 0.4).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 50 * (1 - anim.value)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final mq = MediaQuery.of(context);
    // v1.0.1+42/+45: ~60% viewport hero (the +43 split layout and the
    // +44 art-shift are REVERTED).
    final h = (mq.size.height * 0.60).clamp(400.0, mq.size.height);
    if (items.isEmpty) return const SizedBox.shrink();
    // v1.0.1+45 tablet/landscape guard: on short viewports the bottom
    // copy column was taller than the space left for it, so the title
    // escaped UP into the search bar (and compressed the strip below).
    // Compact mode: smaller title cap, overview dropped.
    final compact = h < 560;
    final m = items[_index.clamp(0, items.length - 1)];
    final backdrop = tmdbBackdropUrl(m.backdropPath);

    return SizedBox(
      height: h,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // backdrop: crossfade + Ken Burns — the whole art is tappable
          // (v1.0.1+39: "make each slider clickable").
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onOpen(m),
            child: AnimatedSwitcher(
              duration: kCineHeroCrossfade,
              child: KeyedSubtree(
                key: ValueKey('hero_${m.id}'),
                child: AnimatedBuilder(
                  animation: _slide,
                  builder: (context, _) {
                    final scale = 1.15 - 0.15 * _slide.value;
                    return Transform.scale(
                      scale: scale,
                      child: backdrop.isEmpty
                          ? const ColoredBox(color: kCineInk)
                          : TmdbImage(url: backdrop, fit: BoxFit.cover),
                    );
                  },
                ),
              ),
            ),
          ),
          // three gradient veils
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kCineInk, Colors.transparent],
                stops: [0.0, 1.0],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Color(0x80050506), Colors.transparent],
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 160,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [kCineInk, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          // content texts — NON-INTERACTIVE: taps fall through to the
          // tap layer below (moved up by the button row's height).
          Positioned(
            left: 20,
            right: 96,
            bottom: 152,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _staggered(
                  1,
                  Text(
                    m.title.toUpperCase(),
                    style: _titleStyle(context, compact),
                  ),
                ),
                const SizedBox(height: 10),
                _staggered(2, _metaRow(m)),
                if (!compact && m.overview.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _staggered(
                    3,
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 390),
                      child: Text(
                        m.overview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // v1.0.1+41: full-bleed tap layer ABOVE the texts/veils and
          // BELOW the buttons + pills — a tap anywhere on the artwork or
          // copy opens the detail page, guaranteed.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => widget.onOpen(m),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(left: 20, bottom: 80, child: _staggered(4, _buttonRow(m))),
          // bottom countdown pills
          if (items.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [for (var i = 0; i < items.length; i++) _pill(i)],
              ),
            ),
        ],
      ),
    );
  }

  TextStyle _titleStyle(BuildContext context, bool compact) {
    final w = MediaQuery.of(context).size.width;
    // v1.0.1+45: capped at 92 (was 128 — the giant tablet titles that
    // overlapped the strip + search bar), 64 in compact/landscape hero.
    final size = (w * 0.09).clamp(44.0, compact ? 64.0 : 92.0);
    return cineDisplay(size, Colors.white).copyWith(
      shadows: const [Shadow(color: Color(0xB3000000), blurRadius: 60)],
    );
  }

  Widget _metaRow(TmdbMovie m) {
    TextStyle st() =>
        cineMono(10, Colors.white.withValues(alpha: 0.5), letterSpacing: 1.5);
    Widget sep() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text('|', style: st()),
    );
    Widget dot() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text('·', style: st()),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.calendar_today_outlined,
          size: 11,
          color: Colors.white.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text('${m.year ?? '—'}', style: st()),
        sep(),
        Icon(
          Icons.movie_outlined,
          size: 11,
          color: Colors.white.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(cineKindLabel(m.kind), style: st()),
        if (m.rating > 0) ...[
          sep(),
          const Icon(Icons.star_rounded, size: 11, color: kCineAmber),
          dot(),
          Text(tmdbRatingText(m.rating), style: st()),
        ],
      ],
    );
  }

  Widget _buttonRow(TmdbMovie m) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => widget.onTap(m),
            child: const SizedBox(
              height: 54,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'PLAY NOW',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(int i) {
    final active = i == _index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: () => _goTo(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: active ? 48 : 16,
          height: 4,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: active
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.2),
          ),
          child: active
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedBuilder(
                    animation: _slide,
                    builder: (context, _) => FractionallySizedBox(
                      widthFactor: _slide.value,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: const LinearGradient(
                            colors: [kCineCyan, kCinePurple, kCinePink],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

// ================================================================ TICKER ==

/// Infinite neon marquee — tilted -1.2°, scaled 1.02 to bleed past the
/// viewport edges. Loop is seamless: the row is duplicated back-to-back
/// and translated exactly one half.
class CineTicker extends StatefulWidget {
  const CineTicker({super.key});

  @override
  State<CineTicker> createState() => _CineTickerState();
}

class _CineTickerState extends State<CineTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: kCineTickerPeriod,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<Widget> _row() => [
    for (final item in kCineTickerItems) ...[
      Padding(
        padding: const EdgeInsets.only(left: 26),
        child: Text(item, style: cineDisplay(22, Colors.white)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(
          Icons.auto_awesome,
          size: 12,
          color: Colors.white.withValues(alpha: 0.6),
        ),
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final strip = Container(
      height: 54,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF9333EA), kCineCyan, kCinePink],
        ),
      ),
      child: ClipRect(
        child: OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          alignment: Alignment.centerLeft,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(-0.5, 0),
            ).animate(_c),
            child: IntrinsicWidth(child: Row(children: [..._row(), ..._row()])),
          ),
        ),
      ),
    );
    return Transform.rotate(
      angle: kCineTickerTiltDeg * math.pi / 180,
      child: Transform.scale(scale: 1.02, child: strip),
    );
  }
}

// ============================================================== TOP TEN ==

/// Horizontal TOP 10 chart rail: giant ghost rank numerals behind each
/// poster, hover lift + cyan stroke on the numeral, frosted overlay with
/// play affordance on hover/press.
class CineTopTen extends StatefulWidget {
  const CineTopTen({super.key, required this.items, required this.onTap});

  final List<TmdbMovie> items;
  final void Function(TmdbMovie) onTap;

  @override
  State<CineTopTen> createState() => _CineTopTenState();
}

class _CineTopTenState extends State<CineTopTen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  static double _posterW(double w) => w >= 1024
      ? 150.0
      : w >= 600
      ? 130.0
      : 110.0;

  static double _ghostSize(double w) => (w * 0.12).clamp(104.0, 192.0);

  /// Rail height = tallest of (poster, ghost numeral) + lift allowance.
  static double _railHeight(double w) =>
      math.max(_posterW(w) * 1.5, _ghostSize(w) * 0.95) + 14;

  @override
  Widget build(BuildContext context) {
    final items = widget.items.take(10).toList();
    if (items.length < 6) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.trending_up,
                  size: 12,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'TRENDING NOW',
                style: cineMono(
                  10,
                  kCineAmber.withValues(alpha: 0.8),
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Text('TOP 10 THIS WEEK', style: cineDisplay(28, Colors.white)),
        ),
        SizedBox(
          // v1.0.1+39: rail height is COMPUTED from the poster size (was
          // a fixed 244 -> a dead black gap under the heading on phones).
          height: _railHeight(MediaQuery.of(context).size.width),
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.035, 0.965, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _TopTenCard(
                rank: i + 1,
                movie: items[i],
                onTap: () => widget.onTap(items[i]),
                posterW: _posterW(MediaQuery.of(context).size.width),
                enterAnim: CurvedAnimation(
                  parent: _enter,
                  curve: Interval(
                    (i * 0.04).clamp(0.0, 0.6),
                    ((i * 0.04) + 0.4).clamp(0.0, 1.0),
                    curve: Curves.easeOut,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopTenCard extends StatefulWidget {
  const _TopTenCard({
    required this.rank,
    required this.movie,
    required this.onTap,
    required this.posterW,
    required this.enterAnim,
  });

  final int rank;
  final TmdbMovie movie;
  final VoidCallback onTap;
  final double posterW;
  final Animation<double> enterAnim;

  @override
  State<_TopTenCard> createState() => _TopTenCardState();
}

class _TopTenCardState extends State<_TopTenCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final posterW = widget.posterW;
    final ghostSize = _CineTopTenState._ghostSize(
      MediaQuery.of(context).size.width,
    );
    final rankPad = widget.rank >= 10 ? ghostSize * 0.62 : ghostSize * 0.34;

    return AnimatedBuilder(
      animation: widget.enterAnim,
      builder: (context, _) {
        final v = widget.enterAnim.value;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 44 * (1 - v)),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                onTap: widget.onTap,
                onTapDown: (_) => setState(() => _hover = true),
                onTapUp: (_) => setState(() => _hover = false),
                onTapCancel: () => setState(() => _hover = false),
                child: SizedBox(
                  width: posterW + rankPad,
                  height:
                      _CineTopTenState._railHeight(
                        MediaQuery.of(context).size.width,
                      ) -
                      14,
                  child: Stack(
                    alignment: Alignment.bottomLeft,
                    children: [
                      // ghost rank numeral
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: TweenAnimationBuilder<Color?>(
                          tween: ColorTween(
                            end: _hover
                                ? kCineCyan.withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.06),
                          ),
                          duration: const Duration(milliseconds: 500),
                          builder: (context, color, _) => Text(
                            '${widget.rank}',
                            style: TextStyle(
                              fontFamily: kCineDisplay,
                              fontSize: ghostSize,
                              height: 0.95,
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = 1.5
                                ..color = color ?? Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                      // poster
                      Positioned(
                        left: rankPad,
                        bottom: 0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          transform: Matrix4.translationValues(
                            0,
                            _hover ? -8 : 0,
                            0,
                          ),
                          width: posterW,
                          height: posterW * 1.5,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _hover
                                  ? kCinePurple.withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.06),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _hover
                                    ? kCinePurple.withValues(alpha: 0.25)
                                    : Colors.black.withValues(alpha: 0.4),
                                blurRadius: _hover ? 22 : 12,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                () {
                                  final url = tmdbPosterUrl(
                                    widget.movie.posterPath,
                                    big: true,
                                  );
                                  return url.isEmpty
                                      ? const ColoredBox(
                                          color: Color(0xFF17171d),
                                        )
                                      : TmdbImage(url: url, fit: BoxFit.cover);
                                }(),
                                // hover overlay
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 220),
                                  opacity: _hover ? 1 : 0,
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.2,
                                            ),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.5,
                                              ),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.play_arrow_rounded,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                          child: Text(
                                            widget.movie.title.toUpperCase(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: cineMono(
                                              8,
                                              Colors.white,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                        ),
                                        if (widget.movie.rating > 0) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.star_rounded,
                                                size: 10,
                                                color: kCineAmber,
                                              ),
                                              Text(
                                                tmdbRatingText(
                                                  widget.movie.rating,
                                                ),
                                                style: cineMono(
                                                  8,
                                                  Colors.white70,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
