import '../utils/app_language.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/iptv_parser.dart';
import '../theme.dart';
import '../services/app_analytics.dart';
import 'player_screen.dart';

/// v1.0.1+62: LIVE TV — the iptv-org free-to-air channel collection,
/// parsed from .m3u, cached 12h, searchable, group-filtered, logos in a
/// fast grid. Tap a channel -> the existing stream player plays it.
class IptvScreen extends StatefulWidget {
  const IptvScreen({super.key});

  @override
  State<IptvScreen> createState() => _IptvScreenState();
}

class _IptvScreenState extends State<IptvScreen> {
  static const _kCacheKey = 'iptv.cache.list';
  static const _kCacheTimeKey = 'iptv.cache.time';

  List<IptvChannel> _all = [];
  List<IptvChannel> _shown = [];
  List<String> _groups = const ['ALL'];
  String _group = 'ALL';
  String _query = '';
  bool _india = true;
  bool _loading = true;
  String _status = 'Loading channels…';

  @override
  void initState() {
    super.initState();
    // v1.0.1+63: anonymous activity counter (screen opened).
    AppAnalytics.instance.bumpDaily(iptvOpened: 1);
    AppAnalytics.instance.log('iptv_open');
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _status = 'Loading channels…';
    });
    final url = _india ? kIptvIndiaUrl : kIptvWorldUrl;
    final cacheKey = '$_kCacheKey.$url';
    final timeKey = '$_kCacheTimeKey.$url';
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      final fetchedAt = prefs.getInt(timeKey) ?? 0;
      final fresh =
          DateTime.now().millisecondsSinceEpoch - fetchedAt <
          const Duration(hours: 12).inMilliseconds;
      String text;
      if (cached != null && fresh && cached.isNotEmpty) {
        text = cached;
      } else {
        _status = 'Downloading live channel list…';
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 25));
        if (resp.statusCode != 200) {
          throw HttpException('HTTP ${resp.statusCode}');
        }
        text = resp.body;
        unawaited(prefs.setString(cacheKey, text));
        unawaited(prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch));
      }
      final channels = parseIptvM3u(text);
      if (!mounted) return;
      setState(() {
        _all = channels;
        _groups = [
          'ALL',
          ...{
            for (final c in channels)
              if (c.group.isNotEmpty) c.group,
          },
        ];
        _loading = false;
        _applyFilters();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Could not load channels ($e). Tap to retry.';
      });
    }
  }

  void _applyFilters() {
    Iterable<IptvChannel> it = _all;
    if (_group != 'ALL') it = it.where((c) => c.group == _group);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      it = it.where((c) => c.name.toLowerCase().contains(q));
    }
    _shown = it.take(400).toList(growable: false); // sane cap for free tiles
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final accent = AppColors.accent;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const LText(
          'LIVE TV',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () {
                setState(() => _india = !_india);
                unawaited(_load());
              },
              icon: Icon(
                _india ? Icons.flag_rounded : Icons.public_rounded,
                color: accent,
                size: 18,
              ),
              label: Text(
                _india ? 'INDIA' : 'WORLD',
                style: TextStyle(color: accent, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => setState(() {
                _query = v;
                _applyFilters();
              }),
              decoration: LInputDecoration(
                hintText: 'Search channels…',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // group chips
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final g in _groups.take(24))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(g),
                      selected: _group == g,
                      onSelected: (_) => setState(() {
                        _group = g;
                        _applyFilters();
                      }),
                      selectedColor: AppColors.accent,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      labelStyle: TextStyle(
                        color: _group == g
                            ? AppColors.onAccent
                            : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: accent),
                        const SizedBox(height: 12),
                        Text(
                          _status,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  )
                : _all.isEmpty
                ? Center(
                    child: GestureDetector(
                      onTap: () => unawaited(_load()),
                      child: Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          MediaQuery.sizeOf(context).shortestSide > 600 ? 5 : 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.25,
                    ),
                    itemCount: _shown.length,
                    itemBuilder: (context, i) => _ChannelTile(_shown[i]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: LText(
              'Free & legal streams collected by the iptv-org open project',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile(this.channel);

  final IptvChannel channel;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final accent = AppColors.accent;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        focusColor: accent.withValues(alpha: 0.30),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen.stream(
              path: channel.url,
              title: channel.name,
              isLiveTv: true,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: 0.05),
          ),
          child: Column(
            children: [
              Expanded(
                child: channel.logo.isNotEmpty
                    ? Image.network(
                        channel.logo,
                        fit: BoxFit.contain,
                        errorBuilder: (_, e, s) => _letter(),
                        loadingBuilder: (c, child, p) =>
                            p == null ? child : _letter(loading: true),
                      )
                    : _letter(),
              ),
              const SizedBox(height: 6),
              Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, color: Colors.white70),
              ),
              if (channel.quality.isNotEmpty)
                Text(
                  channel.quality,
                  style: TextStyle(
                    fontSize: 8,
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _letter({bool loading = false}) {
    return Center(
      child: Text(
        loading
            ? '…'
            : (channel.name.isEmpty ? '?' : channel.name.characters.first),
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: AppColors.accent.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
