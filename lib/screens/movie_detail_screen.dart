import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../utils/tmdb.dart';
import '../widgets/movie_detail_sheet.dart';

/// Full-screen movie detail page — OTT apps open a dedicated page when a
/// banner/poster is tapped instead of a bottom sheet.
///
/// v1.0.1+16: no AppBar band and no drag-handle "notch" at the top any
/// more — the page is edge-to-edge under a transparent status bar with a
/// floating circular back button (always visible; it never scrolls away).
class MovieDetailScreen extends StatelessWidget {
  final TmdbMovie movie;
  final AssetEntity? localMatch;
  final Future<TmdbFull?> Function() detailLoader;

  const MovieDetailScreen({
    super.key,
    required this.movie,
    required this.localMatch,
    required this.detailLoader,
  });

  static Future<void> open(
    BuildContext context, {
    required TmdbMovie movie,
    required AssetEntity? localMatch,
    required Future<TmdbFull?> Function() detailLoader,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(
          movie: movie,
          localMatch: localMatch,
          detailLoader: detailLoader,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF14141c),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF14141c),
        body: Stack(
          children: [
            // Edge-to-edge scrollable content; top padding clears the
            // floating back button area.
            Positioned.fill(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(top: topPad + 56),
                child: MovieDetailSheet(
                  movie: movie,
                  localMatch: localMatch,
                  hostContext: context,
                  detailLoader: detailLoader,
                  showHandle: false,
                ),
              ),
            ),
            // Floating back button — pinned, never disappears on scroll.
            Positioned(
              top: topPad + 10,
              left: 12,
              child: _CircleIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

