import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../utils/ai.dart';
import '../utils/crash_log.dart';
import '../utils/tmdb.dart';

/// Full movie page matching the reference: poster + meta card,
/// Ask AI + Trailer actions, backdrops strip, deep facts table,
/// storyline + director, top cast with photos, user reviews.
class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, required this.movieId});

  final int movieId;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  TmdbMovieDetail? _detail;
  String _director = '';
  List<TmdbCastEntry> _cast = [];
  List<TmdbReviewEntry> _reviews = [];
  List<String> _backdrops = [];
  String? _trailerKey;
  bool _failed = false;
  bool _launchingTrailer = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.movieId;
    final d = await fetchMovieDetail(id);
    if (!mounted) return;
    if (d == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _detail = d);
    // secondary loads complete independently (each fails silently)
    final creds = await fetchCredits(id);
    if (mounted) {
      setState(() {
        _director = creds.director;
        _cast = creds.cast;
      });
    }
    final rev = await fetchReviews(id);
    if (mounted) setState(() => _reviews = rev);
    final bd = await fetchBackdrops(id);
    if (mounted) setState(() => _backdrops = bd);
    final key = await fetchTrailerKey(id);
    if (mounted) setState(() => _trailerKey = key);
  }

  Future<void> _openTrailer() async {
    final key = _trailerKey;
    if (key == null) {
      _toast('No trailer available for this title');
      return;
    }
    setState(() => _launchingTrailer = true);
    CrashLog.crumb('trailer.open', {'id': widget.movieId});
    final uri = Uri.parse('https://www.youtube.com/watch?v=$key');
    try {
      final ok = await launchUrl(uri,
          mode: LaunchMode.externalApplication);
      if (!ok) _toast('Could not open YouTube');
    } catch (_) {
      _toast('Could not open YouTube');
    }
    if (mounted) setState(() => _launchingTrailer = false);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtMoney(int v) {
    if (v <= 0) return '—';
    final s = '$v';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\$$b';
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _failed
          ? const Center(
              child: Text('Could not load this title right now.',
                  style: TextStyle(color: AppColors.textSecondary)))
          : d == null
              ? Center(
                  child: CircularProgressIndicator(
                      color: AppColors.accent))
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () =>
                            Navigator.of(context).maybePop(),
                      ),
                      backgroundColor: AppColors.background,
                      floating: true,
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            _header(d),
                            const SizedBox(height: 14),
                            _actionRow(d),
                            const SizedBox(height: 14),
                            if (_backdrops.isNotEmpty) _backdropStrip(),
                            const SizedBox(height: 18),
                            _facts(d),
                            const SizedBox(height: 14),
                            if (d.tagline.isNotEmpty)
                              Text('“${d.tagline}”',
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 15,
                                      fontStyle: FontStyle.italic)),
                            const SizedBox(height: 8),
                            if (d.runtimeLabel.isNotEmpty)
                              Text(
                                  '${d.runtimeLabel}'
                                  '${d.votes > 0 ? '  ·  ${_fmtVotes(d.votes)} votes' : ''}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13)),
                            const SizedBox(height: 12),
                            if (d.genres.isNotEmpty) _genreRow(d),
                            const SizedBox(height: 20),
                            _storyline(d),
                            if (_cast.isNotEmpty) _castSection(),
                            if (_reviews.isNotEmpty) _reviewsSection(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _fmtVotes(int v) {
    final s = '$v';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  Widget _header(TmdbMovieDetail d) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 108,
              height: 162,
              child: d.posterUrl.isEmpty
                  ? Container(color: AppColors.surfaceAlt)
                  : Image.network(d.posterUrl, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.15)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text('MOVIE',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8)),
                    ),
                    const SizedBox(width: 10),
                    Text(d.year.isEmpty ? '—' : d.year,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFFACC15), size: 18),
                    const SizedBox(width: 2),
                    Text('${d.rating.toStringAsFixed(1)} / 10',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Rating & data via TMDB',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      );

  Widget _actionRow(TmdbMovieDetail d) => Row(
        children: [
          Expanded(
            child: _BigAction(
              icon: Icons.auto_awesome_rounded,
              label: 'Ask AI',
              filled: false,
              onTap: () => _showAskAi(d),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _BigAction(
              icon: _launchingTrailer
                  ? Icons.hourglass_top_rounded
                  : Icons.play_circle_outline_rounded,
              label: 'Trailer',
              filled: true,
              onTap: _openTrailer,
            ),
          ),
        ],
      );

  Widget _backdropStrip() => SizedBox(
        height: 108,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _backdrops.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(_backdrops[i],
                height: 108, fit: BoxFit.cover),
          ),
        ),
      );

  Widget _facts(TmdbMovieDetail d) {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: Text(k,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.5)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(v.isEmpty ? '—' : v,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        height: 1.45)),
              ),
            ],
          ),
        );
    return Column(
      children: [
        row('Release', d.releaseDate.isEmpty ? '—' : d.releaseDate),
        row('Original',
            d.originalTitle.isEmpty ? d.title : d.originalTitle),
        row('Budget', _fmtMoney(d.budget)),
        row('Revenue', _fmtMoney(d.revenue)),
        row('Studio', d.studios),
        row('Country', d.countries),
        row('Languages', d.languages),
      ],
    );
  }

  Widget _genreRow(TmdbMovieDetail d) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final g in d.genres)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(g.name,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 12.5)),
            ),
        ],
      );

  Widget _storyline(TmdbMovieDetail d) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Storyline',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(d.overview.isEmpty ? 'No synopsis available.' : d.overview,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.55)),
          if (_director.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Director: $_director',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ],
        ],
      );

  Widget _castSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          const Text('Top Cast',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _cast.length,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (context, i) {
                final c = _cast[i];
                return SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.surfaceAlt,
                        backgroundImage: c.photoUrl.isEmpty
                            ? null
                            : NetworkImage(c.photoUrl),
                        child: c.photoUrl.isEmpty
                            ? Text(
                                c.name.isNotEmpty ? c.name[0] : '?',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18))
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                      Text(c.character,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );

  Widget _reviewsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          Text('User Reviews  (${_reviews.length})',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final r in _reviews)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.surfaceAlt,
                          child: Text(
                              r.author.isNotEmpty ? r.author[0] : '?',
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(r.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (r.ratingText.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius:
                                  BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded,
                                    color: Color(0xFFFACC15),
                                    size: 12),
                                const SizedBox(width: 2),
                                Text(
                                    r.ratingText
                                        .replaceAll(' / 10', ''),
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(r.content,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                            height: 1.5)),
                  ],
                ),
              ),
            ),
        ],
      );

  // ---------------- Ask AI bottom sheet ----------------

  void _showAskAi(TmdbMovieDetail d) {
    CrashLog.crumb('ask_ai.open', {'id': d.id});
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _AskAiSheet(detail: d),
    );
  }
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.textPrimary : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: filled ? null : Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 19,
                  color: filled
                      ? const Color(0xFF0B0B0E)
                      : AppColors.textPrimary),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: filled
                          ? const Color(0xFF0B0B0E)
                          : AppColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AskAiSheet extends StatefulWidget {
  const _AskAiSheet({required this.detail});

  final TmdbMovieDetail detail;

  @override
  State<_AskAiSheet> createState() => _AskAiSheetState();
}

