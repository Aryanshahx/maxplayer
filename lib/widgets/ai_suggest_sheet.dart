import 'dart:convert';
import 'package:flutter/material.dart';

import '../services/ai_suggest.dart';
import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/theme_state.dart';
import 'tmdb_image.dart';

/// v58: the "AI Suggestor" sheet (a real user request: "a button where
/// the user describes their movie type and you suggest the best movies").
///
/// The user types their taste in plain words - or taps a mood chip - the
/// AI names real films, and each pick appears as a tappable TMDB poster.
/// Popping a pick hands it back to Discover, which opens the detail
/// sheet (local library match included).
class AiSuggestSheet extends StatefulWidget {
  const AiSuggestSheet({super.key});

  /// Returns the tapped movie, or null when the sheet was dismissed.
  static Future<TmdbMovie?> show(BuildContext context) {
    return showModalBottomSheet<TmdbMovie>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        // keyboard pushes the sheet up instead of covering the field
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) =>
              SingleChildScrollView(controller: controller, child: const AiSuggestSheet()),
        ),
      ),
    );
  }

  @override
  State<AiSuggestSheet> createState() => _AiSuggestSheetState();
}

class _AiSuggestSheetState extends State<AiSuggestSheet> {
  final _suggestor = AiSuggestor(TmdbClient());
  final _tasteCtrl = TextEditingController();

  bool _busy = false;
  String? _error;
  List<TmdbMovie> _picks = const [];
  int _token = 0;

  static const String _kSavedPromptKey = 'ai_suggest.saved_prompt';
  static const String _kSavedPicksKey = 'ai_suggest.saved_picks_json';

  @override
  void initState() {
    super.initState();
    _restoreSaved();
  }

  Future<void> _restoreSaved() async {
    final s = await NativeBridge.loadSettings();
    final p = s[_kSavedPromptKey];
    final jsonStr = s[_kSavedPicksKey];
    if (p != null && p.isNotEmpty && mounted) {
      _tasteCtrl.text = p;
    }
    if (jsonStr != null && jsonStr.isNotEmpty && mounted) {
      try {
        final list = jsonDecode(jsonStr) as List;
        setState(() {
          _picks = list
              .map((e) => TmdbMovie(
                    id: e['id'] as int,
                    title: '${e['title']}',
                    rating: (e['rating'] as num).toDouble(),
                    year: e['year'] as int?,
                    posterPath: e['posterPath']?.toString(),
                    kind: '${e['kind'] ?? 'movie'}',
                  ))
              .toList();
        });
      } catch (_) {}
    }
  }

  /// One-tap moods - nobody likes typing on a TV remote-style keyboard.
  static const List<String> _moods = [
    'Funny action like Dhoom',
    'Mind-bending thriller',
    'Bollywood romance',
    'K-drama vibes (movies)',
    'Horror night',
    'Feel-good family',
    'South Indian mass action',
    'True story / biopic',
  ];

  @override
  void dispose() {
    _tasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _suggest([String? preset]) async {
    final q = (preset ?? _tasteCtrl.text).trim();
    if (q.isEmpty || _busy) return;
    if (preset != null) _tasteCtrl.text = preset;
    final token = ++_token;
    setState(() {
      _busy = true;
      _error = null;
      _picks = const [];
    });
    final picks = await _suggestor.suggest(q);
    if (!mounted || token != _token) return;
    setState(() {
      _busy = false;
      if (picks == null) {
        _error =
            'AI is not reachable right now - check the internet and try again.';
      } else {
        _picks = picks;
        NativeBridge.saveSetting(_kSavedPromptKey, q);
        final picksJson = jsonEncode(_picks
            .map((m) => {
                  'id': m.id,
                  'title': m.title,
                  'rating': m.rating,
                  'year': m.year,
                  'posterPath': m.posterPath,
                  'kind': m.kind,
                })
            .toList());
        NativeBridge.saveSetting(_kSavedPicksKey, picksJson);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.auto_awesome, color: accent, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'AI Suggestor',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Describe your movie type - AI suggests the best ones for you.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tasteCtrl,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            onSubmitted: (_) => _suggest(),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'e.g. funny action like Dhoom',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.send_rounded, color: accent, size: 20),
                onPressed: _busy ? null : () => _suggest(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _moods)
                GestureDetector(
                  onTap: _busy ? null : () => _suggest(m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(18),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      m,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_busy)
            const _ThinkingAnimation()
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            )
          else if (_picks.isNotEmpty) ...[
            Text(
              '${_picks.length} picks for you',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 225,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _picks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _PickCard(
                  movie: _picks[i],
                  onTap: () => Navigator.of(context).pop(_picks[i]),
                ),
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Tap a mood above or describe your own.',
                  style: TextStyle(color: Colors.white30, fontSize: 12.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  final TmdbMovie movie;
  final VoidCallback onTap;

  const _PickCard({required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 110,
                height: 160,
                child: TmdbImage(url: tmdbPosterUrl(movie.posterPath)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            if (movie.year != null)
              Text(
                '${movie.year}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingAnimation extends StatefulWidget {
  const _ThinkingAnimation();

  @override
  State<_ThinkingAnimation> createState() => _ThinkingAnimationState();
}

class _ThinkingAnimationState extends State<_ThinkingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  'AI is thinking…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i * 0.25;
                    final val = (_ctrl.value - delay) % 1.0;
                    final scale =
                        0.5 + 0.5 * (val < 0.5 ? val * 2 : (1 - val) * 2);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 9,
                      height: 9,
                      transform: Matrix4.diagonal3Values(scale, scale, 1.0),
                      transformAlignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.3 + 0.7 * scale),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