class _AskAiSheetState extends State<_AskAiSheet> {
  final _ctrl = TextEditingController(
      text: 'Is this movie worth watching, and why?');
  String? _answer;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _answer = null;
    });
    final res = await askMovieAi(
      systemPrompt: buildMovieSystemPrompt(
        title: widget.detail.title,
        year: widget.detail.year,
        rating: widget.detail.rating,
        overview: widget.detail.overview,
      ),
      question: q,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.error == 'config:no-key') {
        _error = 'AI key not set yet.\n'
            'Add OPENROUTER_API_KEY in GitHub → repo Settings → Secrets → '
            'Actions, rebuild once — then Ask AI works everywhere.';
      } else if (res.error.isNotEmpty) {
        _error = res.error;
      } else {
        _answer = res.text;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              const Text('Ask AI',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            minLines: 2,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Ask anything about ${widget.detail.title}...',
              hintStyle:
                  const TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_busy)
            Center(
                child: Padding(
              padding: const EdgeInsets.all(8),
              child: CircularProgressIndicator(color: AppColors.accent),
            ))
          else if (_error != null)
            Text(_error!,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5))
          else if (_answer != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(_answer!,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      height: 1.5)),
            ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _busy ? null : _ask,
            child: const Text('Ask'),
          ),
        ],
      ),
    );
  }
}
